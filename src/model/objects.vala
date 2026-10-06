namespace Singularity.Apps.Database {

    public enum ControlKind {
        AUTO,
        TEXT,
        MULTILINE,
        CHECK,
        CHOICE,
        LOOKUP,
        DATE,
        ATTACHMENT,
        LABEL,
        BUTTON,
        TAB,
        IMAGE,
        COMBO,
        LIST,
        OPTION_GROUP,
        TOGGLE,
        LINE,
        RECTANGLE,
        SUBFORM,
        CHART,
        RICH_TEXT,
        CHECK_LIST;

        public const ControlKind[] ALL = { AUTO, TEXT, MULTILINE, RICH_TEXT, CHECK, TOGGLE, CHOICE, LOOKUP, COMBO, LIST, CHECK_LIST, OPTION_GROUP, DATE, ATTACHMENT, LABEL, BUTTON, TAB, IMAGE, LINE, RECTANGLE, SUBFORM, CHART };

        public bool is_bound_kind () {
            return this != LABEL && this != BUTTON && this != TAB && this != IMAGE && this != LINE && this != RECTANGLE && this != SUBFORM && this != CHART;
        }

        public string id () {
            switch (this) {
                case BUTTON: return "button";
                case TAB: return "tab";
                case IMAGE: return "image";
                case COMBO: return "combo";
                case LIST: return "list";
                case OPTION_GROUP: return "option-group";
                case TOGGLE: return "toggle";
                case LINE: return "line";
                case RECTANGLE: return "rectangle";
                case SUBFORM: return "subform";
                case CHART: return "chart";
                case RICH_TEXT: return "rich-text";
                case CHECK_LIST: return "check-list";
                case TEXT: return "text";
                case MULTILINE: return "multiline";
                case CHECK: return "check";
                case CHOICE: return "choice";
                case LOOKUP: return "lookup";
                case DATE: return "date";
                case ATTACHMENT: return "attachment";
                case LABEL: return "label";
                default: return "auto";
            }
        }

        public static ControlKind from_id (string s) {
            switch (s) {
                case "text": return TEXT;
                case "multiline": return MULTILINE;
                case "check": return CHECK;
                case "choice": return CHOICE;
                case "lookup": return LOOKUP;
                case "date": return DATE;
                case "attachment": return ATTACHMENT;
                case "label": return LABEL;
                case "button": return BUTTON;
                case "tab": return TAB;
                case "image": return IMAGE;
                case "combo": return COMBO;
                case "list": return LIST;
                case "option-group": return OPTION_GROUP;
                case "toggle": return TOGGLE;
                case "line": return LINE;
                case "rectangle": return RECTANGLE;
                case "subform": return SUBFORM;
                case "chart": return CHART;
                case "rich-text": return RICH_TEXT;
                case "check-list": return CHECK_LIST;
                default: return AUTO;
            }
        }

        public string label () {
            switch (this) {
                case TEXT: return _("Text Box");
                case MULTILINE: return _("Text Area");
                case CHECK: return _("Check Box");
                case CHOICE: return _("Choice List");
                case LOOKUP: return _("Lookup List");
                case DATE: return _("Date Picker");
                case ATTACHMENT: return _("Attachment");
                case LABEL: return _("Label");
                case BUTTON: return _("Button");
                case TAB: return _("Tab Control");
                case IMAGE: return _("Image");
                case COMBO: return _("Combo Box");
                case LIST: return _("List Box");
                case OPTION_GROUP: return _("Option Group");
                case TOGGLE: return _("Toggle Button");
                case LINE: return _("Line");
                case RECTANGLE: return _("Rectangle");
                case SUBFORM: return _("Subform");
                case CHART: return _("Chart");
                case RICH_TEXT: return _("Rich Text Box");
                case CHECK_LIST: return _("Check List");
                default: return _("Automatic");
            }
        }

        public static ControlKind for_field (Field f) {
            if (f.multi_value) return CHECK_LIST;
            if (f.rich_text) return RICH_TEXT;
            switch (f.field_type) {
                case FieldType.LONG_TEXT: return MULTILINE;
                case FieldType.BOOLEAN: return CHECK;
                case FieldType.CHOICE: return CHOICE;
                case FieldType.LOOKUP: return LOOKUP;
                case FieldType.DATE:
                case FieldType.DATETIME: return DATE;
                case FieldType.ATTACHMENT: return ATTACHMENT;
                default: return TEXT;
            }
        }
    }

    public class CondRule {
        public string kind = "expression";
        public string op = "";
        public string value1 = "";
        public string value2 = "";
        public string expression = "";
        public string fore = "";
        public string back = "";
        public bool bold;
        public bool italic;
        public bool underline;
        public bool enabled = true;

        public CondRule copy () {
            var r = new CondRule ();
            r.kind = kind;
            r.op = op;
            r.value1 = value1;
            r.value2 = value2;
            r.expression = expression;
            r.fore = fore;
            r.back = back;
            r.bold = bold;
            r.italic = italic;
            r.underline = underline;
            r.enabled = enabled;
            return r;
        }

        public void build (Json.Builder b) {
            b.begin_object ();
            b.set_member_name ("kind").add_string_value (kind);
            b.set_member_name ("op").add_string_value (op);
            b.set_member_name ("value1").add_string_value (value1);
            b.set_member_name ("value2").add_string_value (value2);
            b.set_member_name ("expression").add_string_value (expression);
            b.set_member_name ("fore").add_string_value (fore);
            b.set_member_name ("back").add_string_value (back);
            b.set_member_name ("bold").add_boolean_value (bold);
            b.set_member_name ("italic").add_boolean_value (italic);
            b.set_member_name ("underline").add_boolean_value (underline);
            b.set_member_name ("enabled").add_boolean_value (enabled);
            b.end_object ();
        }

        public static CondRule read (Json.Object o) {
            var r = new CondRule ();
            r.kind = o.get_string_member_with_default ("kind", "expression");
            r.op = o.get_string_member_with_default ("op", "");
            r.value1 = o.get_string_member_with_default ("value1", "");
            r.value2 = o.get_string_member_with_default ("value2", "");
            r.expression = o.get_string_member_with_default ("expression", "");
            r.fore = o.get_string_member_with_default ("fore", "");
            r.back = o.get_string_member_with_default ("back", "");
            r.bold = o.get_boolean_member_with_default ("bold", false);
            r.italic = o.get_boolean_member_with_default ("italic", false);
            r.underline = o.get_boolean_member_with_default ("underline", false);
            r.enabled = o.get_boolean_member_with_default ("enabled", true);
            return r;
        }

        public static void build_list (Json.Builder b, string member, Gee.List<CondRule> rules) {
            if (rules.size == 0) return;
            b.set_member_name (member).begin_array ();
            foreach (var r in rules) r.build (b);
            b.end_array ();
        }

        public static Gee.ArrayList<CondRule> read_list (Json.Object o, string member) {
            var list = new Gee.ArrayList<CondRule> ();
            if (!o.has_member (member)) return list;
            o.get_array_member (member).foreach_element ((a, i, n) => list.add (CondRule.read (n.get_object ())));
            return list;
        }

        public string condition_expression (string control) {
            if (kind == "expression") return expression;
            string c = "[" + control + "]";
            string a = value1, b = value2;
            switch (op) {
                case "between": return "%s Between %s And %s".printf (c, a, b);
                case "not-between": return "Not (%s Between %s And %s)".printf (c, a, b);
                case "equal": return "%s = %s".printf (c, a);
                case "not-equal": return "%s <> %s".printf (c, a);
                case "greater": return "%s > %s".printf (c, a);
                case "less": return "%s < %s".printf (c, a);
                case "greater-equal": return "%s >= %s".printf (c, a);
                case "less-equal": return "%s <= %s".printf (c, a);
                case "empty": return "IsNull(%s) Or %s = \"\"".printf (c, c);
                case "contains": return "InStr(%s, %s) > 0".printf (c, a);
                default: return expression;
            }
        }
    }

    public class FormControl {
        public string field = "";
        public string label = "";
        public ControlKind kind = ControlKind.AUTO;
        public int x;
        public int y;
        public int width = 320;
        public int height = 0;
        public bool read_only;
        public string name = "";
        public string caption = "";
        public string section = "detail";
        public string parent = "";
        public string[] pages = {};
        public string image = "";
        public string row_source = "";
        public int bound_column = 1;
        public int column_count = 1;
        public bool limit_to_list = true;
        public string default_value = "";
        public string format = "";
        public string input_mask = "";
        public string validation_rule = "";
        public string validation_text = "";
        public bool visible = true;
        public bool enabled = true;
        public int tab_index = -1;
        public double font_size;
        public bool bold;
        public bool italic;
        public string fore_color = "";
        public string back_color = "";
        public string text_align = "";
        public string status_text = "";
        public bool hide_label;
        public OrderedMap<string> events = new OrderedMap<string> ();
        public Gee.ArrayList<CondRule> conditions = new Gee.ArrayList<CondRule> ();
        public string subform = "";
        public string link_master = "";
        public string link_child = "";
        public string chart_type = "column";
        public string chart_source = "";
        public string chart_category = "";
        public string chart_value = "";
        public string chart_aggregate = "sum";
        public string chart_series = "";

        public FormControl (string field, string label) {
            this.field = field;
            this.label = label;
        }

        public bool is_calculated () {
            return field.strip ().has_prefix ("=");
        }

        public bool is_bound () {
            return field.strip () != "" && !is_calculated () && kind.is_bound_kind ();
        }

        public string display_name () {
            if (name != "") return name;
            if (field != "" && !is_calculated ()) return field;
            return caption != "" ? caption : kind.label ();
        }

        public FormControl copy () {
            return FormControl.read (to_object ());
        }

        public Json.Object to_object () {
            var b = new Json.Builder ();
            build (b);
            return b.get_root ().get_object ();
        }

        public void build (Json.Builder b) {
            b.begin_object ();
            b.set_member_name ("field").add_string_value (field);
            b.set_member_name ("label").add_string_value (label);
            b.set_member_name ("kind").add_string_value (kind.id ());
            b.set_member_name ("x").add_int_value (x);
            b.set_member_name ("y").add_int_value (y);
            b.set_member_name ("width").add_int_value (width);
            b.set_member_name ("height").add_int_value (height);
            b.set_member_name ("read-only").add_boolean_value (read_only);
            if (name != "") b.set_member_name ("name").add_string_value (name);
            if (caption != "") b.set_member_name ("caption").add_string_value (caption);
            if (section != "detail") b.set_member_name ("section").add_string_value (section);
            if (parent != "") b.set_member_name ("parent").add_string_value (parent);
            if (pages.length > 0) {
                b.set_member_name ("pages").begin_array ();
                foreach (string p in pages) b.add_string_value (p);
                b.end_array ();
            }
            if (image != "") b.set_member_name ("image").add_string_value (image);
            if (row_source != "") b.set_member_name ("row-source").add_string_value (row_source);
            if (bound_column != 1) b.set_member_name ("bound-column").add_int_value (bound_column);
            if (column_count != 1) b.set_member_name ("column-count").add_int_value (column_count);
            if (!limit_to_list) b.set_member_name ("limit-to-list").add_boolean_value (false);
            if (default_value != "") b.set_member_name ("default").add_string_value (default_value);
            if (format != "") b.set_member_name ("format").add_string_value (format);
            if (input_mask != "") b.set_member_name ("input-mask").add_string_value (input_mask);
            if (validation_rule != "") b.set_member_name ("validation-rule").add_string_value (validation_rule);
            if (validation_text != "") b.set_member_name ("validation-text").add_string_value (validation_text);
            if (!visible) b.set_member_name ("visible").add_boolean_value (false);
            if (!enabled) b.set_member_name ("enabled").add_boolean_value (false);
            if (tab_index >= 0) b.set_member_name ("tab-index").add_int_value (tab_index);
            if (font_size > 0) b.set_member_name ("font-size").add_double_value (font_size);
            if (bold) b.set_member_name ("bold").add_boolean_value (true);
            if (italic) b.set_member_name ("italic").add_boolean_value (true);
            if (fore_color != "") b.set_member_name ("fore-color").add_string_value (fore_color);
            if (back_color != "") b.set_member_name ("back-color").add_string_value (back_color);
            if (text_align != "") b.set_member_name ("text-align").add_string_value (text_align);
            if (status_text != "") b.set_member_name ("status-text").add_string_value (status_text);
            if (hide_label) b.set_member_name ("hide-label").add_boolean_value (true);
            if (events.size > 0) {
                b.set_member_name ("events").begin_object ();
                foreach (var e in events.entries) b.set_member_name (e.key).add_string_value (e.value);
                b.end_object ();
            }
            CondRule.build_list (b, "conditions", conditions);
            if (subform != "") b.set_member_name ("subform").add_string_value (subform);
            if (link_master != "") b.set_member_name ("link-master").add_string_value (link_master);
            if (link_child != "") b.set_member_name ("link-child").add_string_value (link_child);
            if (kind == ControlKind.CHART) {
                b.set_member_name ("chart-type").add_string_value (chart_type);
                b.set_member_name ("chart-source").add_string_value (chart_source);
                b.set_member_name ("chart-category").add_string_value (chart_category);
                b.set_member_name ("chart-value").add_string_value (chart_value);
                b.set_member_name ("chart-aggregate").add_string_value (chart_aggregate);
                b.set_member_name ("chart-series").add_string_value (chart_series);
            }
            b.end_object ();
        }

        public static FormControl read (Json.Object c) {
            var fc = new FormControl (c.get_string_member_with_default ("field", ""), c.get_string_member_with_default ("label", ""));
            fc.kind = ControlKind.from_id (c.get_string_member_with_default ("kind", "auto"));
            fc.x = (int) c.get_int_member_with_default ("x", 0);
            fc.y = (int) c.get_int_member_with_default ("y", 0);
            fc.width = (int) c.get_int_member_with_default ("width", 320);
            fc.height = (int) c.get_int_member_with_default ("height", 60);
            fc.read_only = c.get_boolean_member_with_default ("read-only", false);
            fc.name = c.get_string_member_with_default ("name", "");
            fc.caption = c.get_string_member_with_default ("caption", "");
            fc.section = c.get_string_member_with_default ("section", "detail");
            fc.parent = c.get_string_member_with_default ("parent", "");
            fc.pages = Meta.string_array (c, "pages");
            fc.image = c.get_string_member_with_default ("image", "");
            fc.row_source = c.get_string_member_with_default ("row-source", "");
            fc.bound_column = (int) c.get_int_member_with_default ("bound-column", 1);
            fc.column_count = (int) c.get_int_member_with_default ("column-count", 1);
            fc.limit_to_list = c.get_boolean_member_with_default ("limit-to-list", true);
            fc.default_value = c.get_string_member_with_default ("default", "");
            fc.format = c.get_string_member_with_default ("format", "");
            fc.input_mask = c.get_string_member_with_default ("input-mask", "");
            fc.validation_rule = c.get_string_member_with_default ("validation-rule", "");
            fc.validation_text = c.get_string_member_with_default ("validation-text", "");
            fc.visible = c.get_boolean_member_with_default ("visible", true);
            fc.enabled = c.get_boolean_member_with_default ("enabled", true);
            fc.tab_index = (int) c.get_int_member_with_default ("tab-index", -1);
            fc.font_size = c.get_double_member_with_default ("font-size", 0);
            fc.bold = c.get_boolean_member_with_default ("bold", false);
            fc.italic = c.get_boolean_member_with_default ("italic", false);
            fc.fore_color = c.get_string_member_with_default ("fore-color", "");
            fc.back_color = c.get_string_member_with_default ("back-color", "");
            fc.text_align = c.get_string_member_with_default ("text-align", "");
            fc.status_text = c.get_string_member_with_default ("status-text", "");
            fc.hide_label = c.get_boolean_member_with_default ("hide-label", false);
            if (c.has_member ("events")) {
                var ev = c.get_object_member ("events");
                foreach (string k in ev.get_members ()) fc.events[k] = ev.get_string_member (k);
            }
            fc.conditions = CondRule.read_list (c, "conditions");
            fc.subform = c.get_string_member_with_default ("subform", "");
            fc.link_master = c.get_string_member_with_default ("link-master", "");
            fc.link_child = c.get_string_member_with_default ("link-child", "");
            fc.chart_type = c.get_string_member_with_default ("chart-type", "column");
            fc.chart_source = c.get_string_member_with_default ("chart-source", "");
            fc.chart_category = c.get_string_member_with_default ("chart-category", "");
            fc.chart_value = c.get_string_member_with_default ("chart-value", "");
            fc.chart_aggregate = c.get_string_member_with_default ("chart-aggregate", "sum");
            fc.chart_series = c.get_string_member_with_default ("chart-series", "");
            return fc;
        }
    }

    public class SubformDef {
        public string table = "";
        public string link_field = "";
        public string master_field = "";
        public string title = "";
        public string[] fields = {};
        public int x;
        public int y;
        public int width = 640;
        public int height = 220;
    }

    public enum FormLayout {
        COLUMNAR,
        TWO_COLUMNS,
        TABULAR;

        public string id () {
            switch (this) {
                case TWO_COLUMNS: return "two-columns";
                case TABULAR: return "tabular";
                default: return "columnar";
            }
        }

        public static FormLayout from_id (string s) {
            switch (s) {
                case "two-columns": return TWO_COLUMNS;
                case "tabular": return TABULAR;
                default: return COLUMNAR;
            }
        }
    }

    public class FormDef {
        public string name = "";
        public string source = "";
        public string title = "";
        public FormLayout layout = FormLayout.COLUMNAR;
        public Gee.ArrayList<FormControl> controls = new Gee.ArrayList<FormControl> ();
        public Gee.ArrayList<SubformDef> subforms = new Gee.ArrayList<SubformDef> ();
        public bool allow_add = true;
        public bool allow_delete = true;
        public bool allow_edit = true;
        public string sort = "";
        public string default_view = "single";
        public string filter = "";
        public bool filter_on_load;
        public string code = "";
        public int header_height;
        public int footer_height;
        public OrderedMap<string> events = new OrderedMap<string> ();
        public string[] navigation = {};
        public bool data_entry;
        public bool navigation_buttons = true;
        public bool modal;
        public string split_position = "top";

        public FormControl? find_control (string name) {
            foreach (var c in controls) {
                if (c.display_name ().casefold () == name.casefold ()) return c;
            }
            return null;
        }

        public string unique_control_name (string base_name) {
            string b = base_name.replace (" ", "");
            if (find_control (b) == null) return b;
            for (int i = 1; ; i++) {
                if (find_control ("%s%d".printf (b, i)) == null) return "%s%d".printf (b, i);
            }
        }

        public void name_controls () {
            foreach (var c in controls) {
                if (c.name != "") continue;
                string base_name;
                if (c.is_bound ()) base_name = c.field;
                else switch (c.kind) {
                    case ControlKind.BUTTON: base_name = "Command"; break;
                    case ControlKind.LABEL: base_name = "Label"; break;
                    case ControlKind.TAB: base_name = "TabCtl"; break;
                    case ControlKind.IMAGE: base_name = "Image"; break;
                    case ControlKind.SUBFORM: base_name = "Child"; break;
                    case ControlKind.CHART: base_name = "Chart"; break;
                    case ControlKind.LINE: base_name = "Line"; break;
                    case ControlKind.RECTANGLE: base_name = "Box"; break;
                    default: base_name = "Text"; break;
                }
                c.name = "";
                c.name = unique_control_name (base_name);
            }
        }

        public const int GRID = 8;
        public const int ROW_H = 64;
        public const int LABEL_W = 160;

        public static FormDef generate (Database db, string source, FormLayout layout = FormLayout.COLUMNAR) throws Error {
            var f = new FormDef ();
            f.source = source;
            f.name = db.unique_object_name (source);
            f.title = source;
            f.layout = layout;
            TableDef def;
            if (db.object_exists (source, "table")) def = db.load_table (source);
            else {
                def = new RecordSource (db, source).def;
                f.allow_add = false;
                f.allow_delete = false;
                f.allow_edit = false;
            }
            int col = 0;
            int y = 0;
            int row_h = 0;
            foreach (var field in def.fields) {
                var c = new FormControl (field.name, field.name);
                c.kind = ControlKind.AUTO;
                int h = field.field_type == FieldType.LONG_TEXT ? 132 : (field.field_type == FieldType.ATTACHMENT ? 100 : 60);
                c.height = h;
                if (field.field_type == FieldType.AUTONUMBER) c.read_only = true;
                bool wide = field.field_type == FieldType.LONG_TEXT || field.field_type == FieldType.ATTACHMENT;
                if (layout == FormLayout.TABULAR) {
                    c.x = col * 176;
                    c.y = 0;
                    c.width = wide ? 240 : 168;
                    c.height = 60;
                    col++;
                    f.controls.add (c);
                    continue;
                }
                if (layout == FormLayout.TWO_COLUMNS) {
                    if (wide && col == 1) {
                        y += row_h + 12;
                        col = 0;
                        row_h = 0;
                    }
                    c.x = col == 0 ? 0 : 392;
                    c.y = y;
                    c.width = wide ? 752 : 360;
                    row_h = int.max (row_h, h);
                    if (col == 1 || wide) {
                        y += row_h + 12;
                        col = 0;
                        row_h = 0;
                    } else {
                        col = 1;
                    }
                } else {
                    c.x = 0;
                    c.y = y;
                    c.width = field.field_type == FieldType.LONG_TEXT ? 520 : (field.field_type.is_numeric () || field.field_type.is_temporal () || field.field_type == FieldType.BOOLEAN ? 240 : 400);
                    y += h + 12;
                }
                f.controls.add (c);
            }
            if (layout == FormLayout.TABULAR) {
                f.default_view = "continuous";
                y = 72;
            } else if (col == 1) y += row_h + 12;
            y += 12;
            if (def.fields.size > 0 && db.object_exists (source, "table")) {
                foreach (var rel in db.relationships_to (source)) {
                    if (rel.columns.length != 1 || rel.table.casefold () == source.casefold ()) continue;
                    var sub = new SubformDef ();
                    sub.table = rel.table;
                    sub.link_field = rel.columns[0];
                    sub.master_field = rel.ref_columns[0];
                    sub.title = rel.table;
                    try {
                        var cdef = db.load_table (rel.table);
                        string[] names = {};
                        foreach (var cf in cdef.fields) {
                            if (cf.name.casefold () == sub.link_field.casefold ()) continue;
                            names += cf.name;
                        }
                        sub.fields = names;
                    } catch (Error e) {
                    }
                    sub.x = 0;
                    sub.y = y;
                    sub.width = layout == FormLayout.TWO_COLUMNS ? 752 : 720;
                    sub.height = 260;
                    y += sub.height + 24;
                    f.subforms.add (sub);
                }
            }
            f.name_controls ();
            return f;
        }

        public string to_json () {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("source").add_string_value (source);
            b.set_member_name ("title").add_string_value (title);
            b.set_member_name ("layout").add_string_value (layout.id ());
            b.set_member_name ("allow-add").add_boolean_value (allow_add);
            b.set_member_name ("allow-delete").add_boolean_value (allow_delete);
            b.set_member_name ("allow-edit").add_boolean_value (allow_edit);
            b.set_member_name ("sort").add_string_value (sort);
            if (default_view != "single") b.set_member_name ("default-view").add_string_value (default_view);
            if (filter != "") b.set_member_name ("filter").add_string_value (filter);
            if (filter_on_load) b.set_member_name ("filter-on-load").add_boolean_value (true);
            if (code != "") b.set_member_name ("code").add_string_value (code);
            if (header_height > 0) b.set_member_name ("header-height").add_int_value (header_height);
            if (footer_height > 0) b.set_member_name ("footer-height").add_int_value (footer_height);
            if (events.size > 0) {
                b.set_member_name ("events").begin_object ();
                foreach (var e in events.entries) b.set_member_name (e.key).add_string_value (e.value);
                b.end_object ();
            }
            if (navigation.length > 0) {
                b.set_member_name ("navigation").begin_array ();
                foreach (string n in navigation) b.add_string_value (n);
                b.end_array ();
            }
            if (data_entry) b.set_member_name ("data-entry").add_boolean_value (true);
            if (!navigation_buttons) b.set_member_name ("navigation-buttons").add_boolean_value (false);
            if (modal) b.set_member_name ("modal").add_boolean_value (true);
            if (split_position != "top") b.set_member_name ("split-position").add_string_value (split_position);
            b.set_member_name ("controls").begin_array ();
            foreach (var c in controls) c.build (b);
            b.end_array ();
            b.set_member_name ("subforms").begin_array ();
            foreach (var s in subforms) {
                b.begin_object ();
                b.set_member_name ("table").add_string_value (s.table);
                b.set_member_name ("link").add_string_value (s.link_field);
                b.set_member_name ("master").add_string_value (s.master_field);
                b.set_member_name ("title").add_string_value (s.title);
                b.set_member_name ("x").add_int_value (s.x);
                b.set_member_name ("y").add_int_value (s.y);
                b.set_member_name ("width").add_int_value (s.width);
                b.set_member_name ("height").add_int_value (s.height);
                b.set_member_name ("fields").begin_array ();
                foreach (string f in s.fields) b.add_string_value (f);
                b.end_array ();
                b.end_object ();
            }
            b.end_array ();
            b.end_object ();
            return Json.to_string (b.get_root (), false);
        }

        public static FormDef? from_json (string name, string? json) {
            var o = Meta.parse_object (json);
            if (o == null) return null;
            var f = new FormDef ();
            f.name = name;
            f.source = o.get_string_member_with_default ("source", "");
            f.title = o.get_string_member_with_default ("title", name);
            f.layout = FormLayout.from_id (o.get_string_member_with_default ("layout", "columnar"));
            f.allow_add = o.get_boolean_member_with_default ("allow-add", true);
            f.allow_delete = o.get_boolean_member_with_default ("allow-delete", true);
            f.allow_edit = o.get_boolean_member_with_default ("allow-edit", true);
            f.sort = o.get_string_member_with_default ("sort", "");
            f.default_view = o.get_string_member_with_default ("default-view", "single");
            f.filter = o.get_string_member_with_default ("filter", "");
            f.filter_on_load = o.get_boolean_member_with_default ("filter-on-load", false);
            f.code = o.get_string_member_with_default ("code", "");
            f.header_height = (int) o.get_int_member_with_default ("header-height", 0);
            f.footer_height = (int) o.get_int_member_with_default ("footer-height", 0);
            if (o.has_member ("events")) {
                var ev = o.get_object_member ("events");
                foreach (string k in ev.get_members ()) f.events[k] = ev.get_string_member (k);
            }
            f.navigation = Meta.string_array (o, "navigation");
            f.data_entry = o.get_boolean_member_with_default ("data-entry", false);
            f.navigation_buttons = o.get_boolean_member_with_default ("navigation-buttons", true);
            f.modal = o.get_boolean_member_with_default ("modal", false);
            f.split_position = o.get_string_member_with_default ("split-position", "top");
            if (o.has_member ("controls")) {
                o.get_array_member ("controls").foreach_element ((a, i, n) => f.controls.add (FormControl.read (n.get_object ())));
            }
            f.name_controls ();
            if (o.has_member ("subforms")) {
                o.get_array_member ("subforms").foreach_element ((a, i, n) => {
                    var c = n.get_object ();
                    var s = new SubformDef ();
                    s.table = c.get_string_member_with_default ("table", "");
                    s.link_field = c.get_string_member_with_default ("link", "");
                    s.master_field = c.get_string_member_with_default ("master", "");
                    s.title = c.get_string_member_with_default ("title", s.table);
                    s.x = (int) c.get_int_member_with_default ("x", 0);
                    s.y = (int) c.get_int_member_with_default ("y", 0);
                    s.width = (int) c.get_int_member_with_default ("width", 640);
                    s.height = (int) c.get_int_member_with_default ("height", 220);
                    s.fields = Meta.string_array (c, "fields");
                    f.subforms.add (s);
                });
            }
            return f;
        }

        public void snap () {
            foreach (var c in controls) {
                c.x = (int) Math.round (c.x / (double) GRID) * GRID;
                c.y = (int) Math.round (c.y / (double) GRID) * GRID;
                c.width = int.max (GRID * 8, (int) Math.round (c.width / (double) GRID) * GRID);
                c.x = int.max (0, c.x);
                c.y = int.max (0, c.y);
            }
            foreach (var s in subforms) {
                s.x = int.max (0, (int) Math.round (s.x / (double) GRID) * GRID);
                s.y = int.max (0, (int) Math.round (s.y / (double) GRID) * GRID);
            }
        }

        public void tidy () {
            var sorted = new Gee.ArrayList<FormControl> ();
            sorted.add_all (controls);
            sorted.sort ((a, b) => a.y != b.y ? a.y - b.y : a.x - b.x);
            int y = 0;
            int row_y = -1;
            int row_h = 0;
            foreach (var c in sorted) {
                if (row_y < 0 || c.y > row_y + 16) {
                    y += row_h > 0 ? row_h + 12 : 0;
                    row_y = c.y;
                    row_h = 0;
                }
                c.y = y;
                row_h = int.max (row_h, c.height > 0 ? c.height : 60);
            }
            y += row_h > 0 ? row_h + 24 : 0;
            foreach (var s in subforms) {
                s.y = y;
                y += s.height + 24;
            }
        }
    }

    public enum ViewKind {
        GRID,
        GALLERY,
        KANBAN,
        CALENDAR;

        public string id () {
            switch (this) {
                case GALLERY: return "gallery";
                case KANBAN: return "kanban";
                case CALENDAR: return "calendar";
                default: return "grid";
            }
        }

        public static ViewKind from_id (string s) {
            switch (s) {
                case "gallery": return GALLERY;
                case "kanban": return KANBAN;
                case "calendar": return CALENDAR;
                default: return GRID;
            }
        }

        public string label () {
            switch (this) {
                case GALLERY: return _("Gallery");
                case KANBAN: return _("Kanban");
                case CALENDAR: return _("Calendar");
                default: return _("Grid");
            }
        }

        public string icon_name () {
            switch (this) {
                case GALLERY: return "db-view-gallery-symbolic";
                case KANBAN: return "db-view-kanban-symbolic";
                case CALENDAR: return "db-view-calendar-symbolic";
                default: return "db-view-grid-symbolic";
            }
        }
    }

    public class ViewDef {
        public string name = "";
        public ViewKind kind = ViewKind.GRID;
        public ViewState state = new ViewState ();
        public string group_field = "";
        public string date_field = "";
        public string title_field = "";
        public string image_field = "";
        public string[] card_fields = {};

        public ViewDef (string name, ViewKind kind) {
            this.name = name;
            this.kind = kind;
        }

        public static Gee.ArrayList<ViewDef> load_all (Database db, string table) {
            var list = new Gee.ArrayList<ViewDef> ();
            string? json = db.get_meta ("views:" + table);
            if (json != null) {
                try {
                    var p = new Json.Parser ();
                    p.load_from_data (json);
                    var arr = p.get_root ().get_array ();
                    arr.foreach_element ((a, i, n) => {
                        var o = n.get_object ();
                        var v = new ViewDef (o.get_string_member_with_default ("name", _("Grid")), ViewKind.from_id (o.get_string_member_with_default ("kind", "grid")));
                        if (o.has_member ("state")) v.state = ViewState.read (o.get_object_member ("state"));
                        v.group_field = o.get_string_member_with_default ("group-field", "");
                        v.date_field = o.get_string_member_with_default ("date-field", "");
                        v.title_field = o.get_string_member_with_default ("title-field", "");
                        v.image_field = o.get_string_member_with_default ("image-field", "");
                        v.card_fields = Meta.string_array (o, "card-fields");
                        list.add (v);
                    });
                } catch (Error e) {
                }
            }
            if (list.size == 0 || list[0].kind != ViewKind.GRID) list.insert (0, new ViewDef (_("Grid"), ViewKind.GRID));
            return list;
        }

        public static string to_json_all (Gee.ArrayList<ViewDef> views) {
            var b = new Json.Builder ();
            b.begin_array ();
            foreach (var v in views) {
                b.begin_object ();
                b.set_member_name ("name").add_string_value (v.name);
                b.set_member_name ("kind").add_string_value (v.kind.id ());
                b.set_member_name ("state").begin_object ();
                v.state.build (b);
                b.end_object ();
                b.set_member_name ("group-field").add_string_value (v.group_field);
                b.set_member_name ("date-field").add_string_value (v.date_field);
                b.set_member_name ("title-field").add_string_value (v.title_field);
                b.set_member_name ("image-field").add_string_value (v.image_field);
                b.set_member_name ("card-fields").begin_array ();
                foreach (string f in v.card_fields) b.add_string_value (f);
                b.end_array ();
                b.end_object ();
            }
            b.end_array ();
            return Json.to_string (b.get_root (), false);
        }

        public void pick_defaults (TableDef def) {
            foreach (var f in def.fields) {
                if (title_field == "" && f.field_type.is_text () && f.field_type != FieldType.LONG_TEXT) title_field = f.name;
                if (group_field == "" && (f.field_type == FieldType.CHOICE || f.field_type == FieldType.BOOLEAN)) group_field = f.name;
                if (date_field == "" && f.field_type.is_temporal () && f.field_type != FieldType.TIME) date_field = f.name;
                if (image_field == "" && f.field_type == FieldType.ATTACHMENT) image_field = f.name;
            }
            if (group_field == "") {
                foreach (var f in def.fields) {
                    if (f.field_type == FieldType.LOOKUP || f.field_type == FieldType.TEXT) {
                        group_field = f.name;
                        break;
                    }
                }
            }
            if (card_fields.length == 0) {
                string[] cf = {};
                foreach (var f in def.fields) {
                    if (f.name == title_field || f.field_type == FieldType.AUTONUMBER || f.field_type == FieldType.ATTACHMENT || f.name == group_field) continue;
                    if (cf.length < 4) cf += f.name;
                }
                card_fields = cf;
            }
        }
    }
}

namespace Singularity.Apps.Database {

    public class StartupOptions {
        public string app_title = "";
        public string startup_form = "";
        public bool hide_navigation;
        public bool compact_on_close;
        public int refresh_seconds = 5;
        public bool record_locking = true;

        public static StartupOptions load (Database db) {
            var o = new StartupOptions ();
            var j = Meta.parse_object (db.get_meta ("options:startup"));
            if (j == null) return o;
            o.app_title = j.get_string_member_with_default ("app-title", "");
            o.startup_form = j.get_string_member_with_default ("startup-form", "");
            o.hide_navigation = j.get_boolean_member_with_default ("hide-navigation", false);
            o.compact_on_close = j.get_boolean_member_with_default ("compact-on-close", false);
            o.refresh_seconds = (int) j.get_int_member_with_default ("refresh-seconds", 5);
            o.record_locking = j.get_boolean_member_with_default ("record-locking", true);
            return o;
        }

        public void save (Database db) throws Error {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("app-title").add_string_value (app_title);
            b.set_member_name ("startup-form").add_string_value (startup_form);
            b.set_member_name ("hide-navigation").add_boolean_value (hide_navigation);
            b.set_member_name ("compact-on-close").add_boolean_value (compact_on_close);
            b.set_member_name ("refresh-seconds").add_int_value (refresh_seconds);
            b.set_member_name ("record-locking").add_boolean_value (record_locking);
            b.end_object ();
            db.save_object_meta (_("Change Startup Options"), "options:", "startup", Json.to_string (b.get_root (), false));
        }
    }
}
