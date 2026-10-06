namespace Singularity.Apps.Database {

    public class QueryParam {
        public string name;
        public string type_name = "";
        public DbValue value = new DbValue.null ();

        public QueryParam (string name, string type_name = "") {
            this.name = name;
            this.type_name = type_name;
        }

        public FieldType field_type () {
            string t = type_name.down ();
            if (t.contains ("date")) return t.contains ("time") ? FieldType.DATETIME : FieldType.DATE;
            if (t.contains ("bit") || t.contains ("yesno") || t.contains ("bool")) return FieldType.BOOLEAN;
            if (t.contains ("long") || t.contains ("int") || t.contains ("byte") || t.contains ("short")) return FieldType.INTEGER;
            if (t.contains ("double") || t.contains ("single") || t.contains ("float") || t.contains ("decimal") || t.contains ("numeric") || t == "ieeedouble" || t == "ieeesingle") return FieldType.NUMBER;
            if (t.contains ("currency") || t.contains ("money")) return FieldType.CURRENCY;
            if (t == "value" || t == "") return FieldType.TEXT;
            return FieldType.TEXT;
        }
    }

    public delegate DbValue? ParamResolver (string name);

    public class SavedQuery {
        public string name;
        public string sql;
        public string design = "";
        public string description = "";
        public string kind = "select";
        public string connection = "";
        public bool is_view;
    }

    public class SavedQueries {
        public const string PREFIX = "action:";

        public static SavedQuery? load (Database db, string name) {
            var q = db.load_query (name);
            if (q != null && db.object_exists (name, "view")) {
                var s = new SavedQuery ();
                s.name = name;
                s.sql = q.sql;
                s.design = q.design;
                s.description = q.description;
                s.is_view = true;
                s.kind = QueryPrep.kind_of (q.sql);
                return s;
            }
            var o = Meta.parse_object (db.get_meta (PREFIX + name));
            if (o == null) return null;
            var s = new SavedQuery ();
            s.name = name;
            s.sql = o.get_string_member_with_default ("sql", "");
            s.design = o.get_string_member_with_default ("design", "");
            s.description = o.get_string_member_with_default ("description", "");
            s.connection = o.get_string_member_with_default ("connection", "");
            s.kind = o.get_string_member_with_default ("kind", QueryPrep.kind_of (s.sql));
            if (s.connection != "") s.kind = "pass-through";
            return s;
        }

        public static string to_json (string sql, string design, string kind, string connection = "", string description = "") {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("sql").add_string_value (sql);
            b.set_member_name ("design").add_string_value (design);
            b.set_member_name ("kind").add_string_value (kind);
            if (connection != "") b.set_member_name ("connection").add_string_value (connection);
            if (description != "") b.set_member_name ("description").add_string_value (description);
            b.end_object ();
            return Json.to_string (b.get_root (), false);
        }

        public static void save (Database db, string name, string sql, string design = "", string connection = "", string? old_name = null) throws Error {
            string stmt = sql.strip ();
            while (stmt.has_suffix (";")) stmt = stmt.substring (0, stmt.length - 1).strip ();
            if (connection == "" && QueryPrep.can_be_view (db, stmt)) {
                var q = new QueryDef (name, stmt);
                q.design = design;
                if (db.get_meta (PREFIX + name) != null) db.save_object_meta (_("Save Query"), PREFIX, name, null);
                db.save_query (q, db.object_exists (old_name ?? name, "view") ? (old_name ?? name) : null);
                return;
            }
            if (db.object_exists (name, "view")) db.drop_object (name);
            db.save_object_meta (_("Save Query"), PREFIX, name, to_json (stmt, design, connection != "" ? "pass-through" : QueryPrep.kind_of (stmt), connection), old_name);
        }
    }

    public class CrosstabParts {
        public string aggregate_fn = "";
        public string value_expr = "";
        public string select_sql = "";
        public string pivot_expr = "";
        public string transform_expr = "";
        public string[] fixed_values = {};
        public bool has_fixed;
    }

    public class QueryPrep {
        public static string kind_of (string sql) {
            var toks = Sql.tokenize (sql);
            if (toks.size == 0) return "select";
            string first = toks[0].text.up ();
            if (first == "PARAMETERS") {
                int i = 0;
                while (i < toks.size && toks[i].text != ";") i++;
                if (i + 1 < toks.size) first = toks[i + 1].text.up ();
                if (first == "SELECT" && !has_top_word (toks, "INTO")) return "parameter";
            }
            switch (first) {
                case "TRANSFORM": return "crosstab";
                case "INSERT": return "append";
                case "UPDATE": return "update";
                case "DELETE": return "delete";
                case "CREATE":
                    if (toks.size > 1 && toks[1].text.up () == "TABLE" && has_top_word (toks, "AS") && has_top_word (toks, "SELECT")) return "make-table";
                    return "data-definition";
                case "DROP":
                case "ALTER": return "data-definition";
            }
            if (has_top_word (toks, "UNION")) return "union";
            return "select";
        }

        private static bool has_top_word (Gee.ArrayList<Token> toks, string w) {
            int depth = 0;
            foreach (var t in toks) {
                if (t.text == "(") depth++;
                else if (t.text == ")") depth--;
                else if (depth == 0 && t.text.up () == w) return true;
            }
            return false;
        }

        public static bool can_be_view (Database db, string sql) {
            string k = kind_of (sql);
            if (k != "select" && k != "union") return false;
            if (!Sql.is_read_only (sql) || Sql.split_statements (sql).size != 1) return false;
            try {
                db.prepare ("SELECT * FROM (%s) LIMIT 0".printf (sql));
                return true;
            } catch (Error e) {
                return false;
            }
        }

        public static bool is_select_like (string sql) {
            string k = kind_of (sql);
            return k == "select" || k == "union" || k == "crosstab" || k == "parameter";
        }

        public static string strip_parameters (string sql, Gee.ArrayList<QueryParam> declared) {
            string s = sql.strip ();
            var toks = Sql.tokenize (s);
            if (toks.size == 0 || toks[0].text.up () != "PARAMETERS") return s;
            int semi = -1;
            for (int i = 0; i < toks.size; i++) {
                if (toks[i].text == ";") {
                    semi = i;
                    break;
                }
            }
            if (semi < 0) return s;
            var cur = new Gee.ArrayList<Token> ();
            for (int i = 1; i <= semi; i++) {
                if (toks[i].text == "," || toks[i].text == ";") {
                    if (cur.size > 0) {
                        string pname = Sql.unquote_ident (cur[0].text);
                        string[] tparts = {};
                        for (int k = 1; k < cur.size; k++) tparts += cur[k].text;
                        declared.add (new QueryParam (pname, string.joinv (" ", tparts)));
                    }
                    cur.clear ();
                    continue;
                }
                cur.add (toks[i]);
            }
            return s.substring (toks[semi].end).strip ();
        }

        public static CrosstabParts? split_crosstab (string sql) {
            var toks = Sql.tokenize (sql);
            if (toks.size < 4 || toks[0].text.up () != "TRANSFORM") return null;
            int sel = -1, pivot = -1;
            int depth = 0;
            for (int i = 1; i < toks.size; i++) {
                if (toks[i].text == "(") depth++;
                else if (toks[i].text == ")") depth--;
                else if (depth == 0 && toks[i].text.up () == "SELECT" && sel < 0) sel = i;
                else if (depth == 0 && toks[i].text.up () == "PIVOT") pivot = i;
            }
            if (sel < 0 || pivot < 0) return null;
            var p = new CrosstabParts ();
            string agg = sql.substring (toks[1].start, toks[sel - 1].end - toks[1].start).strip ();
            int as_at = -1;
            int d2 = 0;
            for (int i = 1; i < sel; i++) {
                if (toks[i].text == "(") d2++;
                else if (toks[i].text == ")") d2--;
                else if (d2 == 0 && toks[i].text.up () == "AS") as_at = i;
            }
            if (as_at > 1) agg = sql.substring (toks[1].start, toks[as_at - 1].end - toks[1].start).strip ();
            p.transform_expr = agg;
            int open = agg.index_of ("(");
            if (open > 0 && agg.has_suffix (")")) {
                p.aggregate_fn = agg.substring (0, open).strip ();
                p.value_expr = agg.substring (open + 1, agg.length - open - 2).strip ();
            } else {
                p.aggregate_fn = "";
                p.value_expr = agg;
            }
            p.select_sql = sql.substring (toks[sel].start, toks[pivot].start - toks[sel].start).strip ();
            int in_at = -1;
            depth = 0;
            for (int i = pivot + 1; i < toks.size; i++) {
                if (toks[i].text == "(") depth++;
                else if (toks[i].text == ")") depth--;
                else if (depth == 0 && toks[i].text.up () == "IN") {
                    in_at = i;
                    break;
                }
            }
            int pend = in_at > 0 ? toks[in_at].start : sql.length;
            p.pivot_expr = sql.substring (toks[pivot].end, pend - toks[pivot].end).strip ();
            if (in_at > 0) {
                p.has_fixed = true;
                string[] vals = {};
                for (int i = in_at + 1; i < toks.size; i++) {
                    var t = toks[i];
                    if (t.text == "(" || t.text == ")" || t.text == ",") continue;
                    if (t.kind == TokenKind.STRING) vals += Sql.unquote_string (t.text);
                    else vals += Sql.unquote_ident (t.text);
                }
                p.fixed_values = vals;
            }
            return p;
        }

        private static int find_top_kw (Gee.ArrayList<Token> toks, string w, int from = 0) {
            int depth = 0;
            for (int i = from; i < toks.size; i++) {
                if (toks[i].text == "(") depth++;
                else if (toks[i].text == ")") depth--;
                else if (depth == 0 && toks[i].text.up () == w) return i;
            }
            return -1;
        }

        public static string crosstab_probe (string sql) {
            var p = split_crosstab (sql);
            if (p == null) return sql;
            var toks = Sql.tokenize (p.select_sql);
            int from = find_top_kw (toks, "FROM");
            if (from < 0) return p.select_sql;
            string select_list = p.select_sql.substring (toks[0].end, toks[from].start - toks[0].end).strip ();
            return "SELECT %s, %s, %s %s".printf (select_list, p.pivot_expr, p.value_expr == "*" ? "1" : p.value_expr, p.select_sql.substring (toks[from].start));
        }

        private static string wrap_aggregates (string expr, string cond) {
            string[] aggs = { "SUM", "AVG", "COUNT", "MIN", "MAX", "FIRST", "LAST", "STDEV", "STDEVP", "VAR", "VARP", "TOTAL" };
            var toks = Sql.tokenize (expr);
            var sb = new StringBuilder ();
            int pos = 0;
            for (int i = 0; i + 1 < toks.size; i++) {
                bool is_agg = false;
                foreach (string a in aggs) {
                    if (toks[i].text.up () == a) is_agg = true;
                }
                if (!is_agg || toks[i + 1].text != "(") continue;
                int depth = 0;
                int close = -1;
                for (int k = i + 1; k < toks.size; k++) {
                    if (toks[k].text == "(") depth++;
                    else if (toks[k].text == ")") {
                        depth--;
                        if (depth == 0) {
                            close = k;
                            break;
                        }
                    }
                }
                if (close < 0) break;
                string inner = expr.substring (toks[i + 1].end, toks[close].start - toks[i + 1].end).strip ();
                sb.append (expr.substring (pos, toks[i + 1].end - pos));
                if (inner == "*") sb.append ("CASE WHEN %s THEN 1 END".printf (cond));
                else sb.append ("CASE WHEN %s THEN %s END".printf (cond, inner));
                sb.append (")");
                pos = toks[close].end;
                i = close;
            }
            sb.append (expr.substring (pos));
            return sb.str;
        }

        public static string expand_crosstab (Database db, string sql) throws Error {
            var p = split_crosstab (sql);
            if (p == null) return sql;
            var toks = Sql.tokenize (p.select_sql);
            int from = find_top_kw (toks, "FROM");
            if (from < 0) throw new SchemaError.INVALID (_("The crosstab query needs a FROM clause."));
            int group = find_top_kw (toks, "GROUP", from);
            int order = find_top_kw (toks, "ORDER", from);
            int having = find_top_kw (toks, "HAVING", from);
            int from_end = group > 0 ? toks[group].start : (order > 0 ? toks[order].start : p.select_sql.length);
            string from_where = p.select_sql.substring (toks[from].start, from_end - toks[from].start).strip ();
            string select_list = p.select_sql.substring (toks[0].end, toks[from].start - toks[0].end).strip ();
            string group_clause = "";
            if (group > 0) {
                int gend = having > 0 ? toks[having].start : (order > 0 ? toks[order].start : p.select_sql.length);
                group_clause = p.select_sql.substring (toks[group].start, gend - toks[group].start).strip ();
            }
            string tail = "";
            if (having > 0) tail += " " + p.select_sql.substring (toks[having].start, (order > 0 ? toks[order].start : p.select_sql.length) - toks[having].start).strip ();
            string order_clause = order > 0 ? p.select_sql.substring (toks[order].start).strip () : "";
            var values = new Gee.ArrayList<DbValue> ();
            if (p.has_fixed) {
                foreach (string v in p.fixed_values) values.add (new DbValue.text (v));
            } else {
                var rs = db.query ("SELECT DISTINCT %s %s ORDER BY 1".printf (p.pivot_expr, from_where));
                foreach (var r in rs.rows) values.add (r.get (0));
            }
            var cols = new StringBuilder (select_list);
            foreach (var v in values) {
                string label = v.is_null ? "<>" : v.to_string ();
                string cond = v.is_null ? "(%s) IS NULL".printf (p.pivot_expr) : (p.has_fixed ? "CAST((%s) AS TEXT) = %s".printf (p.pivot_expr, Sql.quote_string (v.to_string ())) : "(%s) = %s".printf (p.pivot_expr, v.sql_literal ()));
                string cell = wrap_aggregates (p.transform_expr, cond);
                if (cell == p.transform_expr) cell = "max(CASE WHEN %s THEN %s END)".printf (cond, p.transform_expr);
                cols.append (", ").append (cell).append (" AS ").append (Sql.quote_ident (label));
            }
            var sb = new StringBuilder ("SELECT ");
            sb.append (cols.str).append (" ").append (from_where);
            if (group_clause != "") sb.append (" ").append (group_clause);
            sb.append (tail);
            if (order_clause != "") sb.append (" ").append (order_clause);
            return sb.str;
        }

        public static Gee.ArrayList<QueryParam> find_parameters (Database db, string sql0, Gee.ArrayList<QueryParam>? declared_out = null) {
            var declared = new Gee.ArrayList<QueryParam> ();
            string sql = strip_parameters (sql0, declared);
            var result = new Gee.ArrayList<QueryParam> ();
            result.add_all (declared);
            if (declared_out != null) declared_out.add_all (declared);
            var names = new Gee.HashSet<string> ();
            foreach (var d in declared) names.add (d.name.casefold ());
            for (int guard = 0; guard < 32; guard++) {
                string probe;
                try {
                    probe = substitute (sql, result);
                    if (kind_of (probe) == "crosstab") probe = crosstab_probe (probe);
                    db.prepare (probe);
                    break;
                } catch (Error e) {
                    string m = e.message;
                    string key = "no such column: ";
                    int at = m.index_of (key);
                    if (at < 0) break;
                    string name = m.substring (at + key.length).strip ();
                    if (!names.add (name.casefold ())) break;
                    result.add (new QueryParam (name));
                }
            }
            return result;
        }

        public static string substitute (string sql, Gee.List<QueryParam> params) {
            if (params.size == 0) return sql;
            var toks = Sql.tokenize (sql, true);
            var sb = new StringBuilder ();
            for (int i = 0; i < toks.size; i++) {
                var t = toks[i];
                if (t.kind == TokenKind.IDENTIFIER || t.kind == TokenKind.QUOTED_IDENTIFIER || t.kind == TokenKind.KEYWORD || t.kind == TokenKind.FUNCTION) {
                    string full = Sql.unquote_ident (t.text);
                    int consumed = i;
                    if (i + 2 < toks.size && toks[i + 1].text == "." && (toks[i + 2].kind == TokenKind.IDENTIFIER || toks[i + 2].kind == TokenKind.QUOTED_IDENTIFIER)) {
                        string qualified = full + "." + Sql.unquote_ident (toks[i + 2].text);
                        foreach (var p in params) {
                            if (p.name.casefold () == qualified.casefold ()) {
                                sb.append (p.value.sql_literal ());
                                consumed = i + 2;
                                break;
                            }
                        }
                        if (consumed != i) {
                            i = consumed;
                            continue;
                        }
                    }
                    bool replaced = false;
                    bool prev_dot = i > 0 && toks[i - 1].text == ".";
                    if (!prev_dot && (t.kind == TokenKind.QUOTED_IDENTIFIER || t.kind == TokenKind.IDENTIFIER)) {
                        foreach (var p in params) {
                            if (p.name.casefold () == full.casefold ()) {
                                sb.append (p.value.sql_literal ());
                                replaced = true;
                                break;
                            }
                        }
                    }
                    if (replaced) continue;
                }
                sb.append (t.text);
            }
            return sb.str;
        }

        public static string prepare (Database db, string sql, Gee.List<QueryParam>? values = null) throws Error {
            var declared = new Gee.ArrayList<QueryParam> ();
            string body = strip_parameters (sql, declared);
            var all = new Gee.ArrayList<QueryParam> ();
            if (values != null) all.add_all (values);
            string s = substitute (body, all);
            if (kind_of (s) == "crosstab") s = expand_crosstab (db, s);
            return s;
        }

        public static DbValue coerce (QueryParam p, string text) {
            var f = new Field (p.name, p.field_type ());
            try {
                var v = Codec.parse (f, text);
                if (!v.is_null || text.strip () == "") return v;
            } catch (Error e) {
            }
            double d;
            if (Codec.parse_number (text, out d)) return d == Math.floor (d) && !text.contains (".") && !text.contains (",") ? new DbValue.int ((int64) d) : new DbValue.real (d);
            return new DbValue.text (text);
        }
    }

    public class UpdatePlan {
        public string sql;
        public string[] tables = {};
        public string[] aliases = {};
    }

    public class Updatable {
        private static int find_top (Gee.ArrayList<Token> toks, string w, int from = 0) {
            int depth = 0;
            for (int i = from; i < toks.size; i++) {
                if (toks[i].text == "(") depth++;
                else if (toks[i].text == ")") depth--;
                else if (depth == 0 && toks[i].text.up () == w) return i;
            }
            return -1;
        }

        public static UpdatePlan? plan (Database db, string sql) {
            var toks = Sql.tokenize (sql);
            if (toks.size < 4 || toks[0].text.up () != "SELECT") return null;
            string[] blockers = { "DISTINCT", "GROUP", "UNION", "INTERSECT", "EXCEPT", "HAVING", "WINDOW", "VALUES" };
            foreach (string b in blockers) {
                if (find_top (toks, b) >= 0) return null;
            }
            int from = find_top (toks, "FROM");
            if (from < 0) return null;
            int depth = 0;
            for (int i = 1; i < from; i++) {
                var t = toks[i];
                if (t.text == "(") depth++;
                else if (t.text == ")") depth--;
                if ((t.kind == TokenKind.FUNCTION || t.kind == TokenKind.KEYWORD || t.kind == TokenKind.IDENTIFIER) && i + 1 < from && toks[i + 1].text == "(") {
                    string u = t.text.up ();
                    if (u == "SUM" || u == "COUNT" || u == "AVG" || u == "MIN" || u == "MAX" || u == "TOTAL" || u == "GROUP_CONCAT" || u == "FIRST" || u == "LAST" || u == "STDEV" || u == "VAR" || u == "STDEVP" || u == "VARP" || u == "STRING_AGG") return null;
                }
                if (t.text.up () == "OVER") return null;
            }
            string[] ends = { "WHERE", "ORDER", "LIMIT" };
            int end = toks.size;
            foreach (string e in ends) {
                int k = find_top (toks, e, from);
                if (k > 0 && k < end) end = k;
            }
            var plan = new UpdatePlan ();
            string[] tables = {};
            string[] aliases = {};
            int i = from + 1;
            bool expect_table = true;
            while (i < end) {
                var t = toks[i];
                if (t.text == "(") return null;
                if (expect_table) {
                    if (t.kind != TokenKind.IDENTIFIER && t.kind != TokenKind.QUOTED_IDENTIFIER && t.kind != TokenKind.KEYWORD) return null;
                    string name = Sql.unquote_ident (t.text);
                    if (i + 2 < end && toks[i + 1].text == ".") {
                        return null;
                    }
                    if (!db.object_exists (name, "table")) return null;
                    string alias = name;
                    int k = i + 1;
                    if (k < end && toks[k].text.up () == "AS") k++;
                    if (k < end && (toks[k].kind == TokenKind.IDENTIFIER || toks[k].kind == TokenKind.QUOTED_IDENTIFIER)) {
                        alias = Sql.unquote_ident (toks[k].text);
                        k++;
                    }
                    try {
                        if (db.load_table (name).without_rowid) return null;
                    } catch (Error e) {
                        return null;
                    }
                    tables += name;
                    aliases += alias;
                    i = k;
                    expect_table = false;
                    continue;
                }
                string u = t.text.up ();
                if (u == "JOIN" || t.text == ",") expect_table = true;
                i++;
            }
            if (tables.length == 0) return null;
            var sb = new StringBuilder ("SELECT ");
            for (int k = 0; k < aliases.length; k++) sb.append ("%s.rowid AS %s, ".printf (Sql.quote_ident (aliases[k]), Sql.quote_ident ("_sdb_rid_%d".printf (k))));
            sb.append (sql.substring (toks[0].end).strip ());
            plan.sql = sb.str;
            plan.tables = tables;
            plan.aliases = aliases;
            try {
                db.prepare (plan.sql);
            } catch (Error e) {
                return null;
            }
            return plan;
        }

        public static string? single_table (Database db, string sql) {
            var p = plan (db, sql);
            if (p == null || p.tables.length != 1) return null;
            return p.tables[0];
        }

        public static string with_rowid (string sql) {
            var toks = Sql.tokenize (sql);
            return "SELECT rowid AS _sdb_rid, " + sql.substring (toks[0].end).strip ();
        }
    }
}
