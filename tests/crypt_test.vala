using Singularity.Apps.Database;

int checks = 0;
string dir;

void ok (bool cond, string what) {
    checks++;
    if (!cond) {
        stderr.printf ("FAIL: %s\n", what);
        Process.exit (1);
    }
}

bool contains (uint8[] data, string needle) {
    uint8[] n = needle.data;
    if (n.length == 0 || data.length < n.length) return false;
    for (int i = 0; i <= data.length - n.length; i++) {
        if (data[i] != n[0]) continue;
        if (Memory.cmp ((uint8*) data + i, n, n.length) == 0) return true;
    }
    return false;
}

uint8[] raw (string path) {
    uint8[] bytes;
    try {
        FileUtils.get_data (path, out bytes);
    } catch (Error e) {
        bytes = new uint8[0];
    }
    return bytes;
}

void patch (string path, int64 offset, uint8[] bytes) {
    var f = FileStream.open (path, "r+b");
    f.seek ((long) offset, FileSeek.SET);
    f.write (bytes);
}

string fresh (string name) {
    string p = Path.build_filename (dir, name);
    foreach (string s in new string[] { "", "-journal" }) {
        if (FileUtils.test (p + s, FileTest.EXISTS)) FileUtils.remove (p + s);
    }
    return p;
}

const string MARKER = "SECRETMARKER-7f3a";

Database sample (string path, int rows) throws Error {
    var db = Database.create (path);
    db.exec ("CREATE TABLE people (id INTEGER PRIMARY KEY, name TEXT, note TEXT)");
    db.exec ("BEGIN");
    for (int i = 1; i <= rows; i++) db.run ("INSERT INTO people (name, note) VALUES (?, ?)", { new DbValue.text ("Person %d".printf (i)), new DbValue.text ("%s %d".printf (MARKER, i)) });
    db.exec ("COMMIT");
    return db;
}

void test_encryption () throws Error {
    string path = fresh ("crypt.sdb");
    var db = sample (path, 300);
    db.set_meta ("form:Main", "{\"source\":\"people\"}");
    ok (contains (raw (path), MARKER), "plain file holds the marker");
    ok (!db.is_encrypted, "not encrypted at first");
    db.set_password ("correct horse");
    ok (db.is_encrypted, "encrypted after set_password");
    var bytes = raw (path);
    ok (!contains (bytes, "SQLite format 3"), "no sqlite header in encrypted file");
    ok (!contains (bytes, MARKER), "no plaintext marker in encrypted file");
    ok (!contains (bytes, "people"), "no plaintext schema in encrypted file");
    ok (Memory.cmp (bytes, "SDBENC".data, 6) == 0, "magic at start");
    ok (db.query_int ("SELECT count(*) FROM people") == 300, "same handle reads after encryption");
    ok (db.get_meta ("form:Main") != null, "meta survives encryption");
    db.close ();

    ok (Database.needs_password (path), "needs_password");
    bool required = false;
    try {
        Database.open (path);
    } catch (CryptError.PASSWORD_REQUIRED e) {
        required = true;
    }
    ok (required, "open without password reports PASSWORD_REQUIRED");

    string msg = "";
    try {
        Database.open_with_password (path, "wrong");
    } catch (Error e) {
        msg = e.message;
    }
    ok (msg == "The password is not correct.", "wrong password message: " + msg);

    var a = Database.open_with_password (path, "correct horse");
    ok (a.query_int ("SELECT count(*) FROM people") == 300, "reopen reads data");
    var rs = a.query ("SELECT note FROM people WHERE id = 42");
    ok (rs.rows[0].get (0).to_string () == MARKER + " 42", "reopen reads exact value");

    var b = Database.open_with_password (path, "correct horse");
    a.run ("INSERT INTO people (name, note) VALUES ('Ann', 'from a')");
    ok (b.query_int ("SELECT count(*) FROM people") == 301, "second connection sees first one's commit");
    b.run ("UPDATE people SET name = 'Bea' WHERE id = 1");
    ok (a.query ("SELECT name FROM people WHERE id = 1").rows[0].get (0).to_string () == "Bea", "first connection sees second one's commit");
    b.close ();

    a.exec ("BEGIN");
    a.exec ("UPDATE people SET note = 'changed'");
    a.exec ("DELETE FROM people WHERE id > 100");
    ok (a.query_int ("SELECT count(*) FROM people") == 100, "changes visible inside transaction");
    a.exec ("ROLLBACK");
    ok (a.query_int ("SELECT count(*) FROM people") == 301, "rollback restores rows");
    ok (a.query_int ("SELECT count(*) FROM people WHERE note = 'changed'") == 0, "rollback restores values");

    string copy = fresh ("crypt-copy.sdb");
    a.vacuum_into (copy);
    ok (Database.needs_password (copy) && !contains (raw (copy), MARKER), "save a copy stays encrypted");
    var c = Database.open_with_password (copy, "correct horse");
    ok (c.query_int ("SELECT count(*) FROM people") == 301, "encrypted copy readable");
    c.close ();

    a.compact ();
    ok (a.query_int ("SELECT count(*) FROM people") == 301 && Database.needs_password (path) && !contains (raw (path), MARKER), "compact keeps encryption");

    a.set_password ("battery staple");
    a.close ();
    msg = "";
    try {
        Database.open_with_password (path, "correct horse");
    } catch (Error e) {
        msg = e.message;
    }
    ok (msg == "The password is not correct.", "old password rejected after change");
    a = Database.open_with_password (path, "battery staple");
    ok (a.query_int ("SELECT count(*) FROM people") == 301, "new password works");

    a.set_password (null);
    ok (!a.is_encrypted, "decrypted flag");
    ok (a.query_int ("SELECT count(*) FROM people") == 301, "handle works after decrypt");
    a.close ();
    bytes = raw (path);
    ok (Memory.cmp (bytes, "SQLite format 3\0".data, 16) == 0, "plain sqlite header after removing the password");
    ok (!Database.needs_password (path), "no password needed after removal");
    Sqlite.Database plain;
    ok (Sqlite.Database.open_v2 (path, out plain, Sqlite.OPEN_READONLY) == Sqlite.OK, "plain sqlite open");
    Sqlite.Statement st;
    plain.prepare_v2 ("SELECT count(*) FROM people", -1, out st);
    ok (st.step () == Sqlite.ROW && st.column_int (0) == 301, "plain sqlite reads the decrypted file");
    st = null;
    plain = null;
    var d = Database.open (path);
    ok (d.get_meta ("form:Main") != null, "meta survives decryption");
    d.close ();
    print ("encryption: ok\n");
}

void test_tamper () throws Error {
    string path = fresh ("tamper.sdb");
    var db = sample (path, 400);
    db.set_password ("pw");
    db.close ();
    int64 ps = 4096;
    uint8[] bytes = raw (path);
    ok (bytes.length > ps * 3, "tamper file has several pages");
    int64 at = bytes.length - ps + 200;
    uint8 old = bytes[at];
    patch (path, at, { old ^ 0x01 });
    var t = Database.open_with_password (path, "pw");
    bool failed = false;
    try {
        t.query ("SELECT note FROM people");
    } catch (Error e) {
        failed = true;
    }
    ok (failed, "flipped byte in a page is detected");
    t.close ();
    patch (path, at, { old });
    t = Database.open_with_password (path, "pw");
    ok (t.query_int ("SELECT count(*) FROM people") == 400, "restored byte reads again");
    t.close ();
    patch (path, 40, { raw (path)[40] ^ 0x80 });
    string msg = "";
    try {
        Database.open_with_password (path, "pw");
    } catch (Error e) {
        msg = e.message;
    }
    ok (msg != "", "damaged first page refuses to open");
    print ("tamper: ok\n");
}

int crash_child (string path) {
    try {
        var db = Database.open_with_password (path, "pw");
        db.exec ("PRAGMA cache_size = 2");
        db.exec ("BEGIN");
        db.exec ("UPDATE people SET note = 'overwritten', name = 'X'");
        db.exec ("DELETE FROM people WHERE id % 2 = 0");
        Process.exit (0);
    } catch (Error e) {
        stderr.printf ("child: %s\n", e.message);
        Process.exit (2);
    }
    return 0;
}

void test_crash () throws Error {
    string path = fresh ("crash.sdb");
    var db = sample (path, 2000);
    db.set_password ("pw");
    db.close ();
    string self_exe = FileUtils.read_link ("/proc/self/exe");
    int status;
    string out_text, err_text;
    Process.spawn_sync (null, { self_exe, "crash-child", path }, null, 0, null, out out_text, out err_text, out status);
    ok (status == 0, "crash child ran: " + err_text);
    string journal = path + "-journal";
    ok (FileUtils.test (journal, FileTest.EXISTS), "hot journal left behind");
    var jb = raw (journal);
    ok (jb.length > 4096, "journal holds pages");
    ok (!contains (jb, MARKER) && !contains (jb, "Person 1"), "journal has no plaintext");
    ok (!contains (raw (path), MARKER), "db file has no plaintext after crash");
    var r = Database.open_with_password (path, "pw");
    ok (r.query_int ("SELECT count(*) FROM people") == 2000, "hot journal rolled back all deletes");
    ok (r.query_int ("SELECT count(*) FROM people WHERE note = 'overwritten'") == 0, "hot journal rolled back updates");
    ok (r.query ("PRAGMA integrity_check").rows[0].get (0).to_string () == "ok", "integrity after crash recovery");
    r.close ();
    print ("crash: ok\n");
}

void test_locks () throws Error {
    string path = fresh ("locks.sdb");
    var db = sample (path, 10);
    db.close ();
    var a = Database.open (path);
    var b = Database.open (path);
    var la = new RecordLocks (a, "owner-a");
    var lb = new RecordLocks (b, "owner-b");
    la.acquire ("people", 3);
    la.acquire ("people", 3);
    string msg = "";
    try {
        lb.acquire ("people", 3);
    } catch (SchemaError.CONSTRAINT e) {
        msg = e.message;
    }
    ok (msg == "This record is being edited by %s on %s.".printf (Environment.get_user_name (), Environment.get_host_name ()), "friendly lock message: " + msg);
    ok (lb.holder ("people", 3) != null && la.holder ("people", 3) == null, "holder reports other owner only");
    lb.acquire ("people", 4);
    la.release ("people", 3);
    lb.acquire ("people", 3);
    ok (b.query_int ("SELECT count(*) FROM _sdb_locks WHERE owner = 'owner-b'") == 2, "b holds two locks");
    msg = "";
    try {
        la.acquire ("people", 4);
    } catch (SchemaError.CONSTRAINT e) {
        msg = e.message;
    }
    ok (msg != "", "a blocked on 4");
    b.exec ("UPDATE _sdb_locks SET beat = beat - 30 WHERE owner = 'owner-b'");
    la.stale_seconds = 10;
    la.acquire ("people", 4);
    ok (a.query ("SELECT owner FROM _sdb_locks WHERE rid = 4").rows[0].get (0).to_string () == "owner-a", "stale lock taken over");
    lb.heartbeat ();
    lb.release_all ();
    ok (a.query_int ("SELECT count(*) FROM _sdb_locks WHERE owner = 'owner-b'") == 0, "release_all");
    b.run ("INSERT INTO _sdb_locks (tbl, rid, owner, usr, host, pid, since, beat) VALUES ('people', 9, 'ghost', 'u', ?, 999999999, strftime('%s','now'), strftime('%s','now'))", { new DbValue.text (Environment.get_host_name ()) });
    la.stale_seconds = 120;
    la.acquire ("people", 9);
    ok (a.query ("SELECT owner FROM _sdb_locks WHERE rid = 9").rows[0].get (0).to_string () == "owner-a", "lock of a dead process on this host taken over");
    var viaprop = a.record_locks;
    ok (viaprop.owner == RecordLocks.session (), "default owner is the process session");

    int signals = 0;
    a.external_change.connect (() => signals++);
    ok (!a.poll_external_change (), "baseline poll");
    a.run ("UPDATE people SET name = 'self' WHERE id = 1");
    ok (!a.poll_external_change (), "own write does not count as external");
    b.run ("UPDATE people SET name = 'other' WHERE id = 2");
    ok (a.poll_external_change (), "other connection's write detected");
    ok (!a.poll_external_change (), "no change after that");
    ok (signals == 1, "external_change emitted once");
    a.close ();
    b.close ();
    print ("locks: ok\n");
}

int64 page_of (Database db, string name, bool leaf) throws Error {
    var rs = db.query ("SELECT pageno FROM dbstat WHERE name = ? AND pagetype = ? ORDER BY pageno", { new DbValue.text (name), new DbValue.text (leaf ? "leaf" : "internal") });
    ok (rs.rows.size > 2, "dbstat pages for " + name);
    return rs.rows[rs.rows.size / 2].get (0).as_int ();
}

void test_repair (bool encrypted) throws Error {
    string path = fresh (encrypted ? "repair-enc.sdb" : "repair.sdb");
    var db = sample (path, 5000);
    db.exec ("CREATE INDEX idx_people_name ON people (name)");
    db.exec ("CREATE VIEW v_people AS SELECT name FROM people");
    db.set_meta ("report:Summary", "{\"source\":\"people\"}");
    int64 data_page = page_of (db, "people", true);
    int64 index_page = page_of (db, "idx_people_name", true);
    int64 ps = db.query_int ("PRAGMA page_size");
    if (encrypted) db.set_password ("pw");
    db.close ();
    if (encrypted) {
        patch (path, (data_page - 1) * ps + 300, { 0x55 });
        patch (path, (index_page - 1) * ps + 300, { 0x55 });
    } else {
        uint8[] junk = new uint8[64];
        for (int i = 0; i < junk.length; i++) junk[i] = (uint8) (0xA5 ^ i);
        patch (path, (data_page - 1) * ps, junk);
        patch (path, (index_page - 1) * ps, junk);
    }
    var d = encrypted ? Database.open_with_password (path, "pw") : Database.open (path);
    string[] notes = d.compact_and_repair ();
    string all = string.joinv ("\n", notes);
    ok (all.contains ("could not be read"), "repair notes mention losses: " + all);
    ok (all.contains ("damaged original"), "repair notes mention the backup");
    int64 n = d.query_int ("SELECT count(*) FROM people");
    ok (n > 4500 && n < 5000, "good rows survive (%lld)".printf (n));
    ok (d.query ("PRAGMA integrity_check").rows[0].get (0).to_string () == "ok", "integrity ok after repair");
    ok (d.get_meta ("report:Summary") != null, "meta preserved by repair");
    ok (d.query_int ("SELECT count(*) FROM sqlite_master WHERE name IN ('idx_people_name', 'v_people')") == 2, "index and view recreated");
    ok (d.query_int ("SELECT count(*) FROM people WHERE name = 'Person 4999'") <= 1, "index usable");
    ok (d.is_encrypted == encrypted, "encryption state kept by repair");
    if (encrypted) ok (!contains (raw (path), MARKER), "repaired encrypted file has no plaintext");
    var clean = d.compact_and_repair ();
    ok (clean.length == 1 && clean[0].contains ("No problems"), "healthy database is only compacted");
    d.close ();
    bool backup = false;
    try {
        var dh = Dir.open (dir);
        string? e;
        while ((e = dh.read_name ()) != null) {
            if (e.has_prefix (encrypted ? "repair-enc.damaged-" : "repair.damaged-") && e.has_suffix (".sdb")) backup = true;
        }
    } catch (Error e) {
    }
    ok (backup, "damaged original kept");
    print ("repair%s: ok\n", encrypted ? " (encrypted)" : "");
}

int main (string[] args) {
    if (args.length == 3 && args[1] == "crash-child") return crash_child (args[2]);
    string base_dir = Environment.get_tmp_dir ();
    try {
        dir = DirUtils.make_tmp ("sdb-crypt-XXXXXX");
    } catch (Error e) {
        dir = Path.build_filename (base_dir, "sdb-crypt");
        DirUtils.create_with_parents (dir, 0700);
    }
    try {
        test_encryption ();
        test_tamper ();
        test_crash ();
        test_locks ();
        test_repair (false);
        test_repair (true);
    } catch (Error e) {
        stderr.printf ("FAIL: %s\n", e.message);
        return 1;
    }
    print ("crypt: %d checks passed\n", checks);
    return 0;
}
