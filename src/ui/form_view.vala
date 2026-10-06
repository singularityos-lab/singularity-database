using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Database {

    public class Styling {
        private static int counter;

        public static void apply (Widget w, string fore, string back, bool bold, bool italic, bool underline = false, double font_size = 0) {
            var sb = new StringBuilder ();
            if (fore != "") sb.append ("color: %s; ".printf (fore));
            if (back != "") sb.append ("background: %s; background-color: %s; ".printf (back, back));
            sb.append ("font-weight: %s; ".printf (bold ? "bold" : "normal"));
            sb.append ("font-style: %s; ".printf (italic ? "italic" : "normal"));
            if (underline) sb.append ("text-decoration: underline; ");
            if (font_size > 0) sb.append ("font-size: %gpt; ".printf (font_size).replace (",", "."));
            string cls = w.get_data<string> ("db-style-class");
            if (cls == null) {
                cls = "db-cf-%d".printf (++counter);
                w.set_data<string> ("db-style-class", cls);
                w.add_css_class (cls);
            }
            var provider = w.get_data<CssProvider> ("db-style-provider");
            if (provider == null) {
                provider = new CssProvider ();
                w.set_data<CssProvider> ("db-style-provider", provider);
                w.get_style_context ().add_provider (provider, STYLE_PROVIDER_PRIORITY_USER + 5);
            }
            string css = ".%s, .%s entry, .%s text, .%s label, .%s textview, .%s textview text { %s }".printf (cls, cls, cls, cls, cls, cls, sb.str);
            provider.load_from_string (css);
        }

        public static string vba_color (int64 c) {
            return "#%02x%02x%02x".printf ((int) (c & 255), (int) ((c >> 8) & 255), (int) ((c >> 16) & 255));
        }

        public static int64 color_to_vba (string hex) {
            var rgba = Gdk.RGBA ();
            if (!rgba.parse (hex)) return 0;
            return ((int64) (rgba.red * 255)) | (((int64) (rgba.green * 255)) << 8) | (((int64) (rgba.blue * 255)) << 16);
        }
    }

    public class UnboundControl : FieldControl {
        private Entry entry;

        public UnboundControl (Field f) {
            field = f;
            entry = new Entry ();
            entry.hexpand = true;
            entry.changed.connect (() => emit_changed ());
            widget = entry;
        }

        public override DbValue get_value () throws Error {
            string t = entry.text;
            if (t == "") return new DbValue.null ();
            double d;
            if (Codec.parse_number (t, out d) && !t.contains ("/")) return d == Math.floor (d) && !t.contains (".") ? new DbValue.int ((int64) d) : new DbValue.real (d);
            return new DbValue.text (t);
        }

        public override void set_value (DbValue v) {
            loading = true;
            entry.text = Codec.display (field, v);
            loading = false;
        }

        public override void set_editable (bool on) {
            entry.editable = on;
        }
    }

    public class CalcControl : FieldControl {
        private Entry entry;
        private DbValue value = new DbValue.null ();

        public CalcControl (Field f) {
            field = f;
            entry = new Entry ();
            entry.editable = false;
            entry.can_focus = false;
            entry.hexpand = true;
            entry.add_css_class ("db-calc-control");
            widget = entry;
        }

        public override DbValue get_value () throws Error {
            return value;
        }

        public override void set_value (DbValue v) {
            value = v;
            entry.text = Codec.display (field, v);
            entry.xalign = v.is_number () ? 1 : 0;
        }
    }

    public class ComboControl : FieldControl {
        private DropDown dd;
        private Gee.ArrayList<DbValue> values = new Gee.ArrayList<DbValue> ();
        private Gee.ArrayList<Row> rows = new Gee.ArrayList<Row> ();
        private Gtk.ListBox? list;

        public ComboControl (Field f, Database db, FormControl c, bool as_list) {
            field = f;
            string[] labels = {};
            if (!as_list) {
                labels += _("(Empty)");
                values.add (new DbValue.null ());
                rows.add (new Row (0, { new DbValue.null () }));
            }
            foreach (var r in row_source_rows (db, c.row_source, f)) {
                int bc = int.max (0, c.bound_column - 1);
                int shown = c.column_count > 1 && r.values.length > 1 && bc == 0 ? 1 : (r.values.length > 1 && bc == 0 && c.column_count > 1 ? 1 : 0);
                if (c.column_count > 1 && r.values.length > 1) shown = bc == 0 ? 1 : 0;
                values.add (r.get (bc));
                rows.add (r);
                labels += r.get (shown).to_string ();
            }
            if (as_list) {
                list = new Gtk.ListBox ();
                list.selection_mode = SelectionMode.SINGLE;
                list.add_css_class ("boxed-list");
                foreach (string l in labels) {
                    var lab = new Label (l);
                    lab.xalign = 0;
                    lab.margin_start = lab.margin_end = 8;
                    lab.margin_top = lab.margin_bottom = 4;
                    list.append (lab);
                }
                list.row_selected.connect (() => emit_changed ());
                var sc = new ScrolledWindow ();
                sc.child = list;
                sc.vexpand = true;
                sc.hscrollbar_policy = PolicyType.NEVER;
                widget = sc;
                return;
            }
            dd = new DropDown.from_strings (labels);
            dd.enable_search = true;
            dd.expression = new PropertyExpression (typeof (StringObject), null, "string");
            dd.hexpand = true;
            dd.notify["selected"].connect (() => emit_changed ());
            widget = dd;
        }

        public static Gee.ArrayList<Row> row_source_rows (Database db, string source, Field f) {
            var list = new Gee.ArrayList<Row> ();
            string s = source.strip ();
            try {
                if (s == "" && f.field_type == FieldType.LOOKUP) {
                    var rs0 = new RecordSource (db, f.table_name != "" ? f.table_name : f.lookup_table);
                    foreach (var r in rs0.lookup_choices (f, 2000)) list.add (r);
                    return list;
                }
                if (s == "" && f.field_type == FieldType.CHOICE) {
                    foreach (string c in f.choices) list.add (new Row (list.size, { new DbValue.text (c) }));
                    return list;
                }
                if (s.down ().has_prefix ("select ")) {
                    foreach (var r in db.query (AccessSql.statement (s), null, 5000).rows) list.add (r);
                    return list;
                }
                string name = s.has_prefix ("[") && s.has_suffix ("]") ? s.substring (1, s.length - 2) : s;
                if (name != "" && db.object_exists (name)) {
                    foreach (var r in db.query ("SELECT * FROM %s".printf (Sql.quote_ident (name)), null, 5000).rows) list.add (r);
                    return list;
                }
                foreach (string item in s.split (";")) {
                    string t = item.strip ();
                    if (t.has_prefix ("\"") && t.has_suffix ("\"") && t.length >= 2) t = t.substring (1, t.length - 2);
                    if (t != "") list.add (new Row (list.size, { new DbValue.text (t) }));
                }
            } catch (Error e) {
            }
            return list;
        }

        public override DbValue get_value () throws Error {
            if (list != null) {
                var r = list.get_selected_row ();
                return r != null && r.get_index () < values.size ? values[r.get_index ()] : new DbValue.null ();
            }
            uint i = dd.selected;
            if (i >= values.size) return new DbValue.null ();
            var v = values[(int) i];
            if (v.is_null || field.field_type.is_text () || field.name == "") return v;
            try {
                return Codec.parse (field, v.to_string ());
            } catch (Error e) {
                return v;
            }
        }

        public override void set_value (DbValue v) {
            loading = true;
            int found = -1;
            for (int i = 0; i < values.size; i++) {
                if (!v.is_null && !values[i].is_null && (values[i].equals (v) || values[i].to_string ().casefold () == v.to_string ().casefold ())) {
                    found = i;
                    break;
                }
            }
            if (list != null) {
                if (found >= 0) list.select_row (list.get_row_at_index (found));
                else list.unselect_all ();
            } else {
                dd.selected = found >= 0 ? found : 0;
            }
            loading = false;
        }

        public SValue column (int col) {
            int i = list != null ? (list.get_selected_row () != null ? list.get_selected_row ().get_index () : -1) : (int) dd.selected;
            if (i < 0 || i >= rows.size) return new SValue.null ();
            return SValue.from_db (rows[i].get (col));
        }

        public int count () {
            return rows.size;
        }
    }

    public class OptionGroupControl : FieldControl {
        private Gee.ArrayList<CheckButton> buttons = new Gee.ArrayList<CheckButton> ();
        private Gee.ArrayList<DbValue> values = new Gee.ArrayList<DbValue> ();

        public OptionGroupControl (Field f, Database db, FormControl c) {
            field = f;
            var frame = new Box (Orientation.VERTICAL, 4);
            frame.add_css_class ("db-option-group");
            CheckButton? first = null;
            var items = ComboControl.row_source_rows (db, c.row_source, f);
            int k = 0;
            foreach (var r in items) {
                k++;
                var b = new CheckButton.with_label (r.get (r.values.length > 1 ? 1 : 0).to_string ());
                if (first == null) first = b;
                else b.group = first;
                b.toggled.connect (() => {
                    if (b.active) emit_changed ();
                });
                DbValue v = r.values.length > 1 ? r.get (0) : new DbValue.int (k);
                values.add (v);
                buttons.add (b);
                frame.append (b);
            }
            widget = frame;
        }

        public override DbValue get_value () throws Error {
            for (int i = 0; i < buttons.size; i++) {
                if (buttons[i].active) return values[i];
            }
            return new DbValue.null ();
        }

        public override void set_value (DbValue v) {
            loading = true;
            foreach (var b in buttons) b.active = false;
            for (int i = 0; i < values.size; i++) {
                if (!v.is_null && values[i].equals (v)) buttons[i].active = true;
            }
            loading = false;
        }
    }

    public class ToggleControl : FieldControl {
        private ToggleButton button;

        public ToggleControl (Field f, string caption) {
            field = f;
            button = new ToggleButton.with_label (caption != "" ? caption : f.label ());
            button.toggled.connect (() => emit_changed ());
            widget = button;
        }

        public override DbValue get_value () throws Error {
            return new DbValue.bool (button.active);
        }

        public override void set_value (DbValue v) {
            loading = true;
            button.active = v.as_bool ();
            loading = false;
        }
    }

    public class CheckListControl : FieldControl {
        private Gee.ArrayList<CheckButton> checks = new Gee.ArrayList<CheckButton> ();
        private Gee.ArrayList<string> keys = new Gee.ArrayList<string> ();

        public CheckListControl (Field f, Database db, RecordSource src) {
            field = f;
            var box = new Box (Orientation.VERTICAL, 2);
            box.add_css_class ("db-check-list");
            if (f.field_type == FieldType.LOOKUP) {
                foreach (var r in src.lookup_choices (f, 2000)) {
                    keys.add (r.get (0).to_string ());
                    var c = new CheckButton.with_label (r.get (1).to_string ());
                    c.toggled.connect (() => emit_changed ());
                    checks.add (c);
                    box.append (c);
                }
            } else {
                foreach (string ch in f.choices) {
                    keys.add (ch);
                    var c = new CheckButton.with_label (ch);
                    c.toggled.connect (() => emit_changed ());
                    checks.add (c);
                    box.append (c);
                }
            }
            var sc = new ScrolledWindow ();
            sc.hscrollbar_policy = PolicyType.NEVER;
            sc.child = box;
            sc.vexpand = true;
            widget = sc;
        }

        public override DbValue get_value () throws Error {
            string[] on = {};
            for (int i = 0; i < checks.size; i++) {
                if (checks[i].active) on += keys[i];
            }
            return MultiValue.from_list (on);
        }

        public override void set_value (DbValue v) {
            loading = true;
            var items = MultiValue.items (v);
            for (int i = 0; i < checks.size; i++) {
                bool on = false;
                foreach (string it in items) {
                    if (it == keys[i]) on = true;
                }
                checks[i].active = on;
            }
            loading = false;
        }
    }

    public class RichTextControl : FieldControl {
        private TextView view;
        private TextTag bold_tag;
        private TextTag italic_tag;
        private TextTag underline_tag;
        private TextTag red_tag;

        public RichTextControl (Field f) {
            field = f;
            view = new TextView ();
            view.wrap_mode = WrapMode.WORD_CHAR;
            view.top_margin = view.bottom_margin = view.left_margin = view.right_margin = 6;
            bold_tag = view.buffer.create_tag ("b", "weight", 700);
            italic_tag = view.buffer.create_tag ("i", "style", Pango.Style.ITALIC);
            underline_tag = view.buffer.create_tag ("u", "underline", Pango.Underline.SINGLE);
            red_tag = view.buffer.create_tag ("red", "foreground", "#c01c28");
            view.buffer.changed.connect (() => emit_changed ());
            var box = new Box (Orientation.VERTICAL, 2);
            var bar = new Box (Orientation.HORIZONTAL, 2);
            bar.append (tag_button ("format-text-bold-symbolic", _("Bold"), bold_tag));
            bar.append (tag_button ("format-text-italic-symbolic", _("Italic"), italic_tag));
            bar.append (tag_button ("format-text-underline-symbolic", _("Underline"), underline_tag));
            bar.append (tag_button ("format-text-strikethrough-symbolic", _("Highlight in Red"), red_tag));
            box.append (bar);
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.vexpand = true;
            scroll.child = view;
            scroll.add_css_class ("db-form-multiline");
            box.append (scroll);
            widget = box;
        }

        private Button tag_button (string icon, string tip, TextTag tag) {
            var b = new Button.from_icon_name (icon);
            b.add_css_class ("flat");
            b.tooltip_text = tip;
            b.clicked.connect (() => {
                TextIter a, e;
                if (!view.buffer.get_selection_bounds (out a, out e)) return;
                if (a.has_tag (tag)) view.buffer.remove_tag (tag, a, e);
                else view.buffer.apply_tag (tag, a, e);
                emit_changed ();
            });
            return b;
        }

        public override DbValue get_value () throws Error {
            var sb = new StringBuilder ("<div>");
            TextIter it;
            view.buffer.get_start_iter (out it);
            bool b = false, i = false, u = false, r = false;
            while (!it.is_end ()) {
                bool nb = it.has_tag (bold_tag), ni = it.has_tag (italic_tag), nu = it.has_tag (underline_tag), nr = it.has_tag (red_tag);
                if (r && !nr) sb.append ("</font>");
                if (u && !nu) sb.append ("</u>");
                if (i && !ni) sb.append ("</em>");
                if (b && !nb) sb.append ("</strong>");
                if (nb && !b) sb.append ("<strong>");
                if (ni && !i) sb.append ("<em>");
                if (nu && !u) sb.append ("<u>");
                if (nr && !r) sb.append ("<font color=\"#c01c28\">");
                b = nb;
                i = ni;
                u = nu;
                r = nr;
                unichar c = it.get_char ();
                if (c == '\n') sb.append ("<br>");
                else sb.append (Markup.escape_text (c.to_string ()));
                it.forward_char ();
            }
            if (r) sb.append ("</font>");
            if (u) sb.append ("</u>");
            if (i) sb.append ("</em>");
            if (b) sb.append ("</strong>");
            sb.append ("</div>");
            if (view.buffer.text.strip () == "") return new DbValue.null ();
            return new DbValue.text (sb.str);
        }

        public override void set_value (DbValue v) {
            loading = true;
            view.buffer.text = "";
            if (!v.is_null) {
                TextIter end;
                view.buffer.get_end_iter (out end);
                string markup = RichText.to_markup (v.to_string ());
                view.buffer.insert_markup (ref end, markup, -1);
                TextIter a, e;
                view.buffer.get_bounds (out a, out e);
                var it = a;
                while (!it.is_end ()) {
                    foreach (var t in it.get_tags ()) {
                        var run_end = it;
                        run_end.forward_to_tag_toggle (t);
                        if (t.weight_set && t.weight >= 600) view.buffer.apply_tag (bold_tag, it, run_end);
                        if (t.style_set && t.style == Pango.Style.ITALIC) view.buffer.apply_tag (italic_tag, it, run_end);
                        if (t.underline_set && t.underline != Pango.Underline.NONE) view.buffer.apply_tag (underline_tag, it, run_end);
                        if (t.foreground_set) view.buffer.apply_tag (red_tag, it, run_end);
                    }
                    if (!it.forward_to_tag_toggle (null)) break;
                }
            }
            loading = false;
        }

        public override void set_editable (bool on) {
            view.editable = on;
        }
    }

    public class ChartWidget : DrawingArea {
        public ChartData data = new ChartData ();
        public string chart_type = "column";

        public ChartWidget () {
            set_draw_func ((area, cr, w, h) => data.draw (cr, 0, 0, w, h, chart_type, false));
            add_css_class ("db-chart");
        }
    }

    public class CtlBinding {
        public FormControl c;
        public Field? field;
        public FieldControl? fc;
        public Widget widget;
        public Widget outer;
        public Label? label;
        public DbValue focus_value = new DbValue.null ();
        public DbValue unbound = new DbValue.null ();
        public bool changed_since_focus;
        public FormView? subview;
        public DatasheetView? subsheet;
        public ChartWidget? chart;
        public Gtk.Notebook? notebook;
        public bool visible = true;
        public bool enabled = true;
        public bool locked;
        public string caption = "";
        public string fore = "";
        public string back = "";
        public bool bold;

        public CtlBinding (FormControl c) {
            this.c = c;
            visible = c.visible;
            enabled = c.enabled;
            locked = c.read_only;
            caption = c.caption != "" ? c.caption : c.label;
            fore = c.fore_color;
            back = c.back_color;
            bold = c.bold;
        }
    }

    public class ControlObject : ScriptObject {
        private weak FormView view;
        private CtlBinding b;

        public ControlObject (FormView view, CtlBinding b) {
            this.view = view;
            this.b = b;
        }

        public override string type_name () {
            switch (b.c.kind) {
                case ControlKind.BUTTON: return "CommandButton";
                case ControlKind.LABEL: return "Label";
                case ControlKind.COMBO: return "ComboBox";
                case ControlKind.LIST: return "ListBox";
                case ControlKind.CHECK: return "CheckBox";
                case ControlKind.SUBFORM: return "SubForm";
                case ControlKind.TAB: return "TabControl";
                default: return "TextBox";
            }
        }

        public override SValue get_default (SValue[] args) throws ScriptError {
            if (b.subview != null) return new SValue.object (b.subview.me);
            return view.control_value (b);
        }

        public override void set_default (SValue[] args, SValue value) throws ScriptError {
            view.set_control_value (b, value);
        }

        public override bool has_member (string name) {
            return true;
        }

        public override SValue get_member (string name, SValue[] args) throws ScriptError {
            switch (name.down ()) {
                case "value":
                case "text": return view.control_value (b);
                case "oldvalue": return SValue.from_field (b.focus_value, b.field);
                case "visible": return new SValue.bool (b.visible);
                case "enabled": return new SValue.bool (b.enabled);
                case "locked": return new SValue.bool (b.locked);
                case "caption": return new SValue.str (b.caption);
                case "name": return new SValue.str (b.c.display_name ());
                case "controlsource": return new SValue.str (b.c.field);
                case "rowsource": return new SValue.str (b.c.row_source);
                case "forecolor": return new SValue.int (Styling.color_to_vba (b.fore));
                case "backcolor": return new SValue.int (Styling.color_to_vba (b.back));
                case "fontbold": return new SValue.bool (b.bold);
                case "form":
                    if (b.subview != null) return new SValue.object (b.subview.me);
                    break;
                case "listcount":
                    var cc = b.fc as ComboControl;
                    return new SValue.int (cc != null ? cc.count () : 0);
                case "column":
                    var cc2 = b.fc as ComboControl;
                    if (cc2 == null) return new SValue.null ();
                    return cc2.column (args.length > 0 ? (int) args[0].to_int () : 0);
                case "setfocus":
                    view.focus_binding (b);
                    return new SValue.empty ();
                case "requery":
                    view.requery_control (b);
                    return new SValue.empty ();
                case "undo":
                    view.load_record ();
                    return new SValue.empty ();
            }
            if (b.subview != null) return b.subview.me.get_member (name, args);
            throw Script.fail (438, _("The control does not support \"%s\".").printf (name));
        }

        public override SValue call_method (string name, SValue[] args, string[] names) throws ScriptError {
            return get_member (name, args);
        }

        public override void set_member (string name, SValue[] args, SValue value) throws ScriptError {
            switch (name.down ()) {
                case "value":
                case "text":
                    view.set_control_value (b, value);
                    return;
                case "visible":
                    b.visible = value.to_bool ();
                    break;
                case "enabled":
                    b.enabled = value.to_bool ();
                    break;
                case "locked":
                    b.locked = value.to_bool ();
                    break;
                case "caption":
                    b.caption = value.to_text ();
                    break;
                case "forecolor":
                    b.fore = Styling.vba_color (value.to_int ());
                    break;
                case "backcolor":
                    b.back = Styling.vba_color (value.to_int ());
                    break;
                case "fontbold":
                    b.bold = value.to_bool ();
                    break;
                case "rowsource":
                    b.c.row_source = value.to_text ();
                    view.requery_control (b);
                    return;
                default:
                    throw Script.fail (438, _("The control does not support \"%s\".").printf (name));
            }
            view.apply_binding_state (b);
        }
    }

    public class FormObject : ScriptObject {
        private weak FormView view;

        public FormObject (FormView view) {
            this.view = view;
        }

        public override string type_name () {
            return "Form_" + view.def.name;
        }

        public override bool has_member (string name) {
            if (view.binding (name) != null) return true;
            if (view.src != null && view.src.def.find (name) != null) return true;
            switch (name.down ()) {
                case "dirty":
                case "newrecord":
                case "filter":
                case "filteron":
                case "orderby":
                case "orderbyon":
                case "recordsource":
                case "caption":
                case "openargs":
                case "currentrecord":
                case "name":
                case "allowedits":
                case "allowadditions":
                case "allowdeletions":
                case "dataentry":
                case "recordcount":
                case "parent":
                case "form":
                    return true;
            }
            return false;
        }

        public override SValue get_default (SValue[] args) throws ScriptError {
            if (args.length == 0) return new SValue.object (this);
            return bang (args[0].to_text ());
        }

        public override SValue bang (string name) throws ScriptError {
            var b = view.binding (name);
            if (b != null) return new SValue.object (new ControlObject (view, b));
            if (view.src != null && view.src.def.find (name) != null) return view.field_value (name);
            throw Script.fail (2465, _("\"%s\" is not a control or field of the form.").printf (name));
        }

        public override void set_bang (string name, SValue value) throws ScriptError {
            var b = view.binding (name);
            if (b != null) {
                view.set_control_value (b, value);
                return;
            }
            view.set_field_value (name, value);
        }

        public override SValue get_member (string name, SValue[] args) throws ScriptError {
            switch (name.down ()) {
                case "dirty": return new SValue.bool (view.record_dirty);
                case "newrecord": return new SValue.bool (view.new_mode);
                case "filter": return new SValue.str (view.filter);
                case "filteron": return new SValue.bool (view.filter_on);
                case "orderby": return new SValue.str (view.order_by);
                case "orderbyon": return new SValue.bool (view.order_by != "");
                case "recordsource": return new SValue.str (view.def.source);
                case "caption": return new SValue.str (view.def.title);
                case "openargs": return view.open_args != "" ? new SValue.str (view.open_args) : new SValue.null ();
                case "currentrecord": return new SValue.int (view.position + 1);
                case "recordcount": return new SValue.int (view.src != null ? view.src.count () : 0);
                case "name": return new SValue.str (view.def.name);
                case "form": return new SValue.object (this);
                case "allowedits": return new SValue.bool (view.def.allow_edit);
                case "allowadditions": return new SValue.bool (view.def.allow_add);
                case "allowdeletions": return new SValue.bool (view.def.allow_delete);
                case "dataentry": return new SValue.bool (view.def.data_entry);
                case "parent":
                    if (view.parent_view != null) return new SValue.object (view.parent_view.me);
                    throw Script.fail (2452, _("The form has no parent."));
                case "requery":
                    view.requery ();
                    return new SValue.empty ();
                case "refresh":
                case "recalc":
                    view.recalc ();
                    return new SValue.empty ();
                case "undo":
                    view.load_record ();
                    return new SValue.empty ();
            }
            return bang (name);
        }

        public override SValue call_method (string name, SValue[] args, string[] names) throws ScriptError {
            switch (name.down ()) {
                case "requery":
                case "refresh":
                case "recalc":
                case "undo":
                    return get_member (name, args);
                case "setfocus":
                    return new SValue.empty ();
                case "gotorecord":
                    view.go (args.length > 0 ? args[0].to_int () - 1 : 0);
                    return new SValue.empty ();
            }
            return get_member (name, args);
        }

        public override void set_member (string name, SValue[] args, SValue value) throws ScriptError {
            switch (name.down ()) {
                case "filter":
                    view.filter = value.to_text ();
                    if (view.filter_on) view.apply_filter ();
                    return;
                case "filteron":
                    view.filter_on = value.to_bool ();
                    view.apply_filter ();
                    return;
                case "orderby":
                    view.order_by = value.to_text ();
                    view.apply_filter ();
                    return;
                case "orderbyon":
                    if (!value.to_bool ()) {
                        view.order_by = "";
                        view.apply_filter ();
                    }
                    return;
                case "caption":
                    view.def.title = value.to_text ();
                    view.refresh_title ();
                    return;
                case "recordsource":
                    view.def.source = value.to_text ();
                    view.rebuild ();
                    return;
                case "allowedits":
                    view.def.allow_edit = value.to_bool ();
                    view.load_record ();
                    return;
                case "allowadditions":
                    view.def.allow_add = value.to_bool ();
                    return;
                case "allowdeletions":
                    view.def.allow_delete = value.to_bool ();
                    return;
            }
            set_bang (name, value);
        }
    }

    public class FormView : Box {
        public weak DatabaseWindow win;
        public FormDef def;
        public RecordSource? src;
        public FormObject me;
        public weak FormView? parent_view;
        public string module_name;
        public int64 position;
        public bool new_mode;
        public bool record_dirty;
        public string filter = "";
        public bool filter_on;
        public string order_by = "";
        public string open_args = "";
        public string where_arg = "";
        public string view_override = "";
        public bool read_only_mode;
        public bool embedded;
        public Gee.ArrayList<CtlBinding> bindings = new Gee.ArrayList<CtlBinding> ();
        private Gee.ArrayList<Gee.ArrayList<CtlBinding>> row_bindings = new Gee.ArrayList<Gee.ArrayList<CtlBinding>> ();
        private Gee.ArrayList<int64?> row_index = new Gee.ArrayList<int64?> ();
        private Entry? record_entry;
        private Label? count_label;
        private Label? state_label;
        private Label? title_label;
        private Stack? body_stack;
        private DatasheetView? sheet;
        private bool loading_record;
        private bool opened;
        private CtlBinding? focused;
        private int continuous_page;

        public signal void state_changed ();

        public FormView (DatabaseWindow win, FormDef def, FormView? parent = null) {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            this.win = win;
            this.def = def;
            this.parent_view = parent;
            embedded = parent != null;
            module_name = "Form_" + def.name;
            me = new FormObject (this);
            if (def.code.strip () != "" && win.runtime != null) {
                try {
                    win.runtime.load_module (def.code, module_name);
                } catch (Error e) {
                    win.host.debug_print (_("Code of form %s: %s").printf (def.name, e.message));
                }
            }
            filter = def.filter;
            filter_on = def.filter_on_load && def.filter != "";
            order_by = def.sort;
        }

        public string current_view () {
            if (view_override != "") return view_override;
            return def.default_view;
        }

        public bool fire (string object_name, string event_name, string handler, SValue[] extra = {}) {
            if (handler.strip () == "" || win.runtime == null) return false;
            try {
                bool cancel;
                EventHandler.fire (win.runtime, me, module_name, object_name, event_name, handler, extra, out cancel);
                return cancel;
            } catch (Error e) {
                if (e is ScriptError.CANCELLED) return true;
                win.show_error (_("Error in %s %s").printf (object_name, event_name), e.message);
                return true;
            }
        }

        public bool fire_form (string ev) {
            string h = def.events[ev] ?? "";
            if (h == "") return false;
            return fire ("Form", ev, h);
        }

        private bool fire_control (CtlBinding b, string ev) {
            string h = b.c.events[ev] ?? "";
            if (h == "") return false;
            return fire (b.c.display_name ().replace (" ", "_"), ev, h);
        }

        public CtlBinding? binding (string name) {
            foreach (var b in bindings) {
                if (b.c.display_name ().casefold () == name.casefold ()) return b;
            }
            foreach (var b in bindings) {
                if (b.c.is_bound () && b.c.field.casefold () == name.casefold ()) return b;
            }
            return null;
        }

        public SValue field_value (string name) throws ScriptError {
            foreach (var b in bindings) {
                if (b.c.is_bound () && b.c.field.casefold () == name.casefold ()) return control_value (b);
            }
            if (src == null) return new SValue.null ();
            var row = new_mode ? null : src.row (position);
            if (row == null) return new SValue.null ();
            int i = src.def.index_of (name);
            if (i < 0) return new SValue.null ();
            return SValue.from_db (row.get (i), src.def.fields[i].field_type);
        }

        public void set_field_value (string name, SValue value) throws ScriptError {
            foreach (var b in bindings) {
                if (b.c.is_bound () && b.c.field.casefold () == name.casefold ()) {
                    set_control_value (b, value);
                    return;
                }
            }
            if (src == null || new_mode) return;
            var row = src.row (position);
            if (row == null) return;
            try {
                var f = src.def.find (name);
                if (f == null) throw Script.fail (2465, _("\"%s\" is not a field of the form.").printf (name));
                src.set_value (row.rowid, f.name, value.to_db ());
                load_record ();
            } catch (ScriptError e) {
                throw e;
            } catch (Error e) {
                throw Script.fail (3164, e.message);
            }
        }

        public SValue control_value (CtlBinding b) throws ScriptError {
            if (b.fc == null) return new SValue.str (b.caption);
            if (!b.c.is_bound () && !b.c.is_calculated ()) return SValue.from_field (b.unbound, b.field);
            try {
                var v = b.fc.get_value ();
                return b.field != null ? SValue.from_db (v, b.field.field_type) : SValue.from_db (v);
            } catch (Error e) {
                return new SValue.null ();
            }
        }

        public void set_control_value (CtlBinding b, SValue value) throws ScriptError {
            if (b.fc == null) {
                b.caption = value.to_text ();
                apply_binding_state (b);
                return;
            }
            var v = value.to_db ();
            if (b.field != null && v.kind == ValueKind.TEXT && !b.field.field_type.is_text () && b.c.is_bound ()) {
                try {
                    v = Codec.parse (b.field, v.text_value);
                } catch (Error e) {
                }
            }
            b.fc.set_value (v);
            if (!b.c.is_bound ()) {
                b.unbound = v;
                recalc ();
                return;
            }
            record_dirty = true;
            update_state ();
            recalc ();
        }

        public void focus_binding (CtlBinding b) {
            if (b.fc != null) b.fc.widget.grab_focus ();
            else b.widget.grab_focus ();
        }

        public void requery_control (CtlBinding b) {
            rebuild ();
        }

        public void apply_binding_state (CtlBinding b) {
            b.outer.visible = b.visible;
            b.widget.sensitive = b.enabled;
            if (b.fc != null) {
                bool editable = !b.locked && def.allow_edit && !read_only_mode && (src != null && (b.c.is_bound () ? src.field_updatable (b.c.field) : true));
                if (!b.c.is_bound () && !b.c.is_calculated ()) editable = !b.locked;
                if (b.c.is_calculated ()) editable = false;
                b.fc.set_editable (editable);
            }
            var btn = b.widget as Button;
            if (btn != null) btn.label = b.caption;
            var lab = b.widget as Label;
            if (lab != null && b.c.kind == ControlKind.LABEL) lab.label = b.caption;
            if (b.label != null) b.label.label = b.caption;
            Styling.apply (b.widget, b.fore, b.back, b.bold, b.c.italic, false, b.c.font_size);
        }

        public void refresh_title () {
            if (title_label != null) title_label.label = def.title;
        }

        public void rebuild () {
            Widget? child;
            while ((child = get_first_child ()) != null) remove (child);
            bindings.clear ();
            row_bindings.clear ();
            row_index.clear ();
            sheet = null;
            try {
                var st = new ViewState ();
                if (src != null && src.source == def.source) st = src.state;
                st.extra_where = combined_where ();
                st.sorts.clear ();
                if (order_by.strip () != "") {
                    foreach (string part in order_by.split (",")) {
                        string p = part.strip ();
                        bool desc = p.down ().has_suffix (" desc");
                        if (desc) p = p.substring (0, p.length - 5).strip ();
                        if (p.down ().has_suffix (" asc")) p = p.substring (0, p.length - 4).strip ();
                        if (p.has_prefix ("[") && p.has_suffix ("]")) p = p.substring (1, p.length - 2);
                        int dot = p.last_index_of ("].[");
                        if (dot > 0) p = p.substring (dot + 3);
                        if (p != "") st.sorts.add (new SortSpec (p, desc));
                    }
                }
                string s = def.source.strip ();
                if (s.down ().has_prefix ("select ")) {
                    src = new RecordSource.for_sql (win.db, AccessSql.statement (s));
                    src.state = st;
                } else {
                    var saved = win.db.object_exists (s) ? null : SavedQueries.load (win.db, s);
                    if (saved != null) {
                        var ps = QueryPrep.find_parameters (win.db, saved.sql);
                        foreach (var p in ps) {
                            var v = win.reference_value (p.name);
                            if (v != null) p.value = v;
                        }
                        src = new RecordSource.for_sql (win.db, QueryPrep.prepare (win.db, saved.sql, ps));
                        src.state = st;
                    } else {
                        src = new RecordSource (win.db, s, st);
                    }
                }
                src.invalidate ();
            } catch (Error e) {
                src = null;
                var sp = new StatusPage ();
                sp.icon_name = "dialog-error";
                sp.title = _("Record Source Missing");
                sp.description = _("\"%s\" could not be opened: %s").printf (def.source, e.message);
                sp.vexpand = true;
                append (sp);
                return;
            }
            if (!embedded && !opened) {
                opened = true;
                if (fire_form ("Open")) {
                    Idle.add (() => {
                        win.close_object ("form", def.name);
                        return Source.REMOVE;
                    });
                }
            }
            string v = current_view ();
            if (v == "navigation") {
                append (build_navigation ());
                return;
            }
            if (!embedded) {
                title_label = new Label (def.title);
                title_label.add_css_class ("db-form-title");
                title_label.halign = Align.START;
                title_label.margin_start = 32;
                title_label.margin_top = 8;
                append (title_label);
            }
            if (def.header_height > 0) append (section_panel ("header", def.header_height));
            switch (v) {
                case "datasheet":
                    append (build_datasheet ());
                    break;
                case "continuous":
                    append (build_continuous ());
                    break;
                case "split":
                    var paned = new Paned (Orientation.VERTICAL);
                    paned.vexpand = true;
                    var ds = build_datasheet ();
                    var single = build_single ();
                    if (def.split_position == "bottom") {
                        paned.start_child = single;
                        paned.end_child = ds;
                    } else {
                        paned.start_child = ds;
                        paned.end_child = single;
                    }
                    paned.position = 220;
                    append (paned);
                    break;
                default:
                    append (build_single ());
                    break;
            }
            if (def.footer_height > 0) append (section_panel ("footer", def.footer_height));
            if (def.navigation_buttons && v != "datasheet") append (build_nav ());
            position = 0;
            new_mode = def.data_entry && src.editable;
            load_record ();
            if (!embedded) fire_form ("Load");
        }

        private string combined_where () {
            string[] parts = {};
            if (where_arg.strip () != "") parts += "(" + where_arg + ")";
            if (filter_on && filter.strip () != "") parts += "(" + filter + ")";
            if (parent_view != null && link_filter != "") parts += "(" + link_filter + ")";
            return string.joinv (" And ", parts);
        }

        public string link_filter = "";

        public void apply_filter () {
            if (!commit_record ()) return;
            rebuild ();
        }

        private Widget build_navigation () {
            var box = new Box (Orientation.VERTICAL, 8);
            box.vexpand = true;
            var switcher = new BubbleSwitcher ();
            switcher.halign = Align.CENTER;
            switcher.margin_top = 8;
            var stack = new Stack ();
            stack.vexpand = true;
            foreach (string name in def.navigation) {
                var sub = FormDef.from_json (name, win.db.get_meta ("form:" + name));
                if (sub == null) continue;
                switcher.add_option (name, sub.title != "" ? sub.title : name);
                var holder = new Box (Orientation.VERTICAL, 0);
                holder.vexpand = true;
                stack.add_named (holder, name);
            }
            switcher.selected.connect ((n) => {
                var holder = stack.get_child_by_name (n) as Box;
                if (holder != null && holder.get_first_child () == null) {
                    var sub = FormDef.from_json (n, win.db.get_meta ("form:" + n));
                    if (sub != null) {
                        var fv = new FormView (win, sub, this);
                        fv.vexpand = true;
                        holder.append (fv);
                        fv.rebuild ();
                    }
                }
                stack.visible_child_name = n;
            });
            box.append (switcher);
            box.append (stack);
            if (def.navigation.length > 0) switcher.set_active (def.navigation[0]);
            return box;
        }

        private Widget build_datasheet () {
            var st = src.state;
            foreach (var f in src.def.fields) {
                bool shown = false;
                foreach (var c in def.controls) {
                    if (c.is_bound () && c.field.casefold () == f.name.casefold ()) shown = true;
                }
                if (!shown && def.controls.size > 0) st.hidden.add (f.name);
            }
            sheet = new DatasheetView ();
            sheet.set_source (src);
            sheet.read_only = !def.allow_edit;
            sheet.allow_new = def.allow_add;
            sheet.error.connect ((m) => win.toast (m));
            sheet.attachment_requested.connect ((rowid, f) => Dialogs.attachment (win, src, rowid, f));
            sheet.selection_changed.connect (() => {
                int64 idx = sheet.current_record_index ();
                if (idx >= 0 && idx != position && !loading_record) {
                    position = idx;
                    new_mode = false;
                    load_record ();
                }
            });
            var scroll = new ScrolledWindow ();
            scroll.vexpand = true;
            scroll.child = sheet;
            return scroll;
        }

        private Widget build_single () {
            var scroll = new ScrolledWindow ();
            scroll.vexpand = true;
            var sheet_box = new Box (Orientation.VERTICAL, 16);
            sheet_box.add_css_class ("db-form-sheet");
            sheet_box.margin_start = sheet_box.margin_end = 32;
            sheet_box.margin_bottom = 24;
            sheet_box.halign = Align.START;
            var panel = new Fixed ();
            int max_y = place_controls (panel, "detail", bindings, "");
            panel.height_request = max_y;
            sheet_box.append (panel);
            scroll.child = sheet_box;
            if (src.count () == 0 && !(src.editable && def.allow_add)) {
                var stack = new Stack ();
                stack.vexpand = true;
                stack.add_named (scroll, "record");
                var empty = new StatusPage ();
                empty.icon_name = "x-office-addressbook";
                empty.title = _("No Records");
                empty.description = _("The record source has no records.");
                stack.add_named (empty, "empty");
                stack.visible_child_name = "empty";
                return stack;
            }
            return scroll;
        }

        private Widget build_continuous () {
            var scroll = new ScrolledWindow ();
            scroll.vexpand = true;
            var box = new Box (Orientation.VERTICAL, 0);
            box.add_css_class ("db-form-sheet");
            box.add_css_class ("db-continuous");
            box.margin_start = box.margin_end = 24;
            int64 n = src.count ();
            int per_page = 60;
            int64 start = (int64) continuous_page * per_page;
            var head = new Fixed ();
            head.add_css_class ("db-continuous-head");
            int head_h = 0;
            foreach (var c in def.controls) {
                if (c.section != "detail" || c.parent != "" || c.label == "" || c.hide_label) continue;
                if (c.kind == ControlKind.BUTTON || c.kind == ControlKind.LABEL || c.kind == ControlKind.LINE || c.kind == ControlKind.RECTANGLE || c.kind == ControlKind.IMAGE) continue;
                var l = new Label (c.label);
                l.add_css_class ("db-form-label");
                l.xalign = 0;
                l.width_request = c.width;
                l.ellipsize = Pango.EllipsizeMode.END;
                head.put (l, c.x, 0);
                head_h = 22;
            }
            head.height_request = head_h;
            box.append (head);
            in_rows = true;
            for (int64 i = start; i < n && i < start + per_page; i++) {
                var row = src.row (i);
                if (row == null) break;
                var list = new Gee.ArrayList<CtlBinding> ();
                var panel = new Fixed ();
                panel.add_css_class ("db-continuous-row");
                int h = place_controls (panel, "detail", list, "");
                panel.height_request = int.max (36, h - 26);
                int64 idx = i;
                var click = new GestureClick ();
                click.set_propagation_phase (PropagationPhase.CAPTURE);
                click.pressed.connect (() => {
                    if (position != idx) {
                        if (!commit_continuous ()) return;
                        position = idx;
                        new_mode = false;
                        highlight_row ();
                        update_state ();
                        fire_form ("Current");
                    }
                });
                panel.add_controller (click);
                box.append (panel);
                row_bindings.add (list);
                row_index.add (idx);
                foreach (var b in list) {
                    load_binding (b, row);
                    var bb = b;
                    if (b.fc != null) b.fc.changed.connect (() => {
                        if (!loading_record) {
                            record_dirty = true;
                            bindings_for_current_dirty = true;
                            focused = bb;
                        }
                    });
                }
            }
            if (n > per_page) {
                var pager = new Box (Orientation.HORIZONTAL, 8);
                pager.halign = Align.CENTER;
                pager.margin_top = 8;
                var prev = new Button.with_label (_("Previous"));
                prev.sensitive = continuous_page > 0;
                prev.clicked.connect (() => {
                    continuous_page--;
                    rebuild ();
                });
                var next = new Button.with_label (_("Next"));
                next.sensitive = start + per_page < n;
                next.clicked.connect (() => {
                    continuous_page++;
                    rebuild ();
                });
                var lab = new Label (_("Records %s to %s of %s").printf ((start + 1).to_string (), int64.min (n, start + per_page).to_string (), n.to_string ()));
                lab.add_css_class ("dim-label");
                pager.append (prev);
                pager.append (lab);
                pager.append (next);
                box.append (pager);
            }
            in_rows = false;
            scroll.child = box;
            if (row_bindings.size > 0) bindings = row_bindings[0];
            return scroll;
        }

        private bool bindings_for_current_dirty;
        private bool in_rows;

        private void highlight_row () {
            for (int i = 0; i < row_bindings.size; i++) {
                bool cur = row_index[i] == position;
                if (cur) bindings = row_bindings[i];
                foreach (var b in row_bindings[i]) {
                    var p = b.outer.get_parent ();
                    if (p != null) {
                        if (cur) p.add_css_class ("selected");
                        else p.remove_css_class ("selected");
                    }
                }
            }
        }

        private bool commit_continuous () {
            if (!record_dirty) return true;
            return commit_record ();
        }

        private Widget section_panel (string section, int height) {
            var panel = new Fixed ();
            panel.add_css_class ("db-form-section");
            panel.margin_start = panel.margin_end = 32;
            int h = place_controls (panel, section, bindings, "");
            panel.height_request = int.max (height, h);
            return panel;
        }

        private int place_controls (Fixed panel, string section, Gee.ArrayList<CtlBinding> list, string parent) {
            int max_y = 0;
            var sorted = new Gee.ArrayList<FormControl> ();
            foreach (var c in def.controls) {
                if (c.section != section || c.parent != parent) continue;
                sorted.add (c);
            }
            sorted.sort ((a, b) => {
                int ta = a.tab_index >= 0 ? a.tab_index : 10000 + a.y * 10 + a.x / 100;
                int tb = b.tab_index >= 0 ? b.tab_index : 10000 + b.y * 10 + b.x / 100;
                return ta - tb;
            });
            foreach (var c in sorted) {
                var b = make_binding (c, list);
                if (b == null) continue;
                panel.put (b.outer, c.x, c.y);
                list.add (b);
                max_y = int.max (max_y, c.y + (c.height > 0 ? c.height : 60));
                if (c.kind == ControlKind.TAB && b.notebook != null) {
                    for (int p = 0; p < c.pages.length; p++) {
                        var page = b.notebook.get_nth_page (p) as Fixed;
                        if (page == null) continue;
                        int ph = place_controls (page, section, list, "%s:%d".printf (c.display_name (), p));
                        page.height_request = ph;
                    }
                }
            }
            return max_y;
        }

        private CtlBinding? make_binding (FormControl c, Gee.ArrayList<CtlBinding> list) {
            var b = new CtlBinding (c);
            Field? f = null;
            if (c.is_bound ()) {
                f = src.def.find (c.field);
                if (f == null) return null;
            }
            b.field = f;
            var block = new Box (Orientation.VERTICAL, 4);
            block.width_request = c.width;
            int h = c.height > 0 ? c.height : 60;
            bool with_label = !in_rows && c.kind != ControlKind.LABEL && c.kind != ControlKind.BUTTON && c.kind != ControlKind.TAB && c.kind != ControlKind.IMAGE && c.kind != ControlKind.LINE && c.kind != ControlKind.RECTANGLE && c.kind != ControlKind.TOGGLE && !c.hide_label && c.label != "";
            if (with_label) {
                var l = new Label (c.label);
                l.add_css_class ("db-form-label");
                l.halign = Align.START;
                block.append (l);
                b.label = l;
                b.caption = c.label;
            }
            int inner_h = with_label ? int.max (34, h - 26) : (in_rows ? int.max (34, h - 26) : h);
            switch (c.kind) {
                case ControlKind.BUTTON:
                    var btn = new Button.with_label (c.caption != "" ? c.caption : c.display_name ());
                    btn.height_request = h;
                    btn.clicked.connect (() => {
                        if (!commit_before_command ()) return;
                        fire_control (b, "Click");
                    });
                    b.widget = btn;
                    b.caption = btn.label;
                    block.append (btn);
                    break;
                case ControlKind.LABEL:
                    if (c.field != "" && !c.is_calculated ()) {
                        var lf = new Field (c.field, FieldType.TEXT);
                        b.fc = new LabelControl (f ?? lf, src);
                        b.widget = b.fc.widget;
                    } else {
                        var lab = new Label (c.caption != "" ? c.caption : c.label);
                        lab.wrap = true;
                        lab.xalign = 0;
                        lab.halign = Align.START;
                        b.caption = lab.label;
                        b.widget = lab;
                    }
                    block.append (b.widget);
                    break;
                case ControlKind.IMAGE:
                    var pic = new Picture ();
                    pic.content_fit = ContentFit.CONTAIN;
                    pic.height_request = h;
                    if (c.image != "") {
                        try {
                            pic.paintable = Gdk.Texture.from_bytes (new Bytes (Base64.decode (c.image)));
                        } catch (Error e) {
                        }
                    }
                    b.widget = pic;
                    block.append (pic);
                    break;
                case ControlKind.LINE:
                case ControlKind.RECTANGLE:
                    var area = new DrawingArea ();
                    area.content_width = c.width;
                    area.content_height = h;
                    bool line = c.kind == ControlKind.LINE;
                    string color = c.fore_color;
                    area.set_draw_func ((a, cr, w, hh) => {
                        var rgba = Gdk.RGBA ();
                        if (color == "" || !rgba.parse (color)) rgba = a.get_color ();
                        cr.set_source_rgba (rgba.red, rgba.green, rgba.blue, line ? 0.6 : 0.35);
                        cr.set_line_width (1);
                        if (line) {
                            cr.move_to (0, hh <= 4 ? hh / 2.0 : 0);
                            cr.line_to (w, hh <= 4 ? hh / 2.0 : hh);
                        } else {
                            cr.rectangle (0.5, 0.5, w - 1, hh - 1);
                        }
                        cr.stroke ();
                    });
                    b.widget = area;
                    block.append (area);
                    break;
                case ControlKind.TAB:
                    var nb = new Gtk.Notebook ();
                    nb.height_request = h;
                    foreach (string p in c.pages) {
                        var page = new Fixed ();
                        page.margin_start = page.margin_top = page.margin_end = page.margin_bottom = 12;
                        nb.append_page (page, new Label (p));
                    }
                    nb.switch_page.connect (() => fire_control (b, "Change"));
                    b.notebook = nb;
                    b.widget = nb;
                    block.append (nb);
                    break;
                case ControlKind.SUBFORM:
                    var subdef = FormDef.from_json (c.subform, win.db.get_meta ("form:" + c.subform));
                    if (subdef == null) {
                        var missing = new Label (_("The form \"%s\" does not exist.").printf (c.subform));
                        missing.add_css_class ("dim-label");
                        b.widget = missing;
                        block.append (missing);
                        break;
                    }
                    var sv = new FormView (win, subdef, this);
                    sv.height_request = inner_h;
                    sv.add_css_class ("db-subform");
                    b.subview = sv;
                    b.widget = sv;
                    block.append (sv);
                    break;
                case ControlKind.CHART:
                    var ch = new ChartWidget ();
                    ch.chart_type = c.chart_type;
                    ch.height_request = inner_h;
                    b.chart = ch;
                    b.widget = ch;
                    block.append (ch);
                    break;
                default:
                    FieldControl fc;
                    if (c.is_calculated ()) {
                        var cf = new Field (c.display_name (), FieldType.TEXT);
                        cf.format = c.format;
                        fc = new CalcControl (cf);
                        b.field = cf;
                    } else if (f == null) {
                        var uf = new Field (c.display_name (), FieldType.TEXT);
                        uf.format = c.format;
                        b.field = uf;
                        switch (c.kind) {
                            case ControlKind.COMBO: fc = new ComboControl (uf, win.db, c, false); break;
                            case ControlKind.LIST: fc = new ComboControl (uf, win.db, c, true); break;
                            case ControlKind.CHECK: fc = new CheckControl (uf); break;
                            case ControlKind.TOGGLE: fc = new ToggleControl (uf, c.caption); break;
                            case ControlKind.OPTION_GROUP: fc = new OptionGroupControl (uf, win.db, c); break;
                            case ControlKind.DATE:
                                uf.field_type = FieldType.DATE;
                                fc = new DateControl (uf);
                                break;
                            default: fc = new UnboundControl (uf); break;
                        }
                        if (c.default_value != "") {
                            try {
                                b.unbound = win.runtime.evaluate (c.default_value.has_prefix ("=") ? c.default_value.substring (1) : c.default_value, me).to_db ();
                                fc.set_value (b.unbound);
                            } catch (Error e) {
                            }
                        }
                    } else {
                        switch (c.kind) {
                            case ControlKind.COMBO: fc = new ComboControl (f, win.db, c, false); break;
                            case ControlKind.LIST: fc = new ComboControl (f, win.db, c, true); break;
                            case ControlKind.OPTION_GROUP: fc = new OptionGroupControl (f, win.db, c); break;
                            case ControlKind.TOGGLE: fc = new ToggleControl (f, c.caption); break;
                            case ControlKind.CHECK_LIST: fc = new CheckListControl (f, win.db, src); break;
                            case ControlKind.RICH_TEXT: fc = new RichTextControl (f); break;
                            default:
                                var k = c.kind == ControlKind.AUTO ? ControlKind.for_field (f) : c.kind;
                                if (k == ControlKind.CHECK_LIST) fc = new CheckListControl (f, win.db, src);
                                else if (k == ControlKind.RICH_TEXT) fc = new RichTextControl (f);
                                else fc = FieldControl.create (win, src, f, c.kind);
                                break;
                        }
                    }
                    if (fc is MultilineControl || fc is AttachmentControl || fc is RichTextControl || fc is CheckListControl || (fc is ComboControl && c.kind == ControlKind.LIST)) fc.widget.height_request = inner_h;
                    b.fc = fc;
                    b.widget = fc.widget;
                    if (c.status_text != "") fc.widget.tooltip_text = c.status_text;
                    fc.changed.connect (() => {
                        if (loading_record) return;
                        b.changed_since_focus = true;
                        if (c.is_bound ()) {
                            bool was = record_dirty;
                            if (!was && !new_mode) {
                                string lt;
                                int64 lid;
                                if (src.lock_target (position, out lt, out lid)) {
                                    if (!win.lock_record (lt, lid)) {
                                        load_record ();
                                        return;
                                    }
                                    locked_table = lt;
                                    locked_id = lid;
                                }
                            }
                            record_dirty = true;
                            if (!was) fire_form ("Dirty");
                            update_state ();
                        } else {
                            try {
                                b.unbound = fc.get_value ();
                            } catch (Error e) {
                            }
                        }
                        fire_control (b, "Change");
                        if (!(fc is TextControl) && !(fc is UnboundControl) && !(fc is MultilineControl) && !(fc is RichTextControl)) control_updated (b);
                    });
                    var focus = new EventControllerFocus ();
                    focus.enter.connect (() => {
                        focused = b;
                        b.changed_since_focus = false;
                        try {
                            b.focus_value = fc.get_value ();
                        } catch (Error e) {
                        }
                        fire_control (b, "GotFocus");
                    });
                    focus.leave.connect (() => {
                        if (b.changed_since_focus) control_updated (b);
                        fire_control (b, "LostFocus");
                    });
                    fc.widget.add_controller (focus);
                    block.append (fc.widget);
                    break;
            }
            var dbl = new GestureClick ();
            dbl.pressed.connect ((n, x, y) => {
                if (n == 2) fire_control (b, "DblClick");
                else if (c.kind != ControlKind.BUTTON && (c.events["Click"] ?? "") != "") fire_control (b, "Click");
            });
            b.widget.add_controller (dbl);
            b.outer = block;
            apply_binding_state (b);
            return b;
        }

        private bool commit_before_command () {
            return true;
        }

        private void control_updated (CtlBinding b) {
            b.changed_since_focus = false;
            if (b.c.validation_rule != "" && win.runtime != null) {
                try {
                    var v = control_value (b);
                    var rule = AccessRule.is_short_form (b.c.validation_rule) ? "[__v] " + b.c.validation_rule : b.c.validation_rule;
                    var scope = new ValueScope (me, "__v", v);
                    if (!ScriptRuntime.truth (win.runtime.evaluate (rule, scope))) {
                        win.show_error (_("Invalid Value"), b.c.validation_text != "" ? b.c.validation_text : _("The value does not satisfy the validation rule %s.").printf (b.c.validation_rule));
                        b.fc.set_value (b.focus_value);
                        return;
                    }
                } catch (Error e) {
                }
            }
            if (fire_control (b, "BeforeUpdate")) {
                if (b.fc != null) b.fc.set_value (b.focus_value);
                return;
            }
            try {
                b.focus_value = b.fc.get_value ();
            } catch (Error e) {
            }
            fire_control (b, "AfterUpdate");
            recalc ();
        }

        public void recalc () {
            foreach (var b in bindings) {
                if (b.c.is_calculated () && b.fc != null && win.runtime != null) {
                    try {
                        var v = win.runtime.evaluate (b.c.field.substring (1), new FormAggregateScope (this), me, new FormAggregates (this));
                        b.fc.set_value (v.to_db ());
                    } catch (Error e) {
                        b.fc.set_value (new DbValue.text ("#" + _("Error")));
                    }
                }
                if (b.chart != null) {
                    string where = "";
                    if (b.c.link_master != "" && b.c.link_child != "") {
                        try {
                            var mv = field_value (b.c.link_master);
                            where = "%s = %s".printf (Sql.quote_ident (b.c.link_child), mv.to_db ().sql_literal ());
                        } catch (Error e) {
                        }
                    }
                    b.chart.data = ChartData.load (win.db, b.c.chart_source, b.c.chart_category, b.c.chart_value, b.c.chart_aggregate, b.c.chart_series, where);
                    b.chart.queue_draw ();
                }
            }
            apply_conditions ();
        }

        private void apply_conditions () {
            if (win.runtime == null) return;
            var ev = new CondEval ();
            foreach (var b in bindings) {
                if (b.c.conditions.size == 0) continue;
                DbValue v = new DbValue.null ();
                try {
                    if (b.fc != null) v = b.fc.get_value ();
                } catch (Error e) {
                }
                var hit = ev.first_match (b.c.conditions, b.c.display_name (), b.field, v, win.runtime, me);
                if (hit != null) Styling.apply (b.widget, hit.fore, hit.back, hit.bold, hit.italic, hit.underline, b.c.font_size);
                else Styling.apply (b.widget, b.fore, b.back, b.bold, b.c.italic, false, b.c.font_size);
            }
        }

        private void load_binding (CtlBinding b, Row? row) {
            if (b.fc == null || !b.c.is_bound ()) return;
            if (row == null) {
                DbValue v = new DbValue.null ();
                string d = b.c.default_value != "" ? b.c.default_value : (b.field != null ? b.field.default_value : "");
                if (new_mode && d != "" && b.field != null && b.field.field_type != FieldType.AUTONUMBER) {
                    try {
                        if (win.runtime != null && (d.has_prefix ("=") || d.contains ("(") || d.has_prefix ("["))) v = win.runtime.evaluate (d.has_prefix ("=") ? d.substring (1) : d, me).to_db ();
                        else v = Codec.parse (b.field, d);
                        if (v.kind == ValueKind.TEXT && b.field.field_type.is_temporal ()) v = Codec.parse (b.field, v.text_value);
                    } catch (Error e) {
                        v = new DbValue.null ();
                    }
                }
                b.fc.set_value (v);
                var ac = b.fc as AttachmentControl;
                if (ac != null) ac.rowid = -1;
                return;
            }
            int i = src.def.index_of (b.c.field);
            b.fc.set_value (i >= 0 ? row.get (i) : new DbValue.null ());
            var ac = b.fc as AttachmentControl;
            if (ac != null) ac.rowid = row.rowid;
        }

        private string locked_table = "";
        private int64 locked_id = -1;

        private void release_lock () {
            if (locked_table != "") win.unlock_record (locked_table, locked_id);
            locked_table = "";
            locked_id = -1;
        }

        public void load_record () {
            if (src == null) return;
            release_lock ();
            loading_record = true;
            record_dirty = false;
            Row? row = new_mode ? null : src.row (position);
            if (row_bindings.size > 0) {
                highlight_row ();
            } else {
                foreach (var b in bindings) load_binding (b, row);
            }
            foreach (var b in bindings) {
                if (b.subview != null) {
                    string cond = "";
                    if (b.c.link_master != "" && b.c.link_child != "") {
                        string[] ms = b.c.link_master.split (";");
                        string[] cs = b.c.link_child.split (";");
                        string[] parts = {};
                        for (int k = 0; k < ms.length && k < cs.length; k++) {
                            SValue mv;
                            try {
                                mv = field_value (ms[k].strip ());
                            } catch (Error e) {
                                mv = new SValue.null ();
                            }
                            var dv = mv.to_db ();
                            parts += dv.is_null ? "1 = 0" : "[%s] = %s".printf (cs[k].strip (), dv.kind == ValueKind.TEXT ? "'" + dv.text_value.replace ("'", "''") + "'" : dv.to_string ());
                        }
                        cond = string.joinv (" And ", parts);
                    }
                    b.subview.link_filter = cond;
                    b.subview.rebuild ();
                }
            }
            if (sheet != null && !new_mode && position >= 0) {
                if (sheet.current_record_index () != position) sheet.select_record (position);
            }
            loading_record = false;
            recalc ();
            update_state ();
            if (!embedded || true) fire_form ("Current");
        }

        public bool commit_record () {
            if (src == null || !record_dirty) return true;
            if (fire_form ("BeforeUpdate")) return false;
            bool inserting = new_mode;
            if (inserting && fire_form ("BeforeInsert")) return false;
            string[] cols = {};
            DbValue[] vals = {};
            try {
                Row? row = new_mode ? null : src.row (position);
                foreach (var b in bindings) {
                    if (b.fc == null || !b.c.is_bound () || b.field == null) continue;
                    if (b.field.field_type == FieldType.AUTONUMBER || b.field.field_type == FieldType.ATTACHMENT || b.fc is LabelControl || b.field.is_calculated ()) continue;
                    if (!src.field_updatable (b.field.name)) continue;
                    var v = b.fc.get_value ();
                    if (row != null) {
                        var o = row.get (src.def.index_of (b.field.name));
                        if (o.kind == v.kind && o.equals (v)) continue;
                        cols += b.field.name;
                        vals += v;
                    } else if (!v.is_null) {
                        cols += b.field.name;
                        vals += v;
                    }
                }
                if (parent_view != null && inserting) {
                    foreach (var pb in parent_view.bindings) {
                        if (pb.subview != this || pb.c.link_child == "") continue;
                        string[] ms = pb.c.link_master.split (";");
                        string[] cs = pb.c.link_child.split (";");
                        for (int k = 0; k < ms.length && k < cs.length; k++) {
                            bool present = false;
                            foreach (string x in cols) if (x.casefold () == cs[k].strip ().casefold ()) present = true;
                            if (present) continue;
                            cols += cs[k].strip ();
                            vals += parent_view.field_value (ms[k].strip ()).to_db ();
                        }
                    }
                }
                if (row == null) {
                    int64 id = src.add_row (cols, vals);
                    new_mode = false;
                    int64 idx = src.index_of_rowid (id);
                    position = idx >= 0 ? idx : src.count () - 1;
                } else {
                    for (int i = 0; i < cols.length; i++) src.set_value (row.rowid, cols[i], vals[i]);
                    src.invalidate ();
                    int64 idx = src.index_of_rowid (row.rowid);
                    if (idx >= 0) position = idx;
                }
                record_dirty = false;
                if (inserting) fire_form ("AfterInsert");
                fire_form ("AfterUpdate");
                if (row_bindings.size > 0) {
                    rebuild ();
                    return true;
                }
                load_record ();
                return true;
            } catch (Error e) {
                win.show_error (_("Could Not Save the Record"), e.message);
                return false;
            }
        }

        public void go (int64 pos) {
            if (src == null) return;
            if (!commit_record ()) return;
            int64 n = src.count ();
            new_mode = false;
            position = n == 0 ? 0 : pos.clamp (0, n - 1);
            if (row_bindings.size > 0) {
                int per_page = 60;
                int want = (int) (position / per_page);
                if (want != continuous_page) {
                    continuous_page = want;
                    rebuild ();
                    return;
                }
            }
            load_record ();
        }

        public void go_new () {
            if (src == null || !src.editable || !def.allow_add) return;
            if (!commit_record ()) return;
            if (row_bindings.size > 0 || sheet != null && current_view () == "datasheet") {
                Dialogs.record_editor (win, src, -1);
                return;
            }
            new_mode = true;
            load_record ();
            foreach (var b in bindings) {
                if (b.fc != null && b.c.is_bound () && b.field != null && b.field.field_type != FieldType.AUTONUMBER) {
                    b.fc.widget.grab_focus ();
                    break;
                }
            }
        }

        public void delete_current () {
            if (src == null || new_mode) {
                new_mode = false;
                go (position);
                return;
            }
            var row = src.row (position);
            if (row == null || !def.allow_delete) return;
            if (fire_form ("Delete")) return;
            int64 id = row.rowid;
            var dlg = new ConfirmDialog (win.app, _("Delete This Record?"), "user-trash", _("You can undo this with Ctrl+Z."), _("Delete"), ConfirmDialog.ActionStyle.DESTRUCTIVE);
            dlg.transient_for = win;
            dlg.response.connect ((r) => {
                if (r != ConfirmDialog.Response.PRIMARY) return;
                try {
                    src.delete ({ id });
                    record_dirty = false;
                    fire_form ("AfterDelConfirm");
                    if (row_bindings.size > 0) rebuild ();
                    else go (position);
                } catch (Error e) {
                    win.show_error (_("Could Not Delete"), e.message);
                }
            });
            dlg.present ();
        }

        public void requery () {
            if (!commit_record ()) return;
            int64 keep = position;
            rebuild ();
            go (keep);
        }

        private delegate void Click ();

        private Button tool (string icon, string tip, owned Click cb) {
            var b = new Button.from_icon_name (icon);
            b.add_css_class ("flat");
            b.add_css_class ("db-tool");
            b.tooltip_text = tip;
            b.clicked.connect (() => cb ());
            return b;
        }

        private Widget build_nav () {
            var bar = new Box (Orientation.HORIZONTAL, 4);
            bar.add_css_class ("db-record-bar");
            bar.append (tool ("db-first-symbolic", _("First Record (Alt+Home)"), () => go (0)));
            bar.append (tool ("go-previous-symbolic", _("Previous Record (Alt+Page Up)"), () => go (position - 1)));
            var rec = new Label (_("Record"));
            rec.add_css_class ("db-status");
            bar.append (rec);
            record_entry = new Entry ();
            record_entry.width_chars = 4;
            record_entry.max_width_chars = 6;
            record_entry.xalign = 1;
            record_entry.add_css_class ("db-record-number");
            record_entry.activate.connect (() => {
                int64 n = int64.parse (record_entry.text);
                if (n >= 1) go (n - 1);
            });
            bar.append (record_entry);
            count_label = new Label ("");
            count_label.add_css_class ("db-status");
            count_label.add_css_class ("dim-label");
            bar.append (count_label);
            bar.append (tool ("go-next-symbolic", _("Next Record (Alt+Page Down)"), () => go (position + 1)));
            bar.append (tool ("db-last-symbolic", _("Last Record (Alt+End)"), () => go (src.count () - 1)));
            if (src.editable && def.allow_add) bar.append (tool ("db-record-new-symbolic", _("New Record (Ctrl++)"), () => go_new ()));
            if (src.editable && def.allow_delete) bar.append (tool ("user-trash-symbolic", _("Delete Record (Ctrl+-)"), () => delete_current ()));
            state_label = new Label ("");
            state_label.hexpand = true;
            state_label.halign = Align.END;
            state_label.add_css_class ("db-status");
            state_label.add_css_class ("dim-label");
            bar.append (state_label);
            if (filter_on || where_arg != "") {
                var fl = new Button.with_label (_("Filtered"));
                fl.tooltip_text = _("Remove the filter");
                fl.clicked.connect (() => {
                    filter_on = false;
                    where_arg = "";
                    apply_filter ();
                });
                bar.append (fl);
            }
            if (src.editable && def.allow_edit) {
                var save_btn = new Button.with_label (_("Save Record"));
                save_btn.clicked.connect (() => commit_record ());
                bar.append (save_btn);
                var undo_btn = new Button.with_label (_("Revert"));
                undo_btn.tooltip_text = _("Discard the changes to this record");
                undo_btn.clicked.connect (() => {
                    record_dirty = false;
                    new_mode = false;
                    load_record ();
                });
                bar.append (undo_btn);
            }
            return bar;
        }

        public void update_state () {
            if (src == null) return;
            if (record_entry != null) {
                int64 n = src.count ();
                string rec = "0";
                if (new_mode) rec = "*";
                else if (n > 0) rec = (position + 1).to_string ();
                record_entry.text = rec;
                count_label.label = _("of %s").printf (Codec.format_number (n, 0, true));
                state_label.label = new_mode ? _("New record") : (record_dirty ? _("Edited, not saved yet") : "");
            }
            state_changed ();
        }
    }

    public class ValueScope : ScriptObject {
        private ScriptObject? inner;
        private string name;
        private SValue value;

        public ValueScope (ScriptObject? inner, string name, SValue value) {
            this.inner = inner;
            this.name = name;
            this.value = value;
        }

        public override bool has_member (string n) {
            return n == name || (inner != null && inner.has_member (n));
        }

        public override SValue get_member (string n, SValue[] args) throws ScriptError {
            if (n == name) return value;
            if (inner != null) return inner.get_member (n, args);
            return base.get_member (n, args);
        }
    }

    public class FormAggregateScope : ScriptObject {
        private weak FormView view;

        public FormAggregateScope (FormView view) {
            this.view = view;
        }

        public override bool has_member (string name) {
            return view.me.has_member (name);
        }

        public override SValue get_member (string name, SValue[] args) throws ScriptError {
            return view.me.get_member (name, args);
        }
    }

    public class FormAggregates : Object, AggregateProvider {
        private weak FormView view;

        public FormAggregates (FormView view) {
            this.view = view;
        }

        public bool aggregate (string function, SExpr? argument, ScriptRuntime rt, SFrame frame, out SValue result) throws ScriptError {
            result = new SValue.null ();
            string fn = function.down ();
            if (fn != "sum" && fn != "avg" && fn != "count" && fn != "min" && fn != "max") return false;
            if (view.src == null) return false;
            if (argument == null) {
                if (fn == "count") {
                    result = new SValue.int (view.src.count ());
                    return true;
                }
                return false;
            }
            double sum = 0, mn = double.INFINITY, mx = -double.INFINITY;
            int n = 0;
            int64 total = view.src.count ();
            for (int64 i = 0; i < total && i < 100000; i++) {
                var row = view.src.row (i);
                if (row == null) break;
                var scope = new RowScope (view.src, row);
                var v = rt.eval_with (argument, scope);
                if (v.is_null || v.is_empty) continue;
                if (fn == "count") {
                    n++;
                    continue;
                }
                double d = v.to_double ();
                sum += d;
                mn = double.min (mn, d);
                mx = double.max (mx, d);
                n++;
            }
            switch (fn) {
                case "sum": result = new SValue.dbl (sum); break;
                case "avg": result = n > 0 ? new SValue.dbl (sum / n) : new SValue.null (); break;
                case "count": result = new SValue.int (n); break;
                case "min": result = n > 0 ? new SValue.dbl (mn) : new SValue.null (); break;
                default: result = n > 0 ? new SValue.dbl (mx) : new SValue.null (); break;
            }
            return true;
        }
    }
}
