using Singularity.Apps.Database;

int checks = 0;
int server_checks = 0;
bool in_server = false;
string? auth_paths = null;

void ok (bool cond, string what) {
    checks++;
    if (in_server) server_checks++;
    if (!cond) {
        stderr.printf ("FAIL: %s\n", what);
        Process.exit (1);
    }
}

void eq (string got, string want, string what) {
    checks++;
    if (in_server) server_checks++;
    if (got != want) {
        stderr.printf ("FAIL: %s\n  got:  %s\n  want: %s\n", what, got, want);
        Process.exit (1);
    }
}

string hex (uint8[] b) {
    var sb = new StringBuilder ();
    foreach (uint8 x in b) sb.append ("%02x".printf (x));
    return sb.str;
}

uint8[] unhex (string s) {
    uint8[] out_b = new uint8[s.length / 2];
    for (int i = 0; i < out_b.length; i++) out_b[i] = (uint8) uint64.parse ("0x" + s.substring (i * 2, 2));
    return out_b;
}

void test_framing () {
    uint8 seq = 0;
    uint8[] f = MyCodec.frame ({ 1, 2, 3 }, ref seq);
    eq (hex (f), "03000000010203", "small frame");
    ok (seq == 1, "seq advanced");

    uint8[] big = new uint8[MyCodec.MAX_PAYLOAD + 10];
    for (int i = 0; i < big.length; i++) big[i] = (uint8) (i % 251);
    seq = 5;
    uint8[] fb = MyCodec.frame (big, ref seq);
    ok (fb.length == big.length + 8, "split frame length");
    ok (fb[0] == 0xff && fb[1] == 0xff && fb[2] == 0xff && fb[3] == 5, "first split header");
    int second = 4 + MyCodec.MAX_PAYLOAD;
    ok (fb[second] == 10 && fb[second + 1] == 0 && fb[second + 3] == 6, "second split header");
    ok (seq == 7, "seq after split");

    uint8[] exact = new uint8[MyCodec.MAX_PAYLOAD];
    seq = 0;
    uint8[] fe = MyCodec.frame (exact, ref seq);
    ok (fe.length == exact.length + 8, "exact max payload gets empty trailer");
    ok (fe[fe.length - 4] == 0 && fe[fe.length - 1] == 1, "empty trailer header");

    try {
        var ba = new ByteArray ();
        ba.append (fb);
        ba.append (f);
        ba.append (fe);
        uint8[] partial = { 9, 0, 0, 0, 1 };
        ba.append (partial);
        int consumed;
        var packets = MyCodec.deframe (ba.data, out consumed);
        ok (packets.size == 3, "deframe count");
        ok (packets[0].get_size () == big.length, "deframe joined split");
        ok (packets[0].get_data ()[MyCodec.MAX_PAYLOAD + 3] == (uint8) ((MyCodec.MAX_PAYLOAD + 3) % 251), "deframe content");
        ok (packets[1].get_size () == 3, "deframe small");
        ok (packets[2].get_size () == MyCodec.MAX_PAYLOAD, "deframe exact");
        ok (consumed == ba.len - 5, "deframe leaves partial");
    } catch (Error e) {
        ok (false, "deframe: " + e.message);
    }
}

void test_lenenc () {
    uint64[] values = { 0, 250, 251, 65535, 65536, 16777215, 16777216, (uint64) 1 << 40, uint64.MAX };
    string[] encodings = { "00", "fa", "fcfb00", "fcffff", "fd000001", "fdffffff", "fe0000000100000000", "fe0000000000010000", "feffffffffffffffff" };
    for (int i = 0; i < values.length; i++) {
        var w = new MyWriter ();
        w.lenenc_int (values[i]);
        uint8[] b = w.take ();
        eq (hex (b), encodings[i], "lenenc encode %s".printf (values[i].to_string ()));
        try {
            var r = new MyReader (b);
            ok (r.lenenc_int () == values[i] && r.at_end (), "lenenc decode %s".printf (values[i].to_string ()));
        } catch (Error e) {
            ok (false, e.message);
        }
    }
    try {
        var r = new MyReader ({ 0xfb, 3, 'a', 'b', 'c' });
        ok (r.lenenc_bytes () == null, "lenenc null");
        eq (r.lenenc_str (), "abc", "lenenc string");
        var t = new MyReader ({ 0xfc, 1 });
        bool thrown = false;
        try {
            t.lenenc_int ();
        } catch (RemoteError e) {
            thrown = true;
        }
        ok (thrown, "truncated lenenc throws");
    } catch (Error e) {
        ok (false, e.message);
    }
}

void test_scrambles () {
    uint8[] nonce = new uint8[20];
    for (int i = 0; i < 20; i++) nonce[i] = (uint8) (i + 1);
    eq (hex (MyCodec.native_scramble ("secret", nonce)), "b32bb3a583e1340c0a1108d58b1be49781ad8c2f", "native scramble vector");
    eq (hex (MyCodec.sha2_scramble ("secret", nonce)), "746ebe205d56a0707acb3e796e834e0dd7b1d61743b26bd5202c7a623230c7c9", "sha2 scramble vector");
    ok (MyCodec.native_scramble ("", nonce).length == 0, "empty native");
    ok (MyCodec.sha2_scramble ("", nonce).length == 0, "empty sha2");
    uint8[] x = MyCodec.xor_password ("ab", { 1, 2 });
    eq (hex (x), "606001", "xor password");
}

void test_bignum () {
    var b = MyBigNum.from_bytes ({ 4 }, 3);
    var e = MyBigNum.from_bytes ({ 13 }, 3);
    var m = MyBigNum.from_bytes ({ 0x01, 0xf1 }, 3);
    eq (hex (MyBigNum.modpow (b, e, m).to_bytes (2)), "01bd", "4^13 mod 497");
    var b2 = MyBigNum.from_bytes (unhex ("0123456789abcdef0123"), 5);
    var e2 = MyBigNum.from_bytes (unhex ("010001"), 5);
    var m2 = MyBigNum.from_bytes (unhex ("fedcba9876543210fedcba98765431"), 5);
    var r2 = MyBigNum.modpow (b2, e2, m2).to_bytes (15);
    eq (hex (r2), "00c6d0e060f87212d1216354076d9863".substring (2), "multi limb modpow");
}

string? run (string[] argv, out string output) {
    output = "";
    try {
        string err;
        int status;
        Process.spawn_sync (null, argv, null, SpawnFlags.SEARCH_PATH, null, out output, out err, out status);
        if (status != 0) return err;
        return null;
    } catch (Error e) {
        return e.message;
    }
}

void test_rsa () {
    string dir = Environment.get_tmp_dir ();
    string key = Path.build_filename (dir, "sdb-rsa-key.pem");
    string pub = Path.build_filename (dir, "sdb-rsa-pub.pem");
    string enc = Path.build_filename (dir, "sdb-rsa-enc.bin");
    string outp;
    if (run ({ "timeout", "30", "openssl", "genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:2048", "-out", key }, out outp) != null) {
        stderr.printf ("skip: openssl genpkey failed\n");
        return;
    }
    run ({ "timeout", "30", "openssl", "pkey", "-in", key, "-pubout", "-out", pub }, out outp);
    try {
        string pem;
        FileUtils.get_contents (pub, out pem);
        uint8[] n, e;
        MyRsa.parse_public_key (pem, out n, out e);
        ok (n.length == 256, "modulus length");
        eq (hex (e), "010001", "exponent");
        uint8[] msg = MyCodec.xor_password ("hunter2 secret", { 7, 8, 9 });
        uint8[] c = MyRsa.encrypt_oaep (pem, msg);
        ok (c.length == 256, "ciphertext length");
        FileUtils.set_data (enc, c);
        string plain;
        string? err = run ({ "timeout", "30", "openssl", "pkeyutl", "-decrypt", "-inkey", key, "-in", enc, "-pkeyopt", "rsa_padding_mode:oaep" }, out plain);
        ok (err == null, "openssl oaep decrypt: " + (err ?? ""));
        uint8[] got = plain.data;
        eq (hex (got), hex (msg), "oaep round trip");
        run ({ "timeout", "30", "openssl", "rsa", "-in", key, "-RSAPublicKey_out", "-out", pub }, out outp);
        FileUtils.get_contents (pub, out pem);
        uint8[] n2, e2;
        MyRsa.parse_public_key (pem, out n2, out e2);
        eq (hex (n2), hex (n), "pkcs1 public key parse");
        uint8[] seed = new uint8[20];
        uint8[] em = MyRsa.oaep_pad ({ 1, 2, 3 }, 128, seed);
        ok (em.length == 128 && em[0] == 0, "oaep padded block");
    } catch (Error e) {
        ok (false, "rsa: " + e.message);
    }
    FileUtils.unlink (key);
    FileUtils.unlink (pub);
    FileUtils.unlink (enc);
}

MyColumnDef col (uint8 type, uint flags = 0, uint charset = 45, uint32 length = 11) {
    var c = new MyColumnDef ();
    c.name = "c";
    c.type_code = type;
    c.flags = flags;
    c.charset = charset;
    c.length = length;
    return c;
}

void test_decoding () {
    var v = MyCodec.decode_text (col (3), "42".data);
    ok (v.kind == ValueKind.INTEGER && v.int_value == 42, "text int");
    v = MyCodec.decode_text (col (8, 32), "18446744073709551615".data);
    ok (v.kind == ValueKind.TEXT && v.text_value == "18446744073709551615", "text unsigned bigint overflow");
    v = MyCodec.decode_text (col (8), "-9223372036854775808".data);
    ok (v.kind == ValueKind.INTEGER && v.int_value == int64.MIN, "text bigint min");
    v = MyCodec.decode_text (col (246), "12.50".data);
    ok (v.kind == ValueKind.REAL && v.real_value == 12.5, "decimal real");
    v = MyCodec.decode_text (col (246), "12345678901234567.89".data);
    ok (v.kind == ValueKind.TEXT && v.text_value == "12345678901234567.89", "decimal precision kept as text");
    v = MyCodec.decode_text (col (5), "3.25".data);
    ok (v.kind == ValueKind.REAL && v.real_value == 3.25, "double");
    v = MyCodec.decode_text (col (16), { 0x01, 0x02 });
    ok (v.kind == ValueKind.INTEGER && v.int_value == 258, "bit");
    v = MyCodec.decode_text (col (1, 0, 45, 1), "1".data);
    ok (v.kind == ValueKind.INTEGER && v.int_value == 1, "bool");
    v = MyCodec.decode_text (col (252, 128, 63), { 0, 1, 2 });
    ok (v.kind == ValueKind.BLOB && v.blob_value.get_size () == 3, "blob");
    v = MyCodec.decode_text (col (252, 0, 45), "hello".data);
    ok (v.kind == ValueKind.TEXT && v.text_value == "hello", "text blob type");
    v = MyCodec.decode_text (col (12), "0000-00-00 00:00:00".data);
    ok (v.kind == ValueKind.TEXT && v.text_value == "0000-00-00 00:00:00", "zero datetime");
    v = MyCodec.decode_text (col (3), null);
    ok (v.is_null, "null");
    try {
        var r = new MyReader ({ 0xfe });
        v = MyCodec.decode_binary (col (1), r);
        ok (v.int_value == -2, "binary tiny signed");
        r = new MyReader ({ 0xfe });
        v = MyCodec.decode_binary (col (1, 32), r);
        ok (v.int_value == 254, "binary tiny unsigned");
        r = new MyReader ({ 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff });
        v = MyCodec.decode_binary (col (8, 32), r);
        ok (v.kind == ValueKind.TEXT && v.text_value == "18446744073709551615", "binary unsigned bigint");
        r = new MyReader ({ 11, 0xe8, 0x07, 2, 29, 13, 45, 7, 0x40, 0xe2, 0x01, 0 });
        v = MyCodec.decode_binary (col (12), r);
        eq (v.text_value, "2024-02-29 13:45:07.123456", "binary datetime");
        r = new MyReader ({ 4, 0xe8, 0x07, 2, 29 });
        eq (MyCodec.decode_binary (col (10), r).text_value, "2024-02-29", "binary date");
        r = new MyReader ({ 0 });
        eq (MyCodec.decode_binary (col (12), r).text_value, "0000-00-00 00:00:00", "binary zero datetime");
        r = new MyReader ({ 8, 1, 1, 0, 0, 0, 2, 3, 4 });
        eq (MyCodec.decode_binary (col (11), r).text_value, "-26:03:04", "binary time");
        double d = 2.5;
        uint64 bits = 0;
        Memory.copy (&bits, &d, 8);
        var w = new MyWriter ();
        w.u64 (bits);
        r = new MyReader (w.take ());
        v = MyCodec.decode_binary (col (5), r);
        ok (v.real_value == 2.5, "binary double");
    } catch (Error e) {
        ok (false, "binary decode: " + e.message);
    }
    eq (MyCodec.type_name (8, 32, 63, 20), "BIGINT UNSIGNED", "type name unsigned");
    eq (MyCodec.type_name (252, 144, 63, 65535), "BLOB", "type name blob");
    eq (MyCodec.type_name (253, 0, 45, 400), "VARCHAR", "type name varchar");
    var def = col (3);
    def.org_table = "t";
    def.org_name = "orig";
    var meta = def.to_meta ();
    ok (meta.table == "t" && meta.origin == "orig" && meta.type_name == "INT", "column meta");
}

ColumnInfo ci (string name, string type, bool nullable = true, string def = "", bool pk = false) {
    var c = new ColumnInfo ();
    c.name = name;
    c.data_type = type;
    c.nullable = nullable;
    c.default_expr = def;
    c.primary_key = pk;
    return c;
}

void test_sql_generation () {
    var cfg = new ConnectionConfig ();
    cfg.kind = EngineKind.MYSQL;
    var e = new MysqlEngine (cfg);
    eq (e.quote_ident ("a`b"), "`a``b`", "quote ident");
    eq (e.qualified ("s", "t"), "`s`.`t`", "qualified");
    eq (e.placeholder (3), "?", "placeholder");
    eq (e.literal (new DbValue.text ("it's\\\n")), "'it''s\\\\\\n'", "literal escape");
    eq (e.literal (new DbValue.blob (new Bytes ({ 0xab, 1 }))), "X'AB01'", "blob literal");
    eq (e.literal (new DbValue.null ()), "NULL", "null literal");
    eq (MyCodec.escape_string ("a\\b'", true), "'a\\b'''", "no backslash escapes");
    eq (e.limit_clause (10, 20), " LIMIT 10 OFFSET 20", "limit clause");
    eq (e.text_cast ("x"), "CAST(x AS CHAR)", "text cast");
    eq (e.explain_sql ("SELECT 1;", false), "EXPLAIN SELECT 1", "explain");
    ok (e.keywords ().length > 50 && e.type_names ().length > 20, "keywords and types");

    var before = new TableInfo ();
    before.schema = "shop";
    before.name = "items";
    before.columns.add (ci ("id", "int(11)", false, "", true));
    before.columns.add (ci ("name", "varchar(50)"));
    before.columns.add (ci ("old", "text"));
    var idx = new IndexInfo ();
    idx.name = "ix_name";
    idx.columns = { "name" };
    before.indexes.add (idx);
    var fk = new ForeignKeyInfo ();
    fk.name = "fk_cat";
    fk.columns = { "name" };
    fk.ref_table = "cats";
    fk.ref_columns = { "title" };
    fk.on_delete = "CASCADE";
    before.foreign_keys.add (fk);

    var after = before.copy ();
    after.columns.remove_at (2);
    var renamed = after.find ("name");
    renamed.name = "title";
    renamed.data_type = "varchar(80)";
    renamed.nullable = false;
    var added = ci ("price", "decimal(10,2)", true, "0.00");
    added.comment = "Unit's price";
    after.columns.add (added);
    after.indexes.clear ();
    var idx2 = new IndexInfo ();
    idx2.name = "ux_title";
    idx2.unique = true;
    idx2.columns = { "title" };
    after.indexes.add (idx2);
    after.foreign_keys.clear ();
    after.comment = "Stock";
    after.name = "products";
    var changes = new Gee.ArrayList<ColumnChange> ();
    changes.add (new ColumnChange ("old", null));
    changes.add (new ColumnChange ("name", renamed));
    changes.add (new ColumnChange (null, added));
    string[] stmts = e.alter_table_sql (before, after, changes);
    ok (stmts.length == 2, "alter statement count");
    eq (stmts[0], "ALTER TABLE `shop`.`items` DROP FOREIGN KEY `fk_cat`", "alter drop fk");
    eq (stmts[1], "ALTER TABLE `shop`.`items` DROP COLUMN `old`, CHANGE COLUMN `name` `title` varchar(80) NOT NULL, ADD COLUMN `price` decimal(10,2) NULL DEFAULT 0.00 COMMENT 'Unit''s price' AFTER `title`, DROP INDEX `ix_name`, ADD UNIQUE INDEX `ux_title` (`title`), COMMENT = 'Stock', RENAME TO `shop`.`products`", "alter main");

    var pk_after = before.copy ();
    pk_after.find ("name").primary_key = true;
    pk_after.find ("name").nullable = false;
    var ch2 = new Gee.ArrayList<ColumnChange> ();
    ch2.add (new ColumnChange ("name", pk_after.find ("name")));
    string[] s2 = e.alter_table_sql (before, pk_after, ch2);
    eq (s2[0], "ALTER TABLE `shop`.`items` MODIFY COLUMN `name` varchar(50) NOT NULL, DROP PRIMARY KEY, ADD PRIMARY KEY (`id`, `name`)", "alter primary key");

    var fk_after = before.copy ();
    var fk2 = new ForeignKeyInfo ();
    fk2.name = "fk_new";
    fk2.columns = { "id" };
    fk2.ref_schema = "other";
    fk2.ref_table = "parents";
    fk2.ref_columns = { "pid" };
    fk2.on_update = "SET NULL";
    fk_after.foreign_keys.add (fk2);
    string[] s3 = e.alter_table_sql (before, fk_after, new Gee.ArrayList<ColumnChange> ());
    eq (s3[0], "ALTER TABLE `shop`.`items` ADD CONSTRAINT `fk_new` FOREIGN KEY (`id`) REFERENCES `other`.`parents` (`pid`) ON UPDATE SET NULL", "alter add fk");
    ok (e.alter_table_sql (before, before.copy (), new Gee.ArrayList<ColumnChange> ()).length == 0, "no-op alter");

    var auto_t = new TableInfo ();
    auto_t.schema = "";
    auto_t.name = "t";
    var idc = ci ("id", "bigint unsigned", false, "", true);
    idc.auto_increment = true;
    auto_t.columns.add (idc);
    auto_t.columns.add (ci ("v", "varchar(10)", true, "'x'"));
    auto_t.foreign_keys.add (fk);
    auto_t.checks = { "`v` <> ''" };
    auto_t.comment = "T";
    eq (e.create_table_sql (auto_t), "CREATE TABLE `t` (\n    `id` bigint unsigned NOT NULL AUTO_INCREMENT,\n    `v` varchar(10) NULL DEFAULT 'x',\n    PRIMARY KEY (`id`),\n    CONSTRAINT `fk_cat` FOREIGN KEY (`name`) REFERENCES `cats` (`title`) ON DELETE CASCADE,\n    CHECK (`v` <> '')\n) COMMENT = 'T'", "create table");

    string u, h;
    MysqlEngine.split_account ("'bob'@'%'", out u, out h);
    ok (u == "bob" && h == "%", "split account quoted");
    MysqlEngine.split_account ("`a@b`@localhost", out u, out h);
    ok (u == "a@b" && h == "localhost", "split account at in name");
    MysqlEngine.split_account ("alice", out u, out h);
    ok (u == "alice" && h == "%", "split account bare");
    string privs, obj;
    bool go;
    MysqlEngine.parse_grant ("GRANT SELECT, INSERT ON `shop`.* TO `bob`@`%` WITH GRANT OPTION", out privs, out obj, out go);
    ok (privs == "SELECT, INSERT" && obj == "`shop`.*" && go, "parse grant");
    MysqlEngine.parse_grant ("GRANT USAGE ON *.* TO `x`@`%`", out privs, out obj, out go);
    ok (privs == "USAGE" && obj == "*.*" && !go, "parse usage grant");
    ok (MysqlEngine.server_error_code (new RemoteError.SERVER ("Unknown table 'x' (1051, 42S02)")) == 1051, "error code parse");
}

string my_host;
int my_port;
string my_socket;

ConnectionConfig mk (string user, SslMode mode, bool use_socket = false, string ca_file = "") {
    var c = new ConnectionConfig ();
    c.kind = EngineKind.MYSQL;
    c.host = my_host;
    c.port = my_port;
    c.user = user;
    c.ssl_mode = mode;
    c.ssl_ca_file = ca_file;
    if (use_socket) c.socket_path = my_socket;
    return c;
}

CatalogObject? find_obj (Gee.List<CatalogObject> list, ObjectKind k, string name) {
    foreach (var o in list) if (o.kind == k && o.name == name) return o;
    return null;
}

async void run_server_tests () throws Error {
    in_server = true;
    my_host = Environment.get_variable ("SDB_MY_HOST") ?? "127.0.0.1";
    my_port = int.parse (Environment.get_variable ("SDB_MY_PORT"));
    my_socket = Environment.get_variable ("SDB_MY_SOCKET") ?? "";
    string ca = Environment.get_variable ("SDB_MY_CA") ?? "";
    string other_ca = Environment.get_variable ("SDB_MY_OTHER_CA") ?? "";
    string nu = Environment.get_variable ("SDB_MY_NATIVE_USER") ?? "sdb_native";
    string np = Environment.get_variable ("SDB_MY_NATIVE_PASS") ?? "";
    string su = Environment.get_variable ("SDB_MY_SHA2_USER") ?? "sdb_sha2";
    string sp = Environment.get_variable ("SDB_MY_SHA2_PASS") ?? "";

    var admin = new MysqlEngine (mk (nu, SslMode.PREFER));
    yield admin.open (np);
    ok (admin.connected && admin.server_version != "", "admin connect");
    ok (admin.tls_active, "prefer uses tls over tcp");
    stdout.printf ("server: %s\n", admin.server_version);

    SslMode[] modes = { SslMode.DISABLE, SslMode.PREFER, SslMode.REQUIRE, SslMode.VERIFY_FULL };
    foreach (var mode in modes) {
        foreach (bool sock in new bool[] { false, true }) {
            if (sock && mode != SslMode.DISABLE && mode != SslMode.PREFER) continue;
            var e = new MysqlEngine (mk (nu, mode, sock, ca));
            yield e.open (np);
            var r = yield e.execute ("SELECT 1 + 1");
            ok (r.rows[0].get (0).int_value == 2, "native %s socket=%s".printf (mode.to_string (), sock.to_string ()));
            ok (e.tls_active == (mode != SslMode.DISABLE && !sock), "tls state %s socket=%s".printf (mode.to_string (), sock.to_string ()));
            yield e.close_async ();
        }
    }

    var bad_ca = new MysqlEngine (mk (nu, SslMode.VERIFY_FULL, false, other_ca));
    bool tls_failed = false;
    try {
        yield bad_ca.open (np);
    } catch (RemoteError.TLS err) {
        tls_failed = true;
    }
    ok (tls_failed, "verify-full rejects wrong ca");
    var no_ca = new MysqlEngine (mk (nu, SslMode.VERIFY_FULL, false, ""));
    tls_failed = false;
    try {
        yield no_ca.open (np);
    } catch (RemoteError.TLS err) {
        tls_failed = true;
    }
    ok (tls_failed, "verify-full rejects self-signed without ca");
    var cfg_host = mk (nu, SslMode.VERIFY_FULL, false, ca);
    cfg_host.host = "localhost";
    var by_name = new MysqlEngine (cfg_host);
    yield by_name.open (np);
    ok (by_name.tls_active, "verify-full by host name");
    yield by_name.close_async ();

    var bad = new MysqlEngine (mk (nu, SslMode.DISABLE));
    bool auth_failed = false;
    try {
        yield bad.open ("wrong");
    } catch (RemoteError.AUTH err) {
        auth_failed = err.message.contains ("1045");
    }
    ok (auth_failed, "wrong password gives auth error 1045");

    string[] sha2_cases = { "plain", "tls", "socket", "plain-again" };
    foreach (string sc in sha2_cases) {
        yield admin.execute ("FLUSH PRIVILEGES");
        var cfg = mk (su, sc == "tls" ? SslMode.REQUIRE : SslMode.DISABLE, sc == "socket");
        var e = new MysqlEngine (cfg);
        yield e.open (sp);
        var r = yield e.execute ("SELECT CURRENT_USER()");
        ok (r.rows[0].get (0).to_string ().has_prefix (su), "sha2 login %s".printf (sc));
        auth_paths = "%s%s%s=%s".printf (auth_paths ?? "", auth_paths == null ? "" : ", ", sc, e.auth_path);
        yield e.close_async ();
    }
    var cached = new MysqlEngine (mk (su, SslMode.DISABLE));
    yield cached.open (sp);
    auth_paths = "%s, cached=%s".printf (auth_paths, cached.auth_path);
    yield cached.close_async ();
    ok (auth_paths.has_prefix ("plain=full-rsa, tls=full-tls, socket=full-socket, plain-again=full-rsa, cached="), "sha2 auth paths");
    var sha2_bad = new MysqlEngine (mk (su, SslMode.DISABLE));
    auth_failed = false;
    try {
        yield sha2_bad.open ("nope");
    } catch (RemoteError.AUTH err) {
        auth_failed = true;
    }
    ok (auth_failed, "sha2 wrong password");

    yield admin.execute ("DROP DATABASE IF EXISTS sdb_test");
    yield admin.execute ("CREATE DATABASE sdb_test CHARACTER SET utf8mb4");
    yield admin.use_database ("sdb_test");
    eq (admin.current_database, "sdb_test", "use database");
    yield admin.execute ("CREATE TABLE cats (id INT PRIMARY KEY, title VARCHAR(40) NOT NULL UNIQUE)");
    yield admin.execute ("""CREATE TABLE items (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(50) NOT NULL DEFAULT 'none' COMMENT 'Item name',
        price DECIMAL(10,2) DEFAULT 1.50,
        big DECIMAL(30,4),
        ratio DOUBLE,
        flags BIT(8),
        active BOOLEAN DEFAULT TRUE,
        data BLOB,
        day DATE,
        at DATETIME(6),
        dur TIME,
        doc JSON,
        cat INT,
        huge BIGINT UNSIGNED,
        created TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
        KEY ix_name (name),
        CONSTRAINT fk_cat FOREIGN KEY (cat) REFERENCES cats (id) ON DELETE SET NULL ON UPDATE CASCADE,
        CONSTRAINT chk_price CHECK (price >= 0)
    ) COMMENT 'Stock items'""");
    yield admin.execute ("INSERT INTO cats VALUES (1, 'Tools'), (2, 'Food')");

    var ins = yield admin.execute ("INSERT INTO items (name, price, big, ratio, flags, active, data, day, at, dur, doc, cat, huge) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", {
        new DbValue.text ("Hammer \xf0\x9f\x94\xa8"), new DbValue.real (12.5), new DbValue.text ("12345678901234567890.1234"), new DbValue.real (0.1),
        new DbValue.int (5), new DbValue.bool (true), new DbValue.blob (new Bytes ({ 0, 1, 2, 255 })), new DbValue.text ("2024-02-29"),
        new DbValue.text ("2024-02-29 13:45:07.123456"), new DbValue.text ("-26:03:04"), new DbValue.text ("{\"a\": 1}"), new DbValue.int (1),
        new DbValue.text ("18446744073709551615")
    });
    ok (ins.affected == 1, "prepared insert affected");
    yield admin.execute ("INSERT INTO items (name, price, big, ratio, flags, active, data, day, at, dur, doc, cat, huge) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", {
        new DbValue.text ("Nulls"), new DbValue.null (), new DbValue.null (), new DbValue.null (), new DbValue.null (), new DbValue.null (),
        new DbValue.null (), new DbValue.null (), new DbValue.null (), new DbValue.null (), new DbValue.null (), new DbValue.null (), new DbValue.null ()
    });
    var multi = yield admin.execute ("INSERT INTO items (name) VALUES ('a'), ('b'), ('c')");
    ok (multi.affected == 3, "text insert affected");

    string sel = "SELECT id, name, price, big, ratio, flags, active, data, day, at, dur, doc, cat, huge, created FROM items WHERE id <= ? ORDER BY id";
    foreach (bool binary in new bool[] { false, true }) {
        QueryResult r;
        if (binary) r = yield admin.execute (sel, { new DbValue.int (2) });
        else r = yield admin.execute (sel.replace ("?", "2"));
        string tag = binary ? "binary" : "text";
        ok (r.rows.size == 2, "%s row count".printf (tag));
        var a = r.rows[0];
        ok (a.get (0).kind == ValueKind.INTEGER && a.get (0).int_value == 1, "%s bigint unsigned id".printf (tag));
        eq (a.get (1).to_string (), "Hammer \xf0\x9f\x94\xa8", "%s utf8mb4".printf (tag));
        ok (a.get (2).kind == ValueKind.REAL && a.get (2).real_value == 12.5, "%s decimal".printf (tag));
        ok (a.get (3).kind == ValueKind.TEXT && a.get (3).text_value == "12345678901234567890.1234", "%s wide decimal as text".printf (tag));
        ok (a.get (4).kind == ValueKind.REAL && a.get (4).real_value == 0.1, "%s double".printf (tag));
        ok (a.get (5).kind == ValueKind.INTEGER && a.get (5).int_value == 5, "%s bit".printf (tag));
        ok (a.get (6).kind == ValueKind.INTEGER && a.get (6).int_value == 1, "%s bool".printf (tag));
        ok (a.get (7).kind == ValueKind.BLOB && hex (a.get (7).blob_value.get_data ()) == "000102ff", "%s blob".printf (tag));
        eq (a.get (8).to_string (), "2024-02-29", "%s date".printf (tag));
        eq (a.get (9).to_string (), "2024-02-29 13:45:07.123456", "%s datetime".printf (tag));
        eq (a.get (10).to_string (), "-26:03:04", "%s time".printf (tag));
        ok (a.get (11).kind == ValueKind.TEXT && a.get (11).text_value.contains ("\"a\""), "%s json".printf (tag));
        ok (a.get (12).int_value == 1, "%s int".printf (tag));
        ok (a.get (13).kind == ValueKind.TEXT && a.get (13).text_value == "18446744073709551615", "%s bigint unsigned max".printf (tag));
        ok (a.get (14).kind == ValueKind.TEXT && a.get (14).text_value.length == 19, "%s timestamp".printf (tag));
        var b = r.rows[1];
        bool all_null = true;
        for (int i = 2; i < 14; i++) if (!b.get (i).is_null) all_null = false;
        ok (all_null, "%s nulls".printf (tag));
        ok (r.columns[5].type_name == "BIT" && r.columns[0].type_name == "BIGINT UNSIGNED", "%s column types".printf (tag));
        ok (r.columns[1].table == "items" && r.columns[1].origin == "name", "%s column origin".printf (tag));
    }
    var zero = yield admin.execute ("SELECT CAST('0000-00-00' AS DATE) AS z, CAST(NULL AS CHAR) AS n");
    ok (zero.rows[0].get (1).is_null, "null cast");

    var multi_res = yield admin.execute ("SELECT 1 AS x; UPDATE items SET cat = 2 WHERE id > 2; SELECT 'last' AS y");
    ok (multi_res.columns.size == 1 && multi_res.columns[0].name == "y" && multi_res.rows[0].get (0).text_value == "last", "multi results last set");
    ok (multi_res.affected == 3, "multi results affected");

    var warn = yield admin.execute ("SELECT CAST('abc' AS SIGNED)");
    ok (warn.notices.size >= 1 && warn.notices[0].contains ("1292"), "warning notice");

    try {
        yield admin.execute ("SELECT * FROM missing_table");
        ok (false, "missing table should fail");
    } catch (RemoteError.SERVER err) {
        ok (MysqlEngine.server_error_code (err) == 1146 && err.message.contains ("42S02"), "error code and sqlstate");
    }
    try {
        yield admin.execute ("INSERT INTO cats VALUES (1, 'dup')");
        ok (false, "duplicate should fail");
    } catch (RemoteError.SERVER err) {
        ok (MysqlEngine.server_error_code (err) == 1062, "duplicate key 1062");
    }
    try {
        yield admin.execute ("SELECT ?", { new DbValue.int (1), new DbValue.int (2) });
        ok (false, "param count should fail");
    } catch (RemoteError.SERVER err) {
        ok (true, "param count mismatch");
    }
    var still = yield admin.execute ("SELECT COUNT(*) FROM items");
    ok (still.rows[0].get (0).int_value == 5, "connection usable after errors");

    yield admin.execute ("CREATE TABLE seq100k (n INT PRIMARY KEY)");
    yield admin.execute ("INSERT INTO seq100k SELECT seq FROM seq_1_to_100000");
    var timer = new Timer ();
    var cursor = yield admin.open_cursor ("SELECT n, CONCAT('row ', n) FROM seq100k ORDER BY n");
    int64 total = 0;
    int64 sum = 0;
    while (!cursor.done) {
        var batch = yield cursor.fetch (5000);
        foreach (var row in batch) sum += row.get (0).int_value;
        total += batch.size;
    }
    ok (total == 100000 && sum == (int64) 100000 * 100001 / 2, "cursor streams 100000 rows");
    stdout.printf ("stream: 100000 rows in %.2f s\n", timer.elapsed ());
    var after_stream = yield admin.execute ("SELECT 7");
    ok (after_stream.rows[0].get (0).int_value == 7, "query after stream");

    var partial = yield admin.open_cursor ("SELECT n FROM seq100k ORDER BY n");
    var first = yield partial.fetch (10);
    ok (first.size == 10 && first[9].get (0).int_value == 10, "partial fetch");
    timer.start ();
    yield partial.close_async ();
    ok (timer.elapsed () < 10, "close partial cursor");
    var after_close = yield admin.execute ("SELECT 8");
    ok (after_close.rows[0].get (0).int_value == 8, "query after cursor close");

    var pcur = yield admin.open_cursor ("SELECT n FROM seq100k WHERE n > ? ORDER BY n", { new DbValue.int (99990) });
    var prows = yield pcur.fetch (100);
    ok (prows.size == 10 && pcur.done, "prepared cursor");
    var after_pc = yield admin.execute ("SELECT 9");
    ok (after_pc.rows[0].get (0).int_value == 9, "query after prepared cursor");

    var cancel = new Cancellable ();
    Timeout.add (500, () => {
        cancel.cancel ();
        return false;
    });
    timer.start ();
    bool cancelled = false;
    try {
        yield admin.execute ("SELECT SLEEP(30)", null, cancel);
        cancelled = true;
    } catch (RemoteError.CANCELLED err) {
        cancelled = true;
    } catch (IOError.CANCELLED err) {
        cancelled = true;
    }
    double took = timer.elapsed ();
    ok (cancelled && took < 2.0, "cancel sleep within 2 s (%.2f s)".printf (took));
    var after_cancel = yield admin.execute ("SELECT 10");
    ok (after_cancel.rows[0].get (0).int_value == 10, "query after cancel");

    var dbs = yield admin.list_databases ();
    ok (dbs.contains ("sdb_test") && dbs.contains ("information_schema"), "list databases");
    var schemas = yield admin.list_schemas ();
    ok (schemas.size == dbs.size, "schemas are databases");
    yield admin.execute ("CREATE VIEW v_items AS SELECT id, name FROM items");
    yield admin.execute ("CREATE FUNCTION f_double (x INT) RETURNS INT DETERMINISTIC RETURN x * 2");
    yield admin.execute ("CREATE PROCEDURE p_hello () SELECT 'hello'");
    yield admin.execute ("CREATE TRIGGER t_items BEFORE INSERT ON items FOR EACH ROW SET NEW.name = TRIM(NEW.name)");
    yield admin.execute ("CREATE EVENT e_noop ON SCHEDULE EVERY 1 DAY DISABLE DO SELECT 1");
    yield admin.execute ("CREATE SEQUENCE s_ids");
    var objs = yield admin.list_objects ("sdb_test");
    ok (find_obj (objs, ObjectKind.TABLE, "items") != null, "catalog table");
    ok (find_obj (objs, ObjectKind.TABLE, "items").comment == "Stock items", "catalog table comment");
    ok (find_obj (objs, ObjectKind.VIEW, "v_items") != null, "catalog view");
    ok (find_obj (objs, ObjectKind.INDEX, "ix_name") != null && find_obj (objs, ObjectKind.INDEX, "ix_name").parent == "items", "catalog index");
    ok (find_obj (objs, ObjectKind.FUNCTION, "f_double") != null, "catalog function");
    ok (find_obj (objs, ObjectKind.PROCEDURE, "p_hello") != null, "catalog procedure");
    ok (find_obj (objs, ObjectKind.TRIGGER, "t_items") != null, "catalog trigger");
    ok (find_obj (objs, ObjectKind.EVENT, "e_noop") != null, "catalog event");
    ok (find_obj (objs, ObjectKind.SEQUENCE, "s_ids") != null, "catalog sequence");
    string def_t = yield admin.object_definition (find_obj (objs, ObjectKind.TABLE, "items"));
    ok (def_t.has_prefix ("CREATE TABLE `items`"), "table definition");
    string def_v = yield admin.object_definition (find_obj (objs, ObjectKind.VIEW, "v_items"));
    ok (def_v.contains ("VIEW `v_items`"), "view definition");
    string def_f = yield admin.object_definition (find_obj (objs, ObjectKind.FUNCTION, "f_double"));
    ok (def_f.contains ("x * 2"), "function definition");
    string def_p = yield admin.object_definition (find_obj (objs, ObjectKind.PROCEDURE, "p_hello"));
    ok (def_p.contains ("'hello'"), "procedure definition");
    string def_tr = yield admin.object_definition (find_obj (objs, ObjectKind.TRIGGER, "t_items"));
    ok (def_tr.contains ("TRIM"), "trigger definition");
    string def_e = yield admin.object_definition (find_obj (objs, ObjectKind.EVENT, "e_noop"));
    ok (def_e.contains ("EVENT `e_noop`"), "event definition");
    string def_s = yield admin.object_definition (find_obj (objs, ObjectKind.SEQUENCE, "s_ids"));
    ok (def_s.contains ("SEQUENCE"), "sequence definition");
    string def_i = yield admin.object_definition (find_obj (objs, ObjectKind.INDEX, "ix_name"));
    eq (def_i, "CREATE INDEX `ix_name` ON `sdb_test`.`items` (`name`);", "index definition");

    var info = yield admin.describe_table ("sdb_test", "items");
    eq (info.comment, "Stock items", "describe comment");
    ok (info.columns.size == 15, "describe column count");
    var c_id = info.find ("id");
    ok (c_id.primary_key && c_id.auto_increment && !c_id.nullable && c_id.data_type == "bigint(20) unsigned", "describe id");
    var c_name = info.find ("name");
    eq (c_name.default_expr, "'none'", "describe string default");
    eq (c_name.comment, "Item name", "describe column comment");
    eq (info.find ("price").default_expr, "1.50", "describe numeric default");
    eq (info.find ("created").default_expr.down (), "current_timestamp()", "describe timestamp default");
    ok (info.find ("big").default_expr == "", "describe null default");
    ok (info.find ("active").data_type == "tinyint(1)", "describe bool type");
    bool has_ix = false, has_pk = false;
    foreach (var i in info.indexes) {
        if (i.name == "ix_name" && !i.unique && i.method == "BTREE" && i.columns.length == 1) has_ix = true;
        if (i.primary && i.columns[0] == "id") has_pk = true;
    }
    ok (has_ix && has_pk, "describe indexes");
    ok (info.foreign_keys.size == 1 && info.foreign_keys[0].name == "fk_cat" && info.foreign_keys[0].on_delete == "SET NULL" && info.foreign_keys[0].on_update == "CASCADE" && info.foreign_keys[0].ref_table == "cats" && info.foreign_keys[0].ref_columns[0] == "id", "describe foreign key");
    bool price_check = false;
    foreach (string ck in info.checks) if (ck.contains ("`price` >= 0")) price_check = true;
    ok (price_check, "describe check");

    var altered = info.copy ();
    var nm = altered.find ("name");
    nm.name = "label";
    nm.data_type = "varchar(80)";
    var extra = ci ("stock", "int(11)", false, "0");
    extra.comment = "On hand";
    altered.columns.insert (2, extra);
    altered.columns.remove (altered.find ("doc"));
    var nix = new IndexInfo ();
    nix.name = "ix_stock";
    nix.columns = { "stock", "label" };
    var keep = new Gee.ArrayList<IndexInfo> ();
    foreach (var i in altered.indexes) if (i.name != "ix_name") keep.add (i);
    altered.indexes.clear ();
    altered.indexes.add_all (keep);
    altered.indexes.add (nix);
    altered.foreign_keys[0].on_delete = "CASCADE";
    altered.comment = "Renamed items";
    altered.name = "products";
    var chs = new Gee.ArrayList<ColumnChange> ();
    chs.add (new ColumnChange ("name", nm));
    chs.add (new ColumnChange (null, extra));
    chs.add (new ColumnChange ("doc", null));
    string[] alter = admin.alter_table_sql (info, altered, chs);
    foreach (string s in alter) yield admin.execute (s);
    var re = yield admin.describe_table ("sdb_test", "products");
    eq (re.comment, "Renamed items", "alter comment applied");
    ok (re.find ("label") != null && re.find ("label").data_type == "varchar(80)" && re.find ("label").default_expr == "'none'", "alter rename applied");
    ok (re.find ("stock") != null && re.find ("stock").comment == "On hand" && re.find ("stock").position == 3, "alter add applied");
    ok (re.find ("doc") == null && re.find ("name") == null, "alter drop applied");
    bool ix_stock = false, ix_old = false;
    foreach (var i in re.indexes) {
        if (i.name == "ix_stock" && i.columns.length == 2 && i.columns[1] == "label") ix_stock = true;
        if (i.name == "ix_name") ix_old = true;
    }
    ok (ix_stock && !ix_old, "alter indexes applied");
    ok (re.foreign_keys.size == 1 && re.foreign_keys[0].on_delete == "CASCADE", "alter foreign key applied");
    ok (admin.alter_table_sql (re, re.copy (), new Gee.ArrayList<ColumnChange> ()).length == 0, "re-describe is stable");

    var pk_t = re.copy ();
    pk_t.name = "products";
    foreach (var c in pk_t.columns) if (c.name == "stock") c.primary_key = true;
    var pk_chs = new Gee.ArrayList<ColumnChange> ();
    string[] pk_sql = admin.alter_table_sql (re, pk_t, pk_chs);
    foreach (string s in pk_sql) yield admin.execute (s);
    var re2 = yield admin.describe_table ("sdb_test", "products");
    string[] pk_cols = re2.primary_key ();
    ok (pk_cols.length == 2 && pk_cols[1] == "stock", "alter primary key applied");

    var copy_t = re2.copy ();
    copy_t.name = "products_copy";
    copy_t.foreign_keys.clear ();
    copy_t.checks = {};
    yield admin.execute (admin.create_table_sql (copy_t));
    var re3 = yield admin.describe_table ("sdb_test", "products_copy");
    ok (re3.columns.size == re2.columns.size && re3.primary_key ().length == 2, "create table round trip");

    var ex = yield admin.execute (admin.explain_sql ("SELECT * FROM products WHERE id = 1", false));
    ok (ex.rows.size >= 1, "explain");
    var an = yield admin.execute (admin.explain_sql ("SELECT * FROM products WHERE id = 1", true));
    ok (an.rows.size >= 1, "analyze");

    var users = yield admin.list_users ();
    bool saw_sha2 = false;
    foreach (var r in users.rows) if (r.get (0).to_string () == su && r.get (2).to_string () == "caching_sha2_password") saw_sha2 = true;
    ok (saw_sha2, "list users");
    var privs = yield admin.list_privileges ("'%s'@'%%'".printf (su));
    ok (privs.rows.size >= 1 && privs.rows[0].get (0).to_string () == "ALL PRIVILEGES" && privs.rows[0].get (1).to_string () == "*.*", "list privileges");

    var victim = new MysqlEngine (mk (nu, SslMode.DISABLE));
    yield victim.open (np);
    var act = yield admin.list_activity ();
    bool saw_victim = false;
    foreach (var r in act.rows) if (r.get (0).int_value == victim.thread_id) saw_victim = true;
    ok (saw_victim && act.columns.size == 8, "list activity");
    yield admin.kill_activity (victim.thread_id.to_string (), true);
    bool victim_dead = false;
    try {
        yield victim.execute ("SELECT 1");
    } catch (Error err) {
        victim_dead = true;
    }
    ok (victim_dead, "kill connection");

    var sq = new MysqlEngine (mk (nu, SslMode.DISABLE));
    yield sq.open (np);
    uint32 sq_id = sq.thread_id;
    var sleep_done = false;
    Error? sleep_err = null;
    sq.execute.begin ("SELECT SLEEP(30)", null, null, -1, (o, res) => {
        try {
            sq.execute.end (res);
        } catch (Error err) {
            sleep_err = err;
        }
        sleep_done = true;
    });
    Timeout.add (400, run_server_tests.callback);
    yield;
    timer.start ();
    yield admin.kill_activity (sq_id.to_string (), false);
    while (!sleep_done) {
        Timeout.add (50, run_server_tests.callback);
        yield;
    }
    ok (timer.elapsed () < 2.0, "kill query");
    var sq_after = yield sq.execute ("SELECT 11");
    ok (sq_after.rows[0].get (0).int_value == 11, "connection survives kill query");
    yield sq.close_async ();

    yield admin.execute ("DROP DATABASE sdb_test");
    yield admin.close_async ();
    ok (!admin.connected, "close");
    in_server = false;
}

int main (string[] args) {
    Intl.setlocale (LocaleCategory.ALL, "C");
    test_framing ();
    test_lenenc ();
    test_scrambles ();
    test_bignum ();
    test_rsa ();
    test_decoding ();
    test_sql_generation ();
    int unit = checks;
    if (Environment.get_variable ("SDB_MY_PORT") != null) {
        var loop = new MainLoop ();
        Error? failure = null;
        run_server_tests.begin ((o, res) => {
            try {
                run_server_tests.end (res);
            } catch (Error e) {
                failure = e;
            }
            loop.quit ();
        });
        loop.run ();
        if (failure != null) {
            stderr.printf ("FAIL: server tests: %s\n", failure.message);
            return 1;
        }
        stdout.printf ("sha2 auth paths: %s\n", auth_paths);
        stdout.printf ("mysql: %d checks passed (%d unit, %d server)\n", checks, unit, server_checks);
    } else {
        stdout.printf ("mysql: %d checks passed (unit only, set SDB_MY_PORT for server tests)\n", checks);
    }
    return 0;
}
