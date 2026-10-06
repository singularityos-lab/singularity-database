using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Database {

    public class Dialogs {
        public delegate bool Apply ();
        public delegate void SourceChosen (string source, FormLayout layout);
        public delegate void IndexChosen (IndexDef index);

        public static AppDialog make (DatabaseWindow win, string title, int width, int height) {
            var dlg = new AppDialog (win.app, true);
            dlg.set_title (title);
            dlg.transient_for = win;
            dlg.set_default_size (width, -1);
            dlg.set_data<int> ("db-max-height", int.max (220, height - 110));
            return dlg;
        }

        public static Box body (AppDialog dlg) {
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.vexpand = true;
            scroll.propagate_natural_height = true;
            int max_h = dlg.get_data<int> ("db-max-height");
            scroll.max_content_height = max_h > 0 ? max_h : 520;
            var box = new Box (Orientation.VERTICAL, 14);
            box.margin_start = box.margin_end = 18;
            box.margin_top = 6;
            box.margin_bottom = 12;
            scroll.child = box;
            dlg.content_box.append (scroll);
            return box;
        }

        public static Button footer (AppDialog dlg, string label, owned Apply apply, bool destructive = false) {
            var bar = new Box (Orientation.HORIZONTAL, 8);
            bar.margin_start = bar.margin_end = 18;
            bar.margin_bottom = 16;
            bar.margin_top = 4;
            bar.halign = Align.END;
            var cancel = new Button.with_label (_("Cancel"));
            cancel.clicked.connect (() => dlg.close ());
            dlg.set_cancel_button (cancel);
            var ok = new Button.with_label (label);
            ok.add_css_class (destructive ? "destructive-action" : "suggested-action");
            ok.clicked.connect (() => {
                if (apply ()) dlg.close ();
            });
            bar.append (cancel);
            bar.append (ok);
            dlg.content_box.append (bar);
            dlg.default_widget = ok;
            connect_entries (dlg.content_box, ok);
            return ok;
        }

        private static void connect_entries (Widget w, Button ok) {
            var er = w as EntryRow;
            if (er != null) er.entry_activated.connect (() => ok.activate ());
            for (var c = w.get_first_child (); c != null; c = c.get_next_sibling ()) connect_entries (c, ok);
        }

        public delegate bool NameChosen (string name);

        public static void ask_name (DatabaseWindow win, string title, string suggested, owned NameChosen cb) {
            var dlg = make (win, title, 420, 240);
            var box = body (dlg);
            var g = new PreferencesGroup (title, null);
            var name = new EntryRow (_("Name"));
            name.text = suggested;
            g.add_row (name);
            box.append (g);
            footer (dlg, _("Save"), () => {
                string n = name.text.strip ();
                if (n == "") return false;
                return cb (n);
            });
            dlg.open_dialog ();
        }

        public static void close_footer (AppDialog dlg, string label = _("Close")) {
            var bar = new Box (Orientation.HORIZONTAL, 8);
            bar.margin_start = bar.margin_end = 18;
            bar.margin_bottom = 16;
            bar.halign = Align.END;
            var close = new Button.with_label (label);
            close.add_css_class ("suggested-action");
            close.clicked.connect (() => dlg.close ());
            dlg.set_cancel_button (close);
            bar.append (close);
            dlg.content_box.append (bar);
        }

        private static string[] type_labels () {
            string[] l = {};
            foreach (var t in FieldType.ALL) l += t.label ();
            return l;
        }

        private static FieldType type_for_label (string label) {
            foreach (var t in FieldType.ALL) {
                if (t.label () == label) return t;
            }
            return FieldType.TEXT;
        }

        public static void new_table (DatabaseWindow win) {
            var db = win.db;
            var dlg = make (win, _("New Table"), 460, 420);
            var box = body (dlg);
            var g = new PreferencesGroup (_("Table"), _("You can change everything later in the design view."));
            var name = new EntryRow (_("Name"));
            name.text = db.unique_object_name (_("Table"));
            g.add_row (name);
            string[] starts = { _("ID Only"), _("ID, Name and Notes"), _("ID, Title, Status and Due Date") };
            var start = new SelectionRow (_("Starting Fields"), starts, starts[1]);
            g.add_row (start);
            box.append (g);
            footer (dlg, _("Create"), () => {
                var def = new TableDef (name.text.strip ());
                var id = def.add_field ("ID", FieldType.AUTONUMBER);
                id.primary_key = true;
                if (start.current_value == starts[1]) {
                    def.add_field (_("Name"), FieldType.TEXT).required = true;
                    def.add_field (_("Notes"), FieldType.LONG_TEXT);
                } else if (start.current_value == starts[2]) {
                    def.add_field (_("Title"), FieldType.TEXT).required = true;
                    var st = def.add_field (_("Status"), FieldType.CHOICE);
                    st.choices = { _("To Do"), _("Doing"), _("Done") };
                    st.default_value = _("To Do");
                    def.add_field (_("Due Date"), FieldType.DATE);
                }
                try {
                    db.create_table (def);
                } catch (Error e) {
                    win.show_error (_("Could Not Create Table"), e.message);
                    return false;
                }
                win.rebuild_sidebar ();
                win.open_object ("table", def.name, "design");
                return true;
            });
            dlg.open_dialog ();
            name.grab_focus ();
        }

        public static void add_field (DatabaseWindow win, string table, string? before = null) {
            var db = win.db;
            TableDef def;
            try {
                def = db.load_table (table);
            } catch (Error e) {
                win.show_error (_("Could Not Add Field"), e.message);
                return;
            }
            var dlg = make (win, _("Add Field"), 440, 420);
            var box = body (dlg);
            var g = new PreferencesGroup (_("Field"), _("The field is added to every record of \"%s\".").printf (table));
            var name = new EntryRow (_("Name"));
            name.text = def.unique_field_name (_("Field"));
            g.add_row (name);
            var type = new SelectionRow (_("Data Type"), type_labels (), FieldType.TEXT.label ());
            g.add_row (type);
            var required = new SwitchRow (_("Required"), null, false);
            g.add_row (required);
            box.append (g);
            footer (dlg, _("Add"), () => {
                var t = type_for_label (type.current_value);
                var f = new Field (name.text.strip (), t);
                f.required = required.active;
                if (t == FieldType.CHOICE) f.choices = { _("Option 1"), _("Option 2") };
                if (t == FieldType.CURRENCY) f.decimals = 2;
                if (t == FieldType.LOOKUP) {
                    foreach (string other in db.table_names ()) {
                        if (other == table) continue;
                        try {
                            var odef = db.load_table (other);
                            var pk = odef.primary_key ();
                            if (pk.size != 1) continue;
                            f.lookup_table = other;
                            f.lookup_field = pk[0].name;
                            foreach (var of in odef.fields) {
                                if (of.field_type.is_text ()) {
                                    f.lookup_display = of.name;
                                    break;
                                }
                            }
                            break;
                        } catch (Error e) {
                        }
                    }
                }
                if (t == FieldType.AUTONUMBER) {
                    win.show_error (_("Could Not Add Field"), _("Choose AutoNumber in the design view, where the primary key is set."));
                    return false;
                }
                if (f.required && f.default_value == "" && db.count_rows (table) > 0) {
                    f.default_value = t.is_numeric () ? "0" : (t == FieldType.BOOLEAN ? "No" : (t == FieldType.CHOICE ? f.choices[0] : ""));
                    if (f.default_value == "" && !t.is_text ()) {
                        win.show_error (_("Could Not Add Field"), _("Existing records have no value for a required field. Add it as optional first."));
                        return false;
                    }
                }
                int pos = before != null ? def.index_of (before) : -1;
                if (pos >= 0) def.fields.insert (pos + 1, f);
                else def.fields.add (f);
                try {
                    db.alter_table (table, def, null, _("Add Field"));
                } catch (Error e) {
                    win.show_error (_("Could Not Add Field"), e.message);
                    return false;
                }
                return true;
            });
            dlg.open_dialog ();
            name.grab_focus ();
        }

        public static void rename_field (DatabaseWindow win, string table, string field) {
            var db = win.db;
            var dlg = make (win, _("Rename Field"), 420, 240);
            var box = body (dlg);
            var g = new PreferencesGroup (_("Field"), null);
            var name = new EntryRow (_("Name"));
            name.text = field;
            g.add_row (name);
            box.append (g);
            footer (dlg, _("Rename"), () => {
                string n = name.text.strip ();
                if (n == field) return true;
                try {
                    var def = db.load_table (table);
                    var f = def.find (field);
                    f.name = n;
                    foreach (var ix in def.indexes) {
                        string[] c = ix.columns;
                        for (int i = 0; i < c.length; i++) if (c[i] == field) c[i] = n;
                        ix.columns = c;
                    }
                    foreach (var r in def.relationships) {
                        string[] c = r.columns;
                        for (int i = 0; i < c.length; i++) if (c[i] == field) c[i] = n;
                        r.columns = c;
                    }
                    var renames = new Gee.HashMap<string, string> ();
                    renames[n] = field;
                    db.alter_table (table, def, renames, _("Rename Field"));
                } catch (Error e) {
                    win.show_error (_("Could Not Rename"), e.message);
                    return false;
                }
                return true;
            });
            dlg.open_dialog ();
            name.grab_focus ();
        }

        public static void delete_field (DatabaseWindow win, string table, string field) {
            var dlg = new ConfirmDialog (win.app, _("Delete Field \"%s\"?").printf (field), "user-trash",
                _("The field and its data are removed from every record. You can undo this with Ctrl+Z."), _("Delete"), ConfirmDialog.ActionStyle.DESTRUCTIVE);
            dlg.transient_for = win;
            dlg.response.connect ((r) => {
                if (r != ConfirmDialog.Response.PRIMARY) return;
                try {
                    var def = win.db.load_table (table);
                    if (def.fields.size <= 1) throw new SchemaError.INVALID (_("A table needs at least one field."));
                    def.fields.remove (def.find (field));
                    var keep = new Gee.ArrayList<IndexDef> ();
                    foreach (var ix in def.indexes) {
                        if (!(field in ix.columns)) keep.add (ix);
                    }
                    def.indexes = keep;
                    var rels = new Gee.ArrayList<Relationship> ();
                    foreach (var rel in def.relationships) {
                        if (!(field in rel.columns)) rels.add (rel);
                    }
                    def.relationships = rels;
                    win.db.alter_table (table, def, null, _("Delete Field"));
                } catch (Error e) {
                    win.show_error (_("Could Not Delete Field"), e.message);
                }
            });
            dlg.present ();
        }

        public static void rename_object (DatabaseWindow win, string kind, string name) {
            var db = win.db;
            var dlg = make (win, _("Rename"), 420, 240);
            var box = body (dlg);
            var g = new PreferencesGroup (kind_label (kind), null);
            var entry = new EntryRow (_("Name"));
            entry.text = name;
            g.add_row (entry);
            box.append (g);
            footer (dlg, _("Rename"), () => {
                string n = entry.text.strip ();
                if (n == name) return true;
                if (n == "") return false;
                try {
                    switch (kind) {
                        case "table":
                            db.rename_table (name, n);
                            break;
                        case "query":
                            var q = db.load_query (name);
                            if (q == null) {
                                if (db.object_exists (n) || db.get_meta ("action:" + n) != null) throw new SchemaError.INVALID (_("An object named \"%s\" already exists.").printf (n));
                                db.save_object_meta (_("Rename"), "action:", n, db.get_meta ("action:" + name), name);
                                break;
                            }
                            q.name = n;
                            db.save_query (q, name);
                            break;
                        default:
                            string prefix = kind + ":";
                            if (db.get_meta (prefix + n) != null) throw new SchemaError.INVALID (_("An object named \"%s\" already exists.").printf (n));
                            db.save_object_meta (_("Rename"), prefix, n, db.get_meta (prefix + name), name);
                            break;
                    }
                    var page = win.find_page (kind, name);
                    if (page != null) {
                        string old_key = page.key ();
                        page.object_name = n;
                        win.adopt_page (page, old_key);
                        page.title_changed ();
                    }
                    win.rebuild_sidebar ();
                } catch (Error e) {
                    win.show_error (_("Could Not Rename"), e.message);
                    return false;
                }
                return true;
            });
            dlg.open_dialog ();
            entry.grab_focus ();
        }

        public static string kind_label (string kind) {
            switch (kind) {
                case "table": return _("Table");
                case "query": return _("Query");
                case "form": return _("Form");
                case "report": return _("Report");
                case "macro": return _("Macro");
                case "module": return _("Module");
                default: return kind;
            }
        }

        public static void delete_object (DatabaseWindow win, string kind, string name) {
            var db = win.db;
            string msg;
            if (kind == "table") {
                int64 n = db.count_rows (name);
                var rels = db.relationships_to (name);
                msg = ngettext ("The table and its %lld record are deleted.", "The table and its %lld records are deleted.", (ulong) n).printf (n);
                if (rels.size > 0) msg += " " + _("Other tables refer to it and lose their relationship.");
                msg += " " + _("You can undo this with Ctrl+Z.");
            } else {
                msg = _("You can undo this with Ctrl+Z.");
            }
            var dlg = new ConfirmDialog (win.app, _("Delete %s \"%s\"?").printf (kind_label (kind), name), "user-trash", msg, _("Delete"), ConfirmDialog.ActionStyle.DESTRUCTIVE);
            dlg.transient_for = win;
            dlg.response.connect ((r) => {
                if (r != ConfirmDialog.Response.PRIMARY) return;
                try {
                    if (kind == "query" && !db.object_exists (name, "view")) {
                        db.save_object_meta (_("Delete"), "action:", name, null);
                    } else if (kind == "table" || kind == "query") {
                        if (kind == "table") {
                            foreach (var rel in db.relationships_to (name)) {
                                if (rel.table.casefold () == name.casefold ()) continue;
                                var child = db.load_table (rel.table);
                                var keep = new Gee.ArrayList<Relationship> ();
                                foreach (var cr in child.relationships) {
                                    if (cr.ref_table.casefold () != name.casefold ()) keep.add (cr);
                                }
                                child.relationships = keep;
                                foreach (var f in child.fields) {
                                    if (f.field_type == FieldType.LOOKUP && f.lookup_table.casefold () == name.casefold ()) {
                                        f.field_type = FieldType.INTEGER;
                                        f.lookup_table = "";
                                        f.lookup_field = "";
                                    }
                                }
                                db.alter_table (child.name, child, null, _("Remove Relationship"));
                            }
                        }
                        db.drop_object (name);
                    } else {
                        db.save_object_meta (_("Delete"), kind + ":", name, null);
                    }
                    var page = win.find_page (kind, name);
                    if (page != null) win.forget_page (page);
                    win.rebuild_sidebar ();
                    win.toast (_("\"%s\" deleted").printf (name), _("Undo"), () => win.run ("undo"));
                } catch (Error e) {
                    win.show_error (_("Could Not Delete"), e.message);
                }
            });
            dlg.present ();
        }

        public static void duplicate_table (DatabaseWindow win, string name) {
            var db = win.db;
            var dlg = make (win, _("Duplicate Table"), 440, 300);
            var box = body (dlg);
            var g = new PreferencesGroup (_("Copy"), null);
            var entry = new EntryRow (_("Name"));
            entry.text = db.unique_object_name (_("%s Copy").printf (name));
            g.add_row (entry);
            var data = new SwitchRow (_("Copy the Records"), _("Otherwise only the structure is copied"), true);
            g.add_row (data);
            box.append (g);
            footer (dlg, _("Duplicate"), () => {
                try {
                    var def = db.load_table (name);
                    string n = entry.text.strip ();
                    def.name = n;
                    def.relationships.clear ();
                    var idx = new Gee.ArrayList<IndexDef> ();
                    foreach (var ix in def.indexes) {
                        var c = ix.copy ();
                        c.name = "%s_%s".printf (n, ix.name);
                        idx.add (c);
                    }
                    def.indexes = idx;
                    db.design_change (_("Duplicate Table"), { n }, () => {
                        db.exec (def.create_sql ());
                        foreach (string s in def.index_sql ()) db.exec (s);
                        db.write_table_meta (def);
                        if (data.active) {
                            string[] cols = {};
                            foreach (var f in def.fields) cols += Sql.quote_ident (f.name);
                            string list = string.joinv (", ", cols);
                            db.exec ("INSERT INTO %s (%s) SELECT %s FROM %s".printf (Sql.quote_ident (n), list, list, Sql.quote_ident (name)));
                        }
                    });
                    win.rebuild_sidebar ();
                    win.open_object ("table", n);
                } catch (Error e) {
                    win.show_error (_("Could Not Duplicate"), e.message);
                    return false;
                }
                return true;
            });
            dlg.open_dialog ();
        }

        public static void choose_source (DatabaseWindow win, string title, string action, owned SourceChosen cb) {
            var db = win.db;
            string[] sources = {};
            foreach (string t in db.table_names ()) sources += t;
            foreach (string q in db.view_names ()) sources += q;
            if (sources.length == 0) {
                win.show_error (title, _("Create a table first."));
                return;
            }
            var dlg = make (win, title, 440, 380);
            var box = body (dlg);
            var g = new PreferencesGroup (_("Record Source"), _("The table or query that provides the records."));
            var src = new SelectionRow (_("Table or Query"), sources, sources[0]);
            g.add_row (src);
            box.append (g);
            SelectionRow? layout = null;
            if (title == _("New Form")) {
                var lg = new PreferencesGroup (_("Layout"), null);
                string[] layouts = { _("One Column"), _("Two Columns") };
                layout = new SelectionRow (_("Arrangement"), layouts, layouts[0]);
                lg.add_row (layout);
                box.append (lg);
            }
            footer (dlg, action, () => {
                var l = layout != null && layout.current_value == _("Two Columns") ? FormLayout.TWO_COLUMNS : FormLayout.COLUMNAR;
                cb (src.current_value, l);
                return true;
            });
            dlg.open_dialog ();
        }

        public static void notes (DatabaseWindow win, string title, string[] lines) {
            var dlg = make (win, title, 480, 360);
            var box = body (dlg);
            var g = new PreferencesGroup (_("Details"), null);
            foreach (string l in lines) {
                if (l.strip () == "") continue;
                var row = new ActionRow (l, null, null);
                g.add_row (row);
            }
            box.append (g);
            close_footer (dlg, _("OK"));
            dlg.open_dialog ();
        }

        public static void index_editor (DatabaseWindow win, TableDef def, owned IndexChosen cb) {
            var dlg = make (win, _("Add Index"), 440, 520);
            var box = body (dlg);
            var g = new PreferencesGroup (_("Index"), null);
            var name = new EntryRow (_("Name"));
            name.text = "idx_%s_%d".printf (def.name, def.indexes.size + 1);
            g.add_row (name);
            var unique = new SwitchRow (_("Unique"), _("No two records can have the same combination"), false);
            g.add_row (unique);
            box.append (g);
            var fg = new PreferencesGroup (_("Fields"), _("Pick the fields in the order they are searched."));
            var picks = new Gee.ArrayList<SwitchRow> ();
            foreach (var f in def.fields) {
                var r = new SwitchRow (f.name, f.field_type.label (), false);
                picks.add (r);
                fg.add_row (r);
            }
            box.append (fg);
            footer (dlg, _("Add"), () => {
                string[] cols = {};
                for (int i = 0; i < picks.size; i++) if (picks[i].active) cols += def.fields[i].name;
                if (cols.length == 0) {
                    win.show_error (_("Could Not Add Index"), _("Choose at least one field."));
                    return false;
                }
                cb (new IndexDef (name.text.strip (), cols, unique.active));
                return true;
            });
            dlg.open_dialog ();
        }

        public static void view_settings (DatabaseWindow win, TablePage page, ViewDef view) {
            var dlg = make (win, _("View Settings"), 460, 560);
            var box = body (dlg);
            var def = page.src.def;
            string[] all = {};
            string[] texts = {};
            string[] groupable = {};
            string[] dates = {};
            string[] images = { _("None") };
            foreach (var f in def.fields) {
                all += f.name;
                if (f.field_type != FieldType.ATTACHMENT && f.field_type != FieldType.LONG_TEXT) texts += f.name;
                if (f.field_type == FieldType.CHOICE || f.field_type == FieldType.BOOLEAN || f.field_type == FieldType.LOOKUP || f.field_type == FieldType.TEXT || f.field_type == FieldType.INTEGER) groupable += f.name;
                if (f.field_type == FieldType.DATE || f.field_type == FieldType.DATETIME) dates += f.name;
                if (f.field_type == FieldType.ATTACHMENT) images += f.name;
            }
            var g = new PreferencesGroup (view.kind.label (), null);
            var name = new EntryRow (_("View Name"));
            name.text = view.name;
            g.add_row (name);
            var title = new SelectionRow (_("Card Title"), texts, view.title_field);
            g.add_row (title);
            SelectionRow? group = null, date = null, image = null;
            if (view.kind == ViewKind.KANBAN) {
                group = new SelectionRow (_("Stack Cards By"), groupable, view.group_field);
                g.add_row (group);
            }
            if (view.kind == ViewKind.CALENDAR) {
                if (dates.length == 0) {
                    var none = new ActionRow (_("No Date Field"), _("Add a date field to place records on the calendar."), null);
                    g.add_row (none);
                } else {
                    date = new SelectionRow (_("Date Field"), dates, view.date_field != "" ? view.date_field : dates[0]);
                    g.add_row (date);
                }
            }
            if (view.kind == ViewKind.GALLERY) {
                image = new SelectionRow (_("Cover Image"), images, view.image_field != "" ? view.image_field : images[0]);
                g.add_row (image);
            }
            box.append (g);
            var cg = new PreferencesGroup (_("Fields on Cards"), null);
            var picks = new Gee.ArrayList<SwitchRow> ();
            foreach (string f in all) {
                var r = new SwitchRow (f, null, f in view.card_fields);
                picks.add (r);
                cg.add_row (r);
            }
            box.append (cg);
            footer (dlg, _("Apply"), () => {
                view.name = name.text.strip () != "" ? name.text.strip () : view.name;
                view.title_field = title.current_value;
                if (group != null) view.group_field = group.current_value;
                if (date != null) view.date_field = date.current_value;
                if (image != null) view.image_field = image.current_value == _("None") ? "" : image.current_value;
                string[] cf = {};
                for (int i = 0; i < picks.size; i++) if (picks[i].active) cf += all[i];
                view.card_fields = cf;
                page.view_settings_changed ();
                return true;
            });
            dlg.open_dialog ();
        }

        public static void rename_view (DatabaseWindow win, TablePage page) {
            var dlg = make (win, _("Rename View"), 420, 240);
            var box = body (dlg);
            var g = new PreferencesGroup (_("View"), null);
            var name = new EntryRow (_("Name"));
            name.text = page.current_view ().name;
            g.add_row (name);
            box.append (g);
            footer (dlg, _("Rename"), () => {
                if (name.text.strip () == "") return false;
                page.rename_view (name.text.strip ());
                return true;
            });
            dlg.open_dialog ();
        }

        public static void find_replace (DatabaseWindow win, TablePage page) {
            var src = page.src;
            var dlg = make (win, _("Find and Replace"), 460, 440);
            var box = body (dlg);
            var g = new PreferencesGroup (_("Replace"), _("Replaces text in the records shown by the current view."));
            var find = new EntryRow (_("Find"));
            find.text = src.state.search;
            g.add_row (find);
            var repl = new EntryRow (_("Replace With"));
            g.add_row (repl);
            string[] fields = { _("All Text Fields") };
            foreach (var f in src.def.fields) {
                if (f.field_type.is_text () && f.field_type != FieldType.CHOICE) fields += f.name;
            }
            var cur = page.sheet.current_field ();
            var scope = new SelectionRow (_("Look In"), fields, cur != null && cur.field_type.is_text () && cur.field_type != FieldType.CHOICE ? cur.name : fields[0]);
            g.add_row (scope);
            var match_case = new SwitchRow (_("Match Case"), null, false);
            g.add_row (match_case);
            var whole = new SwitchRow (_("Match Whole Field"), null, false);
            g.add_row (whole);
            box.append (g);
            footer (dlg, _("Replace All"), () => {
                string needle = find.text;
                if (needle == "" || !src.editable) return false;
                var targets = new Gee.ArrayList<Field> ();
                foreach (var f in src.def.fields) {
                    if (!f.field_type.is_text () || f.field_type == FieldType.CHOICE) continue;
                    if (scope.current_value == fields[0] || scope.current_value == f.name) targets.add (f);
                }
                int count = 0;
                try {
                    var db = win.db;
                    var rows = src.all_rows ();
                    foreach (var r in rows.rows) {
                        int64 rowid = r.get (0).as_int ();
                        foreach (var f in targets) {
                            var v = r.get (src.def.index_of (f.name) + 1);
                            if (v.is_null) continue;
                            string s = v.to_string ();
                            string result;
                            if (whole.active) {
                                bool same = match_case.active ? s == needle : s.casefold () == needle.casefold ();
                                if (!same) continue;
                                result = repl.text;
                            } else if (match_case.active) {
                                if (!s.contains (needle)) continue;
                                result = s.replace (needle, repl.text);
                            } else {
                                try {
                                    var re = new Regex (Regex.escape_string (needle), RegexCompileFlags.CASELESS);
                                    if (!re.match (s)) continue;
                                    result = re.replace_literal (s, -1, 0, repl.text);
                                } catch (Error e) {
                                    continue;
                                }
                            }
                            db.update_value (src.source, rowid, f.name, new DbValue.text (result));
                            count++;
                        }
                    }
                } catch (Error e) {
                    win.show_error (_("Could Not Replace"), e.message);
                }
                src.invalidate ();
                page.reload ();
                win.toast (ngettext ("%d value replaced", "%d values replaced", count).printf (count));
                return true;
            });
            dlg.open_dialog ();
        }

        public static void attachment (DatabaseWindow win, RecordSource src, int64 rowid, Field field) {
            var dlg = make (win, field.label (), 520, 560);
            var box = body (dlg);
            DbValue current = new DbValue.null ();
            try {
                if (src.is_table) {
                    var rs = win.db.query ("SELECT %s FROM %s WHERE rowid = ?".printf (Sql.quote_ident (field.name), Sql.quote_ident (src.source)), { new DbValue.int (rowid) });
                    if (rs.rows.size > 0) current = rs.rows[0].get (0);
                } else {
                    var r = src.row (rowid);
                    if (r != null) current = r.get (src.def.index_of (field.name));
                }
            } catch (Error e) {
            }
            var files = current.kind == ValueKind.BLOB ? Attachment.unpack_all (current.blob_value) : new Gee.ArrayList<AttachmentFile> ();
            foreach (var f in files) {
                if (f.mime == "application/octet-stream") {
                    bool uncertain;
                    string? m = ContentType.get_mime_type (ContentType.guess (f.name, f.content.get_data (), out uncertain));
                    if (m != null) f.mime = m;
                }
            }
            foreach (var f in files) {
                if (!f.mime.has_prefix ("image/")) continue;
                try {
                    var pic = new Picture.for_paintable (Gdk.Texture.from_bytes (f.content));
                    pic.height_request = 200;
                    pic.can_shrink = true;
                    pic.content_fit = ContentFit.CONTAIN;
                    box.append (pic);
                } catch (Error e) {
                }
                break;
            }
            var g = new PreferencesGroup (_("Files"), files.size == 0 ? _("Add one or more files to store them in this record.") : null);
            for (int i = 0; i < files.size; i++) {
                var f = files[i];
                var row = new ActionRow (f.name, "%s, %s".printf (ContentType.get_description (ContentType.from_mime_type (f.mime) ?? f.mime), format_size (f.content.get_size ())), "mail-attachment-symbolic");
                var open_b = new Button.from_icon_name ("document-open-symbolic");
                open_b.tooltip_text = _("Open");
                open_b.valign = Align.CENTER;
                open_b.add_css_class ("flat");
                open_b.clicked.connect (() => {
                    try {
                        string dir = Path.build_filename (Environment.get_user_cache_dir (), "dev.sinty.database", "open");
                        DirUtils.create_with_parents (dir, 0700);
                        string p = Path.build_filename (dir, f.name.replace ("/", "_"));
                        FileUtils.set_data (p, f.content.get_data ());
                        new FileLauncher (File.new_for_path (p)).launch.begin (win, null);
                    } catch (Error e) {
                        win.show_error (_("Could Not Open"), e.message);
                    }
                });
                row.add_suffix (open_b);
                var save_b = new Button.from_icon_name ("document-save-symbolic");
                save_b.tooltip_text = _("Save As…");
                save_b.valign = Align.CENTER;
                save_b.add_css_class ("flat");
                save_b.clicked.connect (() => {
                    var fd = new FileDialog ();
                    fd.title = _("Save Attachment");
                    fd.initial_name = f.name;
                    fd.save.begin (dlg, null, (obj, res) => {
                        try {
                            var file = fd.save.end (res);
                            if (file == null) return;
                            FileUtils.set_data (file.get_path (), f.content.get_data ());
                            win.toast (_("Saved \"%s\"").printf (file.get_basename ()));
                        } catch (Error e) {
                            if (!(e is Gtk.DialogError.DISMISSED)) win.show_error (_("Could Not Save"), e.message);
                        }
                    });
                });
                row.add_suffix (save_b);
                var rm = new Button.from_icon_name ("user-trash-symbolic");
                rm.tooltip_text = _("Remove");
                rm.valign = Align.CENTER;
                rm.add_css_class ("flat");
                int idx = i;
                rm.clicked.connect (() => {
                    try {
                        files.remove_at (idx);
                        src.set_value (rowid, field.name, files.size > 0 ? new DbValue.blob (Attachment.pack_many (files)) : new DbValue.null ());
                        dlg.close ();
                        attachment (win, src, rowid, field);
                    } catch (Error e) {
                        win.show_error (_("Could Not Remove"), e.message);
                    }
                });
                row.add_suffix (rm);
                g.add_row (row);
            }
            box.append (g);
            var actions = new Box (Orientation.HORIZONTAL, 8);
            actions.halign = Align.CENTER;
            var choose = new Button.with_label (_("Add Files…"));
            actions.append (choose);
            box.append (actions);
            close_footer (dlg);
            choose.clicked.connect (() => {
                var fd = new FileDialog ();
                fd.title = _("Add Files");
                fd.open_multiple.begin (dlg, null, (obj, res) => {
                    try {
                        var chosen = fd.open_multiple.end (res);
                        if (chosen == null) return;
                        for (uint k = 0; k < chosen.get_n_items (); k++) {
                            var file = (File) chosen.get_item (k);
                            uint8[] data;
                            FileUtils.get_data (file.get_path (), out data);
                            if (data.length > 64 * 1024 * 1024) throw new IOError.FAILED (_("The file is larger than 64 MB."));
                            var info = file.query_info ("standard::content-type", FileQueryInfoFlags.NONE);
                            string m = ContentType.get_mime_type (info.get_content_type ()) ?? "application/octet-stream";
                            files.add (new AttachmentFile (file.get_basename (), m, new Bytes (data)));
                        }
                        src.set_value (rowid, field.name, new DbValue.blob (Attachment.pack_many (files)));
                        dlg.close ();
                        attachment (win, src, rowid, field);
                    } catch (Error e) {
                        if (!(e is Gtk.DialogError.DISMISSED)) win.show_error (_("Could Not Attach"), e.message);
                    }
                });
            });
            dlg.open_dialog ();
        }

        public static void record_editor (DatabaseWindow win, RecordSource src, int64 rowid) {
            var dlg = make (win, rowid < 0 ? _("New Record") : _("Record"), 560, 640);
            var box = body (dlg);
            var editor = new RecordEditor (win, src);
            if (rowid >= 0) editor.load_rowid (rowid);
            else editor.load_new ();
            box.append (editor);
            footer (dlg, _("Save"), () => editor.save ());
            dlg.open_dialog ();
        }
    }
}
