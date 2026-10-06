namespace Singularity.Apps.Database {

    public enum JoinKind {
        INNER,
        LEFT,
        RIGHT,
        FULL;

        public string sql () {
            switch (this) {
                case LEFT: return "LEFT JOIN";
                case RIGHT: return "RIGHT JOIN";
                case FULL: return "FULL JOIN";
                default: return "INNER JOIN";
            }
        }

        public string label () {
            switch (this) {
                case LEFT: return _("All records from the left table");
                case RIGHT: return _("All records from the right table");
                case FULL: return _("All records from both tables");
                default: return _("Only matching records");
            }
        }

        public string id () {
            switch (this) {
                case LEFT: return "left";
                case RIGHT: return "right";
                case FULL: return "full";
                default: return "inner";
            }
        }

        public static JoinKind from_id (string s) {
            switch (s) {
                case "left": return LEFT;
                case "right": return RIGHT;
                case "full": return FULL;
                default: return INNER;
            }
        }
    }

    public enum SortOrder {
        NONE,
        ASCENDING,
        DESCENDING
    }

    public enum Aggregate {
        GROUP_BY,
        SUM,
        AVG,
        MIN,
        MAX,
        COUNT,
        COUNT_DISTINCT,
        STDEV,
        FIRST,
        LAST,
        EXPRESSION,
        WHERE,
        VAR;

        public const Aggregate[] ALL = { GROUP_BY, SUM, AVG, MIN, MAX, COUNT, COUNT_DISTINCT, STDEV, VAR, FIRST, LAST, EXPRESSION, WHERE };

        public string id () {
            switch (this) {
                case SUM: return "sum";
                case AVG: return "avg";
                case MIN: return "min";
                case MAX: return "max";
                case COUNT: return "count";
                case COUNT_DISTINCT: return "count-distinct";
                case STDEV: return "stdev";
                case VAR: return "var";
                case FIRST: return "first";
                case LAST: return "last";
                case EXPRESSION: return "expression";
                case WHERE: return "where";
                default: return "group";
            }
        }

        public static Aggregate from_id (string s) {
            foreach (var a in ALL) {
                if (a.id () == s) return a;
            }
            return GROUP_BY;
        }

        public string label () {
            switch (this) {
                case SUM: return _("Sum");
                case AVG: return _("Average");
                case MIN: return _("Minimum");
                case MAX: return _("Maximum");
                case COUNT: return _("Count");
                case COUNT_DISTINCT: return _("Count Distinct");
                case STDEV: return _("Standard Deviation");
                case VAR: return _("Variance");
                case FIRST: return _("First");
                case LAST: return _("Last");
                case EXPRESSION: return _("Expression");
                case WHERE: return _("Where");
                default: return _("Group By");
            }
        }

        public string alias_prefix () {
            switch (this) {
                case SUM: return "SumOf";
                case AVG: return "AvgOf";
                case MIN: return "MinOf";
                case MAX: return "MaxOf";
                case COUNT: return "CountOf";
                case COUNT_DISTINCT: return "CountDistinctOf";
                case STDEV: return "StDevOf";
                case VAR: return "VarOf";
                case FIRST: return "FirstOf";
                case LAST: return "LastOf";
                default: return "";
            }
        }

        public string wrap (string expr) {
            switch (this) {
                case SUM: return "SUM(%s)".printf (expr);
                case AVG: return "AVG(%s)".printf (expr);
                case MIN: return "MIN(%s)".printf (expr);
                case MAX: return "MAX(%s)".printf (expr);
                case COUNT: return expr == "*" ? "COUNT(*)" : "COUNT(%s)".printf (expr);
                case COUNT_DISTINCT: return "COUNT(DISTINCT %s)".printf (expr);
                case STDEV: return "stdev(%s)".printf (expr);
                case VAR: return "var(%s)".printf (expr);
                case FIRST: return "first(%s)".printf (expr);
                case LAST: return "last(%s)".printf (expr);
                default: return expr;
            }
        }

        public bool is_aggregate () {
            return this != GROUP_BY && this != EXPRESSION && this != WHERE;
        }
    }

    public enum QueryType {
        SELECT,
        MAKE_TABLE,
        APPEND,
        UPDATE,
        DELETE,
        CROSSTAB;

        public const QueryType[] ALL = { SELECT, CROSSTAB, MAKE_TABLE, APPEND, UPDATE, DELETE };

        public string id () {
            switch (this) {
                case CROSSTAB: return "crosstab";
                case MAKE_TABLE: return "make-table";
                case APPEND: return "append";
                case UPDATE: return "update";
                case DELETE: return "delete";
                default: return "select";
            }
        }

        public static QueryType from_id (string s) {
            switch (s) {
                case "make-table": return MAKE_TABLE;
                case "append": return APPEND;
                case "update": return UPDATE;
                case "delete": return DELETE;
                case "crosstab": return CROSSTAB;
                default: return SELECT;
            }
        }

        public string label () {
            switch (this) {
                case MAKE_TABLE: return _("Make Table");
                case APPEND: return _("Append");
                case UPDATE: return _("Update");
                case DELETE: return _("Delete");
                case CROSSTAB: return _("Crosstab");
                default: return _("Select");
            }
        }
    }

    public class QueryTable {
        public string name;
        public string alias;
        public double x;
        public double y;

        public QueryTable (string name, string alias) {
            this.name = name;
            this.alias = alias;
        }
    }

    public class QueryJoin {
        public string left;
        public string left_field;
        public string right;
        public string right_field;
        public JoinKind kind = JoinKind.INNER;

        public QueryJoin (string left, string left_field, string right, string right_field, JoinKind kind = JoinKind.INNER) {
            this.left = left;
            this.left_field = left_field;
            this.right = right;
            this.right_field = right_field;
            this.kind = kind;
        }
    }

    public class QueryColumn {
        public string table = "";
        public string field = "";
        public string expression = "";
        public string alias = "";
        public bool show = true;
        public SortOrder sort = SortOrder.NONE;
        public Aggregate total = Aggregate.GROUP_BY;
        public string[] criteria = {};
        public string update_to = "";
        public string append_to = "";
        public string crosstab = "";

        public QueryColumn (string table, string field) {
            this.table = table;
            this.field = field;
        }

        public QueryColumn.expr (string expression, string alias) {
            this.expression = expression;
            this.alias = alias;
        }

        public string criterion (int row) {
            return row < criteria.length ? criteria[row] : "";
        }

        public void set_criterion (int row, string text) {
            string[] c = criteria;
            while (c.length <= row) c += "";
            c[row] = text;
            criteria = c;
        }

        public string base_expr () {
            if (expression.strip () != "") return QueryDesign.bracket_refs (expression.strip ());
            if (field == "*") return table != "" ? Sql.quote_ident (table) + ".*" : "*";
            if (table == "") return Sql.quote_ident (field);
            return Sql.quote_ident (table) + "." + Sql.quote_ident (field);
        }

        public string display_name () {
            if (alias != "") return alias;
            if (expression != "") return expression;
            return field;
        }
    }

    public class QueryDesign {
        public QueryType query_type = QueryType.SELECT;
        public Gee.ArrayList<QueryTable> tables = new Gee.ArrayList<QueryTable> ();
        public Gee.ArrayList<QueryJoin> joins = new Gee.ArrayList<QueryJoin> ();
        public Gee.ArrayList<QueryColumn> columns = new Gee.ArrayList<QueryColumn> ();
        public bool distinct;
        public bool totals;
        public int limit;
        public string target = "";
        public Gee.ArrayList<QueryParam> params = new Gee.ArrayList<QueryParam> ();

        public string parameters_clause () {
            if (params.size == 0) return "";
            string[] parts = {};
            foreach (var p in params) parts += "%s %s".printf (Sql.quote_ident (p.name), p.type_name != "" ? p.type_name : "Text");
            return "PARAMETERS %s;\n".printf (string.joinv (", ", parts));
        }

        public string crosstab_sql () throws SchemaError {
            QueryColumn? pivot = null, value = null;
            string[] rows = {};
            string[] groups = {};
            foreach (var c in columns) {
                if (c.crosstab == "column") pivot = c;
                else if (c.crosstab == "value") value = c;
                else if (c.crosstab == "row") {
                    string e = c.base_expr ();
                    string a = c.alias != "" ? c.alias : "";
                    rows += a != "" ? "%s AS %s".printf (e, Sql.quote_ident (a)) : e;
                    groups += e;
                }
            }
            if (pivot == null) throw new SchemaError.INVALID (_("Choose one field as the Column Heading."));
            if (value == null) throw new SchemaError.INVALID (_("Choose one field as the Value."));
            if (rows.length == 0) throw new SchemaError.INVALID (_("Choose at least one field as a Row Heading."));
            var agg = value.total.is_aggregate () ? value.total : Aggregate.SUM;
            string vexpr = value.field == "*" ? "*" : value.base_expr ();
            string ve = agg == Aggregate.COUNT && vexpr == "*" ? "Count(*)" : agg.wrap (vexpr);
            var sb = new StringBuilder ("TRANSFORM %s\nSELECT %s\nFROM %s".printf (ve, string.joinv (", ", rows), from_clause ()));
            string w, h;
            criteria_clauses (out w, out h);
            if (pending_join_conditions.size > 0) {
                string extra = string.joinv (" AND ", pending_join_conditions.to_array ());
                w = w == "" ? extra : "(%s) AND (%s)".printf (extra, w);
            }
            if (w != "") sb.append ("\nWHERE ").append (w);
            sb.append ("\nGROUP BY ").append (string.joinv (", ", groups));
            sb.append ("\nPIVOT ").append (pivot.base_expr ());
            return sb.str;
        }

        public QueryTable add_table (string name) {
            string alias = name;
            int n = 1;
            while (find_table (alias) != null) alias = "%s_%d".printf (name, n++);
            var t = new QueryTable (name, alias);
            t.x = 24 + tables.size * 230;
            t.y = 24;
            tables.add (t);
            return t;
        }

        public QueryTable? find_table (string alias) {
            foreach (var t in tables) {
                if (t.alias.casefold () == alias.casefold ()) return t;
            }
            return null;
        }

        public void remove_table (string alias) {
            var t = find_table (alias);
            if (t == null) return;
            tables.remove (t);
            var keep = new Gee.ArrayList<QueryJoin> ();
            foreach (var j in joins) {
                if (j.left != t.alias && j.right != t.alias) keep.add (j);
            }
            joins = keep;
            var cols = new Gee.ArrayList<QueryColumn> ();
            foreach (var c in columns) {
                if (c.table != t.alias) cols.add (c);
            }
            columns = cols;
        }

        public QueryColumn add_column (string table, string field) {
            var c = new QueryColumn (table, field);
            columns.add (c);
            return c;
        }

        public int criteria_rows () {
            int n = 1;
            foreach (var c in columns) n = int.max (n, c.criteria.length);
            return n;
        }

        public void auto_join (Database db) {
            foreach (var a in tables) {
                TableDef def;
                try {
                    def = db.load_table (a.name);
                } catch (Error e) {
                    continue;
                }
                var rels = def.effective_relationships ();
                foreach (var soft in db.soft_relationships ()) {
                    if (soft.table.casefold () == a.name.casefold ()) rels.add (soft);
                }
                foreach (var r in rels) {
                    foreach (var b in tables) {
                        if (b == a || b.name.casefold () != r.ref_table.casefold ()) continue;
                        bool exists = false;
                        foreach (var j in joins) {
                            if ((j.left == a.alias && j.right == b.alias) || (j.left == b.alias && j.right == a.alias)) exists = true;
                        }
                        if (!exists) joins.add (new QueryJoin (b.alias, r.ref_columns[0], a.alias, r.columns[0]));
                    }
                }
            }
        }

        public static string bracket_refs (string expr) {
            var sb = new StringBuilder ();
            int i = 0;
            while (i < expr.length) {
                char c = expr[i];
                if (c == '\'') {
                    int j = i + 1;
                    while (j < expr.length) {
                        if (expr[j] == '\'') {
                            if (j + 1 < expr.length && expr[j + 1] == '\'') {
                                j += 2;
                                continue;
                            }
                            break;
                        }
                        j++;
                    }
                    sb.append (expr.substring (i, int.min (expr.length, j + 1) - i));
                    i = j + 1;
                    continue;
                }
                if (c == '[') {
                    int close = expr.index_of_char (']', i);
                    if (close > i) {
                        string name = expr.substring (i + 1, close - i - 1);
                        if (close + 2 < expr.length && expr[close + 1] == '.' && expr[close + 2] == '[') {
                            int close2 = expr.index_of_char (']', close + 3);
                            if (close2 > close) {
                                sb.append (Sql.quote_ident (name) + "." + Sql.quote_ident (expr.substring (close + 3, close2 - close - 3)));
                                i = close2 + 1;
                                continue;
                            }
                        }
                        sb.append (Sql.quote_ident (name));
                        i = close + 1;
                        continue;
                    }
                }
                sb.append_c (c);
                i++;
            }
            return sb.str;
        }

        private string column_expr (QueryColumn c) {
            string e = c.base_expr ();
            if (totals && c.total.is_aggregate ()) {
                if (c.field == "*" && c.total == Aggregate.COUNT) return "COUNT(*)";
                return c.total.wrap (e);
            }
            return e;
        }

        private string column_alias (QueryColumn c) {
            if (c.alias != "") return c.alias;
            if (totals && c.total.is_aggregate ()) return c.total.alias_prefix () + (c.field == "*" ? "Records" : (c.field != "" ? c.field : "Expr"));
            if (c.expression != "") return "Expr%d".printf (columns.index_of (c) + 1);
            return "";
        }

        public string from_clause () throws SchemaError {
            if (tables.size == 0) throw new SchemaError.INVALID (_("Add at least one table to the query."));
            var sb = new StringBuilder ();
            var added = new Gee.HashSet<string> ();
            var used = new Gee.HashSet<QueryJoin> ();
            var first = tables[0];
            sb.append (table_ref (first));
            added.add (first.alias);
            bool progress = true;
            while (added.size < tables.size && progress) {
                progress = false;
                foreach (var t in tables) {
                    if (added.contains (t.alias)) continue;
                    var conds = new Gee.ArrayList<string> ();
                    JoinKind kind = JoinKind.INNER;
                    bool found = false;
                    foreach (var j in joins) {
                        if (used.contains (j)) continue;
                        bool forward = j.right == t.alias && added.contains (j.left);
                        bool backward = j.left == t.alias && added.contains (j.right);
                        if (!forward && !backward) continue;
                        found = true;
                        used.add (j);
                        conds.add ("%s.%s = %s.%s".printf (Sql.quote_ident (j.left), Sql.quote_ident (j.left_field), Sql.quote_ident (j.right), Sql.quote_ident (j.right_field)));
                        if (conds.size == 1) {
                            kind = j.kind;
                            if (backward) {
                                if (kind == JoinKind.LEFT) kind = JoinKind.RIGHT;
                                else if (kind == JoinKind.RIGHT) kind = JoinKind.LEFT;
                            }
                        }
                    }
                    if (!found) continue;
                    sb.append ("\n%s %s ON %s".printf (kind.sql (), table_ref (t), string.joinv (" AND ", conds.to_array ())));
                    added.add (t.alias);
                    progress = true;
                }
            }
            foreach (var t in tables) {
                if (added.contains (t.alias)) continue;
                sb.append ("\nCROSS JOIN %s".printf (table_ref (t)));
                added.add (t.alias);
            }
            var extra = new Gee.ArrayList<string> ();
            foreach (var j in joins) {
                if (!used.contains (j) && find_table (j.left) != null && find_table (j.right) != null) {
                    extra.add ("%s.%s = %s.%s".printf (Sql.quote_ident (j.left), Sql.quote_ident (j.left_field), Sql.quote_ident (j.right), Sql.quote_ident (j.right_field)));
                }
            }
            pending_join_conditions = extra;
            return sb.str;
        }

        private Gee.ArrayList<string> pending_join_conditions = new Gee.ArrayList<string> ();

        private static string table_ref (QueryTable t) {
            if (t.alias == t.name) return Sql.quote_ident (t.name);
            return "%s AS %s".printf (Sql.quote_ident (t.name), Sql.quote_ident (t.alias));
        }

        private void criteria_clauses (out string where_clause, out string having_clause) throws SchemaError {
            int rows = criteria_rows ();
            string[] where_rows = {};
            string[] having_rows = {};
            for (int r = 0; r < rows; r++) {
                string[] w = {};
                string[] h = {};
                foreach (var c in columns) {
                    string text = c.criterion (r).strip ();
                    if (text == "") continue;
                    bool agg = (totals || query_type == QueryType.CROSSTAB) && c.total.is_aggregate () && c.crosstab == "value";
                    if (query_type != QueryType.CROSSTAB) agg = totals && c.total.is_aggregate ();
                    string expr = agg ? column_expr (c) : c.base_expr ();
                    string cond = Criteria.to_sql (expr, text);
                    if (agg) h += cond;
                    else w += cond;
                }
                if (w.length > 0) where_rows += string.joinv (" AND ", w);
                if (h.length > 0) having_rows += string.joinv (" AND ", h);
            }
            where_clause = combine_or (where_rows);
            having_clause = combine_or (having_rows);
        }

        private static string combine_or (string[] rows) {
            if (rows.length == 0) return "";
            if (rows.length == 1) return rows[0];
            string[] wrapped = {};
            foreach (string r in rows) wrapped += "(" + r + ")";
            return string.joinv (" OR ", wrapped);
        }

        public string select_sql () throws SchemaError {
            string from = from_clause ();
            var sb = new StringBuilder ("SELECT ");
            if (distinct) sb.append ("DISTINCT ");
            string[] items = {};
            foreach (var c in columns) {
                if (!c.show || (totals && c.total == Aggregate.WHERE)) continue;
                string e = column_expr (c);
                string a = column_alias (c);
                items += a != "" ? "%s AS %s".printf (e, Sql.quote_ident (a)) : e;
            }
            if (items.length == 0) {
                if (totals) throw new SchemaError.INVALID (_("Show at least one field in the query."));
                items += "*";
            }
            sb.append (string.joinv (", ", items));
            sb.append ("\nFROM ").append (from);
            string where_c, having_c;
            criteria_clauses (out where_c, out having_c);
            if (pending_join_conditions.size > 0) {
                string extra = string.joinv (" AND ", pending_join_conditions.to_array ());
                where_c = where_c == "" ? extra : "(%s) AND (%s)".printf (extra, where_c);
            }
            if (where_c != "") sb.append ("\nWHERE ").append (where_c);
            if (totals) {
                string[] groups = {};
                foreach (var c in columns) {
                    if (c.total == Aggregate.GROUP_BY) groups += c.base_expr ();
                }
                if (groups.length > 0) sb.append ("\nGROUP BY ").append (string.joinv (", ", groups));
                if (having_c != "") sb.append ("\nHAVING ").append (having_c);
            }
            string[] orders = {};
            foreach (var c in columns) {
                if (c.sort == SortOrder.NONE) continue;
                if (totals && c.total == Aggregate.WHERE) continue;
                orders += column_expr (c) + (c.sort == SortOrder.DESCENDING ? " DESC" : "");
            }
            if (orders.length > 0) sb.append ("\nORDER BY ").append (string.joinv (", ", orders));
            if (limit > 0) sb.append ("\nLIMIT %d".printf (limit));
            return sb.str;
        }

        public string to_sql () throws SchemaError {
            return parameters_clause () + body_sql ();
        }

        private string body_sql () throws SchemaError {
            switch (query_type) {
                case QueryType.CROSSTAB:
                    return crosstab_sql ();
                case QueryType.MAKE_TABLE:
                    if (target.strip () == "") throw new SchemaError.INVALID (_("Choose a name for the new table."));
                    return "CREATE TABLE %s AS\n%s".printf (Sql.quote_ident (target), select_sql ());
                case QueryType.APPEND:
                    if (target.strip () == "") throw new SchemaError.INVALID (_("Choose the table to append to."));
                    string[] dest = {};
                    string[] src = {};
                    foreach (var c in columns) {
                        if (c.append_to.strip () == "") continue;
                        dest += Sql.quote_ident (c.append_to);
                        src += c.base_expr ();
                    }
                    if (dest.length == 0) throw new SchemaError.INVALID (_("Choose at least one field to append to."));
                    string from = from_clause ();
                    var sb = new StringBuilder ("INSERT INTO %s (%s)\nSELECT %s\nFROM %s".printf (Sql.quote_ident (target), string.joinv (", ", dest), string.joinv (", ", src), from));
                    string w, h;
                    criteria_clauses (out w, out h);
                    if (w != "") sb.append ("\nWHERE ").append (w);
                    return sb.str;
                case QueryType.UPDATE:
                    return update_sql ();
                case QueryType.DELETE:
                    return delete_sql ();
                default:
                    return select_sql ();
            }
        }

        private string single_table_where (out QueryTable t) throws SchemaError {
            if (tables.size == 0) throw new SchemaError.INVALID (_("Add a table to the query."));
            t = tables[0];
            int rows = criteria_rows ();
            string[] rs = {};
            for (int r = 0; r < rows; r++) {
                string[] w = {};
                foreach (var c in columns) {
                    string text = c.criterion (r).strip ();
                    if (text == "") continue;
                    string expr = c.expression != "" ? bracket_refs (c.expression) : Sql.quote_ident (c.field);
                    if (c.table != "" && c.table != t.alias) {
                        var other = find_table (c.table);
                        if (other == null) continue;
                        string link = link_condition (t, other);
                        w += "EXISTS (SELECT 1 FROM %s WHERE %s AND %s)".printf (table_ref (other), link, Criteria.to_sql (c.base_expr (), text));
                        continue;
                    }
                    w += Criteria.to_sql (expr, text);
                }
                if (w.length > 0) rs += string.joinv (" AND ", w);
            }
            return combine_or (rs);
        }

        private string link_condition (QueryTable main, QueryTable other) throws SchemaError {
            foreach (var j in joins) {
                if (j.left == main.alias && j.right == other.alias) return "%s.%s = %s.%s".printf (Sql.quote_ident (other.alias), Sql.quote_ident (j.right_field), Sql.quote_ident (main.name), Sql.quote_ident (j.left_field));
                if (j.right == main.alias && j.left == other.alias) return "%s.%s = %s.%s".printf (Sql.quote_ident (other.alias), Sql.quote_ident (j.left_field), Sql.quote_ident (main.name), Sql.quote_ident (j.right_field));
            }
            throw new SchemaError.INVALID (_("Join \"%s\" to \"%s\" to use it in the criteria.").printf (other.alias, main.alias));
        }

        private string update_sql () throws SchemaError {
            QueryTable t;
            string where_c = single_table_where (out t);
            string[] sets = {};
            foreach (var c in columns) {
                if (c.update_to.strip () == "" || c.field == "" || c.field == "*") continue;
                if (c.table != "" && c.table != t.alias) continue;
                sets += "%s = %s".printf (Sql.quote_ident (c.field), Criteria.literal_or_expr (c.update_to.strip ()));
            }
            if (sets.length == 0) throw new SchemaError.INVALID (_("Enter a new value in Update To for at least one field."));
            var sb = new StringBuilder ("UPDATE %s SET %s".printf (Sql.quote_ident (t.name), string.joinv (", ", sets)));
            if (where_c != "") sb.append ("\nWHERE ").append (where_c);
            return sb.str;
        }

        private string delete_sql () throws SchemaError {
            QueryTable t;
            string where_c = single_table_where (out t);
            var sb = new StringBuilder ("DELETE FROM %s".printf (Sql.quote_ident (t.name)));
            if (where_c != "") sb.append ("\nWHERE ").append (where_c);
            return sb.str;
        }

        public string to_json () {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("type").add_string_value (query_type.id ());
            b.set_member_name ("distinct").add_boolean_value (distinct);
            b.set_member_name ("totals").add_boolean_value (totals);
            b.set_member_name ("limit").add_int_value (limit);
            b.set_member_name ("target").add_string_value (target);
            b.set_member_name ("params").begin_array ();
            foreach (var p in params) {
                b.begin_object ();
                b.set_member_name ("name").add_string_value (p.name);
                b.set_member_name ("type").add_string_value (p.type_name);
                b.end_object ();
            }
            b.end_array ();
            b.set_member_name ("tables").begin_array ();
            foreach (var t in tables) {
                b.begin_object ();
                b.set_member_name ("name").add_string_value (t.name);
                b.set_member_name ("alias").add_string_value (t.alias);
                b.set_member_name ("x").add_double_value (t.x);
                b.set_member_name ("y").add_double_value (t.y);
                b.end_object ();
            }
            b.end_array ();
            b.set_member_name ("joins").begin_array ();
            foreach (var j in joins) {
                b.begin_object ();
                b.set_member_name ("left").add_string_value (j.left);
                b.set_member_name ("left-field").add_string_value (j.left_field);
                b.set_member_name ("right").add_string_value (j.right);
                b.set_member_name ("right-field").add_string_value (j.right_field);
                b.set_member_name ("kind").add_string_value (j.kind.id ());
                b.end_object ();
            }
            b.end_array ();
            b.set_member_name ("columns").begin_array ();
            foreach (var c in columns) {
                b.begin_object ();
                b.set_member_name ("table").add_string_value (c.table);
                b.set_member_name ("field").add_string_value (c.field);
                b.set_member_name ("expression").add_string_value (c.expression);
                b.set_member_name ("alias").add_string_value (c.alias);
                b.set_member_name ("show").add_boolean_value (c.show);
                b.set_member_name ("sort").add_int_value ((int) c.sort);
                b.set_member_name ("total").add_string_value (c.total.id ());
                b.set_member_name ("update-to").add_string_value (c.update_to);
                b.set_member_name ("append-to").add_string_value (c.append_to);
                if (c.crosstab != "") b.set_member_name ("crosstab").add_string_value (c.crosstab);
                b.set_member_name ("criteria").begin_array ();
                foreach (string s in c.criteria) b.add_string_value (s);
                b.end_array ();
                b.end_object ();
            }
            b.end_array ();
            b.end_object ();
            return Json.to_string (b.get_root (), false);
        }

        public static QueryDesign? from_json (string json) {
            var o = Meta.parse_object (json);
            if (o == null) return null;
            var d = new QueryDesign ();
            d.query_type = QueryType.from_id (o.get_string_member_with_default ("type", "select"));
            d.distinct = o.get_boolean_member_with_default ("distinct", false);
            d.totals = o.get_boolean_member_with_default ("totals", false);
            d.limit = (int) o.get_int_member_with_default ("limit", 0);
            d.target = o.get_string_member_with_default ("target", "");
            if (o.has_member ("params")) {
                o.get_array_member ("params").foreach_element ((a, i, n) => {
                    var po = n.get_object ();
                    d.params.add (new QueryParam (po.get_string_member_with_default ("name", ""), po.get_string_member_with_default ("type", "")));
                });
            }
            if (o.has_member ("tables")) {
                o.get_array_member ("tables").foreach_element ((a, i, n) => {
                    var t = n.get_object ();
                    var qt = new QueryTable (t.get_string_member_with_default ("name", ""), t.get_string_member_with_default ("alias", ""));
                    qt.x = t.get_double_member_with_default ("x", 24);
                    qt.y = t.get_double_member_with_default ("y", 24);
                    d.tables.add (qt);
                });
            }
            if (o.has_member ("joins")) {
                o.get_array_member ("joins").foreach_element ((a, i, n) => {
                    var j = n.get_object ();
                    d.joins.add (new QueryJoin (j.get_string_member_with_default ("left", ""), j.get_string_member_with_default ("left-field", ""),
                        j.get_string_member_with_default ("right", ""), j.get_string_member_with_default ("right-field", ""),
                        JoinKind.from_id (j.get_string_member_with_default ("kind", "inner"))));
                });
            }
            if (o.has_member ("columns")) {
                o.get_array_member ("columns").foreach_element ((a, i, n) => {
                    var c = n.get_object ();
                    var qc = new QueryColumn (c.get_string_member_with_default ("table", ""), c.get_string_member_with_default ("field", ""));
                    qc.expression = c.get_string_member_with_default ("expression", "");
                    qc.alias = c.get_string_member_with_default ("alias", "");
                    qc.show = c.get_boolean_member_with_default ("show", true);
                    qc.sort = (SortOrder) c.get_int_member_with_default ("sort", 0);
                    qc.total = Aggregate.from_id (c.get_string_member_with_default ("total", "group"));
                    qc.update_to = c.get_string_member_with_default ("update-to", "");
                    qc.append_to = c.get_string_member_with_default ("append-to", "");
                    qc.crosstab = c.get_string_member_with_default ("crosstab", "");
                    qc.criteria = Meta.string_array (c, "criteria");
                    d.columns.add (qc);
                });
            }
            return d;
        }
    }

    public class Criteria {
        private static string strip_outer (string s) {
            return s.strip ();
        }

        private static Gee.ArrayList<string> split_top (string text, string word) {
            var parts = new Gee.ArrayList<string> ();
            int depth = 0;
            bool quote = false;
            char qc = 0;
            int start = 0;
            int n = text.length;
            string lw = word.down ();
            int i = 0;
            bool between_open = false;
            while (i < n) {
                char c = text[i];
                if (quote) {
                    if (c == qc) quote = false;
                    i++;
                    continue;
                }
                if (c == '\'' || c == '"' || c == '#') {
                    quote = true;
                    qc = c;
                    i++;
                    continue;
                }
                if (c == '(') depth++;
                else if (c == ')') depth--;
                if (depth == 0 && (i == 0 || text[i - 1].isspace ())) {
                    if (text.substring (i).down ().has_prefix ("between") && (i + 7 >= n || text[i + 7].isspace ())) between_open = true;
                    if (text.substring (i).down ().has_prefix (lw) && i + lw.length < n && text[i + lw.length].isspace ()) {
                        if (lw == "and" && between_open) {
                            between_open = false;
                        } else {
                            parts.add (text.substring (start, i - start));
                            start = i + lw.length;
                            i = start;
                            continue;
                        }
                    }
                }
                i++;
            }
            parts.add (text.substring (start));
            return parts;
        }

        public static string literal (string raw) {
            string s = raw.strip ();
            if (s == "") return "''";
            if (s.length >= 2 && s[0] == '#' && s[s.length - 1] == '#') {
                string iso;
                string inner = s.substring (1, s.length - 2);
                if (Codec.parse_datetime (inner, out iso) && inner.contains (":")) return Sql.quote_string (iso);
                if (Codec.parse_date (inner, out iso)) return Sql.quote_string (iso);
                return Sql.quote_string (inner);
            }
            if (s.length >= 2 && ((s[0] == '"' && s[s.length - 1] == '"') || (s[0] == '\'' && s[s.length - 1] == '\''))) {
                string inner = s.substring (1, s.length - 2);
                if (s[0] == '\'') inner = inner.replace ("''", "'");
                else inner = inner.replace ("\"\"", "\"");
                return Sql.quote_string (inner);
            }
            string low = s.down ();
            if (low == "date()" || low == "today()") return "date('now','localtime')";
            if (low == "now()") return "datetime('now','localtime')";
            if (low == "true" || low == "yes") return "1";
            if (low == "false" || low == "no") return "0";
            if (low == "null") return "NULL";
            if (s.has_prefix ("[") && s.has_suffix ("]") && s.index_of ("]") == s.length - 1) return Sql.quote_ident (s.substring (1, s.length - 2));
            double d;
            string num = s.replace (",", ".");
            if (double.try_parse (num, out d) && !s.contains (" ")) {
                if (s.contains (",") && s.contains (".")) return Sql.quote_string (s);
                return num;
            }
            return Sql.quote_string (s);
        }

        public static string literal_or_expr (string raw) {
            string s = raw.strip ();
            if (s.has_prefix ("=")) return QueryDesign.bracket_refs (s.substring (1).strip ());
            if (s.contains ("[") && s.contains ("]") && !(s.has_prefix ("[") && s.index_of ("]") == s.length - 1)) return QueryDesign.bracket_refs (s);
            return literal (s);
        }

        private static string like_pattern (string raw) {
            string lit = literal (raw);
            if (!lit.has_prefix ("'")) return lit;
            string inner = Sql.unquote_string (lit);
            bool escape = inner.contains ("%") || inner.contains ("_");
            var sb = new StringBuilder ();
            unichar ch;
            int i = 0;
            while (inner.get_next_char (ref i, out ch)) {
                if (ch == '*') sb.append_c ('%');
                else if (ch == '?') sb.append_c ('_');
                else if (escape && (ch == '%' || ch == '_' || ch == '\\')) {
                    sb.append_c ('\\');
                    sb.append_unichar (ch);
                } else sb.append_unichar (ch);
            }
            string pattern = Sql.quote_string (sb.str);
            return escape ? pattern + " ESCAPE '\\'" : pattern;
        }

        public static string to_sql (string expr, string text) {
            var ors = split_top (text.strip (), "or");
            if (ors.size > 1) {
                string[] parts = {};
                foreach (string p in ors) {
                    if (p.strip () == "") continue;
                    parts += "(" + to_sql (expr, p) + ")";
                }
                return string.joinv (" OR ", parts);
            }
            var ands = split_top (text.strip (), "and");
            if (ands.size > 1) {
                string[] parts = {};
                foreach (string p in ands) {
                    if (p.strip () == "") continue;
                    parts += "(" + to_sql (expr, p) + ")";
                }
                return string.joinv (" AND ", parts);
            }
            return single (expr, strip_outer (text));
        }

        private static string single (string expr, string t) {
            string low = t.down ();
            if (low == "is null" || low == "null") return "%s IS NULL".printf (expr);
            if (low == "is not null" || low == "not null") return "%s IS NOT NULL".printf (expr);
            if (low.has_prefix ("not ")) return "NOT (%s)".printf (single (expr, t.substring (4).strip ()));
            if (low.has_prefix ("between ")) {
                string rest = t.substring (8);
                int and_pos = rest.down ().index_of (" and ");
                if (and_pos > 0) {
                    return "%s BETWEEN %s AND %s".printf (expr, literal_or_expr (rest.substring (0, and_pos)), literal_or_expr (rest.substring (and_pos + 5)));
                }
            }
            if (low.has_prefix ("like ")) return "%s LIKE %s".printf (expr, like_pattern (t.substring (5)));
            if (low.has_prefix ("in ") || low.has_prefix ("in(")) {
                string rest = t.substring (2).strip ();
                if (rest.has_prefix ("(") && rest.has_suffix (")")) rest = rest.substring (1, rest.length - 2);
                string[] items = {};
                foreach (string item in split_list (rest)) items += literal_or_expr (item);
                return "%s IN (%s)".printf (expr, string.joinv (", ", items));
            }
            string[] ops = { "<=", ">=", "<>", "!=", "=", "<", ">" };
            foreach (string op in ops) {
                if (t.has_prefix (op)) {
                    string rhs = t.substring (op.length).strip ();
                    string sop = op == "!=" ? "<>" : op;
                    if (rhs.down () == "null") return sop == "=" ? "%s IS NULL".printf (expr) : "%s IS NOT NULL".printf (expr);
                    return "%s %s %s".printf (expr, sop, literal_or_expr (rhs));
                }
            }
            if (t.contains ("*") || t.contains ("?")) {
                bool quoted = t.length >= 2 && (t[0] == '"' || t[0] == '\'');
                if (!quoted || t.contains ("*")) return "%s LIKE %s".printf (expr, like_pattern (t));
            }
            return "%s = %s".printf (expr, literal_or_expr (t));
        }

        private static Gee.ArrayList<string> split_list (string s) {
            var list = new Gee.ArrayList<string> ();
            int depth = 0;
            bool quote = false;
            char qc = 0;
            int start = 0;
            for (int i = 0; i < s.length; i++) {
                char c = s[i];
                if (quote) {
                    if (c == qc) quote = false;
                    continue;
                }
                if (c == '\'' || c == '"' || c == '#') {
                    quote = true;
                    qc = c;
                } else if (c == '(') depth++;
                else if (c == ')') depth--;
                else if ((c == ',' || c == ';') && depth == 0) {
                    list.add (s.substring (start, i - start).strip ());
                    start = i + 1;
                }
            }
            string last = s.substring (start).strip ();
            if (last != "") list.add (last);
            return list;
        }
    }
}
