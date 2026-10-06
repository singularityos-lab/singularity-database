namespace Singularity.Apps.Database {

    public class ServerLinks {
        private const string[] SYSTEM_SCHEMAS = { "pg_catalog", "information_schema", "mysql", "performance_schema", "sys", "temp" };

        public static async Gee.ArrayList<string> schemas (Engine e, Cancellable? cancellable = null) throws Error {
            var result = new Gee.ArrayList<string> ();
            if (e.kind == EngineKind.SQLITE) {
                result.add ("main");
                return result;
            }
            if (e.kind == EngineKind.MYSQL && e.current_database != "") {
                result.add (e.current_database);
                return result;
            }
            foreach (string s in yield e.list_schemas (cancellable)) {
                if (!(s in SYSTEM_SCHEMAS)) result.add (s);
            }
            return result;
        }

        public static async Gee.ArrayList<string> tables (Engine e, string schema, Cancellable? cancellable = null) throws Error {
            var result = new Gee.ArrayList<string> ();
            foreach (var o in yield e.list_objects (schema, cancellable)) {
                if (o.kind == ObjectKind.TABLE || o.kind == ObjectKind.VIEW) result.add (o.name);
            }
            return result;
        }

        public static async ServerSnapshot fetch (Engine e, string schema, string table, Cancellable? cancellable = null) throws Error {
            var info = yield e.describe_table (schema, table, cancellable);
            var snap = new ServerSnapshot ();
            string[] cols = {};
            string[] names = {};
            string[] types = {};
            string[] serial = {};
            foreach (var c in info.columns) {
                names += c.name;
                types += c.data_type;
                if (c.auto_increment) serial += c.name;
                cols += e.quote_ident (c.name);
            }
            snap.columns = names;
            snap.types = types;
            snap.serial = serial;
            if (cols.length == 0) throw new RemoteError.SERVER (_("The table \"%s\" has no columns.").printf (table));
            snap.key = info.primary_key ();
            var r = yield e.execute ("SELECT %s FROM %s".printf (string.joinv (", ", cols), e.qualified (schema, table)), null, cancellable, 500000);
            snap.rows = r.rows;
            return snap;
        }

        private static DbValue json_value (Json.Object o, string member) {
            var n = o.get_member (member);
            if (n == null || n.is_null ()) return new DbValue.null ();
            var t = n.get_value_type ();
            if (t == typeof (int64)) return new DbValue.int (n.get_int ());
            if (t == typeof (double)) return new DbValue.real (n.get_double ());
            if (t == typeof (bool)) return new DbValue.bool (n.get_boolean ());
            return new DbValue.text (n.get_string () ?? "");
        }

        public static string statement (Engine e, LinkDef l, ServerSnapshot snap, LinkChange c, out DbValue[] args) {
            DbValue[] p = {};
            string target = e.qualified (l.remote_schema, l.table);
            string[] where = {};
            if (c.key != null && c.op == "delete") {
                foreach (string k in snap.key) {
                    var v = json_value (c.key, k);
                    if (v.is_null) {
                        where += "%s IS NULL".printf (e.quote_ident (k));
                    } else {
                        p += v;
                        where += "%s = %s".printf (e.quote_ident (k), e.placeholder (p.length));
                    }
                }
            }
            string sql;
            if (c.op == "delete") {
                sql = "DELETE FROM %s WHERE %s".printf (target, string.joinv (" AND ", where));
            } else if (c.op == "insert") {
                string[] cols = {};
                string[] ph = {};
                foreach (string col in snap.columns) {
                    if (c.values == null || !c.values.has_member (col) || col in snap.serial) continue;
                    p += json_value (c.values, col);
                    cols += e.quote_ident (col);
                    ph += e.placeholder (p.length);
                }
                sql = cols.length == 0 ? "INSERT INTO %s DEFAULT VALUES".printf (target) : "INSERT INTO %s (%s) VALUES (%s)".printf (target, string.joinv (", ", cols), string.joinv (", ", ph));
            } else {
                string[] sets = {};
                DbValue[] sp = {};
                foreach (string col in snap.columns) {
                    if (c.values == null || !c.values.has_member (col)) continue;
                    sp += json_value (c.values, col);
                    sets += "%s = %s".printf (e.quote_ident (col), e.placeholder (sp.length));
                }
                DbValue[] all = {};
                foreach (var v in sp) all += v;
                string[] w2 = {};
                int n = sp.length;
                int wi = 0;
                foreach (string k in snap.key) {
                    var v = json_value (c.key, k);
                    if (v.is_null) {
                        w2 += "%s IS NULL".printf (e.quote_ident (k));
                    } else {
                        all += v;
                        w2 += "%s = %s".printf (e.quote_ident (k), e.placeholder (n + (++wi)));
                    }
                }
                p = all;
                sql = "UPDATE %s SET %s WHERE %s".printf (target, string.joinv (", ", sets), string.joinv (" AND ", w2));
            }
            args = p;
            return sql;
        }
    }
}
