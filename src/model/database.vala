namespace Singularity.Apps.Database {

    public const int APPLICATION_ID = 0x53444231;
    public const string META_TABLE = "_sdb_meta";

    public class UndoEntry {
        public string label;
        public bool design;
        public Gee.ArrayList<Snapshot>? before;
        public Gee.ArrayList<Snapshot>? after;
        public string[] redo_sql = {};
        public string[] undo_sql = {};

        public UndoEntry (string label, bool design) {
            this.label = label;
            this.design = design;
        }
    }

    public class Snapshot {
        public string name;
        public string kind = "";
        public TableDef? def;
        public string create_sql = "";
        public string[] extra_sql = {};
        public string backup = "";
        public Gee.HashMap<string, string?> meta = new Gee.HashMap<string, string?> ();
        public string[] meta_keys = {};
    }

    public class Database : Object {
        public string path { get; private set; }
        public bool is_sdb { get; private set; }
        public bool read_only { get; private set; }

        private Sqlite.Database db;
        private Gee.ArrayList<UndoEntry> undo_stack = new Gee.ArrayList<UndoEntry> ();
        private Gee.ArrayList<UndoEntry> redo_stack = new Gee.ArrayList<UndoEntry> ();
        private int backup_counter;
        private bool recording = true;
        private Gee.HashMap<string, TableDef> table_cache = new Gee.HashMap<string, TableDef> ();

        public signal void schema_changed ();
        public signal void data_changed (string table);
        public signal void history_changed ();

        public bool can_undo { get { return undo_stack.size > 0; } }
        public bool can_redo { get { return redo_stack.size > 0; } }
        public string undo_label { get { return undo_stack.size > 0 ? undo_stack[undo_stack.size - 1].label : ""; } }
        public string redo_label { get { return redo_stack.size > 0 ? redo_stack[redo_stack.size - 1].label : ""; } }

        private Database () {
        }

        public static bool path_is_sdb (string path) {
            return path.down ().has_suffix (".sdb");
        }

        public static Database open (string path, bool create = false) throws Error {
            var d = new Database ();
            d.path = path;
            int flags = Sqlite.OPEN_READWRITE | (create ? Sqlite.OPEN_CREATE : 0);
            bool exists = FileUtils.test (path, FileTest.EXISTS);
            if (!create && !exists) throw new FileError.NOENT (_("The file does not exist."));
            if (!create && Crypt.is_encrypted (path)) throw new CryptError.PASSWORD_REQUIRED (_("This database is protected with a password."));
            if (exists && !create) {
                uint8[] head = new uint8[16];
                try {
                    var f = FileStream.open (path, "rb");
                    if (f != null) {
                        size_t n = f.read (head);
                        if (n > 0 && n < 16) throw new SchemaError.INVALID (_("This is not a database file."));
                        if (n == 16 && Memory.cmp (head, "SQLite format 3\0".data, 16) != 0) throw new SchemaError.INVALID (_("This is not an SQLite database."));
                    }
                } catch (SchemaError e) {
                    throw e;
                }
            }
            int rc = Sqlite.Database.open_v2 (path, out d.db, flags);
            if (rc != Sqlite.OK) {
                rc = Sqlite.Database.open_v2 (path, out d.db, Sqlite.OPEN_READONLY);
                if (rc != Sqlite.OK) throw new SchemaError.SQL (_("The database could not be opened."));
                d.read_only = true;
            }
            d.db.busy_timeout (3000);
            d.db.extended_result_codes (1);
            d.exec ("PRAGMA foreign_keys = ON");
            try {
                d.exec ("PRAGMA temp_store = MEMORY");
                d.exec ("SELECT count(*) FROM sqlite_master");
            } catch (Error e) {
                throw new SchemaError.SQL (_("This file is not a database or it is encrypted."));
            }
            if (create) {
                if (path_is_sdb (path)) {
                    d.exec ("PRAGMA application_id = %d".printf (APPLICATION_ID));
                    d.ensure_meta ();
                }
            }
            d.is_sdb = d.query_int ("PRAGMA application_id") == APPLICATION_ID || path_is_sdb (path);
            SqlFunctions.register (d.db);
            if (!create) Links.attach_all (d);
            return d;
        }

        public static Database create (string path) throws Error {
            if (FileUtils.test (path, FileTest.EXISTS)) FileUtils.remove (path);
            return open (path, true);
        }

        public static Database memory () throws Error {
            var d = new Database ();
            d.path = ":memory:";
            Sqlite.Database.open_v2 (":memory:", out d.db, Sqlite.OPEN_READWRITE | Sqlite.OPEN_CREATE);
            d.exec ("PRAGMA foreign_keys = ON");
            d.is_sdb = true;
            SqlFunctions.register (d.db);
            return d;
        }

        [CCode (cname = "sqlite3_column_decltype")]
        public static extern unowned string? column_decltype (Sqlite.Statement stmt, int col);

        public unowned Sqlite.Database handle () {
            return db;
        }

        public string display_name () {
            if (path == ":memory:") return _("Untitled Database");
            string b = Path.get_basename (path);
            int dot = b.last_index_of (".");
            return dot > 0 ? b.substring (0, dot) : b;
        }

        public void exec (string sql) throws SchemaError {
            string? err;
            int rc = db.exec (sql, null, out err);
            if (rc != Sqlite.OK) throw new SchemaError.SQL (err ?? db.errmsg ());
        }

        public Sqlite.Statement prepare (string sql) throws SchemaError {
            Sqlite.Statement stmt;
            int rc = db.prepare_v2 (sql, -1, out stmt);
            if (rc != Sqlite.OK) throw new SchemaError.SQL (db.errmsg ());
            return stmt;
        }

        public static void bind (Sqlite.Statement stmt, int index, DbValue v) {
            switch (v.kind) {
                case ValueKind.NULL: stmt.bind_null (index); break;
                case ValueKind.INTEGER: stmt.bind_int64 (index, v.int_value); break;
                case ValueKind.REAL: stmt.bind_double (index, v.real_value); break;
                case ValueKind.TEXT: stmt.bind_text (index, v.text_value); break;
                case ValueKind.BLOB:
                    unowned uint8[] data = v.blob_value.get_data ();
                    uint8[] copy = data;
                    stmt.bind_blob (index, (owned) copy, data.length, g_free);
                    break;
            }
        }

        public static DbValue column (Sqlite.Statement stmt, int i) {
            switch (stmt.column_type (i)) {
                case Sqlite.INTEGER: return new DbValue.int (stmt.column_int64 (i));
                case Sqlite.FLOAT: return new DbValue.real (stmt.column_double (i));
                case Sqlite.TEXT: return new DbValue.text (stmt.column_text (i) ?? "");
                case Sqlite.BLOB:
                    int n = stmt.column_bytes (i);
                    uint8* p = stmt.column_blob (i);
                    uint8[] copy = new uint8[n];
                    if (n > 0) Memory.copy (copy, p, n);
                    return new DbValue.blob (new Bytes.take ((owned) copy));
                default: return new DbValue.null ();
            }
        }

        public void check (int rc) throws SchemaError {
            if (rc != Sqlite.OK && rc != Sqlite.DONE && rc != Sqlite.ROW) {
                int basic = rc & 0xff;
                if (basic == Sqlite.CONSTRAINT) throw new SchemaError.CONSTRAINT (validation_message (db.errmsg ()));
                throw new SchemaError.SQL (db.errmsg ());
            }
        }

        public static string friendly_constraint (string msg) {
            if (msg.has_prefix ("FOREIGN KEY constraint failed")) return _("The change breaks a relationship: a related record is missing or other records still depend on this one.");
            if (msg.has_prefix ("NOT NULL constraint failed: ")) {
                string col = msg.substring ("NOT NULL constraint failed: ".length);
                int dot = col.index_of (".");
                return _("\"%s\" is required.").printf (dot >= 0 ? col.substring (dot + 1) : col);
            }
            if (msg.has_prefix ("UNIQUE constraint failed: ")) {
                string col = msg.substring ("UNIQUE constraint failed: ".length);
                int dot = col.index_of (".");
                return _("Another record already has this value in \"%s\".").printf (dot >= 0 ? col.substring (dot + 1) : col);
            }
            if (msg.has_prefix ("CHECK constraint failed")) return _("The value is not allowed by the field rules.");
            return msg;
        }

        public string validation_message (string msg) {
            string key = "CHECK constraint failed: ";
            int at = msg.index_of (key);
            if (at < 0) return friendly_constraint (msg);
            string name = msg.substring (at + key.length).strip ();
            try {
                if (name.has_prefix ("vr:")) {
                    string rest = name.substring (3);
                    if (rest.has_prefix ("_sdb_new_")) rest = rest.substring (9);
                    int dot = rest.last_index_of (".");
                    if (dot > 0) {
                        var def = load_table (rest.substring (0, dot));
                        var f = def.find (rest.substring (dot + 1));
                        if (f != null) {
                            if (f.validation_text != "") return f.validation_text;
                            return _("The value entered for \"%s\" is not allowed by its validation rule %s.").printf (f.label (), f.validation_rule != "" ? f.validation_rule : f.validation);
                        }
                    }
                } else if (name.has_prefix ("tvr:")) {
                    string t = name.substring (4);
                    if (t.has_prefix ("_sdb_new_")) t = t.substring (9);
                    var def = load_table (t);
                    if (def.validation_text != "") return def.validation_text;
                    return _("The record is not allowed by the table validation rule %s.").printf (def.validation_rule);
                }
            } catch (Error e) {
            }
            return friendly_constraint (msg);
        }

        public ResultSet query (string sql, DbValue[]? args = null, int limit = -1) throws SchemaError {
            var stmt = prepare (sql);
            if (args != null) {
                for (int i = 0; i < args.length; i++) bind (stmt, i + 1, args[i]);
            }
            var rs = new ResultSet ();
            int n = stmt.column_count ();
            string[] cols = new string[n];
            for (int i = 0; i < n; i++) cols[i] = stmt.column_name (i) ?? "";
            rs.columns = cols;
            int rc;
            int count = 0;
            while ((rc = stmt.step ()) == Sqlite.ROW) {
                if (limit >= 0 && count >= limit) break;
                DbValue[] vals = new DbValue[n];
                for (int i = 0; i < n; i++) vals[i] = column (stmt, i);
                rs.rows.add (new Row (count, (owned) vals));
                count++;
            }
            if (rc != Sqlite.ROW) check (rc);
            rs.changes = db.changes ();
            return rs;
        }

        public int64 query_int (string sql, DbValue[]? args = null) throws SchemaError {
            var rs = query (sql, args, 1);
            if (rs.rows.size == 0) return 0;
            return rs.rows[0].get (0).as_int ();
        }

        public int run (string sql, DbValue[]? args = null) throws SchemaError {
            var stmt = prepare (sql);
            if (args != null) {
                for (int i = 0; i < args.length; i++) bind (stmt, i + 1, args[i]);
            }
            int rc;
            while ((rc = stmt.step ()) == Sqlite.ROW) {
            }
            check (rc);
            return db.changes ();
        }

        public int64 last_insert_rowid () {
            return db.last_insert_rowid ();
        }

        public int total_changes () {
            return db.total_changes ();
        }

        public void begin () throws SchemaError {
            exec ("SAVEPOINT sdb_op");
        }

        public void commit () throws SchemaError {
            exec ("RELEASE sdb_op");
        }

        public void rollback () {
            try {
                exec ("ROLLBACK TO sdb_op");
                exec ("RELEASE sdb_op");
            } catch (Error e) {
            }
        }

        private void ensure_meta () throws SchemaError {
            exec ("CREATE TABLE IF NOT EXISTS %s (key TEXT PRIMARY KEY, value TEXT)".printf (META_TABLE));
        }

        public bool has_meta_table () {
            try {
                return query_int ("SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name = ?", { new DbValue.text (META_TABLE) }) > 0;
            } catch (Error e) {
                return false;
            }
        }

        public string? get_meta (string key) {
            if (!has_meta_table ()) return null;
            try {
                var rs = query ("SELECT value FROM %s WHERE key = ?".printf (META_TABLE), { new DbValue.text (key) });
                if (rs.rows.size == 0) return null;
                var v = rs.rows[0].get (0);
                return v.is_null ? null : v.to_string ();
            } catch (Error e) {
                return null;
            }
        }

        public void set_meta (string key, string? value) throws SchemaError {
            if (value == null) {
                if (has_meta_table ()) run ("DELETE FROM %s WHERE key = ?".printf (META_TABLE), { new DbValue.text (key) });
                return;
            }
            ensure_meta ();
            run ("INSERT OR REPLACE INTO %s (key, value) VALUES (?, ?)".printf (META_TABLE), { new DbValue.text (key), new DbValue.text (value) });
        }

        public Gee.ArrayList<string> meta_keys (string prefix) {
            var list = new Gee.ArrayList<string> ();
            if (!has_meta_table ()) return list;
            try {
                var rs = query ("SELECT key FROM %s WHERE substr(key, 1, ?) = ? ORDER BY key".printf (META_TABLE), { new DbValue.int (prefix.length), new DbValue.text (prefix) });
                foreach (var r in rs.rows) list.add (r.get (0).to_string ());
            } catch (Error e) {
            }
            return list;
        }

        public static bool is_internal (string name) {
            return name.has_prefix ("sqlite_") || name.has_prefix ("_sdb_");
        }

        public Gee.HashMap<string, LinkDef> linked = new Gee.HashMap<string, LinkDef> ();
        public Gee.HashMap<string, ServerSnapshot> server_data = new Gee.HashMap<string, ServerSnapshot> ();
        public Gee.ArrayList<LinkChange> link_changes = new Gee.ArrayList<LinkChange> ();
        public signal void link_changed ();

        public void register_link_hook () {
            db.create_function ("sdb_link_change", 4, Sqlite.UTF8, (void*) this, (ctx, args) => {
                unowned Database self = ctx.user_data<Database> ();
                var c = new LinkChange ();
                c.link = args[0].to_text () ?? "";
                c.op = args[1].to_text () ?? "";
                if (args[2].to_type () != Sqlite.NULL) c.key = Meta.parse_object (args[2].to_text ());
                if (args[3].to_type () != Sqlite.NULL) c.values = Meta.parse_object (args[3].to_text ());
                self.link_changes.add (c);
                self.link_changed ();
                ctx.result_null ();
            }, null, null);
        }

        public LinkDef? link_of (string name) {
            var l = linked[name.casefold ()];
            return l != null && l.available ? l : null;
        }

        public bool is_linked (string name) {
            if (link_of (name) == null) return false;
            try {
                return query_int ("SELECT count(*) FROM main.sqlite_master WHERE type = 'table' AND name = ? COLLATE NOCASE", { new DbValue.text (name) }) == 0;
            } catch (Error e) {
                return false;
            }
        }

        public Gee.ArrayList<string> table_names () {
            var list = new Gee.ArrayList<string> ();
            var seen = new Gee.HashSet<string> ();
            try {
                var rs = query ("SELECT name FROM main.sqlite_master WHERE type = 'table' ORDER BY name COLLATE NOCASE");
                foreach (var r in rs.rows) {
                    string n = r.get (0).to_string ();
                    if (!is_internal (n)) {
                        list.add (n);
                        seen.add (n.casefold ());
                    }
                }
            } catch (Error e) {
            }
            bool added = false;
            foreach (var l in linked.values) {
                if (l.available && seen.add (l.name.casefold ())) {
                    list.add (l.name);
                    added = true;
                }
            }
            if (added) list.sort ((a, b) => a.casefold ().collate (b.casefold ()));
            return list;
        }

        public Gee.ArrayList<string> view_names () {
            var list = new Gee.ArrayList<string> ();
            try {
                var rs = query ("SELECT name FROM sqlite_master WHERE type = 'view' ORDER BY name COLLATE NOCASE");
                foreach (var r in rs.rows) {
                    string n = r.get (0).to_string ();
                    if (!is_internal (n)) list.add (n);
                }
            } catch (Error e) {
            }
            return list;
        }

        public bool object_exists (string name, string? type = null) {
            if ((type == null || type == "table") && link_of (name) != null) return true;
            try {
                if (type != null) return query_int ("SELECT count(*) FROM sqlite_master WHERE name = ? COLLATE NOCASE AND type = ?", { new DbValue.text (name), new DbValue.text (type) }) > 0;
                return query_int ("SELECT count(*) FROM sqlite_master WHERE name = ? COLLATE NOCASE AND type IN ('table', 'view')", { new DbValue.text (name) }) > 0;
            } catch (Error e) {
                return false;
            }
        }

        public string? object_sql (string name) {
            var link = link_of (name);
            if (link != null && is_linked (name)) {
                try {
                    var lr = query ("SELECT sql FROM %s.sqlite_master WHERE name = ? COLLATE NOCASE".printf (Sql.quote_ident (link.schema)), { new DbValue.text (link.stored_name ()) });
                    if (lr.rows.size > 0) return lr.rows[0].get (0).to_string ();
                } catch (Error e) {
                }
            }
            try {
                var rs = query ("SELECT sql FROM sqlite_master WHERE name = ? COLLATE NOCASE", { new DbValue.text (name) });
                if (rs.rows.size == 0) return null;
                return rs.rows[0].get (0).to_string ();
            } catch (Error e) {
                return null;
            }
        }

        public string unique_object_name (string base_name) {
            if (!object_exists (base_name) && get_meta ("form:" + base_name) == null && get_meta ("report:" + base_name) == null) return base_name;
            for (int i = 2; ; i++) {
                string n = "%s %d".printf (base_name, i);
                if (!object_exists (n) && get_meta ("form:" + n) == null && get_meta ("report:" + n) == null) return n;
            }
        }

        public int64 count_rows (string table) {
            try {
                return query_int ("SELECT count(*) FROM %s".printf (Sql.quote_ident (table)));
            } catch (Error e) {
                return 0;
            }
        }

        public void invalidate () {
            table_cache.clear ();
        }

        public TableDef load_table (string name) throws SchemaError {
            string key = name.casefold ();
            if (table_cache.has_key (key)) return table_cache[key].copy ();
            var def = introspect (name);
            table_cache[key] = def;
            return def.copy ();
        }

        private TableDef introspect (string name) throws SchemaError {
            var link = is_linked (name) ? link_of (name) : null;
            string sp = link != null ? Sql.quote_ident (link.schema) + "." : "main.";
            var rs0 = query ("SELECT name, sql FROM %ssqlite_master WHERE type = 'table' AND name = ? COLLATE NOCASE".printf (sp), { new DbValue.text (link != null ? link.stored_name () : name) });
            if (rs0.rows.size == 0) throw new SchemaError.NOT_FOUND (_("The table \"%s\" does not exist.").printf (name));
            string real_name = rs0.rows[0].get (0).to_string ();
            string create = rs0.rows[0].get (1).to_string ();
            var def = new TableDef (real_name);
            if (link != null) {
                def.link_path = link.path;
                def.link_table = link.table;
            }
            string q = Sql.quote_ident (real_name);
            var info = query ("PRAGMA %stable_xinfo(%s)".printf (sp, q));
            int pk_count = 0;
            foreach (var r in info.rows) {
                if (r.get (5).as_int () > 0) pk_count++;
            }
            var checks = SchemaParser.column_checks (create);
            bool autoinc = create.up ().contains ("AUTOINCREMENT");
            foreach (var r in info.rows) {
                string col = r.get (1).to_string ();
                string decl = r.get (2).to_string ();
                int64 hidden = r.get (6).as_int ();
                if (hidden == 1) continue;
                var f = new Field (col, FieldType.from_declared (decl));
                f.table_name = real_name;
                if (hidden == 2 || hidden == 3) f.expression = SchemaParser.generated_expression (create, col);
                f.required = r.get (3).as_int () != 0;
                var dv = r.get (4);
                if (!dv.is_null) f.default_value = SchemaParser.default_to_input (dv.to_string ());
                f.primary_key = r.get (5).as_int () > 0;
                if (f.primary_key && pk_count == 1 && decl.up () == "INTEGER" && (autoinc || !def.without_rowid)) {
                    f.field_type = FieldType.AUTONUMBER;
                }
                int paren = decl.index_of ("(");
                if (paren > 0 && f.field_type.is_text ()) {
                    int close = decl.index_of (")", paren);
                    if (close > paren) f.max_length = int.parse (decl.substring (paren + 1, close - paren - 1));
                }
                var ck = checks[col.casefold ()];
                if (ck != null) {
                    if (ck.choices.length > 0 && f.field_type == FieldType.TEXT) {
                        f.field_type = FieldType.CHOICE;
                        f.choices = ck.choices;
                    } else if (ck.choices.length > 0 && f.field_type == FieldType.CHOICE) {
                        f.choices = ck.choices;
                    }
                    if (ck.max_length > 0) f.max_length = ck.max_length;
                    f.validation = ck.other;
                }
                def.fields.add (f);
            }
            def.without_rowid = create.up ().contains ("WITHOUT ROWID");
            var idx = query ("PRAGMA %sindex_list(%s)".printf (sp, q));
            foreach (var r in idx.rows) {
                string iname = r.get (1).to_string ();
                bool unique = r.get (2).as_int () != 0;
                string origin = r.get (3).to_string ();
                var cols = query ("PRAGMA %sindex_info(%s)".printf (sp, Sql.quote_ident (iname)));
                string[] names = {};
                foreach (var c in cols.rows) names += c.get (2).to_string ();
                if (origin == "pk") continue;
                if (origin == "u" && names.length == 1) {
                    var f = def.find (names[0]);
                    if (f != null) f.unique = true;
                    continue;
                }
                if (origin == "u") {
                    def.indexes.add (new IndexDef (iname, names, true));
                    continue;
                }
                if (names.length == 1 && !unique && iname.has_prefix ("idx_%s_".printf (real_name))) {
                    var f = def.find (names[0]);
                    if (f != null) {
                        f.indexed = true;
                        continue;
                    }
                }
                def.indexes.add (new IndexDef (iname, names, unique));
            }
            var fks = query ("PRAGMA %sforeign_key_list(%s)".printf (sp, q));
            var by_id = new Gee.TreeMap<int, Relationship> ();
            foreach (var r in fks.rows) {
                int id = (int) r.get (0).as_int ();
                string ref_table = r.get (2).to_string ();
                string from = r.get (3).to_string ();
                var to_v = r.get (4);
                string to = to_v.is_null ? "" : to_v.to_string ();
                Relationship rel;
                if (!by_id.has_key (id)) {
                    rel = new Relationship (real_name, from, ref_table, to);
                    rel.on_update = RefAction.parse (r.get (5).to_string ());
                    rel.on_delete = RefAction.parse (r.get (6).to_string ());
                    by_id[id] = rel;
                } else {
                    rel = by_id[id];
                    string[] a = rel.columns;
                    a += from;
                    rel.columns = a;
                    string[] b = rel.ref_columns;
                    b += to;
                    rel.ref_columns = b;
                }
            }
            foreach (var rel in by_id.values) {
                for (int i = 0; i < rel.ref_columns.length; i++) {
                    if (rel.ref_columns[i] == "") {
                        try {
                            var pk = primary_key_of (rel.ref_table);
                            if (i < pk.length) {
                                string[] rc = rel.ref_columns;
                                rc[i] = pk[i];
                                rel.ref_columns = rc;
                            }
                        } catch (Error e) {
                        }
                    }
                }
                def.relationships.add (rel);
            }
            if (link != null) {
                try {
                    var mr = query ("SELECT value FROM %s._sdb_meta WHERE key = ?".printf (Sql.quote_ident (link.schema)), { new DbValue.text ("table:" + real_name) });
                    if (mr.rows.size > 0) Meta.apply_table (def, mr.rows[0].get (0).to_string ());
                } catch (Error e) {
                }
                derive_lookups (def);
                return def;
            }
            apply_meta (def);
            return def;
        }

        private string[] primary_key_of (string table) throws SchemaError {
            var info = query ("PRAGMA table_info(%s)".printf (Sql.quote_ident (table)));
            var ordered = new Gee.TreeMap<int, string> ();
            foreach (var r in info.rows) {
                int k = (int) r.get (5).as_int ();
                if (k > 0) ordered[k] = r.get (1).to_string ();
            }
            string[] list = {};
            foreach (var v in ordered.values) list += v;
            if (list.length == 0) list += "rowid";
            return list;
        }

        private void apply_meta (TableDef def) {
            string? json = get_meta ("table:" + def.name);
            if (json == null) {
                derive_lookups (def);
                return;
            }
            Meta.apply_table (def, json);
            derive_lookups (def);
        }

        private void derive_lookups (TableDef def) {
            foreach (var rel in def.relationships) {
                if (rel.columns.length != 1) continue;
                var f = def.find (rel.columns[0]);
                if (f == null) continue;
                if (f.field_type == FieldType.LOOKUP) {
                    if (f.lookup_table == "") f.lookup_table = rel.ref_table;
                    if (f.lookup_field == "") f.lookup_field = rel.ref_columns[0];
                }
            }
            var keep = new Gee.ArrayList<Relationship> ();
            foreach (var rel in def.relationships) {
                bool from_lookup = false;
                if (rel.columns.length == 1) {
                    var f = def.find (rel.columns[0]);
                    if (f != null && f.field_type == FieldType.LOOKUP && f.lookup_table.casefold () == rel.ref_table.casefold () && f.lookup_field.casefold () == rel.ref_columns[0].casefold () && rel.on_delete == RefAction.NO_ACTION && rel.on_update == RefAction.NO_ACTION) from_lookup = true;
                }
                if (!from_lookup) keep.add (rel);
            }
            def.relationships = keep;
        }

        public Gee.ArrayList<Relationship> all_relationships () {
            var list = new Gee.ArrayList<Relationship> ();
            foreach (string t in table_names ()) {
                try {
                    var def = load_table (t);
                    foreach (var r in def.effective_relationships ()) list.add (r);
                } catch (Error e) {
                }
            }
            list.add_all (soft_relationships ());
            return list;
        }

        public Gee.ArrayList<Relationship> soft_relationships () {
            var list = new Gee.ArrayList<Relationship> ();
            string? json = get_meta ("relationships:soft");
            if (json == null) return list;
            try {
                var p = new Json.Parser ();
                p.load_from_data (json);
                p.get_root ().get_array ().foreach_element ((a, i, n) => {
                    var o = n.get_object ();
                    var r = new Relationship (o.get_string_member_with_default ("table", ""), "", o.get_string_member_with_default ("ref-table", ""), "");
                    r.columns = Meta.string_array (o, "columns");
                    r.ref_columns = Meta.string_array (o, "ref-columns");
                    r.enforce = false;
                    if (r.columns.length > 0 && r.ref_columns.length == r.columns.length && object_exists (r.table, "table") && object_exists (r.ref_table, "table")) list.add (r);
                });
            } catch (Error e) {
            }
            return list;
        }

        public void save_soft_relationships (Gee.List<Relationship> list) throws Error {
            var b = new Json.Builder ();
            b.begin_array ();
            foreach (var r in list) {
                b.begin_object ();
                b.set_member_name ("table").add_string_value (r.table);
                b.set_member_name ("ref-table").add_string_value (r.ref_table);
                b.set_member_name ("columns").begin_array ();
                foreach (string c in r.columns) b.add_string_value (c);
                b.end_array ();
                b.set_member_name ("ref-columns").begin_array ();
                foreach (string c in r.ref_columns) b.add_string_value (c);
                b.end_array ();
                b.end_object ();
            }
            b.end_array ();
            save_object_meta (_("Change Relationships"), "relationships:", "soft", list.size > 0 ? Json.to_string (b.get_root (), false) : null);
        }

        public Gee.ArrayList<Relationship> relationships_to (string table) {
            var list = new Gee.ArrayList<Relationship> ();
            foreach (var r in all_relationships ()) {
                if (r.ref_table.casefold () == table.casefold ()) list.add (r);
            }
            return list;
        }

        public string[] view_columns (string name) {
            string[] cols = {};
            try {
                var stmt = prepare ("SELECT * FROM %s LIMIT 0".printf (Sql.quote_ident (name)));
                for (int i = 0; i < stmt.column_count (); i++) cols += stmt.column_name (i);
            } catch (Error e) {
            }
            return cols;
        }

        public string[] columns_of (string name) {
            if (object_exists (name, "table")) {
                try {
                    var def = load_table (name);
                    string[] cols = {};
                    foreach (var f in def.fields) cols += f.name;
                    return cols;
                } catch (Error e) {
                }
            }
            return view_columns (name);
        }

        private Snapshot capture (string name, string[] meta_prefixes) throws SchemaError {
            var s = new Snapshot ();
            s.name = name;
            var rs = query ("SELECT type, sql, name FROM sqlite_master WHERE name = ? COLLATE NOCASE AND type IN ('table', 'view')", { new DbValue.text (name) });
            if (rs.rows.size > 0) {
                s.kind = rs.rows[0].get (0).to_string ();
                s.create_sql = rs.rows[0].get (1).to_string ();
                s.name = rs.rows[0].get (2).to_string ();
                if (s.kind == "table") {
                    s.def = load_table (s.name);
                    s.backup = "_sdb_undo_%d".printf (++backup_counter);
                    string[] keep = {};
                    foreach (var f in s.def.fields) {
                        if (!f.is_calculated ()) keep += Sql.quote_ident (f.name);
                    }
                    exec ("CREATE TEMP TABLE %s AS SELECT rowid AS _sdb_rowid, %s FROM main.%s".printf (Sql.quote_ident (s.backup), keep.length > 0 ? string.joinv (", ", keep) : "*", Sql.quote_ident (s.name)));
                    var ix = query ("SELECT sql FROM sqlite_master WHERE type IN ('index', 'trigger') AND tbl_name = ? COLLATE NOCASE AND sql IS NOT NULL", { new DbValue.text (s.name) });
                    string[] extra = {};
                    foreach (var r in ix.rows) extra += r.get (0).to_string ();
                    s.extra_sql = extra;
                }
            }
            string[] keys = {};
            foreach (string p in meta_prefixes) {
                string k = p + name;
                keys += k;
                s.meta[k] = get_meta (k);
            }
            s.meta_keys = keys;
            return s;
        }

        private void restore (Snapshot s) throws SchemaError {
            var cur = query ("SELECT type, name FROM sqlite_master WHERE name = ? COLLATE NOCASE AND type IN ('table', 'view')", { new DbValue.text (s.name) });
            if (cur.rows.size > 0) {
                string t = cur.rows[0].get (0).to_string ();
                exec ("DROP %s main.%s".printf (t == "view" ? "VIEW" : "TABLE", Sql.quote_ident (cur.rows[0].get (1).to_string ())));
            }
            if (s.kind == "view") {
                exec (s.create_sql);
            } else if (s.kind == "table") {
                exec (s.create_sql);
                string[] cols = {};
                foreach (var f in s.def.fields) {
                    if (!f.is_calculated ()) cols += Sql.quote_ident (f.name);
                }
                string list = string.joinv (", ", cols);
                string rowid = s.def.without_rowid ? "" : "rowid, ";
                string rowsrc = s.def.without_rowid ? "" : "_sdb_rowid, ";
                exec ("INSERT INTO main.%s (%s%s) SELECT %s%s FROM temp.%s".printf (Sql.quote_ident (s.name), rowid, list, rowsrc, list, Sql.quote_ident (s.backup)));
                foreach (string x in s.extra_sql) exec (x);
            }
            foreach (string k in s.meta_keys) set_meta (k, s.meta[k]);
        }

        private void drop_backup (Snapshot s) {
            if (s.backup == "") return;
            try {
                exec ("DROP TABLE IF EXISTS temp.%s".printf (Sql.quote_ident (s.backup)));
            } catch (Error e) {
            }
        }

        private const string[] TABLE_META = { "table:", "views:", "layout-table:" };

        public delegate void DesignOp () throws Error;

        public void design_change (string label, string[] names, owned DesignOp op, string[]? meta_prefixes = null) throws Error {
            string[] prefixes = meta_prefixes ?? TABLE_META;
            var before = new Gee.ArrayList<Snapshot> ();
            exec ("PRAGMA foreign_keys = OFF");
            exec ("PRAGMA legacy_alter_table = ON");
            try {
                begin ();
                try {
                    if (recording) {
                        foreach (string n in names) before.add (capture (n, prefixes));
                    }
                    op ();
                    var violations = query ("PRAGMA foreign_key_check");
                    if (violations.rows.size > 0) {
                        bool related = false;
                        foreach (var v in violations.rows) {
                            string vt = v.get (0).to_string ();
                            foreach (string n in names) {
                                if (vt.casefold () == n.casefold ()) related = true;
                            }
                        }
                        if (related) {
                            throw new SchemaError.CONSTRAINT (ngettext ("%d record does not match the relationship rules, so the change was not applied.", "%d records do not match the relationship rules, so the change was not applied.", violations.rows.size).printf (violations.rows.size));
                        }
                    }
                    commit ();
                } catch (Error e) {
                    rollback ();
                    foreach (var s in before) drop_backup (s);
                    invalidate ();
                    throw e;
                }
            } finally {
                try {
                    exec ("PRAGMA legacy_alter_table = OFF");
                    exec ("PRAGMA foreign_keys = ON");
                } catch (Error e) {
                }
            }
            invalidate ();
            if (recording) {
                var entry = new UndoEntry (label, true);
                entry.before = before;
                push_undo (entry);
            }
            schema_changed ();
        }

        private void push_undo (UndoEntry e) {
            undo_stack.add (e);
            if (undo_stack.size > 100) {
                var old = undo_stack.remove_at (0);
                release (old);
            }
            foreach (var r in redo_stack) release (r);
            redo_stack.clear ();
            history_changed ();
        }

        private void release (UndoEntry e) {
            if (e.before != null) foreach (var s in e.before) drop_backup (s);
            if (e.after != null) foreach (var s in e.after) drop_backup (s);
        }

        public void record_data (string label, string[] undo_sql, string[] redo_sql) {
            if (!recording) return;
            var e = new UndoEntry (label, false);
            e.undo_sql = undo_sql;
            e.redo_sql = redo_sql;
            push_undo (e);
        }

        private Gee.ArrayList<Snapshot> swap (Gee.ArrayList<Snapshot> target) throws Error {
            var current = new Gee.ArrayList<Snapshot> ();
            exec ("PRAGMA foreign_keys = OFF");
            exec ("PRAGMA legacy_alter_table = ON");
            try {
                begin ();
                try {
                    foreach (var s in target) {
                        string[] prefixes = {};
                        foreach (string k in s.meta_keys) prefixes += k.substring (0, k.length - s.name.length);
                        current.add (capture (s.name, prefixes));
                    }
                    foreach (var s in target) restore (s);
                    commit ();
                } catch (Error e) {
                    rollback ();
                    foreach (var s in current) drop_backup (s);
                    throw e;
                }
            } finally {
                try {
                    exec ("PRAGMA legacy_alter_table = OFF");
                    exec ("PRAGMA foreign_keys = ON");
                } catch (Error e) {
                }
            }
            foreach (var s in target) drop_backup (s);
            invalidate ();
            return current;
        }

        private void run_script (string[] stmts) throws Error {
            begin ();
            try {
                foreach (string s in stmts) exec (s);
                commit ();
            } catch (Error e) {
                rollback ();
                throw e;
            }
        }

        public void undo () throws Error {
            if (undo_stack.size == 0) return;
            var e = undo_stack[undo_stack.size - 1];
            if (e.design) {
                e.after = swap (e.before);
                e.before = null;
                schema_changed ();
            } else {
                run_script (e.undo_sql);
                data_changed ("");
            }
            undo_stack.remove_at (undo_stack.size - 1);
            redo_stack.add (e);
            history_changed ();
        }

        public void redo () throws Error {
            if (redo_stack.size == 0) return;
            var e = redo_stack[redo_stack.size - 1];
            if (e.design) {
                e.before = swap (e.after);
                e.after = null;
                schema_changed ();
            } else {
                run_script (e.redo_sql);
                data_changed ("");
            }
            redo_stack.remove_at (redo_stack.size - 1);
            undo_stack.add (e);
            history_changed ();
        }

        public void clear_history () {
            foreach (var e in undo_stack) release (e);
            foreach (var e in redo_stack) release (e);
            undo_stack.clear ();
            redo_stack.clear ();
            history_changed ();
        }

        public void create_table (TableDef def) throws Error {
            def.validate ();
            if (object_exists (def.name)) throw new SchemaError.INVALID (_("An object named \"%s\" already exists.").printf (def.name));
            check_lookups (def);
            design_change (_("Create Table"), { def.name }, () => {
                exec (def.create_sql ());
                foreach (string s in def.index_sql ()) exec (s);
                write_table_meta (def);
            });
        }

        private void check_lookups (TableDef def) throws Error {
            foreach (var r in def.effective_relationships ()) {
                if (r.ref_table.casefold () == def.name.casefold ()) {
                    foreach (string c in r.ref_columns) {
                        if (def.find (c) == null) throw new SchemaError.INVALID (_("The related field \"%s\" does not exist.").printf (c));
                    }
                    continue;
                }
                if (!object_exists (r.ref_table, "table")) throw new SchemaError.INVALID (_("The related table \"%s\" does not exist.").printf (r.ref_table));
                if (r.enforce && is_linked (r.ref_table)) throw new SchemaError.INVALID (_("Referential integrity cannot be enforced with the linked table \"%s\". Create the relationship in its database.").printf (r.ref_table));
                var other = load_table (r.ref_table);
                foreach (string c in r.ref_columns) {
                    var f = other.find (c);
                    if (f == null) throw new SchemaError.INVALID (_("The related field \"%s\" does not exist in \"%s\".").printf (c, r.ref_table));
                }
                if (r.enforce && !references_unique (other, r.ref_columns)) {
                    throw new SchemaError.INVALID (_("To enforce the relationship, \"%s\" in \"%s\" must be a primary key or unique.").printf (string.joinv (", ", r.ref_columns), r.ref_table));
                }
            }
        }

        private static bool references_unique (TableDef t, string[] cols) {
            var pk = t.primary_key ();
            if (pk.size == cols.length) {
                bool all = true;
                foreach (string c in cols) {
                    var f = t.find (c);
                    if (f == null || !f.primary_key) all = false;
                }
                if (all) return true;
            }
            if (cols.length == 1) {
                var f = t.find (cols[0]);
                if (f != null && f.unique) return true;
            }
            foreach (var i in t.indexes) {
                if (!i.unique || i.columns.length != cols.length) continue;
                bool same = true;
                for (int k = 0; k < cols.length; k++) {
                    if (i.columns[k].casefold () != cols[k].casefold ()) same = false;
                }
                if (same) return true;
            }
            return false;
        }

        public void write_table_meta (TableDef def) throws SchemaError {
            if (!is_sdb && !has_meta_table () && !Meta.needs_meta (def)) return;
            set_meta ("table:" + def.name, Meta.table_json (def));
        }

        public void alter_table (string old_name, TableDef def, Gee.Map<string, string>? renames = null, string label = "") throws Error {
            if (is_linked (old_name)) throw new SchemaError.INVALID (_("\"%s\" is a linked table. Open its database to change the design.").printf (old_name));
            def.validate ();
            if (def.name.casefold () != old_name.casefold () && object_exists (def.name)) throw new SchemaError.INVALID (_("An object named \"%s\" already exists.").printf (def.name));
            check_lookups (def);
            var old = load_table (old_name);
            string[] names = { old.name };
            bool renamed = def.name.casefold () != old.name.casefold ();
            if (renamed) names += def.name;
            var children = new Gee.ArrayList<TableDef> ();
            if (renamed) {
                foreach (string t in table_names ()) {
                    if (t.casefold () == old.name.casefold ()) continue;
                    var cdef = load_table (t);
                    bool refers = false;
                    foreach (var r in cdef.relationships) {
                        if (r.ref_table.casefold () == old.name.casefold ()) {
                            r.ref_table = def.name;
                            refers = true;
                        }
                    }
                    foreach (var f in cdef.fields) {
                        if (f.field_type == FieldType.LOOKUP && f.lookup_table.casefold () == old.name.casefold ()) {
                            f.lookup_table = def.name;
                            refers = true;
                        }
                    }
                    if (refers) {
                        children.add (cdef);
                        names += cdef.name;
                    }
                }
            }
            design_change (label != "" ? label : _("Change Table Design"), names, () => {
                rebuild (old, def, renames);
                foreach (var cdef in children) {
                    var cold = load_table (cdef.name);
                    rebuild (cold, cdef, null);
                }
            });
        }

        private void rebuild (TableDef old, TableDef def, Gee.Map<string, string>? renames) throws Error {
            string tmp = "_sdb_new_%s".printf (def.name);
            exec (def.create_sql (tmp));
            string[] dst = {}, src = {};
            foreach (var f in def.fields) {
                if (f.is_calculated ()) continue;
                string? from = null;
                if (renames != null && renames.has_key (f.name)) from = renames[f.name];
                else if (old.find (f.name) != null) from = old.find (f.name).name;
                if (from == null || old.find (from) == null || old.find (from).is_calculated ()) continue;
                dst += Sql.quote_ident (f.name);
                src += convert_expr (old.find (from), f);
            }
            if (dst.length > 0) {
                string rowid_d = def.without_rowid || old.without_rowid ? "" : "rowid, ";
                exec ("INSERT INTO %s (%s%s) SELECT %s%s FROM %s".printf (Sql.quote_ident (tmp), rowid_d, string.joinv (", ", dst), rowid_d, string.joinv (", ", src), Sql.quote_ident (old.name)));
            }
            var triggers = query ("SELECT sql FROM sqlite_master WHERE type = 'trigger' AND tbl_name = ? COLLATE NOCASE", { new DbValue.text (old.name) });
            exec ("DROP TABLE %s".printf (Sql.quote_ident (old.name)));
            exec ("ALTER TABLE %s RENAME TO %s".printf (Sql.quote_ident (tmp), Sql.quote_ident (def.name)));
            foreach (string s in def.index_sql ()) exec (s);
            if (def.name == old.name) {
                foreach (var r in triggers.rows) {
                    try {
                        exec (r.get (0).to_string ());
                    } catch (Error e) {
                    }
                }
            }
            if (old.name.casefold () != def.name.casefold ()) {
                set_meta ("table:" + old.name, null);
                string? views = get_meta ("views:" + old.name);
                set_meta ("views:" + old.name, null);
                if (views != null) set_meta ("views:" + def.name, views);
            }
            write_table_meta (def);
        }

        private static string convert_expr (Field from, Field to) {
            string q = Sql.quote_ident (from.name);
            if (from.field_type == to.field_type) return q;
            switch (to.field_type) {
                case FieldType.INTEGER:
                case FieldType.AUTONUMBER:
                case FieldType.LOOKUP:
                    if (from.field_type.is_numeric ()) return "CAST(%s AS INTEGER)".printf (q);
                    return "CASE WHEN %s IS NULL OR trim(%s) = '' THEN NULL WHEN CAST(%s AS INTEGER) || '' = trim(%s) THEN CAST(%s AS INTEGER) ELSE %s END".printf (q, q, q, q, q, q);
                case FieldType.NUMBER:
                case FieldType.CURRENCY:
                case FieldType.PERCENT:
                    if (from.field_type.is_numeric ()) return "CAST(%s AS REAL)".printf (q);
                    return "CASE WHEN %s IS NULL OR trim(%s) = '' THEN NULL ELSE CAST(%s AS REAL) END".printf (q, q, q);
                case FieldType.BOOLEAN:
                    return "CASE WHEN %s IS NULL THEN NULL WHEN lower(CAST(%s AS TEXT)) IN ('1', 'true', 'yes', 'y', '-1', 'on') THEN 1 ELSE 0 END".printf (q, q);
                case FieldType.DATE:
                    if (from.field_type == FieldType.DATETIME) return "substr(%s, 1, 10)".printf (q);
                    return q;
                default:
                    if (to.field_type.is_text () && !from.field_type.is_text ()) {
                        if (from.field_type == FieldType.BOOLEAN) return "CASE WHEN %s IS NULL THEN NULL WHEN %s THEN 'Yes' ELSE 'No' END".printf (q, q);
                        return "CAST(%s AS TEXT)".printf (q);
                    }
                    return q;
            }
        }

        public void drop_object (string name) throws Error {
            if (is_linked (name) || (link_of (name) == null && linked.has_key (name.casefold ()))) {
                Links.remove (this, name);
                return;
            }
            bool is_view = object_exists (name, "view");
            if (!is_view && !object_exists (name, "table")) throw new SchemaError.NOT_FOUND (_("\"%s\" does not exist.").printf (name));
            string[] prefixes = is_view ? new string[] { "query:" } : TABLE_META;
            if (is_view) Links.unshadow (this);
            design_change (is_view ? _("Delete Query") : _("Delete Table"), { name }, () => {
                exec ("DROP %s %s".printf (is_view ? "VIEW" : "TABLE", Sql.quote_ident (name)));
                foreach (string p in prefixes) set_meta (p + name, null);
            }, prefixes);
            if (is_view) Links.shadow_views (this);
        }

        public void rename_table (string old_name, string new_name) throws Error {
            var def = load_table (old_name);
            def.name = new_name;
            alter_table (old_name, def, null, _("Rename Table"));
        }

        public void save_query (QueryDef q, string? old_name = null) throws Error {
            if (q.name.strip () == "") throw new SchemaError.INVALID (_("The query needs a name."));
            if (is_internal (q.name)) throw new SchemaError.INVALID (_("This name is reserved."));
            string stmt = q.sql.strip ();
            while (stmt.has_suffix (";")) stmt = stmt.substring (0, stmt.length - 1).strip ();
            if (!Sql.is_read_only (stmt) || stmt.up ().has_prefix ("PRAGMA") || stmt.up ().has_prefix ("EXPLAIN")) {
                throw new SchemaError.INVALID (_("Only SELECT queries can be saved as queries. Run action queries from the SQL view."));
            }
            bool renaming = old_name != null && old_name.casefold () != q.name.casefold ();
            if ((old_name == null || renaming) && object_exists (q.name)) throw new SchemaError.INVALID (_("An object named \"%s\" already exists.").printf (q.name));
            string[] names = { q.name };
            if (old_name != null && renaming) names += old_name;
            Links.unshadow (this);
            design_change (old_name == null ? _("Save Query") : _("Change Query"), names, () => {
                if (old_name != null) {
                    exec ("DROP VIEW IF EXISTS %s".printf (Sql.quote_ident (old_name)));
                    set_meta ("query:" + old_name, null);
                }
                exec ("CREATE VIEW %s AS %s".printf (Sql.quote_ident (q.name), stmt));
                try {
                    var check = prepare ("SELECT * FROM %s LIMIT 0".printf (Sql.quote_ident (q.name)));
                    check.step ();
                } catch (Error e) {
                    throw new SchemaError.SQL (e.message);
                }
                var b = new Json.Builder ();
                b.begin_object ();
                b.set_member_name ("design").add_string_value (q.design);
                b.set_member_name ("description").add_string_value (q.description);
                b.end_object ();
                if (q.design != "" || q.description != "" || has_meta_table () || is_sdb) set_meta ("query:" + q.name, Json.to_string (b.get_root (), false));
            }, { "query:" });
            Links.shadow_views (this);
        }

        public QueryDef? load_query (string name) {
            string? sql = object_sql (name);
            if (sql == null) return null;
            var toks = Sql.tokenize (sql, true);
            int as_pos = -1;
            int words = 0;
            foreach (var t in toks) {
                if (t.kind == TokenKind.WHITESPACE || t.kind == TokenKind.COMMENT) continue;
                words++;
                if (t.kind == TokenKind.KEYWORD && t.text.up () == "AS" && words >= 3) {
                    as_pos = t.end;
                    break;
                }
            }
            string body = as_pos >= 0 ? sql.substring (as_pos).strip () : sql;
            var q = new QueryDef (name, body);
            string? meta = get_meta ("query:" + name);
            if (meta != null) {
                try {
                    var p = new Json.Parser ();
                    p.load_from_data (meta);
                    var o = p.get_root ().get_object ();
                    q.design = o.has_member ("design") ? o.get_string_member ("design") : "";
                    q.description = o.has_member ("description") ? o.get_string_member ("description") : "";
                } catch (Error e) {
                }
            }
            return q;
        }

        public void save_object_meta (string label, string prefix, string name, string? json, string? old_name = null) throws Error {
            string[] names = { name };
            if (old_name != null && old_name != name) names += old_name;
            design_change (label, names, () => {
                if (old_name != null && old_name != name) set_meta (prefix + old_name, null);
                set_meta (prefix + name, json);
            }, { prefix });
        }

        public Gee.ArrayList<string> object_names (string prefix) {
            var list = new Gee.ArrayList<string> ();
            foreach (string k in meta_keys (prefix)) list.add (k.substring (prefix.length));
            list.sort ((a, b) => a.collate (b));
            return list;
        }

        public int64 insert_row (string table, string[] columns, DbValue[] values) throws Error {
            string[] q = {};
            string[] ph = {};
            foreach (string c in columns) {
                q += Sql.quote_ident (c);
                ph += "?";
            }
            string sql = columns.length == 0 ? "INSERT INTO %s DEFAULT VALUES".printf (Sql.quote_ident (table))
                : "INSERT INTO %s (%s) VALUES (%s)".printf (Sql.quote_ident (table), string.joinv (", ", q), string.joinv (", ", ph));
            run (sql, values);
            int64 id = last_insert_rowid ();
            string redo = full_row_insert (table, id);
            record_data (_("Add Record"), { "DELETE FROM %s WHERE rowid = %s".printf (Sql.quote_ident (table), id.to_string ()) }, { redo });
            data_changed (table);
            return id;
        }

        public string[] stored_columns (string table) {
            string[] cols = {};
            try {
                foreach (var f in load_table (table).fields) {
                    if (!f.is_calculated ()) cols += f.name;
                }
            } catch (Error e) {
            }
            return cols;
        }

        private string full_row_insert (string table, int64 rowid) throws Error {
            string[] stored = {};
            foreach (string c in stored_columns (table)) stored += Sql.quote_ident (c);
            var rs = query ("SELECT rowid, %s FROM %s WHERE rowid = ?".printf (stored.length > 0 ? string.joinv (", ", stored) : "*", Sql.quote_ident (table)), { new DbValue.int (rowid) });
            if (rs.rows.size == 0) return "SELECT 1";
            string[] cols = {};
            string[] vals = {};
            for (int i = 0; i < rs.columns.length; i++) {
                cols += i == 0 ? "rowid" : Sql.quote_ident (rs.columns[i]);
                vals += rs.rows[0].get (i).sql_literal ();
            }
            return "INSERT INTO %s (%s) VALUES (%s)".printf (Sql.quote_ident (table), string.joinv (", ", cols), string.joinv (", ", vals));
        }

        public void update_value (string table, int64 rowid, string column, DbValue value) throws Error {
            var old = query ("SELECT %s FROM %s WHERE rowid = ?".printf (Sql.quote_ident (column), Sql.quote_ident (table)), { new DbValue.int (rowid) });
            if (old.rows.size == 0) throw new SchemaError.NOT_FOUND (_("The record no longer exists."));
            var prev = old.rows[0].get (0);
            if (prev.kind == value.kind && prev.equals (value)) return;
            run ("UPDATE %s SET %s = ? WHERE rowid = ?".printf (Sql.quote_ident (table), Sql.quote_ident (column)), { value, new DbValue.int (rowid) });
            string tq = Sql.quote_ident (table), cq = Sql.quote_ident (column);
            int64 new_rowid = rowid;
            try {
                var def = load_table (table);
                var f = def.find (column);
                if (f != null && f.field_type == FieldType.AUTONUMBER && value.kind == ValueKind.INTEGER) new_rowid = value.int_value;
            } catch (Error e) {
            }
            record_data (_("Edit Value"),
                { "UPDATE %s SET %s = %s WHERE rowid = %s".printf (tq, cq, prev.sql_literal (), new_rowid.to_string ()) },
                { "UPDATE %s SET %s = %s WHERE rowid = %s".printf (tq, cq, value.sql_literal (), rowid.to_string ()) });
            data_changed (table);
        }

        public int delete_rows (string table, int64[] rowids) throws Error {
            if (rowids.length == 0) return 0;
            string[] undo = {};
            string[] redo = {};
            begin ();
            try {
                int before = total_changes ();
                foreach (int64 id in rowids) {
                    undo += full_row_insert (table, id);
                    redo += "DELETE FROM %s WHERE rowid = %s".printf (Sql.quote_ident (table), id.to_string ());
                    run ("DELETE FROM %s WHERE rowid = ?".printf (Sql.quote_ident (table)), { new DbValue.int (id) });
                }
                int cascaded = total_changes () - before - rowids.length;
                commit ();
                if (cascaded > 0) {
                    clear_history ();
                } else {
                    record_data (ngettext ("Delete Record", "Delete Records", rowids.length), undo, redo);
                }
            } catch (Error e) {
                rollback ();
                throw e;
            }
            data_changed (table);
            return rowids.length;
        }

        public int execute_script (string script, out ResultSet? last_result) throws Error {
            last_result = null;
            var stmts = Sql.split_statements (script);
            int changed = 0;
            bool ddl = false;
            foreach (string s in stmts) {
                string u = s.strip ().up ();
                if (u.has_prefix ("CREATE") || u.has_prefix ("DROP") || u.has_prefix ("ALTER")) ddl = true;
                if (Sql.is_read_only (s)) {
                    last_result = query (s);
                } else {
                    changed += run (s);
                }
            }
            if (ddl) {
                invalidate ();
                clear_history ();
                schema_changed ();
            } else if (changed > 0) {
                clear_history ();
                data_changed ("");
            }
            return changed;
        }

        public void close () {
            clear_history ();
            stop_change_watch ();
            db = null;
            if (is_encrypted) Crypt.clear_key (path);
        }

        public void vacuum_into (string target) throws Error {
            if (FileUtils.test (target, FileTest.EXISTS)) FileUtils.remove (target);
            if (is_encrypted) {
                encrypted_copy (target, password);
                return;
            }
            run ("VACUUM INTO ?", { new DbValue.text (target) });
        }

        public void compact () throws Error {
            clear_history ();
            exec ("VACUUM");
        }

        public string integrity_check () throws Error {
            var rs = query ("PRAGMA integrity_check");
            var sb = new StringBuilder ();
            foreach (var r in rs.rows) {
                if (sb.len > 0) sb.append ("\n");
                sb.append (r.get (0).to_string ());
            }
            var fk = query ("PRAGMA foreign_key_check");
            if (fk.rows.size > 0) {
                sb.append ("\n");
                sb.append (ngettext ("%d record breaks a relationship.", "%d records break relationships.", fk.rows.size).printf (fk.rows.size));
            }
            return sb.str;
        }

        private string? password;
        private ChangeWatcher? watcher;
        private RecordLocks? locks;

        public bool is_encrypted { get; private set; }

        public signal void external_change ();

        public static bool needs_password (string path) {
            return Crypt.is_encrypted (path);
        }

        public static Database open_with_password (string path, string password) throws Error {
            if (!FileUtils.test (path, FileTest.EXISTS)) throw new FileError.NOENT (_("The file does not exist."));
            if (!Crypt.is_encrypted (path)) throw new SchemaError.INVALID (_("This database is not protected with a password."));
            var d = new Database ();
            d.path = path;
            d.password = password;
            d.open_encrypted ();
            Links.attach_all (d);
            return d;
        }

        private void setup_handle () throws Error {
            db.busy_timeout (3000);
            db.extended_result_codes (1);
            exec ("PRAGMA foreign_keys = ON");
            exec ("PRAGMA temp_store = MEMORY");
            exec ("SELECT count(*) FROM sqlite_master");
            is_sdb = query_int ("PRAGMA application_id") == APPLICATION_ID || path_is_sdb (path);
            SqlFunctions.register (db);
        }

        private void open_encrypted () throws Error {
            Crypt.set_key (path, password);
            read_only = false;
            int rc = Sqlite.Database.open_v2 (path, out db, Sqlite.OPEN_READWRITE, Crypt.VFS);
            if (rc != Sqlite.OK && (rc & 0xff) != Sqlite.NOTADB) {
                rc = Sqlite.Database.open_v2 (path, out db, Sqlite.OPEN_READONLY, Crypt.VFS);
                read_only = true;
            }
            if (rc != Sqlite.OK) {
                db = null;
                Crypt.clear_key (path);
                if ((rc & 0xff) == Sqlite.NOTADB) throw new SchemaError.INVALID (_("The password is not correct."));
                throw new SchemaError.SQL (_("The database could not be opened."));
            }
            is_encrypted = true;
            try {
                setup_handle ();
            } catch (Error e) {
                bool wrong = (db.errcode () & 0xff) == Sqlite.NOTADB;
                db = null;
                is_encrypted = false;
                Crypt.clear_key (path);
                if (wrong) throw new SchemaError.INVALID (_("The password is not correct."));
                throw e;
            }
        }

        private void reopen () throws Error {
            if (is_encrypted) {
                open_encrypted ();
                return;
            }
            read_only = false;
            int rc = Sqlite.Database.open_v2 (path, out db, Sqlite.OPEN_READWRITE);
            if (rc != Sqlite.OK) {
                rc = Sqlite.Database.open_v2 (path, out db, Sqlite.OPEN_READONLY);
                read_only = true;
            }
            if (rc != Sqlite.OK) {
                db = null;
                throw new SchemaError.SQL (_("The database could not be opened."));
            }
            setup_handle ();
        }

        private void encrypted_copy (string target, string? new_password) throws Error {
            Crypt.register ();
            if (FileUtils.test (target, FileTest.EXISTS)) FileUtils.remove (target);
            if (new_password != null) Crypt.set_key (target, new_password);
            try {
                Sqlite.Database h;
                if (Sqlite.Database.open_v2 (path, out h, Sqlite.OPEN_READONLY, Crypt.VFS) != Sqlite.OK) throw new SchemaError.SQL (_("The database could not be opened."));
                h.busy_timeout (3000);
                if (new_password != null) Crypt.set_reserve (h, Crypt.RESERVE);
                string? err;
                if (h.exec ("VACUUM INTO " + Sql.quote_string (target), null, out err) != Sqlite.OK) {
                    FileUtils.remove (target);
                    throw new SchemaError.SQL (err ?? h.errmsg ());
                }
            } finally {
                if (new_password != null) Crypt.clear_key (target);
            }
        }

        private static void verify_copy (string target, string? new_password) throws Error {
            if (new_password != null) Crypt.set_key (target, new_password);
            try {
                Sqlite.Database h;
                if (Sqlite.Database.open_v2 (target, out h, Sqlite.OPEN_READONLY, new_password != null ? Crypt.VFS : null) != Sqlite.OK) throw new SchemaError.SQL (_("The new copy of the database could not be opened."));
                Sqlite.Statement st;
                if (h.prepare_v2 ("PRAGMA integrity_check", -1, out st) != Sqlite.OK || st.step () != Sqlite.ROW || st.column_text (0) != "ok") {
                    throw new SchemaError.SQL (_("The new copy of the database did not pass the integrity check."));
                }
            } finally {
                if (new_password != null) Crypt.clear_key (target);
            }
        }

        public void set_password (string? new_password) throws Error {
            if (db == null || path == ":memory:") throw new SchemaError.INVALID (_("Save the database to a file before setting a password."));
            if (read_only) throw new SchemaError.INVALID (_("The database is read-only, so its password cannot be changed."));
            if (new_password != null && new_password == "") throw new SchemaError.INVALID (_("The password cannot be empty."));
            if (new_password == null && !is_encrypted) return;
            string tmp = Crypt.temp_path (path, "rekey");
            try {
                encrypted_copy (tmp, new_password);
                verify_copy (tmp, new_password);
            } catch (Error e) {
                if (FileUtils.test (tmp, FileTest.EXISTS)) FileUtils.remove (tmp);
                throw e;
            }
            bool watching = watcher != null && watcher.running;
            clear_history ();
            stop_change_watch ();
            db = null;
            if (FileUtils.rename (tmp, path) != 0) {
                FileUtils.remove (tmp);
                reopen ();
                throw new SchemaError.SQL (_("The database file could not be replaced."));
            }
            if (is_encrypted) Crypt.clear_key (path);
            is_encrypted = new_password != null;
            password = new_password;
            reopen ();
            if (watching) start_change_watch (watcher.interval_seconds);
        }

        public string[] compact_and_repair () throws Error {
            string[] notes = {};
            bool healthy = false;
            try {
                var rs = query ("PRAGMA integrity_check");
                healthy = rs.rows.size == 1 && rs.rows[0].get (0).to_string () == "ok";
            } catch (Error e) {
                healthy = false;
            }
            if (healthy) {
                compact ();
                notes += _("No problems were found. The database was compacted.");
                return notes;
            }
            if (path == ":memory:") throw new SchemaError.INVALID (_("Only databases saved in a file can be repaired."));
            if (read_only) throw new SchemaError.INVALID (_("The database is read-only, so it cannot be repaired."));
            string tmp = Crypt.temp_path (path, "repair");
            bool watching = watcher != null && watcher.running;
            clear_history ();
            stop_change_watch ();
            db = null;
            string[] found;
            try {
                Repair.run (path, tmp, out found, is_encrypted ? password : null);
            } catch (Error e) {
                if (FileUtils.test (tmp, FileTest.EXISTS)) FileUtils.remove (tmp);
                reopen ();
                throw e;
            }
            string base_name = Path.get_basename (path);
            int dot = base_name.last_index_of (".");
            string stamp = new DateTime.now_local ().format ("%Y%m%d-%H%M%S");
            string damaged = dot > 0 ? "%s.damaged-%s%s".printf (base_name.substring (0, dot), stamp, base_name.substring (dot)) : "%s.damaged-%s".printf (base_name, stamp);
            string backup = Path.build_filename (Path.get_dirname (path), damaged);
            if (FileUtils.rename (path, backup) != 0) {
                FileUtils.remove (tmp);
                reopen ();
                throw new SchemaError.SQL (_("The damaged database could not be moved aside."));
            }
            if (FileUtils.test (path + "-journal", FileTest.EXISTS)) FileUtils.rename (path + "-journal", backup + "-journal");
            if (FileUtils.rename (tmp, path) != 0) {
                FileUtils.rename (backup, path);
                reopen ();
                throw new SchemaError.SQL (_("The repaired database could not be put in place."));
            }
            reopen ();
            foreach (string n in found) notes += n;
            notes += _("The damaged original was kept as \"%s\".").printf (damaged);
            if (watching) start_change_watch (watcher.interval_seconds);
            return notes;
        }

        public RecordLocks record_locks {
            get {
                if (locks == null) locks = new RecordLocks (this);
                return locks;
            }
        }

        private void on_watch_changed () {
            external_change ();
        }

        private void ensure_watcher () {
            if (watcher != null) return;
            watcher = new ChangeWatcher (this);
            watcher.changed.connect (on_watch_changed);
        }

        public void start_change_watch (uint seconds = 5) {
            ensure_watcher ();
            watcher.interval_seconds = seconds;
            watcher.start ();
        }

        public void stop_change_watch () {
            if (watcher != null) watcher.stop ();
        }

        public bool poll_external_change () {
            ensure_watcher ();
            return watcher.poll ();
        }
    }
}
