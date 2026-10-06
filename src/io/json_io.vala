namespace Singularity.Apps.Database {

    public class JsonIO {
        private static void add_value (Json.Builder b, DbValue v, FieldType? t) {
            switch (v.kind) {
                case ValueKind.NULL:
                    b.add_null_value ();
                    break;
                case ValueKind.INTEGER:
                    if (t != null && t == FieldType.BOOLEAN) b.add_boolean_value (v.int_value != 0);
                    else b.add_int_value (v.int_value);
                    break;
                case ValueKind.REAL:
                    b.add_double_value (v.real_value);
                    break;
                case ValueKind.BLOB:
                    b.add_string_value (Base64.encode (v.blob_value.get_data ()));
                    break;
                default:
                    b.add_string_value (v.text_value);
                    break;
            }
        }

        private static void table_array (Json.Builder b, DataTable dt) {
            b.begin_array ();
            foreach (var r in dt.rows) {
                b.begin_object ();
                for (int c = 0; c < dt.columns.length; c++) {
                    b.set_member_name (dt.columns[c]);
                    add_value (b, r.get (c), c < dt.types.length ? dt.types[c] : null);
                }
                b.end_object ();
            }
            b.end_array ();
        }

        public static string export (DataTable dt, bool pretty = true) {
            var b = new Json.Builder ();
            table_array (b, dt);
            var gen = new Json.Generator ();
            gen.pretty = pretty;
            gen.indent = 2;
            gen.set_root (b.get_root ());
            return gen.to_data (null);
        }

        public static string export_many (Gee.List<DataTable> tables, bool pretty = true) {
            var b = new Json.Builder ();
            b.begin_object ();
            foreach (var dt in tables) {
                b.set_member_name (dt.name);
                table_array (b, dt);
            }
            b.end_object ();
            var gen = new Json.Generator ();
            gen.pretty = pretty;
            gen.indent = 2;
            gen.set_root (b.get_root ());
            return gen.to_data (null);
        }

        private static DbValue node_value (Json.Node n) {
            switch (n.get_node_type ()) {
                case Json.NodeType.NULL:
                    return new DbValue.null ();
                case Json.NodeType.VALUE:
                    var t = n.get_value_type ();
                    if (t == typeof (int64)) return new DbValue.int (n.get_int ());
                    if (t == typeof (double)) return new DbValue.real (n.get_double ());
                    if (t == typeof (bool)) return new DbValue.bool (n.get_boolean ());
                    return new DbValue.text (n.get_string () ?? "");
                default:
                    return new DbValue.text (Json.to_string (n, false));
            }
        }

        private static DataTable table_from_array (string name, Json.Array arr) {
            var dt = new DataTable (name);
            var cols = new Gee.ArrayList<string> ();
            var seen = new Gee.HashSet<string> ();
            arr.foreach_element ((a, i, n) => {
                if (n.get_node_type () != Json.NodeType.OBJECT) return;
                foreach (string m in n.get_object ().get_members ()) {
                    if (seen.add (m)) cols.add (m);
                }
            });
            bool scalars = cols.size == 0 && arr.get_length () > 0;
            if (scalars) cols.add (_("Value"));
            dt.columns = cols.to_array ();
            dt.types = new FieldType?[cols.size];
            var bool_cols = new bool[cols.size];
            for (int c = 0; c < cols.size; c++) bool_cols[c] = true;
            arr.foreach_element ((a, i, n) => {
                DbValue[] vals = new DbValue[cols.size];
                if (scalars) {
                    vals[0] = node_value (n);
                } else if (n.get_node_type () == Json.NodeType.OBJECT) {
                    var o = n.get_object ();
                    for (int c = 0; c < cols.size; c++) {
                        if (o.has_member (cols[c])) {
                            var mn = o.get_member (cols[c]);
                            vals[c] = node_value (mn);
                            if (!(mn.get_node_type () == Json.NodeType.VALUE && mn.get_value_type () == typeof (bool)) && mn.get_node_type () != Json.NodeType.NULL) bool_cols[c] = false;
                        } else {
                            vals[c] = new DbValue.null ();
                        }
                    }
                } else {
                    return;
                }
                dt.add_row ((owned) vals);
            });
            for (int c = 0; c < cols.size; c++) {
                if (bool_cols[c] && dt.rows.size > 0 && !scalars) {
                    bool any = false;
                    foreach (var r in dt.rows) {
                        if (!r.get (c).is_null) any = true;
                    }
                    if (any) dt.types[c] = FieldType.BOOLEAN;
                }
            }
            return dt;
        }

        public static Gee.ArrayList<DataTable> load (string path) throws Error {
            string text;
            FileUtils.get_contents (path, out text);
            string name = Path.get_basename (path);
            int dot = name.last_index_of (".");
            if (dot > 0) name = name.substring (0, dot);
            return parse (text, name);
        }

        public static Gee.ArrayList<DataTable> parse (string text, string name) throws Error {
            var list = new Gee.ArrayList<DataTable> ();
            var p = new Json.Parser ();
            string t = text.strip ();
            if (t.has_prefix ("{") && t.contains ("}\n{") || (t.has_prefix ("{") && t.split ("\n").length > 1 && !t.has_suffix ("}\n}") && ndjson (t))) {
                var arr = new Json.Array ();
                foreach (string line in t.split ("\n")) {
                    if (line.strip () == "") continue;
                    var lp = new Json.Parser ();
                    lp.load_from_data (line);
                    arr.add_element (lp.get_root ().copy ());
                }
                list.add (table_from_array (name, arr));
                return list;
            }
            p.load_from_data (text);
            var root = p.get_root ();
            if (root.get_node_type () == Json.NodeType.ARRAY) {
                list.add (table_from_array (name, root.get_array ()));
                return list;
            }
            if (root.get_node_type () == Json.NodeType.OBJECT) {
                var o = root.get_object ();
                bool all_arrays = o.get_size () > 0;
                foreach (string m in o.get_members ()) {
                    if (o.get_member (m).get_node_type () != Json.NodeType.ARRAY) all_arrays = false;
                }
                if (all_arrays) {
                    foreach (string m in o.get_members ()) list.add (table_from_array (m, o.get_array_member (m)));
                    return list;
                }
                var arr = new Json.Array ();
                arr.add_element (root.copy ());
                list.add (table_from_array (name, arr));
                return list;
            }
            throw new SchemaError.INVALID (_("The JSON file does not contain records."));
        }

        private static bool ndjson (string t) {
            foreach (string line in t.split ("\n")) {
                string l = line.strip ();
                if (l == "") continue;
                if (!l.has_prefix ("{") || !l.has_suffix ("}")) return false;
            }
            return true;
        }
    }
}
