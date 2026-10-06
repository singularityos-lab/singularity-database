using Singularity.Apps.Database;

int checks = 0;
bool failed = false;
string scratch;

void ok (bool cond, string what) {
    checks++;
    if (Environment.get_variable ("SDB_TRACE") != null) print ("ok %d %s\n", checks, what);
    if (!cond) {
        stderr.printf ("FAIL: %s\n", what);
        Process.exit (1);
    }
}

void eq (string got, string want, string what) {
    if (got != want) stderr.printf ("  got:  [%s]\n  want: [%s]\n", got, want);
    ok (got == want, what);
}

string env (string name, string fallback = "") {
    return Environment.get_variable (name) ?? fallback;
}

string scratch_file (string name) {
    string p = Path.build_filename (scratch, name);
    foreach (string suffix in new string[] { "", "-journal", "-wal", "-shm" }) FileUtils.unlink (p + suffix);
    return p;
}

async void sleep_ms (uint ms) {
    Timeout.add (ms, () => {
        sleep_ms.callback ();
        return false;
    });
    yield;
}

string[] texts (Gee.List<ScriptStatement> list) {
    string[] out_list = {};
    foreach (var s in list) out_list += s.text;
    return out_list;
}

void test_script () {
    var l = SqlScript.split ("SELECT 1; SELECT 'a;b'; SELECT 'it''s;'", EngineKind.POSTGRESQL);
    ok (l.size == 3, "split three statements");
    eq (l[1].text, "SELECT 'a;b'", "quoted semicolon");
    eq (l[2].text, "SELECT 'it''s;'", "doubled quote");
    l = SqlScript.split ("-- c;\nSELECT 1; /* x; y */ SELECT 2;;\n;  \n", EngineKind.POSTGRESQL);
    ok (l.size == 2, "comments and empty statements");
    eq (l[0].text, "-- c;\nSELECT 1", "leading comment kept with statement");
    eq (l[1].text, "/* x; y */ SELECT 2", "block comment kept");
    string fn = "CREATE FUNCTION f() RETURNS int AS $$ BEGIN RETURN 1; END; $$ LANGUAGE plpgsql; SELECT f()";
    l = SqlScript.split (fn, EngineKind.POSTGRESQL);
    ok (l.size == 2, "dollar quote body");
    ok (l[0].text.has_suffix ("LANGUAGE plpgsql"), "dollar quote whole");
    l = SqlScript.split ("DO $body$ BEGIN PERFORM 1; END $body$; SELECT $1", EngineKind.POSTGRESQL);
    ok (l.size == 2, "tagged dollar quote");
    eq (l[1].text, "SELECT $1", "parameter not a dollar quote");
    l = SqlScript.split ("SELECT \"a;b\" FROM t; SELECT 2", EngineKind.POSTGRESQL);
    ok (l.size == 2, "quoted identifier");
    l = SqlScript.split ("SELECT 'a\\';b'; # note;\nSELECT `x;y` FROM t", EngineKind.MYSQL);
    ok (l.size == 2, "mysql backslash, hash comment, backtick");
    eq (l[0].text, "SELECT 'a\\';b'", "mysql backslash escape");
    ok (l[1].text.has_suffix ("SELECT `x;y` FROM t"), "backtick identifier");
    string trig = "CREATE TRIGGER t BEFORE INSERT ON x FOR EACH ROW BEGIN SET NEW.a = 1; IF NEW.b > 0 THEN SET NEW.c = 2; END IF; SET NEW.d = CASE WHEN 1 THEN 2 ELSE 3 END; END; SELECT 1";
    l = SqlScript.split (trig, EngineKind.MYSQL);
    ok (l.size == 2, "mysql trigger body with IF and CASE");
    ok (l[0].text.has_suffix ("END"), "trigger ends at END");
    string proc = "CREATE PROCEDURE p() BEGIN DECLARE i INT DEFAULT 0; WHILE i < 3 DO SET i = i + 1; END WHILE; CASE i WHEN 3 THEN SELECT 1; ELSE SELECT 2; END CASE; BEGIN SELECT 3; END; END; CALL p()";
    l = SqlScript.split (proc, EngineKind.MYSQL);
    ok (l.size == 2, "mysql procedure nested blocks");
    eq (l[1].text, "CALL p()", "statement after procedure");
    l = SqlScript.split ("CREATE TRIGGER tr AFTER INSERT ON a BEGIN INSERT INTO b VALUES (1); UPDATE c SET x = 1; END; BEGIN; COMMIT;", EngineKind.SQLITE);
    ok (l.size == 3, "sqlite trigger and plain BEGIN");
    eq (l[1].text, "BEGIN", "plain begin is a statement");
    string src = "SELECT 1;\nSELECT 2;\n\nSELECT 3";
    var st = SqlScript.statement_at (src, src.index_of ("2"), EngineKind.POSTGRESQL);
    eq (st.text, "SELECT 2", "statement at cursor");
    ok (st.start == 10 && st.end == 18, "statement offsets");
    st = SqlScript.statement_at (src, src.length, EngineKind.POSTGRESQL);
    eq (st.text, "SELECT 3", "statement at end");
    st = SqlScript.statement_at (src, 9, EngineKind.POSTGRESQL);
    eq (st.text, "SELECT 1", "cursor right after semicolon");
    st = SqlScript.statement_at (src, 20, EngineKind.POSTGRESQL);
    eq (st.text, "SELECT 2", "blank line belongs to previous");
    ok (SqlScript.statement_at ("  ", 0, EngineKind.POSTGRESQL) == null, "no statement in blank text");
    ok (SqlScript.returns_rows ("  -- x\nselect 1"), "returns rows select");
    ok (SqlScript.returns_rows ("WITH a AS (SELECT 1) SELECT * FROM a"), "returns rows with");
    ok (SqlScript.returns_rows ("SHOW TABLES"), "returns rows show");
    ok (!SqlScript.returns_rows ("UPDATE t SET a = 1"), "update returns no rows");
    ok (SqlScript.is_destructive ("drop table x"), "drop destructive");
    ok (SqlScript.is_destructive ("DELETE FROM t"), "delete without where");
    ok (!SqlScript.is_destructive ("DELETE FROM t WHERE id = 1"), "delete with where");
    ok (SqlScript.is_destructive ("UPDATE t SET a = 1"), "update without where");
    ok (SqlScript.is_destructive ("TRUNCATE t"), "truncate");
    ok (!SqlScript.is_destructive ("SELECT 1"), "select not destructive");
}

void test_ssh_command () throws Error {
    var c = new ConnectionConfig ();
    c.kind = EngineKind.POSTGRESQL;
    c.host = "db.internal";
    c.ssh_host = "gw.example";
    c.ssh_user = "ann";
    c.ssh_port = 2200;
    c.ssh_key_file = "/k/id";
    var t = new SshTunnel ();
    string joined = string.joinv (" ", t.command (c, 40000));
    ok (joined.has_prefix ("ssh -N -T"), "ssh argv head");
    ok (joined.contains ("-p 2200"), "ssh port");
    ok (joined.contains ("-i /k/id -o IdentitiesOnly=yes"), "ssh key");
    ok (joined.contains ("BatchMode=yes"), "key mode batch");
    ok (joined.contains ("ExitOnForwardFailure=yes"), "exit on forward failure");
    ok (joined.has_suffix ("-L 127.0.0.1:40000:db.internal:5432 ann@gw.example"), "ssh forward and destination");
    c.ssh_use_password = true;
    c.ssh_key_file = "";
    joined = string.joinv (" ", t.command (c, 40001));
    ok (joined.contains ("BatchMode=no") && joined.contains ("PubkeyAuthentication=no") && joined.contains ("NumberOfPasswordPrompts=1"), "password mode options");
    ok (!joined.contains ("-i "), "password mode has no key");
    c.socket_path = "/run/postgresql";
    joined = string.joinv (" ", t.command (c, 40002));
    ok (joined.contains ("-L 127.0.0.1:40002:/run/postgresql/.s.PGSQL.5432 "), "pg socket forward");
    c.kind = EngineKind.MYSQL;
    c.socket_path = "/run/mysqld/mysqld.sock";
    c.port = 0;
    t.extra_options = { "-F", "/dev/null" };
    joined = string.joinv (" ", t.command (c, 40003));
    ok (joined.contains ("-F /dev/null -L 127.0.0.1:40003:/run/mysqld/mysqld.sock "), "mysql socket forward with extra options");
    ok (SshTunnel.free_port () > 1024, "free port");
}

void test_stores () throws Error {
    var store = new ConnectionStore ();
    store.load ();
    ok (store.items.size == 0, "empty connection store");
    var c = new ConnectionConfig ();
    c.name = "Prod";
    c.kind = EngineKind.MYSQL;
    c.host = "h";
    c.port = 3307;
    c.user = "u";
    c.database = "d";
    c.socket_path = "/s";
    c.file_path = "/f";
    c.ssl_mode = SslMode.VERIFY_FULL;
    c.ssl_ca_file = "/ca";
    c.ssh_enabled = true;
    c.ssh_host = "sh";
    c.ssh_port = 2222;
    c.ssh_user = "su";
    c.ssh_key_file = "/key";
    c.ssh_use_password = true;
    c.color = "red";
    c.read_only = true;
    c.connect_timeout = 7;
    store.put (c);
    ok (c.id != "", "put assigns id");
    var second = new ConnectionConfig ();
    second.name = "Local";
    store.put (second);
    var again = new ConnectionStore ();
    again.load ();
    ok (again.items.size == 2, "store persisted");
    var r = again.find (c.id);
    ok (r != null, "find by id");
    ok (r.name == "Prod" && r.kind == EngineKind.MYSQL && r.host == "h" && r.port == 3307 && r.user == "u" && r.database == "d", "basic fields round trip");
    ok (r.socket_path == "/s" && r.file_path == "/f" && r.ssl_mode == SslMode.VERIFY_FULL && r.ssl_ca_file == "/ca", "tls fields round trip");
    ok (r.ssh_enabled && r.ssh_host == "sh" && r.ssh_port == 2222 && r.ssh_user == "su" && r.ssh_key_file == "/key" && r.ssh_use_password, "ssh fields round trip");
    ok (r.color == "red" && r.read_only && r.connect_timeout == 7, "misc fields round trip");
    string data;
    FileUtils.get_contents (ClientStore.path ("connections.json"), out data);
    ok (!data.contains ("password\":\"") && !data.contains ("secret"), "no password stored in file");
    var finfo = File.new_for_path (ClientStore.path ("connections.json")).query_info ("unix::mode", FileQueryInfoFlags.NONE);
    ok ((finfo.get_attribute_uint32 ("unix::mode") & 0077) == 0, "connections file private");
    r.name = "Prod 2";
    again.put (r);
    ok (again.items.size == 2, "put existing replaces");
    again.remove (second.id);
    var third = new ConnectionStore ();
    third.load ();
    ok (third.items.size == 1 && third.items[0].name == "Prod 2", "remove persisted");
    third.remove (c.id);

    var h = new QueryHistory ("conn/../x");
    h.clear ();
    h.add ("SELECT 1", 1.5, true, "db");
    h.add ("SELECT 2", 2, false, "db");
    h.add ("  SELECT 2  ", 3, true, "db");
    h.add ("   ", 1, true, "db");
    ok (h.entries.size == 2, "history dedupe and skip blank");
    eq (h.entries[0].sql, "SELECT 2", "history newest first");
    ok (h.entries[0].ok && h.entries[0].elapsed_ms == 3, "history keeps latest run");
    ok (!FileUtils.test (Path.build_filename (scratch, "x.json"), FileTest.EXISTS), "history id sanitized");
    for (int i = 0; i < 510; i++) h.add ("SELECT %d".printf (i + 100), 1, true, "db");
    ok (h.entries.size == QueryHistory.LIMIT, "history limit");
    var h2 = new QueryHistory ("conn/../x");
    ok (h2.entries.size == QueryHistory.LIMIT, "history persisted");
    eq (h2.entries[0].sql, "SELECT 609", "history order persisted");
    ok (h2.entries[0].database == "db" && h2.entries[0].time > 0, "history fields persisted");
    h2.clear ();
    ok (new QueryHistory ("conn/../x").entries.size == 0, "history cleared");

    var sn = new SnippetStore ();
    foreach (var s in sn.items.to_array ()) sn.remove (s.name);
    sn.put ("zeta", "SELECT 1");
    sn.put ("alpha", "SELECT 2");
    sn.put ("zeta", "SELECT 3");
    ok (sn.items.size == 2, "snippet update in place");
    var sn2 = new SnippetStore ();
    ok (sn2.items.size == 2 && sn2.items[0].name == "alpha", "snippets persisted sorted");
    ok (sn2.items[1].sql == "SELECT 3", "snippet updated sql persisted");
    sn2.remove ("alpha");
    ok (new SnippetStore ().items.size == 1, "snippet removed");
    sn2.remove ("zeta");
}

class Canceller : Object {
    public SqliteEngine e;
    public Canceller (SqliteEngine e) {
        this.e = e;
    }
    public void* run () {
        Thread.usleep (300000);
        e.cancel_running ();
        return null;
    }
}

async SqliteEngine open_sqlite (string path, bool ro = false) throws Error {
    var c = new ConnectionConfig ();
    c.kind = EngineKind.SQLITE;
    c.file_path = path;
    c.read_only = ro;
    var e = new SqliteEngine (c);
    yield e.open (null);
    return e;
}

ColumnInfo? col (TableInfo t, string name) {
    return t.find (name);
}

async int64 count (Engine e, string table) throws Error {
    var r = yield e.execute ("SELECT COUNT(*) FROM " + table);
    return r.rows[0].get (0).as_int ();
}

async void test_sqlite () throws Error {
    var bad = new ConnectionConfig ();
    bad.kind = EngineKind.SQLITE;
    bad.file_path = Path.build_filename (scratch, "missing-dir", "x.db");
    bool failed_open = false;
    try {
        yield new SqliteEngine (bad).open (null);
    } catch (RemoteError.CONNECT err) {
        failed_open = err.message.contains ("does not exist");
    }
    ok (failed_open, "missing folder error");
    string junk = scratch_file ("junk.db");
    FileUtils.set_contents (junk, "this is certainly not a database file, just some text that is long enough to be a header.......");
    bad.file_path = junk;
    failed_open = false;
    try {
        yield new SqliteEngine (bad).open (null);
    } catch (RemoteError.CONNECT err) {
        failed_open = err.message.contains ("not a SQLite database");
    }
    ok (failed_open, "non sqlite file error");
    bad.file_path = "";
    failed_open = false;
    try {
        yield new SqliteEngine (bad).open (null);
    } catch (RemoteError.CONNECT err) {
        failed_open = true;
    }
    ok (failed_open, "empty path error");

    string path = scratch_file ("engine.db");
    var e = yield open_sqlite (path);
    ok (e.connected && e.server_version.has_prefix ("SQLite 3"), "sqlite opened");
    var r = yield e.execute ("CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT); INSERT INTO t (name) VALUES ('a'); INSERT INTO t (name) VALUES ('b');");
    ok (r.affected == 1 && r.command == "INSERT", "multi statement execute");
    r = yield e.execute ("INSERT INTO t (name) VALUES (?), (?)", { new DbValue.text ("c"), new DbValue.null () });
    ok (r.affected == 2, "params insert affected");
    r = yield e.execute ("SELECT id, name FROM t WHERE name = ? OR name IS NULL ORDER BY id", { new DbValue.text ("c") });
    ok (r.rows.size == 2 && r.rows[0].get (1).to_string () == "c" && r.rows[1].get (1).is_null, "params select");
    ok (r.columns.size == 2 && r.columns[0].type_name == "INTEGER" && r.columns[0].table == "t" && r.columns[1].origin == "name", "column meta");
    r = yield e.execute ("SELECT * FROM t", null, null, 2);
    ok (r.rows.size == 2 && r.truncated, "max rows truncation");
    r = yield e.execute ("SELECT * FROM t", null, null, 4);
    ok (r.rows.size == 4 && !r.truncated, "max rows exact not truncated");
    r = yield e.execute ("UPDATE t SET name = 'z' WHERE id > 100");
    ok (r.affected == 0 && !r.has_rows (), "update no match");
    bool threw = false;
    try {
        yield e.execute ("SELECT * FROM nope");
    } catch (RemoteError.SERVER err) {
        threw = err.message.contains ("no such table");
    }
    ok (threw, "server error message");
    r = yield e.execute ("-- only a comment");
    ok (!r.has_rows (), "comment only script");

    var cur = yield e.open_cursor ("WITH RECURSIVE c(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM c WHERE x < 50000) SELECT x, 'row ' || x FROM c");
    ok (cur.columns.size == 2, "cursor columns");
    int64 total = 0;
    int batches = 0;
    int64 last = 0;
    while (!cur.done) {
        var rows = yield cur.fetch (7000);
        total += rows.size;
        if (rows.size > 0) last = rows[rows.size - 1].get (0).as_int ();
        batches++;
    }
    ok (total == 50000 && last == 50000 && batches == 8, "cursor streams 50000 rows");
    var empty = yield cur.fetch (10);
    ok (empty.size == 0, "fetch after done");
    cur = yield e.open_cursor ("SELECT * FROM t");
    var part = yield cur.fetch (1);
    yield cur.close_async ();
    ok (part.size == 1 && cur.done, "cursor close early");

    var canceller = new Canceller (e);
    var th = new Thread<void*> ("cancel", canceller.run);
    var timer = new Timer ();
    bool cancelled = false;
    try {
        yield e.execute ("WITH RECURSIVE c(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM c) SELECT count(*) FROM c");
    } catch (RemoteError.CANCELLED err) {
        cancelled = true;
    }
    th.join ();
    ok (cancelled && timer.elapsed () < 5, "cancel running query");
    r = yield e.execute ("SELECT 1");
    ok (r.rows.size == 1, "usable after cancel");

    yield e.execute ("""CREATE TABLE parent (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL UNIQUE,
        qty INTEGER NOT NULL DEFAULT 5,
        price REAL DEFAULT 1.5,
        created TEXT DEFAULT CURRENT_TIMESTAMP,
        checked_at TEXT,
        CHECK (qty >= 0)
    )""");
    yield e.execute ("CREATE TABLE child (a INTEGER, b TEXT, parent_id INTEGER REFERENCES parent (id) ON DELETE CASCADE, note TEXT DEFAULT 'n/a', PRIMARY KEY (a, b))");
    yield e.execute ("CREATE INDEX child_note_idx ON child (note, parent_id)");
    yield e.execute ("CREATE VIEW parent_view AS SELECT id, code FROM parent");
    yield e.execute ("CREATE TRIGGER parent_trg AFTER INSERT ON parent BEGIN UPDATE parent SET qty = qty WHERE id = NEW.id; END");
    yield e.execute ("INSERT INTO parent (code) VALUES ('p1'), ('p2')");
    yield e.execute ("INSERT INTO child VALUES (1, 'x', 1, 'hello'), (1, 'y', 2, NULL)");
    var dbs = yield e.list_databases ();
    ok (dbs.size == 1 && dbs[0] == "main", "list databases");
    var objs = yield e.list_objects ("main");
    CatalogObject? tbl = null, view = null, idx = null, trg = null;
    foreach (var o in objs) {
        if (o.kind == ObjectKind.TABLE && o.name == "parent") tbl = o;
        if (o.kind == ObjectKind.VIEW && o.name == "parent_view") view = o;
        if (o.kind == ObjectKind.INDEX && o.name == "child_note_idx") idx = o;
        if (o.kind == ObjectKind.TRIGGER && o.name == "parent_trg") trg = o;
        ok (!o.name.has_prefix ("sqlite_"), "internal object hidden " + o.name);
    }
    ok (tbl != null && tbl.row_estimate == 2, "table with row count");
    ok (view != null, "view listed");
    ok (idx != null && idx.parent == "child", "index with parent");
    ok (trg != null && trg.parent == "parent", "trigger with parent");
    var p = yield e.describe_table ("main", "parent");
    ok (p.columns.size == 6, "describe columns");
    var id = col (p, "id");
    ok (id.primary_key && id.auto_increment && !id.nullable && id.data_type == "INTEGER", "autoincrement pk");
    ok (!col (p, "code").nullable && col (p, "qty").default_expr == "5" && col (p, "price").default_expr == "1.5", "not null and defaults");
    eq (col (p, "created").default_expr, "CURRENT_TIMESTAMP", "keyword default");
    ok (p.checks.length == 1 && p.checks[0] == "qty >= 0", "check extracted, checked_at column ignored");
    bool unique_found = false;
    foreach (var ix in p.indexes) if (ix.unique && ix.columns.length == 1 && ix.columns[0] == "code") unique_found = true;
    ok (unique_found, "unique constraint index");
    var ch = yield e.describe_table ("main", "child");
    string[] pk = ch.primary_key ();
    ok (pk.length == 2 && pk[0] == "a" && pk[1] == "b", "composite pk");
    ok (!col (ch, "a").auto_increment, "composite pk not autoincrement");
    ok (ch.foreign_keys.size == 1 && ch.foreign_keys[0].ref_table == "parent" && ch.foreign_keys[0].columns[0] == "parent_id" && ch.foreign_keys[0].ref_columns[0] == "id" && ch.foreign_keys[0].on_delete == "CASCADE", "foreign key");
    IndexInfo? note_ix = null;
    foreach (var ix in ch.indexes) if (ix.name == "child_note_idx") note_ix = ix;
    ok (note_ix != null && string.joinv (",", note_ix.columns) == "note,parent_id" && !note_ix.unique, "index columns");
    eq (col (ch, "note").default_expr, "'n/a'", "text default");
    bool missing = false;
    try {
        yield e.describe_table ("main", "ghost");
    } catch (RemoteError.SERVER err) {
        missing = true;
    }
    ok (missing, "describe missing table");
    string vdef = yield e.object_definition (view);
    ok (vdef.has_prefix ("CREATE VIEW parent_view") && vdef.has_suffix (";"), "view definition");
    string tdef = yield e.object_definition (trg);
    ok (tdef.contains ("BEGIN UPDATE parent") && tdef.has_suffix ("END;"), "trigger definition");

    var copy = ch.copy ();
    copy.name = "child_copy";
    foreach (var ix in copy.indexes) ix.name = ix.name + "_copy";
    string ddl = e.create_table_sql (copy);
    ok (ddl.contains ("PRIMARY KEY (\"a\", \"b\")") && ddl.contains ("REFERENCES \"parent\" (\"id\") ON DELETE CASCADE"), "create table sql content");
    yield TransferRun.script (e, ddl);
    var ch2 = yield e.describe_table ("main", "child_copy");
    ok (same_table (ch, ch2), "create table round trip composite");
    var pcopy = p.copy ();
    pcopy.name = "parent_copy";
    var keep = new Gee.ArrayList<IndexInfo> ();
    foreach (var ix in pcopy.indexes) if (!ix.name.has_prefix ("sqlite_autoindex")) keep.add (ix);
    pcopy.indexes = keep;
    string pddl = e.create_table_sql (pcopy);
    ok (pddl.contains ("\"id\" INTEGER PRIMARY KEY AUTOINCREMENT") && pddl.contains ("CHECK (qty >= 0)"), "create table sql autoincrement and check");
    yield TransferRun.script (e, pddl);
    var p2 = yield e.describe_table ("main", "parent_copy");
    ok (same_columns (p, p2) && p2.checks.length == 1, "create table round trip parent");

    yield test_sqlite_alter (e);
    yield e.close_async ();
    ok (!e.connected, "closed");

    var ro = yield open_sqlite (path, true);
    bool ro_failed = false;
    try {
        yield ro.execute ("INSERT INTO t (name) VALUES ('x')");
    } catch (RemoteError.SERVER err) {
        ro_failed = err.message.contains ("readonly");
    }
    ok (ro_failed, "read only connection refuses writes");
    yield ro.close_async ();
    string no_file = scratch_file ("absent.db");
    bad.file_path = no_file;
    bad.read_only = true;
    failed_open = false;
    try {
        yield new SqliteEngine (bad).open (null);
    } catch (RemoteError.CONNECT err) {
        failed_open = true;
    }
    ok (failed_open && !FileUtils.test (no_file, FileTest.EXISTS), "read only does not create files");
    bool unsupported = false;
    try {
        yield ro.list_users ();
    } catch (RemoteError.UNSUPPORTED err) {
        unsupported = true;
    }
    ok (unsupported, "users unsupported on sqlite");
    eq (ro.explain_sql ("SELECT 1", false), "EXPLAIN QUERY PLAN SELECT 1", "explain sql");
    eq (ro.qualified ("main", "a\"b"), "\"a\"\"b\"", "qualified main");
    eq (ro.qualified ("aux", "t"), "\"aux\".\"t\"", "qualified attached");
}

bool same_columns (TableInfo a, TableInfo b) {
    if (a.columns.size != b.columns.size) return false;
    for (int i = 0; i < a.columns.size; i++) {
        var x = a.columns[i];
        var y = b.columns[i];
        if (x.name != y.name || x.data_type != y.data_type || x.nullable != y.nullable || x.default_expr != y.default_expr || x.primary_key != y.primary_key || x.auto_increment != y.auto_increment) {
            stderr.printf ("  column %s differs: %s/%s %s/%s [%s]/[%s]\n", x.name, x.data_type, y.data_type, x.nullable.to_string (), y.nullable.to_string (), x.default_expr, y.default_expr);
            return false;
        }
    }
    return true;
}

bool same_table (TableInfo a, TableInfo b) {
    if (!same_columns (a, b)) return false;
    if (a.foreign_keys.size != b.foreign_keys.size) return false;
    int ia = 0, ib = 0;
    foreach (var ix in a.indexes) if (!ix.primary) ia++;
    foreach (var ix in b.indexes) if (!ix.primary) ib++;
    return ia == ib && string.joinv (",", a.checks) == string.joinv (",", b.checks);
}

class TransferRun {
    public static async void script (Engine e, string sql) throws Error {
        yield RemoteTransfer.run_script (e, sql);
    }

    public static async void apply (Engine e, string[] sql) throws Error {
        foreach (string s in sql) yield e.execute (s);
    }
}

Gee.ArrayList<ColumnChange> changes () {
    return new Gee.ArrayList<ColumnChange> ();
}

async void test_sqlite_alter (SqliteEngine e) throws Error {
    yield e.execute ("CREATE TABLE al (id INTEGER PRIMARY KEY, name TEXT, qty TEXT, extra TEXT)");
    yield e.execute ("CREATE INDEX al_name_idx ON al (name)");
    yield e.execute ("INSERT INTO al VALUES (1, 'one', '10', 'x'), (2, 'two', '20', 'y')");
    var before = yield e.describe_table ("main", "al");
    var after = before.copy ();
    after.name = "al2";
    var sql = e.alter_table_sql (before, after, changes ());
    ok (sql.length == 1 && sql[0] == "ALTER TABLE \"al\" RENAME TO \"al2\";", "rename table sql");
    yield TransferRun.apply (e, sql);
    ok ((yield count (e, "al2")) == 2, "rename table applied");

    before = yield e.describe_table ("main", "al2");
    after = before.copy ();
    var ren = after.find ("name");
    ren.name = "title";
    var chs = changes ();
    chs.add (new ColumnChange ("name", ren));
    sql = e.alter_table_sql (before, after, chs);
    ok (string.joinv ("\n", sql).contains ("RENAME COLUMN \"name\" TO \"title\"") && !string.joinv ("\n", sql).contains ("_sdb_new_"), "rename column without rebuild");
    yield TransferRun.apply (e, sql);
    var d = yield e.describe_table ("main", "al2");
    ok (d.find ("title") != null && d.find ("name") == null, "rename column applied");

    before = d;
    after = before.copy ();
    var added = new ColumnInfo ();
    added.name = "added";
    added.data_type = "INTEGER";
    added.default_expr = "7";
    after.columns.add (added);
    chs = changes ();
    chs.add (new ColumnChange (null, added));
    sql = e.alter_table_sql (before, after, chs);
    ok (sql.length == 1 && sql[0].contains ("ADD COLUMN \"added\" INTEGER DEFAULT 7"), "add column sql");
    yield TransferRun.apply (e, sql);
    var r = yield e.execute ("SELECT added FROM al2 WHERE id = 1");
    ok (r.rows[0].get (0).as_int () == 7, "add column default applied");

    before = yield e.describe_table ("main", "al2");
    after = before.copy ();
    after.columns.remove (after.find ("extra"));
    chs = changes ();
    chs.add (new ColumnChange ("extra", null));
    sql = e.alter_table_sql (before, after, chs);
    ok (sql.length == 1 && sql[0].contains ("DROP COLUMN \"extra\""), "drop column sql");
    yield TransferRun.apply (e, sql);
    ok ((yield e.describe_table ("main", "al2")).find ("extra") == null, "drop column applied");

    before = yield e.describe_table ("main", "al2");
    after = before.copy ();
    var q = after.find ("qty");
    q.data_type = "INTEGER";
    q.nullable = false;
    q.default_expr = "0";
    chs = changes ();
    chs.add (new ColumnChange ("qty", q));
    sql = e.alter_table_sql (before, after, chs);
    string joined = string.joinv ("\n", sql);
    ok (joined.contains ("_sdb_new_al2") && joined.contains ("INSERT INTO") && joined.contains ("DROP TABLE \"al2\""), "type change rebuild");
    ok (joined.contains ("CREATE INDEX \"al_name_idx\""), "rebuild recreates index");
    yield TransferRun.apply (e, sql);
    d = yield e.describe_table ("main", "al2");
    ok (d.find ("qty").data_type == "INTEGER" && !d.find ("qty").nullable, "type change applied");
    r = yield e.execute ("SELECT typeof(qty), qty, title FROM al2 ORDER BY id");
    ok (r.rows.size == 2 && r.rows[1].get (0).to_string () == "integer" && r.rows[1].get (1).as_int () == 20 && r.rows[1].get (2).to_string () == "two", "rebuild keeps data");
    bool has_index = false;
    foreach (var ix in d.indexes) if (ix.name == "al_name_idx") has_index = true;
    ok (has_index, "index survives rebuild");
    r = yield e.execute ("PRAGMA foreign_keys");
    ok (r.rows[0].get (0).as_int () == 1, "foreign keys back on after rebuild");

    before = d;
    after = before.copy ();
    after.find ("id").primary_key = false;
    after.find ("id").auto_increment = false;
    after.find ("title").primary_key = true;
    after.find ("title").nullable = false;
    after.find ("id").primary_key = true;
    chs = changes ();
    sql = e.alter_table_sql (before, after, chs);
    ok (string.joinv ("\n", sql).contains ("PRIMARY KEY (\"id\", \"title\")"), "pk change rebuild sql");
    yield TransferRun.apply (e, sql);
    d = yield e.describe_table ("main", "al2");
    ok (d.primary_key ().length == 2, "pk change applied");
    ok ((yield count (e, "al2")) == 2, "pk change keeps rows");

    before = d;
    after = before.copy ();
    var nix = new IndexInfo ();
    nix.name = "al_qty_idx";
    nix.columns = { "qty" };
    nix.unique = true;
    after.indexes.add (nix);
    IndexInfo? old_ix = null;
    foreach (var ix in after.indexes) if (ix.name == "al_name_idx") old_ix = ix;
    after.indexes.remove (old_ix);
    sql = e.alter_table_sql (before, after, changes ());
    ok (sql.length == 2 && sql[0].has_prefix ("DROP INDEX") && sql[1].has_prefix ("CREATE UNIQUE INDEX"), "index add and drop sql");
    yield TransferRun.apply (e, sql);
    d = yield e.describe_table ("main", "al2");
    bool has_new = false, has_old = false;
    foreach (var ix in d.indexes) {
        if (ix.name == "al_qty_idx" && ix.unique) has_new = true;
        if (ix.name == "al_name_idx") has_old = true;
    }
    ok (has_new && !has_old, "index change applied");

    before = d;
    after = before.copy ();
    after.columns.remove (after.find ("qty"));
    foreach (var ix in after.indexes.to_array ()) if (ix.name == "al_qty_idx") after.indexes.remove (ix);
    chs = changes ();
    chs.add (new ColumnChange ("qty", null));
    sql = e.alter_table_sql (before, after, chs);
    ok (sql[0].has_prefix ("DROP INDEX"), "index dropped before its column");
    yield TransferRun.apply (e, sql);
    ok ((yield e.describe_table ("main", "al2")).find ("qty") == null, "drop indexed column applied");
    ok (e.alter_table_sql (d, d.copy (), changes ()).length == 0, "no change no sql");
}

class Target {
    public Engine e;
    public string label;
    public string schema;
    public string text_type;
    public string int_type;

    public Target (Engine e, string label, string schema) {
        this.e = e;
        this.label = label;
        this.schema = schema;
        text_type = e.kind == EngineKind.MYSQL ? "VARCHAR(100)" : "TEXT";
        int_type = "INTEGER";
    }

    public string t (string name) {
        return e.qualified (schema, name);
    }
}

async Gee.ArrayList<Row> load (Target g, string sql) throws Error {
    var r = yield g.e.execute (sql);
    return r.rows;
}

async void test_pending (Target g) throws Error {
    var e = g.e;
    string L = g.label + " ";
    yield e.execute ("DROP TABLE IF EXISTS " + g.t ("cl_people"));
    yield e.execute ("DROP TABLE IF EXISTS " + g.t ("cl_pairs"));
    yield e.execute ("DROP TABLE IF EXISTS " + g.t ("cl_nopk"));
    yield e.execute ("CREATE TABLE %s (id %s PRIMARY KEY, name %s, qty %s DEFAULT 5, note %s)".printf (g.t ("cl_people"), g.int_type, g.text_type, g.int_type, g.text_type));
    yield e.execute ("CREATE TABLE %s (a %s NOT NULL, b %s NOT NULL, v %s, PRIMARY KEY (a, b))".printf (g.t ("cl_pairs"), g.int_type, g.int_type, g.text_type));
    yield e.execute ("CREATE TABLE %s (x %s)".printf (g.t ("cl_nopk"), g.int_type));
    yield e.execute ("INSERT INTO %s (id, name, qty, note) VALUES (1, 'Ann', 1, 'n1'), (2, 'Bob', 2, 'n2'), (3, 'Cy', 3, 'n3'), (4, 'Di''s', 4, NULL)".printf (g.t ("cl_people")));
    yield e.execute ("INSERT INTO %s VALUES (1, 1, 'a'), (1, 2, 'b'), (2, 1, 'c')".printf (g.t ("cl_pairs")));
    string sel = "SELECT id, name, qty, note FROM %s ORDER BY id".printf (g.t ("cl_people"));
    var rows = yield load (g, sel);
    ok (rows.size == 4, L + "loaded rows");
    var pc = new PendingChanges (g.schema, "cl_people", { "id", "name", "qty", "note" }, { "id" });
    int signals = 0;
    pc.changed.connect (() => signals++);
    ok (pc.editable && pc.is_empty (), L + "pending empty");
    pc.set_value (0, 1, rows[0].get (1), new DbValue.text ("Zed"));
    pc.set_value (1, 3, rows[1].get (3), new DbValue.null ());
    ok (pc.count () == 2 && pc.row_edited (0) && pc.edited (0, 1).to_string () == "Zed", L + "edits recorded");
    pc.set_value (0, 2, rows[0].get (2), new DbValue.int (99));
    pc.set_value (0, 2, rows[0].get (2), rows[0].get (2).copy ());
    ok (pc.count () == 2 && pc.edited (0, 2) == null, L + "revert to original clears edit");
    pc.mark_deleted (2);
    int ins = pc.add_insert ();
    pc.set_insert_value (ins, 0, new DbValue.int (10));
    pc.set_insert_value (ins, 1, new DbValue.text ("New"));
    ok (pc.count () == 4 && pc.is_deleted (2), L + "delete and insert counted");
    ok (signals >= 6, L + "changed signal");
    var stmts = pc.statements (e, rows);
    ok (stmts.size == 4, L + "statement count");
    ok (stmts[0].sql.has_prefix ("DELETE FROM") && stmts[3].sql.has_prefix ("INSERT INTO"), L + "statement order");
    string ph1 = e.placeholder (1);
    string ph2 = e.placeholder (2);
    eq (stmts[1].sql, "UPDATE %s SET %s = %s WHERE %s = %s".printf (g.t ("cl_people"), e.quote_ident ("name"), ph1, e.quote_ident ("id"), ph2), L + "update sql by pk");
    ok (!stmts[3].sql.contains (e.quote_ident ("qty")), L + "insert omits null columns");
    string pv = stmts[1].preview (e);
    ok (pv.contains ("'Zed'") && pv.has_suffix (" = 1"), L + "preview literal " + pv);
    ok (stmts[2].preview (e).contains ("NULL"), L + "preview null");
    int n = yield pc.apply (e, rows);
    ok (n == 4 && pc.is_empty (), L + "apply returns count and clears");
    rows = yield load (g, sel);
    ok (rows.size == 4, L + "row count after apply");
    ok (rows[0].get (1).to_string () == "Zed" && rows[1].get (3).is_null, L + "updates applied");
    ok (rows[2].get (0).as_int () == 4 && rows[3].get (0).as_int () == 10, L + "delete and insert applied");
    ok (rows[3].get (2).as_int () == 5 && rows[3].get (3).is_null, L + "insert default applied");

    var pp = new PendingChanges (g.schema, "cl_pairs", { "a", "b", "v" }, { "a", "b" });
    var prow = yield load (g, "SELECT a, b, v FROM %s ORDER BY a, b".printf (g.t ("cl_pairs")));
    pp.set_value (1, 2, prow[1].get (2), new DbValue.text ("B!"));
    pp.set_value (2, 1, prow[2].get (1), new DbValue.int (5));
    var ps = pp.statements (e, prow);
    ok (ps[0].sql.contains (" AND ") && ps[0].params.length == 3, L + "composite where");
    yield pp.apply (e, prow);
    prow = yield load (g, "SELECT a, b, v FROM %s ORDER BY a, b".printf (g.t ("cl_pairs")));
    ok (prow[1].get (2).to_string () == "B!" && prow[2].get (1).as_int () == 5 && prow[0].get (2).to_string () == "a", L + "composite update applied");

    var np = new PendingChanges (g.schema, "cl_nopk", { "x" }, {});
    ok (!np.editable, L + "no pk not editable");
    np.add_insert ();
    bool refused = false;
    try {
        np.statements (e, new Gee.ArrayList<Row> ());
    } catch (RemoteError.UNSUPPORTED err) {
        refused = err.message.contains ("primary key");
    }
    ok (refused, L + "no pk refused");

    rows = yield load (g, sel);
    pc.set_value (1, 1, rows[1].get (1), new DbValue.text ("Keep?"));
    pc.set_value (0, 1, rows[0].get (1), new DbValue.text ("Lost"));
    yield e.execute ("DELETE FROM %s WHERE id = 1".printf (g.t ("cl_people")));
    bool conflict = false;
    try {
        yield pc.apply (e, rows);
    } catch (RemoteError.CONFLICT err) {
        conflict = err.message.contains ("was deleted on the server") && err.message.contains ("id 1");
    }
    ok (conflict, L + "deleted row conflict detected");
    ok (!pc.is_empty (), L + "pending kept after failure");
    var after = yield load (g, sel);
    ok (after[0].get (1).to_string () == "Bob", L + "rollback leaves other rows unchanged");
    pc.discard ();
    ok (pc.is_empty (), L + "discard");

    rows = yield load (g, sel);
    yield e.execute ("UPDATE %s SET id = 11 WHERE id = 10".printf (g.t ("cl_people")));
    pc.set_value (rows.size - 1, 1, rows[rows.size - 1].get (1), new DbValue.text ("Moved"));
    conflict = false;
    try {
        yield pc.apply (e, rows);
    } catch (RemoteError.CONFLICT err) {
        conflict = true;
    }
    ok (conflict, L + "pk changed underneath detected");
    pc.discard ();

    rows = yield load (g, sel);
    pc.set_value (0, 1, rows[0].get (1), new DbValue.text ("Mine"));
    yield e.execute ("UPDATE %s SET note = 'theirs' WHERE id = 2".printf (g.t ("cl_people")));
    conflict = false;
    string cmsg = "";
    try {
        yield pc.apply (e, rows);
    } catch (RemoteError.CONFLICT err) {
        conflict = true;
        cmsg = err.message;
    }
    ok (conflict, L + "other column changed underneath detected");
    ok (cmsg.contains ("note is now 'theirs'") && cmsg.contains ("id 2") && cmsg.contains ("Nothing was saved"), L + "conflict message names column and values: " + cmsg);
    after = yield load (g, sel);
    ok (after[0].get (1).to_string () == "Bob" && after[0].get (3).to_string () == "theirs", L + "concurrent change kept, mine not written");
    ok (!pc.is_empty (), L + "pending kept after conflict");
    pc.discard ();

    rows = yield load (g, sel);
    pc.set_value (0, 1, rows[0].get (1), new DbValue.text ("Bob2"));
    pc.set_value (1, 2, rows[1].get (2), new DbValue.int (44));
    int applied = yield pc.apply (e, rows);
    ok (applied == 2, L + "apply after reload succeeds");
    after = yield load (g, sel);
    ok (after[0].get (1).to_string () == "Bob2", L + "reloaded edit written");

    rows = yield load (g, sel);
    int ins2 = pc.add_insert ();
    pc.set_insert_value (ins2, 0, new DbValue.int (2));
    pc.set_insert_value (ins2, 1, new DbValue.text ("dup"));
    pc.set_value (0, 1, rows[0].get (1), new DbValue.text ("Rolled"));
    bool dup = false;
    try {
        yield pc.apply (e, rows);
    } catch (Error err) {
        dup = true;
    }
    ok (dup, L + "duplicate key fails");
    after = yield load (g, sel);
    ok (after[0].get (1).to_string () == "Bob2", L + "transaction rolled back on insert failure");
    pc.remove_insert (0);
    pc.discard ();
}

DataTable people_data () {
    var dt = new DataTable ("in");
    dt.columns = { "id", "name", "qty", "note" };
    dt.add_row ({ new DbValue.int (100), new DbValue.text ("I1"), new DbValue.text (""), new DbValue.text ("x") });
    dt.add_row ({ new DbValue.int (101), new DbValue.text ("I2"), new DbValue.int (3), new DbValue.text ("") });
    return dt;
}

async void test_transfer (Target g) throws Error {
    var e = g.e;
    string L = g.label + " ";
    int64 base_count = yield count (e, g.t ("cl_people"));
    var dt = people_data ();
    int64 progress_seen = -1;
    int64 n = yield RemoteTransfer.import_rows (e, g.schema, "cl_people", dt, { "id", "name", "qty", "note" }, null, (v) => progress_seen = v);
    ok (n == 2 && progress_seen == 2, L + "import rows");
    var r = yield e.execute ("SELECT qty, note FROM %s WHERE id = 100".printf (g.t ("cl_people")));
    ok (r.rows[0].get (0).is_null && r.rows[0].get (1).to_string () == "x", L + "empty imported as null");
    r = yield e.execute ("SELECT note FROM %s WHERE id = 101".printf (g.t ("cl_people")));
    ok (r.rows[0].get (0).is_null, L + "empty text imported as null");
    var bad = new DataTable ("bad");
    bad.columns = { "id", "name" };
    bad.add_row ({ new DbValue.int (200), new DbValue.text ("ok") });
    bad.add_row ({ new DbValue.int (100), new DbValue.text ("dup") });
    bool failed_import = false;
    try {
        yield RemoteTransfer.import_rows (e, g.schema, "cl_people", bad, { "id", "name" }, null);
    } catch (RemoteError.SERVER err) {
        failed_import = err.message.has_prefix ("Row 2 could not be imported");
    }
    ok (failed_import, L + "failing import row reported");
    yield e.execute ("DROP TABLE IF EXISTS " + g.t ("cl_defaults"));
    yield e.execute ("CREATE TABLE %s (id %s PRIMARY KEY, stock %s NOT NULL DEFAULT 7, label %s)".printf (g.t ("cl_defaults"), g.int_type, g.int_type, g.text_type));
    var dd = new DataTable ("dd");
    dd.columns = { "id", "stock", "label" };
    dd.add_row ({ new DbValue.int (1), new DbValue.text (""), new DbValue.text ("") });
    dd.add_row ({ new DbValue.int (2), new DbValue.int (3), new DbValue.text ("x") });
    int64 dn = yield RemoteTransfer.import_rows (e, g.schema, "cl_defaults", dd, { "id", "stock", "label" }, null);
    r = yield e.execute ("SELECT stock, label FROM %s ORDER BY id".printf (g.t ("cl_defaults")));
    ok (dn == 2 && r.rows[0].get (0).as_int () == 7 && r.rows[0].get (1).is_null && r.rows[1].get (0).as_int () == 3, L + "empty value in not null column takes its default");
    yield e.execute ("DROP TABLE " + g.t ("cl_defaults"));
    ok ((yield count (e, g.t ("cl_people"))) == base_count + 2, L + "failed import rolled back");
    bool none = false;
    try {
        yield RemoteTransfer.import_rows (e, g.schema, "cl_people", bad, { "", "" }, null);
    } catch (RemoteError.UNSUPPORTED err) {
        none = true;
    }
    ok (none, L + "import needs a column");
    var skip = new DataTable ("skip");
    skip.columns = { "ignored", "id", "name" };
    skip.add_row ({ new DbValue.text ("zzz"), new DbValue.int (300), new DbValue.text ("mapped") });
    yield RemoteTransfer.import_rows (e, g.schema, "cl_people", skip, { "", "id", "name" }, null);
    r = yield e.execute ("SELECT name FROM %s WHERE id = 300".printf (g.t ("cl_people")));
    ok (r.rows.size == 1 && r.rows[0].get (0).to_string () == "mapped", L + "import column mapping");

    int64 total = yield count (e, g.t ("cl_people"));
    string csv = scratch_file (g.label + "-people.csv");
    n = yield RemoteTransfer.export_table (e, g.schema, "cl_people", File.new_for_path (csv), ExportFormat.CSV, null);
    ok (n == total, L + "csv export count");
    var back = Csv.load (csv);
    ok (back.columns.length == 4 && back.columns[0] == "id" && back.rows.size == total, L + "csv parses back");
    string json = scratch_file (g.label + "-people.json");
    yield RemoteTransfer.export_table (e, g.schema, "cl_people", File.new_for_path (json), ExportFormat.JSON, null);
    string jtext;
    FileUtils.get_contents (json, out jtext);
    var jl = JsonIO.parse (jtext, "people");
    ok (jl.size == 1 && jl[0].rows.size == total, L + "json parses back");
    var jparser = new Json.Parser ();
    jparser.load_from_data (jtext);
    var first = jparser.get_root ().get_array ().get_object_element (0);
    ok (first.has_member ("note") && first.get_int_member ("id") > 0, L + "json typed values");
    string sqlf = scratch_file (g.label + "-people.sql");
    yield RemoteTransfer.export_table (e, g.schema, "cl_people", File.new_for_path (sqlf), ExportFormat.SQL, null);
    ok (!FileUtils.test (sqlf + ".part", FileTest.EXISTS), L + "sql part file removed");
    string stext;
    FileUtils.get_contents (sqlf, out stext);
    ok (stext.has_prefix ("CREATE TABLE") && stext.contains ("INSERT INTO"), L + "sql export content");
    yield e.execute ("DROP TABLE " + g.t ("cl_people"));
    yield RemoteTransfer.run_script (e, stext);
    ok ((yield count (e, g.t ("cl_people"))) == total, L + "sql export replays");
    r = yield e.execute ("SELECT name FROM %s WHERE id = 4".printf (g.t ("cl_people")));
    ok (r.rows[0].get (0).to_string () == "Di's", L + "quote survives sql round trip");
    string q = scratch_file (g.label + "-query.csv");
    n = yield RemoteTransfer.export_query (e, "SELECT id, name FROM %s WHERE id > 100".printf (g.t ("cl_people")), File.new_for_path (q), ExportFormat.CSV, "x", null);
    var qb = Csv.load (q);
    ok (n == qb.rows.size && n >= 2 && qb.columns.length == 2, L + "export query");
}

async void test_sqlite_dump () throws Error {
    string src = scratch_file ("dump-src.db");
    var e = yield open_sqlite (src);
    yield e.execute ("CREATE TABLE z_parent (id INTEGER PRIMARY KEY, name TEXT)");
    yield e.execute ("CREATE TABLE a_child (id INTEGER PRIMARY KEY, parent_id INTEGER NOT NULL REFERENCES z_parent (id), v BLOB, r REAL)");
    yield e.execute ("CREATE INDEX a_child_parent ON a_child (parent_id)");
    yield e.execute ("CREATE VIEW v_all AS SELECT c.id, p.name FROM a_child c JOIN z_parent p ON p.id = c.parent_id");
    yield e.execute ("CREATE TRIGGER a_child_trg AFTER INSERT ON a_child BEGIN UPDATE z_parent SET name = name WHERE id = NEW.parent_id; END");
    yield e.execute ("WITH RECURSIVE c(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM c WHERE x < 3000) INSERT INTO z_parent SELECT x, 'p;' || x FROM c");
    yield e.execute ("WITH RECURSIVE c(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM c WHERE x < 4500) INSERT INTO a_child SELECT x, (x % 3000) + 1, X'00FF', x / 3.0 FROM c");
    var infos = new Gee.ArrayList<TableInfo> ();
    infos.add (yield e.describe_table ("main", "a_child"));
    infos.add (yield e.describe_table ("main", "z_parent"));
    var sorted = RemoteTransfer.dependency_order (infos);
    ok (sorted[0].name == "z_parent", "dependency order parent first");
    string dump = scratch_file ("dump.sql");
    int64 last = 0;
    int64 n = yield RemoteTransfer.dump_schema (e, "main", File.new_for_path (dump), true, null, (v) => last = v);
    ok (n == 7500 && last == 7500, "dump row count");
    string text;
    FileUtils.get_contents (dump, out text);
    ok (text.index_of ("CREATE TABLE \"z_parent\"") < text.index_of ("CREATE TABLE \"a_child\""), "dump orders parent first");
    ok (text.contains ("CREATE INDEX") && text.contains ("CREATE VIEW v_all") && text.contains ("CREATE TRIGGER a_child_trg"), "dump has index view trigger");
    var fresh = yield open_sqlite (scratch_file ("dump-dst.db"));
    yield RemoteTransfer.run_script (fresh, text);
    ok ((yield count (fresh, "z_parent")) == 3000 && (yield count (fresh, "a_child")) == 4500, "dump replays counts");
    ok ((yield count (fresh, "v_all")) == 4500, "dump replays view");
    var r = yield fresh.execute ("SELECT hex(v), r, (SELECT name FROM z_parent WHERE id = 7) FROM a_child WHERE id = 10");
    ok (r.rows[0].get (0).to_string () == "00FF" && (r.rows[0].get (1).as_double () - 10 / 3.0).abs () < 1e-9 && r.rows[0].get (2).to_string () == "p;7", "dump preserves values");
    var objs = yield fresh.list_objects ("main");
    bool trig = false;
    foreach (var o in objs) if (o.kind == ObjectKind.TRIGGER) trig = true;
    ok (trig, "dump replays trigger");
    string schema_only = scratch_file ("schema.sql");
    n = yield RemoteTransfer.dump_schema (e, "main", File.new_for_path (schema_only), false, null);
    FileUtils.get_contents (schema_only, out text);
    ok (n == 0 && !text.contains ("INSERT INTO"), "schema only dump");
    yield e.close_async ();
    yield fresh.close_async ();
}

async void test_server_dump (Target g, string dump_schema, string recreate_sql, string drop_sql) throws Error {
    var e = g.e;
    string L = g.label + " ";
    yield e.execute (drop_sql);
    yield e.execute (recreate_sql);
    yield e.execute ("CREATE TABLE %s (id INTEGER PRIMARY KEY, name %s)".printf (e.qualified (dump_schema, "z_parent"), g.text_type));
    yield e.execute ("CREATE TABLE %s (id INTEGER PRIMARY KEY, parent_id INTEGER NOT NULL, note %s, FOREIGN KEY (parent_id) REFERENCES %s (id))".printf (e.qualified (dump_schema, "a_child"), g.text_type, e.qualified (dump_schema, "z_parent")));
    yield e.execute ("CREATE VIEW %s AS SELECT id FROM %s".printf (e.qualified (dump_schema, "v_parent"), e.qualified (dump_schema, "z_parent")));
    for (int i = 1; i <= 300; i++) yield e.execute ("INSERT INTO %s VALUES (%d, 'p%d')".printf (e.qualified (dump_schema, "z_parent"), i, i));
    yield e.execute ("INSERT INTO %s SELECT id, id, 'it''s' FROM %s".printf (e.qualified (dump_schema, "a_child"), e.qualified (dump_schema, "z_parent")));
    string dump = scratch_file (g.label + "-dump.sql");
    int64 n = yield RemoteTransfer.dump_schema (e, dump_schema, File.new_for_path (dump), true, null);
    ok (n == 600, L + "dump row count");
    string text;
    FileUtils.get_contents (dump, out text);
    ok (text.index_of ("z_parent") < text.index_of ("a_child"), L + "dump dependency order");
    yield e.execute (drop_sql);
    yield e.execute (recreate_sql);
    yield RemoteTransfer.run_script (e, text);
    ok ((yield count (e, e.qualified (dump_schema, "a_child"))) == 300 && (yield count (e, e.qualified (dump_schema, "z_parent"))) == 300, L + "dump replays counts");
    ok ((yield count (e, e.qualified (dump_schema, "v_parent"))) == 300, L + "dump replays view");
    var info = yield e.describe_table (dump_schema, "a_child");
    ok (info.foreign_keys.size == 1, L + "dump replays foreign key");
    yield e.execute (drop_sql);
}

async void cleanup (Target g) throws Error {
    foreach (string t in new string[] { "cl_people", "cl_pairs", "cl_nopk" }) yield g.e.execute ("DROP TABLE IF EXISTS " + g.t (t));
}

ConnectionConfig pg_config () {
    var c = new ConnectionConfig ();
    c.kind = EngineKind.POSTGRESQL;
    c.host = env ("SDB_PG_HOST", "127.0.0.1");
    c.port = int.parse (env ("SDB_PG_PORT"));
    c.user = "sdb_scram";
    c.database = env ("SDB_PG_DB", "sdb_test");
    c.ssl_mode = SslMode.DISABLE;
    c.connect_timeout = 5;
    c.id = "pg-test";
    return c;
}

ConnectionConfig my_config () {
    var c = new ConnectionConfig ();
    c.kind = EngineKind.MYSQL;
    c.host = env ("SDB_MY_HOST", "127.0.0.1");
    c.port = int.parse (env ("SDB_MY_PORT"));
    c.user = env ("SDB_MY_NATIVE_USER", "sdb_native");
    c.ssl_mode = SslMode.DISABLE;
    c.connect_timeout = 5;
    c.id = "my-test";
    return c;
}

string servers_run;

async void test_servers () throws Error {
    if (env ("SDB_PG_PORT") != "") {
        var s = new ClientSession (pg_config ());
        yield s.connect ("scrampass", null);
        string ns = "cl_%d".printf ((int) (Random.next_int () % 1000000));
        yield s.engine.execute ("DROP SCHEMA IF EXISTS %s CASCADE".printf (ns));
        yield s.engine.execute ("CREATE SCHEMA " + ns);
        var g = new Target (s.engine, "pg", ns);
        yield test_pending (g);
        yield test_transfer (g);
        yield cleanup (g);
        yield test_server_links (s.engine, ns, "pg");
        yield s.engine.execute ("DROP SCHEMA IF EXISTS %s CASCADE".printf (ns));
        string dn = ns + "_dump";
        yield test_server_dump (g, dn, "CREATE SCHEMA " + dn, "DROP SCHEMA IF EXISTS %s CASCADE".printf (dn));
        string info = yield ClientSession.test (pg_config (), "scrampass", null);
        ok (info.contains ("PostgreSQL") || info.contains ("database sdb_test"), "pg test connection summary " + info);
        bool bad = false;
        try {
            yield ClientSession.test (pg_config (), "wrong", null);
        } catch (RemoteError.AUTH err) {
            bad = true;
        }
        ok (bad, "pg test connection wrong password");
        yield s.disconnect ();
        ok (s.engine == null, "pg session disconnected");
        servers_run += " pg";
    }
    if (env ("SDB_MY_PORT") != "") {
        var s = new ClientSession (my_config ());
        yield s.connect (env ("SDB_MY_NATIVE_PASS"), null);
        string mdb = "sdb_client_%d".printf ((int) (Random.next_int () % 1000000));
        yield s.engine.execute ("DROP DATABASE IF EXISTS " + mdb);
        yield s.engine.execute ("CREATE DATABASE %s CHARACTER SET utf8mb4".printf (mdb));
        yield s.engine.use_database (mdb);
        var g = new Target (s.engine, "mysql", mdb);
        yield test_pending (g);
        yield test_transfer (g);
        yield cleanup (g);
        yield test_server_links (s.engine, mdb, "mysql");
        string mdump = mdb + "_dump";
        yield test_server_dump (g, mdump, "CREATE DATABASE " + mdump, "DROP DATABASE IF EXISTS " + mdump);
        yield s.engine.execute ("DROP DATABASE IF EXISTS " + mdb);
        string info = yield ClientSession.test (my_config (), env ("SDB_MY_NATIVE_PASS"), null);
        ok (info.contains ("not encrypted"), "mysql test connection summary " + info);
        yield s.disconnect ();
        servers_run += " mysql";
    }
}

bool pid_alive (string pid) {
    if (pid == "") return false;
    string stat;
    try {
        if (!FileUtils.get_contents ("/proc/%s/stat".printf (pid), out stat)) return false;
    } catch (Error e) {
        return false;
    }
    int close_paren = stat.last_index_of (")");
    return close_paren > 0 && stat.length > close_paren + 2 && stat[close_paren + 2] != 'Z';
}

string ssh_status;

async void test_ssh () throws Error {
    if (env ("SDB_SSH_PORT") == "") return;
    string[] opts = { "-F", "/dev/null", "-o", "UserKnownHostsFile=" + env ("SDB_SSH_KNOWN"), "-o", "GlobalKnownHostsFile=/dev/null" };
    string tunneled = "";
    if (env ("SDB_PG_PORT") != "") {
        var c = pg_config ();
        c.ssh_enabled = true;
        c.ssh_host = "127.0.0.1";
        c.ssh_port = int.parse (env ("SDB_SSH_PORT"));
        c.ssh_user = env ("SDB_SSH_USER");
        c.ssh_key_file = env ("SDB_SSH_KEY");
        var s = new ClientSession (c);
        s.ssh_extra_options = opts;
        yield s.connect ("scrampass", null);
        ok (s.tunnel != null && s.tunnel.running && s.tunnel.local_port != c.port, "pg tunnel running on its own port");
        ok (s.engine.config.port == s.tunnel.local_port && s.engine.config.host == "127.0.0.1", "pg engine goes through tunnel");
        var r = yield s.engine.execute ("SELECT inet_server_port(), current_user");
        ok (r.rows[0].get (0).as_int () == c.port && r.rows[0].get (1).to_string () == "sdb_scram", "pg query through tunnel");
        string pid = s.tunnel.last_pid;
        ok (pid_alive (pid), "ssh child alive");
        var t = s.tunnel;
        yield s.disconnect ();
        for (int i = 0; i < 40 && pid_alive (pid); i++) yield sleep_ms (50);
        ok (!pid_alive (pid) && !t.running, "ssh child exited after disconnect");
        tunneled += " pg";
    }
    if (env ("SDB_MY_PORT") != "") {
        var c = my_config ();
        c.ssh_enabled = true;
        c.ssh_host = "127.0.0.1";
        c.ssh_port = int.parse (env ("SDB_SSH_PORT"));
        c.ssh_user = env ("SDB_SSH_USER");
        c.ssh_key_file = env ("SDB_SSH_KEY");
        var s = new ClientSession (c);
        s.ssh_extra_options = opts;
        yield s.connect (env ("SDB_MY_NATIVE_PASS"), null);
        var r = yield s.engine.execute ("SELECT @@port, 1 + 1");
        ok (r.rows[0].get (0).as_int () == c.port && r.rows[0].get (1).as_int () == 2, "mysql query through tunnel");
        string pid = s.tunnel.last_pid;
        yield s.disconnect ();
        for (int i = 0; i < 40 && pid_alive (pid); i++) yield sleep_ms (50);
        ok (!pid_alive (pid), "mysql ssh child exited");
        c.socket_path = env ("SDB_MY_SOCKET");
        s = new ClientSession (c);
        s.ssh_extra_options = opts;
        yield s.connect (env ("SDB_MY_NATIVE_PASS"), null);
        r = yield s.engine.execute ("SELECT 42");
        ok (r.rows[0].get (0).as_int () == 42, "mysql unix socket through tunnel");
        yield s.disconnect ();
        tunneled += " mysql";
    }
    var w = pg_config ();
    w.kind = env ("SDB_PG_PORT") != "" ? EngineKind.POSTGRESQL : EngineKind.MYSQL;
    w.ssh_enabled = true;
    w.ssh_host = "127.0.0.1";
    w.ssh_port = int.parse (env ("SDB_SSH_PORT"));
    w.ssh_user = env ("SDB_SSH_USER");
    w.ssh_key_file = env ("SDB_SSH_WRONG_KEY");
    var ws = new ClientSession (w);
    ws.ssh_extra_options = opts;
    string msg = "";
    try {
        yield ws.connect ("scrampass", null);
    } catch (RemoteError.CONNECT err) {
        msg = err.message;
    }
    ok (msg.has_prefix ("The SSH tunnel could not be opened") && msg.contains ("Permission denied"), "wrong key error: " + msg);
    ok (ws.tunnel == null && ws.engine == null, "wrong key leaves no tunnel");
    w.ssh_key_file = env ("SDB_SSH_KEY");
    w.ssh_port = SshTunnel.free_port ();
    ws = new ClientSession (w);
    ws.ssh_extra_options = opts;
    msg = "";
    try {
        yield ws.connect ("scrampass", null);
    } catch (RemoteError.CONNECT err) {
        msg = err.message;
    }
    ok (msg.contains ("Connection refused"), "unreachable ssh port error: " + msg);
    w.ssh_port = int.parse (env ("SDB_SSH_PORT"));
    w.port = SshTunnel.free_port ();
    ws = new ClientSession (w);
    ws.ssh_extra_options = opts;
    bool failed_db = false;
    try {
        yield ws.connect ("scrampass", null);
    } catch (RemoteError.CONNECT err) {
        failed_db = true;
    }
    ok (failed_db && ws.tunnel == null, "database behind tunnel down closes tunnel");
    ssh_status = "PROVEN:" + tunneled;
}

async void flush_links (Engine e, Database db) throws Error {
    var changes = new Gee.ArrayList<LinkChange> ();
    changes.add_all (db.link_changes);
    db.link_changes.clear ();
    foreach (var c in changes) {
        var l = db.linked[c.link.casefold ()];
        DbValue[] args;
        string sql = ServerLinks.statement (e, l, db.server_data[c.link.casefold ()], c, out args);
        if (Environment.get_variable ("SDB_TRACE") != null) {
            string[] a = {};
            foreach (var v in args) a += v.to_string ();
            print ("%s | %s\n", sql, string.joinv (",", a));
        }
        yield e.execute (sql, args);
    }
}

async void test_server_links (Engine e, string schema, string label) throws Error {
    string t = e.qualified (schema, "sl_items");
    yield e.execute ("DROP TABLE IF EXISTS " + t);
    yield e.execute ("CREATE TABLE %s (id INTEGER PRIMARY KEY, name VARCHAR(50), price NUMERIC(10,2), active BOOLEAN, added DATE)".printf (t));
    yield e.execute ("INSERT INTO %s (id, name, price, active, added) VALUES (1, 'Screw', 1.25, TRUE, '2026-01-05')".printf (t));
    yield e.execute ("INSERT INTO %s (id, name, price, active, added) VALUES (2, 'Washer', 0.10, FALSE, NULL)".printf (t));
    var db = Database.create (scratch_file ("links-%s.sdb".printf (label)));
    var tables = yield ServerLinks.tables (e, schema);
    ok (tables.contains ("sl_items"), label + " link lists server tables");
    var schemas = yield ServerLinks.schemas (e);
    ok (schemas.contains (schema), label + " link lists schema " + schema);
    var snap = yield ServerLinks.fetch (e, schema, "sl_items");
    ok (snap.key.length == 1 && snap.key[0] == "id", label + " link reads the primary key");
    Links.add_server (db, "conn-" + label, schema, "sl_items", "Items", snap);
    ok (db.table_names ().contains ("Items") && db.is_linked ("Items"), label + " linked server table listed");
    ok (db.count_rows ("Items") == 2, label + " linked server rows loaded");
    var def = db.load_table ("Items");
    ok (def.find ("active").field_type == FieldType.BOOLEAN, label + " boolean column type");
    ok (def.find ("added").field_type == FieldType.DATE, label + " date column type");
    ok (def.find ("price").field_type == FieldType.NUMBER, label + " numeric column type");
    eq (db.query ("SELECT name FROM Items WHERE active = 1").rows[0].get (0).to_string (), "Screw", label + " boolean values usable in queries");
    eq (db.query ("SELECT added FROM Items WHERE id = 1").rows[0].get (0).to_string (), "2026-01-05", label + " date values kept");
    db.exec ("UPDATE Items SET name = 'Bolt', price = 2.5 WHERE id = 1");
    db.exec ("INSERT INTO Items (id, name, price, active) VALUES (3, 'Nut', 0.5, 1)");
    db.exec ("DELETE FROM Items WHERE id = 2");
    ok (db.link_changes.size == 3, label + " edits queued for the server");
    yield flush_links (e, db);
    var r = yield e.execute ("SELECT id, name, price FROM %s ORDER BY id".printf (t));
    ok (r.rows.size == 2, label + " server has two rows after the edits");
    eq (r.rows[0].get (1).to_string (), "Bolt", label + " update written to the server");
    ok (r.rows[0].get (2).as_double () == 2.5, label + " number written to the server");
    eq (r.rows[1].get (1).to_string (), "Nut", label + " insert written to the server");
    yield e.execute ("UPDATE %s SET name = 'Hex Nut' WHERE id = 3".printf (t));
    db.server_data["items"] = yield ServerLinks.fetch (e, schema, "sl_items");
    Links.attach_all (db);
    db.invalidate ();
    eq (db.query ("SELECT name FROM Items WHERE id = 3").rows[0].get (0).to_string (), "Hex Nut", label + " refresh reads server changes");
    ok (db.link_changes.size == 0, label + " refresh does not queue edits");
    var q = db.query ("SELECT count(*) FROM Items WHERE price > 1");
    ok (q.rows[0].get (0).as_int () == 1, label + " linked server table joins local queries");
    Links.remove (db, "Items");
    ok (!db.table_names ().contains ("Items"), label + " server link removed");
    db.close ();
    yield e.execute ("DROP TABLE " + t);
}

async void run_all () throws Error {
    yield test_sqlite ();
    yield test_sqlite_dump ();
    var s = new ClientSession (new ConnectionConfig ());
    s.config.kind = EngineKind.SQLITE;
    s.config.file_path = scratch_file ("pending.db");
    yield s.connect (null, null);
    var g = new Target (s.engine, "sqlite", "main");
    yield test_pending (g);
    yield test_transfer (g);
    yield cleanup (g);
    yield test_server_links (s.engine, "main", "sqlite");
    string info = yield ClientSession.test (s.config, null, null);
    ok (info.has_prefix ("SQLite 3") && info.contains ("database main"), "sqlite test connection summary");
    yield s.disconnect ();
    ok (Engines.create (pg_config ()) is PgEngine && Engines.create (my_config ()) is MysqlEngine && Engines.create (new ConnectionConfig ()) is PgEngine, "engine factory");
    ok (Engines.is_cancelled (new IOError.CANCELLED ("x")) && Engines.is_cancelled (new RemoteError.CANCELLED ("x")) && !Engines.is_cancelled (new RemoteError.SERVER ("x")), "cancel detection");
    yield test_servers ();
    yield test_ssh ();
}

int main (string[] args) {
    if (SshTunnel.handle_askpass ()) return 0;
    Intl.setlocale (LocaleCategory.ALL, "C");
    servers_run = "";
    ssh_status = "skipped: SDB_SSH_PORT not set";
    scratch = env ("SDB_CLIENT_SCRATCH", Path.build_filename (Environment.get_tmp_dir (), "sdb-client-test"));
    DirUtils.create_with_parents (scratch, 0700);
    Environment.set_variable ("SDB_CONFIG_DIR", Path.build_filename (scratch, "config"), true);
    FileUtils.unlink (ClientStore.path ("connections.json"));
    try {
        test_script ();
        test_ssh_command ();
        test_stores ();
    } catch (Error e) {
        stderr.printf ("FAIL: %s\n", e.message);
        return 1;
    }
    var loop = new MainLoop ();
    run_all.begin ((obj, res) => {
        try {
            run_all.end (res);
        } catch (Error e) {
            stderr.printf ("FAIL after %d checks: %s (%s %d)\n", checks, e.message, e.domain.to_string (), e.code);
            failed = true;
        }
        loop.quit ();
    });
    loop.run ();
    if (failed) return 1;
    print ("client: %d checks passed (servers:%s, ssh %s)\n", checks, servers_run == "" ? " none" : servers_run, ssh_status);
    return 0;
}
