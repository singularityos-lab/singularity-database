namespace Singularity.Apps.Database {

    public class DataExport {
        public static string xml_name (string name) {
            var sb = new StringBuilder ();
            int i = 0;
            unichar c;
            bool first = true;
            while (name.get_next_char (ref i, out c)) {
                bool ok = c.isalnum () || c == '_' || (!first && (c == '-' || c == '.'));
                if (first && c.isdigit ()) sb.append_c ('_');
                sb.append_unichar (ok ? c : '_');
                first = false;
            }
            string r = sb.str;
            return r == "" ? "_" : r;
        }

        private static string esc (string s) {
            return Markup.escape_text (s);
        }

        private static string xsd_type (FieldType? t) {
            if (t == null) return "xsd:string";
            switch (t) {
                case FieldType.AUTONUMBER:
                case FieldType.INTEGER:
                case FieldType.LOOKUP: return "xsd:int";
                case FieldType.NUMBER:
                case FieldType.PERCENT: return "xsd:double";
                case FieldType.CURRENCY: return "xsd:decimal";
                case FieldType.DATE: return "xsd:date";
                case FieldType.DATETIME: return "xsd:dateTime";
                case FieldType.TIME: return "xsd:time";
                case FieldType.BOOLEAN: return "xsd:boolean";
                case FieldType.ATTACHMENT: return "xsd:base64Binary";
                default: return "xsd:string";
            }
        }

        private static string xml_value (DbValue v, FieldType? t) {
            if (v.kind == ValueKind.BLOB) return Base64.encode (v.blob_value.get_data ());
            if (t != null && t == FieldType.BOOLEAN) return v.as_bool () ? "1" : "0";
            if (t != null && t == FieldType.DATETIME) return v.to_string ().replace (" ", "T");
            return v.to_string ();
        }

        public static string to_xml (DataTable dt, string? schema_file = null) {
            string tn = xml_name (dt.name);
            var sb = new StringBuilder ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
            if (schema_file != null) sb.append ("<dataroot xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xsi:noNamespaceSchemaLocation=\"%s\" generated=\"%s\">\n".printf (esc (schema_file), new DateTime.now_local ().format ("%Y-%m-%dT%H:%M:%S")));
            else sb.append ("<dataroot generated=\"%s\">\n".printf (new DateTime.now_local ().format ("%Y-%m-%dT%H:%M:%S")));
            foreach (var r in dt.rows) {
                sb.append ("<%s>\n".printf (tn));
                for (int i = 0; i < dt.columns.length; i++) {
                    var v = r.get (i);
                    if (v.is_null) continue;
                    string cn = xml_name (dt.columns[i]);
                    sb.append ("<%s>%s</%s>\n".printf (cn, esc (xml_value (v, i < dt.types.length ? dt.types[i] : null)), cn));
                }
                sb.append ("</%s>\n".printf (tn));
            }
            sb.append ("</dataroot>\n");
            return sb.str;
        }

        public static string to_xsd (DataTable dt) {
            string tn = xml_name (dt.name);
            var sb = new StringBuilder ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<xsd:schema xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\">\n");
            sb.append ("<xsd:element name=\"dataroot\"><xsd:complexType><xsd:sequence><xsd:element ref=\"%s\" minOccurs=\"0\" maxOccurs=\"unbounded\"/></xsd:sequence><xsd:attribute name=\"generated\" type=\"xsd:dateTime\"/></xsd:complexType></xsd:element>\n".printf (tn));
            sb.append ("<xsd:element name=\"%s\"><xsd:complexType><xsd:sequence>\n".printf (tn));
            for (int i = 0; i < dt.columns.length; i++) {
                sb.append ("<xsd:element name=\"%s\" minOccurs=\"0\" type=\"%s\"/>\n".printf (xml_name (dt.columns[i]), xsd_type (i < dt.types.length ? dt.types[i] : null)));
            }
            sb.append ("</xsd:sequence></xsd:complexType></xsd:element>\n</xsd:schema>\n");
            return sb.str;
        }

        public static Gee.ArrayList<DataTable> from_xml (string text, string fallback_name) throws Error {
            var list = new Gee.ArrayList<DataTable> ();
            var doc = Xml.Parser.read_memory (text, text.length, null, null, Xml.ParserOption.NONET | Xml.ParserOption.NOBLANKS);
            if (doc == null) throw new SchemaError.INVALID (_("The XML file could not be read."));
            var root = doc->get_root_element ();
            var tables = new Gee.HashMap<string, DataTable> ();
            var colmaps = new Gee.HashMap<string, Gee.ArrayList<string>> ();
            var rowmaps = new Gee.HashMap<string, Gee.ArrayList<Gee.HashMap<string, string>>> ();
            for (Xml.Node* rec = root->children; rec != null; rec = rec->next) {
                if (rec->type != Xml.ElementType.ELEMENT_NODE) continue;
                string tn = rec->name;
                if (!tables.has_key (tn)) {
                    tables[tn] = new DataTable (tn);
                    colmaps[tn] = new Gee.ArrayList<string> ();
                    rowmaps[tn] = new Gee.ArrayList<Gee.HashMap<string, string>> ();
                }
                var values = new Gee.HashMap<string, string> ();
                for (Xml.Node* f = rec->children; f != null; f = f->next) {
                    if (f->type != Xml.ElementType.ELEMENT_NODE) continue;
                    if (!colmaps[tn].contains (f->name)) colmaps[tn].add (f->name);
                    values[f->name] = f->get_content ();
                }
                rowmaps[tn].add (values);
            }
            foreach (var e in tables.entries) {
                var dt = e.value;
                dt.columns = colmaps[e.key].to_array ();
                foreach (var m in rowmaps[e.key]) {
                    DbValue[] vals = new DbValue[dt.columns.length];
                    for (int i = 0; i < dt.columns.length; i++) vals[i] = m.has_key (dt.columns[i]) ? new DbValue.text (m[dt.columns[i]]) : new DbValue.null ();
                    dt.add_row ((owned) vals);
                }
                list.add (dt);
            }
            delete doc;
            if (list.size == 0) list.add (new DataTable (fallback_name));
            return list;
        }

        public static string to_html (DataTable dt) {
            var sb = new StringBuilder ("<!DOCTYPE html>\n<html>\n<head>\n<meta charset=\"utf-8\">\n");
            sb.append ("<title>%s</title>\n".printf (esc (dt.name)));
            sb.append ("<style>body{font-family:sans-serif;margin:24px}table{border-collapse:collapse}th,td{border:1px solid #ccc;padding:4px 8px}th{background:#e8edf5;text-align:left}td.n{text-align:right}</style>\n</head>\n<body>\n");
            sb.append ("<table>\n<caption>%s</caption>\n<thead><tr>".printf (esc (dt.name)));
            foreach (string c in dt.columns) sb.append ("<th>%s</th>".printf (esc (c)));
            sb.append ("</tr></thead>\n<tbody>\n");
            foreach (var r in dt.rows) {
                sb.append ("<tr>");
                for (int i = 0; i < dt.columns.length; i++) {
                    var v = r.get (i);
                    sb.append (v.is_number () ? "<td class=\"n\">" : "<td>");
                    sb.append (esc (v.to_string ()));
                    sb.append ("</td>");
                }
                sb.append ("</tr>\n");
            }
            sb.append ("</tbody>\n</table>\n</body>\n</html>\n");
            return sb.str;
        }

        public static string rtf_escape (string s) {
            var sb = new StringBuilder ();
            int i = 0;
            unichar c;
            while (s.get_next_char (ref i, out c)) {
                if (c == '\\' || c == '{' || c == '}') {
                    sb.append_c ('\\');
                    sb.append_unichar (c);
                } else if (c == '\n') {
                    sb.append ("\\line ");
                } else if (c < 128) {
                    sb.append_unichar (c);
                } else if (c <= 0xFFFF) {
                    int16 code = (int16) (uint16) c;
                    sb.append ("\\u%d?".printf (code));
                } else {
                    uint v = c - 0x10000;
                    int16 hi = (int16) (uint16) (0xD800 + (v >> 10));
                    int16 lo = (int16) (uint16) (0xDC00 + (v & 0x3FF));
                    sb.append ("\\u%d?\\u%d?".printf (hi, lo));
                }
            }
            return sb.str;
        }

        public static string to_rtf (DataTable dt) {
            int n = int.max (1, dt.columns.length);
            int width = 9000 / n;
            var sb = new StringBuilder ("{\\rtf1\\ansi\\ansicpg1252\\deff0{\\fonttbl{\\f0\\fswiss Helvetica;}}\\f0\\fs20\n");
            sb.append ("{\\b\\fs28 %s\\par}\n".printf (rtf_escape (dt.name)));
            var row_def = new StringBuilder ("\\trowd\\trgaph60");
            for (int i = 1; i <= n; i++) row_def.append ("\\clbrdrb\\brdrs\\cellx%d".printf (i * width));
            sb.append (row_def.str).append ("\n");
            foreach (string c in dt.columns) sb.append ("\\intbl{\\b %s}\\cell ".printf (rtf_escape (c)));
            sb.append ("\\row\n");
            foreach (var r in dt.rows) {
                sb.append (row_def.str).append ("\n");
                for (int i = 0; i < dt.columns.length; i++) {
                    var v = r.get (i);
                    sb.append ("\\intbl%s %s\\cell ".printf (v.is_number () ? "\\qr" : "\\ql", rtf_escape (v.to_string ())));
                }
                sb.append ("\\row\n");
            }
            sb.append ("}\n");
            return sb.str;
        }

        public static string to_fixed_width (DataTable dt, bool header = true) {
            int[] widths = new int[dt.columns.length];
            for (int i = 0; i < dt.columns.length; i++) widths[i] = header ? dt.columns[i].char_count () : 1;
            foreach (var r in dt.rows) {
                for (int i = 0; i < dt.columns.length; i++) widths[i] = int.max (widths[i], r.get (i).to_string ().replace ("\n", " ").char_count ());
            }
            var sb = new StringBuilder ();
            if (header) {
                for (int i = 0; i < dt.columns.length; i++) sb.append (pad (dt.columns[i], widths[i], false)).append (i < dt.columns.length - 1 ? " " : "");
                sb.append ("\n");
            }
            foreach (var r in dt.rows) {
                for (int i = 0; i < dt.columns.length; i++) {
                    var v = r.get (i);
                    sb.append (pad (v.to_string ().replace ("\n", " "), widths[i], v.is_number ())).append (i < dt.columns.length - 1 ? " " : "");
                }
                sb.append ("\n");
            }
            return sb.str;
        }

        private static string pad (string s, int w, bool right) {
            int n = s.char_count ();
            if (n >= w) return s;
            string sp = string.nfill (w - n, ' ');
            return right ? sp + s : s + sp;
        }

        public static void write (DataTable dt, string path) throws Error {
            string low = path.down ();
            if (low.has_suffix (".xml")) {
                string xsd = path.substring (0, path.length - 4) + ".xsd";
                FileUtils.set_contents (xsd, to_xsd (dt));
                FileUtils.set_contents (path, to_xml (dt, Path.get_basename (xsd)));
            } else if (low.has_suffix (".html") || low.has_suffix (".htm")) {
                FileUtils.set_contents (path, to_html (dt));
            } else if (low.has_suffix (".rtf")) {
                FileUtils.set_contents (path, to_rtf (dt));
            } else if (low.has_suffix (".txt")) {
                FileUtils.set_contents (path, to_fixed_width (dt));
            } else if (low.has_suffix (".json")) {
                FileUtils.set_contents (path, JsonIO.export (dt));
            } else if (low.has_suffix (".xlsx")) {
                var list = new Gee.ArrayList<DataTable> ();
                list.add (dt);
                Xlsx.save (list, path);
            } else if (low.has_suffix (".tsv")) {
                Csv.save (dt, path, '\t');
            } else {
                Csv.save (dt, path, ',');
            }
        }
    }
}
