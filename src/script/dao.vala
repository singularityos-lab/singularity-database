namespace Singularity.Apps.Database {

    public class AccessRun {
        public static int execute (Database db, string access_sql) throws Error {
            string sql = AccessSql.statement (access_sql);
            string u = sql.strip ().up ();
            bool ddl = u.has_prefix ("CREATE") || u.has_prefix ("DROP") || u.has_prefix ("ALTER");
            int changed = db.run (sql);
            if (ddl) {
                db.invalidate ();
                db.schema_changed ();
            } else {
                db.data_changed ("");
            }
            return changed;
        }
    }

    public class DaoDatabase : ScriptObject {
        private weak ScriptRuntime rt;
        public int64 records_affected;

        public DaoDatabase (ScriptRuntime rt) {
            this.rt = rt;
        }

        public override string type_name () {
            return "Database";
        }

        public override SValue get_member (string name, SValue[] args) throws ScriptError {
            switch (name.down ()) {
                case "name": return new SValue.str (rt.db.path);
                case "recordsaffected": return new SValue.int (records_affected);
                case "openrecordset":
                case "execute":
                    return call_method (name, args, new string[args.length]);
            }
            return base.get_member (name, args);
        }

        public override SValue call_method (string name, SValue[] args, string[] names) throws ScriptError {
            switch (name.down ()) {
                case "execute":
                    if (args.length == 0) throw Script.fail (450, _("Execute needs a statement."));
                    try {
                        records_affected = AccessRun.execute (rt.db, args[0].to_text ());
                    } catch (Error e) {
                        throw Script.fail (3061, e.message);
                    }
                    return new SValue.empty ();
                case "openrecordset":
                    if (args.length == 0) throw Script.fail (450, _("OpenRecordset needs a source."));
                    return new SValue.object (new DaoRecordset (rt, args[0].to_text ()));
                case "close":
                    return new SValue.empty ();
            }
            return get_member (name, args);
        }
    }

    public class DaoField : ScriptObject {
        private weak DaoRecordset rs;
        public int index;

        public DaoField (DaoRecordset rs, int index) {
            this.rs = rs;
            this.index = index;
        }

        public override string type_name () {
            return "Field";
        }

        public override SValue get_default (SValue[] args) throws ScriptError {
            return rs.value_at (index);
        }

        public override void set_default (SValue[] args, SValue value) throws ScriptError {
            rs.set_value_at (index, value);
        }

        public override SValue get_member (string name, SValue[] args) throws ScriptError {
            switch (name.down ()) {
                case "value": return rs.value_at (index);
                case "name": return new SValue.str (rs.columns[index]);
            }
            return base.get_member (name, args);
        }

        public override void set_member (string name, SValue[] args, SValue value) throws ScriptError {
            if (name.down () == "value") {
                rs.set_value_at (index, value);
                return;
            }
            base.set_member (name, args, value);
        }
    }

    public class DaoFields : ScriptObject {
        private weak DaoRecordset rs;

        public DaoFields (DaoRecordset rs) {
            this.rs = rs;
        }

        public override string type_name () {
            return "Fields";
        }

        public override SValue get_default (SValue[] args) throws ScriptError {
            if (args.length == 0) throw Script.fail (450, _("Fields needs a name or a number."));
            return new SValue.object (new DaoField (rs, rs.column_index (args[0])));
        }

        public override SValue bang (string name) throws ScriptError {
            return get_default ({ new SValue.str (name) });
        }

        public override SValue get_member (string name, SValue[] args) throws ScriptError {
            if (name.down () == "count") return new SValue.int (rs.columns.length);
            if (name.down () == "item") return get_default (args);
            return base.get_member (name, args);
        }

        public override Gee.List<SValue>? items () {
            var list = new Gee.ArrayList<SValue> ();
            for (int i = 0; i < rs.columns.length; i++) list.add (new SValue.object (new DaoField (rs, i)));
            return list;
        }
    }

    public class DaoRecordset : ScriptObject {
        private weak ScriptRuntime rt;
        public string[] columns = {};
        public string table = "";
        private string sql;
        private Gee.ArrayList<Row> rows = new Gee.ArrayList<Row> ();
        private int pos;
        private string edit_mode = "";
        private Gee.HashMap<int, SValue> pending = new Gee.HashMap<int, SValue> ();
        private bool has_rowid;
        private bool no_match;
        private bool closed;

        public DaoRecordset (ScriptRuntime rt, string source) throws ScriptError {
            this.rt = rt;
            string s = source.strip ();
            if (s.down ().has_prefix ("select ") || s.down ().has_prefix ("transform ") || s.down ().has_prefix ("parameters ")) {
                sql = AccessSql.statement (s);
            } else {
                string t = s.has_prefix ("[") && s.has_suffix ("]") ? s.substring (1, s.length - 2) : s;
                if (rt.db.object_exists (t, "table")) {
                    table = t;
                    sql = "SELECT rowid AS _sdb_rid, * FROM %s".printf (Sql.quote_ident (t));
                    has_rowid = true;
                } else if (rt.db.object_exists (t, "view")) {
                    sql = "SELECT * FROM %s".printf (Sql.quote_ident (t));
                } else {
                    var saved = SavedQueries.load (rt.db, t);
                    if (saved == null) throw Script.fail (3078, _("The table or query \"%s\" does not exist.").printf (t));
                    sql = AccessSql.statement (saved.sql);
                }
            }
            if (!has_rowid) {
                var single = Updatable.single_table (rt.db, sql);
                if (single != null) {
                    table = single;
                    sql = Updatable.with_rowid (sql);
                    has_rowid = true;
                }
            }
            load ();
        }

        private void load () throws ScriptError {
            try {
                var rs = rt.db.query (sql);
                string[] cols = {};
                for (int i = has_rowid ? 1 : 0; i < rs.columns.length; i++) cols += rs.columns[i];
                columns = cols;
                rows = rs.rows;
            } catch (Error e) {
                throw Script.fail (3061, e.message);
            }
            pos = 0;
        }

        public override string type_name () {
            return "Recordset";
        }

        private void check_open () throws ScriptError {
            if (closed) throw Script.fail (3420, _("The recordset is closed."));
        }

        public int column_index (SValue key) throws ScriptError {
            if (key.kind == SKind.INT || key.kind == SKind.DOUBLE) {
                int k = (int) key.to_int ();
                if (k < 0 || k >= columns.length) throw Script.fail (3265, _("Item not found in this collection."));
                return k;
            }
            string n = key.to_text ();
            for (int i = 0; i < columns.length; i++) {
                if (columns[i].casefold () == n.casefold ()) return i;
            }
            throw Script.fail (3265, _("The field \"%s\" is not in the recordset.").printf (n));
        }

        public SValue value_at (int i) throws ScriptError {
            check_open ();
            if (pending.has_key (i)) return pending[i];
            if (edit_mode == "add") return new SValue.null ();
            if (pos < 0 || pos >= rows.size) throw Script.fail (3021, _("There is no current record."));
            return SValue.from_db (rows[pos].get (has_rowid ? i + 1 : i));
        }

        public void set_value_at (int i, SValue v) throws ScriptError {
            check_open ();
            if (edit_mode == "") throw Script.fail (3020, _("Update or CancelUpdate without AddNew or Edit."));
            pending[i] = v.resolved ();
        }

        public override SValue get_default (SValue[] args) throws ScriptError {
            if (args.length == 0) return new SValue.object (new DaoFields (this));
            return value_at (column_index (args[0]));
        }

        public override void set_default (SValue[] args, SValue value) throws ScriptError {
            if (args.length == 0) throw Script.fail (450, _("A field name is needed."));
            set_value_at (column_index (args[0]), value);
        }

        public override SValue bang (string name) throws ScriptError {
            return value_at (column_index (new SValue.str (name)));
        }

        public override void set_bang (string name, SValue value) throws ScriptError {
            set_value_at (column_index (new SValue.str (name)), value);
        }

        public override SValue get_member (string name, SValue[] args) throws ScriptError {
            switch (name.down ()) {
                case "eof": return new SValue.bool (pos >= rows.size || rows.size == 0);
                case "bof": return new SValue.bool (pos < 0 || rows.size == 0);
                case "recordcount": return new SValue.int (rows.size);
                case "nomatch": return new SValue.bool (no_match);
                case "absoluteposition": return new SValue.int (pos);
                case "fields":
                    if (args.length > 0) return new SValue.object (new DaoField (this, column_index (args[0])));
                    return new SValue.object (new DaoFields (this));
                case "name": return new SValue.str (table);
            }
            return call_method (name, args, new string[args.length]);
        }

        public override void set_member (string name, SValue[] args, SValue value) throws ScriptError {
            if (name.down () == "absoluteposition") {
                pos = (int) value.to_int ();
                return;
            }
            base.set_member (name, args, value);
        }

        public override SValue call_method (string name, SValue[] args, string[] names) throws ScriptError {
            check_open ();
            switch (name.down ()) {
                case "movenext": pos = int.min (rows.size, pos + 1); return new SValue.empty ();
                case "moveprevious": pos = int.max (-1, pos - 1); return new SValue.empty ();
                case "movefirst": pos = 0; return new SValue.empty ();
                case "movelast": pos = rows.size - 1; return new SValue.empty ();
                case "move": pos = (pos + (int) args[0].to_int ()).clamp (-1, rows.size); return new SValue.empty ();
                case "close": closed = true; return new SValue.empty ();
                case "requery": load (); return new SValue.empty ();
                case "addnew":
                    require_table ();
                    edit_mode = "add";
                    pending.clear ();
                    return new SValue.empty ();
                case "edit":
                    require_table ();
                    if (pos < 0 || pos >= rows.size) throw Script.fail (3021, _("There is no current record."));
                    edit_mode = "edit";
                    pending.clear ();
                    return new SValue.empty ();
                case "cancelupdate":
                    edit_mode = "";
                    pending.clear ();
                    return new SValue.empty ();
                case "update":
                    commit ();
                    return new SValue.empty ();
                case "delete":
                    require_table ();
                    if (pos < 0 || pos >= rows.size) throw Script.fail (3021, _("There is no current record."));
                    try {
                        rt.db.delete_rows (table, { rows[pos].get (0).as_int () });
                    } catch (Error e) {
                        throw Script.fail (3200, e.message);
                    }
                    rows.remove_at (pos);
                    return new SValue.empty ();
                case "findfirst":
                case "findnext":
                case "findlast":
                case "findprevious":
                    find (name.down (), args.length > 0 ? args[0].to_text () : "");
                    return new SValue.empty ();
                case "getrows":
                    int n = args.length > 0 && !(args[0] is MissingValue) ? (int) args[0].to_int () : rows.size;
                    var list = new Gee.ArrayList<SValue> ();
                    for (int k = 0; k < n && pos < rows.size; k++) {
                        var row = new Gee.ArrayList<SValue> ();
                        for (int c = 0; c < columns.length; c++) row.add (value_at (c));
                        list.add (new SValue.array (new SArray.from_list (row)));
                        pos++;
                    }
                    return new SValue.array (new SArray.from_list (list));
            }
            return base.call_method (name, args, names);
        }

        private void require_table () throws ScriptError {
            if (!has_rowid || table == "") throw Script.fail (3027, _("The recordset is not updatable."));
        }

        private void find (string how, string criteria) throws ScriptError {
            string cond = AccessSql.expression (criteria);
            var matches = new Gee.HashSet<int> ();
            try {
                string inner = "SELECT row_number() OVER () - 1 AS _sdb_n, * FROM (%s)".printf (sql);
                var rs = rt.db.query ("SELECT _sdb_n FROM (%s) WHERE %s".printf (inner, cond));
                var hits = new Gee.HashSet<int64?> ((v) => (uint) v, (a, b) => a == b);
                foreach (var r in rs.rows) hits.add (r.get (0).as_int ());
                if (has_rowid) {
                    var ids = rt.db.query ("SELECT _sdb_rid FROM (%s) WHERE %s".printf (inner, cond));
                    var idset = new Gee.HashSet<int64?> ((v) => (uint) v, (a, b) => a == b);
                    foreach (var r in ids.rows) idset.add (r.get (0).as_int ());
                    for (int k = 0; k < rows.size; k++) {
                        if (idset.contains (rows[k].get (0).as_int ())) matches.add (k);
                    }
                } else {
                    for (int k = 0; k < rows.size; k++) {
                        if (hits.contains (k)) matches.add (k);
                    }
                }
            } catch (Error e) {
                throw Script.fail (3077, e.message);
            }
            int start, end, step;
            switch (how) {
                case "findfirst": start = 0; end = rows.size; step = 1; break;
                case "findlast": start = rows.size - 1; end = -1; step = -1; break;
                case "findnext": start = pos + 1; end = rows.size; step = 1; break;
                default: start = pos - 1; end = -1; step = -1; break;
            }
            for (int k = start; k != end; k += step) {
                if (matches.contains (k)) {
                    pos = k;
                    no_match = false;
                    return;
                }
            }
            no_match = true;
        }

        private void commit () throws ScriptError {
            if (edit_mode == "") throw Script.fail (3020, _("Update or CancelUpdate without AddNew or Edit."));
            try {
                if (edit_mode == "add") {
                    string[] cols = {};
                    DbValue[] vals = {};
                    foreach (var e in pending.entries) {
                        cols += columns[e.key];
                        vals += e.value.to_db ();
                    }
                    int64 id = rt.db.insert_row (table, cols, vals);
                    var rs = rt.db.query ("SELECT rowid AS _sdb_rid, * FROM %s WHERE rowid = ?".printf (Sql.quote_ident (table)), { new DbValue.int (id) });
                    if (rs.rows.size > 0) rows.add (rs.rows[0]);
                } else {
                    int64 id = rows[pos].get (0).as_int ();
                    foreach (var e in pending.entries) rt.db.update_value (table, id, columns[e.key], e.value.to_db ());
                    var rs = rt.db.query ("SELECT rowid AS _sdb_rid, * FROM %s WHERE rowid = ?".printf (Sql.quote_ident (table)), { new DbValue.int (id) });
                    if (rs.rows.size > 0) rows[pos] = rs.rows[0];
                }
            } catch (Error e) {
                throw Script.fail (3022, e.message);
            } finally {
                edit_mode = "";
                pending.clear ();
            }
        }

        public override Gee.List<SValue>? items () {
            var list = new Gee.ArrayList<SValue> ();
            for (int i = 0; i < columns.length; i++) list.add (new SValue.object (new DaoField (this, i)));
            return list;
        }
    }
}
