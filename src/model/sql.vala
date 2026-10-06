namespace Singularity.Apps.Database {

    public enum TokenKind {
        KEYWORD,
        FUNCTION,
        IDENTIFIER,
        QUOTED_IDENTIFIER,
        STRING,
        NUMBER,
        BLOB,
        OPERATOR,
        PUNCTUATION,
        PARAMETER,
        COMMENT,
        WHITESPACE
    }

    public class Token {
        public TokenKind kind;
        public int start;
        public int end;
        public string text;

        public Token (TokenKind kind, int start, int end, string text) {
            this.kind = kind;
            this.start = start;
            this.end = end;
            this.text = text;
        }
    }

    public class Sql {
        public const string[] KEYWORDS = {
            "ABORT", "ACTION", "ADD", "AFTER", "ALL", "ALTER", "ALWAYS", "ANALYZE", "AND", "AS", "ASC", "ATTACH",
            "AUTOINCREMENT", "BEFORE", "BEGIN", "BETWEEN", "BY", "CASCADE", "CASE", "CAST", "CHECK", "COLLATE",
            "COLUMN", "COMMIT", "CONFLICT", "CONSTRAINT", "CREATE", "CROSS", "CURRENT", "CURRENT_DATE",
            "CURRENT_TIME", "CURRENT_TIMESTAMP", "DATABASE", "DEFAULT", "DEFERRABLE", "DEFERRED", "DELETE", "DESC",
            "DETACH", "DISTINCT", "DO", "DROP", "EACH", "ELSE", "END", "ESCAPE", "EXCEPT", "EXCLUDE", "EXCLUSIVE",
            "EXISTS", "EXPLAIN", "FAIL", "FILTER", "FIRST", "FOLLOWING", "FOR", "FOREIGN", "FROM", "FULL",
            "GENERATED", "GLOB", "GROUP", "GROUPS", "HAVING", "IF", "IGNORE", "IMMEDIATE", "IN", "INDEX", "INDEXED",
            "INITIALLY", "INNER", "INSERT", "INSTEAD", "INTERSECT", "INTO", "IS", "ISNULL", "JOIN", "KEY", "LAST",
            "LEFT", "LIKE", "LIMIT", "MATCH", "MATERIALIZED", "NATURAL", "NO", "NOT", "NOTHING", "NOTNULL", "NULL",
            "NULLS", "OF", "OFFSET", "ON", "OR", "ORDER", "OTHERS", "OUTER", "OVER", "PARTITION", "PLAN", "PRAGMA",
            "PRECEDING", "PRIMARY", "QUERY", "RAISE", "RANGE", "RECURSIVE", "REFERENCES", "REGEXP", "REINDEX",
            "RELEASE", "RENAME", "REPLACE", "RESTRICT", "RETURNING", "RIGHT", "ROLLBACK", "ROW", "ROWS",
            "SAVEPOINT", "SELECT", "SET", "STRICT", "TABLE", "TEMP", "TEMPORARY", "THEN", "TIES", "TO",
            "TRANSACTION", "TRIGGER", "UNBOUNDED", "UNION", "UNIQUE", "UPDATE", "USING", "VACUUM", "VALUES", "VIEW",
            "VIRTUAL", "WHEN", "WHERE", "WINDOW", "WITH", "WITHOUT", "INTEGER", "TEXT", "REAL", "BLOB", "NUMERIC",
            "TRUE", "FALSE"
        };

        public const string[] FUNCTIONS = {
            "ABS", "AVG", "CHANGES", "CHAR", "COALESCE", "COUNT", "DATE", "DATETIME", "GLOB", "GROUP_CONCAT",
            "HEX", "IFNULL", "IIF", "INSTR", "JULIANDAY", "LENGTH", "LOWER", "LTRIM", "MAX", "MIN", "NULLIF",
            "PRINTF", "FORMAT", "QUOTE", "RANDOM", "REPLACE", "ROUND", "RTRIM", "SIGN", "STRFTIME", "SUBSTR",
            "SUBSTRING", "SUM", "TIME", "TOTAL", "TRIM", "TYPEOF", "UNIXEPOCH", "UPPER", "ROW_NUMBER", "RANK",
            "DENSE_RANK", "LAG", "LEAD", "FIRST_VALUE", "LAST_VALUE", "NTILE", "JSON", "JSON_EXTRACT",
            "JSON_OBJECT", "JSON_ARRAY", "JSON_GROUP_ARRAY", "LIKE", "CEIL", "FLOOR", "POWER", "SQRT", "MOD",
            "LOG", "EXP", "PI", "CONCAT", "CONCAT_WS", "LAST_INSERT_ROWID", "RANDOMBLOB", "ZEROBLOB", "UNICODE",
            "SOUNDEX", "STRING_AGG", "OCTET_LENGTH", "TIMEDIFF"
        };

        private static Gee.HashSet<string>? keyword_set;
        private static Gee.HashSet<string>? function_set;

        public static bool is_keyword (string word) {
            if (keyword_set == null) {
                keyword_set = new Gee.HashSet<string> ();
                foreach (string k in KEYWORDS) keyword_set.add (k);
            }
            return keyword_set.contains (word.up ());
        }

        public static bool is_function (string word) {
            if (function_set == null) {
                function_set = new Gee.HashSet<string> ();
                foreach (string k in FUNCTIONS) function_set.add (k);
            }
            return function_set.contains (word.up ());
        }

        public static string quote_ident (string name) {
            return "\"" + name.replace ("\"", "\"\"") + "\"";
        }

        public static string quote_string (string s) {
            return "'" + s.replace ("'", "''") + "'";
        }

        public static string unquote_ident (string s) {
            if (s.length >= 2) {
                char a = s[0], b = s[s.length - 1];
                if ((a == '"' && b == '"') || (a == '`' && b == '`')) return s.substring (1, s.length - 2).replace ("%c%c".printf (a, a), "%c".printf (a));
                if (a == '[' && b == ']') return s.substring (1, s.length - 2);
            }
            return s;
        }

        public static string unquote_string (string s) {
            if (s.length >= 2 && s[0] == '\'' && s[s.length - 1] == '\'') return s.substring (1, s.length - 2).replace ("''", "'");
            return s;
        }

        private static bool ident_start (char c) {
            return c.isalpha () || c == '_' || (uchar) c >= 0x80;
        }

        private static bool ident_char (char c) {
            return c.isalnum () || c == '_' || c == '$' || (uchar) c >= 0x80;
        }

        public static Gee.ArrayList<Token> tokenize (string sql, bool keep_space = false) {
            var list = new Gee.ArrayList<Token> ();
            int i = 0, n = sql.length;
            while (i < n) {
                char c = sql[i];
                int start = i;
                TokenKind kind;
                if (c.isspace ()) {
                    while (i < n && sql[i].isspace ()) i++;
                    kind = TokenKind.WHITESPACE;
                } else if (c == '-' && i + 1 < n && sql[i + 1] == '-') {
                    while (i < n && sql[i] != '\n') i++;
                    kind = TokenKind.COMMENT;
                } else if (c == '/' && i + 1 < n && sql[i + 1] == '*') {
                    i += 2;
                    while (i < n && !(sql[i] == '*' && i + 1 < n && sql[i + 1] == '/')) i++;
                    i = int.min (n, i + 2);
                    kind = TokenKind.COMMENT;
                } else if (c == '\'') {
                    i++;
                    while (i < n) {
                        if (sql[i] == '\'') {
                            if (i + 1 < n && sql[i + 1] == '\'') {
                                i += 2;
                                continue;
                            }
                            i++;
                            break;
                        }
                        i++;
                    }
                    kind = TokenKind.STRING;
                } else if ((c == 'x' || c == 'X') && i + 1 < n && sql[i + 1] == '\'') {
                    i += 2;
                    while (i < n && sql[i] != '\'') i++;
                    i = int.min (n, i + 1);
                    kind = TokenKind.BLOB;
                } else if (c == '"' || c == '`') {
                    char q = c;
                    i++;
                    while (i < n) {
                        if (sql[i] == q) {
                            if (i + 1 < n && sql[i + 1] == q) {
                                i += 2;
                                continue;
                            }
                            i++;
                            break;
                        }
                        i++;
                    }
                    kind = TokenKind.QUOTED_IDENTIFIER;
                } else if (c == '[') {
                    while (i < n && sql[i] != ']') i++;
                    i = int.min (n, i + 1);
                    kind = TokenKind.QUOTED_IDENTIFIER;
                } else if (c.isdigit () || (c == '.' && i + 1 < n && sql[i + 1].isdigit ())) {
                    if (c == '0' && i + 1 < n && (sql[i + 1] == 'x' || sql[i + 1] == 'X')) {
                        i += 2;
                        while (i < n && sql[i].isxdigit ()) i++;
                    } else {
                        while (i < n && (sql[i].isdigit () || sql[i] == '.' || sql[i] == '_')) i++;
                        if (i < n && (sql[i] == 'e' || sql[i] == 'E')) {
                            int save = i;
                            i++;
                            if (i < n && (sql[i] == '+' || sql[i] == '-')) i++;
                            if (i < n && sql[i].isdigit ()) {
                                while (i < n && sql[i].isdigit ()) i++;
                            } else {
                                i = save;
                            }
                        }
                    }
                    kind = TokenKind.NUMBER;
                } else if (ident_start (c)) {
                    while (i < n && ident_char (sql[i])) i++;
                    string word = sql.substring (start, i - start);
                    int j = i;
                    while (j < n && sql[j].isspace ()) j++;
                    bool call = j < n && sql[j] == '(';
                    if (call && is_function (word)) kind = TokenKind.FUNCTION;
                    else if (is_keyword (word)) kind = TokenKind.KEYWORD;
                    else if (call) kind = TokenKind.FUNCTION;
                    else kind = TokenKind.IDENTIFIER;
                } else if (c == '?' || c == ':' || c == '@' || c == '$') {
                    i++;
                    while (i < n && ident_char (sql[i])) i++;
                    kind = TokenKind.PARAMETER;
                } else if (c == '(' || c == ')' || c == ',' || c == ';' || c == '.') {
                    i++;
                    kind = TokenKind.PUNCTUATION;
                } else {
                    string[] ops = { "||", "<=", ">=", "<>", "!=", "==", "<<", ">>", "->>" , "->" };
                    bool matched = false;
                    foreach (string op in ops) {
                        if (sql.substring (i).has_prefix (op)) {
                            i += op.length;
                            matched = true;
                            break;
                        }
                    }
                    if (!matched) i++;
                    kind = TokenKind.OPERATOR;
                }
                if (kind != TokenKind.WHITESPACE || keep_space) list.add (new Token (kind, start, i, sql.substring (start, i - start)));
            }
            return list;
        }

        public static Gee.ArrayList<string> split_statements (string script) {
            var result = new Gee.ArrayList<string> ();
            var tokens = tokenize (script, true);
            var sb = new StringBuilder ();
            int depth = 0;
            bool in_trigger = false;
            string first = "";
            string second = "";
            int words = 0;
            foreach (var t in tokens) {
                if (t.kind == TokenKind.KEYWORD || t.kind == TokenKind.IDENTIFIER) {
                    string u = t.text.up ();
                    if (words == 0) first = u;
                    else if (words == 1 || (words == 2 && (second == "TEMP" || second == "TEMPORARY"))) second = u;
                    words++;
                    if (first == "CREATE" && u == "TRIGGER") in_trigger = true;
                    if (in_trigger && u == "BEGIN") depth++;
                    if (in_trigger && u == "END" && depth > 0) depth--;
                }
                if (t.kind == TokenKind.PUNCTUATION && t.text == ";" && depth == 0) {
                    string stmt = sb.str.strip ();
                    if (stmt != "" && !only_comments (stmt)) result.add (stmt);
                    sb.truncate ();
                    words = 0;
                    first = "";
                    second = "";
                    in_trigger = false;
                    continue;
                }
                sb.append (t.text);
            }
            string tail = sb.str.strip ();
            if (tail != "" && !only_comments (tail)) result.add (tail);
            return result;
        }

        private static bool only_comments (string s) {
            foreach (var t in tokenize (s)) {
                if (t.kind != TokenKind.COMMENT) return false;
            }
            return true;
        }

        public static bool is_read_only (string sql) {
            var toks = tokenize (sql);
            foreach (var t in toks) {
                if (t.kind == TokenKind.COMMENT) continue;
                string u = t.text.up ();
                if (u == "SELECT" || u == "VALUES") return true;
                if (u == "WITH") {
                    foreach (var k in toks) {
                        string ku = k.text.up ();
                        if (k.kind == TokenKind.KEYWORD && (ku == "INSERT" || ku == "UPDATE" || ku == "DELETE" || ku == "REPLACE")) return false;
                    }
                    return true;
                }
                if (u == "EXPLAIN" || u == "PRAGMA") return true;
                return false;
            }
            return false;
        }

        public static string format (string sql) {
            string[] breakers = { "SELECT", "FROM", "WHERE", "GROUP", "HAVING", "ORDER", "LIMIT", "UNION", "INNER", "LEFT", "RIGHT", "FULL", "CROSS", "JOIN", "SET", "VALUES", "INSERT", "UPDATE", "DELETE" };
            var sb = new StringBuilder ();
            string prev = "";
            TokenKind prev_kind = TokenKind.WHITESPACE;
            foreach (var t in tokenize (sql)) {
                string text = t.kind == TokenKind.KEYWORD ? t.text.up () : t.text;
                bool brk = false;
                if (t.kind == TokenKind.KEYWORD) {
                    foreach (string b in breakers) {
                        if (text == b) brk = true;
                    }
                    if (text == "JOIN" && (prev == "INNER" || prev == "LEFT" || prev == "RIGHT" || prev == "FULL" || prev == "CROSS" || prev == "OUTER")) brk = false;
                    if (text == "OUTER") brk = false;
                }
                if (sb.len > 0) {
                    if (brk) sb.append ("\n");
                    else if (t.text == "(" && (prev_kind == TokenKind.FUNCTION || prev_kind == TokenKind.IDENTIFIER || prev_kind == TokenKind.QUOTED_IDENTIFIER)) {
                    } else if (!(t.text == "," || t.text == ")" || t.text == "." || prev == "(" || prev == "." || t.text == ";")) sb.append (" ");
                }
                sb.append (text);
                prev = text;
                prev_kind = t.kind;
            }
            return sb.str;
        }
    }
}
