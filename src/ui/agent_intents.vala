namespace Singularity.Apps.Database {

    [CCode (cname = "sqlite3_stmt_readonly")]
    private extern int statement_readonly (Sqlite.Statement stmt);

    internal class DatabaseIntents : Object {
        private const int MAX_ROWS = 1000;

        private static string text (Json.Object args, string key) {
            return args.has_member (key) ? args.get_string_member (key) : "";
        }

        private static Json.Node obj (Json.Object o) {
            var node = new Json.Node (Json.NodeType.OBJECT);
            node.set_object (o);
            return node;
        }

        private static DatabaseWindow? find_window (DatabaseApp app) {
            var active = app.get_active_window () as DatabaseWindow;
            if (active != null && active.db != null) return active;
            foreach (var w in app.get_windows ()) {
                var dw = w as DatabaseWindow;
                if (dw != null && dw.db != null) return dw;
            }
            return null;
        }

        private static DatabaseWindow window (DatabaseApp app) throws Error {
            var w = find_window (app);
            if (w == null) throw new IOError.NOT_FOUND ("no database is open; call db_open first");
            return w;
        }

        private static DbValue to_value (Json.Node node) {
            if (node.is_null ()) return new DbValue.null ();
            if (node.get_node_type () != Json.NodeType.VALUE) return new DbValue.text (Json.to_string (node, false));
            var t = node.get_value_type ();
            if (t == typeof (int64)) return new DbValue.int (node.get_int ());
            if (t == typeof (double)) return new DbValue.real (node.get_double ());
            if (t == typeof (bool)) return new DbValue.int (node.get_boolean () ? 1 : 0);
            return new DbValue.text (node.get_string ());
        }

        private static Json.Node from_value (DbValue v) {
            var node = new Json.Node (Json.NodeType.VALUE);
            switch (v.kind) {
                case ValueKind.NULL:
                    node.init_null ();
                    break;
                case ValueKind.INTEGER:
                    node.set_int (v.int_value);
                    break;
                case ValueKind.REAL:
                    node.set_double (v.real_value);
                    break;
                case ValueKind.BLOB:
                    node.set_string ("<%d bytes>".printf (v.blob_value != null ? (int) v.blob_value.get_size () : 0));
                    break;
                default:
                    node.set_string (v.to_string ().make_valid ());
                    break;
            }
            return node;
        }

        private static Json.Node rows (ResultSet rs, int limit) {
            var list = new Json.Array ();
            foreach (var row in rs.rows) {
                if (list.get_length () == limit) break;
                var o = new Json.Object ();
                for (int i = 0; i < rs.columns.length; i++) o.set_member (rs.columns[i], from_value (row.get (i)));
                list.add_object_element (o);
            }
            var node = new Json.Node (Json.NodeType.ARRAY);
            node.set_array (list);
            return node;
        }

        private static Json.Node schema (Database db) throws Error {
            var tables = new Json.Array ();
            foreach (string name in db.table_names ()) {
                var def = db.load_table (name);
                var t = new Json.Object ();
                t.set_string_member ("name", name);
                if (def.description != "") t.set_string_member ("description", def.description);
                t.set_int_member ("rows", db.query_int ("SELECT COUNT(*) FROM %s".printf (Sql.quote_ident (name))));
                var fields = new Json.Array ();
                foreach (var f in def.fields) {
                    var fo = new Json.Object ();
                    fo.set_string_member ("name", f.name);
                    fo.set_string_member ("type", f.field_type.id ());
                    if (f.primary_key) fo.set_boolean_member ("primary_key", true);
                    if (f.required) fo.set_boolean_member ("required", true);
                    if (f.unique) fo.set_boolean_member ("unique", true);
                    if (f.choices.length > 0) {
                        var ch = new Json.Array ();
                        foreach (string c in f.choices) ch.add_string_element (c);
                        fo.set_array_member ("choices", ch);
                    }
                    if (f.lookup_table != "") fo.set_string_member ("lookup", f.lookup_table + "." + f.lookup_field);
                    fields.add_object_element (fo);
                }
                t.set_array_member ("fields", fields);
                tables.add_object_element (t);
            }
            var queries = new Json.Array ();
            foreach (string q in db.view_names ()) {
                var def = db.load_query (q);
                var qo = new Json.Object ();
                qo.set_string_member ("name", q);
                if (def != null) qo.set_string_member ("sql", def.sql);
                queries.add_object_element (qo);
            }
            var rels = new Json.Array ();
            foreach (var r in db.all_relationships ()) rels.add_string_element ("%s(%s) references %s(%s)".printf (r.table, string.joinv (", ", r.columns), r.ref_table, string.joinv (", ", r.ref_columns)));
            var o = new Json.Object ();
            o.set_string_member ("file", db.path);
            o.set_array_member ("tables", tables);
            o.set_array_member ("queries", queries);
            o.set_array_member ("relationships", rels);
            return obj (o);
        }

        private static string where_clause (Json.Object where, out DbValue[] values) throws Error {
            string[] parts = {};
            DbValue[] vals = {};
            foreach (string col in where.get_members ()) {
                var node = where.get_member (col);
                if (node.is_null ()) {
                    parts += "%s IS NULL".printf (Sql.quote_ident (col));
                } else {
                    parts += "%s = ?".printf (Sql.quote_ident (col));
                    vals += to_value (node);
                }
            }
            if (parts.length == 0) throw new IOError.INVALID_ARGUMENT ("where needs at least one column");
            values = vals;
            return string.joinv (" AND ", parts);
        }

        private static int64[] matching (Database db, string table, Json.Object args) throws Error {
            if (args.has_member ("rowid")) return { args.get_int_member ("rowid") };
            if (!args.has_member ("where")) throw new IOError.INVALID_ARGUMENT ("give a rowid or a where object");
            DbValue[] vals;
            string clause = where_clause (args.get_object_member ("where"), out vals);
            var rs = db.query ("SELECT rowid FROM %s WHERE %s".printf (Sql.quote_ident (table), clause), vals, MAX_ROWS + 1);
            if (rs.rows.size > MAX_ROWS) throw new IOError.FAILED ("more than %d rows match; narrow the where", MAX_ROWS);
            int64[] ids = {};
            foreach (var row in rs.rows) ids += row.get (0).as_int ();
            return ids;
        }

        private static string table_arg (Database db, Json.Object args) throws Error {
            string table = text (args, "table");
            foreach (string t in db.table_names ()) if (t.casefold () == table.casefold ()) return t;
            throw new IOError.NOT_FOUND ("no table %s", table);
        }

        private static void show (DatabaseWindow w, string table) {
            w.open_object ("table", table);
        }

        internal static void install (DatabaseApp app) {
            var agent = app.agent;

            agent.add_intent ("db_open", "Open a database file, or create one, empty or from a template (contacts, inventory and the others listed when the template is unknown).",
                "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"template\":{\"type\":\"string\"},\"name\":{\"type\":\"string\"}}}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    string path = text (args, "path");
                    string template = text (args, "template");
                    Database d;
                    if (path != "" && FileUtils.test (path, FileTest.EXISTS)) {
                        d = Database.open (path);
                    } else {
                        if (template != "") {
                            string[] ids = {};
                            foreach (var t in Templates.list ()) ids += t.id;
                            if (!(template in ids)) throw new IOError.NOT_FOUND ("no template %s, use one of %s", template, string.joinv (", ", ids));
                        }
                        string target = path != "" ? path : app.unique_path (text (args, "name") != "" ? text (args, "name") : (template != "" ? template : _("Database")));
                        d = Database.create (target);
                        if (template != "") Templates.build (d, template);
                    }
                    var w = find_window (app);
                    if (w == null) {
                        app.activate ();
                        w = app.get_active_window () as DatabaseWindow;
                        if (w == null) {
                            w = new DatabaseWindow (app);
                            w.present ();
                        }
                    }
                    w.load (d);
                    return schema (d);
                });

            agent.add_intent ("db_schema", "Describe the open database: tables with fields, types and row counts, views, saved queries and relationships.",
                "{\"type\":\"object\",\"properties\":{}}",
                Singularity.AppIntentRisk.READ, (args) => schema (window (app).db));

            agent.add_intent ("db_query", "Run a read-only SQL query (SELECT or WITH) or a saved query by name, with ? parameters, and return the rows.",
                "{\"type\":\"object\",\"properties\":{\"sql\":{\"type\":\"string\"},\"query\":{\"type\":\"string\"},\"params\":{\"type\":\"array\"},\"limit\":{\"type\":\"integer\"}}}",
                Singularity.AppIntentRisk.READ, (args) => {
                    var db = window (app).db;
                    string sql = text (args, "sql");
                    if (sql == "" && text (args, "query") != "") {
                        var q = db.load_query (text (args, "query"));
                        if (q == null) throw new IOError.NOT_FOUND ("no saved query %s", text (args, "query"));
                        sql = q.sql;
                    }
                    if (sql.strip () == "") throw new IOError.INVALID_ARGUMENT ("give sql or a saved query name");
                    var stmt = db.prepare (sql);
                    if (statement_readonly (stmt) == 0) throw new IOError.PERMISSION_DENIED ("db_query only reads; use db_insert, db_update or db_delete to change data");
                    DbValue[] vals = {};
                    if (args.has_member ("params")) foreach (var p in args.get_array_member ("params").get_elements ()) vals += to_value (p);
                    int limit = args.has_member ("limit") ? (int) args.get_int_member ("limit").clamp (1, MAX_ROWS) : 200;
                    var rs = db.query (sql, vals, limit + 1);
                    var o = new Json.Object ();
                    var cols = new Json.Array ();
                    foreach (string c in rs.columns) cols.add_string_element (c);
                    o.set_array_member ("columns", cols);
                    o.set_member ("rows", rows (rs, limit));
                    o.set_boolean_member ("truncated", rs.rows.size > limit);
                    return obj (o);
                });

            agent.add_intent ("db_insert", "Add records to a table: rows is a list of {column: value} objects. Undo removes them.",
                "{\"type\":\"object\",\"properties\":{\"table\":{\"type\":\"string\"},\"rows\":{\"type\":\"array\",\"items\":{\"type\":\"object\"}}},\"required\":[\"table\",\"rows\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var w = window (app);
                    var db = w.db;
                    string table = table_arg (db, args);
                    var ids = new Json.Array ();
                    foreach (var node in args.get_array_member ("rows").get_elements ()) {
                        if (node.get_node_type () != Json.NodeType.OBJECT) throw new IOError.INVALID_ARGUMENT ("each row is an object of column values");
                        var r = node.get_object ();
                        string[] cols = {};
                        DbValue[] vals = {};
                        foreach (string c in r.get_members ()) {
                            cols += c;
                            vals += to_value (r.get_member (c));
                        }
                        ids.add_int_element (db.insert_row (table, cols, vals));
                    }
                    show (w, table);
                    var o = new Json.Object ();
                    o.set_string_member ("table", table);
                    o.set_array_member ("rowids", ids);
                    o.set_int_member ("rows_now", db.query_int ("SELECT COUNT(*) FROM %s".printf (Sql.quote_ident (table))));
                    return obj (o);
                });

            agent.add_intent ("db_update", "Change records of a table, chosen by rowid or by a where object of column values, setting the columns in set. Each change can be undone.",
                "{\"type\":\"object\",\"properties\":{\"table\":{\"type\":\"string\"},\"rowid\":{\"type\":\"integer\"},\"where\":{\"type\":\"object\"},\"set\":{\"type\":\"object\"}},\"required\":[\"table\",\"set\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var w = window (app);
                    var db = w.db;
                    string table = table_arg (db, args);
                    var set = args.get_object_member ("set");
                    if (set.get_size () == 0) throw new IOError.INVALID_ARGUMENT ("set is empty");
                    var ids = matching (db, table, args);
                    foreach (int64 id in ids) {
                        foreach (string c in set.get_members ()) db.update_value (table, id, c, to_value (set.get_member (c)));
                    }
                    show (w, table);
                    var o = new Json.Object ();
                    o.set_string_member ("table", table);
                    o.set_int_member ("updated", ids.length);
                    if (ids.length > 0) {
                        string[] marks = {};
                        DbValue[] vals = {};
                        foreach (int64 id in ids) {
                            marks += "?";
                            vals += new DbValue.int (id);
                        }
                        o.set_member ("rows", rows (db.query ("SELECT rowid, * FROM %s WHERE rowid IN (%s)".printf (Sql.quote_ident (table), string.joinv (",", marks)), vals, 50), 50));
                    }
                    return obj (o);
                });

            agent.add_intent ("db_delete", "Delete records of a table chosen by rowid or by a where object.",
                "{\"type\":\"object\",\"properties\":{\"table\":{\"type\":\"string\"},\"rowid\":{\"type\":\"integer\"},\"where\":{\"type\":\"object\"}},\"required\":[\"table\"]}",
                Singularity.AppIntentRisk.IRREVERSIBLE, (args) => {
                    var w = window (app);
                    var db = w.db;
                    string table = table_arg (db, args);
                    var ids = matching (db, table, args);
                    int n = db.delete_rows (table, ids);
                    show (w, table);
                    var o = new Json.Object ();
                    o.set_string_member ("table", table);
                    o.set_int_member ("deleted", n);
                    return obj (o);
                });

            agent.add_intent ("db_create_table", "Create a table with fields {name, type, required, primary_key}; an AutoNumber ID is added when no primary key is given. Types: autonumber, text, long_text, integer, number, currency, percent, date, datetime, time, boolean, choice, email, url, phone.",
                "{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"},\"fields\":{\"type\":\"array\",\"items\":{\"type\":\"object\"}}},\"required\":[\"name\",\"fields\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var w = window (app);
                    var db = w.db;
                    string name = text (args, "name").strip ();
                    if (name == "") throw new IOError.INVALID_ARGUMENT ("the table needs a name");
                    if (db.object_exists (name)) throw new IOError.EXISTS ("%s already exists", name);
                    var def = new TableDef (name);
                    bool has_key = false;
                    foreach (var node in args.get_array_member ("fields").get_elements ()) {
                        var fo = node.get_object ();
                        string fname = fo.has_member ("name") ? fo.get_string_member ("name").strip () : "";
                        if (fname == "") throw new IOError.INVALID_ARGUMENT ("every field needs a name");
                        string tid = fo.has_member ("type") ? fo.get_string_member ("type") : "text";
                        var type = FieldType.from_id (tid);
                        if (type.id () != tid) throw new IOError.INVALID_ARGUMENT ("unknown field type %s", tid);
                        var f = new Field (fname, type);
                        f.required = fo.has_member ("required") && fo.get_boolean_member ("required");
                        f.primary_key = fo.has_member ("primary_key") && fo.get_boolean_member ("primary_key");
                        if (f.primary_key) has_key = true;
                        def.fields.add (f);
                    }
                    if (!has_key) {
                        var id = new Field ("ID", FieldType.AUTONUMBER);
                        id.primary_key = true;
                        def.fields.insert (0, id);
                    }
                    db.create_table (def);
                    show (w, name);
                    return schema (db);
                });
        }
    }
}
