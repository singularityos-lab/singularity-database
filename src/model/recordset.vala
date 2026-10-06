namespace Singularity.Apps.Database {

    public enum FilterOp {
        EQUALS,
        NOT_EQUALS,
        CONTAINS,
        NOT_CONTAINS,
        STARTS_WITH,
        ENDS_WITH,
        GREATER,
        GREATER_EQUAL,
        LESS,
        LESS_EQUAL,
        BETWEEN,
        IS_EMPTY,
        IS_NOT_EMPTY,
        IS_TRUE,
        IS_FALSE,
        ONE_OF;

        public const FilterOp[] ALL = { EQUALS, NOT_EQUALS, CONTAINS, NOT_CONTAINS, STARTS_WITH, ENDS_WITH, GREATER, GREATER_EQUAL, LESS, LESS_EQUAL, BETWEEN, IS_EMPTY, IS_NOT_EMPTY, IS_TRUE, IS_FALSE, ONE_OF };

        public string id () {
            switch (this) {
                case NOT_EQUALS: return "ne";
                case CONTAINS: return "contains";
                case NOT_CONTAINS: return "not-contains";
                case STARTS_WITH: return "starts";
                case ENDS_WITH: return "ends";
                case GREATER: return "gt";
                case GREATER_EQUAL: return "ge";
                case LESS: return "lt";
                case LESS_EQUAL: return "le";
                case BETWEEN: return "between";
                case IS_EMPTY: return "empty";
                case IS_NOT_EMPTY: return "not-empty";
                case IS_TRUE: return "true";
                case IS_FALSE: return "false";
                case ONE_OF: return "in";
                default: return "eq";
            }
        }

        public static FilterOp from_id (string s) {
            foreach (var o in ALL) {
                if (o.id () == s) return o;
            }
            return EQUALS;
        }

        public string label () {
            switch (this) {
                case NOT_EQUALS: return _("Is Not");
                case CONTAINS: return _("Contains");
                case NOT_CONTAINS: return _("Does Not Contain");
                case STARTS_WITH: return _("Starts With");
                case ENDS_WITH: return _("Ends With");
                case GREATER: return _("Greater Than");
                case GREATER_EQUAL: return _("At Least");
                case LESS: return _("Less Than");
                case LESS_EQUAL: return _("At Most");
                case BETWEEN: return _("Between");
                case IS_EMPTY: return _("Is Empty");
                case IS_NOT_EMPTY: return _("Is Not Empty");
                case IS_TRUE: return _("Is Yes");
                case IS_FALSE: return _("Is No");
                case ONE_OF: return _("Is Any Of");
                default: return _("Is");
            }
        }

        public int operands () {
            switch (this) {
                case IS_EMPTY:
                case IS_NOT_EMPTY:
                case IS_TRUE:
                case IS_FALSE: return 0;
                case BETWEEN: return 2;
                default: return 1;
            }
        }
    }

    public class SortSpec {
        public string column;
        public bool descending;

        public SortSpec (string column, bool descending) {
            this.column = column;
            this.descending = descending;
        }
    }

    public class FilterSpec {
        public string column;
        public FilterOp op;
        public string value = "";
        public string value2 = "";
        public string[] values = {};

        public FilterSpec (string column, FilterOp op, string value = "") {
            this.column = column;
            this.op = op;
            this.value = value;
        }
    }

    public class ViewState {
        public Gee.ArrayList<SortSpec> sorts = new Gee.ArrayList<SortSpec> ();
        public Gee.ArrayList<FilterSpec> filters = new Gee.ArrayList<FilterSpec> ();
        public bool match_any;
        public string search = "";
        public string group_by = "";
        public Gee.HashSet<string> hidden = new Gee.HashSet<string> ();
        public Gee.HashMap<string, int> widths = new Gee.HashMap<string, int> ();
        public Gee.HashMap<string, string> totals = new Gee.HashMap<string, string> ();
        public Gee.HashSet<string> collapsed = new Gee.HashSet<string> ();
        public string[] order = {};
        public string extra_where = "";
        public string extra_label = "";
        public Gee.ArrayList<CondRuleSet> formats = new Gee.ArrayList<CondRuleSet> ();

        public ViewState copy () {
            var s = new ViewState ();
            s.extra_where = extra_where;
            s.extra_label = extra_label;
            foreach (var f in formats) s.formats.add (f.copy ());
            foreach (var x in sorts) s.sorts.add (new SortSpec (x.column, x.descending));
            foreach (var f in filters) {
                var n = new FilterSpec (f.column, f.op, f.value);
                n.value2 = f.value2;
                n.values = f.values;
                s.filters.add (n);
            }
            s.match_any = match_any;
            s.search = search;
            s.group_by = group_by;
            s.hidden.add_all (hidden);
            foreach (var e in widths.entries) s.widths[e.key] = e.value;
            foreach (var e in totals.entries) s.totals[e.key] = e.value;
            s.collapsed.add_all (collapsed);
            s.order = order;
            return s;
        }

        public void build (Json.Builder b) {
            b.set_member_name ("sorts").begin_array ();
            foreach (var s in sorts) {
                b.begin_object ();
                b.set_member_name ("column").add_string_value (s.column);
                b.set_member_name ("desc").add_boolean_value (s.descending);
                b.end_object ();
            }
            b.end_array ();
            b.set_member_name ("filters").begin_array ();
            foreach (var f in filters) {
                b.begin_object ();
                b.set_member_name ("column").add_string_value (f.column);
                b.set_member_name ("op").add_string_value (f.op.id ());
                b.set_member_name ("value").add_string_value (f.value);
                b.set_member_name ("value2").add_string_value (f.value2);
                b.set_member_name ("values").begin_array ();
                foreach (string v in f.values) b.add_string_value (v);
                b.end_array ();
                b.end_object ();
            }
            b.end_array ();
            b.set_member_name ("any").add_boolean_value (match_any);
            b.set_member_name ("group").add_string_value (group_by);
            b.set_member_name ("hidden").begin_array ();
            foreach (string h in hidden) b.add_string_value (h);
            b.end_array ();
            b.set_member_name ("widths").begin_object ();
            foreach (var e in widths.entries) b.set_member_name (e.key).add_int_value (e.value);
            b.end_object ();
            b.set_member_name ("order").begin_array ();
            foreach (string o in order) b.add_string_value (o);
            b.end_array ();
            b.set_member_name ("totals").begin_object ();
            foreach (var e in totals.entries) b.set_member_name (e.key).add_string_value (e.value);
            b.end_object ();
            if (extra_where != "") {
                b.set_member_name ("extra-where").add_string_value (extra_where);
                b.set_member_name ("extra-label").add_string_value (extra_label);
            }
            if (formats.size > 0) {
                b.set_member_name ("formats").begin_array ();
                foreach (var f in formats) f.build (b);
                b.end_array ();
            }
        }

        public static ViewState read (Json.Object o) {
            var s = new ViewState ();
            if (o.has_member ("sorts")) {
                o.get_array_member ("sorts").foreach_element ((a, i, n) => {
                    var x = n.get_object ();
                    s.sorts.add (new SortSpec (x.get_string_member_with_default ("column", ""), x.get_boolean_member_with_default ("desc", false)));
                });
            }
            if (o.has_member ("filters")) {
                o.get_array_member ("filters").foreach_element ((a, i, n) => {
                    var x = n.get_object ();
                    var f = new FilterSpec (x.get_string_member_with_default ("column", ""), FilterOp.from_id (x.get_string_member_with_default ("op", "eq")), x.get_string_member_with_default ("value", ""));
                    f.value2 = x.get_string_member_with_default ("value2", "");
                    f.values = Meta.string_array (x, "values");
                    s.filters.add (f);
                });
            }
            s.match_any = o.get_boolean_member_with_default ("any", false);
            s.group_by = o.get_string_member_with_default ("group", "");
            foreach (string h in Meta.string_array (o, "hidden")) s.hidden.add (h);
            if (o.has_member ("widths")) {
                var w = o.get_object_member ("widths");
                foreach (string k in w.get_members ()) s.widths[k] = (int) w.get_int_member (k);
            }
            s.order = Meta.string_array (o, "order");
            if (o.has_member ("totals")) {
                var t = o.get_object_member ("totals");
                foreach (string k in t.get_members ()) s.totals[k] = t.get_string_member (k);
            }
            s.extra_where = o.get_string_member_with_default ("extra-where", "");
            s.extra_label = o.get_string_member_with_default ("extra-label", "");
            if (o.has_member ("formats")) {
                o.get_array_member ("formats").foreach_element ((a, i, n) => s.formats.add (CondRuleSet.read (n.get_object ())));
            }
            return s;
        }
    }

    public class GroupInfo {
        public DbValue key;
        public string label;
        public int64 count;
        public int64 start;

        public GroupInfo (DbValue key, string label, int64 count) {
            this.key = key;
            this.label = label;
            this.count = count;
        }
    }

    public class RecordSource : Object {
        public const int PAGE = 200;

        public Database db { get; private set; }
        public string source { get; private set; }
        public bool is_table { get; private set; }
        public bool editable { get; private set; }
        public TableDef def { get; private set; }
        public ViewState state;

        private string custom_sql;
        private UpdatePlan? plan;
        private int[] col_key = {};
        private string[] col_origin = {};
        public Gee.ArrayList<QueryParam> parameters = new Gee.ArrayList<QueryParam> ();
        private int64 cached_count = -1;
        private Gee.HashMap<int, Gee.ArrayList<Row>> pages = new Gee.HashMap<int, Gee.ArrayList<Row>> ();
        private Gee.ArrayList<int> page_order = new Gee.ArrayList<int> ();
        private Gee.ArrayList<GroupInfo>? groups_cache;
        private Gee.HashMap<string, string> lookup_cache = new Gee.HashMap<string, string> ();

        public signal void reset ();

        public RecordSource (Database db, string source, ViewState? state = null) throws Error {
            this.db = db;
            this.source = source;
            this.state = state ?? new ViewState ();
            reload_schema ();
        }

        public RecordSource.for_sql (Database db, string sql) throws Error {
            this.db = db;
            this.source = "";
            this.custom_sql = sql;
            this.state = new ViewState ();
            reload_schema ();
        }

        public void reload_schema () throws Error {
            if (custom_sql == null && db.object_exists (source, "table")) {
                def = db.load_table (source);
                is_table = true;
                editable = !def.without_rowid && !db.read_only;
            } else {
                is_table = false;
                editable = false;
                plan = null;
                def = new TableDef (source != "" ? source : _("Results"));
                var stmt = db.prepare ("SELECT * FROM (%s) LIMIT 0".printf (base_sql ()));
                for (int i = 0; i < stmt.column_count (); i++) {
                    string decl = Database.column_decltype (stmt, i) ?? "";
                    var f = new Field (stmt.column_name (i), decl == "" ? FieldType.TEXT : FieldType.from_declared (decl));
                    if (f.field_type == FieldType.AUTONUMBER) f.field_type = FieldType.INTEGER;
                    string? origin_table = stmt.column_table_name (i);
                    string? origin = stmt.column_origin_name (i);
                    if (origin_table != null && origin != null) {
                        try {
                            var odef = db.load_table (origin_table);
                            var of = odef.find (origin);
                            if (of != null) {
                                var copy = of.copy ();
                                copy.name = stmt.column_name (i);
                                copy.primary_key = false;
                                if (copy.field_type == FieldType.AUTONUMBER) copy.field_type = FieldType.INTEGER;
                                f = copy;
                            }
                        } catch (Error e) {
                        }
                    }
                    if (decl == "" && (origin_table == null || origin == null)) f.field_type = sample_type (i, f.field_type);
                    def.fields.add (f);
                }
                setup_plan ();
            }
            invalidate ();
        }

        private string plain_sql () {
            if (custom_sql != null) return base_sql ();
            var q = db.load_query (source);
            return q != null ? q.sql.strip () : base_sql ();
        }

        private void setup_plan () {
            if (db.read_only) return;
            var p = Updatable.plan (db, plain_sql ());
            if (p == null) return;
            try {
                var stmt = db.prepare (p.sql);
                int n = stmt.column_count () - p.tables.length;
                if (n != def.fields.size) return;
                int[] keys = new int[n];
                string[] origins = new string[n];
                bool any = false;
                for (int i = 0; i < n; i++) {
                    int c = i + p.tables.length;
                    string? t = stmt.column_table_name (c);
                    string? o = stmt.column_origin_name (c);
                    keys[i] = -1;
                    origins[i] = "";
                    if (t == null || o == null) continue;
                    int match = -1, count = 0;
                    for (int k = 0; k < p.tables.length; k++) {
                        if (p.tables[k].casefold () == t.casefold ()) {
                            if (match < 0) match = k;
                            count++;
                        }
                    }
                    if (count != 1) continue;
                    keys[i] = match;
                    origins[i] = o;
                    any = true;
                    try {
                        var of = db.load_table (t).find (o);
                        if (of != null && of.field_type == FieldType.AUTONUMBER) keys[i] = -1;
                    } catch (Error e) {
                    }
                }
                if (!any) return;
                plan = p;
                col_key = keys;
                col_origin = origins;
                editable = true;
            } catch (Error e) {
            }
        }

        public bool lock_target (int64 index, out string table, out int64 id) {
            table = "";
            id = -1;
            var r = row (index);
            if (r == null) return false;
            if (is_table) {
                table = source;
                id = r.rowid;
                return true;
            }
            if (plan != null && r.keys != null) {
                table = plan.tables[0];
                id = r.keys[0];
                return true;
            }
            return false;
        }

        public bool query_updatable {
            get { return plan != null; }
        }

        public bool field_updatable (string column) {
            if (is_table) {
                var tf = def.find (column);
                return editable && tf != null && !tf.is_calculated ();
            }
            if (plan == null) return false;
            int i = def.index_of (column);
            return i >= 0 && i < col_key.length && col_key[i] >= 0;
        }

        public void set_query_value (int64 index, string column, DbValue value) throws Error {
            if (plan == null) throw new SchemaError.INVALID (_("This data cannot be edited."));
            int i = def.index_of (column);
            if (i < 0 || i >= col_key.length || col_key[i] < 0) throw new SchemaError.INVALID (_("\"%s\" is calculated or comes from a summary and cannot be edited.").printf (column));
            var r = row (index);
            if (r == null || r.keys == null) throw new SchemaError.NOT_FOUND (_("The record no longer exists."));
            int64 rid = r.keys[col_key[i]];
            db.update_value (plan.tables[col_key[i]], rid, col_origin[i], value);
            invalidate ();
        }

        private FieldType sample_type (int col, FieldType fallback) {
            try {
                var rs = db.query ("SELECT * FROM (%s) LIMIT 50".printf (base_sql ()));
                int ints = 0, reals = 0, other = 0;
                foreach (var r in rs.rows) {
                    var v = r.get (col);
                    if (v.is_null) continue;
                    if (v.kind == ValueKind.INTEGER) ints++;
                    else if (v.kind == ValueKind.REAL) reals++;
                    else other++;
                }
                if (other == 0 && reals > 0) return FieldType.NUMBER;
                if (other == 0 && ints > 0) return FieldType.INTEGER;
            } catch (Error e) {
            }
            return fallback;
        }

        public void invalidate () {
            cached_count = -1;
            pages.clear ();
            page_order.clear ();
            groups_cache = null;
            lookup_cache.clear ();
            reset ();
        }

        private string base_sql () {
            if (custom_sql != null) {
                string s = custom_sql.strip ();
                while (s.has_suffix (";")) s = s.substring (0, s.length - 1).strip ();
                return s;
            }
            return "SELECT * FROM %s".printf (Sql.quote_ident (source));
        }

        public int field_count () {
            return def.fields.size;
        }

        private string col (string name) {
            return Sql.quote_ident (name);
        }

        private string filter_sql (FilterSpec f) {
            var field = def.find (f.column);
            if (field == null) return "";
            string c = col (field.name);
            string v = f.value;
            DbValue lit = coerce (field, v);
            switch (f.op) {
                case FilterOp.EQUALS:
                    if (field.field_type.is_text ()) return "%s = %s COLLATE NOCASE".printf (c, lit.sql_literal ());
                    return "%s = %s".printf (c, lit.sql_literal ());
                case FilterOp.NOT_EQUALS:
                    if (field.field_type.is_text ()) return "(%s IS NULL OR %s <> %s COLLATE NOCASE)".printf (c, c, lit.sql_literal ());
                    return "(%s IS NULL OR %s <> %s)".printf (c, c, lit.sql_literal ());
                case FilterOp.CONTAINS: return "instr(casefold(CAST(%s AS TEXT)), %s) > 0".printf (c, Sql.quote_string (v.casefold ()));
                case FilterOp.NOT_CONTAINS: return "(%s IS NULL OR instr(casefold(CAST(%s AS TEXT)), %s) = 0)".printf (c, c, Sql.quote_string (v.casefold ()));
                case FilterOp.STARTS_WITH: return "substr(casefold(CAST(%s AS TEXT)), 1, %d) = %s".printf (c, v.casefold ().char_count (), Sql.quote_string (v.casefold ()));
                case FilterOp.ENDS_WITH: return "substr(casefold(CAST(%s AS TEXT)), -%d) = %s".printf (c, int.max (1, v.casefold ().char_count ()), Sql.quote_string (v.casefold ()));
                case FilterOp.GREATER: return "%s > %s".printf (c, lit.sql_literal ());
                case FilterOp.GREATER_EQUAL: return "%s >= %s".printf (c, lit.sql_literal ());
                case FilterOp.LESS: return "%s < %s".printf (c, lit.sql_literal ());
                case FilterOp.LESS_EQUAL: return "%s <= %s".printf (c, lit.sql_literal ());
                case FilterOp.BETWEEN: return "%s BETWEEN %s AND %s".printf (c, lit.sql_literal (), coerce (field, f.value2).sql_literal ());
                case FilterOp.IS_EMPTY: return "(%s IS NULL OR %s = '')".printf (c, c);
                case FilterOp.IS_NOT_EMPTY: return "(%s IS NOT NULL AND %s <> '')".printf (c, c);
                case FilterOp.IS_TRUE: return "%s = 1".printf (c);
                case FilterOp.IS_FALSE: return "(%s IS NULL OR %s = 0)".printf (c, c);
                case FilterOp.ONE_OF:
                    string[] items = {};
                    bool with_null = false;
                    foreach (string x in f.values) {
                        if (x == "") with_null = true;
                        else items += coerce (field, x).sql_literal ();
                    }
                    string cond = items.length > 0 ? "%s IN (%s)".printf (c, string.joinv (", ", items)) : "0";
                    if (with_null) cond = "(%s OR %s IS NULL OR %s = '')".printf (cond, c, c);
                    return cond;
            }
            return "";
        }

        public static DbValue coerce (Field f, string text) {
            try {
                var v = Codec.parse (f, text);
                if (!v.is_null) return v;
            } catch (Error e) {
            }
            double d = 0;
            if (f.field_type.is_numeric () && Codec.parse_number (text, out d)) return new DbValue.real (d);
            return new DbValue.text (text);
        }

        public string where_sql () {
            string[] conds = {};
            foreach (var f in state.filters) {
                if (f.op.operands () > 0 && f.value.strip () == "" && f.values.length == 0) continue;
                string s = filter_sql (f);
                if (s != "") conds += s;
            }
            string filter = "";
            if (conds.length > 0) filter = string.joinv (state.match_any ? " OR " : " AND ", conds);
            if (state.extra_where.strip () != "") {
                string ew = "(" + AccessSql.expression (state.extra_where) + ")";
                filter = filter != "" ? "(%s) AND %s".printf (filter, ew) : ew;
            }
            string search = "";
            if (state.search.strip () != "") {
                string needle = Sql.quote_string (state.search.strip ().casefold ());
                string[] any = {};
                foreach (var f in def.fields) {
                    if (f.field_type == FieldType.ATTACHMENT) continue;
                    any += "instr(casefold(CAST(%s AS TEXT)), %s) > 0".printf (col (f.name), needle);
                    if (f.field_type == FieldType.LOOKUP && f.lookup_display != "" && is_table) {
                        any += "EXISTS (SELECT 1 FROM %s AS _l WHERE _l.%s = %s.%s AND instr(casefold(CAST(_l.%s AS TEXT)), %s) > 0)".printf (
                            col (f.lookup_table), col (f.lookup_field), col (source), col (f.name), col (f.lookup_display), needle);
                    }
                }
                if (any.length > 0) search = "(" + string.joinv (" OR ", any) + ")";
            }
            if (filter != "" && search != "") return "(%s) AND %s".printf (filter, search);
            if (filter != "") return filter;
            return search;
        }

        public string order_sql () {
            string[] parts = {};
            if (state.group_by != "" && def.find (state.group_by) != null) parts += group_expr () + " ASC";
            foreach (var s in state.sorts) {
                var f = def.find (s.column);
                if (f == null) continue;
                string e = col (f.name);
                if (f.field_type.is_text ()) e += " COLLATE NOCASE";
                parts += e + (s.descending ? " DESC" : " ASC");
            }
            if (is_table) parts += "rowid";
            return parts.length > 0 ? " ORDER BY " + string.joinv (", ", parts) : "";
        }

        private string group_expr () {
            var f = def.find (state.group_by);
            string e = col (f.name);
            return f.field_type.is_text () ? e + " COLLATE NOCASE" : e;
        }

        public string select_sql () {
            string where_c = where_sql ();
            if (plan != null) {
                string[] pc = {};
                for (int k = 0; k < plan.tables.length; k++) pc += col ("_sdb_rid_%d".printf (k));
                foreach (var f in def.fields) pc += col (f.name);
                return "SELECT %s FROM (%s)%s%s".printf (string.joinv (", ", pc), plan.sql, where_c != "" ? " WHERE " + where_c : "", order_sql ());
            }
            string rid = is_table && !def.without_rowid ? "rowid AS _sdb_rid, " : "";
            string from = is_table ? col (source) : "(%s)".printf (base_sql ());
            string[] cols = {};
            foreach (var f in def.fields) cols += col (f.name);
            return "SELECT %s%s FROM %s%s%s".printf (rid, string.joinv (", ", cols), from, where_c != "" ? " WHERE " + where_c : "", order_sql ());
        }

        public int64 count () {
            if (cached_count >= 0) return cached_count;
            try {
                string where_c = where_sql ();
                string from = is_table ? col (source) : "(%s)".printf (base_sql ());
                cached_count = db.query_int ("SELECT count(*) FROM %s%s".printf (from, where_c != "" ? " WHERE " + where_c : ""));
            } catch (Error e) {
                cached_count = 0;
            }
            return cached_count;
        }

        public int64 total_count () {
            try {
                string from = is_table ? col (source) : "(%s)".printf (base_sql ());
                return db.query_int ("SELECT count(*) FROM %s".printf (from));
            } catch (Error e) {
                return 0;
            }
        }

        public Row? row (int64 index) {
            if (index < 0 || index >= count ()) return null;
            int page = (int) (index / PAGE);
            var list = pages[page];
            if (list == null) {
                list = fetch_page (page);
                pages[page] = list;
                page_order.add (page);
                if (page_order.size > 60) {
                    int old = page_order.remove_at (0);
                    pages.unset (old);
                }
            }
            int off = (int) (index % PAGE);
            return off < list.size ? list[off] : null;
        }

        private Gee.ArrayList<Row> fetch_page (int page) {
            var list = new Gee.ArrayList<Row> ();
            try {
                var rs = db.query (select_sql () + " LIMIT %d OFFSET %lld".printf (PAGE, (int64) page * PAGE));
                bool has_rid = is_table && !def.without_rowid;
                int64 n = (int64) page * PAGE;
                if (plan != null) {
                    int nk = plan.tables.length;
                    foreach (var r in rs.rows) {
                        DbValue[] vals = new DbValue[r.values.length - nk];
                        int64[] keys = new int64[nk];
                        for (int k = 0; k < nk; k++) keys[k] = r.values[k].as_int ();
                        for (int i = nk; i < r.values.length; i++) vals[i - nk] = r.values[i];
                        var row = new Row (n, (owned) vals);
                        row.keys = keys;
                        list.add (row);
                        n++;
                    }
                    return list;
                }
                foreach (var r in rs.rows) {
                    int k = has_rid ? 1 : 0;
                    DbValue[] vals = new DbValue[r.values.length - k];
                    for (int i = k; i < r.values.length; i++) vals[i - k] = r.values[i];
                    list.add (new Row (has_rid ? r.values[0].as_int () : n, (owned) vals));
                    n++;
                }
            } catch (Error e) {
                warning ("database: %s", e.message);
            }
            return list;
        }

        public int64 index_of_rowid (int64 rowid) {
            if (plan != null) return rowid;
            if (!is_table) return -1;
            foreach (var e in pages.entries) {
                for (int i = 0; i < e.value.size; i++) {
                    if (e.value[i].rowid == rowid) return (int64) e.key * PAGE + i;
                }
            }
            try {
                string where_c = where_sql ();
                var rs = db.query ("SELECT n FROM (SELECT rowid AS r, row_number() OVER (%s) - 1 AS n FROM %s%s) WHERE r = ?".printf (
                    order_sql ().strip (), col (source), where_c != "" ? " WHERE " + where_c : ""), { new DbValue.int (rowid) });
                if (rs.rows.size > 0) return rs.rows[0].get (0).as_int ();
            } catch (Error e) {
            }
            return -1;
        }

        public Gee.ArrayList<GroupInfo> groups () {
            if (groups_cache != null) return groups_cache;
            groups_cache = new Gee.ArrayList<GroupInfo> ();
            var f = def.find (state.group_by);
            if (f == null) return groups_cache;
            try {
                string where_c = where_sql ();
                string from = is_table ? col (source) : "(%s)".printf (base_sql ());
                var rs = db.query ("SELECT %s, count(*) FROM %s%s GROUP BY %s ORDER BY %s".printf (group_expr (), from, where_c != "" ? " WHERE " + where_c : "", group_expr (), group_expr ()));
                int64 start = 0;
                foreach (var r in rs.rows) {
                    var key = r.get (0);
                    string label = key.is_null ? _("(Empty)") : display (f, key);
                    var g = new GroupInfo (key, label, r.get (1).as_int ());
                    g.start = start;
                    start += g.count;
                    groups_cache.add (g);
                }
            } catch (Error e) {
            }
            return groups_cache;
        }

        public string display (Field f, DbValue v) {
            if (f.multi_value && f.field_type == FieldType.LOOKUP && !v.is_null) {
                string[] shown = {};
                foreach (string item in MultiValue.items (v)) {
                    double d;
                    DbValue key = Codec.parse_number (item, out d) && d == Math.floor (d) ? new DbValue.int ((int64) d) : new DbValue.text (item);
                    shown += lookup_display (f, key);
                }
                return string.joinv ("; ", shown);
            }
            if (f.field_type == FieldType.LOOKUP && !v.is_null && !f.multi_value) return lookup_display (f, v);
            return Codec.display (f, v);
        }

        public string lookup_display (Field f, DbValue v) {
            if (f.lookup_table == "" || f.lookup_field == "") return v.to_string ();
            string display_col = f.lookup_display != "" ? f.lookup_display : f.lookup_field;
            string key = "%s|%s|%s".printf (f.lookup_table, display_col, v.to_string ());
            if (lookup_cache.has_key (key)) return lookup_cache[key];
            string result = v.to_string ();
            try {
                var rs = db.query ("SELECT %s FROM %s WHERE %s = ? LIMIT 1".printf (col (display_col), col (f.lookup_table), col (f.lookup_field)), { v });
                if (rs.rows.size > 0) result = rs.rows[0].get (0).to_string ();
            } catch (Error e) {
            }
            if (lookup_cache.size > 5000) lookup_cache.clear ();
            lookup_cache[key] = result;
            return result;
        }

        public Gee.ArrayList<Row> lookup_choices (Field f, int limit = 500) {
            var list = new Gee.ArrayList<Row> ();
            if (f.lookup_table == "" || f.lookup_field == "") return list;
            string display_col = f.lookup_display != "" ? f.lookup_display : f.lookup_field;
            try {
                var rs = db.query ("SELECT %s, %s FROM %s ORDER BY 2 COLLATE NOCASE LIMIT %d".printf (col (f.lookup_field), col (display_col), col (f.lookup_table), limit));
                foreach (var r in rs.rows) list.add (r);
            } catch (Error e) {
            }
            return list;
        }

        public Gee.ArrayList<DbValue> distinct_values (string column, int limit = 200) {
            var list = new Gee.ArrayList<DbValue> ();
            var f = def.find (column);
            if (f == null) return list;
            try {
                string from = is_table ? col (source) : "(%s)".printf (base_sql ());
                var rs = db.query ("SELECT DISTINCT %s FROM %s ORDER BY 1 LIMIT %d".printf (col (f.name), from, limit));
                foreach (var r in rs.rows) list.add (r.get (0));
            } catch (Error e) {
            }
            return list;
        }

        public DbValue aggregate (string column, Aggregate agg) {
            var f = def.find (column);
            if (f == null) return new DbValue.null ();
            try {
                string where_c = where_sql ();
                string from = is_table ? col (source) : "(%s)".printf (base_sql ());
                var rs = db.query ("SELECT %s FROM %s%s".printf (agg.wrap (col (f.name)), from, where_c != "" ? " WHERE " + where_c : ""));
                if (rs.rows.size > 0) return rs.rows[0].get (0);
            } catch (Error e) {
            }
            return new DbValue.null ();
        }

        public void set_value (int64 rowid, string column, DbValue value) throws Error {
            if (!editable) throw new SchemaError.INVALID (_("This data cannot be edited."));
            if (plan != null) {
                set_query_value (rowid, column, value);
                return;
            }
            db.update_value (source, rowid, column, value);
            invalidate ();
        }

        public int64 add_row (string[] columns, DbValue[] values) throws Error {
            if (!editable) throw new SchemaError.INVALID (_("This data cannot be edited."));
            if (plan != null) {
                string[] cols = {};
                DbValue[] vals = {};
                for (int i = 0; i < columns.length; i++) {
                    int c = def.index_of (columns[i]);
                    if (c < 0 || c >= col_key.length || col_key[c] != 0) continue;
                    cols += col_origin[c];
                    vals += values[i];
                }
                db.insert_row (plan.tables[0], cols, vals);
                invalidate ();
                return count () - 1;
            }
            int64 id = db.insert_row (source, columns, values);
            invalidate ();
            return id;
        }

        public void delete (int64[] rowids) throws Error {
            if (!editable) throw new SchemaError.INVALID (_("This data cannot be edited."));
            if (plan != null) {
                int64[] ids = {};
                foreach (int64 idx in rowids) {
                    var r = row (idx);
                    if (r != null && r.keys != null) ids += r.keys[0];
                }
                db.delete_rows (plan.tables[0], ids);
                invalidate ();
                return;
            }
            db.delete_rows (source, rowids);
            invalidate ();
        }

        public ResultSet all_rows () throws Error {
            return db.query (select_sql ());
        }
    }
}

namespace Singularity.Apps.Database {

    public class CondRuleSet {
        public string column = "";
        public Gee.ArrayList<CondRule> rules = new Gee.ArrayList<CondRule> ();
        public bool data_bar;
        public string bar_color = "#3584e4";

        public CondRuleSet copy () {
            var c = new CondRuleSet ();
            c.column = column;
            c.data_bar = data_bar;
            c.bar_color = bar_color;
            foreach (var r in rules) c.rules.add (r.copy ());
            return c;
        }

        public void build (Json.Builder b) {
            b.begin_object ();
            b.set_member_name ("column").add_string_value (column);
            b.set_member_name ("data-bar").add_boolean_value (data_bar);
            b.set_member_name ("bar-color").add_string_value (bar_color);
            CondRule.build_list (b, "rules", rules);
            b.end_object ();
        }

        public static CondRuleSet read (Json.Object o) {
            var c = new CondRuleSet ();
            c.column = o.get_string_member_with_default ("column", "");
            c.data_bar = o.get_boolean_member_with_default ("data-bar", false);
            c.bar_color = o.get_string_member_with_default ("bar-color", "#3584e4");
            c.rules = CondRule.read_list (o, "rules");
            return c;
        }
    }

    public class CondEval {
        public CondRule? first_match (Gee.List<CondRule> rules, string control, Field? f, DbValue v, ScriptRuntime rt, ScriptObject? scope) {
            foreach (var r in rules) {
                if (!r.enabled) continue;
                try {
                    if (r.kind == "value") {
                        if (match_value (r, f, v, rt)) return r;
                    } else if (r.expression.strip () != "" && ScriptRuntime.truth (rt.evaluate (r.expression, scope))) {
                        return r;
                    }
                } catch (Error e) {
                }
            }
            return null;
        }

        private bool match_value (CondRule r, Field? f, DbValue v, ScriptRuntime rt) throws Error {
            var val = f != null ? SValue.from_db (v, f.field_type) : SValue.from_db (v);
            if (r.op == "empty") return v.is_null || v.to_string () == "";
            if (r.op == "not-empty") return !(v.is_null || v.to_string () == "");
            if (v.is_null) return false;
            var a = r.value1.strip () != "" ? rt.evaluate (r.value1) : new SValue.empty ();
            switch (r.op) {
                case "between":
                case "not-between":
                    var b = rt.evaluate (r.value2);
                    bool inside = ScriptRuntime.compare (val, a) >= 0 && ScriptRuntime.compare (val, b) <= 0;
                    return r.op == "between" ? inside : !inside;
                case "equal": return ScriptRuntime.compare (val, a) == 0;
                case "not-equal": return ScriptRuntime.compare (val, a) != 0;
                case "greater": return ScriptRuntime.compare (val, a) > 0;
                case "less": return ScriptRuntime.compare (val, a) < 0;
                case "greater-equal": return ScriptRuntime.compare (val, a) >= 0;
                case "less-equal": return ScriptRuntime.compare (val, a) <= 0;
                case "contains": return val.to_text ().casefold ().contains (a.to_text ().casefold ());
            }
            return false;
        }
    }
}
