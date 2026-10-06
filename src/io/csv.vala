namespace Singularity.Apps.Database {

    public class DataTable {
        public string name;
        public string[] columns = {};
        public FieldType?[] types = {};
        public Gee.ArrayList<Row> rows = new Gee.ArrayList<Row> ();

        public DataTable (string name) {
            this.name = name;
        }

        public void add_row (owned DbValue[] values) {
            rows.add (new Row (rows.size, (owned) values));
        }
    }

    public class Csv {
        public static char detect (string text) {
            char[] candidates = { ',', ';', '\t', '|' };
            char best = ',';
            int best_score = -1;
            string[] lines = text.split ("\n", 20);
            foreach (char c in candidates) {
                int first = -1;
                int score = 0;
                bool consistent = true;
                foreach (string line in lines) {
                    if (line.strip () == "") continue;
                    int n = 0;
                    bool q = false;
                    for (int i = 0; i < line.length; i++) {
                        if (line[i] == '"') q = !q;
                        else if (!q && line[i] == c) n++;
                    }
                    if (first < 0) first = n;
                    else if (n != first) consistent = false;
                    score += n;
                }
                if (first > 0 && consistent) score *= 4;
                if (score > best_score) {
                    best_score = score;
                    best = c;
                }
            }
            return best;
        }

        public static Gee.ArrayList<Gee.ArrayList<string>> parse (string text, char sep) {
            var rows = new Gee.ArrayList<Gee.ArrayList<string>> ();
            var row = new Gee.ArrayList<string> ();
            var field = new StringBuilder ();
            bool quoted = false;
            bool started = false;
            int i = 0;
            int n = text.length;
            if (text.has_prefix ("\xef\xbb\xbf")) i = 3;
            while (i < n) {
                char c = text[i];
                if (quoted) {
                    if (c == '"') {
                        if (i + 1 < n && text[i + 1] == '"') {
                            field.append_c ('"');
                            i += 2;
                            continue;
                        }
                        quoted = false;
                        i++;
                        continue;
                    }
                    field.append_c (c);
                    i++;
                    continue;
                }
                if (c == '"' && field.len == 0) {
                    quoted = true;
                    started = true;
                    i++;
                    continue;
                }
                if (c == sep) {
                    row.add (field.str);
                    field.truncate ();
                    started = true;
                    i++;
                    continue;
                }
                if (c == '\r' || c == '\n') {
                    if (started || field.len > 0 || row.size > 0) {
                        row.add (field.str);
                        rows.add (row);
                    }
                    row = new Gee.ArrayList<string> ();
                    field.truncate ();
                    started = false;
                    if (c == '\r' && i + 1 < n && text[i + 1] == '\n') i++;
                    i++;
                    continue;
                }
                field.append_c (c);
                started = true;
                i++;
            }
            if (started || field.len > 0 || row.size > 0) {
                row.add (field.str);
                rows.add (row);
            }
            return rows;
        }

        public static string read_text (string path) throws Error {
            string text;
            FileUtils.get_contents (path, out text);
            if (text.has_prefix ("\xff\xfe") || text.has_prefix ("\xfe\xff")) {
                uint8[] raw;
                FileUtils.get_data (path, out raw);
                text = convert ((string) raw, raw.length, "UTF-8", "UTF-16");
            } else if (!text.validate ()) {
                text = convert (text, -1, "UTF-8", "WINDOWS-1252");
            }
            return text;
        }

        public static DataTable load (string path, char sep = 0, bool header = true) throws Error {
            string text = read_text (path);
            string name = Path.get_basename (path);
            int dot = name.last_index_of (".");
            if (dot > 0) name = name.substring (0, dot);
            if (sep == 0) sep = path.down ().has_suffix (".tsv") || path.down ().has_suffix (".tab") ? '\t' : detect (text);
            return from_text (text, name, sep, header);
        }

        public static DataTable from_text (string text, string name, char sep, bool header) {
            var dt = new DataTable (name);
            var rows = parse (text, sep);
            int width = 0;
            foreach (var r in rows) width = int.max (width, r.size);
            string[] cols = {};
            int start = 0;
            if (header && rows.size > 0) {
                var h = rows[0];
                var seen = new Gee.HashSet<string> ();
                for (int c = 0; c < width; c++) {
                    string n = c < h.size ? h[c].strip () : "";
                    if (n == "") n = _("Field %d").printf (c + 1);
                    string base_n = n;
                    int k = 2;
                    while (!seen.add (n.casefold ())) n = "%s %d".printf (base_n, k++);
                    cols += n;
                }
                start = 1;
            } else {
                for (int c = 0; c < width; c++) cols += _("Field %d").printf (c + 1);
            }
            dt.columns = cols;
            dt.types = new FieldType?[width];
            for (int r = start; r < rows.size; r++) {
                var src = rows[r];
                bool empty = true;
                foreach (string s in src) {
                    if (s != "") empty = false;
                }
                if (empty) continue;
                DbValue[] vals = new DbValue[width];
                for (int c = 0; c < width; c++) vals[c] = c < src.size && src[c] != "" ? new DbValue.text (src[c]) : new DbValue.null ();
                dt.add_row ((owned) vals);
            }
            return dt;
        }

        public static string quote (string s, char sep) {
            if (s.index_of_char (sep) >= 0 || s.contains ("\"") || s.contains ("\n") || s.contains ("\r") || s != s.strip ()) {
                return "\"" + s.replace ("\"", "\"\"") + "\"";
            }
            return s;
        }

        public static string export (DataTable dt, char sep, bool header = true) {
            var sb = new StringBuilder ();
            if (header) {
                for (int c = 0; c < dt.columns.length; c++) {
                    if (c > 0) sb.append_c (sep);
                    sb.append (quote (dt.columns[c], sep));
                }
                sb.append ("\r\n");
            }
            foreach (var r in dt.rows) {
                for (int c = 0; c < dt.columns.length; c++) {
                    if (c > 0) sb.append_c (sep);
                    var v = r.get (c);
                    string s = v.kind == ValueKind.BLOB ? "" : v.to_string ();
                    sb.append (quote (s, sep));
                }
                sb.append ("\r\n");
            }
            return sb.str;
        }

        public static void save (DataTable dt, string path, char sep = ',') throws Error {
            FileUtils.set_contents (path, export (dt, sep));
        }
    }
}
