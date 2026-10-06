namespace Singularity.Apps.Database {

    public class Xlsx {
        private const string NS_REL = "http://schemas.openxmlformats.org/officeDocument/2006/relationships";

        private ZipReader zip;
        private string[] shared = {};
        private bool[] date_styles = {};
        private bool[] time_only_styles = {};
        private bool date1904;

        private static Xml.Doc* parse (string? text) {
            if (text == null) return null;
            return Xml.Parser.read_memory (text, text.length, null, null, Xml.ParserOption.NONET | Xml.ParserOption.NOBLANKS | Xml.ParserOption.HUGE);
        }

        private static Xml.Node* child (Xml.Node* n, string name) {
            if (n == null) return null;
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type == Xml.ElementType.ELEMENT_NODE && c->name == name) return c;
            }
            return null;
        }

        private static string attr (Xml.Node* n, string name, string def = "") {
            if (n == null) return def;
            string? v = n->get_prop (name);
            return v ?? def;
        }

        private static string text_of (Xml.Node* n) {
            if (n == null) return "";
            string? c = n->get_content ();
            return c ?? "";
        }

        private static string resolve (string base_dir, string target) {
            if (target.has_prefix ("/")) return target.substring (1);
            string[] parts = (base_dir + "/" + target).split ("/");
            var stack = new Gee.ArrayList<string> ();
            foreach (string p in parts) {
                if (p == "" || p == ".") continue;
                if (p == "..") {
                    if (stack.size > 0) stack.remove_at (stack.size - 1);
                    continue;
                }
                stack.add (p);
            }
            return string.joinv ("/", stack.to_array ());
        }

        private Gee.HashMap<string, string> rels (string path) throws Error {
            var map = new Gee.HashMap<string, string> ();
            string dir = Path.get_dirname (path);
            string rel = (dir == "." ? "" : dir + "/") + "_rels/" + Path.get_basename (path) + ".rels";
            var doc = parse (zip.read_text (rel));
            if (doc == null) return map;
            for (Xml.Node* c = doc->get_root_element ()->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                map[attr (c, "Id")] = resolve (dir == "." ? "" : dir, attr (c, "Target"));
            }
            delete doc;
            return map;
        }

        public static bool is_date_format (string code) {
            string c = code.down ();
            var sb = new StringBuilder ();
            bool q = false;
            for (int i = 0; i < c.length; i++) {
                char ch = c[i];
                if (ch == '"') {
                    q = !q;
                    continue;
                }
                if (q) continue;
                if (ch == '\\' || ch == '_') {
                    i++;
                    continue;
                }
                if (ch == '[') {
                    int close = c.index_of_char (']', i);
                    if (close > i) {
                        string inner = c.substring (i + 1, close - i - 1);
                        if (inner == "h" || inner == "hh" || inner == "m" || inner == "mm" || inner == "s" || inner == "ss") sb.append ("h");
                        i = close;
                        continue;
                    }
                }
                sb.append_c (ch);
            }
            string s = sb.str;
            if (s == "general" || s.contains ("0") || s.contains ("#")) return false;
            return s.contains ("d") || s.contains ("y") || s.contains ("m") || s.contains ("h") || s.contains ("s");
        }

        private static bool is_time_only (string code) {
            string c = code.down ();
            return is_date_format (code) && !c.contains ("d") && !c.contains ("y") && (c.contains ("h") || c.contains ("s"));
        }

        private void read_styles () throws Error {
            var doc = parse (zip.read_text ("xl/styles.xml"));
            if (doc == null) return;
            var formats = new Gee.HashMap<int, string> ();
            var nf = child (doc->get_root_element (), "numFmts");
            for (Xml.Node* n = nf != null ? nf->children : null; n != null; n = n->next) {
                if (n->type == Xml.ElementType.ELEMENT_NODE) formats[int.parse (attr (n, "numFmtId"))] = attr (n, "formatCode");
            }
            bool[] dates = {};
            bool[] times = {};
            var xfs = child (doc->get_root_element (), "cellXfs");
            for (Xml.Node* xf = xfs != null ? xfs->children : null; xf != null; xf = xf->next) {
                if (xf->type != Xml.ElementType.ELEMENT_NODE) continue;
                int id = int.parse (attr (xf, "numFmtId", "0"));
                bool d = false, t = false;
                if (formats.has_key (id)) {
                    d = is_date_format (formats[id]);
                    t = is_time_only (formats[id]);
                } else {
                    d = (id >= 14 && id <= 22) || (id >= 45 && id <= 47) || (id >= 27 && id <= 36) || (id >= 50 && id <= 58);
                    t = (id >= 18 && id <= 21) || (id >= 45 && id <= 47);
                }
                dates += d;
                times += t;
            }
            date_styles = dates;
            time_only_styles = times;
            delete doc;
        }

        private void read_shared () throws Error {
            var doc = parse (zip.read_text ("xl/sharedStrings.xml"));
            if (doc == null) return;
            string[] list = {};
            for (Xml.Node* si = doc->get_root_element ()->children; si != null; si = si->next) {
                if (si->type != Xml.ElementType.ELEMENT_NODE || si->name != "si") continue;
                list += rich_text (si);
            }
            shared = list;
            delete doc;
        }

        private static string rich_text (Xml.Node* si) {
            var sb = new StringBuilder ();
            for (Xml.Node* c = si->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                if (c->name == "t") sb.append (text_of (c));
                else if (c->name == "r") sb.append (text_of (child (c, "t")));
            }
            return sb.str;
        }

        public static void parse_ref (string r, out int row, out int col) {
            row = 0;
            col = 0;
            int i = 0;
            while (i < r.length && r[i].isalpha ()) {
                col = col * 26 + (r[i].toupper () - 'A' + 1);
                i++;
            }
            col -= 1;
            row = int.parse (r.substring (i)) - 1;
        }

        public static string column_name (int col) {
            var sb = new StringBuilder ();
            int c = col + 1;
            while (c > 0) {
                int m = (c - 1) % 26;
                sb.prepend_c ((char) ('A' + m));
                c = (c - 1) / 26;
            }
            return sb.str;
        }

        public static string serial_to_iso (double serial, bool with_time, bool date1904 = false) {
            double days = serial + (date1904 ? 1462 : 0);
            int64 whole = (int64) Math.floor (days);
            double frac = days - whole;
            var d = new DateTime.utc (1899, 12, 30, 0, 0, 0).add_days ((int) whole);
            int secs = (int) Math.round (frac * 86400);
            if (secs >= 86400) {
                d = d.add_days (1);
                secs -= 86400;
            }
            string date = d.format ("%Y-%m-%d");
            if (!with_time) return date;
            return "%s %02d:%02d:%02d".printf (date, secs / 3600, (secs / 60) % 60, secs % 60);
        }

        public static double iso_to_serial (string iso) {
            if (iso.length < 10) return 0;
            int y = int.parse (iso.substring (0, 4)), m = int.parse (iso.substring (5, 2)), d = int.parse (iso.substring (8, 2));
            var dt = new DateTime.utc (y, m, d, 0, 0, 0);
            if (dt == null) return 0;
            var base_d = new DateTime.utc (1899, 12, 30, 0, 0, 0);
            double days = Math.round (dt.difference (base_d) / (double) TimeSpan.DAY);
            if (iso.length >= 19) {
                int hh = int.parse (iso.substring (11, 2)), mm = int.parse (iso.substring (14, 2)), ss = int.parse (iso.substring (17, 2));
                days += (hh * 3600 + mm * 60 + ss) / 86400.0;
            } else if (iso.length >= 16) {
                int hh = int.parse (iso.substring (11, 2)), mm = int.parse (iso.substring (14, 2));
                days += (hh * 3600 + mm * 60) / 86400.0;
            }
            return days;
        }

        public static Gee.ArrayList<DataTable> load (string path, bool header = true) throws Error {
            uint8[] data;
            FileUtils.get_data (path, out data);
            var x = new Xlsx ();
            return x.read (data, header);
        }

        public Gee.ArrayList<DataTable> read (uint8[] data, bool header) throws Error {
            zip = new ZipReader (data);
            var result = new Gee.ArrayList<DataTable> ();
            var doc = parse (zip.read_text ("xl/workbook.xml"));
            if (doc == null) throw new ZipError.FORMAT (_("This is not an Excel workbook."));
            var wb_rels = rels ("xl/workbook.xml");
            read_shared ();
            read_styles ();
            var root = doc->get_root_element ();
            var pr = child (root, "workbookPr");
            if (pr != null) date1904 = attr (pr, "date1904") == "1" || attr (pr, "date1904") == "true";
            var names = new Gee.ArrayList<string> ();
            var targets = new Gee.ArrayList<string> ();
            var sheets_node = child (root, "sheets");
            for (Xml.Node* s = sheets_node != null ? sheets_node->children : null; s != null; s = s->next) {
                if (s->type != Xml.ElementType.ELEMENT_NODE) continue;
                string rid = s->get_ns_prop ("id", NS_REL) ?? attr (s, "id");
                names.add (attr (s, "name"));
                targets.add (wb_rels[rid] ?? "");
            }
            delete doc;
            for (int i = 0; i < names.size; i++) {
                if (targets[i] == "") continue;
                var dt = read_sheet (names[i], targets[i], header);
                if (dt != null) result.add (dt);
            }
            return result;
        }

        private DataTable? read_sheet (string name, string path, bool header) throws Error {
            var doc = parse (zip.read_text (path));
            if (doc == null) return null;
            var cells = new Gee.TreeMap<int, Gee.HashMap<int, DbValue>> ();
            int width = 0;
            var sd = child (doc->get_root_element (), "sheetData");
            for (Xml.Node* row = sd != null ? sd->children : null; row != null; row = row->next) {
                if (row->type != Xml.ElementType.ELEMENT_NODE) continue;
                int r = int.parse (attr (row, "r", "0")) - 1;
                int next_col = 0;
                for (Xml.Node* c = row->children; c != null; c = c->next) {
                    if (c->type != Xml.ElementType.ELEMENT_NODE || c->name != "c") continue;
                    int rr = r, cc = next_col;
                    string ref_s = attr (c, "r");
                    if (ref_s != "") parse_ref (ref_s, out rr, out cc);
                    next_col = cc + 1;
                    if (rr < 0) rr = r;
                    var v = cell_value (c);
                    if (v.is_null) continue;
                    if (!cells.has_key (rr)) cells[rr] = new Gee.HashMap<int, DbValue> ();
                    cells[rr][cc] = v;
                    width = int.max (width, cc + 1);
                }
            }
            delete doc;
            var dt = new DataTable (name);
            if (cells.size == 0) {
                dt.columns = {};
                return dt;
            }
            int first = cells.ascending_keys.first ();
            string[] cols = {};
            var seen = new Gee.HashSet<string> ();
            for (int c = 0; c < width; c++) {
                string n = "";
                if (header && cells[first].has_key (c)) n = cells[first][c].to_string ().strip ();
                if (n == "") n = header ? _("Field %d").printf (c + 1) : _("Field %d").printf (c + 1);
                string b = n;
                int k = 2;
                while (!seen.add (n.casefold ())) n = "%s %d".printf (b, k++);
                cols += n;
            }
            dt.columns = cols;
            dt.types = new FieldType?[width];
            foreach (var e in cells.entries) {
                if (header && e.key == first) continue;
                DbValue[] vals = new DbValue[width];
                for (int c = 0; c < width; c++) vals[c] = e.value.has_key (c) ? e.value[c] : new DbValue.null ();
                dt.add_row ((owned) vals);
            }
            return dt;
        }

        private DbValue cell_value (Xml.Node* c) {
            string t = attr (c, "t", "n");
            int s = int.parse (attr (c, "s", "0"));
            var vnode = child (c, "v");
            string v = text_of (vnode);
            switch (t) {
                case "s":
                    int k = int.parse (v);
                    return new DbValue.text (k >= 0 && k < shared.length ? shared[k] : "");
                case "inlineStr":
                    var is_node = child (c, "is");
                    return new DbValue.text (is_node != null ? rich_text (is_node) : "");
                case "str":
                    return vnode != null ? new DbValue.text (v) : new DbValue.null ();
                case "b":
                    return new DbValue.bool (v == "1" || v == "true");
                case "e":
                    return new DbValue.null ();
                case "d":
                    return new DbValue.text (v.replace ("T", " ").replace ("Z", ""));
                default:
                    if (vnode == null || v == "") return new DbValue.null ();
                    double d = double.parse (v);
                    if (s > 0 && s < date_styles.length && date_styles[s]) {
                        if (time_only_styles[s]) {
                            int secs = (int) Math.round ((d - Math.floor (d)) * 86400);
                            return new DbValue.text ("%02d:%02d:%02d".printf (secs / 3600 % 24, (secs / 60) % 60, secs % 60));
                        }
                        return new DbValue.text (serial_to_iso (d, d != Math.floor (d), date1904));
                    }
                    if (d == Math.floor (d) && Math.fabs (d) < 1e15) return new DbValue.int ((int64) d);
                    return new DbValue.real (d);
            }
        }

        public static string esc (string s) {
            var sb = new StringBuilder ();
            unichar c;
            int i = 0;
            while (s.get_next_char (ref i, out c)) {
                switch (c) {
                    case '&': sb.append ("&amp;"); break;
                    case '<': sb.append ("&lt;"); break;
                    case '>': sb.append ("&gt;"); break;
                    case '"': sb.append ("&quot;"); break;
                    default:
                        if (c < 0x20 && c != '\t' && c != '\n' && c != '\r') continue;
                        sb.append_unichar (c);
                        break;
                }
            }
            return sb.str;
        }

        private static string sheet_name (string name, Gee.HashSet<string> used) {
            var sb = new StringBuilder ();
            unichar c;
            int i = 0;
            while (name.get_next_char (ref i, out c)) {
                if (c == '[' || c == ']' || c == '*' || c == '?' || c == '/' || c == '\\' || c == ':') continue;
                sb.append_unichar (c);
            }
            string n = sb.str.strip ();
            if (n == "") n = "Sheet";
            if (n.char_count () > 31) n = n.substring (0, n.index_of_nth_char (31));
            string b = n;
            int k = 2;
            while (!used.add (n.casefold ())) {
                string suffix = " %d".printf (k++);
                int keep = int.min (b.char_count (), 31 - suffix.length);
                n = b.substring (0, b.index_of_nth_char (keep)) + suffix;
            }
            return n;
        }

        public static void save (Gee.List<DataTable> tables, string path) throws Error {
            FileUtils.set_data (path, build (tables));
        }

        public static uint8[] build (Gee.List<DataTable> tables) throws Error {
            var zip = new ZipWriter ();
            var strings = new Gee.ArrayList<string> ();
            var index = new Gee.HashMap<string, int> ();
            var used = new Gee.HashSet<string> ();
            string[] names = {};
            string[] sheets = {};
            foreach (var dt in tables) {
                names += sheet_name (dt.name, used);
                sheets += sheet_xml (dt, strings, index);
            }
            var ct = new StringBuilder ("""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/><Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/><Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/><Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>""");
            for (int i = 0; i < sheets.length; i++) ct.append ("<Override PartName=\"/xl/worksheets/sheet%d.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>".printf (i + 1));
            ct.append ("</Types>");
            zip.add_text ("[Content_Types].xml", ct.str);
            zip.add_text ("_rels/.rels", """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/></Relationships>""");
            var now = new DateTime.now_utc ().format ("%Y-%m-%dT%H:%M:%SZ");
            zip.add_text ("docProps/core.xml", """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><dcterms:created xsi:type="dcterms:W3CDTF">%s</dcterms:created><dcterms:modified xsi:type="dcterms:W3CDTF">%s</dcterms:modified></cp:coreProperties>""".printf (now, now));
            zip.add_text ("docProps/app.xml", """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"><Application>Singularity Database</Application></Properties>""");
            var wb = new StringBuilder ("""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><workbookPr/><bookViews><workbookView/></bookViews><sheets>""");
            for (int i = 0; i < names.length; i++) wb.append ("<sheet name=\"%s\" sheetId=\"%d\" r:id=\"rId%d\"/>".printf (esc (names[i]), i + 1, i + 1));
            wb.append ("</sheets><definedNames>");
            for (int i = 0; i < names.length; i++) {
                var dt = tables[i];
                if (dt.columns.length == 0) continue;
                wb.append ("<definedName name=\"_xlnm._FilterDatabase\" localSheetId=\"%d\" hidden=\"1\">'%s'!$A$1:$%s$%d</definedName>".printf (i, esc (names[i].replace ("'", "''")), column_name (dt.columns.length - 1), dt.rows.size + 1));
            }
            wb.append ("</definedNames></workbook>");
            zip.add_text ("xl/workbook.xml", wb.str);
            var rels = new StringBuilder ("""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">""");
            for (int i = 0; i < names.length; i++) rels.append ("<Relationship Id=\"rId%d\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet%d.xml\"/>".printf (i + 1, i + 1));
            rels.append ("<Relationship Id=\"rId%d\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>".printf (names.length + 1));
            rels.append ("<Relationship Id=\"rId%d\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings\" Target=\"sharedStrings.xml\"/>".printf (names.length + 2));
            rels.append ("</Relationships>");
            zip.add_text ("xl/_rels/workbook.xml.rels", rels.str);
            zip.add_text ("xl/styles.xml", """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><numFmts count="3"><numFmt numFmtId="164" formatCode="yyyy\-mm\-dd"/><numFmt numFmtId="165" formatCode="yyyy\-mm\-dd\ hh:mm:ss"/><numFmt numFmtId="166" formatCode="hh:mm:ss"/></numFmts><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts><fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FFDCE6F2"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="7"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/><xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/><xf numFmtId="165" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/><xf numFmtId="166" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/><xf numFmtId="4" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/><xf numFmtId="10" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>""");
            var ss = new StringBuilder ("""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
""");
            ss.append ("<sst xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" count=\"%d\" uniqueCount=\"%d\">".printf (strings.size, strings.size));
            foreach (string s in strings) {
                bool keep = s != s.strip () || s.contains ("\n");
                ss.append (keep ? "<si><t xml:space=\"preserve\">%s</t></si>".printf (esc (s)) : "<si><t>%s</t></si>".printf (esc (s)));
            }
            ss.append ("</sst>");
            zip.add_text ("xl/sharedStrings.xml", ss.str);
            for (int i = 0; i < sheets.length; i++) zip.add_text ("xl/worksheets/sheet%d.xml".printf (i + 1), sheets[i]);
            return zip.finish ();
        }

        private static int intern (string s, Gee.ArrayList<string> strings, Gee.HashMap<string, int> index) {
            if (index.has_key (s)) return index[s];
            strings.add (s);
            index[s] = strings.size - 1;
            return strings.size - 1;
        }

        private static string sheet_xml (DataTable dt, Gee.ArrayList<string> strings, Gee.HashMap<string, int> index) {
            var sb = new StringBuilder ("""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">""");
            int ncol = dt.columns.length;
            sb.append ("<sheetViews><sheetView workbookViewId=\"0\"><pane ySplit=\"1\" topLeftCell=\"A2\" activePane=\"bottomLeft\" state=\"frozen\"/></sheetView></sheetViews>");
            if (ncol > 0) {
                sb.append ("<cols>");
                for (int c = 0; c < ncol; c++) {
                    int w = dt.columns[c].char_count () + 2;
                    int limit = int.min (dt.rows.size, 200);
                    for (int r = 0; r < limit; r++) w = int.max (w, dt.rows[r].get (c).to_string ().char_count () + 2);
                    sb.append ("<col min=\"%d\" max=\"%d\" width=\"%d\" customWidth=\"1\"/>".printf (c + 1, c + 1, w.clamp (8, 60)));
                }
                sb.append ("</cols>");
            }
            sb.append ("<sheetData>");
            if (ncol > 0) {
                sb.append ("<row r=\"1\">");
                for (int c = 0; c < ncol; c++) sb.append ("<c r=\"%s1\" t=\"s\" s=\"1\"><v>%d</v></c>".printf (column_name (c), intern (dt.columns[c], strings, index)));
                sb.append ("</row>");
            }
            int rn = 2;
            foreach (var row in dt.rows) {
                sb.append ("<row r=\"%d\">".printf (rn));
                for (int c = 0; c < ncol; c++) {
                    var v = row.get (c);
                    if (v.is_null || v.kind == ValueKind.BLOB) continue;
                    string cref = column_name (c) + rn.to_string ();
                    FieldType? ft = c < dt.types.length ? dt.types[c] : null;
                    if (ft != null && ft == FieldType.BOOLEAN) {
                        sb.append ("<c r=\"%s\" t=\"b\"><v>%d</v></c>".printf (cref, v.as_bool () ? 1 : 0));
                        continue;
                    }
                    if (ft != null && (ft == FieldType.DATE || ft == FieldType.DATETIME) && v.kind == ValueKind.TEXT) {
                        string iso = v.text_value;
                        string parsed = "";
                        if (iso.length >= 10 && Codec.parse_datetime (iso, out parsed)) {
                            double serial = iso_to_serial (parsed);
                            bool has_time = ft == FieldType.DATETIME && parsed.substring (11) != "00:00:00";
                            sb.append ("<c r=\"%s\" s=\"%d\"><v>%s</v></c>".printf (cref, has_time ? 3 : 2, DbValue.format_real (serial)));
                            continue;
                        }
                    }
                    if (ft != null && ft == FieldType.TIME && v.kind == ValueKind.TEXT) {
                        string ti;
                        if (Codec.parse_time (v.text_value, out ti)) {
                            int hh = int.parse (ti.substring (0, 2)), mm = int.parse (ti.substring (3, 2)), ss = int.parse (ti.substring (6, 2));
                            sb.append ("<c r=\"%s\" s=\"4\"><v>%s</v></c>".printf (cref, DbValue.format_real ((hh * 3600 + mm * 60 + ss) / 86400.0)));
                            continue;
                        }
                    }
                    if (v.is_number ()) {
                        int style = 0;
                        if (ft != null && ft == FieldType.CURRENCY) style = 5;
                        if (ft != null && ft == FieldType.PERCENT) style = 6;
                        string num = v.kind == ValueKind.INTEGER ? v.int_value.to_string () : DbValue.format_real (v.real_value);
                        sb.append (style > 0 ? "<c r=\"%s\" s=\"%d\"><v>%s</v></c>".printf (cref, style, num) : "<c r=\"%s\"><v>%s</v></c>".printf (cref, num));
                        continue;
                    }
                    sb.append ("<c r=\"%s\" t=\"s\"><v>%d</v></c>".printf (cref, intern (v.to_string (), strings, index)));
                }
                sb.append ("</row>");
                rn++;
            }
            sb.append ("</sheetData>");
            if (ncol > 0) sb.append ("<autoFilter ref=\"A1:%s%d\"/>".printf (column_name (ncol - 1), dt.rows.size + 1));
            sb.append ("</worksheet>");
            return sb.str;
        }
    }
}
