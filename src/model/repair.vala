namespace Singularity.Apps.Database {

    public class Repair {
        private const int PROBE = 64;

        private Sqlite.Database src;
        private Sqlite.Database dst;
        private string[] notes = {};
        private int64 lost;
        private int64 copied;
        private int64 rejected;

        private Repair () {
        }

        private static void run_sql (Sqlite.Database h, string sql) throws SchemaError {
            string? err;
            if (h.exec (sql, null, out err) != Sqlite.OK) throw new SchemaError.SQL (err ?? h.errmsg ());
        }

        private static int64 scalar (Sqlite.Database h, string sql) throws SchemaError {
            Sqlite.Statement st;
            if (h.prepare_v2 (sql, -1, out st) != Sqlite.OK) throw new SchemaError.SQL (h.errmsg ());
            int rc = st.step ();
            if (rc == Sqlite.ROW) return st.column_int64 (0);
            if (rc != Sqlite.DONE) throw new SchemaError.SQL (h.errmsg ());
            return 0;
        }

        private static Sqlite.Database open_handle (string path, int flags, string? password) throws Error {
            Sqlite.Database h;
            string? vfs = null;
            if (password != null) {
                Crypt.register ();
                vfs = Crypt.VFS;
            }
            int rc = Sqlite.Database.open_v2 (path, out h, flags, vfs);
            if (rc != Sqlite.OK) throw new SchemaError.SQL (_("The database could not be opened."));
            h.busy_timeout (3000);
            return h;
        }

        public static void run (string path, string output_path, out string[] notes, string? password = null) throws Error {
            var r = new Repair ();
            if (FileUtils.test (output_path, FileTest.EXISTS)) FileUtils.remove (output_path);
            if (password != null) {
                Crypt.set_key (path, password);
                Crypt.set_key (output_path, password);
            }
            try {
                r.src = open_handle (path, Sqlite.OPEN_READONLY, password);
                r.dst = open_handle (output_path, Sqlite.OPEN_READWRITE | Sqlite.OPEN_CREATE, password);
                if (password != null) Crypt.set_reserve (r.dst, Crypt.RESERVE);
                r.salvage ();
            } finally {
                r.src = null;
                r.dst = null;
                if (password != null) {
                    Crypt.clear_key (path);
                    Crypt.clear_key (output_path);
                }
            }
            notes = r.notes;
        }

        private class Entry {
            public string type;
            public string name;
            public string sql;
        }

        private Gee.ArrayList<Entry> read_schema () throws Error {
            var list = new Gee.ArrayList<Entry> ();
            Sqlite.Statement st;
            if (src.prepare_v2 ("SELECT type, name, sql FROM sqlite_master WHERE sql IS NOT NULL ORDER BY rowid", -1, out st) != Sqlite.OK) {
                throw new SchemaError.SQL (_("The database is too damaged to repair: its list of tables cannot be read."));
            }
            int rc;
            while ((rc = st.step ()) == Sqlite.ROW) {
                var e = new Entry ();
                e.type = st.column_text (0) ?? "";
                e.name = st.column_text (1) ?? "";
                e.sql = st.column_text (2) ?? "";
                list.add (e);
            }
            if (rc != Sqlite.DONE) notes += _("Part of the list of tables could not be read; some objects may be missing.");
            return list;
        }

        private void salvage () throws Error {
            try {
                int64 ps = scalar (src, "PRAGMA page_size");
                if (ps > 0) run_sql (dst, "PRAGMA page_size = %lld".printf (ps));
            } catch (Error e) {
            }
            var schema = read_schema ();
            run_sql (dst, "PRAGMA foreign_keys = OFF");
            run_sql (dst, "BEGIN");
            int tables = 0;
            foreach (var e in schema) {
                if (e.type != "table" || e.name.has_prefix ("sqlite_")) continue;
                try {
                    run_sql (dst, e.sql);
                    tables++;
                } catch (Error err) {
                    notes += _("The table \"%s\" could not be recreated: %s").printf (e.name, err.message);
                }
            }
            foreach (var e in schema) {
                if (e.type != "table" || e.name.has_prefix ("sqlite_")) continue;
                copy_table (e.name);
            }
            copy_sequence ();
            foreach (string kind in new string[] { "index", "trigger", "view" }) {
                foreach (var e in schema) {
                    if (e.type != kind) continue;
                    try {
                        run_sql (dst, e.sql);
                    } catch (Error err) {
                        notes += _("The %s \"%s\" could not be recreated: %s").printf (kind, e.name, err.message);
                    }
                }
            }
            foreach (string pragma in new string[] { "application_id", "user_version" }) {
                try {
                    run_sql (dst, "PRAGMA %s = %lld".printf (pragma, scalar (src, "PRAGMA " + pragma)));
                } catch (Error e) {
                }
            }
            run_sql (dst, "COMMIT");
            run_sql (dst, "REINDEX");
            notes += ngettext ("%d table was recovered.", "%d tables were recovered.", tables).printf (tables);
            if (lost > 0) notes += ngettext ("%lld record could not be read and was lost.", "%lld records could not be read and were lost.", (ulong) lost).printf (lost);
            if (rejected > 0) notes += ngettext ("%lld damaged record was left out because it broke the table rules.", "%lld damaged records were left out because they broke the table rules.", (ulong) rejected).printf (rejected);
            string check = integrity (dst);
            if (check != "ok") notes += _("The repaired database still reports problems: %s").printf (check);
            int64 fk = count_rows (dst, "PRAGMA foreign_key_check");
            if (fk > 0) notes += ngettext ("%lld record no longer matches its relationship.", "%lld records no longer match their relationships.", (ulong) fk).printf (fk);
        }

        private static string integrity (Sqlite.Database h) {
            Sqlite.Statement st;
            if (h.prepare_v2 ("PRAGMA integrity_check", -1, out st) != Sqlite.OK) return h.errmsg ();
            string[] lines = {};
            while (st.step () == Sqlite.ROW) lines += st.column_text (0) ?? "";
            return string.joinv ("; ", lines);
        }

        private static int64 count_rows (Sqlite.Database h, string sql) {
            Sqlite.Statement st;
            if (h.prepare_v2 (sql, -1, out st) != Sqlite.OK) return 0;
            int64 n = 0;
            while (st.step () == Sqlite.ROW) n++;
            return n;
        }

        private string[] columns_of (string table, out bool rowid) {
            rowid = true;
            string[] cols = {};
            Sqlite.Statement st;
            if (dst.prepare_v2 ("PRAGMA table_xinfo(%s)".printf (Sql.quote_ident (table)), -1, out st) != Sqlite.OK) return cols;
            while (st.step () == Sqlite.ROW) {
                int hidden = st.column_int (6);
                if (hidden == 2 || hidden == 3) continue;
                cols += st.column_text (1);
            }
            Sqlite.Statement probe;
            if (dst.prepare_v2 ("SELECT rowid FROM %s LIMIT 0".printf (Sql.quote_ident (table)), -1, out probe) != Sqlite.OK) rowid = false;
            return cols;
        }

        private void copy_table (string table) {
            bool has_rowid;
            string[] cols = columns_of (table, out has_rowid);
            if (cols.length == 0) return;
            string[] quoted = {};
            string[] marks = {};
            foreach (string c in cols) {
                quoted += Sql.quote_ident (c);
                marks += "?";
            }
            string list = string.joinv (", ", quoted);
            string t = Sql.quote_ident (table);
            if (!has_rowid) {
                copy_select (table, "SELECT %s FROM %s".printf (list, t), "INSERT INTO %s (%s) VALUES (%s)".printf (t, list, string.joinv (", ", marks)), false, 0, 0);
                return;
            }
            string select = "SELECT rowid, %s FROM %s WHERE rowid >= ?1 AND rowid <= ?2 ORDER BY rowid".printf (list, t);
            string insert = "INSERT INTO %s (rowid, %s) VALUES (?, %s)".printf (t, list, string.joinv (", ", marks));
            int64 lo = int64.MIN, hi = int64.MAX;
            try {
                lo = scalar (src, "SELECT min(rowid) FROM %s".printf (t));
                hi = scalar (src, "SELECT max(rowid) FROM %s".printf (t));
            } catch (Error e) {
                lo = int64.MIN;
                hi = int64.MAX;
            }
            int64 before_lost = lost;
            copy_range (table, select, insert, lo, hi);
            if (lost > before_lost) notes += ngettext ("%s: %lld record could not be read.", "%s: %lld records could not be read.", (ulong) (lost - before_lost)).printf (table, lost - before_lost);
        }

        private void copy_range (string table, string select, string insert, int64 lo, int64 hi) {
            if (lo > hi) return;
            if (copy_select (table, select, insert, true, lo, hi)) return;
            if ((uint64) hi - (uint64) lo < PROBE) {
                for (int64 id = lo; ; id++) {
                    if (!copy_select (table, select, insert, true, id, id)) lost++;
                    if (id == hi) break;
                }
                return;
            }
            int64 mid = lo + (int64) (((uint64) hi - (uint64) lo) / 2);
            copy_range (table, select, insert, lo, mid);
            copy_range (table, select, insert, mid + 1, hi);
        }

        private bool copy_select (string table, string select, string insert, bool ranged, int64 lo, int64 hi) {
            Sqlite.Statement rd;
            Sqlite.Statement wr;
            if (src.prepare_v2 (select, -1, out rd) != Sqlite.OK) {
                if (!ranged) notes += _("The records of \"%s\" could not be read.").printf (table);
                return false;
            }
            if (dst.prepare_v2 (insert, -1, out wr) != Sqlite.OK) return true;
            if (ranged) {
                rd.bind_int64 (1, lo);
                rd.bind_int64 (2, hi);
            }
            try {
                run_sql (dst, "SAVEPOINT sdb_range");
            } catch (Error e) {
                return false;
            }
            int n = rd.column_count ();
            int64 done = 0, bad = 0;
            int rc;
            while ((rc = rd.step ()) == Sqlite.ROW) {
                wr.reset ();
                wr.clear_bindings ();
                for (int i = 0; i < n; i++) Database.bind (wr, i + 1, Database.column (rd, i));
                int w = wr.step ();
                if (w == Sqlite.DONE) done++;
                else bad++;
            }
            if (rc != Sqlite.DONE) {
                try {
                    run_sql (dst, "ROLLBACK TO sdb_range");
                    run_sql (dst, "RELEASE sdb_range");
                } catch (Error e) {
                }
                if (!ranged) notes += _("Some records of \"%s\" could not be read.").printf (table);
                return false;
            }
            try {
                run_sql (dst, "RELEASE sdb_range");
            } catch (Error e) {
            }
            copied += done;
            rejected += bad;
            return true;
        }

        private void copy_sequence () {
            Sqlite.Statement probe;
            if (dst.prepare_v2 ("SELECT name, seq FROM sqlite_sequence LIMIT 0", -1, out probe) != Sqlite.OK) return;
            Sqlite.Statement rd;
            if (src.prepare_v2 ("SELECT name, seq FROM sqlite_sequence", -1, out rd) != Sqlite.OK) return;
            Sqlite.Statement wr;
            if (dst.prepare_v2 ("INSERT INTO sqlite_sequence (name, seq) VALUES (?, ?)", -1, out wr) != Sqlite.OK) return;
            try {
                run_sql (dst, "DELETE FROM sqlite_sequence");
            } catch (Error e) {
                return;
            }
            while (rd.step () == Sqlite.ROW) {
                wr.reset ();
                wr.bind_text (1, rd.column_text (0) ?? "");
                wr.bind_int64 (2, rd.column_int64 (1));
                wr.step ();
            }
        }
    }
}
