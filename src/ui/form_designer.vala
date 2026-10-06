using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Database {

    public class CodeDialog {
        public delegate void Saved (string code);

        public static void show (DatabaseWindow win, string title, string code, string? jump_to, owned Saved saved) {
            var dlg = Dialogs.make (win, title, 820, 720);
            var buffer = new GtkSource.Buffer (null);
            var lang = GtkSource.LanguageManager.get_default ().get_language ("sdb-basic");
            if (lang != null) buffer.language = lang;
            buffer.text = code;
            var view = new Singularity.Widgets.SourceView (buffer);
            view.show_line_numbers = true;
            view.auto_indent = true;
            view.tab_width = 4;
            view.insert_spaces_instead_of_tabs = true;
            view.monospace = true;
            SqlTab.apply_scheme (view, buffer, win.app.settings);
            var scroll = new ScrolledWindow ();
            scroll.child = view;
            scroll.vexpand = true;
            scroll.height_request = 480;
            scroll.add_css_class ("db-sql-frame");
            var box = new Box (Orientation.VERTICAL, 8);
            box.margin_start = box.margin_end = 18;
            box.margin_top = 6;
            box.append (scroll);
            var msg = new Label ("");
            msg.wrap = true;
            msg.xalign = 0;
            msg.add_css_class ("db-message");
            msg.visible = false;
            box.append (msg);
            dlg.content_box.append (box);
            if (jump_to != null) {
                int line = 0;
                string[] lines = code.split ("\n");
                for (int i = 0; i < lines.length; i++) {
                    if (lines[i].contains (jump_to)) line = i;
                }
                TextIter it;
                buffer.get_iter_at_line (out it, line + 1);
                buffer.place_cursor (it);
                Idle.add (() => {
                    view.scroll_to_iter (it, 0.2, false, 0, 0);
                    view.grab_focus ();
                    return Source.REMOVE;
                });
            }
            Dialogs.footer (dlg, _("Save"), () => {
                try {
                    ScriptParser.parse_module (buffer.text);
                    saved (buffer.text);
                    return true;
                } catch (Error e) {
                    msg.label = e.message;
                    msg.visible = true;
                    return false;
                }
            });
            dlg.open_dialog ();
        }
    }

    public class CondFormatDialog {
        public delegate void Done (Gee.ArrayList<CondRule> rules);

        public static void show (DatabaseWindow win, string title, Gee.List<CondRule> current, owned Done done) {
            var rules = new Gee.ArrayList<CondRule> ();
            foreach (var r in current) rules.add (r.copy ());
            var dlg = Dialogs.make (win, title, 620, 640);
            var box = Dialogs.body (dlg);
            var list = new Box (Orientation.VERTICAL, 12);
            box.append (list);
            string[] ops = { "between", "not-between", "equal", "not-equal", "greater", "less", "greater-equal", "less-equal", "contains", "empty", "not-empty" };
            string[] op_labels = { _("Between"), _("Not Between"), _("Equal To"), _("Not Equal To"), _("Greater Than"), _("Less Than"), _("At Least"), _("At Most"), _("Contains"), _("Is Empty"), _("Is Not Empty") };
            FilterByForm.Callback rebuild = null;
            rebuild = () => {
                Widget? c;
                while ((c = list.get_first_child ()) != null) list.remove (c);
                for (int i = 0; i < rules.size; i++) {
                    var r = rules[i];
                    int idx = i;
                    var g = new PreferencesGroup (_("Rule %d").printf (i + 1), null);
                    string[] kinds = { _("Field Value"), _("Expression") };
                    var kind = new SelectionRow (_("Condition"), kinds, r.kind == "value" ? kinds[0] : kinds[1]);
                    g.add_row (kind);
                    int oi = 0;
                    for (int k = 0; k < ops.length; k++) if (ops[k] == r.op) oi = k;
                    var op = new SelectionRow (_("Comparison"), op_labels, op_labels[oi]);
                    var v1 = new EntryRow (_("Value"));
                    v1.text = r.value1;
                    var v2 = new EntryRow (_("And"));
                    v2.text = r.value2;
                    var expr = new EntryRow (_("Expression"));
                    expr.text = r.expression;
                    g.add_row (op);
                    g.add_row (v1);
                    g.add_row (v2);
                    g.add_row (expr);
                    var fore = new EntryRow (_("Text Color"));
                    fore.text = r.fore;
                    var back = new EntryRow (_("Fill Color"));
                    back.text = r.back;
                    g.add_row (fore);
                    g.add_row (back);
                    var bold = new SwitchRow (_("Bold"), null, r.bold);
                    var italic = new SwitchRow (_("Italic"), null, r.italic);
                    g.add_row (bold);
                    g.add_row (italic);
                    kind.notify["current-value"].connect (() => r.kind = kind.current_value == kinds[0] ? "value" : "expression");
                    op.notify["current-value"].connect (() => {
                        for (int k = 0; k < ops.length; k++) if (op_labels[k] == op.current_value) r.op = ops[k];
                    });
                    v1.entry_changed.connect (() => r.value1 = v1.text);
                    v2.entry_changed.connect (() => r.value2 = v2.text);
                    expr.entry_changed.connect (() => r.expression = expr.text);
                    fore.entry_changed.connect (() => r.fore = fore.text);
                    back.entry_changed.connect (() => r.back = back.text);
                    bold.notify["active"].connect (() => r.bold = bold.active);
                    italic.notify["active"].connect (() => r.italic = italic.active);
                    var del = new Button.with_label (_("Remove Rule"));
                    del.add_css_class ("destructive-action");
                    del.halign = Align.START;
                    del.clicked.connect (() => {
                        rules.remove_at (idx);
                        rebuild ();
                    });
                    list.append (g);
                    list.append (del);
                }
            };
            rebuild ();
            var add = new Button.with_label (_("New Rule"));
            add.halign = Align.START;
            add.clicked.connect (() => {
                var r = new CondRule ();
                r.kind = "value";
                r.op = "greater";
                r.back = "#f6d32d";
                rules.add (r);
                rebuild ();
            });
            box.append (add);
            Dialogs.footer (dlg, _("Apply"), () => {
                done (rules);
                return true;
            });
            dlg.open_dialog ();
        }
    }

    public class FormDesigner : Box {
        private weak FormPage page;
        private FormDef def;
        private Box canvas_box;
        private Box inspector;
        private PropertySheet sheet;
        private int selected = -1;
        private Gee.ArrayList<string> undo_stack = new Gee.ArrayList<string> ();
        private Gee.ArrayList<string> redo_stack = new Gee.ArrayList<string> ();
        private Gee.HashMap<int, Widget> frames = new Gee.HashMap<int, Widget> ();
        private Gee.HashMap<string, Fixed> containers = new Gee.HashMap<string, Fixed> ();
        private bool building;
        private string tab = "format";
        private ControlKind pending_kind = ControlKind.AUTO;
        private bool placing;

        public signal void changed ();

        public FormDesigner (FormPage page) {
            Object (orientation: Orientation.HORIZONTAL, spacing: 12);
            this.page = page;
            add_css_class ("db-pane-page");
            var left = new Box (Orientation.VERTICAL, 6);
            left.hexpand = true;
            canvas_box = new Box (Orientation.VERTICAL, 0);
            canvas_box.margin_start = canvas_box.margin_top = 12;
            canvas_box.margin_end = canvas_box.margin_bottom = 12;
            var scroll = new ScrolledWindow ();
            scroll.hexpand = true;
            scroll.vexpand = true;
            scroll.child = canvas_box;
            scroll.add_css_class ("db-canvas");
            left.append (scroll);
            append (left);
            var iscroll = new ScrolledWindow ();
            iscroll.hscrollbar_policy = PolicyType.NEVER;
            iscroll.width_request = 340;
            iscroll.hexpand = false;
            inspector = new Box (Orientation.VERTICAL, 8);
            inspector.add_css_class ("db-inspector");
            sheet = new PropertySheet ();
            iscroll.child = inspector;
            iscroll.add_css_class ("db-panel");
            append (iscroll);
        }

        public const string[] CONTROL_ICONS = { "db-type-text-symbolic", "format-text-bold-symbolic", "input-mouse-symbolic", "db-type-choice-symbolic", "view-list-symbolic", "db-type-boolean-symbolic", "radio-checked-symbolic", "media-playlist-shuffle-symbolic", "view-paged-symbolic", "image-x-generic-symbolic", "list-remove-symbolic", "checkbox-symbolic", "db-form-symbolic", "db-report-symbolic" };

        private void add_calculated () {
            add_new (ControlKind.TEXT);
            if (selected >= 0) {
                def.controls[selected].field = "=Now()";
                def.controls[selected].label = _("Calculated");
                rebuild ();
            }
        }

        public void load (FormDef d) {
            def = FormDef.from_json (d.name, d.to_json ());
            undo_stack.clear ();
            redo_stack.clear ();
            selected = -1;
            rebuild ();
        }

        public FormDef current () {
            return def;
        }

        private void snapshot () {
            undo_stack.add (def.to_json ());
            redo_stack.clear ();
        }

        private void touched () {
            if (!building) changed ();
        }

        public void run_action (string action, Variant? param = null) {
            switch (action) {
                case "design-add":
                    if (param != null) add_new ((ControlKind) param.get_int32 ());
                    break;
                case "design-calc":
                    add_calculated ();
                    break;
                case "view-code":
                    edit_code (null);
                    break;
                case "add-field":
                    add_missing ();
                    break;
                case "tidy":
                    snapshot ();
                    def.tidy ();
                    rebuild ();
                    touched ();
                    break;
                case "undo":
                    if (undo_stack.size == 0) {
                        page.win.run_db_undo ();
                        return;
                    }
                    redo_stack.add (def.to_json ());
                    def = FormDef.from_json (def.name, undo_stack.remove_at (undo_stack.size - 1));
                    selected = -1;
                    rebuild ();
                    touched ();
                    break;
                case "redo":
                    if (redo_stack.size == 0) {
                        page.win.run_db_redo ();
                        return;
                    }
                    undo_stack.add (def.to_json ());
                    def = FormDef.from_json (def.name, redo_stack.remove_at (redo_stack.size - 1));
                    selected = -1;
                    rebuild ();
                    touched ();
                    break;
            }
        }

        private TableDef? source_def () {
            try {
                string s = def.source.strip ();
                if (s.down ().has_prefix ("select ")) return new RecordSource.for_sql (page.win.db, AccessSql.statement (s)).def;
                return new RecordSource (page.win.db, s).def;
            } catch (Error e) {
                return null;
            }
        }

        private int next_y (string section) {
            int y = 0;
            foreach (var c in def.controls) {
                if (c.section == section && c.parent == "") y = int.max (y, c.y + (c.height > 0 ? c.height : 60) + 12);
            }
            return y;
        }

        private void add_missing () {
            var sd = source_def ();
            if (sd == null) return;
            foreach (var f in sd.fields) {
                bool present = false;
                foreach (var c in def.controls) if (c.field == f.name) present = true;
                if (!present) {
                    add_field (f);
                    return;
                }
            }
            page.win.toast (_("Every field is already on the form."));
        }

        private void add_field (Field f) {
            snapshot ();
            var c = new FormControl (f.name, f.label ());
            c.y = next_y ("detail");
            c.width = f.field_type == FieldType.LONG_TEXT ? 520 : 320;
            c.height = f.field_type == FieldType.LONG_TEXT ? 132 : 60;
            def.controls.add (c);
            c.name = def.unique_control_name (f.name);
            selected = def.controls.size - 1;
            rebuild ();
            touched ();
        }

        private void add_new (ControlKind k) {
            snapshot ();
            string section = selected >= 0 ? def.controls[selected].section : "detail";
            string parent = "";
            if (selected >= 0) {
                if (def.controls[selected].kind == ControlKind.TAB) parent = def.controls[selected].display_name () + ":0";
                else parent = def.controls[selected].parent;
            }
            var c = new FormControl ("", "");
            c.kind = k;
            c.section = section;
            c.parent = parent;
            c.y = parent != "" ? 0 : next_y (section);
            c.x = 0;
            switch (k) {
                case ControlKind.BUTTON:
                    c.caption = _("Button");
                    c.width = 160;
                    c.height = 40;
                    break;
                case ControlKind.LABEL:
                    c.caption = _("Label");
                    c.width = 240;
                    c.height = 32;
                    break;
                case ControlKind.TAB:
                    c.pages = { _("Page 1"), _("Page 2") };
                    c.width = 640;
                    c.height = 320;
                    break;
                case ControlKind.LINE:
                    c.width = 400;
                    c.height = 4;
                    break;
                case ControlKind.RECTANGLE:
                case ControlKind.IMAGE:
                    c.width = 240;
                    c.height = 160;
                    break;
                case ControlKind.SUBFORM:
                case ControlKind.CHART:
                    c.width = 560;
                    c.height = 260;
                    c.label = k.label ();
                    break;
                case ControlKind.LIST:
                case ControlKind.OPTION_GROUP:
                    c.width = 240;
                    c.height = 140;
                    c.label = k.label ();
                    break;
                default:
                    c.label = k.label ();
                    c.width = 320;
                    c.height = 60;
                    break;
            }
            def.controls.add (c);
            def.name_controls ();
            selected = def.controls.size - 1;
            rebuild ();
            touched ();
        }

        private void rebuild () {
            building = true;
            Widget? child;
            while ((child = canvas_box.get_first_child ()) != null) canvas_box.remove (child);
            frames.clear ();
            containers.clear ();
            string[] sections = { "header", "detail", "footer" };
            string[] titles = { _("Form Header"), _("Detail"), _("Form Footer") };
            for (int s = 0; s < 3; s++) {
                string sec = sections[s];
                bool has = sec == "detail" || (sec == "header" && def.header_height > 0) || (sec == "footer" && def.footer_height > 0);
                foreach (var c in def.controls) if (c.section == sec) has = true;
                if (!has) continue;
                var head = new Label (titles[s]);
                head.add_css_class ("db-section-bar");
                head.halign = Align.FILL;
                head.xalign = 0;
                canvas_box.append (head);
                var fixed = new Fixed ();
                fixed.add_css_class ("db-design-section");
                containers[sec] = fixed;
                string sec_copy = sec;
                var click = new GestureClick ();
                click.pressed.connect ((n, x, y) => {
                    if (fixed.pick (x, y, PickFlags.DEFAULT) == fixed) {
                        selected = -1;
                        refresh_frames ();
                        build_inspector ();
                    }
                });
                fixed.add_controller (click);
                int max_y = sec == "detail" ? 240 : (sec == "header" ? def.header_height : def.footer_height);
                int max_x = 700;
                for (int i = 0; i < def.controls.size; i++) {
                    var c = def.controls[i];
                    if (c.section != sec_copy || c.parent != "") continue;
                    var frame = control_frame (c, i);
                    fixed.put (frame, c.x, c.y);
                    frames[i] = frame;
                    max_y = int.max (max_y, c.y + (c.height > 0 ? c.height : 60) + 40);
                    max_x = int.max (max_x, c.x + c.width + 40);
                }
                fixed.set_size_request (max_x, max_y);
                canvas_box.append (fixed);
            }
            build_inspector ();
            building = false;
        }

        private void refresh_frames () {
            foreach (var e in frames.entries) {
                if (e.key == selected) e.value.add_css_class ("selected");
                else e.value.remove_css_class ("selected");
            }
        }

        private Widget control_frame (FormControl c, int index) {
            var frame = new Box (Orientation.VERTICAL, 2);
            frame.add_css_class ("db-design-control");
            if (index == selected) frame.add_css_class ("selected");
            frame.set_size_request (c.width, c.height > 0 ? c.height : 60);
            if (c.kind == ControlKind.TAB) {
                var tabs = new Box (Orientation.HORIZONTAL, 4);
                for (int p = 0; p < c.pages.length; p++) {
                    var pl = new Label (c.pages[p]);
                    pl.add_css_class ("db-design-tab");
                    tabs.append (pl);
                }
                frame.append (tabs);
                for (int p = 0; p < c.pages.length; p++) {
                    string key = "%s:%d".printf (c.display_name (), p);
                    var inner = new Fixed ();
                    inner.add_css_class ("db-design-page");
                    int mh = 60;
                    for (int j = 0; j < def.controls.size; j++) {
                        var cc = def.controls[j];
                        if (cc.parent != key) continue;
                        var fr = control_frame (cc, j);
                        inner.put (fr, cc.x, cc.y);
                        frames[j] = fr;
                        mh = int.max (mh, cc.y + (cc.height > 0 ? cc.height : 60) + 8);
                    }
                    var pl = new Label (c.pages[p]);
                    pl.add_css_class ("caption");
                    pl.add_css_class ("dim-label");
                    pl.halign = Align.START;
                    frame.append (pl);
                    inner.height_request = mh;
                    frame.append (inner);
                    containers[key] = inner;
                }
            } else {
                string title = c.display_name ();
                if (c.kind == ControlKind.BUTTON || c.kind == ControlKind.LABEL) {
                    if (c.caption != "") title = c.caption;
                } else if (c.label != "") {
                    title = c.label;
                }
                var l = new Label (title);
                l.add_css_class ("db-form-label");
                l.halign = Align.START;
                l.ellipsize = Pango.EllipsizeMode.END;
                frame.append (l);
                string src = _("Unbound");
                if (c.field != "") src = c.field;
                else if (c.kind == ControlKind.SUBFORM) src = c.subform;
                else if (c.kind == ControlKind.CHART) src = c.chart_source;
                var info = new Label ("%s  %s".printf (src, c.kind.label ()));
                info.add_css_class ("caption");
                info.add_css_class ("dim-label");
                info.halign = Align.START;
                info.ellipsize = Pango.EllipsizeMode.END;
                info.vexpand = true;
                info.valign = Align.START;
                frame.append (info);
            }
            var handle = new Image.from_icon_name ("list-drag-handle-symbolic");
            handle.halign = Align.END;
            handle.valign = Align.END;
            handle.tooltip_text = _("Drag to resize");
            handle.set_cursor_from_name ("se-resize");
            frame.append (handle);
            attach_move (frame, index);
            attach_resize (handle, frame, index);
            return frame;
        }

        private void attach_move (Widget frame, int index) {
            var drag = new GestureDrag ();
            int x0 = 0, y0 = 0;
            bool moved = false;
            drag.drag_begin.connect ((x, y) => {
                selected = index;
                x0 = def.controls[index].x;
                y0 = def.controls[index].y;
                moved = false;
                refresh_frames ();
                building = true;
                build_inspector ();
                building = false;
                drag.set_state (EventSequenceState.CLAIMED);
            });
            drag.drag_update.connect ((dx, dy) => {
                if (!moved && Math.fabs (dx) + Math.fabs (dy) < 4) return;
                if (!moved) snapshot ();
                moved = true;
                int nx = int.max (0, (int) Math.round ((x0 + dx) / FormDef.GRID) * FormDef.GRID);
                int ny = int.max (0, (int) Math.round ((y0 + dy) / FormDef.GRID) * FormDef.GRID);
                var parent = frame.get_parent () as Fixed;
                if (parent != null) parent.move (frame, nx, ny);
                def.controls[index].x = nx;
                def.controls[index].y = ny;
            });
            drag.drag_end.connect (() => {
                if (moved) {
                    rebuild ();
                    touched ();
                }
            });
            frame.add_controller (drag);
        }

        private void attach_resize (Widget handle, Widget frame, int index) {
            var drag = new GestureDrag ();
            drag.set_propagation_phase (PropagationPhase.CAPTURE);
            int w0 = 0, h0 = 0;
            drag.drag_begin.connect (() => {
                snapshot ();
                w0 = def.controls[index].width;
                h0 = def.controls[index].height > 0 ? def.controls[index].height : 60;
                drag.set_state (EventSequenceState.CLAIMED);
            });
            drag.drag_update.connect ((dx, dy) => {
                int nw = int.max (FormDef.GRID * 4, (int) Math.round ((w0 + dx) / FormDef.GRID) * FormDef.GRID);
                int nh = int.max (4, (int) Math.round ((h0 + dy) / FormDef.GRID) * FormDef.GRID);
                frame.set_size_request (nw, nh);
                def.controls[index].width = nw;
                def.controls[index].height = nh;
            });
            drag.drag_end.connect (() => {
                rebuild ();
                touched ();
            });
            handle.add_controller (drag);
        }

        private void edit_code (string? proc) {
            string code = def.code;
            string? jump = null;
            if (proc != null) {
                if (!code.contains ("Sub " + proc)) {
                    if (code.strip () == "") code = "Option Compare Database\nOption Explicit\n";
                    string sig = proc.has_suffix ("_BeforeUpdate") || proc.has_suffix ("_Open") || proc.has_suffix ("_Unload") || proc.has_suffix ("_Delete") || proc.has_suffix ("_BeforeInsert") || proc.has_suffix ("_Exit") ? "(Cancel As Integer)" : "()";
                    code = code.chomp () + "\n\nPrivate Sub %s%s\n    \nEnd Sub\n".printf (proc, sig);
                }
                jump = "Sub " + proc;
            }
            CodeDialog.show (page.win, _("Code of %s").printf (def.name), code, jump, (text) => {
                snapshot ();
                def.code = text;
                touched ();
            });
        }

        private void event_row (string label, string event_name, OrderedMap<string> events, string object_name) {
            var box = new Box (Orientation.HORIZONTAL, 4);
            var e = new Entry ();
            e.hexpand = true;
            string cur = events[event_name] ?? "";
            e.text = cur.has_prefix ("{") ? _("[Embedded Macro]") : cur;
            e.placeholder_text = _("None");
            e.changed.connect (() => {
                if (building || e.text == _("[Embedded Macro]")) return;
                if (e.text.strip () == "") events.unset (event_name);
                else events[event_name] = e.text.strip ();
                touched ();
            });
            box.append (e);
            var more = new Button.from_icon_name ("view-more-symbolic");
            more.add_css_class ("flat");
            more.tooltip_text = _("Choose a Builder");
            more.clicked.connect (() => {
                var menu = new ContextMenu (more);
                menu.add_item (_("Code Builder"), "db-sql-symbolic", () => {
                    events[event_name] = "[Event Procedure]";
                    e.text = "[Event Procedure]";
                    edit_code ("%s_%s".printf (object_name.replace (" ", "_"), event_name));
                });
                menu.add_item (_("Macro Builder"), "db-run-symbolic", () => {
                    var m = MacroDef.from_json ("", events[event_name] ?? "") ?? new MacroDef ();
                    var dlg = Dialogs.make (page.win, _("Embedded Macro: %s").printf (label), 760, 640);
                    var body = Dialogs.body (dlg);
                    var ed = new MacroEditor (m, false);
                    ed.height_request = 420;
                    body.append (ed);
                    Dialogs.footer (dlg, _("Save"), () => {
                        snapshot ();
                        if (ed.def.items.size == 0) events.unset (event_name);
                        else events[event_name] = ed.def.to_json ();
                        e.text = ed.def.items.size == 0 ? "" : _("[Embedded Macro]");
                        touched ();
                        return true;
                    });
                    dlg.open_dialog ();
                });
                var macros = page.win.db.object_names ("macro:");
                if (macros.size > 0) {
                    menu.add_separator ();
                    foreach (string mn in macros) {
                        string name = mn;
                        menu.add_item (mn, "db-run-symbolic", () => e.text = name);
                    }
                }
                DatabaseWindow.popup_menu (menu);
            });
            box.append (more);
            sheet.add_widget (label, box);
        }

        private string[] source_names () {
            string[] sources = {};
            foreach (string t in page.win.db.table_names ()) sources += t;
            foreach (string q in page.win.db.view_names ()) sources += q;
            foreach (string q in page.win.db.object_names ("action:")) {
                var sq = SavedQueries.load (page.win.db, q);
                if (sq != null && QueryPrep.is_select_like (sq.sql)) sources += q;
            }
            return sources;
        }

        private void build_inspector () {
            Widget? ch;
            while ((ch = inspector.get_first_child ()) != null) inspector.remove (ch);
            var switcher = new SidebarTabs ();
            switcher.add_option ("format", _("Format"));
            switcher.add_option ("data", _("Data"));
            switcher.add_option ("event", _("Event"));
            switcher.add_option ("other", _("Other"));
            switcher.set_active (tab);
            switcher.selected.connect ((n) => {
                tab = n;
                Idle.add (() => {
                    build_inspector ();
                    return Source.REMOVE;
                });
            });
            switcher.margin_top = 8;
            inspector.append (switcher);
            sheet = new PropertySheet ();
            inspector.append (sheet);
            if (selected >= 0 && selected < def.controls.size) control_properties (def.controls[selected]);
            else form_properties ();
        }

        private void control_properties (FormControl c) {
            var db = page.win.db;
            var sec = sheet.section (c.kind.label (), c.display_name ());
            sheet.section_button (sec, _("Remove"), () => {
                snapshot ();
                string key = c.display_name ();
                var keep = new Gee.ArrayList<FormControl> ();
                foreach (var x in def.controls) {
                    if (x == c || x.parent.has_prefix (key + ":")) continue;
                    keep.add (x);
                }
                def.controls = keep;
                selected = -1;
                rebuild ();
                touched ();
            });
            switch (tab) {
                case "format":
                    if (c.kind == ControlKind.BUTTON || c.kind == ControlKind.LABEL || c.kind == ControlKind.TOGGLE) {
                        sheet.add_entry (_("Caption"), c.caption, (t) => {
                            if (building) return;
                            c.caption = t;
                            touched ();
                        });
                    }
                    if (c.kind.is_bound_kind () || c.kind == ControlKind.SUBFORM || c.kind == ControlKind.CHART) {
                        sheet.add_entry (_("Label"), c.label, (t) => {
                            if (building) return;
                            c.label = t;
                            touched ();
                        });
                        sheet.add_switch (_("Hide Label"), c.hide_label, (v) => {
                            if (building) return;
                            c.hide_label = v;
                            touched ();
                        });
                    }
                    if (c.kind.is_bound_kind ()) {
                        sheet.add_entry (_("Format"), c.format, (t) => {
                            if (building) return;
                            c.format = t;
                            touched ();
                        }, _("e.g. Currency, #,##0.00, Short Date"));
                    }
                    if (c.kind == ControlKind.TAB) {
                        sheet.add_entry (_("Pages"), string.joinv ("; ", c.pages), (t) => {
                            if (building) return;
                            string[] ps = {};
                            foreach (string p in t.split (";")) if (p.strip () != "") ps += p.strip ();
                            c.pages = ps;
                            touched ();
                        }, _("Names separated by semicolons"));
                    }
                    if (c.kind == ControlKind.IMAGE) {
                        sheet.add_item ("image-x-generic-symbolic", _("Picture"), c.image != "" ? _("Embedded") : _("None"), "document-open-symbolic", () => choose_image (c));
                    }
                    if (c.kind == ControlKind.CHART) {
                        string[] types = { "column", "bar", "line", "area", "pie" };
                        string[] tl = { _("Column"), _("Bar"), _("Line"), _("Area"), _("Pie") };
                        int ti = 0;
                        for (int i = 0; i < types.length; i++) if (types[i] == c.chart_type) ti = i;
                        sheet.add_choice (_("Chart Type"), tl, ti, (i, v) => {
                            if (building) return;
                            c.chart_type = types[i];
                            touched ();
                        });
                    }
                    sheet.add_spin (_("Left"), 0, 4000, FormDef.GRID, c.x, (v) => {
                        if (building) return;
                        c.x = (int) v;
                        rebuild ();
                        touched ();
                    });
                    sheet.add_spin (_("Top"), 0, 8000, FormDef.GRID, c.y, (v) => {
                        if (building) return;
                        c.y = (int) v;
                        rebuild ();
                        touched ();
                    });
                    sheet.add_spin (_("Width"), 8, 4000, FormDef.GRID, c.width, (v) => {
                        if (building) return;
                        c.width = (int) v;
                        rebuild ();
                        touched ();
                    });
                    sheet.add_spin (_("Height"), 4, 4000, FormDef.GRID, c.height > 0 ? c.height : 60, (v) => {
                        if (building) return;
                        c.height = (int) v;
                        rebuild ();
                        touched ();
                    });
                    sheet.add_spin (_("Font Size"), 0, 72, 1, c.font_size, (v) => {
                        if (building) return;
                        c.font_size = v;
                        touched ();
                    });
                    sheet.add_switch (_("Bold"), c.bold, (v) => {
                        if (building) return;
                        c.bold = v;
                        touched ();
                    });
                    sheet.add_switch (_("Italic"), c.italic, (v) => {
                        if (building) return;
                        c.italic = v;
                        touched ();
                    });
                    sheet.add_entry (_("Text Color"), c.fore_color, (t) => {
                        if (building) return;
                        c.fore_color = t.strip ();
                        touched ();
                    }, "#1a5fb4");
                    sheet.add_entry (_("Fill Color"), c.back_color, (t) => {
                        if (building) return;
                        c.back_color = t.strip ();
                        touched ();
                    }, "#ffffff");
                    sheet.add_switch (_("Visible"), c.visible, (v) => {
                        if (building) return;
                        c.visible = v;
                        touched ();
                    });
                    if (c.kind.is_bound_kind ()) {
                        sheet.add_item ("db-filter-symbolic", _("Conditional Formatting"), ngettext ("%d rule", "%d rules", c.conditions.size).printf (c.conditions.size), "document-edit-symbolic", () => {
                            CondFormatDialog.show (page.win, _("Conditional Formatting: %s").printf (c.display_name ()), c.conditions, (rules) => {
                                snapshot ();
                                c.conditions = rules;
                                build_inspector ();
                                touched ();
                            });
                        });
                    }
                    break;
                case "data":
                    var sd = source_def ();
                    if (c.kind.is_bound_kind ()) {
                        string[] fields = { _("Unbound") };
                        int fi = 0;
                        if (sd != null) {
                            foreach (var f in sd.fields) {
                                fields += f.name;
                                if (f.name == c.field) fi = fields.length - 1;
                            }
                        }
                        if (!c.is_calculated ()) {
                            sheet.add_choice (_("Control Source"), fields, fi, (i, v) => {
                                if (building) return;
                                snapshot ();
                                c.field = i == 0 ? "" : v;
                                if (i > 0 && c.label == c.kind.label ()) c.label = v;
                                touched ();
                                Idle.add (() => {
                                    rebuild ();
                                    return Source.REMOVE;
                                });
                            });
                        }
                        sheet.add_entry (_("Expression"), c.is_calculated () ? c.field.substring (1) : "", (t) => {
                            if (building) return;
                            if (t.strip () == "") {
                                if (c.is_calculated ()) c.field = "";
                            } else {
                                c.field = "=" + t.strip ();
                            }
                            touched ();
                        }, _("Makes it calculated, e.g. [Qty]*[Price]"));
                        ControlKind[] all = ControlKind.ALL;
                        string[] kl = {};
                        int ki = 0;
                        for (int i = 0; i < all.length; i++) {
                            if (!all[i].is_bound_kind ()) continue;
                            kl += all[i].label ();
                            if (all[i] == c.kind) ki = kl.length - 1;
                        }
                        sheet.add_choice (_("Control Type"), kl, ki, (i, v) => {
                            if (building) return;
                            snapshot ();
                            foreach (var k in all) if (k.label () == v) c.kind = k;
                            Idle.add (() => {
                                rebuild ();
                                return Source.REMOVE;
                            });
                            touched ();
                        });
                        if (c.kind == ControlKind.COMBO || c.kind == ControlKind.LIST || c.kind == ControlKind.OPTION_GROUP) {
                            sheet.add_entry (_("Row Source"), c.row_source, (t) => {
                                if (building) return;
                                c.row_source = t;
                                touched ();
                            }, _("Table, query, SELECT or a;b;c"));
                            sheet.add_spin (_("Bound Column"), 1, 20, 1, c.bound_column, (v) => {
                                if (building) return;
                                c.bound_column = (int) v;
                                touched ();
                            });
                            sheet.add_spin (_("Column Count"), 1, 20, 1, c.column_count, (v) => {
                                if (building) return;
                                c.column_count = (int) v;
                                touched ();
                            });
                        }
                        sheet.add_entry (_("Default Value"), c.default_value, (t) => {
                            if (building) return;
                            c.default_value = t;
                            touched ();
                        });
                        sheet.add_entry (_("Input Mask"), c.input_mask, (t) => {
                            if (building) return;
                            c.input_mask = t;
                            touched ();
                        });
                        sheet.add_entry (_("Validation Rule"), c.validation_rule, (t) => {
                            if (building) return;
                            c.validation_rule = t;
                            touched ();
                        }, ">0");
                        sheet.add_entry (_("Validation Text"), c.validation_text, (t) => {
                            if (building) return;
                            c.validation_text = t;
                            touched ();
                        });
                        sheet.add_switch (_("Enabled"), c.enabled, (v) => {
                            if (building) return;
                            c.enabled = v;
                            touched ();
                        });
                        sheet.add_switch (_("Locked"), c.read_only, (v) => {
                            if (building) return;
                            c.read_only = v;
                            touched ();
                        });
                    }
                    if (c.kind == ControlKind.SUBFORM) {
                        var forms = db.object_names ("form:");
                        string[] fl = {};
                        int si = -1;
                        foreach (string f in forms) {
                            if (f == def.name) continue;
                            fl += f;
                            if (f == c.subform) si = fl.length - 1;
                        }
                        sheet.add_choice (_("Source Object"), fl, si, (i, v) => {
                            if (building) return;
                            c.subform = v;
                            touched ();
                        });
                        sheet.add_entry (_("Link Master Fields"), c.link_master, (t) => {
                            if (building) return;
                            c.link_master = t;
                            touched ();
                        }, "ID");
                        sheet.add_entry (_("Link Child Fields"), c.link_child, (t) => {
                            if (building) return;
                            c.link_child = t;
                            touched ();
                        }, "CustomerID");
                    }
                    if (c.kind == ControlKind.CHART) {
                        string[] srcs = source_names ();
                        int si = -1;
                        for (int i = 0; i < srcs.length; i++) if (srcs[i] == c.chart_source) si = i;
                        sheet.add_choice (_("Data Source"), srcs, si, (i, v) => {
                            if (building) return;
                            c.chart_source = v;
                            touched ();
                            Idle.add (() => {
                                build_inspector ();
                                return Source.REMOVE;
                            });
                        });
                        string[] cols = { "" };
                        foreach (string col in db.columns_of (c.chart_source)) cols += col;
                        int ci = 0, vi = 0, se = 0;
                        for (int i = 0; i < cols.length; i++) {
                            if (cols[i] == c.chart_category) ci = i;
                            if (cols[i] == c.chart_value) vi = i;
                            if (cols[i] == c.chart_series) se = i;
                        }
                        sheet.add_choice (_("Axis"), cols, ci, (i, v) => {
                            if (building) return;
                            c.chart_category = v;
                            touched ();
                        });
                        sheet.add_choice (_("Values"), cols, vi, (i, v) => {
                            if (building) return;
                            c.chart_value = v;
                            touched ();
                        });
                        string[] aggs = { "sum", "avg", "count", "min", "max" };
                        string[] al = { _("Sum"), _("Average"), _("Count"), _("Minimum"), _("Maximum") };
                        int ai = 0;
                        for (int i = 0; i < aggs.length; i++) if (aggs[i] == c.chart_aggregate) ai = i;
                        sheet.add_choice (_("Summary"), al, ai, (i, v) => {
                            if (building) return;
                            c.chart_aggregate = aggs[i];
                            touched ();
                        });
                        sheet.add_choice (_("Legend"), cols, se, (i, v) => {
                            if (building) return;
                            c.chart_series = v;
                            touched ();
                        });
                        sheet.add_entry (_("Link Master Fields"), c.link_master, (t) => {
                            if (building) return;
                            c.link_master = t;
                            touched ();
                        });
                        sheet.add_entry (_("Link Child Fields"), c.link_child, (t) => {
                            if (building) return;
                            c.link_child = t;
                            touched ();
                        });
                    }
                    break;
                case "event":
                    string on = c.display_name ();
                    if (c.kind == ControlKind.BUTTON || c.kind == ControlKind.LABEL || c.kind == ControlKind.IMAGE) {
                        event_row (_("On Click"), "Click", c.events, on);
                        event_row (_("On Double Click"), "DblClick", c.events, on);
                    } else if (c.kind == ControlKind.TAB) {
                        event_row (_("On Change"), "Change", c.events, on);
                    } else if (c.kind.is_bound_kind ()) {
                        event_row (_("Before Update"), "BeforeUpdate", c.events, on);
                        event_row (_("After Update"), "AfterUpdate", c.events, on);
                        event_row (_("On Change"), "Change", c.events, on);
                        event_row (_("On Got Focus"), "GotFocus", c.events, on);
                        event_row (_("On Lost Focus"), "LostFocus", c.events, on);
                        event_row (_("On Click"), "Click", c.events, on);
                        event_row (_("On Double Click"), "DblClick", c.events, on);
                    } else {
                        sheet.add_note (_("This control has no events."));
                    }
                    break;
                default:
                    sheet.add_entry (_("Name"), c.name, (t) => {
                        if (building || t.strip () == "") return;
                        string old = c.display_name ();
                        c.name = t.strip ();
                        foreach (var x in def.controls) {
                            if (x.parent.has_prefix (old + ":")) x.parent = c.name + x.parent.substring (old.length);
                        }
                        touched ();
                    });
                    string[] secs = { "header", "detail", "footer" };
                    string[] sl = { _("Form Header"), _("Detail"), _("Form Footer") };
                    int sidx = 1;
                    for (int i = 0; i < 3; i++) if (secs[i] == c.section) sidx = i;
                    sheet.add_choice (_("Section"), sl, sidx, (i, v) => {
                        if (building) return;
                        snapshot ();
                        c.section = secs[i];
                        c.parent = "";
                        if (secs[i] == "header" && def.header_height == 0) def.header_height = 80;
                        if (secs[i] == "footer" && def.footer_height == 0) def.footer_height = 80;
                        Idle.add (() => {
                            rebuild ();
                            return Source.REMOVE;
                        });
                        touched ();
                    });
                    string[] parents = { _("None") };
                    string[] pkeys = { "" };
                    int pi = 0;
                    foreach (var x in def.controls) {
                        if (x.kind != ControlKind.TAB || x == c) continue;
                        for (int p = 0; p < x.pages.length; p++) {
                            parents += "%s: %s".printf (x.display_name (), x.pages[p]);
                            pkeys += "%s:%d".printf (x.display_name (), p);
                            if (pkeys[pkeys.length - 1] == c.parent) pi = pkeys.length - 1;
                        }
                    }
                    if (parents.length > 1) {
                        sheet.add_choice (_("Tab Page"), parents, pi, (i, v) => {
                            if (building) return;
                            snapshot ();
                            c.parent = pkeys[i];
                            c.x = 0;
                            c.y = 0;
                            Idle.add (() => {
                                rebuild ();
                                return Source.REMOVE;
                            });
                            touched ();
                        });
                    }
                    sheet.add_spin (_("Tab Index"), -1, 999, 1, c.tab_index, (v) => {
                        if (building) return;
                        c.tab_index = (int) v;
                        touched ();
                    });
                    sheet.add_entry (_("Status Bar Text"), c.status_text, (t) => {
                        if (building) return;
                        c.status_text = t;
                        touched ();
                    });
                    break;
            }
        }

        private void choose_image (FormControl c) {
            var fd = new FileDialog ();
            fd.title = _("Choose Picture");
            fd.open.begin (page.win, null, (obj, res) => {
                try {
                    var file = fd.open.end (res);
                    if (file == null) return;
                    uint8[] data;
                    FileUtils.get_data (file.get_path (), out data);
                    if (data.length > 4 * 1024 * 1024) throw new IOError.FAILED (_("The picture is larger than 4 MB."));
                    snapshot ();
                    c.image = Base64.encode (data);
                    rebuild ();
                    touched ();
                } catch (Error e) {
                    if (!(e is Gtk.DialogError.DISMISSED)) page.win.show_error (_("Could Not Use the Picture"), e.message);
                }
            });
        }

        private void form_properties () {
            var db = page.win.db;
            sheet.section (_("Form"), def.name);
            switch (tab) {
                case "format":
                    sheet.add_entry (_("Caption"), def.title, (t) => {
                        if (building) return;
                        def.title = t;
                        touched ();
                    });
                    string[] views = { "single", "continuous", "datasheet", "split", "navigation" };
                    string[] vl = { _("Single Form"), _("Continuous Forms"), _("Datasheet"), _("Split Form"), _("Navigation Form") };
                    int vi = 0;
                    for (int i = 0; i < views.length; i++) if (views[i] == def.default_view) vi = i;
                    sheet.add_choice (_("Default View"), vl, vi, (i, v) => {
                        if (building) return;
                        def.default_view = views[i];
                        touched ();
                        Idle.add (() => {
                            build_inspector ();
                            return Source.REMOVE;
                        });
                    });
                    if (def.default_view == "split") {
                        string[] pos = { "top", "bottom" };
                        string[] pl = { _("Datasheet on Top"), _("Datasheet on Bottom") };
                        sheet.add_choice (_("Split Orientation"), pl, def.split_position == "bottom" ? 1 : 0, (i, v) => {
                            if (building) return;
                            def.split_position = pos[i];
                            touched ();
                        });
                    }
                    if (def.default_view == "navigation") {
                        sheet.add_entry (_("Navigation Tabs"), string.joinv ("; ", def.navigation), (t) => {
                            if (building) return;
                            string[] ns = {};
                            foreach (string n in t.split (";")) if (n.strip () != "") ns += n.strip ();
                            def.navigation = ns;
                            touched ();
                        }, _("Form names separated by semicolons"));
                    }
                    sheet.add_switch (_("Navigation Buttons"), def.navigation_buttons, (v) => {
                        if (building) return;
                        def.navigation_buttons = v;
                        touched ();
                    });
                    sheet.add_spin (_("Header Height"), 0, 600, FormDef.GRID, def.header_height, (v) => {
                        if (building) return;
                        def.header_height = (int) v;
                        rebuild ();
                        touched ();
                    });
                    sheet.add_spin (_("Footer Height"), 0, 600, FormDef.GRID, def.footer_height, (v) => {
                        if (building) return;
                        def.footer_height = (int) v;
                        rebuild ();
                        touched ();
                    });
                    break;
                case "data":
                    string[] sources = source_names ();
                    int si = -1;
                    for (int i = 0; i < sources.length; i++) if (sources[i] == def.source) si = i;
                    sheet.add_choice (_("Record Source"), sources, si, (i, v) => {
                        if (building || v == def.source) return;
                        snapshot ();
                        def.source = v;
                        touched ();
                        Idle.add (() => {
                            rebuild ();
                            return Source.REMOVE;
                        });
                    });
                    sheet.add_entry (_("Record Source SQL"), def.source.down ().has_prefix ("select ") ? def.source : "", (t) => {
                        if (building || t.strip () == "") return;
                        def.source = t.strip ();
                        touched ();
                    }, "SELECT * FROM ...");
                    sheet.add_entry (_("Filter"), def.filter, (t) => {
                        if (building) return;
                        def.filter = t;
                        touched ();
                    }, "[City] = 'Rome'");
                    sheet.add_switch (_("Filter on Load"), def.filter_on_load, (v) => {
                        if (building) return;
                        def.filter_on_load = v;
                        touched ();
                    });
                    sheet.add_entry (_("Order By"), def.sort, (t) => {
                        if (building) return;
                        def.sort = t;
                        touched ();
                    }, "[Name] DESC");
                    sheet.add_switch (_("Data Entry"), def.data_entry, (v) => {
                        if (building) return;
                        def.data_entry = v;
                        touched ();
                    });
                    sheet.add_switch (_("Allow Additions"), def.allow_add, (v) => {
                        if (building) return;
                        def.allow_add = v;
                        touched ();
                    });
                    sheet.add_switch (_("Allow Edits"), def.allow_edit, (v) => {
                        if (building) return;
                        def.allow_edit = v;
                        touched ();
                    });
                    sheet.add_switch (_("Allow Deletions"), def.allow_delete, (v) => {
                        if (building) return;
                        def.allow_delete = v;
                        touched ();
                    });
                    var sd = source_def ();
                    if (sd != null) {
                        bool header = false;
                        foreach (var f in sd.fields) {
                            bool present = false;
                            foreach (var c in def.controls) if (c.field == f.name) present = true;
                            if (present) continue;
                            if (!header) {
                                sheet.section (_("Available Fields"), _("Fields of the record source that are not on the form."));
                                header = true;
                            }
                            var field = f;
                            sheet.add_item (f.field_type.icon_name (), f.name, f.field_type.label (), "list-add-symbolic", () => add_field (field));
                        }
                    }
                    if (db.object_exists (def.source, "table")) {
                        bool header = false;
                        foreach (var r in db.relationships_to (def.source)) {
                            if (r.columns.length != 1) continue;
                            if (!header) {
                                sheet.section (_("Related Tables"), _("Add a subform that shows related records."));
                                header = true;
                            }
                            var rel = r;
                            sheet.add_item ("db-table-symbolic", r.table, _("Linked by %s").printf (r.columns[0]), "list-add-symbolic", () => add_related_subform (rel));
                        }
                    }
                    break;
                case "event":
                    string[,] evs = {
                        { _("On Open"), "Open" }, { _("On Load"), "Load" }, { _("On Current"), "Current" },
                        { _("Before Insert"), "BeforeInsert" }, { _("After Insert"), "AfterInsert" },
                        { _("Before Update"), "BeforeUpdate" }, { _("After Update"), "AfterUpdate" },
                        { _("On Dirty"), "Dirty" }, { _("On Delete"), "Delete" }, { _("After Delete Confirm"), "AfterDelConfirm" },
                        { _("On Unload"), "Unload" }, { _("On Close"), "Close" }
                    };
                    for (int i = 0; i < evs.length[0]; i++) event_row (evs[i, 0], evs[i, 1], def.events, "Form");
                    break;
                default:
                    sheet.add_switch (_("Modal"), def.modal, (v) => {
                        if (building) return;
                        def.modal = v;
                        touched ();
                    });
                    sheet.add_item ("db-sql-symbolic", _("Code"), def.code.strip () != "" ? _("This form has code") : _("No code yet"), "document-edit-symbolic", () => edit_code (null));
                    break;
            }
        }

        private void add_related_subform (Relationship rel) {
            var db = page.win.db;
            string sub_name = db.unique_object_name ("%s %s".printf (def.name, rel.table));
            try {
                var sub = FormDef.generate (db, rel.table, FormLayout.TABULAR);
                sub.name = sub_name;
                sub.default_view = "datasheet";
                sub.subforms.clear ();
                var keep = new Gee.ArrayList<FormControl> ();
                foreach (var c in sub.controls) if (c.field != rel.columns[0]) keep.add (c);
                sub.controls = keep;
                db.save_object_meta (_("Create Form"), "form:", sub_name, sub.to_json ());
            } catch (Error e) {
                page.win.show_error (_("Could Not Create the Subform"), e.message);
                return;
            }
            snapshot ();
            var c = new FormControl ("", rel.table);
            c.kind = ControlKind.SUBFORM;
            c.subform = sub_name;
            c.link_master = rel.ref_columns[0];
            c.link_child = rel.columns[0];
            c.y = next_y ("detail");
            c.width = 640;
            c.height = 260;
            def.controls.add (c);
            def.name_controls ();
            selected = def.controls.size - 1;
            page.win.rebuild_sidebar ();
            rebuild ();
            touched ();
        }
    }
}
