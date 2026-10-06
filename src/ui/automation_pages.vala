using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Database {

    public class MacroEditor : Box {
        public MacroDef def;
        private bool data_mode;
        private Box list;
        private bool building;
        private Gee.ArrayList<string> undo_stack = new Gee.ArrayList<string> ();

        public signal void changed ();

        public MacroEditor (MacroDef def, bool data_mode) {
            Object (orientation: Orientation.VERTICAL, spacing: 10);
            this.def = def;
            this.data_mode = data_mode;
            add_css_class ("db-macro-editor");
            list = new Box (Orientation.VERTICAL, 8);
            var scroll = new ScrolledWindow ();
            scroll.vexpand = true;
            scroll.hscrollbar_policy = PolicyType.NEVER;
            var clamp = new Box (Orientation.VERTICAL, 0);
            clamp.margin_start = clamp.margin_end = 24;
            clamp.margin_top = 12;
            clamp.margin_bottom = 12;
            clamp.append (list);
            scroll.child = clamp;
            append (scroll);
            append (add_bar (def.items, null));
            rebuild ();
        }

        public void load (MacroDef d) {
            def = d;
            rebuild ();
        }

        private void touched () {
            if (!building) changed ();
        }

        private void snapshot () {
            undo_stack.add (def.to_json ());
        }

        public bool undo () {
            if (undo_stack.size == 0) return false;
            var d = MacroDef.from_json (def.name, undo_stack.remove_at (undo_stack.size - 1));
            if (d != null) {
                def = d;
                rebuild ();
                changed ();
            }
            return true;
        }

        private string[] action_labels (out Gee.ArrayList<MacroAction> acts) {
            acts = new Gee.ArrayList<MacroAction> ();
            string[] labels = {};
            foreach (var a in MacroCatalog.all ()) {
                if (data_mode && !a.data && a.name != "SetLocalVar" && a.name != "StopMacro" && a.name != "RaiseError") continue;
                if (!data_mode && a.data) continue;
                acts.add (a);
                labels += a.label;
            }
            return labels;
        }

        private Widget add_bar (Gee.List<MacroItem> target, MacroItem? parent) {
            var bar = new Box (Orientation.HORIZONTAL, 6);
            bar.add_css_class ("db-macro-addbar");
            bar.margin_start = bar.margin_end = 24;
            bar.margin_bottom = parent == null ? 12 : 0;
            Gee.ArrayList<MacroAction> acts;
            string[] labels = { _("Add New Action") };
            foreach (string l in action_labels (out acts)) labels += l;
            var dd = new DropDown.from_strings (labels);
            dd.enable_search = true;
            dd.expression = new PropertyExpression (typeof (StringObject), null, "string");
            dd.hexpand = true;
            dd.notify["selected"].connect (() => {
                if (dd.selected == 0 || building) return;
                snapshot ();
                var a = acts[(int) dd.selected - 1];
                var it = new MacroItem ("action", a.name);
                foreach (string arg in a.args) it.args[arg] = "";
                target.add (it);
                Idle.add (() => {
                    dd.selected = 0;
                    rebuild ();
                    return Source.REMOVE;
                });
                touched ();
            });
            bar.append (dd);
            string[] kinds = { "if", "group", "comment" };
            string[] kind_labels = { _("If"), _("Group"), _("Comment") };
            if (!data_mode && parent == null) {
                kinds += "submacro";
                kind_labels += _("Submacro");
            }
            for (int i = 0; i < kinds.length; i++) {
                string k = kinds[i];
                var b = new Button.with_label (kind_labels[i]);
                b.clicked.connect (() => {
                    snapshot ();
                    var it = new MacroItem (k);
                    if (k == "submacro") it.name = _("Submacro%d").printf (target.size + 1);
                    if (k == "group") it.name = _("Group");
                    target.add (it);
                    rebuild ();
                    touched ();
                });
                bar.append (b);
            }
            return bar;
        }

        public void rebuild () {
            building = true;
            Widget? c;
            while ((c = list.get_first_child ()) != null) list.remove (c);
            if (def.items.size == 0) {
                var hint = new Label (data_mode ? _("Add actions that run when records change.") : _("Add actions to automate the database. They run from top to bottom."));
                hint.add_css_class ("dim-label");
                hint.margin_top = 24;
                hint.wrap = true;
                list.append (hint);
            }
            append_items (list, def.items, 0);
            building = false;
        }

        private void append_items (Box into, Gee.List<MacroItem> items, int depth) {
            for (int i = 0; i < items.size; i++) {
                into.append (item_widget (items, i, depth));
            }
        }

        private Button tool (string icon, string tip) {
            var b = new Button.from_icon_name (icon);
            b.add_css_class ("flat");
            b.add_css_class ("db-small-button");
            b.tooltip_text = tip;
            return b;
        }

        private Widget item_widget (Gee.List<MacroItem> items, int index, int depth) {
            var it = items[index];
            var card = new Box (Orientation.VERTICAL, 6);
            card.add_css_class ("db-macro-card");
            card.add_css_class ("card");
            var head = new Box (Orientation.HORIZONTAL, 6);
            head.margin_start = head.margin_end = 10;
            head.margin_top = 8;
            string title;
            switch (it.kind) {
                case "if": title = _("If"); break;
                case "elseif": title = _("Else If"); break;
                case "else": title = _("Else"); break;
                case "group": title = _("Group"); break;
                case "comment": title = _("Comment"); break;
                case "submacro": title = _("Submacro"); break;
                default:
                    var spec = MacroCatalog.find (it.action);
                    title = spec != null ? spec.label : it.action;
                    break;
            }
            var t = new Label (title);
            t.add_css_class ("heading");
            t.halign = Align.START;
            head.append (t);
            if (it.kind == "if" || it.kind == "elseif") {
                var cond = new Entry ();
                cond.text = it.condition;
                cond.placeholder_text = _("Condition, e.g. [Total] > 100");
                cond.hexpand = true;
                cond.changed.connect (() => {
                    it.condition = cond.text;
                    touched ();
                });
                head.append (cond);
                var then = new Label (_("Then"));
                then.add_css_class ("dim-label");
                head.append (then);
            } else if (it.kind == "submacro" || it.kind == "group") {
                var name = new Entry ();
                name.text = it.name;
                name.hexpand = true;
                name.changed.connect (() => {
                    it.name = name.text.strip ();
                    touched ();
                });
                head.append (name);
            } else {
                var spacer = new Box (Orientation.HORIZONTAL, 0);
                spacer.hexpand = true;
                head.append (spacer);
            }
            var up = tool ("go-up-symbolic", _("Move Up"));
            up.sensitive = index > 0;
            up.clicked.connect (() => {
                snapshot ();
                var x = items.remove_at (index);
                items.insert (index - 1, x);
                rebuild ();
                touched ();
            });
            head.append (up);
            var down = tool ("go-down-symbolic", _("Move Down"));
            down.sensitive = index < items.size - 1;
            down.clicked.connect (() => {
                snapshot ();
                var x = items.remove_at (index);
                items.insert (index + 1, x);
                rebuild ();
                touched ();
            });
            head.append (down);
            if (it.kind == "if" || it.kind == "elseif") {
                var more = tool ("list-add-symbolic", _("Add Else If or Else"));
                more.clicked.connect (() => {
                    var menu = new ContextMenu (more);
                    menu.add_item (_("Add Else If"), "list-add-symbolic", () => {
                        snapshot ();
                        int at = index + 1;
                        while (at < items.size && (items[at].kind == "elseif" || items[at].kind == "else")) at++;
                        items.insert (at, new MacroItem ("elseif"));
                        rebuild ();
                        touched ();
                    });
                    menu.add_item (_("Add Else"), "list-add-symbolic", () => {
                        snapshot ();
                        int at = index + 1;
                        while (at < items.size && items[at].kind == "elseif") at++;
                        if (at < items.size && items[at].kind == "else") return;
                        items.insert (at, new MacroItem ("else"));
                        rebuild ();
                        touched ();
                    });
                    DatabaseWindow.popup_menu (menu);
                });
                head.append (more);
            }
            var del = tool ("user-trash-symbolic", _("Delete"));
            del.clicked.connect (() => {
                snapshot ();
                items.remove_at (index);
                rebuild ();
                touched ();
            });
            head.append (del);
            card.append (head);
            var body = new Box (Orientation.VERTICAL, 6);
            body.margin_start = 10 + (it.kind == "action" ? 0 : 12);
            body.margin_end = 10;
            body.margin_bottom = 10;
            if (it.kind == "comment") {
                var tv = new TextView ();
                tv.wrap_mode = WrapMode.WORD_CHAR;
                tv.buffer.text = it.comment;
                tv.add_css_class ("db-macro-comment");
                tv.buffer.changed.connect (() => {
                    it.comment = tv.buffer.text;
                    touched ();
                });
                body.append (tv);
            } else if (it.kind == "action") {
                var spec = MacroCatalog.find (it.action);
                string[] args = spec != null ? spec.args : new string[0];
                if (spec == null) {
                    string[] keys = {};
                    foreach (var e in it.args.entries) keys += e.key;
                    args = keys;
                }
                var grid = new Grid ();
                grid.column_spacing = 12;
                grid.row_spacing = 4;
                int r = 0;
                foreach (string a in args) {
                    var l = new Label (arg_label (a));
                    l.add_css_class ("dim-label");
                    l.halign = Align.END;
                    grid.attach (l, 0, r, 1, 1);
                    var e = new Entry ();
                    e.hexpand = true;
                    e.text = it.arg (a);
                    e.placeholder_text = arg_hint (a);
                    string key = a;
                    e.changed.connect (() => {
                        it.args[key] = e.text;
                        touched ();
                    });
                    grid.attach (e, 1, r++, 1, 1);
                }
                if (!data_mode && it.action != "") {
                    var l = new Label (_("Only If"));
                    l.add_css_class ("dim-label");
                    l.halign = Align.END;
                    grid.attach (l, 0, r, 1, 1);
                    var cond = new Entry ();
                    cond.hexpand = true;
                    cond.text = it.condition;
                    cond.placeholder_text = _("Optional condition");
                    cond.changed.connect (() => {
                        it.condition = cond.text;
                        touched ();
                    });
                    grid.attach (cond, 1, r++, 1, 1);
                }
                body.append (grid);
                if (it.action.down () == "createrecord" || it.action.down () == "lookuprecord" || it.action.down () == "foreachrecord" || it.action.down () == "editrecord") {
                    var inner = new Box (Orientation.VERTICAL, 6);
                    inner.margin_start = 12;
                    append_items (inner, it.children, depth + 1);
                    body.append (inner);
                    body.append (add_bar (it.children, it));
                }
            }
            if (it.kind != "action" && it.kind != "comment") {
                var inner = new Box (Orientation.VERTICAL, 6);
                append_items (inner, it.children, depth + 1);
                body.append (inner);
                body.append (add_bar (it.children, it));
            }
            card.append (body);
            return card;
        }

        private static string arg_label (string a) {
            var sb = new StringBuilder ();
            for (int i = 0; i < a.length; i++) {
                if (i > 0 && a[i].isupper () && !a[i - 1].isupper ()) sb.append_c (' ');
                sb.append_c (a[i]);
            }
            return sb.str;
        }

        private static string arg_hint (string a) {
            switch (a) {
                case "View": return _("Form, Design, Datasheet, Print Preview, Report");
                case "WindowMode": return _("Normal, Hidden, Dialog");
                case "DataMode": return _("Add, Edit, Read Only");
                case "ObjectType": return _("Table, Query, Form, Report, Macro");
                case "Record": return _("Previous, Next, First, Last, Go To, New");
                case "Type": return _("None, Critical, Warning?, Warning!, Information");
                case "Goto": return _("Next, Macro Name, Fail");
                case "WhereCondition": return _("e.g. [City] = 'Rome'");
                case "Expression":
                case "Value": return _("Expression, e.g. =[Price] * 2");
                case "OutputFormat": return _("PDF, Excel, HTML, Text");
                default: return "";
            }
        }
    }

    public class MacroPage : ObjectPage {
        public bool unsaved;
        private MacroEditor editor;
        private string saved_json;
        private static int counter;

        public MacroPage (DatabaseWindow win, string name) throws Error {
            base (win, "macro", name);
            var def = MacroDef.from_json (name, win.db.get_meta ("macro:" + name));
            if (def == null) throw new SchemaError.NOT_FOUND (_("The macro \"%s\" does not exist.").printf (name));
            build (def);
        }

        public MacroPage.untitled (DatabaseWindow win) {
            base (win, "macro", "\n%d".printf (++counter));
            unsaved = true;
            var def = new MacroDef ();
            build (def);
        }

        private void build (MacroDef def) {
            add_css_class ("db-content");
            editor = new MacroEditor (def, false);
            editor.vexpand = true;
            editor.changed.connect (() => {
                title_changed ();
                win.sync_bubbles ();
            });
            append (editor);
            saved_json = unsaved ? "" : def.to_json ();
            mode = "design";
        }

        public override string title () {
            string n = object_name;
            if (unsaved) n = _("Macro %s").printf (object_name.strip ());
            return n + (dirty () ? " *" : "");
        }

        public override string icon_name () {
            return "db-run-symbolic";
        }

        public override string[] bubbles () {
            return { "run" };
        }

        public override bool dirty () {
            if (unsaved) return editor.def.items.size > 0;
            return editor.def.to_json () != saved_json;
        }

        public override bool handles (string action) {
            return action == "run" || action == "undo" || action == "print";
        }

        public override void run_action (string action, Variant? param) {
            if (action == "print") {
                TextPrinter.print (win, unsaved ? _("Macro") : object_name, editor.def.listing ());
                return;
            }
            if (action == "undo") {
                if (!editor.undo ()) win.run_db_undo ();
                return;
            }
            if (action == "run") {
                if (dirty () && !save ()) return;
                if (unsaved) return;
                win.run_macro (object_name);
            }
        }

        public override bool save () {
            if (unsaved) {
                Dialogs.ask_name (win, _("Save Macro"), win.db.unique_object_name (_("Macro")), (n) => {
                    if (win.db.get_meta ("macro:" + n) != null) {
                        win.show_error (_("Could Not Save"), _("An object named \"%s\" already exists.").printf (n));
                        return false;
                    }
                    string old_key = key ();
                    if (!store (n)) return false;
                    unsaved = false;
                    object_name = n;
                    win.adopt_page (this, old_key);
                    title_changed ();
                    return true;
                });
                return false;
            }
            return store (object_name);
        }

        private bool store (string name) {
            try {
                editor.def.name = name;
                win.db.save_object_meta (_("Save Macro"), "macro:", name, editor.def.to_json ());
                saved_json = editor.def.to_json ();
                win.rebuild_sidebar ();
                win.toast (_("Macro saved"));
                title_changed ();
                return true;
            } catch (Error e) {
                win.show_error (_("Could Not Save the Macro"), e.message);
                return false;
            }
        }

        public override void reload () {
            if (dirty () || unsaved) return;
            var d = MacroDef.from_json (object_name, win.db.get_meta ("macro:" + object_name));
            if (d == null) return;
            editor.load (d);
            saved_json = d.to_json ();
        }
    }

    public class ModulePage : ObjectPage {
        public bool unsaved;
        private GtkSource.Buffer buffer;
        private Singularity.Widgets.SourceView view;
        private Label message;
        private TextView immediate;
        private Entry command;
        private string saved = "";
        private static int counter;
        private ulong printed_id;

        public ModulePage (DatabaseWindow win, string name) throws Error {
            base (win, "module", name);
            var o = Meta.parse_object (win.db.get_meta ("module:" + name));
            if (o == null) throw new SchemaError.NOT_FOUND (_("The module \"%s\" does not exist.").printf (name));
            build (o.get_string_member_with_default ("code", ""));
            saved = buffer.text;
        }

        public ModulePage.untitled (DatabaseWindow win) {
            base (win, "module", "\n%d".printf (++counter));
            unsaved = true;
            build ("Option Compare Database\nOption Explicit\n\nPublic Sub Hello()\n    MsgBox \"Hello from the database\"\nEnd Sub\n");
        }

        public static string template_code () {
            return "Option Compare Database\nOption Explicit\n";
        }

        private void build (string code) {
            add_css_class ("db-content");
            mode = "design";
            buffer = new GtkSource.Buffer (null);
            var lang = GtkSource.LanguageManager.get_default ().get_language ("sdb-basic");
            if (lang != null) buffer.language = lang;
            buffer.highlight_syntax = true;
            buffer.text = code;
            view = new Singularity.Widgets.SourceView (buffer);
            view.show_line_numbers = true;
            view.highlight_current_line = true;
            view.auto_indent = true;
            view.tab_width = 4;
            view.insert_spaces_instead_of_tabs = true;
            view.monospace = true;
            view.add_css_class ("db-sql-view");
            SqlTab.apply_scheme (view, buffer, win.app.settings);
            buffer.changed.connect (() => {
                title_changed ();
                win.sync_bubbles ();
            });
            var scroll = new ScrolledWindow ();
            scroll.vexpand = true;
            scroll.child = view;
            scroll.add_css_class ("db-sql-frame");
            var top = new Box (Orientation.VERTICAL, 6);
            top.append (scroll);
            message = new Label ("");
            message.add_css_class ("db-message");
            message.halign = Align.START;
            message.wrap = true;
            message.selectable = true;
            message.visible = false;
            top.append (message);
            var bottom = new Box (Orientation.VERTICAL, 4);
            var il = new Label (_("Immediate"));
            il.add_css_class ("heading");
            il.halign = Align.START;
            bottom.append (il);
            immediate = new TextView ();
            immediate.editable = false;
            immediate.monospace = true;
            immediate.wrap_mode = WrapMode.WORD_CHAR;
            immediate.buffer.text = win.host != null ? win.host.immediate.str : "";
            var iscroll = new ScrolledWindow ();
            iscroll.vexpand = true;
            iscroll.child = immediate;
            iscroll.add_css_class ("db-sql-frame");
            bottom.append (iscroll);
            command = new Entry ();
            command.placeholder_text = _("Type ? followed by an expression, or a statement, and press Enter");
            command.add_css_class ("monospace");
            command.activate.connect (() => run_immediate ());
            bottom.append (command);
            var paned = new Paned (Orientation.VERTICAL);
            paned.start_child = top;
            paned.end_child = bottom;
            paned.resize_start_child = true;
            paned.shrink_end_child = false;
            paned.vexpand = true;
            paned.position = 460;
            paned.add_css_class ("db-pane-page");
            append (paned);
            if (win.host != null) printed_id = win.host.printed.connect ((t) => {
                immediate.buffer.text = win.host.immediate.str;
            });
        }

        public override void dispose () {
            if (printed_id != 0 && win != null && win.host != null) win.host.disconnect (printed_id);
            printed_id = 0;
            base.dispose ();
        }

        private void run_immediate () {
            string t = command.text.strip ();
            if (t == "" || win.runtime == null) return;
            win.host.debug_print ("> " + t);
            try {
                if (t.has_prefix ("?")) {
                    var v = win.runtime.evaluate (t.substring (1));
                    win.host.debug_print (v.debug ());
                } else {
                    win.runtime.run_statements (t);
                }
            } catch (Error e) {
                win.host.debug_print (_("Error: %s").printf (e.message));
            }
            command.text = "";
        }

        public override string title () {
            string n = object_name;
            if (unsaved) n = _("Module %s").printf (object_name.strip ());
            return n + (dirty () ? " *" : "");
        }

        public override string icon_name () {
            return "db-sql-symbolic";
        }

        public override string[] bubbles () {
            return { "run" };
        }

        public override bool dirty () {
            if (unsaved) return buffer.text.strip () != "";
            return buffer.text != saved;
        }

        public override bool handles (string action) {
            return action == "run" || action == "print";
        }

        public override void focus_content () {
            view.grab_focus ();
        }

        public override void run_action (string action, Variant? param) {
            if (action == "print") {
                TextPrinter.print (win, unsaved ? _("Module") : object_name, buffer.text);
                return;
            }
            if (action != "run" || win.runtime == null) return;
            SModule m;
            try {
                m = ScriptParser.parse_module (buffer.text, unsaved ? "Scratch" : object_name);
            } catch (Error e) {
                show_message (e.message, true);
                return;
            }
            TextIter it;
            buffer.get_iter_at_mark (out it, buffer.get_insert ());
            int line = it.get_line () + 1;
            SProcedure? target = null;
            foreach (var p in m.procedures) {
                if (p.line <= line && p.params.size == 0) target = p;
            }
            if (target == null) {
                foreach (var p in m.procedures) {
                    if (p.params.size == 0) {
                        target = p;
                        break;
                    }
                }
            }
            if (target == null) {
                show_message (_("Put the cursor inside a Sub without arguments to run it."), true);
                return;
            }
            try {
                win.runtime.add_module (m);
                win.runtime.call (target.name, {}, null, m);
                show_message (_("%s finished.").printf (target.name), false);
            } catch (Error e) {
                if (e is ScriptError.CANCELLED) return;
                show_message (_("Run-time error: %s").printf (e.message), true);
            }
        }

        private void show_message (string text, bool error) {
            message.label = text;
            message.visible = text != "";
            if (error) message.add_css_class ("error");
            else message.remove_css_class ("error");
        }

        public override bool save () {
            if (unsaved) {
                Dialogs.ask_name (win, _("Save Module"), win.db.unique_object_name (_("Module")), (n) => {
                    if (win.db.get_meta ("module:" + n) != null) {
                        win.show_error (_("Could Not Save"), _("An object named \"%s\" already exists.").printf (n));
                        return false;
                    }
                    string old_key = key ();
                    if (!store (n)) return false;
                    unsaved = false;
                    object_name = n;
                    win.adopt_page (this, old_key);
                    title_changed ();
                    return true;
                });
                return false;
            }
            return store (object_name);
        }

        private bool store (string name) {
            string code = buffer.text;
            try {
                var m = ScriptParser.parse_module (code, name);
                if (win.runtime != null) win.runtime.add_module (m);
                show_message ("", false);
            } catch (Error e) {
                show_message (_("Saved with errors: %s").printf (e.message), true);
            }
            try {
                var b = new Json.Builder ();
                b.begin_object ();
                b.set_member_name ("code").add_string_value (code);
                b.end_object ();
                win.db.save_object_meta (_("Save Module"), "module:", name, Json.to_string (b.get_root (), false));
                saved = code;
                win.rebuild_sidebar ();
                title_changed ();
                return true;
            } catch (Error e) {
                win.show_error (_("Could Not Save the Module"), e.message);
                return false;
            }
        }
    }

    public class DataMacroDialog {
        public static void show (DatabaseWindow win, string table) {
            var macros = DataMacros.load (win.db, table);
            var dlg = Dialogs.make (win, _("Data Macros for \"%s\"").printf (table), 760, 720);
            var box = Dialogs.body (dlg);
            var note = new Label (_("Data macros run inside the database whenever records change, from any form, query or program."));
            note.wrap = true;
            note.xalign = 0;
            note.add_css_class ("dim-label");
            box.append (note);
            var switcher = new BubbleSwitcher ();
            var stack = new Stack ();
            stack.vexpand = true;
            stack.height_request = 460;
            var editors = new Gee.HashMap<string, MacroEditor> ();
            foreach (string ev in DataMacros.EVENTS) {
                var m = macros.has_key (ev) ? macros[ev] : new MacroDef ();
                m.name = ev;
                var ed = new MacroEditor (m, true);
                editors[ev] = ed;
                stack.add_named (ed, ev);
                switcher.add_option (ev, DataMacros.event_label (ev));
            }
            switcher.selected.connect ((n) => stack.visible_child_name = n);
            switcher.set_active (DataMacros.EVENTS[0]);
            box.append (switcher);
            box.append (stack);
            Dialogs.footer (dlg, _("Save"), () => {
                var result = new Gee.HashMap<string, MacroDef> ();
                foreach (var e in editors.entries) {
                    if (e.value.def.items.size > 0) result[e.key] = e.value.def;
                }
                try {
                    DataMacros.save (win.db, table, result);
                    win.toast (_("Data macros saved"));
                    return true;
                } catch (Error e) {
                    win.show_error (_("Could Not Save the Data Macros"), e.message);
                    return false;
                }
            });
            dlg.open_dialog ();
        }
    }
}
