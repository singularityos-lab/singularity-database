using Singularity.Apps.Database;

int checks = 0;
bool failed = false;

void ok (bool cond, string what) {
    checks++;
    if (Environment.get_variable ("SDB_TRACE") != null) print ("ok %d %s\n", checks, what);
    if (!cond) {
        stderr.printf ("FAIL: %s\n", what);
        Process.exit (1);
    }
}

string hex (uint8[] data) {
    var sb = new StringBuilder ();
    foreach (uint8 b in data) sb.append ("%02x".printf (b));
    return sb.str;
}

string env (string name, string fallback = "") {
    return Environment.get_variable (name) ?? fallback;
}

PgEngine make_engine (string user, SslMode mode = SslMode.DISABLE, string host = "", bool unix_socket = false, string database = "") {
    var c = new ConnectionConfig ();
    c.kind = EngineKind.POSTGRESQL;
    c.host = host != "" ? host : env ("SDB_PG_HOST", "127.0.0.1");
    c.port = int.parse (env ("SDB_PG_PORT"));
    c.user = user;
    c.database = database != "" ? database : env ("SDB_PG_DB", "postgres");
    c.ssl_mode = mode;
    c.ssl_ca_file = env ("SDB_PG_CA");
    c.connect_timeout = 5;
    if (unix_socket) c.socket_path = env ("SDB_PG_SOCKET_DIR");
    return new PgEngine (c);
}

TableInfo sample_table () {
    var t = new TableInfo ();
    t.schema = "public";
    t.name = "people";
    var id = new ColumnInfo ();
    id.name = "id";
    id.data_type = "integer";
    id.nullable = false;
    id.primary_key = true;
    id.auto_increment = true;
    t.columns.add (id);
    var name = new ColumnInfo ();
    name.name = "name";
    name.data_type = "text";
    t.columns.add (name);
    var old = new ColumnInfo ();
    old.name = "old";
    old.data_type = "text";
    t.columns.add (old);
    var ix = new IndexInfo ();
    ix.name = "people_name_idx";
    ix.columns = { "name" };
    ix.method = "btree";
    t.indexes.add (ix);
    return t;
}

void test_codec () {
    var w = new PgWriter ();
    w.put_int16 (-2);
    w.put_int32 (123456789);
    w.put_int32 (-1);
    w.put_cstr ("héllo");
    w.put_byte (7);
    uint8[] framed = w.finish ('Q');
    ok (framed[0] == 'Q', "codec type byte");
    uint32 len = ((uint32) framed[1] << 24) | ((uint32) framed[2] << 16) | ((uint32) framed[3] << 8) | framed[4];
    ok (len == framed.length - 1, "codec length includes itself");
    var m = new PgMessage ('Q', framed[5:framed.length]);
    ok (m.read_int16 () == -2, "codec int16");
    ok (m.read_int32 () == 123456789, "codec int32");
    ok (m.read_int32 () == -1, "codec negative int32");
    ok (m.read_cstr () == "héllo", "codec utf8 cstring");
    ok (m.read_byte () == 7 && m.at_end (), "codec byte and end");
    var raw = new PgWriter ();
    raw.put_int32 (80877103);
    ok (hex (raw.finish (0)) == "0000000804d2162f", "codec untyped frame");
    PgMessage row = new PgMessage ('D', { 0, 2, 0, 0, 0, 2, '4', '2', 0xff, 0xff, 0xff, 0xff });
    ok (row.read_int16 () == 2 && row.read_int32 () == 2 && row.read_text (2) == "42" && row.read_int32 () == -1, "codec data row");
}

void test_crypto () throws Error {
    ok (hex (PgScram.pbkdf2 ("passwd".data, "salt".data, 1)) == "55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc", "pbkdf2 c=1");
    ok (hex (PgScram.pbkdf2 ("password".data, "salt".data, 2)) == "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43", "pbkdf2 c=2");
    ok (hex (PgScram.pbkdf2 ("password".data, "salt".data, 4096)) == "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a", "pbkdf2 c=4096");
    var s = new PgScram ("user", "rOprNGfwEbeRWgbNEkqO");
    ok (s.client_first () == "n,,n=user,r=rOprNGfwEbeRWgbNEkqO", "scram client first");
    string fin = s.client_final ("r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096", "pencil");
    ok (fin == "c=biws,r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,p=dHzbZapWIk4jUhN+Ute9ytag9zjfMHgsqmmiz7AndVQ=", "scram rfc7677 proof");
    ok (s.verify_server ("v=6rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4="), "scram rfc7677 server signature");
    ok (!s.verify_server ("v=AAAA"), "scram rejects bad server signature");
    bool threw = false;
    try {
        new PgScram ("user", "abc").client_final ("r=xyz,s=QQ==,i=1", "p");
    } catch (Error e) {
        threw = true;
    }
    ok (threw, "scram rejects foreign nonce");
    ok (new PgScram ("a=b,c").client_first ().has_prefix ("n,,n=a=3Db=2Cc,r="), "scram username escaping");
    ok (PgScram.md5_password ("sdb_md5", "md5pass", { 1, 2, 3, 4 }) == "md5a672b9d1d76a51283386d00cfff0a55b", "md5 password hash");
}

void test_types () {
    var v = PgTypes.decode (23, "42");
    ok (v.kind == ValueKind.INTEGER && v.int_value == 42, "int4 decodes int");
    v = PgTypes.decode (20, "-9223372036854775808");
    ok (v.kind == ValueKind.INTEGER && v.int_value == int64.MIN, "int8 min");
    ok (PgTypes.decode (21, "7").kind == ValueKind.INTEGER && PgTypes.decode (26, "16384").int_value == 16384, "int2 and oid");
    v = PgTypes.decode (701, "1.5");
    ok (v.kind == ValueKind.REAL && v.real_value == 1.5, "float8 real");
    ok (PgTypes.decode (701, "NaN").kind == ValueKind.TEXT, "float NaN stays text");
    v = PgTypes.decode (1700, "12.50");
    ok (v.kind == ValueKind.REAL && v.real_value == 12.5, "numeric round trippable is real");
    ok (PgTypes.decode (1700, "10").kind == ValueKind.REAL, "numeric integer real");
    v = PgTypes.decode (1700, "123456789012345678901234.5");
    ok (v.kind == ValueKind.TEXT && v.text_value == "123456789012345678901234.5", "numeric precise stays text");
    ok (PgTypes.decode (1700, "0.1000000000000000000001").kind == ValueKind.TEXT, "numeric long fraction stays text");
    ok (PgTypes.decode (16, "t").int_value == 1 && PgTypes.decode (16, "f").int_value == 0, "bool 0/1");
    v = PgTypes.decode (17, "\\x00ff10");
    ok (v.kind == ValueKind.BLOB && hex (v.blob_value.get_data ()) == "00ff10", "bytea hex blob");
    ok (PgTypes.decode (2950, "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11").kind == ValueKind.TEXT, "uuid text");
    ok (PgTypes.name_for (1184) == "timestamptz" && PgTypes.name_for (3802) == "jsonb", "type names");
    ok (PgTypes.encode (new DbValue.blob (new Bytes ({ 0, 255 }))) == "\\x00ff", "encode blob");
    ok (PgTypes.encode (new DbValue.real (0.25)) == "0.25" && PgTypes.encode (new DbValue.int (-3)) == "-3", "encode numbers");
    var r = new QueryResult ();
    PgEngine.apply_tag (r, "INSERT 0 5");
    ok (r.affected == 5 && r.command == "INSERT", "tag insert");
    r = new QueryResult ();
    PgEngine.apply_tag (r, "CREATE TABLE");
    ok (r.affected == -1 && r.command == "CREATE TABLE", "tag ddl");
}

void test_sql () {
    var e = new PgEngine (new ConnectionConfig ());
    ok (e.quote_ident ("abc_1") == "abc_1", "ident plain");
    ok (e.quote_ident ("Abc") == "\"Abc\"", "ident uppercase");
    ok (e.quote_ident ("user") == "\"user\"", "ident reserved");
    ok (e.quote_ident ("a\"b c") == "\"a\"\"b c\"", "ident escaping");
    ok (e.quote_ident ("1a") == "\"1a\"", "ident leading digit");
    ok (e.qualified ("public", "My Table") == "public.\"My Table\"", "qualified");
    ok (e.placeholder (1) == "$1" && e.placeholder (12) == "$12", "placeholder");
    ok (e.literal (new DbValue.text ("it's")) == "'it''s'", "literal quote");
    ok (e.literal (new DbValue.text ("a\\b")) == "E'a\\\\b'", "literal backslash");
    ok (e.literal (new DbValue.blob (new Bytes ({ 1, 2 }))) == "'\\x0102'::bytea", "literal bytea");
    ok (e.literal (new DbValue.null ()) == "NULL" && e.literal (new DbValue.int (5)) == "5", "literal null int");
    ok (e.text_cast ("x") == "CAST(x AS TEXT)", "text cast");
    ok (e.explain_sql ("SELECT 1", true) == "EXPLAIN (ANALYZE, BUFFERS) SELECT 1" && e.explain_sql ("SELECT 1", false) == "EXPLAIN SELECT 1", "explain");
    ok (e.limit_clause (10, 20) == " LIMIT 10 OFFSET 20", "limit clause");
    ok (e.keywords ().length > 20 && e.type_names ().length > 20, "keywords and types");

    var before = sample_table ();
    var after = before.copy ();
    var changes = new Gee.ArrayList<ColumnChange> ();
    var renamed = after.find ("name");
    renamed.name = "full_name";
    renamed.data_type = "varchar(200)";
    renamed.nullable = false;
    renamed.comment = "Full name";
    changes.add (new ColumnChange ("id", after.find ("id")));
    changes.add (new ColumnChange ("name", renamed));
    after.columns.remove (after.find ("old"));
    changes.add (new ColumnChange ("old", null));
    var added = new ColumnInfo ();
    added.name = "Score";
    added.data_type = "numeric(5,2)";
    added.nullable = false;
    added.default_expr = "0";
    after.columns.add (added);
    changes.add (new ColumnChange (null, added));
    after.indexes[0].columns = { "full_name" };
    string[] sql = e.alter_table_sql (before, after, changes);
    string joined = string.joinv (";\n", sql);
    ok (sql.length == 6, "alter statement count: " + joined);
    ok (sql[0] == "ALTER TABLE public.people DROP COLUMN old", "alter drop");
    ok (sql[1] == "ALTER TABLE public.people RENAME COLUMN name TO full_name", "alter rename");
    ok (sql[2] == "ALTER TABLE public.people ALTER COLUMN full_name TYPE varchar(200) USING full_name::varchar(200)", "alter type");
    ok (sql[3] == "ALTER TABLE public.people ALTER COLUMN full_name SET NOT NULL", "alter not null");
    ok (sql[4] == "COMMENT ON COLUMN public.people.full_name IS 'Full name'", "alter comment");
    ok (sql[5] == "ALTER TABLE public.people ADD COLUMN \"Score\" numeric(5,2) NOT NULL DEFAULT 0", "alter add");

    var after2 = before.copy ();
    after2.name = "persons";
    after2.find ("name").primary_key = true;
    after2.indexes[0].unique = true;
    var fk = new ForeignKeyInfo ();
    fk.name = "persons_team_fk";
    fk.columns = { "old" };
    fk.ref_schema = "public";
    fk.ref_table = "teams";
    fk.ref_columns = { "code" };
    fk.on_delete = "CASCADE";
    after2.foreign_keys.add (fk);
    after2.checks = { "CHECK (id > 0)" };
    after2.comment = "People";
    string[] sql2 = e.alter_table_sql (before, after2, new Gee.ArrayList<ColumnChange> ());
    string j2 = string.joinv (";\n", sql2);
    ok (sql2[0] == "ALTER TABLE public.people RENAME TO persons", "alter rename table: " + j2);
    ok ("DROP INDEX public.people_name_idx" in sql2, "alter drop changed index");
    ok ("ALTER TABLE public.persons DROP CONSTRAINT people_pkey" in sql2, "alter drop pk");
    ok ("ALTER TABLE public.persons ADD PRIMARY KEY (id, name)" in sql2, "alter add pk");
    ok ("CREATE UNIQUE INDEX people_name_idx ON public.persons (name)" in sql2, "alter recreate index");
    ok ("ALTER TABLE public.persons ADD CONSTRAINT persons_team_fk FOREIGN KEY (old) REFERENCES public.teams (code) ON DELETE CASCADE" in sql2, "alter add fk");
    ok ("ALTER TABLE public.persons ADD CHECK (id > 0)" in sql2, "alter add check");
    ok ("COMMENT ON TABLE public.persons IS 'People'" in sql2, "alter table comment");
    ok (e.alter_table_sql (before, before.copy (), new Gee.ArrayList<ColumnChange> ()).length == 0, "alter no changes");
    string create = e.create_table_sql (before);
    ok (create.has_prefix ("CREATE TABLE public.people (\n    id integer GENERATED BY DEFAULT AS IDENTITY NOT NULL,\n    name text,\n    old text,\n    PRIMARY KEY (id)\n);"), "create table: " + create);
}

async void run_e2e () throws Error {
    var admin = make_engine (env ("SDB_PG_ADMIN", "postgres"), SslMode.DISABLE, "", true);
    yield admin.open (null);
    ok (admin.connected && admin.server_version != "", "unix socket trust connect");
    ok (!admin.tls_active, "unix socket no tls");

    var u = make_engine ("sdb_scram", SslMode.DISABLE, "", true);
    yield u.open ("scrampass");
    ok ((yield u.execute ("SELECT current_user")).text (0, "current_user") == "sdb_scram", "unix socket scram");
    yield u.close_async ();

    foreach (var mode in new SslMode[] { SslMode.DISABLE, SslMode.PREFER, SslMode.REQUIRE, SslMode.VERIFY_FULL }) {
        var e = make_engine ("sdb_scram", mode);
        yield e.open ("scrampass");
        var r = yield e.execute ("SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid()");
        bool ssl = r.rows[0].get (0).as_bool ();
        ok (ssl == (mode != SslMode.DISABLE) && e.tls_active == ssl, "tcp scram sslmode %s".printf (mode.id ()));
        yield e.close_async ();
    }
    var loc = make_engine ("sdb_scram", SslMode.VERIFY_FULL, "localhost");
    yield loc.open ("scrampass");
    ok (loc.tls_active, "verify-full by dns name");
    yield loc.close_async ();

    var bad_ca = make_engine ("sdb_scram", SslMode.VERIFY_FULL);
    bad_ca.config.ssl_ca_file = env ("SDB_PG_OTHER_CA");
    string msg = "";
    try {
        yield bad_ca.open ("scrampass");
    } catch (RemoteError.TLS e) {
        msg = e.message;
    }
    ok (msg != "", "verify-full wrong CA fails");
    var bad_host = make_engine ("sdb_scram", SslMode.VERIFY_FULL, "127.0.0.2");
    msg = "";
    try {
        yield bad_host.open ("scrampass");
    } catch (RemoteError.TLS e) {
        msg = e.message;
    }
    ok (msg != "", "verify-full wrong host fails");
    var req_host = make_engine ("sdb_scram", SslMode.REQUIRE, "127.0.0.2");
    yield req_host.open ("scrampass");
    ok (req_host.tls_active, "require accepts unverified host");
    yield req_host.close_async ();
    var no_ca = make_engine ("sdb_scram", SslMode.VERIFY_FULL);
    no_ca.config.ssl_ca_file = "";
    msg = "";
    try {
        yield no_ca.open ("scrampass");
    } catch (RemoteError.TLS e) {
        msg = e.message;
    }
    ok (msg != "", "verify-full without trusted CA fails");

    var md5 = make_engine ("sdb_md5", SslMode.PREFER);
    yield md5.open ("md5pass");
    ok ((yield md5.execute ("SELECT 1 AS x")).text (0, "x") == "1", "md5 auth");
    yield md5.close_async ();
    var plain = make_engine ("sdb_plain", SslMode.REQUIRE);
    yield plain.open ("plainpass");
    ok ((yield plain.execute ("SELECT current_user AS u")).text (0, "u") == "sdb_plain", "cleartext auth");
    yield plain.close_async ();
    foreach (string who in new string[] { "sdb_scram", "sdb_md5", "sdb_plain" }) {
        var w = make_engine (who, SslMode.PREFER);
        msg = "";
        try {
            yield w.open ("wrong");
        } catch (RemoteError.AUTH e) {
            msg = e.message;
        }
        ok (msg.contains ("password authentication failed") && msg.contains ("28P01"), "wrong password %s: %s".printf (who, msg));
    }
    var nodb = make_engine ("sdb_scram", SslMode.DISABLE, "", false, "no_such_db");
    msg = "";
    try {
        yield nodb.open ("scrampass");
    } catch (Error e) {
        msg = e.message;
    }
    ok (msg.contains ("no_such_db") && msg.contains ("3D000"), "missing database error");

    var e = make_engine ("sdb_scram", SslMode.REQUIRE);
    yield e.open ("scrampass");
    ok (e.current_database == env ("SDB_PG_DB", "sdb_test"), "current database");
    var notices = new Gee.ArrayList<string> ();
    e.notice.connect ((m) => notices.add (m));
    yield e.execute ("DROP SCHEMA IF EXISTS t_s CASCADE; CREATE SCHEMA t_s; COMMENT ON SCHEMA t_s IS 'test'");
    yield e.execute ("""
        CREATE TABLE t_s.teams (code text PRIMARY KEY, label text);
        CREATE TABLE t_s.items (
            id integer GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
            serial_no bigserial,
            name varchar(80) NOT NULL DEFAULT 'none',
            price numeric(10,2),
            ratio double precision,
            active boolean,
            data bytea,
            born date,
            seen timestamptz,
            doc json,
            tags text[],
            ref uuid,
            team text REFERENCES t_s.teams (code) ON DELETE CASCADE ON UPDATE SET NULL,
            note text,
            CONSTRAINT price_positive CHECK (price >= 0)
        );
        COMMENT ON TABLE t_s.items IS 'Things';
        COMMENT ON COLUMN t_s.items.name IS 'Item name';
        CREATE INDEX items_tags_gin ON t_s.items USING gin (tags);
        CREATE UNIQUE INDEX items_name_team ON t_s.items (name, team);
        CREATE VIEW t_s.cheap AS SELECT id, name FROM t_s.items WHERE price < 10;
        CREATE MATERIALIZED VIEW t_s.totals AS SELECT count(*) AS n FROM t_s.items;
        CREATE SEQUENCE t_s.counter START 5;
        CREATE FUNCTION t_s.add_one(x integer) RETURNS integer LANGUAGE sql AS $$ SELECT x + 1 $$;
        COMMENT ON FUNCTION t_s.add_one(integer) IS 'adds';
        CREATE PROCEDURE t_s.noop() LANGUAGE plpgsql AS $$ BEGIN END $$;
        CREATE FUNCTION t_s.touch() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN NEW.note := coalesce(NEW.note, 'touched'); RETURN NEW; END $$;
        CREATE TRIGGER items_touch BEFORE INSERT ON t_s.items FOR EACH ROW EXECUTE FUNCTION t_s.touch();
        INSERT INTO t_s.teams VALUES ('a', 'Alpha'), ('b', 'Beta');
    """);

    DbValue[] p = {
        new DbValue.text ("Ünïcødé ✓ 日本"), new DbValue.text ("12.34"), new DbValue.real (0.125), new DbValue.bool (true),
        new DbValue.blob (new Bytes ({ 0, 1, 254, 255 })), new DbValue.text ("2024-02-29"), new DbValue.text ("2024-03-01 12:30:00+00"),
        new DbValue.text ("{\"k\": [1, 2]}"), new DbValue.text ("a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11"), new DbValue.text ("a"), new DbValue.null ()
    };
    var ins = yield e.execute ("INSERT INTO t_s.items (name, price, ratio, active, data, born, seen, doc, ref, team, note) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11) RETURNING id", p);
    ok (ins.affected == 1 && ins.rows.size == 1 && ins.rows[0].get (0).int_value == 1, "parameterized insert returning");
    DbValue[] p2 = { new DbValue.text ("second"), new DbValue.null (), new DbValue.null (), new DbValue.null (), new DbValue.null (), new DbValue.null (), new DbValue.null (), new DbValue.null (), new DbValue.null (), new DbValue.null (), new DbValue.text ("given") };
    yield e.execute ("INSERT INTO t_s.items (name, price, ratio, active, data, born, seen, doc, ref, team, note) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)", p2);
    var r = yield e.execute ("SELECT id, serial_no, name, price, ratio, active, data, born, seen, doc, ref, team, note, 9223372036854775807::bigint AS big, 1e400::numeric AS huge, 'NaN'::float8 AS nan, (-5)::int2 AS small FROM t_s.items ORDER BY id");
    ok (r.rows.size == 2 && r.columns.size == 17, "select shape");
    var row = r.rows[0];
    ok (r.columns[0].type_name == "int4" && r.columns[0].type_oid == 23 && row.get (0).int_value == 1, "int column");
    ok (r.columns[1].type_name == "int8" && row.get (1).int_value == 1, "bigserial");
    ok (row.get (2).text_value == "Ünïcødé ✓ 日本", "unicode text round trip");
    ok (row.get (3).kind == ValueKind.REAL && row.get (3).real_value == 12.34, "numeric round trip");
    ok (row.get (4).real_value == 0.125, "float round trip");
    ok (row.get (5).kind == ValueKind.INTEGER && row.get (5).int_value == 1, "bool round trip");
    ok (row.get (6).kind == ValueKind.BLOB && hex (row.get (6).blob_value.get_data ()) == "0001feff", "bytea round trip");
    ok (row.get (7).text_value == "2024-02-29", "date round trip");
    ok (row.get (8).text_value.has_prefix ("2024-03-01") && r.columns[8].type_name == "timestamptz", "timestamptz round trip " + row.get (8).to_string ());
    ok (row.get (9).text_value == "{\"k\": [1, 2]}", "json round trip");
    ok (row.get (10).text_value == "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11" && r.columns[10].type_name == "uuid", "uuid round trip");
    ok (row.get (12).text_value == "touched", "trigger fired and null param");
    ok (row.get (13).int_value == int64.MAX, "bigint max");
    ok (row.get (14).kind == ValueKind.TEXT && row.get (14).text_value.has_prefix ("1000000000"), "huge numeric text");
    ok (row.get (15).kind == ValueKind.TEXT && row.get (16).int_value == -5, "nan and int2");
    ok (r.rows[1].get (3).is_null && r.rows[1].get (6).is_null && r.rows[1].get (12).text_value == "given", "null round trips");
    var sel = yield e.execute ("SELECT name FROM t_s.items WHERE note IS NOT DISTINCT FROM $1", { new DbValue.null () });
    ok (sel.rows.size == 0, "null param comparison");
    var up = yield e.execute ("UPDATE t_s.items SET ratio = 2 WHERE id > $1", { new DbValue.int (0) });
    ok (up.affected == 2 && up.command == "UPDATE", "update affected");

    var lim = yield e.execute ("SELECT g FROM generate_series(1, 10) g", null, null, 3);
    ok (lim.rows.size == 3 && lim.truncated, "execute max_rows truncates");
    var lim2 = yield e.execute ("SELECT 1; SELECT g FROM generate_series(1, 10) g", null, null, 4);
    ok (lim2.rows.size == 4 && lim2.truncated, "simple max_rows truncates");
    var full = yield e.execute ("SELECT g FROM generate_series(1, 10) g", null, null, 10);
    ok (full.rows.size == 10 && !full.truncated, "exact max_rows not truncated");
    var multi = yield e.execute ("SELECT 1 AS a; SELECT 2 AS b, 3 AS c");
    ok (multi.columns.size == 2 && multi.text (0, "c") == "3", "multi statement last result");

    notices.clear ();
    var nr = yield e.execute ("DO $$ BEGIN RAISE NOTICE 'hello %', 42; END $$");
    ok (nr.notices.size == 1 && nr.notices[0].contains ("hello 42") && notices.size == 1, "notices collected and signalled");

    yield e.execute ("BEGIN");
    ok (e.transaction_status == 'T', "transaction status in tx");
    string code = "";
    try {
        yield e.execute ("SELECT 1/0");
    } catch (RemoteError.SERVER x) {
        code = e.last_sqlstate;
        msg = x.message;
    }
    ok (code == "22012" && msg.contains ("division by zero") && msg.contains ("22012"), "division by zero sqlstate");
    ok (e.transaction_status == 'E', "failed transaction status");
    yield e.rollback ();
    ok (e.transaction_status == 'I', "idle after rollback");
    msg = "";
    try {
        yield e.execute ("SELEC 1");
    } catch (RemoteError.SERVER x) {
        msg = x.message;
    }
    ok (msg.contains ("42601") && msg.contains ("At character 1"), "syntax error with position: " + msg);
    msg = "";
    try {
        yield e.execute ("INSERT INTO t_s.teams VALUES ($1, 'dup')", { new DbValue.text ("a") });
    } catch (RemoteError.SERVER x) {
        msg = x.message;
    }
    ok (msg.contains ("23505") && msg.contains ("Key (code)=(a) already exists"), "unique violation detail");
    msg = "";
    try {
        yield e.execute ("SELECT * FROM t_s.nope");
    } catch (RemoteError.SERVER x) {
        msg = x.message;
    }
    ok (msg.contains ("42P01"), "undefined table");
    ok ((yield e.execute ("SELECT 5 AS x", null)).text (0, "x") == "5", "usable after errors");

    var cursor = yield e.open_cursor ("SELECT g, md5(g::text) AS h FROM generate_series(1, 100000) g");
    ok (cursor.columns.size == 2 && cursor.columns[1].name == "h", "cursor columns");
    int64 total = 0, sum = 0;
    int batches = 0;
    string last_hash = "";
    while (!cursor.done) {
        var rows = yield cursor.fetch (7000);
        batches++;
        foreach (var rr in rows) {
            total++;
            sum += rr.get (0).int_value;
            last_hash = rr.get (1).text_value;
        }
    }
    ok (total == 100000 && sum == (int64) 100000 * 100001 / 2, "cursor streamed 100000 rows");
    ok (batches == 15 && last_hash == Checksum.compute_for_string (ChecksumType.MD5, "100000"), "cursor batches and last row");
    yield cursor.close_async ();

    var c2 = yield e.open_cursor ("SELECT g FROM generate_series(1, 1000) g WHERE g > $1", { new DbValue.int (990) });
    var first = yield c2.fetch (3);
    ok (first.size == 3 && first[0].get (0).int_value == 991, "param cursor first batch");
    ok ((yield e.execute ("SELECT 7 AS x")).text (0, "x") == "7", "execute auto-closes open cursor");
    ok (c2.done && (yield c2.fetch (3)).size == 0, "closed cursor is done");
    var c3 = yield e.open_cursor ("SELECT 1 / (g - 3) AS x FROM generate_series(1, 5) g");
    msg = "";
    try {
        yield c3.fetch (10);
    } catch (Error x) {
        msg = x.message;
    }
    ok (msg.contains ("22012") && c3.done, "cursor error");
    msg = "";
    try {
        yield e.open_cursor ("SELECT nope");
    } catch (Error x) {
        msg = x.message;
    }
    ok (msg.contains ("42703"), "cursor parse error");
    ok ((yield e.execute ("SELECT 8 AS x")).text (0, "x") == "8", "usable after cursor errors");

    var cancel = new Cancellable ();
    Timeout.add (300, () => {
        cancel.cancel ();
        return false;
    });
    var timer = new Timer ();
    msg = "";
    try {
        yield e.execute ("SELECT pg_sleep(30)", null, cancel);
    } catch (IOError.CANCELLED x) {
        msg = x.message;
    }
    double took = timer.elapsed ();
    ok (msg != "" && e.last_sqlstate == "57014" && took < 2.0, "cancellable cancels pg_sleep in %.2fs".printf (took));
    Timeout.add (300, () => {
        e.cancel_running ();
        return false;
    });
    timer.start ();
    msg = "";
    try {
        yield e.execute ("SELECT pg_sleep(30)");
    } catch (RemoteError.CANCELLED x) {
        msg = x.message;
    }
    took = timer.elapsed ();
    ok (msg != "" && took < 2.0, "cancel_running cancels in %.2fs".printf (took));
    var sc = new Cancellable ();
    var scur = yield e.open_cursor ("SELECT pg_sleep(0.001), g FROM generate_series(1, 100000) g");
    Timeout.add (300, () => {
        sc.cancel ();
        return false;
    });
    timer.start ();
    msg = "";
    try {
        yield scur.fetch (100000, sc);
    } catch (IOError.CANCELLED x) {
        msg = x.message;
    }
    took = timer.elapsed ();
    ok (msg != "" && e.last_sqlstate == "57014" && took < 2.0 && scur.done, "cursor fetch cancel in %.2fs".printf (took));
    ok ((yield e.execute ("SELECT 9 AS x")).text (0, "x") == "9", "usable after cancel");

    var dbs = yield e.list_databases ();
    ok (dbs.contains ("sdb_test") && dbs.contains ("postgres") && !dbs.contains ("template0"), "list databases");
    var schemas = yield e.list_schemas ();
    ok (schemas.contains ("t_s") && schemas.contains ("public"), "list schemas");
    string tail = schemas[schemas.size - 1];
    ok (schemas.index_of ("t_s") < schemas.index_of ("pg_catalog") && (tail == "pg_catalog" || tail == "information_schema"), "system schemas last");
    bool toast = false;
    foreach (string s in schemas) if (s.has_prefix ("pg_toast") || s.has_prefix ("pg_temp")) toast = true;
    ok (!toast, "toast and temp schemas hidden");
    yield e.execute ("ANALYZE t_s.items");
    var objs = yield e.list_objects ("t_s");
    var found = new Gee.HashMap<string, CatalogObject> ();
    foreach (var o in objs) found["%s:%s".printf (o.kind.label (), o.name)] = o;
    ok (found.has_key ("Table:items") && found["Table:items"].comment == "Things" && found["Table:items"].row_estimate == 2, "list objects table with estimate");
    ok (found.has_key ("View:cheap") && found.has_key ("Materialized View:totals"), "list views");
    ok (found.has_key ("Index:items_tags_gin") && found["Index:items_tags_gin"].parent == "items" && found["Index:items_tags_gin"].detail.contains ("gin"), "list index parent");
    ok (found.has_key ("Index:items_pkey") && found["Index:items_pkey"].detail.contains (_("primary key")), "list pk index");
    ok (found.has_key ("Function:add_one") && found["Function:add_one"].comment == "adds" && found["Function:add_one"].detail == "x integer", "list function");
    ok (found.has_key ("Procedure:noop"), "list procedure");
    ok (found.has_key ("Trigger:items_touch") && found["Trigger:items_touch"].parent == "items", "list trigger parent");
    ok (found.has_key ("Sequence:counter") && found.has_key ("Sequence:items_serial_no_seq"), "list sequences");

    var t = yield e.describe_table ("t_s", "items");
    ok (t.comment == "Things" && t.columns.size == 14, "describe table columns");
    var id = t.find ("id");
    ok (id.primary_key && id.auto_increment && !id.nullable && id.data_type == "integer", "describe identity pk");
    var sn = t.find ("serial_no");
    ok (sn.auto_increment && sn.default_expr.has_prefix ("nextval(") && sn.data_type == "bigint", "describe serial");
    var nm = t.find ("name");
    ok (nm.data_type == "character varying(80)" && !nm.nullable && nm.default_expr.contains ("'none'") && nm.comment == "Item name", "describe varchar default comment");
    ok (t.find ("price").data_type == "numeric(10,2)" && t.find ("tags").data_type == "text[]", "describe formatted types");
    ok (t.find ("price").nullable && t.find ("seen").data_type == "timestamp with time zone", "describe nullable");
    IndexInfo? gin = null, uq = null;
    foreach (var i in t.indexes) {
        if (i.name == "items_tags_gin") gin = i;
        if (i.name == "items_name_team") uq = i;
    }
    ok (gin != null && gin.method == "gin" && gin.columns.length == 1 && gin.columns[0] == "tags", "describe gin index");
    ok (uq != null && uq.unique && uq.columns.length == 2 && uq.columns[1] == "team", "describe unique index");
    ok (t.foreign_keys.size == 1 && t.foreign_keys[0].ref_table == "teams" && t.foreign_keys[0].columns[0] == "team" && t.foreign_keys[0].ref_columns[0] == "code", "describe fk");
    ok (t.foreign_keys[0].on_delete == "CASCADE" && t.foreign_keys[0].on_update == "SET NULL" && t.foreign_keys[0].ref_schema == "t_s", "describe fk actions");
    ok (t.checks.length == 1 && t.checks[0] == "CHECK (price >= 0::numeric)", "describe check " + string.joinv ("|", t.checks));

    string vdef = yield e.object_definition (found["View:cheap"]);
    ok (vdef.has_prefix ("CREATE OR REPLACE VIEW t_s.cheap AS") && vdef.contains ("price < 10"), "view definition");
    string fdef = yield e.object_definition (found["Function:add_one"]);
    ok (fdef.contains ("CREATE OR REPLACE FUNCTION t_s.add_one(x integer)"), "function definition");
    string idef = yield e.object_definition (found["Index:items_tags_gin"]);
    ok (idef == "CREATE INDEX items_tags_gin ON t_s.items USING gin (tags);", "index definition " + idef);
    string tdef = yield e.object_definition (found["Trigger:items_touch"]);
    ok (tdef.contains ("CREATE TRIGGER items_touch BEFORE INSERT ON t_s.items"), "trigger definition");
    string sdef = yield e.object_definition (found["Sequence:counter"]);
    ok (sdef.contains ("START WITH 5"), "sequence definition " + sdef);
    string mdef = yield e.object_definition (found["Materialized View:totals"]);
    ok (mdef.has_prefix ("CREATE MATERIALIZED VIEW t_s.totals AS"), "matview definition");
    string tbl = yield e.object_definition (found["Table:items"]);
    yield e.execute (tbl.replace ("t_s.items", "t_s.items_copy").replace ("CONSTRAINT items_team_fkey", "").replace ("items_tags_gin", "copy_tags_gin").replace ("items_name_team", "copy_name_team"));
    var copy = yield e.describe_table ("t_s", "items_copy");
    ok (copy.columns.size == 14 && copy.find ("name").comment == "Item name" && copy.comment == "Things" && copy.indexes.size == 3, "table definition recreates: " + tbl);
    ok (copy.find ("id").auto_increment && copy.foreign_keys.size == 1 && copy.checks.length == 1, "table definition keeps identity fk check");

    var before = yield e.describe_table ("t_s", "items");
    var after = before.copy ();
    var changes = new Gee.ArrayList<ColumnChange> ();
    var note = after.find ("note");
    note.name = "Remark";
    note.data_type = "varchar(300)";
    note.comment = "free text";
    changes.add (new ColumnChange ("note", note));
    var ratio = after.find ("ratio");
    ratio.nullable = false;
    ratio.default_expr = "1";
    changes.add (new ColumnChange ("ratio", ratio));
    after.columns.remove (after.find ("born"));
    changes.add (new ColumnChange ("born", null));
    var extra = new ColumnInfo ();
    extra.name = "extra";
    extra.data_type = "integer";
    extra.nullable = false;
    extra.default_expr = "3";
    after.columns.add (extra);
    changes.add (new ColumnChange (null, extra));
    after.comment = "Stuff";
    after.checks = { before.checks[0], "CHECK (extra < 100)" };
    var ix = new IndexInfo ();
    ix.name = "items_extra_idx";
    ix.columns = { "extra" };
    after.indexes.add (ix);
    string[] alter = e.alter_table_sql (before, after, changes);
    yield e.execute ("BEGIN");
    foreach (string s in alter) yield e.execute (s);
    yield e.execute ("COMMIT");
    var re = yield e.describe_table ("t_s", "items");
    ok (re.find ("note") == null && re.find ("Remark") != null && re.find ("Remark").data_type == "character varying(300)" && re.find ("Remark").comment == "free text", "alter applied rename type comment");
    ok (!re.find ("ratio").nullable && re.find ("ratio").default_expr == "1", "alter applied not null default");
    ok (re.find ("born") == null && re.find ("extra") != null && re.find ("extra").default_expr == "3", "alter applied drop add");
    ok (re.comment == "Stuff" && re.checks.length == 2, "alter applied comment check");
    bool has_ix = false;
    foreach (var i in re.indexes) if (i.name == "items_extra_idx") has_ix = true;
    ok (has_ix, "alter applied index");
    var again = e.alter_table_sql (re, re.copy (), new Gee.ArrayList<ColumnChange> ());
    ok (again.length == 0, "alter idempotent after describe");
    var pk_after = re.copy ();
    pk_after.find ("id").primary_key = false;
    pk_after.find ("serial_no").primary_key = true;
    pk_after.name = "items2";
    foreach (string s in e.alter_table_sql (re, pk_after, new Gee.ArrayList<ColumnChange> ())) yield e.execute (s);
    var re2 = yield e.describe_table ("t_s", "items2");
    ok (re2.primary_key ().length == 1 && re2.primary_key ()[0] == "serial_no", "alter applied pk change and rename table");

    var users = yield e.list_users ();
    bool seen = false;
    for (int i = 0; i < users.rows.size; i++) if (users.rows[i].get (0).to_string () == "sdb_scram") seen = true;
    ok (seen && users.columns.size == 8, "list users");
    var privs = yield e.list_privileges ("sdb_scram");
    bool has_db = false;
    for (int i = 0; i < privs.rows.size; i++) if (privs.rows[i].get (1).to_string () == "sdb_test" && privs.rows[i].get (2).to_string ().contains ("CREATE")) has_db = true;
    ok (has_db && privs.columns.size == 3, "list privileges");

    var victim = make_engine ("sdb_scram", SslMode.PREFER);
    yield victim.open ("scrampass");
    string vpid = (yield victim.execute ("SELECT pg_backend_pid() AS p")).text (0, "p");
    string vmsg = "";
    bool vdone = false;
    victim.execute.begin ("SELECT pg_sleep(30)", null, null, -1, (obj, res) => {
        try {
            victim.execute.end (res);
        } catch (Error x) {
            vmsg = x.message;
        }
        vdone = true;
    });
    yield sleep_ms (300);
    var act = yield e.list_activity ();
    bool listed = false;
    for (int i = 0; i < act.rows.size; i++) {
        if (act.rows[i].get (0).to_string () == vpid && act.rows[i].get (8).to_string ().contains ("pg_sleep")) listed = true;
    }
    ok (listed && act.columns.size == 9, "list activity");
    yield e.kill_activity (vpid, false);
    for (int i = 0; i < 40 && !vdone; i++) yield sleep_ms (50);
    ok (vdone && vmsg.contains ("57014"), "kill query cancels");
    ok ((yield victim.execute ("SELECT 1 AS x")).text (0, "x") == "1", "victim alive after cancel");
    yield e.kill_activity (vpid, true);
    yield sleep_ms (200);
    msg = "";
    try {
        yield victim.execute ("SELECT 1");
    } catch (Error x) {
        msg = x.message;
    }
    ok (msg != "", "kill connection terminates: " + msg);
    msg = "";
    try {
        yield e.kill_activity ("abc", false);
    } catch (Error x) {
        msg = x.message;
    }
    ok (msg != "", "kill rejects bad id");

    yield e.use_database ("postgres");
    ok (e.current_database == "postgres" && (yield e.execute ("SELECT current_database() AS d")).text (0, "d") == "postgres", "use database reconnects");
    yield e.use_database ("sdb_test");
    yield e.execute ("DROP SCHEMA t_s CASCADE");
    yield e.close_async ();
    ok (!e.connected, "closed");
    msg = "";
    try {
        yield e.execute ("SELECT 1");
    } catch (RemoteError.CONNECT x) {
        msg = x.message;
    }
    ok (msg != "", "execute after close fails");
    yield admin.close_async ();
}

async void test_login_errors () throws Error {
    var svc = new SocketService ();
    uint16 port = svc.add_any_inet_port (null);
    svc.incoming.connect ((conn) => {
        try {
            conn.close ();
        } catch (Error e) {
        }
        return true;
    });
    svc.start ();
    var c = new ConnectionConfig ();
    c.kind = EngineKind.POSTGRESQL;
    c.host = "127.0.0.1";
    c.port = port;
    c.user = "nobody";
    c.ssl_mode = SslMode.DISABLE;
    c.connect_timeout = 5;
    string msg = "";
    bool connect_err = false;
    try {
        yield new PgEngine (c).open ("x");
    } catch (RemoteError.CONNECT e) {
        connect_err = true;
        msg = e.message;
    } catch (Error e) {
        msg = "unexpected %s: %s".printf (e.domain.to_string (), e.message);
    }
    ok (connect_err && msg.contains ("closed the connection while signing in"), "login read error is a friendly connect error: " + msg);
    c.ssl_mode = SslMode.PREFER;
    connect_err = false;
    try {
        yield new PgEngine (c).open ("x");
    } catch (RemoteError.CONNECT e) {
        connect_err = true;
        msg = e.message;
    } catch (Error e) {
        msg = "unexpected %s: %s".printf (e.domain.to_string (), e.message);
    }
    ok (connect_err, "login close during ssl request is a connect error: " + msg);
    svc.stop ();
}

async void sleep_ms (uint ms) {
    Timeout.add (ms, () => {
        sleep_ms.callback ();
        return false;
    });
    yield;
}

int main () {
    Intl.setlocale (LocaleCategory.ALL, "C");
    try {
        test_codec ();
        test_crypto ();
        test_types ();
        test_sql ();
    } catch (Error e) {
        stderr.printf ("FAIL: %s\n", e.message);
        return 1;
    }
    var lloop = new MainLoop ();
    test_login_errors.begin ((obj, res) => {
        try {
            test_login_errors.end (res);
        } catch (Error e) {
            stderr.printf ("FAIL login errors: %s\n", e.message);
            failed = true;
        }
        lloop.quit ();
    });
    lloop.run ();
    if (failed) return 1;
    int units = checks;
    if (env ("SDB_PG_PORT") == "") {
        print ("pg: %d checks passed (server tests skipped, SDB_PG_PORT not set)\n", checks);
        return 0;
    }
    var loop = new MainLoop ();
    run_e2e.begin ((obj, res) => {
        try {
            run_e2e.end (res);
        } catch (Error e) {
            stderr.printf ("FAIL after %d checks: %s (%s %d)\n", checks, e.message, e.domain.to_string (), e.code);
            failed = true;
        }
        loop.quit ();
    });
    loop.run ();
    if (failed) return 1;
    print ("pg: %d checks passed (%d unit, %d server)\n", checks, units, checks - units);
    return 0;
}
