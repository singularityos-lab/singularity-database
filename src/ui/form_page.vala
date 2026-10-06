using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Database {

    public abstract class FieldControl : Object {
        public Field field;
        public Widget widget;
        public bool loading;
        public signal void changed ();

        public abstract DbValue get_value () throws Error;
        public abstract void set_value (DbValue v);
        public virtual void set_editable (bool on) {
            widget.sensitive = on;
        }

        public void emit_changed () {
            if (!loading) changed ();
        }

        public static FieldControl create (DatabaseWindow win, RecordSource src, Field f, ControlKind kind) {
            var k = kind == ControlKind.AUTO ? ControlKind.for_field (f) : kind;
            switch (k) {
                case ControlKind.MULTILINE: return new MultilineControl (f);
                case ControlKind.CHECK: return new CheckControl (f);
                case ControlKind.CHOICE: return new ChoiceControl (f, src);
                case ControlKind.LOOKUP: return new ChoiceControl (f, src);
                case ControlKind.DATE: return new DateControl (f);
                case ControlKind.ATTACHMENT: return new AttachmentControl (win, src, f);
                case ControlKind.LABEL: return new LabelControl (f, src);
                default: return new TextControl (f);
            }
        }
    }

    public class TextControl : FieldControl {
        private Entry entry;

        public TextControl (Field f) {
            field = f;
            entry = new Entry ();
            entry.hexpand = true;
            if (f.field_type.is_numeric ()) entry.xalign = 1;
            if (f.field_type == FieldType.AUTONUMBER) entry.placeholder_text = _("Automatic");
            entry.changed.connect (() => emit_changed ());
            widget = entry;
        }

        public override DbValue get_value () throws Error {
            return Codec.parse (field, entry.text);
        }

        public override void set_value (DbValue v) {
            loading = true;
            entry.text = Codec.edit_text (field, v);
            loading = false;
        }

        public override void set_editable (bool on) {
            entry.editable = on;
            entry.can_focus = on;
        }
    }

    public class LabelControl : FieldControl {
        private Label label;
        private RecordSource src;
        private DbValue value = new DbValue.null ();

        public LabelControl (Field f, RecordSource src) {
            field = f;
            this.src = src;
            label = new Label ("");
            label.halign = Align.START;
            label.xalign = 0;
            label.wrap = true;
            label.selectable = true;
            widget = label;
        }

        public override DbValue get_value () throws Error {
            return value;
        }

        public override void set_value (DbValue v) {
            value = v;
            label.label = src.display (field, v);
        }
    }

    public class MultilineControl : FieldControl {
        private TextView view;

        public MultilineControl (Field f) {
            field = f;
            view = new TextView ();
            view.wrap_mode = WrapMode.WORD_CHAR;
            view.top_margin = view.bottom_margin = view.left_margin = view.right_margin = 6;
            view.buffer.changed.connect (() => emit_changed ());
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.vexpand = true;
            scroll.child = view;
            scroll.add_css_class ("db-form-multiline");
            widget = scroll;
        }

        public override DbValue get_value () throws Error {
            return Codec.parse (field, view.buffer.text);
        }

        public override void set_value (DbValue v) {
            loading = true;
            view.buffer.text = v.is_null ? "" : v.to_string ();
            loading = false;
        }

        public override void set_editable (bool on) {
            view.editable = on;
        }
    }

    public class CheckControl : FieldControl {
        private CheckButton check;

        public CheckControl (Field f) {
            field = f;
            check = new CheckButton.with_label (_("Yes"));
            check.toggled.connect (() => emit_changed ());
            widget = check;
        }

        public override DbValue get_value () throws Error {
            return new DbValue.bool (check.active);
        }

        public override void set_value (DbValue v) {
            loading = true;
            check.active = v.as_bool ();
            loading = false;
        }
    }

    public class ChoiceControl : FieldControl {
        private DropDown dd;
        private Gee.ArrayList<DbValue> values = new Gee.ArrayList<DbValue> ();

        public ChoiceControl (Field f, RecordSource src) {
            field = f;
            string[] labels = { _("(Empty)") };
            values.add (new DbValue.null ());
            if (f.field_type == FieldType.CHOICE) {
                foreach (string c in f.choices) {
                    labels += c;
                    values.add (new DbValue.text (c));
                }
            } else if (f.field_type == FieldType.LOOKUP) {
                foreach (var r in src.lookup_choices (f, 2000)) {
                    labels += r.get (1).to_string ();
                    values.add (r.get (0));
                }
            }
            dd = new DropDown.from_strings (labels);
            dd.enable_search = labels.length > 12;
            dd.expression = new PropertyExpression (typeof (StringObject), null, "string");
            dd.hexpand = true;
            dd.notify["selected"].connect (() => emit_changed ());
            widget = dd;
        }

        public override DbValue get_value () throws Error {
            uint i = dd.selected;
            if (i >= values.size) return new DbValue.null ();
            return values[(int) i];
        }

        public override void set_value (DbValue v) {
            loading = true;
            dd.selected = 0;
            for (int i = 1; i < values.size; i++) {
                bool same = field.field_type == FieldType.CHOICE ? values[i].to_string ().casefold () == v.to_string ().casefold () : values[i].equals (v);
                if (!v.is_null && same) {
                    dd.selected = i;
                    break;
                }
            }
            loading = false;
        }
    }

    public class DateControl : FieldControl {
        private Entry entry;
        private Gtk.Calendar cal;
        private Popover pop;

        public DateControl (Field f) {
            field = f;
            var box = new Box (Orientation.HORIZONTAL, 4);
            entry = new Entry ();
            entry.hexpand = true;
            entry.placeholder_text = Locale.get ().day_first ? _("DD/MM/YYYY") : _("MM/DD/YYYY");
            entry.changed.connect (() => emit_changed ());
            box.append (entry);
            var btn = new Button.from_icon_name ("x-office-calendar-symbolic");
            btn.tooltip_text = _("Choose Date");
            cal = new Gtk.Calendar ();
            pop = new Popover ();
            pop.child = cal;
            pop.set_parent (btn);
            btn.clicked.connect (() => {
                string iso;
                if (Codec.parse_date (entry.text, out iso)) {
                    var dt = new DateTime.local (int.parse (iso.substring (0, 4)), int.parse (iso.substring (5, 2)), int.parse (iso.substring (8, 2)), 0, 0, 0);
                    if (dt != null) cal.select_day (dt);
                }
                pop.popup ();
            });
            cal.day_selected.connect (() => {
                string time = "";
                string cur = "";
                if (field.field_type == FieldType.DATETIME && Codec.parse_datetime (entry.text, out cur)) time = cur.substring (10);
                var v = new DbValue.text (cal.get_date ().format ("%Y-%m-%d") + time);
                entry.text = Codec.edit_text (field, v);
                pop.popdown ();
            });
            box.append (btn);
            widget = box;
        }

        public override DbValue get_value () throws Error {
            return Codec.parse (field, entry.text);
        }

        public override void set_value (DbValue v) {
            loading = true;
            entry.text = Codec.edit_text (field, v);
            loading = false;
        }

        public override void set_editable (bool on) {
            widget.sensitive = on;
        }
    }

    public class AttachmentControl : FieldControl {
        private Button button;
        private Label label;
        private Image image;
        private DbValue value = new DbValue.null ();
        public int64 rowid = -1;

        public AttachmentControl (DatabaseWindow win, RecordSource src, Field f) {
            field = f;
            button = new Button ();
            var box = new Box (Orientation.HORIZONTAL, 10);
            image = new Image.from_icon_name ("mail-attachment-symbolic");
            image.pixel_size = 32;
            box.append (image);
            label = new Label (_("No File"));
            label.ellipsize = Pango.EllipsizeMode.MIDDLE;
            label.halign = Align.START;
            box.append (label);
            button.child = box;
            button.clicked.connect (() => {
                if (rowid < 0) {
                    win.toast (_("Save the record first, then add the attachment."));
                    return;
                }
                Dialogs.attachment (win, src, rowid, field);
            });
            widget = button;
        }

        public override DbValue get_value () throws Error {
            return value;
        }

        public override void set_value (DbValue v) {
            value = v;
            if (v.kind == ValueKind.BLOB) {
                label.label = Attachment.describe (v.blob_value);
                string n, m;
                Bytes content;
                if (Attachment.unpack (v.blob_value, out n, out m, out content) && m.has_prefix ("image/")) {
                    try {
                        image.paintable = Gdk.Texture.from_bytes (content);
                        image.pixel_size = 64;
                        return;
                    } catch (Error e) {
                    }
                }
                image.icon_name = "mail-attachment-symbolic";
                image.pixel_size = 32;
            } else {
                label.label = _("No File");
                image.icon_name = "mail-attachment-symbolic";
                image.pixel_size = 32;
            }
        }
    }

    public class RecordEditor : Box {
        private DatabaseWindow win;
        private RecordSource src;
        private Gee.ArrayList<FieldControl> controls = new Gee.ArrayList<FieldControl> ();
        private int64 rowid = -1;
        private Row? original;

        public RecordEditor (DatabaseWindow win, RecordSource src) {
            Object (orientation: Orientation.VERTICAL, spacing: 12);
            this.win = win;
            this.src = src;
            var grid = new Grid ();
            grid.column_spacing = 16;
            grid.row_spacing = 10;
            int r = 0;
            foreach (var f in src.def.fields) {
                var l = new Label (f.name);
                l.add_css_class ("db-form-label");
                l.halign = Align.END;
                l.valign = f.field_type == FieldType.LONG_TEXT ? Align.START : Align.CENTER;
                l.margin_top = f.field_type == FieldType.LONG_TEXT ? 6 : 0;
                grid.attach (l, 0, r, 1, 1);
                var c = FieldControl.create (win, src, f, ControlKind.AUTO);
                if (f.field_type == FieldType.LONG_TEXT) c.widget.height_request = 110;
                c.set_editable (f.field_type != FieldType.AUTONUMBER);
                c.widget.hexpand = true;
                grid.attach (c.widget, 1, r, 1, 1);
                controls.add (c);
                r++;
            }
            append (grid);
        }

        public void load_rowid (int64 id) {
            rowid = id;
            try {
                var rs = src.db.query ("SELECT * FROM %s WHERE rowid = ?".printf (Sql.quote_ident (src.source)), { new DbValue.int (id) });
                if (rs.rows.size == 0) return;
                original = rs.rows[0];
                for (int i = 0; i < controls.size; i++) {
                    controls[i].set_value (original.get (rs.index_of (controls[i].field.name)));
                    var ac = controls[i] as AttachmentControl;
                    if (ac != null) ac.rowid = id;
                }
            } catch (Error e) {
                win.show_error (_("Could Not Load Record"), e.message);
            }
        }

        public void load_new () {
            rowid = -1;
            foreach (var c in controls) {
                var f = c.field;
                DbValue v = new DbValue.null ();
                if (f.default_value != "" && f.field_type != FieldType.AUTONUMBER) {
                    string d = f.default_value;
                    if (d == "Date()" || d == "Now()") d = new DateTime.now_local ().format (d == "Now()" ? "%Y-%m-%d %H:%M:%S" : "%Y-%m-%d");
                    try {
                        v = Codec.parse (f, d);
                    } catch (Error e) {
                    }
                }
                c.set_value (v);
            }
        }

        public bool save () {
            string[] cols = {};
            DbValue[] vals = {};
            try {
                foreach (var c in controls) {
                    if (c.field.field_type == FieldType.AUTONUMBER || c.field.field_type == FieldType.ATTACHMENT) continue;
                    var v = c.get_value ();
                    if (rowid >= 0 && original != null) {
                        var o = original.get (src.def.index_of (c.field.name));
                        if (o.kind == v.kind && o.equals (v)) continue;
                        src.db.update_value (src.source, rowid, c.field.name, v);
                    } else if (!v.is_null) {
                        cols += c.field.name;
                        vals += v;
                    }
                }
                if (rowid < 0) rowid = src.db.insert_row (src.source, cols, vals);
                src.invalidate ();
                return true;
            } catch (Error e) {
                win.show_error (_("Could Not Save the Record"), e.message);
                return false;
            }
        }
    }

    public class FormPage : ObjectPage {
        public FormDef def;
        public bool unsaved;
        private string saved_json;
        private Stack stack;
        private Box form_box;
        public FormView? view;
        private FormDesigner? designer;
        private string last_search = "";
        private string pending_where = "";
        private string pending_args = "";
        private int pending_mode = -1;

        public FormPage (DatabaseWindow win, string name) throws Error {
            base (win, "form", name);
            def = FormDef.from_json (name, win.db.get_meta ("form:" + name));
            if (def == null) throw new SchemaError.NOT_FOUND (_("The form \"%s\" could not be read.").printf (name));
            saved_json = def.to_json ();
            add_css_class ("db-content");
            stack = new Stack ();
            stack.transition_type = StackTransitionType.CROSSFADE;
            stack.vexpand = true;
            form_box = new Box (Orientation.VERTICAL, 0);
            stack.add_named (form_box, "form");
            append (stack);
            mode = def.default_view == "datasheet" ? "datasheet" : "form";
            build_form ();
        }

        public ScriptObject? script_object () {
            return view != null ? view.me : null;
        }

        public ScriptObject? active_control_object () {
            if (view == null) return null;
            var focus = win.get_focus ();
            foreach (var b in view.bindings) {
                if (focus != null && (focus == b.widget || focus.is_ancestor (b.widget))) return new ControlObject (view, b);
            }
            return null;
        }

        public void open_with (string where, int data_mode, string open_args, bool datasheet) {
            pending_where = where;
            pending_args = open_args;
            pending_mode = data_mode;
            if (datasheet && mode != "datasheet") {
                change_mode ("datasheet");
                win.sync_bubbles ();
                return;
            }
            build_form ();
        }

        public void go_to_record (int64 index) {
            if (view != null) view.go (index);
        }

        public void focus_control (string name) {
            if (view == null) return;
            var b = view.binding (name);
            if (b != null) view.focus_binding (b);
        }

        public void script_command (string cmd, SValue[] args) {
            if (view == null) return;
            switch (cmd) {
                case "requery":
                    if (args.length > 0 && !(args[0] is MissingValue) && args[0].to_text () != "") {
                        var b = view.binding (args[0].to_text ());
                        if (b != null) view.requery_control (b);
                        return;
                    }
                    view.requery ();
                    break;
                case "refresh":
                case "refreshrecord":
                    view.load_record ();
                    break;
                case "showallrecords":
                    view.filter_on = false;
                    view.where_arg = "";
                    view.apply_filter ();
                    break;
                case "saverecord":
                    view.commit_record ();
                    break;
                case "deleterecord":
                    view.delete_current ();
                    break;
                case "undorecord":
                    view.record_dirty = false;
                    view.load_record ();
                    break;
                case "applyfilter":
                    string where = args.length > 1 && !(args[1] is MissingValue) ? args[1].to_text () : "";
                    if (where == "" && args.length > 0 && !(args[0] is MissingValue)) {
                        var q = SavedQueries.load (win.db, args[0].to_text ());
                        if (q != null) where = QueryWhere.extract (q.sql);
                    }
                    view.filter = where;
                    view.filter_on = where != "";
                    view.apply_filter ();
                    break;
                case "findrecord":
                    if (args.length > 0) search (args[0].to_text ());
                    break;
                case "setproperty":
                    if (args.length < 3) return;
                    var b = view.binding (args[0].to_text ());
                    if (b == null) return;
                    try {
                        new ControlObject (view, b).set_member (property_name (args[1]), {}, args[2]);
                    } catch (Error e) {
                        win.show_error (_("Could Not Set the Property"), e.message);
                    }
                    break;
                case "runcommand":
                    int code = 0;
                    try {
                        code = args.length > 0 ? (int) args[0].to_int () : 0;
                    } catch (ScriptError e) {
                    }
                    switch (code) {
                        case 97: view.commit_record (); break;
                        case 223: view.delete_current (); break;
                        case 28: view.go_new (); break;
                        case 292: view.load_record (); break;
                        case 505:
                        case 18: view.requery (); break;
                        case 145: run_action ("filter-by-form", null); break;
                        case 144: script_command ("showallrecords", {}); break;
                        case 340: run_action ("print", null); break;
                        case 58: win.close_object ("form", object_name); break;
                    }
                    break;
            }
        }

        private static string property_name (SValue v) {
            if (v.kind == SKind.INT) {
                switch (v.i) {
                    case 0: return "Enabled";
                    case 1: return "Visible";
                    case 2: return "Locked";
                    case 4: return "Left";
                    case 5: return "Top";
                    case 6: return "Width";
                    case 7: return "Height";
                    case 8: return "ForeColor";
                    case 9: return "BackColor";
                    case 10: return "Caption";
                    default: return "Value";
                }
            }
            return v.to_text ();
        }

        public bool before_close () {
            if (view != null) {
                if (!view.commit_record ()) return false;
                if (view.fire_form ("Unload")) return false;
                view.fire_form ("Close");
            }
            return true;
        }

        public override string[] modes () {
            return { "form", "datasheet", "design" };
        }

        public override string mode_label (string m) {
            if (m == "datasheet") return _("Datasheet");
            return base.mode_label (m);
        }

        public override void change_mode (string m) {
            if (m == mode) return;
            if (m == "design") {
                if (view != null && !view.commit_record ()) return;
                if (designer == null) {
                    designer = new FormDesigner (this);
                    stack.add_named (designer, "design");
                    designer.changed.connect (() => {
                        win.sync_bubbles ();
                        title_changed ();
                    });
                }
                designer.load (def);
                stack.visible_child_name = "design";
            } else {
                if (designer != null && mode == "design") def = designer.current ();
                else if (view != null && !view.commit_record ()) return;
                mode = m;
                build_form ();
                stack.visible_child_name = "form";
            }
            base.change_mode (m);
        }

        public override bool dirty () {
            if (designer != null && mode == "design") return designer.current ().to_json () != saved_json;
            return def.to_json () != saved_json;
        }

        public override bool save () {
            if (designer != null && mode == "design") def = designer.current ();
            try {
                win.db.save_object_meta (_("Save Form"), "form:", object_name, def.to_json ());
                saved_json = def.to_json ();
                if (win.runtime != null && def.code.strip () != "") {
                    try {
                        win.runtime.load_module (def.code, "Form_" + def.name);
                    } catch (Error e) {
                        win.toast (_("The form code has errors: %s").printf (e.message));
                    }
                }
                win.toast (_("Form saved"));
                title_changed ();
                return true;
            } catch (Error e) {
                win.show_error (_("Could Not Save the Form"), e.message);
                return false;
            }
        }

        public override void reload () {
            if (dirty ()) return;
            var fresh = FormDef.from_json (object_name, win.db.get_meta ("form:" + object_name));
            if (fresh == null) return;
            def = fresh;
            saved_json = def.to_json ();
            if (mode != "design") {
                if (view != null && view.record_dirty) return;
                build_form ();
            } else if (designer != null) designer.load (def);
        }

        public override string title () {
            return object_name + (dirty () ? " *" : "");
        }

        public override string[] bubbles () {
            if (mode == "design") return { "add-field", "layout" };
            return { "search", "filter", "print", "pdf" };
        }

        public override bool handles (string action) {
            if (mode == "design") return action == "add-field" || action == "tidy" || action == "undo" || action == "redo" || action == "design-add" || action == "design-calc" || action == "view-code";
            var src = view != null ? view.src : null;
            switch (action) {
                case "new-record":
                case "delete-record":
                    return src != null && src.editable;
                case "save-record":
                case "first-record":
                case "prev-record":
                case "next-record":
                case "last-record":
                case "goto":
                case "print":
                case "export-pdf":
                case "sort-asc":
                case "sort-desc":
                case "clear-filters":
                case "filter-selection":
                case "filter":
                case "filter-by-form":
                case "refresh-records":
                    return src != null;
                default:
                    return false;
            }
        }

        public override void run_action (string action, Variant? param) {
            if (mode == "design") {
                designer.run_action (action, param);
                return;
            }
            if (view == null) return;
            var src = view.src;
            switch (action) {
                case "new-record": view.go_new (); break;
                case "delete-record": view.delete_current (); break;
                case "save-record": view.commit_record (); break;
                case "first-record": view.go (0); break;
                case "prev-record": view.go (view.position - 1); break;
                case "next-record": view.go (view.position + 1); break;
                case "last-record": view.go (src.count () - 1); break;
                case "refresh-records": view.requery (); break;
                case "goto":
                    break;
                case "sort-asc":
                case "sort-desc":
                    var focus = win.get_focus ();
                    foreach (var b in view.bindings) {
                        if (b.fc != null && b.c.is_bound () && focus != null && (focus == b.fc.widget || focus.is_ancestor (b.fc.widget))) {
                            view.order_by = "[%s]%s".printf (b.c.field, action == "sort-desc" ? " DESC" : "");
                            view.apply_filter ();
                            break;
                        }
                    }
                    break;
                case "clear-filters":
                    view.order_by = def.sort;
                    view.filter_on = false;
                    view.where_arg = "";
                    src.state.search = "";
                    view.apply_filter ();
                    break;
                case "filter-selection":
                    var focus = win.get_focus ();
                    foreach (var b in view.bindings) {
                        if (b.fc != null && b.c.is_bound () && focus != null && (focus == b.fc.widget || focus.is_ancestor (b.fc.widget))) {
                            try {
                                var v = b.fc.get_value ();
                                view.filter = v.is_null ? "[%s] Is Null".printf (b.c.field) : "[%s] = %s".printf (b.c.field, v.kind == ValueKind.TEXT ? "'" + v.text_value.replace ("'", "''") + "'" : v.to_string ());
                                view.filter_on = true;
                                view.apply_filter ();
                            } catch (Error e) {
                            }
                            break;
                        }
                    }
                    break;
                case "filter":
                case "filter-by-form":
                    FilterByForm.show (win, src.def, view.filter_on ? view.filter : "", (where) => {
                        view.filter = where;
                        view.filter_on = where != "";
                        view.apply_filter ();
                    });
                    break;
                case "print":
                case "export-pdf":
                    var r = ReportDesign.from_form (def, src.def);
                    r.state = src.state.copy ();
                    if (action == "print") ReportPrinter.print_source (win, r, src);
                    else ReportPrinter.export_pdf (win, r, src);
                    break;
            }
        }

        public override void search (string text) {
            if (view == null || view.src == null) return;
            last_search = text;
            if (!view.commit_record ()) return;
            view.src.state.search = text;
            view.src.invalidate ();
            view.go (0);
        }

        public override string search_text () {
            return last_search;
        }

        private void build_form () {
            Widget? child;
            while ((child = form_box.get_first_child ()) != null) form_box.remove (child);
            view = new FormView (win, def);
            view.vexpand = true;
            if (mode == "datasheet") view.view_override = "datasheet";
            if (pending_where != "") view.where_arg = pending_where;
            view.open_args = pending_args;
            if (pending_mode == 2) view.read_only_mode = true;
            view.state_changed.connect (() => win.sync_bubbles ());
            form_box.append (view);
            view.rebuild ();
            if (pending_mode == 0 && view.src != null && view.src.editable) view.go_new ();
            pending_mode = -1;
        }
    }

    public class FilterByForm {
        public delegate void Apply (string where);

        public static void show (DatabaseWindow win, TableDef def, string current, owned Apply apply) {
            var dlg = Dialogs.make (win, _("Filter by Form"), 560, 640);
            var box = Dialogs.body (dlg);
            var note = new Label (_("Type criteria under the fields, like >100, Like \"A*\", Between #1/1/2024# And #3/31/2024#. Each Or page is an alternative."));
            note.wrap = true;
            note.xalign = 0;
            note.add_css_class ("dim-label");
            box.append (note);
            var switcher = new BubbleSwitcher ();
            var stack = new Stack ();
            box.append (switcher);
            box.append (stack);
            var pages = new Gee.ArrayList<Gee.HashMap<string, EntryRow>> ();
            Callback add_page = null;
            add_page = () => {
                int n = pages.size;
                var g = new PreferencesGroup (n == 0 ? _("Look For") : _("Or"), null);
                var map = new Gee.HashMap<string, EntryRow> ();
                foreach (var f in def.fields) {
                    if (f.field_type == FieldType.ATTACHMENT) continue;
                    var row = new EntryRow (f.label ());
                    g.add_row (row);
                    map[f.name] = row;
                }
                pages.add (map);
                string id = "p%d".printf (n);
                stack.add_named (g, id);
                switcher.add_option (id, n == 0 ? _("Look For") : _("Or %d").printf (n));
                switcher.set_active (id);
                stack.visible_child_name = id;
            };
            switcher.selected.connect ((id) => stack.visible_child_name = id);
            add_page ();
            var more = new Button.with_label (_("Add Or"));
            more.halign = Align.START;
            more.clicked.connect (() => add_page ());
            box.append (more);
            Dialogs.footer (dlg, _("Apply Filter"), () => {
                string[] ors = {};
                foreach (var map in pages) {
                    string[] ands = {};
                    foreach (var e in map.entries) {
                        string t = e.value.text.strip ();
                        if (t == "") continue;
                        var f = def.find (e.key);
                        string col = "[" + e.key + "]";
                        ands += "(" + criteria_access (col, t, f) + ")";
                    }
                    if (ands.length > 0) ors += "(" + string.joinv (" And ", ands) + ")";
                }
                apply (string.joinv (" Or ", ors));
                return true;
            });
            dlg.open_dialog ();
        }

        public delegate void Callback ();

        public static string criteria_access (string col, string text, Field? f) {
            string t = text.strip ();
            string low = t.down ();
            string[] ops = { "<=", ">=", "<>", "=", "<", ">" };
            foreach (string op in ops) {
                if (t.has_prefix (op)) return col + " " + t;
            }
            if (low.has_prefix ("between ") || low.has_prefix ("like ") || low.has_prefix ("in ") || low.has_prefix ("in(") || low.has_prefix ("is ") || low.has_prefix ("not ")) return col + " " + t;
            if (t.contains ("*") || t.contains ("?")) return "%s Like \"%s\"".printf (col, t.replace ("\"", ""));
            double d = 0;
            bool isnum = f != null && f.field_type.is_numeric ();
            if (isnum) isnum = Codec.parse_number (t, out d);
            if (isnum) return "%s = %s".printf (col, DbValue.format_real (d));
            if (t.has_prefix ("#") || t.has_prefix ("\"") || t.has_prefix ("'")) return "%s = %s".printf (col, t);
            if (f != null && f.field_type.is_temporal ()) {
                string iso = "";
                if (Codec.parse_date (t, out iso)) return "%s = '%s'".printf (col, iso);
            }
            if (f != null && f.field_type == FieldType.BOOLEAN) return "%s = %s".printf (col, new DbValue.text (t).as_bool () ? "True" : "False");
            return "%s = \"%s\"".printf (col, t.replace ("\"", "\"\""));
        }
    }
}
