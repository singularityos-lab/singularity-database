namespace Singularity.Apps.Database {

    public class RecordLocks : Object {
        public const string TABLE = "_sdb_locks";

        private static string? process_owner;

        public weak Database db;
        public string owner { get; private set; }
        public int stale_seconds { get; set; default = 120; }
        private bool ready;

        public RecordLocks (Database db, string? owner = null) {
            this.db = db;
            this.owner = owner ?? session ();
        }

        public static string session () {
            if (process_owner == null) process_owner = Uuid.string_random ();
            return process_owner;
        }

        private static int64 now () {
            return get_real_time () / 1000000;
        }

        private void ensure () throws Error {
            if (ready) return;
            db.exec ("CREATE TABLE IF NOT EXISTS %s (tbl TEXT NOT NULL, rid INTEGER NOT NULL, owner TEXT NOT NULL, usr TEXT, host TEXT, pid INTEGER, since INTEGER, beat INTEGER, PRIMARY KEY (tbl, rid))".printf (TABLE));
            ready = true;
        }

        private static bool pid_alive (int64 pid) {
            if (pid <= 0) return true;
            if (!FileUtils.test ("/proc/self", FileTest.IS_DIR)) return true;
            return FileUtils.test ("/proc/%lld".printf (pid), FileTest.EXISTS);
        }

        private bool is_stale (Row r) {
            int64 beat = r.get (5).as_int ();
            if (now () - beat > stale_seconds) return true;
            string host = r.get (3).to_string ();
            int64 pid = r.get (4).as_int ();
            if (host == Environment.get_host_name () && pid != c_getpid () && !pid_alive (pid)) return true;
            return false;
        }

        [CCode (cname = "getpid", cheader_filename = "unistd.h")]
        private static extern int c_getpid ();

        private void transaction (owned Database.DesignOp op) throws Error {
            bool outer = db.handle ().get_autocommit () != 0;
            db.exec (outer ? "BEGIN IMMEDIATE" : "SAVEPOINT sdb_lock");
            try {
                op ();
                db.exec (outer ? "COMMIT" : "RELEASE sdb_lock");
            } catch (Error e) {
                try {
                    if (outer) {
                        db.exec ("ROLLBACK");
                    } else {
                        db.exec ("ROLLBACK TO sdb_lock");
                        db.exec ("RELEASE sdb_lock");
                    }
                } catch (Error e2) {
                }
                throw e;
            }
        }

        public void acquire (string table, int64 rowid) throws Error {
            ensure ();
            transaction (() => {
                var rs = db.query ("SELECT owner, usr, since, host, pid, beat FROM %s WHERE tbl = ? AND rid = ?".printf (TABLE), { new DbValue.text (table), new DbValue.int (rowid) });
                if (rs.rows.size > 0) {
                    var r = rs.rows[0];
                    if (r.get (0).to_string () != owner && !is_stale (r)) {
                        string user = r.get (1).to_string ();
                        string host = r.get (3).to_string ();
                        throw new SchemaError.CONSTRAINT (_("This record is being edited by %s on %s.").printf (user != "" ? user : _("another user"), host != "" ? host : _("another computer")));
                    }
                }
                int64 t = now ();
                db.run ("INSERT OR REPLACE INTO %s (tbl, rid, owner, usr, host, pid, since, beat) VALUES (?, ?, ?, ?, ?, ?, ?, ?)".printf (TABLE), {
                    new DbValue.text (table), new DbValue.int (rowid), new DbValue.text (owner), new DbValue.text (Environment.get_user_name ()),
                    new DbValue.text (Environment.get_host_name ()), new DbValue.int (c_getpid ()), new DbValue.int (t), new DbValue.int (t)
                });
            });
        }

        public string? holder (string table, int64 rowid) {
            try {
                ensure ();
                var rs = db.query ("SELECT owner, usr, since, host, pid, beat FROM %s WHERE tbl = ? AND rid = ?".printf (TABLE), { new DbValue.text (table), new DbValue.int (rowid) });
                if (rs.rows.size == 0) return null;
                var r = rs.rows[0];
                if (r.get (0).to_string () == owner || is_stale (r)) return null;
                return "%s@%s".printf (r.get (1).to_string (), r.get (3).to_string ());
            } catch (Error e) {
                return null;
            }
        }

        public void release (string table, int64 rowid) throws Error {
            ensure ();
            db.run ("DELETE FROM %s WHERE tbl = ? AND rid = ? AND owner = ?".printf (TABLE), { new DbValue.text (table), new DbValue.int (rowid), new DbValue.text (owner) });
        }

        public void release_all () throws Error {
            ensure ();
            db.run ("DELETE FROM %s WHERE owner = ?".printf (TABLE), { new DbValue.text (owner) });
        }

        public void heartbeat () throws Error {
            ensure ();
            db.run ("UPDATE %s SET beat = ? WHERE owner = ?".printf (TABLE), { new DbValue.int (now ()), new DbValue.text (owner) });
        }
    }

    public class ChangeWatcher : Object {
        public weak Database db;
        public uint interval_seconds { get; set; default = 5; }
        private int64 last;
        private uint timer;

        public signal void changed ();

        public ChangeWatcher (Database db) {
            this.db = db;
            last = version ();
        }

        public int64 version () {
            try {
                return db.query_int ("PRAGMA data_version");
            } catch (Error e) {
                return last;
            }
        }

        public bool poll () {
            int64 v = version ();
            if (v == last) return false;
            last = v;
            changed ();
            return true;
        }

        public void start () {
            stop ();
            last = version ();
            timer = Timeout.add_seconds (uint.max (1, interval_seconds), () => {
                poll ();
                return Source.CONTINUE;
            });
        }

        public void stop () {
            if (timer != 0) {
                Source.remove (timer);
                timer = 0;
            }
        }

        public bool running {
            get { return timer != 0; }
        }
    }
}
