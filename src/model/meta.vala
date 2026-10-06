namespace Singularity.Apps.Database {

    public class ColumnCheck {
        public string[] choices = {};
        public int max_length;
        public string other = "";
    }

    public class Span {
        public int a;
        public int b;

        public Span (int a, int b) {
            this.a = a;
            this.b = b;
        }
    }

    public class SchemaParser {
        public static Gee.HashMap<string, ColumnCheck> column_checks (string create_sql) {
            var map = new Gee.HashMap<string, ColumnCheck> ();
            var toks = Sql.tokenize (create_sql);
            int open = -1;
            for (int i = 0; i < toks.size; i++) {
                if (toks[i].text == "(") {
                    open = i;
                    break;
                }
            }
            if (open < 0) return map;
            int depth = 0;
            int start = open + 1;
            for (int i = open + 1; i < toks.size; i++) {
                var t = toks[i];
                if (t.text == "(") depth++;
                else if (t.text == ")") {
                    if (depth == 0) {
                        column_segment (toks, start, i, map);
                        break;
                    }
                    depth--;
                } else if (t.text == "," && depth == 0) {
                    column_segment (toks, start, i, map);
                    start = i + 1;
                }
            }
            return map;
        }

        private static void column_segment (Gee.ArrayList<Token> toks, int a, int b, Gee.HashMap<string, ColumnCheck> map) {
            if (a >= b) return;
            var first = toks[a];
            if (first.kind == TokenKind.KEYWORD) {
                string u = first.text.up ();
                if (u == "CONSTRAINT" || u == "PRIMARY" || u == "FOREIGN" || u == "UNIQUE" || u == "CHECK") return;
            }
            string col = Sql.unquote_ident (first.text);
            var check = new ColumnCheck ();
            string[] others = {};
            for (int i = a + 1; i < b; i++) {
                if (toks[i].kind != TokenKind.KEYWORD || toks[i].text.up () != "CHECK") continue;
                if (i + 1 >= b || toks[i + 1].text != "(") continue;
                int depth = 0;
                int end = -1;
                for (int j = i + 1; j < b; j++) {
                    if (toks[j].text == "(") depth++;
                    else if (toks[j].text == ")") {
                        depth--;
                        if (depth == 0) {
                            end = j;
                            break;
                        }
                    }
                }
                if (end < 0) continue;
                foreach (var part in split_and (toks, i + 2, end)) {
                    if (!parse_part (toks, part.a, part.b, col, check)) others += join (toks, part.a, part.b);
                }
                i = end;
            }
            check.other = string.joinv (" AND ", others);
            if (check.choices.length > 0 || check.max_length > 0 || check.other != "") map[col.casefold ()] = check;
        }

        private static Gee.ArrayList<Span> split_and (Gee.ArrayList<Token> toks, int a, int b) {
            var parts = new Gee.ArrayList<Span> ();
            int depth = 0;
            int start = a;
            for (int i = a; i < b; i++) {
                if (toks[i].text == "(") depth++;
                else if (toks[i].text == ")") depth--;
                else if (depth == 0 && toks[i].kind == TokenKind.KEYWORD && toks[i].text.up () == "AND") {
                    bool between = false;
                    for (int k = start; k < i; k++) {
                        if (toks[k].text.up () == "BETWEEN") between = true;
                    }
                    if (!between) {
                        parts.add (new Span (start, i));
                        start = i + 1;
                    }
                }
            }
            parts.add (new Span (start, b));
            var cleaned = new Gee.ArrayList<Span> ();
            foreach (var p in parts) {
                int s = p.a, e = p.b;
                while (s < e && toks[s].text == "(" && toks[e - 1].text == ")" && matching (toks, s) == e - 1) {
                    s++;
                    e--;
                }
                cleaned.add (new Span (s, e));
            }
            return cleaned;
        }

        private static int matching (Gee.ArrayList<Token> toks, int open) {
            int depth = 0;
            for (int i = open; i < toks.size; i++) {
                if (toks[i].text == "(") depth++;
                else if (toks[i].text == ")") {
                    depth--;
                    if (depth == 0) return i;
                }
            }
            return -1;
        }

        private static string join (Gee.ArrayList<Token> toks, int a, int b) {
            var sb = new StringBuilder ();
            for (int i = a; i < b; i++) {
                var t = toks[i];
                if (sb.len > 0 && t.text != ")" && t.text != "," && toks[i - 1].text != "(" && !(t.text == "(" && (toks[i - 1].kind == TokenKind.FUNCTION || toks[i - 1].kind == TokenKind.IDENTIFIER))) sb.append (" ");
                sb.append (t.text);
            }
            return sb.str;
        }

        private static bool parse_part (Gee.ArrayList<Token> toks, int a, int b, string col, ColumnCheck check) {
            int n = b - a;
            if (n >= 4 && Sql.unquote_ident (toks[a].text).casefold () == col.casefold () && toks[a + 1].text.up () == "IN" && toks[a + 2].text == "(" && toks[b - 1].text == ")") {
                string[] items = {};
                bool ints = true;
                for (int i = a + 3; i < b - 1; i++) {
                    var t = toks[i];
                    if (t.text == ",") continue;
                    if (t.kind == TokenKind.STRING) {
                        items += Sql.unquote_string (t.text);
                        ints = false;
                    } else if (t.kind == TokenKind.NUMBER) {
                        items += t.text;
                    } else {
                        return false;
                    }
                }
                if (ints && items.length == 2 && ((items[0] == "0" && items[1] == "1") || (items[0] == "1" && items[1] == "0"))) return true;
                check.choices = items;
                return true;
            }
            if (n == 6 && toks[a].text.down () == "length" && toks[a + 1].text == "(" && Sql.unquote_ident (toks[a + 2].text).casefold () == col.casefold () && toks[a + 3].text == ")" && toks[a + 4].text == "<=" && toks[a + 5].kind == TokenKind.NUMBER) {
                check.max_length = int.parse (toks[a + 5].text);
                return true;
            }
            return false;
        }

        public static string generated_expression (string create_sql, string column) {
            var toks = Sql.tokenize (create_sql);
            for (int i = 0; i + 1 < toks.size; i++) {
                if (Sql.unquote_ident (toks[i].text).casefold () != column.casefold ()) continue;
                if (i > 0 && toks[i - 1].text != "(" && toks[i - 1].text != ",") continue;
                for (int j = i + 1; j < toks.size; j++) {
                    if (toks[j].text == ",") break;
                    if (toks[j].text.up () == "AS" && j + 1 < toks.size && toks[j + 1].text == "(") {
                        int depth = 0;
                        for (int k = j + 1; k < toks.size; k++) {
                            if (toks[k].text == "(") depth++;
                            else if (toks[k].text == ")") {
                                depth--;
                                if (depth == 0) return create_sql.substring (toks[j + 1].end, toks[k].start - toks[j + 1].end).strip ();
                            }
                        }
                    }
                    if (toks[j].text == "(") {
                        int depth = 0;
                        for (int k = j; k < toks.size; k++) {
                            if (toks[k].text == "(") depth++;
                            else if (toks[k].text == ")") {
                                depth--;
                                if (depth == 0) {
                                    j = k;
                                    break;
                                }
                            }
                        }
                    }
                }
            }
            return "";
        }

        public static string default_to_input (string sql_default) {
            string d = sql_default.strip ();
            string low = d.down ().replace (" ", "");
            if (low.has_prefix ("(") && low.has_suffix (")")) low = low.substring (1, low.length - 2);
            if (low == "datetime('now','localtime')" || low == "current_timestamp" || low == "datetime('now')") return "Now()";
            if (low == "date('now','localtime')" || low == "current_date" || low == "date('now')") return "Date()";
            if (low == "time('now','localtime')" || low == "current_time" || low == "time('now')") return "Time()";
            if (d.length >= 2 && d[0] == '\'' && d[d.length - 1] == '\'') return Sql.unquote_string (d);
            double num;
            if (double.try_parse (d, out num) || d.up () == "NULL") return d;
            return "(" + d + ")";
        }
    }

    public class Meta {
        public static bool needs_meta (TableDef def) {
            if (def.description != "" || def.validation_rule != "" || def.validation_text != "") return true;
            foreach (var f in def.fields) {
                if (f.description != "" || f.decimals >= 0 || f.field_type == FieldType.LOOKUP && f.lookup_display != "") return true;
                if (f.is_calculated () || f.multi_value || f.format != "" || f.input_mask != "" || f.caption != "" || f.validation_rule != "" || f.validation_text != "" || f.rich_text) return true;
            }
            return false;
        }

        public static string table_json (TableDef def) {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("description").add_string_value (def.description);
            if (def.validation_rule != "") b.set_member_name ("validation-rule").add_string_value (def.validation_rule);
            if (def.validation_text != "") b.set_member_name ("validation-text").add_string_value (def.validation_text);
            b.set_member_name ("fields").begin_object ();
            foreach (var f in def.fields) {
                b.set_member_name (f.name).begin_object ();
                b.set_member_name ("type").add_string_value (f.field_type.id ());
                if (f.description != "") b.set_member_name ("description").add_string_value (f.description);
                if (f.decimals >= 0) b.set_member_name ("decimals").add_int_value (f.decimals);
                if (f.lookup_display != "") b.set_member_name ("display").add_string_value (f.lookup_display);
                if (f.field_type == FieldType.LOOKUP) {
                    b.set_member_name ("lookup-table").add_string_value (f.lookup_table);
                    b.set_member_name ("lookup-field").add_string_value (f.lookup_field);
                }
                if (f.is_calculated ()) b.set_member_name ("expression").add_string_value (f.expression);
                if (f.multi_value) {
                    b.set_member_name ("multi-value").add_boolean_value (true);
                    if (f.field_type == FieldType.CHOICE) {
                        b.set_member_name ("choices").begin_array ();
                        foreach (string c in f.choices) b.add_string_value (c);
                        b.end_array ();
                    }
                }
                if (f.format != "") b.set_member_name ("format").add_string_value (f.format);
                if (f.input_mask != "") b.set_member_name ("input-mask").add_string_value (f.input_mask);
                if (f.caption != "") b.set_member_name ("caption").add_string_value (f.caption);
                if (f.validation_rule != "") b.set_member_name ("validation-rule").add_string_value (f.validation_rule);
                if (f.validation_text != "") b.set_member_name ("validation-text").add_string_value (f.validation_text);
                if (f.rich_text) b.set_member_name ("rich-text").add_boolean_value (true);
                b.end_object ();
            }
            b.end_object ();
            b.set_member_name ("order").begin_array ();
            foreach (var f in def.fields) b.add_string_value (f.name);
            b.end_array ();
            b.end_object ();
            return Json.to_string (b.get_root (), false);
        }

        public static void apply_table (TableDef def, string json) {
            try {
                var p = new Json.Parser ();
                p.load_from_data (json);
                var root = p.get_root ().get_object ();
                if (root.has_member ("description")) def.description = root.get_string_member ("description");
                def.validation_rule = root.get_string_member_with_default ("validation-rule", "");
                def.validation_text = root.get_string_member_with_default ("validation-text", "");
                if (!root.has_member ("fields")) return;
                var fields = root.get_object_member ("fields");
                foreach (var f in def.fields) {
                    if (!fields.has_member (f.name)) continue;
                    var o = fields.get_object_member (f.name);
                    var t = FieldType.from_id (o.get_string_member_with_default ("type", f.field_type.id ()));
                    if (compatible (f.field_type, t)) f.field_type = t;
                    f.description = o.get_string_member_with_default ("description", "");
                    f.decimals = (int) o.get_int_member_with_default ("decimals", -1);
                    f.lookup_display = o.get_string_member_with_default ("display", "");
                    if (t == FieldType.LOOKUP) {
                        f.lookup_table = o.get_string_member_with_default ("lookup-table", "");
                        f.lookup_field = o.get_string_member_with_default ("lookup-field", "");
                    }
                    if (o.has_member ("expression")) f.expression = o.get_string_member ("expression");
                    f.multi_value = o.get_boolean_member_with_default ("multi-value", false);
                    if (f.multi_value && (t == FieldType.CHOICE || t == FieldType.LOOKUP)) {
                        f.field_type = t;
                        if (o.has_member ("choices")) f.choices = Meta.string_array (o, "choices");
                    }
                    f.format = o.get_string_member_with_default ("format", "");
                    f.input_mask = o.get_string_member_with_default ("input-mask", "");
                    f.caption = o.get_string_member_with_default ("caption", "");
                    string vr = o.get_string_member_with_default ("validation-rule", "");
                    if (vr != "") {
                        f.validation_rule = vr;
                        f.validation = "";
                    }
                    f.validation_text = o.get_string_member_with_default ("validation-text", "");
                    f.rich_text = o.get_boolean_member_with_default ("rich-text", false);
                }
            } catch (Error e) {
            }
        }

        private static bool compatible (FieldType declared, FieldType meta) {
            if (declared == meta) return true;
            if (meta == FieldType.LOOKUP) return declared == FieldType.INTEGER || declared.is_text () || declared == FieldType.NUMBER;
            if (meta == FieldType.AUTONUMBER) return declared == FieldType.AUTONUMBER || declared == FieldType.INTEGER;
            if (declared == FieldType.CHOICE) return meta == FieldType.CHOICE;
            if (meta.is_text ()) return declared.is_text ();
            return false;
        }

        public static Json.Object? parse_object (string? json) {
            if (json == null) return null;
            try {
                var p = new Json.Parser ();
                p.load_from_data (json);
                var root = p.get_root ();
                if (root == null || root.get_node_type () != Json.NodeType.OBJECT) return null;
                return root.get_object ();
            } catch (Error e) {
                return null;
            }
        }

        public static string[] string_array (Json.Object o, string member) {
            string[] list = {};
            if (!o.has_member (member)) return list;
            var arr = o.get_array_member (member);
            for (uint i = 0; i < arr.get_length (); i++) list += arr.get_string_element (i);
            return list;
        }
    }

    public class SqlFunctions {
        private static string arg_text (Sqlite.Value v) {
            return v.to_type () == Sqlite.NULL ? "" : v.to_text ();
        }

        private static void date_part (Sqlite.Context ctx, Sqlite.Value[] args, int start, int len) {
            if (args.length < 1 || args[0].to_type () == Sqlite.NULL) {
                ctx.result_null ();
                return;
            }
            string s = arg_text (args[0]);
            if (s.length < start + len) {
                ctx.result_null ();
                return;
            }
            int v;
            if (!Codec.decimal_int (s.substring (start, len), out v)) {
                ctx.result_null ();
                return;
            }
            ctx.result_int (v);
        }

        public static void register (Sqlite.Database db) {
            int flags = Sqlite.UTF8 | 0x800;
            db.create_function ("year", 1, flags, null, (ctx, args) => date_part (ctx, args, 0, 4), null, null);
            db.create_function ("month", 1, flags, null, (ctx, args) => date_part (ctx, args, 5, 2), null, null);
            db.create_function ("day", 1, flags, null, (ctx, args) => date_part (ctx, args, 8, 2), null, null);
            db.create_function ("hour", 1, flags, null, (ctx, args) => {
                string s = arg_text (args[0]);
                int p = s.length >= 19 ? 11 : 0;
                if (s.length < p + 2) {
                    ctx.result_null ();
                    return;
                }
                ctx.result_int (int.parse (s.substring (p, 2)));
            }, null, null);
            db.create_function ("ucase", 1, flags, null, (ctx, args) => {
                if (args[0].to_type () == Sqlite.NULL) ctx.result_null ();
                else ctx.result_text (arg_text (args[0]).up ());
            }, null, null);
            db.create_function ("lcase", 1, flags, null, (ctx, args) => {
                if (args[0].to_type () == Sqlite.NULL) ctx.result_null ();
                else ctx.result_text (arg_text (args[0]).down ());
            }, null, null);
            db.create_function ("len", 1, flags, null, (ctx, args) => {
                if (args[0].to_type () == Sqlite.NULL) ctx.result_null ();
                else ctx.result_int (arg_text (args[0]).char_count ());
            }, null, null);
            db.create_function ("left", 2, flags, null, (ctx, args) => {
                if (args[0].to_type () == Sqlite.NULL) {
                    ctx.result_null ();
                    return;
                }
                string s = arg_text (args[0]);
                int n = int.max (0, (int) args[1].to_int64 ());
                int chars = s.char_count ();
                ctx.result_text (n >= chars ? s : s.substring (0, s.index_of_nth_char (n)));
            }, null, null);
            db.create_function ("right", 2, flags, null, (ctx, args) => {
                if (args[0].to_type () == Sqlite.NULL) {
                    ctx.result_null ();
                    return;
                }
                string s = arg_text (args[0]);
                int n = int.max (0, (int) args[1].to_int64 ());
                int chars = s.char_count ();
                ctx.result_text (n >= chars ? s : s.substring (s.index_of_nth_char (chars - n)));
            }, null, null);
            db.create_function ("nz", -1, flags, null, (ctx, args) => {
                if (args.length == 0) {
                    ctx.result_null ();
                    return;
                }
                if (args[0].to_type () != Sqlite.NULL) ctx.result_value (args[0]);
                else if (args.length > 1) ctx.result_value (args[1]);
                else ctx.result_int (0);
            }, null, null);
            db.create_function ("regexp", 2, flags, null, (ctx, args) => {
                if (args[0].to_type () == Sqlite.NULL || args[1].to_type () == Sqlite.NULL) {
                    ctx.result_null ();
                    return;
                }
                try {
                    var re = new Regex (arg_text (args[0]));
                    ctx.result_int (re.match (arg_text (args[1])) ? 1 : 0);
                } catch (Error e) {
                    ctx.result_error (e.message, Sqlite.ERROR);
                }
            }, null, null);
            db.create_function ("casefold", 1, flags, null, (ctx, args) => {
                if (args[0].to_type () == Sqlite.NULL) ctx.result_null ();
                else ctx.result_text (arg_text (args[0]).casefold ());
            }, null, null);
            AccessSqlFunctions.register (db);
        }
    }
}
