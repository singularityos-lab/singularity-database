namespace Singularity.Apps.Database {

    public enum STok {
        NUMBER,
        STRING,
        DATE,
        IDENT,
        OP,
        EOL,
        EOF
    }

    public class SToken {
        public STok kind;
        public string text;
        public int line;
        public bool bracketed;
        public double number;
        public bool integer;

        public SToken (STok kind, string text, int line) {
            this.kind = kind;
            this.text = text;
            this.line = line;
        }

        public bool is (string word) {
            return (kind == STok.IDENT && !bracketed || kind == STok.OP) && text.ascii_casecmp (word) == 0;
        }
    }

    public class ScriptLexer {
        public static Gee.ArrayList<SToken> tokenize (string source) throws ScriptError {
            var list = new Gee.ArrayList<SToken> ();
            int i = 0;
            int line = 1;
            int n = source.length;
            while (i < n) {
                char c = source[i];
                if (c == ' ' || c == '\t' || c == '\r') {
                    i++;
                    continue;
                }
                if (c == '_' && i + 1 <= n && (i + 1 == n || source[i + 1] == '\n' || source[i + 1] == '\r' || source[i + 1] == ' ') && (i == 0 || source[i - 1] == ' ' || source[i - 1] == '\t')) {
                    int j = i + 1;
                    while (j < n && (source[j] == ' ' || source[j] == '\t' || source[j] == '\r')) j++;
                    if (j >= n || source[j] == '\n') {
                        i = j + 1;
                        line++;
                        continue;
                    }
                }
                if (c == '\n') {
                    list.add (new SToken (STok.EOL, "\n", line));
                    line++;
                    i++;
                    continue;
                }
                if (c == ':' && !(i + 1 < n && source[i + 1] == '=')) {
                    list.add (new SToken (STok.EOL, ":", line));
                    i++;
                    continue;
                }
                if (c == '\'') {
                    while (i < n && source[i] != '\n') i++;
                    continue;
                }
                if (c == '"') {
                    var sb = new StringBuilder ();
                    i++;
                    bool closed = false;
                    while (i < n) {
                        if (source[i] == '"') {
                            if (i + 1 < n && source[i + 1] == '"') {
                                sb.append_c ('"');
                                i += 2;
                                continue;
                            }
                            closed = true;
                            i++;
                            break;
                        }
                        if (source[i] == '\n') break;
                        sb.append_c (source[i]);
                        i++;
                    }
                    if (!closed) throw new ScriptError.SYNTAX (_("Line %d: a text value is not closed.").printf (line));
                    list.add (new SToken (STok.STRING, sb.str, line));
                    continue;
                }
                if (c == '#' && date_ahead (source, i)) {
                    int close = source.index_of_char ('#', i + 1);
                    list.add (new SToken (STok.DATE, source.substring (i + 1, close - i - 1), line));
                    i = close + 1;
                    continue;
                }
                if (c == '[') {
                    int close = source.index_of_char (']', i + 1);
                    if (close < 0) throw new ScriptError.SYNTAX (_("Line %d: a bracketed name is not closed.").printf (line));
                    var t = new SToken (STok.IDENT, source.substring (i + 1, close - i - 1), line);
                    t.bracketed = true;
                    list.add (t);
                    i = close + 1;
                    continue;
                }
                if (c.isdigit () || (c == '.' && i + 1 < n && source[i + 1].isdigit () && !prev_is_value (list))) {
                    int j = i;
                    bool real = false;
                    while (j < n && (source[j].isdigit () || source[j] == '.')) {
                        if (source[j] == '.') real = true;
                        j++;
                    }
                    if (j < n && (source[j] == 'e' || source[j] == 'E') && j + 1 < n && (source[j + 1].isdigit () || ((source[j + 1] == '-' || source[j + 1] == '+') && j + 2 < n && source[j + 2].isdigit ()))) {
                        real = true;
                        j += 2;
                        while (j < n && source[j].isdigit ()) j++;
                    }
                    string text = source.substring (i, j - i);
                    if (j < n && (source[j] == '#' || source[j] == '!' || source[j] == '@')) {
                        real = true;
                        j++;
                    } else if (j < n && (source[j] == '&' || source[j] == '%') && !(j + 1 < n && source[j + 1].isalnum ())) {
                        j++;
                    }
                    var t = new SToken (STok.NUMBER, text, line);
                    t.number = double.parse (text);
                    t.integer = !real && t.number == Math.floor (t.number) && Math.fabs (t.number) < 9.2e18;
                    list.add (t);
                    i = j;
                    continue;
                }
                if (c == '&' && i + 1 < n && (source[i + 1] == 'H' || source[i + 1] == 'h' || source[i + 1] == 'O' || source[i + 1] == 'o') && i + 2 < n && source[i + 2].isxdigit ()) {
                    bool hex = source[i + 1] == 'H' || source[i + 1] == 'h';
                    int j = i + 2;
                    while (j < n && (hex ? source[j].isxdigit () : (source[j] >= '0' && source[j] <= '7'))) j++;
                    int64 v = 0;
                    int64.try_parse (source.substring (i + 2, j - i - 2), out v, null, hex ? 16 : 8);
                    if (j < n && source[j] == '&') j++;
                    var t = new SToken (STok.NUMBER, v.to_string (), line);
                    t.number = v;
                    t.integer = true;
                    list.add (t);
                    i = j;
                    continue;
                }
                if (c.isalpha () || c == '_' || (uchar) c >= 0x80) {
                    int j = i;
                    while (j < n && (source[j].isalnum () || source[j] == '_' || (uchar) source[j] >= 0x80)) j++;
                    string word = source.substring (i, j - i);
                    if (j < n && (source[j] == '$' || source[j] == '%' || source[j] == '&') && !(j + 1 < n && (source[j + 1].isalnum ()))) j++;
                    if (word.ascii_casecmp ("Rem") == 0 && (j >= n || source[j] == ' ' || source[j] == '\t' || source[j] == '\n')) {
                        while (j < n && source[j] != '\n') j++;
                        i = j;
                        continue;
                    }
                    list.add (new SToken (STok.IDENT, word, line));
                    i = j;
                    continue;
                }
                string[] two = { "<=", ">=", "<>", ":=", "=<", "=>" };
                bool matched = false;
                foreach (string op in two) {
                    if (i + 1 < n && source[i] == op[0] && source[i + 1] == op[1]) {
                        string norm = op == "=<" ? "<=" : (op == "=>" ? ">=" : op);
                        list.add (new SToken (STok.OP, norm, line));
                        i += 2;
                        matched = true;
                        break;
                    }
                }
                if (matched) continue;
                if ("+-*/\\^&=<>().,!;".index_of_char (c) >= 0) {
                    list.add (new SToken (STok.OP, c.to_string (), line));
                    i++;
                    continue;
                }
                throw new ScriptError.SYNTAX (_("Line %d: unexpected character \"%c\".").printf (line, c));
            }
            list.add (new SToken (STok.EOL, "\n", line));
            list.add (new SToken (STok.EOF, "", line));
            return list;
        }

        private static bool prev_is_value (Gee.ArrayList<SToken> list) {
            if (list.size == 0) return false;
            var t = list[list.size - 1];
            return t.kind == STok.IDENT || (t.kind == STok.OP && t.text == ")");
        }

        private static bool date_ahead (string s, int i) {
            int close = s.index_of_char ('#', i + 1);
            if (close < 0 || close - i > 40) return false;
            string inner = s.substring (i + 1, close - i - 1);
            if (inner.contains ("\n") || inner.strip () == "") return false;
            bool digit = false;
            for (int k = 0; k < inner.length; k++) {
                char c = inner[k];
                if (c.isdigit ()) digit = true;
                else if (!(c == '/' || c == '-' || c == ':' || c == ' ' || c == '.' || c.isalpha ())) return false;
            }
            return digit;
        }
    }
}
