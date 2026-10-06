using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Database {

    public class TableDesigner : Box {
        private weak TablePage page;
        private TableDef def;
        private Gee.ArrayList<string?> origins = new Gee.ArrayList<string?> ();
        private Gee.ArrayList<TableDef> undo_defs = new Gee.ArrayList<TableDef> ();
        private Gee.ArrayList<Gee.ArrayList<string?>> undo_origins = new Gee.ArrayList<Gee.ArrayList<string?>> ();
        private Gee.ArrayList<TableDef> redo_defs = new Gee.ArrayList<TableDef> ();
        private Gee.ArrayList<Gee.ArrayList<string?>> redo_origins = new Gee.ArrayList<Gee.ArrayList<string?>> ();
        private Box field_rows;
        private SizeGroup[] columns_sg = {};
        private Box inspector;
        private int selected;
        private bool building;
        public bool dirty { get; private set; }

        public signal void changed ();

        private PropertySheet sheet;

        public const int W_KEY = 30;
        public const int W_NAME = 170;
        public const int W_TYPE = 176;
        public const int W_FLAG = 70;
        public const int W_MENU = 30;

        public TableDesigner (TablePage page, TableDef def) {
            Object (orientation: Orientation.HORIZONTAL, spacing: 12);
            this.page = page;
            add_css_class ("db-pane-page");
            var left = new Box (Orientation.VERTICAL, 0);
            left.hexpand = true;
            left.add_css_class ("db-panel");
            left.add_css_class ("db-dense");
            var head = new Box (Orientation.HORIZONTAL, 0);
            head.add_css_class ("db-grid-header");
            string[] titles = { "", _("Field Name"), _("Data Type"), _("Required"), _("Unique"), _("Description"), "" };
            int[] ws = { W_KEY, W_NAME, W_TYPE, W_FLAG, W_FLAG, -1, W_MENU };
            int[] mss = { 0, 10, 10, 10, 10, 10, 0 };
            for (int i = 0; i < titles.length; i++) {
                columns_sg += new SizeGroup (SizeGroupMode.HORIZONTAL);
                var cell = new Box (Orientation.HORIZONTAL, 0);
                var l = new Label (titles[i]);
                l.add_css_class ("db-grid-head");
                l.hexpand = true;
                l.xalign = 0;
                l.ellipsize = Pango.EllipsizeMode.END;
                l.tooltip_text = titles[i];
                l.margin_start = mss[i];
                cell.append (l);
                if (ws[i] > 0) cell.width_request = ws[i];
                else cell.hexpand = true;
                columns_sg[i].add_widget (cell);
                head.append (cell);
            }
            var table_box = new Box (Orientation.VERTICAL, 0);
            table_box.append (head);
            field_rows = new Box (Orientation.VERTICAL, 0);
            field_rows.add_css_class ("db-design-grid");
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.vexpand = true;
            scroll.child = field_rows;
            table_box.append (scroll);
            var hscroll = new ScrolledWindow ();
            hscroll.vscrollbar_policy = PolicyType.NEVER;
            hscroll.hscrollbar_policy = PolicyType.AUTOMATIC;
            hscroll.vexpand = true;
            hscroll.min_content_width = 360;
            hscroll.child = table_box;
            left.append (hscroll);
            var foot = new Box (Orientation.HORIZONTAL, 6);
            foot.add_css_class ("db-grid-footer");
            var add = new Button.with_label (_("Add Field"));
            add.add_css_class ("db-small-button");
            add.clicked.connect (() => add_field ());
            foot.append (add);
            var key = new Button.with_label (_("Primary Key"));
            key.add_css_class ("db-small-button");
            key.tooltip_text = _("Make the selected field the primary key");
            key.clicked.connect (() => toggle_key ());
            foot.append (key);
            count_label = new Label ("");
            count_label.add_css_class ("db-status");
            count_label.add_css_class ("dim-label");
            count_label.hexpand = true;
            count_label.halign = Align.END;
            foot.append (count_label);
            left.append (foot);
            append (left);
            var iscroll = new ScrolledWindow ();
            iscroll.hscrollbar_policy = PolicyType.NEVER;
            iscroll.width_request = 310;
            iscroll.hexpand = false;
            iscroll.add_css_class ("db-panel");
            inspector = new Box (Orientation.VERTICAL, 0);
            inspector.add_css_class ("db-inspector");
            sheet = new PropertySheet ();
            inspector.append (sheet);
            iscroll.child = inspector;
            append (iscroll);
            reset (def);
        }

        private Label count_label;

        public void reset (TableDef d) {
            def = d;
            origins.clear ();
            foreach (var f in def.fields) origins.add (f.name);
            undo_defs.clear ();
            undo_origins.clear ();
            redo_defs.clear ();
            redo_origins.clear ();
            dirty = false;
            selected = 0;
            rebuild ();
            changed ();
        }

        private void snapshot () {
            undo_defs.add (def.copy ());
            var o = new Gee.ArrayList<string?> ();
            o.add_all (origins);
            undo_origins.add (o);
            redo_defs.clear ();
            redo_origins.clear ();
            if (undo_defs.size > 200) {
                undo_defs.remove_at (0);
                undo_origins.remove_at (0);
            }
        }

        private void touched () {
            dirty = true;
            changed ();
        }

        public void run_action (string action) {
            switch (action) {
                case "add-field": add_field (); break;
                case "primary-key": toggle_key (); break;
                case "undo": undo (); break;
                case "redo": redo (); break;
                case "save-record": apply (); break;
            }
        }

        private void undo () {
            if (undo_defs.size == 0) {
                page.win.run_db_undo ();
                return;
            }
            redo_defs.add (def.copy ());
            var o = new Gee.ArrayList<string?> ();
            o.add_all (origins);
            redo_origins.add (o);
            def = undo_defs.remove_at (undo_defs.size - 1);
            origins = undo_origins.remove_at (undo_origins.size - 1);
            dirty = undo_defs.size > 0 || redo_defs.size > 0;
            rebuild ();
            touched ();
        }

        private void redo () {
            if (redo_defs.size == 0) {
                page.win.run_db_redo ();
                return;
            }
            undo_defs.add (def.copy ());
            var o = new Gee.ArrayList<string?> ();
            o.add_all (origins);
            undo_origins.add (o);
            def = redo_defs.remove_at (redo_defs.size - 1);
            origins = redo_origins.remove_at (redo_origins.size - 1);
            rebuild ();
            touched ();
        }

        public void select_field (string name) {
            int i = def.index_of (name);
            if (i >= 0) {
                selected = i;
                rebuild ();
            }
        }

        private void add_field () {
            snapshot ();
            var f = new Field (def.unique_field_name (_("Field")), FieldType.TEXT);
            def.fields.add (f);
            origins.add (null);
            selected = def.fields.size - 1;
            rebuild ();
            touched ();
            focus_name (selected);
        }

        private void focus_name (int index) {
            var row = field_rows.get_first_child ();
            for (int i = 0; row != null && i < index; i++) row = row.get_next_sibling ();
            if (row == null) return;
            var name = row.get_first_child ();
            if (name != null) name = name.get_next_sibling ();
            if (name is Entry) {
                name.grab_focus ();
                ((Entry) name).select_region (0, -1);
            }
        }

        private void toggle_key () {
            if (selected < 0 || selected >= def.fields.size) return;
            snapshot ();
            var f = def.fields[selected];
            bool was = f.primary_key;
            bool ctrl_multi = false;
            if (!was && !ctrl_multi) {
                foreach (var o in def.fields) {
                    if (o.primary_key && o.field_type == FieldType.AUTONUMBER) o.field_type = FieldType.INTEGER;
                    o.primary_key = false;
                }
            }
            f.primary_key = !was;
            if (f.primary_key) f.required = true;
            rebuild ();
            touched ();
        }

        private void move_field (int index, int delta) {
            int j = index + delta;
            if (j < 0 || j >= def.fields.size) return;
            snapshot ();
            var f = def.fields.remove_at (index);
            def.fields.insert (j, f);
            var o = origins.remove_at (index);
            origins.insert (j, o);
            selected = j;
            rebuild ();
            touched ();
        }

        private void delete_field (int index) {
            if (def.fields.size <= 1) {
                page.win.toast (_("A table needs at least one field."));
                return;
            }
            snapshot ();
            string name = def.fields[index].name;
            def.fields.remove_at (index);
            origins.remove_at (index);
            var keep = new Gee.ArrayList<IndexDef> ();
            foreach (var ix in def.indexes) {
                bool uses = false;
                foreach (string c in ix.columns) {
                    if (c.casefold () == name.casefold ()) uses = true;
                }
                if (!uses) keep.add (ix);
            }
            def.indexes = keep;
            var rels = new Gee.ArrayList<Relationship> ();
            foreach (var r in def.relationships) {
                bool uses = false;
                foreach (string c in r.columns) {
                    if (c.casefold () == name.casefold ()) uses = true;
                }
                if (!uses) rels.add (r);
            }
            def.relationships = rels;
            selected = int.min (index, def.fields.size - 1);
            rebuild ();
            touched ();
        }

        private void rebuild () {
            building = true;
            Widget? child;
            while ((child = field_rows.get_first_child ()) != null) {
                int k = 0;
                for (var c = child.get_first_child (); c != null; c = c.get_next_sibling ()) {
                    if (k < columns_sg.length) columns_sg[k].remove_widget (c);
                    k++;
                }
                field_rows.remove (child);
            }
            string[] type_labels = {};
            foreach (var t in FieldType.ALL) type_labels += t.label ();
            for (int i = 0; i < def.fields.size; i++) field_rows.append (field_row (i, type_labels));
            build_inspector ();
            building = false;
        }

        private Widget field_row (int i, string[] type_labels) {
            var f = def.fields[i];
            var row = new Box (Orientation.HORIZONTAL, 0);
            row.add_css_class ("db-design-row");
            if (i % 2 == 1) row.add_css_class ("odd");
            if (i == selected) row.add_css_class ("selected");
            var keyb = new Button.from_icon_name (f.primary_key ? "db-key-symbolic" : f.field_type.icon_name ());
            keyb.add_css_class ("flat");
            keyb.add_css_class ("db-cell-icon");
            if (f.primary_key) keyb.add_css_class ("accent");
            keyb.width_request = W_KEY;
            keyb.tooltip_text = f.primary_key ? _("Primary key") : _("Make Primary Key");
            keyb.clicked.connect (() => {
                selected = i;
                toggle_key ();
            });
            row.append (keyb);
            var name = new Entry ();
            name.text = f.name;
            name.width_request = W_NAME;
            name.width_chars = 1;
            name.add_css_class ("db-cell");
            name.changed.connect (() => {
                if (building) return;
                string old = f.name;
                string n = name.text.strip ();
                if (n == "" || n == old) return;
                snapshot ();
                f.name = n;
                foreach (var ix in def.indexes) {
                    string[] cols = ix.columns;
                    for (int k = 0; k < cols.length; k++) if (cols[k] == old) cols[k] = n;
                    ix.columns = cols;
                }
                foreach (var r in def.relationships) {
                    string[] cols = r.columns;
                    for (int k = 0; k < cols.length; k++) if (cols[k] == old) cols[k] = n;
                    r.columns = cols;
                }
                touched ();
            });
            focus_selects (name, i);
            row.append (name);
            var type = new DropDown.from_strings (type_labels);
            type.width_request = W_TYPE;
            type.hexpand = false;
            type.add_css_class ("db-cell");
            for (int k = 0; k < FieldType.ALL.length; k++) {
                if (FieldType.ALL[k] == f.field_type) type.selected = k;
            }
            type.notify["selected"].connect (() => {
                if (building) return;
                var nt = FieldType.ALL[type.selected];
                if (nt == f.field_type) return;
                snapshot ();
                change_type (f, nt);
                selected = i;
                Idle.add (() => {
                    rebuild ();
                    return Source.REMOVE;
                });
                touched ();
            });
            row.append (type);
            var req = new CheckButton ();
            req.active = f.required || f.primary_key;
            req.sensitive = !f.primary_key;
            req.halign = Align.START;
            req.margin_start = 10;
            var req_box = new Box (Orientation.HORIZONTAL, 0);
            req_box.width_request = W_FLAG;
            req_box.append (req);

            req.toggled.connect (() => {
                if (building) return;
                snapshot ();
                f.required = req.active;
                select_row (i);
                touched ();
            });
            row.append (req_box);
            var uniq = new CheckButton ();
            uniq.active = f.unique || f.primary_key;
            uniq.sensitive = !f.primary_key;

            uniq.halign = Align.START;
            uniq.margin_start = 10;
            var uniq_box = new Box (Orientation.HORIZONTAL, 0);
            uniq_box.width_request = W_FLAG;
            uniq_box.append (uniq);
            uniq.toggled.connect (() => {
                if (building) return;
                snapshot ();
                f.unique = uniq.active;
                select_row (i);
                touched ();
            });
            row.append (uniq_box);
            var desc = new Entry ();
            desc.hexpand = true;
            desc.width_chars = 1;
            desc.add_css_class ("db-cell");
            desc.text = f.description;
            desc.changed.connect (() => {
                if (building) return;
                f.description = desc.text;
                touched ();
            });
            focus_selects (desc, i);
            row.append (desc);
            var more = new Button.from_icon_name ("view-more-symbolic");
            more.add_css_class ("flat");
            more.add_css_class ("db-cell-icon");
            more.width_request = W_MENU;
            more.tooltip_text = _("Field Actions");
            more.clicked.connect (() => {
                var menu = new Singularity.Widgets.ContextMenu (more);
                if (i > 0) menu.add_item (_("Move Up"), "go-up-symbolic", () => move_field (i, -1));
                if (i < def.fields.size - 1) menu.add_item (_("Move Down"), "go-down-symbolic", () => move_field (i, 1));
                menu.add_item (_("Insert Field Below"), "list-add-symbolic", () => insert_field (i + 1));
                menu.add_item (f.primary_key ? _("Remove Primary Key") : _("Make Primary Key"), "db-key-symbolic", () => {
                    selected = i;
                    toggle_key ();
                });
                menu.add_separator ();
                menu.add_item (_("Delete Field"), "user-trash-symbolic", () => delete_field (i), "destructive");
                DatabaseWindow.popup_menu (menu);
            });
            row.append (more);
            int ci = 0;
            for (var c = row.get_first_child (); c != null; c = c.get_next_sibling ()) {
                if (ci < columns_sg.length) columns_sg[ci].add_widget (c);
                ci++;
            }
            var click = new GestureClick ();
            click.pressed.connect (() => select_row (i));
            row.add_controller (click);
            return row;
        }

        private void focus_selects (Widget w, int i) {
            var focus = new EventControllerFocus ();
            focus.enter.connect (() => select_row (i));
            w.add_controller (focus);
        }

        private void insert_field (int at) {
            snapshot ();
            var f = new Field (def.unique_field_name (_("Field")), FieldType.TEXT);
            def.fields.insert (at, f);
            origins.insert (at, null);
            selected = at;
            rebuild ();
            touched ();
            focus_name (selected);
        }

        private void select_row (int i) {
            if (selected == i) return;
            selected = i;
            int k = 0;
            for (var c = field_rows.get_first_child (); c != null; c = c.get_next_sibling ()) {
                if (k == i) c.add_css_class ("selected");
                else c.remove_css_class ("selected");
                k++;
            }
            building = true;
            build_inspector ();
            building = false;
        }

        private void change_type (Field f, FieldType nt) {
            if (nt == FieldType.AUTONUMBER) {
                foreach (var o in def.fields) {
                    if (o != f && o.field_type == FieldType.AUTONUMBER) o.field_type = FieldType.INTEGER;
                    o.primary_key = false;
                }
                f.primary_key = true;
            }
            if (f.field_type == FieldType.AUTONUMBER && nt != FieldType.AUTONUMBER) f.primary_key = nt == FieldType.INTEGER && f.primary_key;
            if (nt == FieldType.CHOICE && f.choices.length == 0) {
                f.choices = { _("Option 1"), _("Option 2") };
                try {
                    if (page.src != null && f.name != "" && page.src.def.find (f.name) != null) {
                        string[] found = {};
                        foreach (var v in page.src.distinct_values (f.name, 30)) {
                            if (!v.is_null && v.to_string ().strip () != "") found += v.to_string ();
                        }
                        if (found.length > 0 && found.length <= 20) f.choices = found;
                    }
                } catch (Error e) {
                }
            }
            if (nt == FieldType.LOOKUP && f.lookup_table == "") {
                foreach (string t in page.db.table_names ()) {
                    if (t.casefold () == def.name.casefold ()) continue;
                    f.lookup_table = t;
                    try {
                        var other = page.db.load_table (t);
                        var pk = other.primary_key ();
                        f.lookup_field = pk.size > 0 ? pk[0].name : other.fields[0].name;
                        foreach (var of in other.fields) {
                            if (of.field_type.is_text ()) {
                                f.lookup_display = of.name;
                                break;
                            }
                        }
                    } catch (Error e) {
                    }
                    break;
                }
            }
            if (nt != FieldType.LOOKUP) {
                f.lookup_table = "";
                f.lookup_field = "";
            }
            if (!nt.is_text ()) f.max_length = 0;
            if (nt == FieldType.CURRENCY && f.decimals < 0) f.decimals = 2;
            f.field_type = nt;
        }

        private void build_inspector () {
            sheet.clear ();
            count_label.label = ngettext ("%d field", "%d fields", def.fields.size).printf (def.fields.size);
            if (selected < 0 || selected >= def.fields.size) return;
            var f = def.fields[selected];
            sheet.section (_("Field Properties"), null);
            sheet.add_value (_("Field"), f.name);
            sheet.add_value (_("Data Type"), f.field_type.label ());
            sheet.add_value (_("Stored As"), f.field_type.declared_type ());
            if (f.primary_key) sheet.add_value (_("Key"), _("Primary key, values are unique and required"));
            sheet.add_switch (_("Required"), f.required || f.primary_key, (v) => {
                if (building) return;
                snapshot ();
                f.required = v;
                touched ();
                rebuild ();
            }).sensitive = !f.primary_key;
            sheet.add_switch (_("Unique"), f.unique || f.primary_key, (v) => {
                if (building) return;
                snapshot ();
                f.unique = v;
                touched ();
                rebuild ();
            }).sensitive = !f.primary_key;
            sheet.add_switch (_("Indexed"), f.indexed || f.unique || f.primary_key, (v) => {
                if (building) return;
                snapshot ();
                f.indexed = v;
                touched ();
            }).sensitive = !f.unique && !f.primary_key;
            if (f.field_type.is_text () && f.field_type != FieldType.CHOICE && f.field_type != FieldType.LONG_TEXT) {
                sheet.add_spin (_("Maximum Length"), 0, 100000, 1, f.max_length, (v) => {
                    if (building) return;
                    f.max_length = (int) v;
                    touched ();
                });
            }
            if (f.field_type == FieldType.NUMBER || f.field_type == FieldType.CURRENCY || f.field_type == FieldType.PERCENT) {
                sheet.add_spin (_("Decimal Places"), -1, 10, 1, f.decimals, (v) => {
                    if (building) return;
                    f.decimals = (int) v;
                    touched ();
                });
                sheet.add_note (_("Minus one shows the stored precision."));
            }
            if (f.field_type != FieldType.AUTONUMBER && f.field_type != FieldType.ATTACHMENT) {
                sheet.add_entry (_("Default Value"), f.default_value, (t) => {
                    if (building) return;
                    f.default_value = t;
                    touched ();
                }, f.field_type == FieldType.DATE ? _("Date() for today") : "");
            }
            sheet.add_entry (_("Caption"), f.caption, (t) => {
                if (building) return;
                f.caption = t;
                touched ();
            }, _("Label shown instead of the field name"));
            if (f.field_type != FieldType.ATTACHMENT && f.field_type != FieldType.CHOICE && f.field_type != FieldType.LOOKUP) {
                sheet.add_entry (_("Format"), f.format, (t) => {
                    if (building) return;
                    f.format = t;
                    touched ();
                }, f.field_type.is_temporal () ? _("Short Date, Long Date, dd/mm/yyyy") : (f.field_type.is_numeric () ? _("Currency, Percent, #,##0.00") : _("> for capitals, @@@-@@")));
            }
            if (f.field_type.is_text () && f.field_type != FieldType.LONG_TEXT && f.field_type != FieldType.CHOICE || f.field_type.is_temporal ()) {
                sheet.add_entry (_("Input Mask"), f.input_mask, (t) => {
                    if (building) return;
                    f.input_mask = t;
                    touched ();
                }, _("e.g. (999) 000-0000;0;_ or >LL-000"));
            }
            if (!f.is_calculated ()) {
                sheet.add_entry (_("Validation Rule"), f.validation_rule != "" ? f.validation_rule : f.validation, (t) => {
                    if (building) return;
                    f.validation_rule = t.strip ();
                    f.validation = "";
                    touched ();
                }, _(">0, Between 1 And 10, Like \"A*\""));
                sheet.add_entry (_("Validation Text"), f.validation_text, (t) => {
                    if (building) return;
                    f.validation_text = t;
                    touched ();
                }, _("Message shown when the rule is not met"));
            }
            if (f.field_type == FieldType.CHOICE || f.field_type == FieldType.LOOKUP) {
                sheet.add_switch (_("Allow Multiple Values"), f.multi_value, (v) => {
                    if (building) return;
                    snapshot ();
                    f.multi_value = v;
                    touched ();
                    rebuild ();
                });
            }
            if (f.field_type == FieldType.LONG_TEXT) {
                sheet.add_switch (_("Rich Text"), f.rich_text, (v) => {
                    if (building) return;
                    f.rich_text = v;
                    touched ();
                });
            }
            if (f.field_type != FieldType.AUTONUMBER && f.field_type != FieldType.ATTACHMENT && !f.primary_key) {
                var calc = sheet.add_switch (_("Calculated"), f.is_calculated (), (v) => {
                    if (building) return;
                    snapshot ();
                    f.expression = v ? "[%s]".printf (def.fields[0].name) : "";
                    touched ();
                    rebuild ();
                });
                calc.tooltip_text = _("The value is computed from other fields of the record");
                if (f.is_calculated ()) {
                    var box = new Box (Orientation.HORIZONTAL, 4);
                    var e = new Entry ();
                    e.hexpand = true;
                    e.text = f.expression;
                    e.changed.connect (() => {
                        if (building) return;
                        f.expression = e.text.strip ();
                        touched ();
                    });
                    box.append (e);
                    var b = new Button.from_icon_name ("document-edit-symbolic");
                    b.add_css_class ("flat");
                    b.tooltip_text = _("Expression Builder");
                    b.clicked.connect (() => ExpressionBuilder.show (page.win, def, e.text, (t) => e.text = t));
                    box.append (b);
                    sheet.add_widget (_("Expression"), box);
                }
            }
            sheet.add_entry (_("Description"), f.description, (t) => {
                if (building) return;
                f.description = t;
                touched ();
            }, _("Shown as a hint when entering data"));
            if (f.field_type == FieldType.CHOICE) choices_section (f);
            if (f.field_type == FieldType.LOOKUP) lookup_section (f);
            table_section ();
            index_section ();
        }

        private void choices_section (Field f) {
            var sec = sheet.section (_("Choices"), _("The values offered in the list, in order."));
            sheet.section_button (sec, _("Add"), () => {
                snapshot ();
                string[] c = f.choices;
                c += _("Option %d").printf (c.length + 1);
                f.choices = c;
                rebuild ();
                touched ();
            });
            for (int i = 0; i < f.choices.length; i++) {
                int idx = i;
                var box = new Box (Orientation.HORIZONTAL, 4);
                var e = new Entry ();
                e.hexpand = true;
                e.text = f.choices[i];
                e.changed.connect (() => {
                    if (building) return;
                    string[] c = f.choices;
                    c[idx] = e.text;
                    f.choices = c;
                    touched ();
                });
                box.append (e);
                var rm = new Button.from_icon_name ("list-remove-symbolic");
                rm.add_css_class ("flat");
                rm.add_css_class ("db-small-button");
                rm.tooltip_text = _("Remove Choice");
                rm.clicked.connect (() => {
                    snapshot ();
                    string[] c = {};
                    for (int k = 0; k < f.choices.length; k++) if (k != idx) c += f.choices[k];
                    f.choices = c;
                    rebuild ();
                    touched ();
                });
                box.append (rm);
                sheet.add_widget ("%d".printf (i + 1), box);
            }
        }

        private void lookup_section (Field f) {
            sheet.section (_("Lookup"), _("Values come from a field of another table and are kept consistent."));
            string[] tnames = page.db.table_names ().to_array ();
            int ti = -1;
            for (int i = 0; i < tnames.length; i++) if (tnames[i] == f.lookup_table) ti = i;
            sheet.add_choice (_("Table"), tnames, ti, (i, t) => {
                if (building) return;
                snapshot ();
                f.lookup_table = t;
                try {
                    var other = t.casefold () == def.name.casefold () ? def : page.db.load_table (t);
                    var pk = other.primary_key ();
                    f.lookup_field = pk.size > 0 ? pk[0].name : other.fields[0].name;
                    f.lookup_display = "";
                    foreach (var of in other.fields) {
                        if (of.field_type.is_text ()) {
                            f.lookup_display = of.name;
                            break;
                        }
                    }
                } catch (Error e) {
                }
                Idle.add (() => {
                    rebuild ();
                    return Source.REMOVE;
                });
                touched ();
            });
            string[] fnames = {};
            if (f.lookup_table != "") {
                try {
                    var other = f.lookup_table.casefold () == def.name.casefold () ? def : page.db.load_table (f.lookup_table);
                    foreach (var of in other.fields) fnames += of.name;
                } catch (Error e) {
                }
            }
            int ki = -1, di = -1;
            for (int i = 0; i < fnames.length; i++) {
                if (fnames[i] == f.lookup_field) ki = i;
                if (fnames[i] == (f.lookup_display != "" ? f.lookup_display : f.lookup_field)) di = i;
            }
            sheet.add_choice (_("Stored Field"), fnames, ki, (i, v) => {
                if (building) return;
                snapshot ();
                f.lookup_field = v;
                touched ();
            });
            sheet.add_choice (_("Shown Field"), fnames, di, (i, v) => {
                if (building) return;
                snapshot ();
                f.lookup_display = v;
                touched ();
            });
        }

        private void table_section () {
            var sec = sheet.section (_("Table"), null);
            sheet.section_button (sec, _("Relationships"), () => page.win.open_relationships ());
            sheet.add_entry (_("Description"), def.description, (t) => {
                if (building) return;
                def.description = t;
                touched ();
            });
            sheet.add_entry (_("Validation Rule"), def.validation_rule, (t) => {
                if (building) return;
                def.validation_rule = t.strip ();
                touched ();
            }, _("[End Date] >= [Start Date]"));
            sheet.add_entry (_("Validation Text"), def.validation_text, (t) => {
                if (building) return;
                def.validation_text = t;
                touched ();
            });
            sheet.add_item ("db-run-symbolic", _("Data Macros"), _("Actions that run when records change"), "document-edit-symbolic", () => DataMacroDialog.show (page.win, def.name));
            foreach (var r in def.relationships) {
                var rel = r;
                sheet.add_item ("db-relationship-symbolic", "%s to %s".printf (string.joinv (", ", r.columns), r.ref_table), relationship_summary (r), "list-remove-symbolic", () => {
                    snapshot ();
                    def.relationships.remove (rel);
                    rebuild ();
                    touched ();
                });
            }
        }

        public static string relationship_summary (Relationship r) {
            string[] parts = {};
            parts += r.enforce ? _("Integrity enforced") : _("Not enforced");
            if (r.on_update == RefAction.CASCADE) parts += _("cascade updates");
            if (r.on_delete == RefAction.CASCADE) parts += _("cascade deletes");
            if (r.on_delete == RefAction.SET_NULL) parts += _("clear on delete");
            return string.joinv (", ", parts);
        }

        private void index_section () {
            var sec = sheet.section (_("Indexes"), def.indexes.size == 0 ? _("Indexes on several fields speed up searches that use them together.") : null);
            sheet.section_button (sec, _("Add Index"), () => Dialogs.index_editor (page.win, def, (ix) => {
                snapshot ();
                def.indexes.add (ix);
                rebuild ();
                touched ();
            }));
            foreach (var ix in def.indexes) {
                var index = ix;
                sheet.add_item ("db-key-symbolic", ix.name, "%s%s".printf (string.joinv (", ", ix.columns), ix.unique ? ", " + _("unique") : ""), "list-remove-symbolic", () => {
                    snapshot ();
                    def.indexes.remove (index);
                    rebuild ();
                    touched ();
                });
            }
        }

        public bool apply () {
            var renames = new Gee.HashMap<string, string> ();
            var kept = new Gee.HashSet<string> ();
            for (int i = 0; i < def.fields.size; i++) {
                string? o = origins[i];
                if (o != null) {
                    renames[def.fields[i].name] = o;
                    kept.add (o.casefold ());
                }
            }
            try {
                var current = page.db.load_table (page.object_name);
                string[] lost = {};
                foreach (var f in current.fields) {
                    if (!kept.contains (f.name.casefold ())) lost += f.name;
                }
                def.validate ();
                if (lost.length > 0) {
                    var names = string.joinv (", ", lost);
                    var dlg = new ConfirmDialog (page.win.app, _("Delete Fields and Their Data?"), "user-trash",
                        _("The data in %s will be deleted. You can undo this with Ctrl+Z.").printf (names), _("Delete"), ConfirmDialog.ActionStyle.DESTRUCTIVE);
                    dlg.transient_for = page.win;
                    dlg.response.connect ((r) => {
                        if (r == ConfirmDialog.Response.PRIMARY) commit (renames);
                    });
                    dlg.present ();
                    return false;
                }
                return commit (renames);
            } catch (Error e) {
                page.win.show_error (_("Could Not Save the Design"), e.message);
                return false;
            }
        }

        private bool commit (Gee.HashMap<string, string> renames) {
            try {
                page.db.alter_table (page.object_name, def.copy (), renames);
                reset (page.db.load_table (page.object_name));
                page.win.toast (_("Design saved"));
                page.win.sync_bubbles ();
                return true;
            } catch (Error e) {
                page.win.show_error (_("Could Not Save the Design"), e.message);
                return false;
            }
        }
    }
}
