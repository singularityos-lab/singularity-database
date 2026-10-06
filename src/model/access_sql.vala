namespace Singularity.Apps.Database {

    public enum ATok {
        WORD,
        IDENT,
        STRING,
        NUMBER,
        OP,
        SPACE
    }

    public class AToken {
        public ATok kind;
        public string text;

        public AToken (ATok kind, string text) {
            this.kind = kind;
            this.text = text;
        }

        public bool is (string w) {
            return kind == ATok.WORD && text.ascii_casecmp (w) == 0;
        }

        public bool op (string o) {
            return kind == ATok.OP && text == o;
        }
    }

    public class AccessSql {
        private const string[] STOP_WORDS = {
            "SELECT", "FROM", "WHERE", "GROUP", "BY", "HAVING", "ORDER", "AND", "OR", "NOT", "ON", "AS", "SET", "INTO",
            "VALUES", "JOIN", "INNER", "LEFT", "RIGHT", "OUTER", "FULL", "CROSS", "UNION", "ALL", "BETWEEN", "IN", "IS",
            "LIKE", "THEN", "ELSE", "WHEN", "CASE", "END", "ASC", "DESC", "TRANSFORM", "PIVOT", "PARAMETERS", "WITH",
            "DISTINCT", "DISTINCTROW", "TOP", "LIMIT", "XOR", "EQV", "IMP", "OWNERACCESS", "OPTION", "DELETE", "UPDATE", "INSERT"
        };

        public static bool parse_us_date (string text, out string iso) {
            iso = "";
            string t = text.strip ();
            double serial;
            if (Script.iso_to_serial (t, out serial)) {
                iso = Script.serial_to_iso (serial);
                return true;
            }
            string date_part = t;
            string time_part = "";
            int sp = t.index_of (" ");
            if (sp > 0) {
                date_part = t.substring (0, sp);
                time_part = t.substring (sp + 1).strip ();
            }
            string[] p = date_part.split ("/");
            if (p.length != 3) p = date_part.split ("-");
            int y = 0, m = 0, d = 0;
            if (p.length == 3) {
                if (!int.try_parse (p[0], out m, null, 10) || !int.try_parse (p[1], out d, null, 10) || !int.try_parse (p[2], out y, null, 10)) {
                    return Script.parse_date_text (t, out serial) && fill_iso (serial, out iso);
                }
                if (p[0].length == 4) {
                    y = int.parse (p[0]);
                    m = int.parse (p[1]);
                    d = int.parse (p[2]);
                }
                if (y < 100) y += y < 30 ? 2000 : 1900;
            } else if (date_part.contains (":")) {
                time_part = t;
                y = 1899;
                m = 12;
                d = 30;
            } else {
                return Script.parse_date_text (t, out serial) && fill_iso (serial, out iso);
            }
            if (m < 1 || m > 12 || d < 1 || d > 31) return false;
            int hh = 0, mi = 0, ss = 0;
            if (time_part != "") {
                string tp = time_part.down ();
                bool pm = tp.has_suffix ("pm") || tp.has_suffix ("p");
                bool am = tp.has_suffix ("am") || tp.has_suffix ("a");
                tp = tp.replace ("pm", "").replace ("am", "").strip ();
                string[] q = tp.split (":");
                if (q.length >= 1) int.try_parse (q[0], out hh, null, 10);
                if (q.length >= 2) int.try_parse (q[1], out mi, null, 10);
                if (q.length >= 3) int.try_parse (q[2], out ss, null, 10);
                if (pm && hh < 12) hh += 12;
                if (am && hh == 12) hh = 0;
            }
            if (y == 1899 && m == 12 && d == 30) {
                iso = "%02d:%02d:%02d".printf (hh, mi, ss);
                return true;
            }
            iso = hh == 0 && mi == 0 && ss == 0 ? "%04d-%02d-%02d".printf (y, m, d) : "%04d-%02d-%02d %02d:%02d:%02d".printf (y, m, d, hh, mi, ss);
            return true;
        }

        private static bool fill_iso (double serial, out string iso) {
            iso = Script.serial_to_iso (serial);
            return true;
        }

        public static Gee.ArrayList<AToken> tokenize (string sql) {
            var list = new Gee.ArrayList<AToken> ();
            int i = 0;
            int n = sql.length;
            while (i < n) {
                char c = sql[i];
                if (c.isspace ()) {
                    int j = i;
                    while (j < n && sql[j].isspace ()) j++;
                    list.add (new AToken (ATok.SPACE, " "));
                    i = j;
                    continue;
                }
                if (c == '-' && i + 1 < n && sql[i + 1] == '-') {
                    while (i < n && sql[i] != '\n') i++;
                    continue;
                }
                if (c == '\'' || c == '"') {
                    char q = c;
                    var sb = new StringBuilder ();
                    int j = i + 1;
                    while (j < n) {
                        if (sql[j] == q) {
                            if (j + 1 < n && sql[j + 1] == q) {
                                sb.append_c (q);
                                j += 2;
                                continue;
                            }
                            break;
                        }
                        sb.append_c (sql[j]);
                        j++;
                    }
                    list.add (new AToken (ATok.STRING, Sql.quote_string (sb.str)));
                    i = int.min (n, j + 1);
                    continue;
                }
                if (c == '#') {
                    int close = sql.index_of_char ('#', i + 1);
                    if (close > i && close - i < 40) {
                        string iso;
                        if (parse_us_date (sql.substring (i + 1, close - i - 1), out iso)) {
                            list.add (new AToken (ATok.STRING, Sql.quote_string (iso)));
                            i = close + 1;
                            continue;
                        }
                    }
                }
                if (c == '[') {
                    int close = sql.index_of_char (']', i + 1);
                    if (close < 0) close = n;
                    list.add (new AToken (ATok.IDENT, sql.substring (i + 1, close - i - 1)));
                    i = int.min (n, close + 1);
                    continue;
                }
                if (c == '`') {
                    int close = sql.index_of_char ('`', i + 1);
                    if (close < 0) close = n;
                    list.add (new AToken (ATok.IDENT, sql.substring (i + 1, close - i - 1)));
                    i = int.min (n, close + 1);
                    continue;
                }
                if (c.isdigit () || (c == '.' && i + 1 < n && sql[i + 1].isdigit ())) {
                    int j = i;
                    while (j < n && (sql[j].isdigit () || sql[j] == '.')) j++;
                    if (j < n && (sql[j] == 'e' || sql[j] == 'E') && j + 1 < n && (sql[j + 1].isdigit () || sql[j + 1] == '-' || sql[j + 1] == '+')) {
                        j += 2;
                        while (j < n && sql[j].isdigit ()) j++;
                    }
                    list.add (new AToken (ATok.NUMBER, sql.substring (i, j - i)));
                    i = j;
                    continue;
                }
                if (c == '&' && i + 1 < n && (sql[i + 1] == 'H' || sql[i + 1] == 'h') && i + 2 < n && sql[i + 2].isxdigit ()) {
                    int j = i + 2;
                    while (j < n && sql[j].isxdigit ()) j++;
                    int64 v = 0;
                    int64.try_parse (sql.substring (i + 2, j - i - 2), out v, null, 16);
                    list.add (new AToken (ATok.NUMBER, v.to_string ()));
                    i = j;
                    continue;
                }
                if (c.isalpha () || c == '_' || (uchar) c >= 0x80) {
                    int j = i;
                    while (j < n && (sql[j].isalnum () || sql[j] == '_' || (uchar) sql[j] >= 0x80)) j++;
                    string w = sql.substring (i, j - i);
                    if (j < n && sql[j] == '$') j++;
                    list.add (new AToken (ATok.WORD, w));
                    i = j;
                    continue;
                }
                string[] two = { "<=", ">=", "<>", "!=", "||", "==" };
                bool done = false;
                foreach (string o in two) {
                    if (i + 1 < n && sql[i] == o[0] && sql[i + 1] == o[1]) {
                        list.add (new AToken (ATok.OP, o == "!=" ? "<>" : (o == "==" ? "=" : o)));
                        i += 2;
                        done = true;
                        break;
                    }
                }
                if (done) continue;
                list.add (new AToken (ATok.OP, c.to_string ()));
                i++;
            }
            return list;
        }

        private static bool is_stop (AToken t) {
            if (t.kind != ATok.WORD) return false;
            foreach (string w in STOP_WORDS) {
                if (t.text.ascii_casecmp (w) == 0) return true;
            }
            return t.text.ascii_casecmp ("Mod") == 0 && false;
        }

        private static int skip_space_left (Gee.ArrayList<AToken> t, int i) {
            while (i >= 0 && t[i].kind == ATok.SPACE) i--;
            return i;
        }

        private static int skip_space_right (Gee.ArrayList<AToken> t, int i) {
            while (i < t.size && t[i].kind == ATok.SPACE) i++;
            return i;
        }

        private static int primary_start (Gee.ArrayList<AToken> t, int i) {
            i = skip_space_left (t, i);
            if (i < 0) return -1;
            if (t[i].op (")")) {
                int depth = 0;
                int k = i;
                while (k >= 0) {
                    if (t[k].op (")")) depth++;
                    else if (t[k].op ("(")) {
                        depth--;
                        if (depth == 0) break;
                    }
                    k--;
                }
                if (k < 0) return -1;
                int before = skip_space_left (t, k - 1);
                if (before >= 0 && (t[before].kind == ATok.WORD && !is_stop (t[before]) || t[before].kind == ATok.IDENT)) return chain_start (t, before);
                return k;
            }
            if (t[i].kind == ATok.WORD && is_stop (t[i])) return -1;
            if (t[i].kind == ATok.OP) return -1;
            return chain_start (t, i);
        }

        private static int chain_start (Gee.ArrayList<AToken> t, int i) {
            int k = i;
            while (k - 2 >= 0 && (t[k - 1].op (".") || t[k - 1].op ("!")) && (t[k - 2].kind == ATok.IDENT || t[k - 2].kind == ATok.WORD)) k -= 2;
            return k;
        }

        private static int primary_end (Gee.ArrayList<AToken> t, int i) {
            i = skip_space_right (t, i);
            if (i >= t.size) return -1;
            if (t[i].op ("(")) return match_paren (t, i);
            if (t[i].kind == ATok.OP && (t[i].text == "-" || t[i].text == "+")) {
                int e = primary_end (t, i + 1);
                return e;
            }
            if (t[i].kind == ATok.WORD && t[i].is ("NOT")) {
                return primary_end (t, i + 1);
            }
            if (t[i].kind == ATok.WORD && is_stop (t[i])) return -1;
            if (t[i].kind == ATok.OP) return -1;
            int k = i;
            while (k + 2 < t.size && (t[k + 1].op (".") || t[k + 1].op ("!")) && (t[k + 2].kind == ATok.IDENT || t[k + 2].kind == ATok.WORD)) k += 2;
            int after = skip_space_right (t, k + 1);
            if ((t[k].kind == ATok.WORD || t[k].kind == ATok.IDENT) && after < t.size && t[after].op ("(")) return match_paren (t, after);
            return k;
        }

        private static int match_paren (Gee.ArrayList<AToken> t, int open) {
            int depth = 0;
            for (int k = open; k < t.size; k++) {
                if (t[k].op ("(")) depth++;
                else if (t[k].op (")")) {
                    depth--;
                    if (depth == 0) return k;
                }
            }
            return t.size - 1;
        }

        private static bool higher_op (AToken t, int level) {
            if (t.kind == ATok.OP) {
                switch (t.text) {
                    case "*":
                    case "/": return level >= 1;
                    case "\\":
                    case "%":
                    case "+":
                    case "-": return level >= 2;
                    case "&":
                    case "||": return level >= 3;
                }
                return false;
            }
            if (t.is ("MOD")) return level >= 2;
            return false;
        }

        private static int operand_left (Gee.ArrayList<AToken> t, int op_index, int level) {
            int start = primary_start (t, op_index - 1);
            if (start < 0) return -1;
            while (true) {
                int prev = skip_space_left (t, start - 1);
                if (prev < 0 || !higher_op (t[prev], level)) break;
                int s2 = primary_start (t, prev - 1);
                if (s2 < 0) {
                    if (t[prev].op ("-") || t[prev].op ("+")) start = prev;
                    break;
                }
                start = s2;
            }
            return start;
        }

        private static int operand_right (Gee.ArrayList<AToken> t, int op_index, int level) {
            int end = primary_end (t, op_index + 1);
            if (end < 0) return -1;
            while (true) {
                int next = skip_space_right (t, end + 1);
                if (next >= t.size || !higher_op (t[next], level)) break;
                int e2 = primary_end (t, next + 1);
                if (e2 < 0) break;
                end = e2;
            }
            return end;
        }

        private static string join (Gee.ArrayList<AToken> t, int a, int b) {
            var sb = new StringBuilder ();
            for (int i = a; i <= b && i < t.size; i++) sb.append (render (t[i]));
            return sb.str.strip ();
        }

        private static string render (AToken t) {
            if (t.kind == ATok.IDENT) return Sql.quote_ident (t.text);
            return t.text;
        }

        private static void replace_range (Gee.ArrayList<AToken> t, int a, int b, string text) {
            for (int i = b; i >= a; i--) t.remove_at (i);
            t.insert (a, new AToken (ATok.WORD, text));
        }

        private static void rewrite_binary (Gee.ArrayList<AToken> t, string match, string function, int level, bool negatable = false) {
            int guard = 0;
            while (guard++ < 10000) {
                int idx = -1;
                for (int i = 0; i < t.size; i++) {
                    if ((t[i].kind == ATok.OP && t[i].text == match) || (t[i].kind == ATok.WORD && t[i].text.ascii_casecmp (match) == 0)) {
                        idx = i;
                        break;
                    }
                }
                if (idx < 0) return;
                bool negate = false;
                int op_start = idx;
                if (negatable) {
                    int p = skip_space_left (t, idx - 1);
                    if (p >= 0 && t[p].is ("NOT")) {
                        negate = true;
                        op_start = p;
                    }
                }
                int ls = operand_left (t, op_start, level);
                int re = operand_right (t, idx, level);
                if (ls < 0 || re < 0) {
                    t[idx] = new AToken (ATok.WORD, match == "&" ? "||" : function);
                    continue;
                }
                string left = join (t, ls, op_start - 1);
                string right = join (t, idx + 1, re);
                string text = "%s(%s, %s)".printf (function, left, right);
                if (negate) text = "NOT " + text;
                replace_range (t, ls, re, text);
            }
        }

        private static void merge_references (Gee.ArrayList<AToken> t) {
            for (int i = 0; i < t.size; i++) {
                bool forms = (t[i].kind == ATok.IDENT || t[i].kind == ATok.WORD) && (t[i].text.ascii_casecmp ("Forms") == 0 || t[i].text.ascii_casecmp ("Reports") == 0 || t[i].text.ascii_casecmp ("TempVars") == 0);
                if (forms && i + 2 < t.size && (t[i + 1].op ("!") || t[i + 1].op ("."))) {
                    var sb = new StringBuilder (t[i].text);
                    int k = i + 1;
                    while (k + 1 < t.size && (t[k].op ("!") || t[k].op (".")) && (t[k + 1].kind == ATok.IDENT || t[k + 1].kind == ATok.WORD)) {
                        sb.append ("!").append (t[k + 1].text);
                        k += 2;
                    }
                    for (int r = k - 1; r > i; r--) t.remove_at (r);
                    t[i] = new AToken (ATok.IDENT, sb.str);
                    continue;
                }
                if (t[i].op ("!") && i > 0 && i + 1 < t.size && (t[i - 1].kind == ATok.IDENT || t[i - 1].kind == ATok.WORD) && (t[i + 1].kind == ATok.IDENT || t[i + 1].kind == ATok.WORD)) {
                    t[i] = new AToken (ATok.OP, ".");
                }
            }
        }

        private static string? renamed_function (string name) {
            switch (name.down ()) {
                case "format": return "acc_format";
                case "instr": return "acc_instr";
                case "replace": return "acc_replace";
                case "round": return "acc_round";
                case "date": return "acc_date";
                case "now": return "acc_now";
                case "time": return "acc_time";
                default: return null;
            }
        }

        private static void simple_words (Gee.ArrayList<AToken> t) {
            for (int i = 0; i < t.size; i++) {
                var tok = t[i];
                if (tok.kind != ATok.WORD) continue;
                int nx = skip_space_right (t, i + 1);
                if (nx < t.size && t[nx].op ("(")) {
                    string? r = renamed_function (tok.text);
                    if (r != null) {
                        tok.text = r;
                        continue;
                    }
                }
                if (tok.is ("DISTINCTROW")) tok.text = "DISTINCT";
                else if (tok.is ("TRUE") || tok.is ("YES") || tok.is ("ON")) {
                    int pv = skip_space_left (t, i - 1);
                    if (!(tok.is ("ON") && (pv < 0 || t[pv].kind == ATok.IDENT || t[pv].kind == ATok.WORD || t[pv].op (")")))) tok.text = "1";
                } else if (tok.is ("FALSE") || tok.is ("NO") || tok.is ("OFF")) tok.text = "0";
                else if (tok.is ("MOD")) {
                    tok.kind = ATok.OP;
                    tok.text = "%";
                } else if (tok.is ("OWNERACCESS") || (tok.is ("WITH") && i + 2 < t.size && t[skip_space_right (t, i + 1)].is ("OWNERACCESS"))) {
                    tok.kind = ATok.SPACE;
                    tok.text = "";
                }
            }
            for (int i = 0; i < t.size; i++) {
                if (t[i].is ("OPTION") && i > 0) {
                    int p = skip_space_left (t, i - 1);
                    if (p >= 0 && t[p].kind == ATok.SPACE) {
                        t[i].kind = ATok.SPACE;
                        t[i].text = "";
                    }
                }
            }
        }

        public static string expression (string access_expr) {
            var t = tokenize (access_expr);
            merge_references (t);
            simple_words (t);
            rewrite_binary (t, "^", "acc_pow", 0);
            rewrite_binary (t, "\\", "acc_intdiv", 1);
            rewrite_binary (t, "&", "acc_cat", 2);
            rewrite_binary (t, "LIKE", "acc_like", 3, true);
            return join (t, 0, t.size - 1);
        }

        public static string expression_from_tokens (Gee.ArrayList<AToken> t) {
            return expression_tokens (t);
        }

        public static string statement (string access_sql) {
            string s = access_sql.strip ();
            while (s.has_suffix (";")) s = s.substring (0, s.length - 1).strip ();
            var t = tokenize (s);
            int first = skip_space_right (t, 0);
            if (first < t.size && t[first].is ("SELECT")) return select_statement (t);
            if (first < t.size && t[first].is ("DELETE")) return delete_statement (t, first);
            if (first < t.size && t[first].is ("UPDATE")) return update_statement (t, first);
            return expression_tokens (t);
        }

        private static string expression_tokens (Gee.ArrayList<AToken> t) {
            merge_references (t);
            simple_words (t);
            rewrite_binary (t, "^", "acc_pow", 0);
            rewrite_binary (t, "\\", "acc_intdiv", 1);
            rewrite_binary (t, "&", "acc_cat", 2);
            rewrite_binary (t, "LIKE", "acc_like", 3, true);
            return join (t, 0, t.size - 1);
        }

        private static int find_top (Gee.ArrayList<AToken> t, string word, int from = 0) {
            int depth = 0;
            for (int i = from; i < t.size; i++) {
                if (t[i].op ("(")) depth++;
                else if (t[i].op (")")) depth--;
                else if (depth == 0 && t[i].is (word)) return i;
            }
            return -1;
        }

        private static string select_statement (Gee.ArrayList<AToken> t) {
            int sel = find_top (t, "SELECT");
            int k = skip_space_right (t, sel + 1);
            if (k < t.size && (t[k].is ("DISTINCT") || t[k].is ("DISTINCTROW"))) k = skip_space_right (t, k + 1);
            string top = "";
            bool percent = false;
            if (k < t.size && t[k].is ("TOP")) {
                int n = skip_space_right (t, k + 1);
                top = t[n].text;
                int end = n;
                int p = skip_space_right (t, n + 1);
                if (p < t.size && t[p].is ("PERCENT")) {
                    percent = true;
                    end = p;
                }
                for (int r = end; r >= k; r--) t.remove_at (r);
            }
            int into = find_top (t, "INTO");
            string target = "";
            if (into > 0) {
                int name = skip_space_right (t, into + 1);
                target = render (t[name]);
                int after = name;
                while (after + 2 < t.size && t[after + 1].op (".")) after += 2;
                for (int r = after; r >= into; r--) t.remove_at (r);
            }
            string body = expression_tokens (t);
            if (top != "") {
                if (percent) {
                    body = "%s LIMIT (SELECT max(1, CAST(((count(*) * %s) + 99.999999) / 100 AS INTEGER)) FROM (%s))".printf (body, top, body);
                } else {
                    body = "%s LIMIT %s".printf (body, top);
                }
            }
            if (target != "") return "CREATE TABLE %s AS %s".printf (target, body);
            return body;
        }

        private static string delete_statement (Gee.ArrayList<AToken> t, int first) {
            int from = find_top (t, "FROM");
            if (from < 0) return expression_tokens (t);
            int where = find_top (t, "WHERE");
            int end_from = where > 0 ? where : t.size;
            string from_clause = join (t, from + 1, end_from - 1);
            var from_tokens = new Gee.ArrayList<AToken> ();
            for (int i = from + 1; i < end_from; i++) from_tokens.add (t[i]);
            bool joined = find_top (from_tokens, "JOIN") >= 0 || find_top (from_tokens, ",") >= 0;
            string where_clause = where > 0 ? expression_tokens (sub (t, where + 1, t.size - 1)) : "";
            if (!joined) {
                return "DELETE FROM %s%s".printf (from_clause, where_clause != "" ? " WHERE " + where_clause : "");
            }
            string target = "";
            int k = skip_space_right (t, first + 1);
            if (k < from && (t[k].kind == ATok.IDENT || t[k].kind == ATok.WORD)) target = render (t[k]);
            if (target == "") {
                int f = skip_space_right (from_tokens, 0);
                target = render (from_tokens[f]);
            }
            string fc = expression_tokens (from_tokens);
            return "DELETE FROM %s WHERE rowid IN (SELECT %s.rowid FROM %s%s)".printf (target, target, fc, where_clause != "" ? " WHERE " + where_clause : "");
        }

        private static Gee.ArrayList<AToken> sub (Gee.ArrayList<AToken> t, int a, int b) {
            var list = new Gee.ArrayList<AToken> ();
            for (int i = a; i <= b && i < t.size; i++) list.add (t[i]);
            return list;
        }

        private static string update_statement (Gee.ArrayList<AToken> t, int first) {
            int set = find_top (t, "SET");
            if (set < 0) return expression_tokens (t);
            var target_tokens = sub (t, first + 1, set - 1);
            int join_at = find_top (target_tokens, "JOIN");
            if (join_at < 0) return expression_tokens (t);
            int where = find_top (t, "WHERE", set);
            var set_tokens = sub (t, set + 1, where > 0 ? where - 1 : t.size - 1);
            string where_clause = where > 0 ? expression_tokens (sub (t, where + 1, t.size - 1)) : "";
            int f = skip_space_right (target_tokens, 0);
            string main = render (target_tokens[f]);
            string rest = expression_tokens (target_tokens);
            var fixed_sets = new StringBuilder ();
            var parts = new Gee.ArrayList<Gee.ArrayList<AToken>> ();
            var cur = new Gee.ArrayList<AToken> ();
            int depth = 0;
            foreach (var tok in set_tokens) {
                if (tok.op ("(")) depth++;
                if (tok.op (")")) depth--;
                if (depth == 0 && tok.op (",")) {
                    parts.add (cur);
                    cur = new Gee.ArrayList<AToken> ();
                    continue;
                }
                cur.add (tok);
            }
            parts.add (cur);
            foreach (var part in parts) {
                int eq = -1;
                for (int k = 0; k < part.size; k++) {
                    if (part[k].op ("=")) {
                        eq = k;
                        break;
                    }
                }
                if (fixed_sets.len > 0) fixed_sets.append (", ");
                if (eq <= 0) {
                    fixed_sets.append (expression_tokens (part));
                    continue;
                }
                string lhs = "";
                for (int k = eq - 1; k >= 0; k--) {
                    if (part[k].kind == ATok.IDENT || part[k].kind == ATok.WORD) {
                        lhs = render (part[k]);
                        break;
                    }
                }
                fixed_sets.append (lhs).append (" = ").append (expression_tokens (sub (part, eq + 1, part.size - 1)));
            }
            int on_at = find_top (target_tokens, "ON");
            int joins = 0;
            for (int i = 0; i < target_tokens.size; i++) if (target_tokens[i].is ("JOIN")) joins++;
            bool paren = false;
            foreach (var tok in target_tokens) if (tok.op ("(")) paren = true;
            if (joins == 1 && on_at > join_at && !paren) {
                int kw = join_at;
                int prev = skip_space_left (target_tokens, join_at - 1);
                if (prev >= 0 && (target_tokens[prev].is ("INNER") || target_tokens[prev].is ("LEFT") || target_tokens[prev].is ("RIGHT") || target_tokens[prev].is ("OUTER"))) kw = prev;
                int prev2 = skip_space_left (target_tokens, kw - 1);
                if (prev2 >= 0 && (target_tokens[prev2].is ("LEFT") || target_tokens[prev2].is ("RIGHT"))) kw = prev2;
                string main_part = expression_tokens (sub (target_tokens, 0, kw - 1));
                string other = expression_tokens (sub (target_tokens, join_at + 1, on_at - 1));
                string cond = expression_tokens (sub (target_tokens, on_at + 1, target_tokens.size - 1));
                string w = where_clause != "" ? "(%s) AND (%s)".printf (cond, where_clause) : cond;
                return "UPDATE %s SET %s FROM %s WHERE %s".printf (main_part, fixed_sets.str, other, w);
            }
            return "UPDATE %s SET %s WHERE %s.rowid IN (SELECT %s.rowid FROM %s%s)".printf (main, fixed_sets.str, main, main, rest, where_clause != "" ? " WHERE " + where_clause : "");
        }
    }
}
