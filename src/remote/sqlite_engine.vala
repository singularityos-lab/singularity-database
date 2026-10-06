namespace Singularity.Apps.Database {

    [CCode (cname = "sqlite3_column_decltype")]
    extern unowned string? sqlite_decltype (Sqlite.Statement stmt, int col);

    public class SqliteCursor : Cursor {
        private SqliteEngine engine;
        private Sqlite.Statement? stmt;

        public SqliteCursor (SqliteEngine engine, owned Sqlite.Statement stmt) {
            this.engine = engine;
            this.stmt = (owned) stmt;
            for (int i = 0; i < this.stmt.column_count (); i++) {
                var m = new ColumnMeta (this.stmt.column_name (i) ?? "");
                m.type_name = sqlite_decltype (this.stmt, i) ?? "";
                m.table = this.stmt.column_table_name (i) ?? "";
                m.origin = this.stmt.column_origin_name (i) ?? "";
                columns.add (m);
            }
        }

        public override async Gee.ArrayList<Row> fetch (int max_rows, Cancellable? cancellable = null) throws Error {
            var rows = new Gee.ArrayList<Row> ();
            if (done || stmt == null) return rows;
            int n = columns.size;
            while (rows.size < max_rows) {
                if (cancellable != null && cancellable.is_cancelled ()) throw new RemoteError.CANCELLED (_("The query was cancelled."));
                int rc = stmt.step ();
                if (rc == Sqlite.ROW) {
                    var vals = new DbValue[n];
                    for (int i = 0; i < n; i++) vals[i] = Database.column (stmt, i);
                    rows.add (new Row (rows.size, (owned) vals));
                } else if (rc == Sqlite.DONE) {
                    done = true;
                    stmt = null;
                    break;
                } else {
                    done = true;
                    string msg = engine.errmsg ();
                    stmt = null;
                    throw engine.error_for (rc, msg);
                }
            }
            return rows;
        }

        public override async void close_async () throws Error {
            stmt = null;
            done = true;
        }
    }

    public class SqliteEngine : Engine {
        private Sqlite.Database? db;

        public SqliteEngine (ConnectionConfig config) {
            Object (config: config);
        }

        public string errmsg () {
            return db != null ? db.errmsg () : "";
        }

        public Error error_for (int rc, string msg) {
            if ((rc & 0xff) == Sqlite.INTERRUPT) return new RemoteError.CANCELLED (_("The query was cancelled."));
            return new RemoteError.SERVER (msg);
        }

        public override async void open (string? password, Cancellable? cancellable = null) throws Error {
            if (config.file_path == "") throw new RemoteError.CONNECT (_("Choose a database file."));
            int flags = config.read_only ? Sqlite.OPEN_READONLY : (Sqlite.OPEN_READWRITE | Sqlite.OPEN_CREATE);
            if (config.file_path != ":memory:" && !config.read_only && !FileUtils.test (config.file_path, FileTest.EXISTS)) {
                var parent = File.new_for_path (config.file_path).get_parent ();
                if (parent != null && !parent.query_exists ()) throw new RemoteError.CONNECT (_("The folder %s does not exist.").printf (parent.get_path ()));
            }
            int rc = Sqlite.Database.open_v2 (config.file_path, out db, flags);
            if (rc != Sqlite.OK) {
                string msg = db != null ? db.errmsg () : "";
                db = null;
                throw new RemoteError.CONNECT (_("Could not open %s: %s").printf (config.file_path, msg));
            }
            db.busy_timeout (5000);
            db.exec ("PRAGMA foreign_keys = ON");
            Sqlite.Statement probe;
            if (db.prepare_v2 ("SELECT count(*) FROM sqlite_master", -1, out probe) != Sqlite.OK || probe.step () != Sqlite.ROW) {
                string msg = db.errmsg ();
                db = null;
                throw new RemoteError.CONNECT (_("%s is not a SQLite database: %s").printf (config.file_path, msg));
            }
            server_version = "SQLite " + Sqlite.libversion ();
            current_database = "main";
            connected = true;
        }

        public override async void close_async () {
            db = null;
            connected = false;
        }

        public override void cancel_running () {
            if (db != null) db.interrupt ();
        }

        private Sqlite.Statement prepare (string sql, DbValue[]? params, out string tail) throws Error {
            if (db == null) throw new RemoteError.CONNECT (_("Not connected."));
            Sqlite.Statement stmt;
            unowned string rest;
            int rc = db.prepare_v2 (sql, -1, out stmt, out rest);
            if (rc != Sqlite.OK) throw error_for (rc, db.errmsg ());
            tail = rest;
            if (params != null) {
                for (int i = 0; i < params.length; i++) Database.bind (stmt, i + 1, params[i]);
            }
            return stmt;
        }

        public override async QueryResult execute (string sql, DbValue[]? params = null, Cancellable? cancellable = null, int max_rows = -1) throws Error {
            var result = new QueryResult ();
            var timer = new Timer ();
            ulong handler = 0;
            if (cancellable != null) handler = cancellable.connect (() => cancel_running ());
            try {
                string remaining = sql;
                bool first = true;
                while (remaining.strip () != "") {
                    string tail;
                    var stmt = prepare (remaining, first ? params : null, out tail);
                    first = false;
                    if (stmt == null) {
                        remaining = tail;
                        continue;
                    }
                    int n = stmt.column_count ();
                    bool rows_statement = n > 0;
                    if (rows_statement) {
                        result.columns.clear ();
                        result.rows.clear ();
                        result.truncated = false;
                        for (int i = 0; i < n; i++) {
                            var m = new ColumnMeta (stmt.column_name (i) ?? "");
                            m.type_name = sqlite_decltype (stmt, i) ?? "";
                            m.table = stmt.column_table_name (i) ?? "";
                            m.origin = stmt.column_origin_name (i) ?? "";
                            result.columns.add (m);
                        }
                    }
                    int before = db.total_changes ();
                    while (true) {
                        int rc = stmt.step ();
                        if (rc == Sqlite.ROW) {
                            if (max_rows >= 0 && result.rows.size >= max_rows) {
                                result.truncated = true;
                                break;
                            }
                            var vals = new DbValue[n];
                            for (int i = 0; i < n; i++) vals[i] = Database.column (stmt, i);
                            result.rows.add (new Row (result.rows.size, (owned) vals));
                        } else if (rc == Sqlite.DONE) {
                            break;
                        } else {
                            throw error_for (rc, db.errmsg ());
                        }
                    }
                    string head = remaining.strip ();
                    int sp = 0;
                    while (sp < head.length && !head[sp].isspace () && head[sp] != '(' && head[sp] != ';') sp++;
                    result.command = head.substring (0, sp).up ();
                    if (!rows_statement) result.affected = db.total_changes () - before;
                    else result.affected = result.rows.size;
                    remaining = tail;
                }
            } finally {
                if (handler != 0) cancellable.disconnect (handler);
            }
            result.elapsed_ms = timer.elapsed () * 1000.0;
            return result;
        }

        public override async Cursor open_cursor (string sql, DbValue[]? params = null, Cancellable? cancellable = null) throws Error {
            string tail;
            var stmt = prepare (sql, params, out tail);
            if (stmt == null) throw new RemoteError.SERVER (_("The statement is empty."));
            return new SqliteCursor (this, (owned) stmt);
        }

        public override async void use_database (string database, Cancellable? cancellable = null) throws Error {
            if (database != "main" && database != "") throw new RemoteError.UNSUPPORTED (_("SQLite files contain a single database."));
        }

        public override string quote_ident (string name) {
            return "\"" + name.replace ("\"", "\"\"") + "\"";
        }

        public override string placeholder (int index) {
            return "?";
        }

        public override string qualified (string schema, string name) {
            if (schema == "" || schema == "main") return quote_ident (name);
            return quote_ident (schema) + "." + quote_ident (name);
        }

        public override string text_cast (string expr) {
            return "CAST(%s AS TEXT)".printf (expr);
        }

        public override string[] keywords () {
            return Sql.KEYWORDS;
        }

        public override string[] type_names () {
            return { "INTEGER", "REAL", "TEXT", "BLOB", "NUMERIC", "BOOLEAN", "DATE", "DATETIME", "VARCHAR(255)", "DECIMAL(10,2)" };
        }

        private async QueryResult query (string sql, DbValue[]? params = null) throws Error {
            return yield execute (sql, params);
        }

        public override async Gee.ArrayList<string> list_databases (Cancellable? cancellable = null) throws Error {
            var list = new Gee.ArrayList<string> ();
            var r = yield query ("PRAGMA database_list");
            foreach (var row in r.rows) {
                string n = row.get (1).to_string ();
                if (n != "temp") list.add (n);
            }
            return list;
        }

        public override async Gee.ArrayList<string> list_schemas (Cancellable? cancellable = null) throws Error {
            return yield list_databases (cancellable);
        }

        public override async Gee.ArrayList<CatalogObject> list_objects (string schema, Cancellable? cancellable = null) throws Error {
            var list = new Gee.ArrayList<CatalogObject> ();
            string s = schema == "" ? "main" : schema;
            var r = yield query ("SELECT type, name, tbl_name FROM %s.sqlite_master WHERE name NOT LIKE 'sqlite_%%' AND name NOT LIKE '_sdb_%%' ORDER BY type, name COLLATE NOCASE".printf (quote_ident (s)));
            foreach (var row in r.rows) {
                string type = row.get (0).to_string ();
                ObjectKind kind;
                switch (type) {
                    case "table": kind = ObjectKind.TABLE; break;
                    case "view": kind = ObjectKind.VIEW; break;
                    case "index": kind = ObjectKind.INDEX; break;
                    case "trigger": kind = ObjectKind.TRIGGER; break;
                    default: continue;
                }
                var o = new CatalogObject (kind, s, row.get (1).to_string ());
                if (kind == ObjectKind.INDEX || kind == ObjectKind.TRIGGER) {
                    o.parent = row.get (2).to_string ();
                    o.detail = o.parent;
                }
                if (kind == ObjectKind.TABLE) {
                    try {
                        var c = yield query ("SELECT count(*) FROM %s".printf (qualified (s, o.name)));
                        o.row_estimate = c.rows.size > 0 ? c.rows[0].get (0).as_int () : -1;
                    } catch (Error e) {
                    }
                }
                list.add (o);
            }
            return list;
        }

        public override async TableInfo describe_table (string schema, string table, Cancellable? cancellable = null) throws Error {
            string s = schema == "" ? "main" : schema;
            var info = new TableInfo ();
            info.schema = s;
            info.name = table;
            var cols = yield query ("PRAGMA %s.table_xinfo(%s)".printf (quote_ident (s), Sql.quote_string (table)));
            if (cols.rows.size == 0) throw new RemoteError.SERVER (_("The table %s does not exist.").printf (table));
            var sqlr = yield query ("SELECT sql FROM %s.sqlite_master WHERE type = 'table' AND name = ?".printf (quote_ident (s)), { new DbValue.text (table) });
            string create_sql = sqlr.rows.size > 0 ? sqlr.rows[0].get (0).to_string () : "";
            int pk_count = 0;
            foreach (var row in cols.rows) {
                if (row.get (5).as_int () > 0) pk_count++;
            }
            foreach (var row in cols.rows) {
                if (row.get (6).as_int () == 1) continue;
                var c = new ColumnInfo ();
                c.position = (int) row.get (0).as_int () + 1;
                c.name = row.get (1).to_string ();
                c.data_type = row.get (2).to_string ();
                c.nullable = row.get (3).as_int () == 0;
                c.default_expr = row.get (4).is_null ? "" : row.get (4).to_string ();
                c.primary_key = row.get (5).as_int () > 0;
                c.auto_increment = c.primary_key && pk_count == 1 && c.data_type.up () == "INTEGER";
                if (c.primary_key) c.nullable = false;
                info.columns.add (c);
            }
            var idx = yield query ("PRAGMA %s.index_list(%s)".printf (quote_ident (s), Sql.quote_string (table)));
            foreach (var row in idx.rows) {
                var ix = new IndexInfo ();
                ix.name = row.get (1).to_string ();
                ix.unique = row.get (2).as_int () == 1;
                ix.primary = row.get (3).to_string () == "pk";
                ix.method = row.get (3).to_string ();
                var ic = yield query ("PRAGMA %s.index_info(%s)".printf (quote_ident (s), Sql.quote_string (ix.name)));
                string[] names = {};
                foreach (var r2 in ic.rows) names += r2.get (2).to_string ();
                ix.columns = names;
                info.indexes.add (ix);
            }
            var fks = yield query ("PRAGMA %s.foreign_key_list(%s)".printf (quote_ident (s), Sql.quote_string (table)));
            var by_id = new Gee.TreeMap<int, ForeignKeyInfo> ();
            foreach (var row in fks.rows) {
                int id = (int) row.get (0).as_int ();
                var fk = by_id[id];
                if (fk == null) {
                    fk = new ForeignKeyInfo ();
                    fk.name = "fk_%s_%d".printf (table, id);
                    fk.ref_schema = s;
                    fk.ref_table = row.get (2).to_string ();
                    fk.on_update = row.get (5).to_string ();
                    fk.on_delete = row.get (6).to_string ();
                    by_id[id] = fk;
                }
                string[] a = fk.columns;
                a += row.get (3).to_string ();
                fk.columns = a;
                string[] b = fk.ref_columns;
                b += row.get (4).is_null ? "" : row.get (4).to_string ();
                fk.ref_columns = b;
            }
            foreach (var fk in by_id.values) info.foreign_keys.add (fk);
            info.checks = extract_checks (create_sql);
            return info;
        }

        public static string[] extract_checks (string create_sql) {
            string[] out_checks = {};
            string up = create_sql.up ();
            int from = 0;
            while (true) {
                int at = up.index_of ("CHECK", from);
                if (at < 0) break;
                int open = at + 5;
                while (open < create_sql.length && create_sql[open].isspace ()) open++;
                bool boundary = at == 0 || !(create_sql[at - 1].isalnum () || create_sql[at - 1] == '_' || create_sql[at - 1] == '"');
                if (!boundary || open >= create_sql.length || create_sql[open] != '(') {
                    from = at + 5;
                    continue;
                }
                int depth = 0;
                int i = open;
                for (; i < create_sql.length; i++) {
                    char ch = create_sql[i];
                    if (ch == '\'') {
                        i++;
                        while (i < create_sql.length && create_sql[i] != '\'') i++;
                        continue;
                    }
                    if (ch == '(') depth++;
                    else if (ch == ')') {
                        depth--;
                        if (depth == 0) break;
                    }
                }
                if (i >= create_sql.length) break;
                out_checks += create_sql.substring (open + 1, i - open - 1).strip ();
                from = i + 1;
            }
            return out_checks;
        }

        public override async string object_definition (CatalogObject obj, Cancellable? cancellable = null) throws Error {
            string s = obj.schema == "" ? "main" : obj.schema;
            var r = yield query ("SELECT sql FROM %s.sqlite_master WHERE name = ?".printf (quote_ident (s)), { new DbValue.text (obj.name) });
            if (r.rows.size == 0 || r.rows[0].get (0).is_null) return "";
            return r.rows[0].get (0).to_string () + ";";
        }

        private string column_sql (ColumnInfo c, bool inline_pk) {
            var sb = new StringBuilder (quote_ident (c.name));
            if (c.data_type != "") sb.append (" ").append (c.data_type);
            if (inline_pk) {
                sb.append (" PRIMARY KEY");
                if (c.auto_increment) sb.append (" AUTOINCREMENT");
            }
            if (!c.nullable && !inline_pk) sb.append (" NOT NULL");
            if (c.default_expr != "") sb.append (" DEFAULT ").append (default_sql (c.default_expr));
            return sb.str;
        }

        private static string default_sql (string expr) {
            string e = expr.strip ();
            if (e.has_prefix ("(") || e.has_prefix ("'") || double.try_parse (e) || e.up () == "NULL" || e.up ().has_prefix ("CURRENT_")) return e;
            return "(" + e + ")";
        }

        public override string create_table_sql (TableInfo table) {
            string[] pk = table.primary_key ();
            bool inline_pk = pk.length == 1;
            var parts = new Gee.ArrayList<string> ();
            foreach (var c in table.columns) {
                bool this_pk = inline_pk && c.primary_key;
                parts.add ("    " + column_sql (c, this_pk && (c.data_type.up () == "INTEGER" || !c.auto_increment)));
            }
            if (pk.length > 1) {
                string[] q = {};
                foreach (string p in pk) q += quote_ident (p);
                parts.add ("    PRIMARY KEY (%s)".printf (string.joinv (", ", q)));
            }
            foreach (var fk in table.foreign_keys) {
                string[] a = {};
                foreach (string p in fk.columns) a += quote_ident (p);
                string[] b = {};
                foreach (string p in fk.ref_columns) if (p != "") b += quote_ident (p);
                string clause = "    FOREIGN KEY (%s) REFERENCES %s".printf (string.joinv (", ", a), quote_ident (fk.ref_table));
                if (b.length > 0) clause += " (%s)".printf (string.joinv (", ", b));
                if (fk.on_update != "" && fk.on_update != "NO ACTION") clause += " ON UPDATE " + fk.on_update;
                if (fk.on_delete != "" && fk.on_delete != "NO ACTION") clause += " ON DELETE " + fk.on_delete;
                parts.add (clause);
            }
            foreach (string ch in table.checks) parts.add ("    CHECK (%s)".printf (ch));
            var sb = new StringBuilder ();
            sb.append ("CREATE TABLE %s (\n".printf (qualified (table.schema, table.name)));
            sb.append (string.joinv (",\n", parts.to_array ()));
            sb.append ("\n);");
            foreach (var ix in table.indexes) {
                if (ix.primary || ix.name.has_prefix ("sqlite_autoindex")) continue;
                sb.append ("\n").append (index_sql (table, ix));
            }
            return sb.str;
        }

        private string index_sql (TableInfo table, IndexInfo ix) {
            string[] q = {};
            foreach (string c in ix.columns) q += quote_ident (c);
            return "CREATE %sINDEX %s ON %s (%s);".printf (ix.unique ? "UNIQUE " : "", qualified (table.schema, ix.name), quote_ident (table.name), string.joinv (", ", q));
        }

        private static bool same_indexes (IndexInfo a, IndexInfo b) {
            return a.unique == b.unique && string.joinv (",", a.columns) == string.joinv (",", b.columns);
        }

        public override string[] alter_table_sql (TableInfo before, TableInfo after, Gee.List<ColumnChange> changes) {
            string[] out_sql = {};
            bool rebuild = false;
            string[] simple = {};
            string table_q = qualified (before.schema, before.name);
            if (before.name != after.name) simple += "ALTER TABLE %s RENAME TO %s;".printf (table_q, quote_ident (after.name));
            string cur = qualified (before.schema, after.name);
            if (string.joinv (",", before.primary_key ()) != string.joinv (",", after.primary_key ())) rebuild = true;
            if (string.joinv ("\n", before.checks) != string.joinv ("\n", after.checks)) rebuild = true;
            if (before.foreign_keys.size != after.foreign_keys.size) rebuild = true;
            foreach (var ch in changes) {
                if (ch.column == null) {
                    var old = before.find (ch.old_name ?? "");
                    if (old != null && old.primary_key) rebuild = true;
                    if (old != null) simple += "ALTER TABLE %s DROP COLUMN %s;".printf (cur, quote_ident (old.name));
                } else if (ch.old_name == null) {
                    var c = ch.column;
                    if (c.primary_key || (!c.nullable && c.default_expr == "")) rebuild = true;
                    simple += "ALTER TABLE %s ADD COLUMN %s;".printf (cur, column_sql (c, false));
                } else {
                    var old = before.find (ch.old_name);
                    if (old == null) continue;
                    if (old.name != ch.column.name) simple += "ALTER TABLE %s RENAME COLUMN %s TO %s;".printf (cur, quote_ident (old.name), quote_ident (ch.column.name));
                    if (!old.same_definition (ch.column) && (old.data_type != ch.column.data_type || old.nullable != ch.column.nullable || old.default_expr != ch.column.default_expr)) rebuild = true;
                }
            }
            string[] index_drops = {};
            string[] index_sql_list = {};
            foreach (var ix in before.indexes) {
                if (ix.primary || ix.name.has_prefix ("sqlite_autoindex")) continue;
                bool keep = false;
                foreach (var nx in after.indexes) if (nx.name == ix.name && same_indexes (ix, nx)) keep = true;
                if (!keep) index_drops += "DROP INDEX %s;".printf (qualified (before.schema, ix.name));
            }
            foreach (var nx in after.indexes) {
                if (nx.primary || nx.name.has_prefix ("sqlite_autoindex")) continue;
                bool exists = false;
                foreach (var ix in before.indexes) if (nx.name == ix.name && same_indexes (ix, nx)) exists = true;
                if (!exists) index_sql_list += index_sql (after, nx);
            }
            if (!rebuild) {
                foreach (string s in index_drops) out_sql += s;
                foreach (string s in simple) out_sql += s;
                foreach (string s in index_sql_list) out_sql += s;
                return out_sql;
            }
            string tmp = "_sdb_new_" + after.name;
            var shadow = after.copy ();
            shadow.name = tmp;
            shadow.indexes.clear ();
            out_sql += "PRAGMA foreign_keys = OFF;";
            out_sql += "BEGIN;";
            out_sql += create_table_sql (shadow);
            string[] dst = {};
            string[] src = {};
            foreach (var c in after.columns) {
                string? from = null;
                bool is_new = false;
                foreach (var ch in changes) {
                    if (ch.column != null && ch.column.name == c.name) {
                        if (ch.old_name == null) is_new = true;
                        else from = ch.old_name;
                    }
                }
                if (is_new) continue;
                if (from == null && before.find (c.name) != null) from = c.name;
                if (from == null) continue;
                dst += quote_ident (c.name);
                src += quote_ident (from);
            }
            if (dst.length > 0) out_sql += "INSERT INTO %s (%s) SELECT %s FROM %s;".printf (qualified (after.schema, tmp), string.joinv (", ", dst), string.joinv (", ", src), table_q);
            out_sql += "DROP TABLE %s;".printf (table_q);
            out_sql += "ALTER TABLE %s RENAME TO %s;".printf (qualified (after.schema, tmp), quote_ident (after.name));
            foreach (var nx in after.indexes) {
                if (nx.primary || nx.name.has_prefix ("sqlite_autoindex")) continue;
                out_sql += index_sql (after, nx);
            }
            out_sql += "COMMIT;";
            out_sql += "PRAGMA foreign_keys = ON;";
            return out_sql;
        }

        public override string explain_sql (string sql, bool analyze) {
            return "EXPLAIN QUERY PLAN " + sql;
        }

        public override async QueryResult list_users (Cancellable? cancellable = null) throws Error {
            throw new RemoteError.UNSUPPORTED (_("SQLite files have no user accounts."));
        }

        public override async QueryResult list_privileges (string user, Cancellable? cancellable = null) throws Error {
            throw new RemoteError.UNSUPPORTED (_("SQLite files have no user accounts."));
        }

        public override async QueryResult list_activity (Cancellable? cancellable = null) throws Error {
            throw new RemoteError.UNSUPPORTED (_("SQLite runs inside this app, there is no server activity."));
        }

        public override async void kill_activity (string id, bool whole_connection, Cancellable? cancellable = null) throws Error {
            throw new RemoteError.UNSUPPORTED (_("SQLite runs inside this app, there is no server activity."));
        }
    }
}
