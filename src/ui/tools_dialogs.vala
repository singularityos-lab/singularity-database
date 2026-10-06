using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Database {

    public class ExpressionBuilder {
        public delegate void Done (string expression);

        private static string[,] functions () {
            return {
                { _("Text"), "Left([Text], 3)" }, { _("Text"), "Right([Text], 3)" }, { _("Text"), "Mid([Text], 2, 3)" }, { _("Text"), "Len([Text])" },
                { _("Text"), "InStr([Text], \"x\")" }, { _("Text"), "Replace([Text], \"a\", \"b\")" }, { _("Text"), "Trim([Text])" }, { _("Text"), "UCase([Text])" },
                { _("Text"), "LCase([Text])" }, { _("Text"), "StrConv([Text], 3)" }, { _("Text"), "Format([Value], \"#,##0.00\")" },
                { _("Date and Time"), "Date()" }, { _("Date and Time"), "Now()" }, { _("Date and Time"), "Year([Date])" }, { _("Date and Time"), "Month([Date])" },
                { _("Date and Time"), "Day([Date])" }, { _("Date and Time"), "Weekday([Date])" }, { _("Date and Time"), "DateAdd(\"m\", 1, [Date])" },
                { _("Date and Time"), "DateDiff(\"d\", [Start], [End])" }, { _("Date and Time"), "DatePart(\"q\", [Date])" }, { _("Date and Time"), "DateSerial(2024, 1, 1)" },
                { _("Date and Time"), "MonthName(Month([Date]))" },
                { _("Math"), "Round([Number], 2)" }, { _("Math"), "Int([Number])" }, { _("Math"), "Abs([Number])" }, { _("Math"), "Sqr([Number])" },
                { _("Program Flow"), "IIf([Value] > 0, \"yes\", \"no\")" }, { _("Program Flow"), "Nz([Value], 0)" }, { _("Program Flow"), "Switch([A] > 1, \"x\", True, \"y\")" },
                { _("Program Flow"), "Choose([Index], \"a\", \"b\")" }, { _("Inspection"), "IsNull([Value])" }, { _("Inspection"), "IsNumeric([Value])" },
                { _("Inspection"), "IsDate([Value])" }, { _("Conversion"), "CStr([Value])" }, { _("Conversion"), "CLng([Value])" }, { _("Conversion"), "CDbl([Value])" },
                { _("Conversion"), "CDate([Value])" }, { _("Conversion"), "Val([Text])" },
                { _("Domain Aggregate"), "DLookup(\"[Field]\", \"Table\", \"[ID] = 1\")" }, { _("Domain Aggregate"), "DCount(\"*\", \"Table\")" },
                { _("Domain Aggregate"), "DSum(\"[Field]\", \"Table\")" }, { _("Domain Aggregate"), "DAvg(\"[Field]\", \"Table\")" },
                { _("SQL Aggregate"), "Sum([Field])" }, { _("SQL Aggregate"), "Avg([Field])" }, { _("SQL Aggregate"), "Count(*)" }
            };
        }

        public static void show (DatabaseWindow win, TableDef? fields_of, string current, owned Done done) {
            var dlg = Dialogs.make (win, _("Expression Builder"), 760, 640);
            var box = Dialogs.body (dlg);
            var buffer = new TextBuffer (null);
            buffer.text = current;
            var view = new TextView.with_buffer (buffer);
            view.monospace = true;
            view.wrap_mode = WrapMode.WORD_CHAR;
            view.height_request = 90;
            view.add_css_class ("db-sql-view");
            var frame = new ScrolledWindow ();
            frame.child = view;
            frame.add_css_class ("db-sql-frame");
            box.append (frame);
            var status = new Label ("");
            status.xalign = 0;
            status.wrap = true;
            status.add_css_class ("caption");
            box.append (status);
            var ops = new Box (Orientation.HORIZONTAL, 4);
            foreach (string op in new string[] { "+", "-", "*", "/", "&", "=", "<>", ">", "<", "And", "Or", "Not", "Like", "(", ")" }) {
                var b = new Button.with_label (op);
                b.add_css_class ("flat");
                string ins = op.length > 1 && op[0].isalpha () ? " %s ".printf (op) : op;
                b.clicked.connect (() => {
                    buffer.insert_at_cursor (ins, -1);
                    view.grab_focus ();
                });
                ops.append (b);
            }
            box.append (ops);
            var cols = new Box (Orientation.HORIZONTAL, 12);
            cols.homogeneous = true;
            cols.height_request = 260;
            var cats = new Gtk.ListBox ();
            var items = new Gtk.ListBox ();
            var s1 = new ScrolledWindow ();
            s1.child = cats;
            var s2 = new ScrolledWindow ();
            s2.child = items;
            cols.append (s1);
            cols.append (s2);
            box.append (cols);
            var categories = new Gee.ArrayList<string> ();
            if (fields_of != null) categories.add (_("Fields"));
            var fn = functions ();
            for (int i = 0; i < fn.length[0]; i++) if (!categories.contains (fn[i, 0])) categories.add (fn[i, 0]);
            foreach (string c in categories) {
                var l = new Label (c);
                l.xalign = 0;
                l.margin_start = l.margin_end = 8;
                l.margin_top = l.margin_bottom = 4;
                cats.append (l);
            }
            cats.row_selected.connect ((row) => {
                Widget? ch;
                while ((ch = items.get_first_child ()) != null) items.remove (ch);
                if (row == null) return;
                string cat = categories[row.get_index ()];
                string[] values = {};
                if (cat == _("Fields") && fields_of != null) {
                    foreach (var f in fields_of.fields) values += "[%s]".printf (f.name);
                } else {
                    for (int i = 0; i < fn.length[0]; i++) if (fn[i, 0] == cat) values += fn[i, 1];
                }
                foreach (string v in values) {
                    var l = new Label (v);
                    l.xalign = 0;
                    l.margin_start = l.margin_end = 8;
                    l.margin_top = l.margin_bottom = 4;
                    l.add_css_class ("monospace");
                    items.append (l);
                }
            });
            items.row_activated.connect ((row) => {
                var l = row.child as Label;
                if (l == null) return;
                buffer.insert_at_cursor (l.label, -1);
                view.grab_focus ();
            });
            buffer.changed.connect (() => {
                try {
                    ScriptParser.parse_expression (buffer.text.strip () == "" ? "Null" : buffer.text);
                    status.label = _("The expression is valid.");
                    status.remove_css_class ("error");
                } catch (Error e) {
                    status.label = e.message;
                    status.add_css_class ("error");
                }
            });
            buffer.changed ();
            Dialogs.footer (dlg, _("OK"), () => {
                done (buffer.text.strip ());
                return true;
            });
            dlg.open_dialog ();
        }
    }

    public class ToolDialogs {
        public static void startup_options (DatabaseWindow win) {
            var opts = StartupOptions.load (win.db);
            var dlg = Dialogs.make (win, _("Current Database Options"), 520, 560);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (_("Application"), _("These options are stored in this database and apply to everyone who opens it."));
            var title = new EntryRow (_("Application Title"));
            title.text = opts.app_title;
            g.add_row (title);
            string[] forms = { _("None") };
            foreach (string f in win.db.object_names ("form:")) forms += f;
            var form = new SelectionRow (_("Display Form"), forms, opts.startup_form != "" ? opts.startup_form : forms[0]);
            g.add_row (form);
            var nav = new SwitchRow (_("Hide the Navigation Pane"), _("Start with the object list closed"), opts.hide_navigation);
            g.add_row (nav);
            box.append (g);
            var g2 = new PreferencesGroup (_("Sharing"), null);
            var locking = new SwitchRow (_("Record Locking"), _("Lock a record while someone edits it"), opts.record_locking);
            g2.add_row (locking);
            var refresh = new EntryRow (_("Refresh Interval in Seconds"));
            refresh.text = opts.refresh_seconds.to_string ();
            g2.add_row (refresh);
            var compact = new SwitchRow (_("Compact on Close"), null, opts.compact_on_close);
            g2.add_row (compact);
            box.append (g2);
            var note = new Label (_("A macro named AutoExec runs every time the database opens."));
            note.xalign = 0;
            note.wrap = true;
            note.add_css_class ("dim-label");
            box.append (note);
            Dialogs.footer (dlg, _("Apply"), () => {
                opts.app_title = title.text.strip ();
                opts.startup_form = form.current_value == forms[0] ? "" : form.current_value;
                opts.hide_navigation = nav.active;
                opts.record_locking = locking.active;
                opts.refresh_seconds = int.max (1, int.parse (refresh.text));
                opts.compact_on_close = compact.active;
                try {
                    opts.save (win.db);
                    win.apply_sharing_options ();
                    return true;
                } catch (Error e) {
                    win.show_error (_("Could Not Save the Options"), e.message);
                    return false;
                }
            });
            dlg.open_dialog ();
        }

        public static void link_tables (DatabaseWindow win) {
            var conns = ConnectionStore.get_default ().items;
            if (conns.size == 0) {
                link_file (win);
                return;
            }
            var dlg = Dialogs.make (win, _("Link Tables"), 460, 480);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (_("Source"), null);
            var file_row = new ActionRow (_("Database, Spreadsheet or Text File"), _("Tables from another database file, Excel sheets or delimited text"), "db-table-symbolic");
            file_row.activatable = true;
            file_row.add_suffix (new Image.from_icon_name ("go-next-symbolic"));
            file_row.activated.connect (() => {
                dlg.close ();
                link_file (win);
            });
            g.add_row (file_row);
            box.append (g);
            var sg = new PreferencesGroup (_("Servers"), _("Linked server tables are read when the database opens and every change is written back to the server."));
            foreach (var c in conns) {
                var cfg = c;
                var row = new ActionRow (cfg.name, cfg.summary (), "db-server-symbolic");
                row.activatable = true;
                row.add_suffix (new Image.from_icon_name ("go-next-symbolic"));
                row.activated.connect (() => {
                    dlg.close ();
                    choose_server_tables (win, cfg);
                });
                sg.add_row (row);
            }
            box.append (sg);
            Dialogs.close_footer (dlg);
            dlg.open_dialog ();
        }

        private static void choose_server_tables (DatabaseWindow win, ConnectionConfig cfg) {
            win.toast (_("Connecting to %s").printf (cfg.name));
            server_tables_async.begin (win, cfg, (obj, res) => {
                try {
                    server_tables_async.end (res);
                } catch (Error e) {
                    win.show_error (_("Could Not Link"), e.message);
                }
            });
        }

        private static async void server_tables_async (DatabaseWindow win, ConnectionConfig cfg) throws Error {
            var session = yield win.open_link_session (cfg.id);
            var schemas = yield ServerLinks.schemas (session.engine);
            string[] schema_of = {};
            string[] names = {};
            foreach (string sc in schemas) {
                foreach (string t in yield ServerLinks.tables (session.engine, sc)) {
                    schema_of += sc;
                    names += t;
                }
            }
            if (names.length == 0) throw new RemoteError.SERVER (_("There are no tables on %s.").printf (cfg.name));
            var dlg = Dialogs.make (win, _("Link Server Tables"), 460, 560);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (_("Tables on %s").printf (cfg.name), _("Tables need a primary key to be edited from here."));
            var rows = new Gee.ArrayList<SwitchRow> ();
            for (int i = 0; i < names.length; i++) {
                bool exists = win.db.object_exists (names[i]);
                var r = new SwitchRow (names[i], exists ? _("A table with this name already exists") : (schemas.size > 1 ? schema_of[i] : null), false);
                r.sensitive = !exists;
                g.add_row (r);
                rows.add (r);
            }
            box.append (g);
            Dialogs.footer (dlg, _("Link"), () => {
                var pick_schema = new Gee.ArrayList<string> ();
                var pick_name = new Gee.ArrayList<string> ();
                for (int i = 0; i < names.length; i++) {
                    if (!rows[i].active) continue;
                    pick_schema.add (schema_of[i]);
                    pick_name.add (names[i]);
                }
                link_server_async.begin (win, cfg, pick_schema, pick_name);
                return true;
            });
            dlg.open_dialog ();
        }

        private static async void link_server_async (DatabaseWindow win, ConnectionConfig cfg, Gee.ArrayList<string> schemas, Gee.ArrayList<string> names) {
            int done = 0;
            string[] errors = {};
            for (int i = 0; i < names.size; i++) {
                try {
                    var session = yield win.open_link_session (cfg.id);
                    var snap = yield ServerLinks.fetch (session.engine, schemas[i], names[i]);
                    Links.add_server (win.db, cfg.id, schemas[i], names[i], names[i], snap);
                    done++;
                } catch (Error e) {
                    errors += "%s: %s".printf (names[i], e.message);
                }
            }
            win.rebuild_sidebar ();
            win.toast (ngettext ("%d table linked", "%d tables linked", done).printf (done));
            if (errors.length > 0) Dialogs.notes (win, _("Some Tables Were Not Linked"), errors);
        }

        private static void link_file (DatabaseWindow win) {
            var fd = new FileDialog ();
            fd.title = _("Link Tables");
            var filters = new GLib.ListStore (typeof (FileFilter));
            var f1 = new FileFilter ();
            f1.name = _("Databases, Spreadsheets and Text");
            foreach (string s in new string[] { "sdb", "sqlite", "sqlite3", "db", "xlsx", "csv", "tsv", "txt" }) f1.add_suffix (s);
            filters.append (f1);
            fd.filters = filters;
            fd.open.begin (win, null, (obj, res) => {
                try {
                    var file = fd.open.end (res);
                    if (file == null) return;
                    choose_link_tables (win, file.get_path ());
                } catch (Error e) {
                    if (!(e is Gtk.DialogError.DISMISSED)) win.show_error (_("Could Not Link"), e.message);
                }
            });
        }

        private static void choose_link_tables (DatabaseWindow win, string path) throws Error {
            string low = path.down ();
            bool file_link = low.has_suffix (".xlsx") || low.has_suffix (".csv") || low.has_suffix (".tsv") || low.has_suffix (".txt");
            string[] names = {};
            if (file_link) {
                if (low.has_suffix (".xlsx")) {
                    foreach (var t in Xlsx.load (path)) names += t.name;
                } else {
                    string b = Path.get_basename (path);
                    int dot = b.last_index_of (".");
                    names += dot > 0 ? b.substring (0, dot) : b;
                }
            } else {
                foreach (string t in Links.tables_in (path)) names += t;
            }
            var dlg = Dialogs.make (win, _("Link Tables"), 460, 520);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (_("Tables"), file_link ? _("Linked sheets and text files are read again each time the database opens.") : _("Linked tables stay in their file; changes are saved there."));
            var rows = new Gee.ArrayList<SwitchRow> ();
            foreach (string n in names) {
                bool exists = win.db.object_exists (n);
                var r = new SwitchRow (n, exists ? _("A table with this name already exists") : null, !exists);
                r.sensitive = !exists;
                g.add_row (r);
                rows.add (r);
            }
            box.append (g);
            Dialogs.footer (dlg, _("Link"), () => {
                int done = 0;
                string[] errors = {};
                for (int i = 0; i < names.length; i++) {
                    if (!rows[i].active) continue;
                    try {
                        Links.add (win.db, path, names[i], names[i], file_link ? "file" : "database");
                        done++;
                    } catch (Error e) {
                        errors += "%s: %s".printf (names[i], e.message);
                    }
                }
                win.rebuild_sidebar ();
                win.toast (ngettext ("%d table linked", "%d tables linked", done).printf (done));
                if (errors.length > 0) Dialogs.notes (win, _("Some Tables Were Not Linked"), errors);
                return true;
            });
            dlg.open_dialog ();
        }

        public static void linked_table_manager (DatabaseWindow win) {
            var links = Links.list (win.db);
            var dlg = Dialogs.make (win, _("Linked Table Manager"), 560, 560);
            var box = Dialogs.body (dlg);
            if (links.size == 0) {
                var sp = new StatusPage ();
                sp.icon_name = "db-table-symbolic";
                sp.title = _("No Linked Tables");
                sp.description = _("Link tables from another database, a spreadsheet or a text file.");
                box.append (sp);
            }
            var paths = new Gee.TreeSet<string> ();
            foreach (var l in links) paths.add (l.path);
            foreach (string p in paths) {
                string path = p;
                bool server = false;
                foreach (var l in links) {
                    if (l.path == p && l.kind == "server") server = true;
                }
                var cfg = server ? win.find_connection (p) : null;
                var g = server ? new PreferencesGroup (cfg != null ? cfg.name : p, cfg != null ? cfg.summary () : _("Connection not saved on this computer")) : new PreferencesGroup (Path.get_basename (p), Links.resolve (win.db, p));
                foreach (var l in links) {
                    if (l.path != p) continue;
                    var st = win.db.linked[l.name.casefold ()];
                    string sub = st != null && st.available ? _("Connected") : (st != null && st.error != "" ? st.error : _("Missing"));
                    var row = new ActionRow (l.name, sub, "db-table-symbolic");
                    var rm = new Button.from_icon_name ("user-trash-symbolic");
                    rm.add_css_class ("flat");
                    rm.valign = Align.CENTER;
                    rm.tooltip_text = _("Delete Link");
                    string name = l.name;
                    rm.clicked.connect (() => {
                        try {
                            Links.remove (win.db, name);
                            dlg.close ();
                            win.rebuild_sidebar ();
                            linked_table_manager (win);
                        } catch (Error e) {
                            win.show_error (_("Could Not Delete the Link"), e.message);
                        }
                    });
                    row.add_suffix (rm);
                    g.add_row (row);
                }
                if (server) {
                    box.append (g);
                    continue;
                }
                var relink = new Button.with_label (_("Relink…"));
                relink.halign = Align.START;
                relink.clicked.connect (() => {
                    var fd = new FileDialog ();
                    fd.title = _("Choose the New Location");
                    fd.open.begin (dlg, null, (obj, res) => {
                        try {
                            var file = fd.open.end (res);
                            if (file == null) return;
                            Links.relink (win.db, path, file.get_path ());
                            dlg.close ();
                            win.rebuild_sidebar ();
                            linked_table_manager (win);
                        } catch (Error e) {
                            if (!(e is Gtk.DialogError.DISMISSED)) win.show_error (_("Could Not Relink"), e.message);
                        }
                    });
                });
                box.append (g);
                box.append (relink);
            }
            var refresh = new Button.with_label (_("Refresh All"));
            refresh.halign = Align.START;
            refresh.clicked.connect (() => {
                Links.attach_all (win.db);
                win.db.invalidate ();
                win.db.schema_changed ();
                dlg.close ();
                win.refresh_server_links.begin (null, (obj, res) => {
                    win.refresh_server_links.end (res);
                    linked_table_manager (win);
                });
            });
            box.append (refresh);
            Dialogs.close_footer (dlg);
            dlg.open_dialog ();
        }

        public static void split_database (DatabaseWindow win) {
            if (win.db.path == ":memory:") {
                win.show_error (_("Could Not Split"), _("Save the database before splitting it."));
                return;
            }
            var dlg = new ConfirmDialog (win.app, _("Split the Database?"), "dialog-question",
                _("The tables move to a new back end file and this file keeps queries, forms, reports, macros and modules, linked to those tables. Share the back end and give everyone a copy of this front end."),
                _("Split…"), ConfirmDialog.ActionStyle.SUGGESTED);
            dlg.transient_for = win;
            dlg.response.connect ((r) => {
                if (r != ConfirmDialog.Response.PRIMARY) return;
                var fd = new FileDialog ();
                fd.title = _("Save the Back End");
                fd.initial_name = win.db.display_name () + "_be.sdb";
                fd.save.begin (win, null, (obj, res) => {
                    try {
                        var file = fd.save.end (res);
                        if (file == null) return;
                        string path = file.get_path ();
                        if (!path.down ().has_suffix (".sdb")) path += ".sdb";
                        Links.split (win.db, path);
                        win.rebuild_sidebar ();
                        win.toast (_("Tables moved to \"%s\"").printf (Path.get_basename (path)));
                    } catch (Error e) {
                        if (!(e is Gtk.DialogError.DISMISSED)) win.show_error (_("Could Not Split"), e.message);
                    }
                });
            });
            dlg.present ();
        }

        public static void password (DatabaseWindow win) {
            bool enc = win.db.is_encrypted;
            var dlg = Dialogs.make (win, enc ? _("Change Database Password") : _("Encrypt with Password"), 460, 360);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (_("Password"), enc ? _("Leave both empty to remove the password and store the file unencrypted.") : _("The whole file is encrypted. Without the password nobody can open it, and it cannot be recovered."));
            var p1 = new PasswordRow (_("New Password"));
            var p2 = new PasswordRow (_("Confirm Password"));
            g.add_row (p1);
            g.add_row (p2);
            box.append (g);
            Dialogs.footer (dlg, enc ? _("Apply") : _("Encrypt"), () => {
                if (p1.text != p2.text) {
                    win.show_error (_("Passwords Do Not Match"), _("Type the same password twice."));
                    return false;
                }
                if (p1.text == "" && !enc) return false;
                try {
                    win.db.set_password (p1.text == "" ? null : p1.text);
                    win.toast (p1.text == "" ? _("Password removed") : _("Database encrypted"));
                    return true;
                } catch (Error e) {
                    win.show_error (_("Could Not Change the Password"), e.message);
                    return false;
                }
            });
            dlg.open_dialog ();
        }

        public static void ask_password (DatabaseApp app, Gtk.Window? parent, string path, owned DatabaseWindow.Callback? cancelled, owned PasswordGiven given, string? problem = null) {
            var dlg = new AppDialog (app, true);
            dlg.set_title (_("Password Required"));
            dlg.transient_for = parent;
            dlg.set_default_size (420, -1);
            var box = new Box (Orientation.VERTICAL, 12);
            box.margin_start = box.margin_end = 18;
            box.margin_top = 6;
            var g = new PreferencesGroup (Path.get_basename (path), problem ?? _("This database is encrypted."));
            var pw = new PasswordRow (_("Password"));
            g.add_row (pw);
            box.append (g);
            dlg.content_box.append (box);
            Dialogs.footer (dlg, _("Open"), () => {
                given (pw.text);
                return true;
            });
            dlg.open_dialog ();
        }

        public delegate void PasswordGiven (string password);

        public static void documenter (DatabaseWindow win) {
            var dlg = Dialogs.make (win, _("Database Documenter"), 460, 520);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (_("Document"), _("Choose the objects to describe in the report."));
            string[] kinds = { "table", "query", "form", "report", "macro", "module" };
            string[] labels = { _("Tables"), _("Queries"), _("Forms"), _("Reports"), _("Macros"), _("Modules") };
            var rows = new Gee.ArrayList<SwitchRow> ();
            for (int i = 0; i < kinds.length; i++) {
                var r = new SwitchRow (labels[i], null, true);
                g.add_row (r);
                rows.add (r);
            }
            box.append (g);
            Dialogs.footer (dlg, _("Create"), () => {
                string[] chosen = {};
                for (int i = 0; i < kinds.length; i++) if (rows[i].active) chosen += kinds[i];
                try {
                    Database doc;
                    var def = Documenter.build (win.db, chosen, out doc);
                    var src = ReportEngine.open_source (doc, def);
                    var pages = new ReportRenderer ().layout (def, src);
                    win.show_pages (_("Database Documenter"), pages, def);
                    return true;
                } catch (Error e) {
                    win.show_error (_("Could Not Document"), e.message);
                    return false;
                }
            });
            dlg.open_dialog ();
        }

        public static void analyzer (DatabaseWindow win) {
            var items = PerformanceAnalyzer.run (win.db);
            var dlg = Dialogs.make (win, _("Analyze Performance"), 620, 600);
            var box = Dialogs.body (dlg);
            if (items.size == 0) {
                var sp = new StatusPage ();
                sp.icon_name = "emblem-ok-symbolic";
                sp.title = _("Nothing to Improve");
                sp.description = _("The analyzer found no suggestions for this database.");
                box.append (sp);
            }
            string[] sev = { "recommendation", "idea" };
            string[] titles = { _("Recommendations"), _("Ideas") };
            for (int s = 0; s < 2; s++) {
                PreferencesGroup? g = null;
                foreach (var it in items) {
                    if (it.severity != sev[s]) continue;
                    if (g == null) g = new PreferencesGroup (titles[s], null);
                    var row = new ActionRow (it.object_name != "" ? it.object_name : win.db.display_name (), it.message, s == 0 ? "dialog-warning-symbolic" : "dialog-information-symbolic");
                    if (it.fix_sql != "") {
                        var fix = new Button.with_label (_("Optimize"));
                        fix.valign = Align.CENTER;
                        string sql = it.fix_sql;
                        string target = it.object_name;
                        fix.clicked.connect (() => {
                            try {
                                win.db.design_change (_("Add Index"), { target }, () => {
                                    win.db.exec (sql);
                                });
                                fix.sensitive = false;
                                fix.label = _("Done");
                            } catch (Error e) {
                                win.show_error (_("Could Not Optimize"), e.message);
                            }
                        });
                        row.add_suffix (fix);
                    }
                    g.add_row (row);
                }
                if (g != null) box.append (g);
            }
            Dialogs.close_footer (dlg);
            dlg.open_dialog ();
        }

        public static void dependencies (DatabaseWindow win, string kind, string name) {
            var deps = new Dependencies (win.db);
            var dlg = Dialogs.make (win, _("Object Dependencies: %s").printf (name), 520, 560);
            var box = Dialogs.body (dlg);
            var uses = deps.used_by (kind, name);
            var depend = deps.depending_on (kind, name);
            var g1 = new PreferencesGroup (_("Objects That Depend on Me"), depend.size == 0 ? _("No other object uses it.") : null);
            foreach (var o in depend) g1.add_row (dep_row (win, dlg, o));
            var g2 = new PreferencesGroup (_("Objects That I Depend On"), uses.size == 0 ? _("It does not use other objects.") : null);
            foreach (var o in uses) g2.add_row (dep_row (win, dlg, o));
            box.append (g1);
            box.append (g2);
            Dialogs.close_footer (dlg);
            dlg.open_dialog ();
        }

        private static Widget dep_row (DatabaseWindow win, AppDialog dlg, DbObjectRef o) {
            string icon = o.kind == "table" ? "db-table-symbolic" : (o.kind == "query" ? "db-query-symbolic" : (o.kind == "form" ? "db-form-symbolic" : (o.kind == "report" ? "db-report-symbolic" : "db-run-symbolic")));
            var row = new ActionRow (o.name, Dialogs.kind_label (o.kind), icon);
            var open = new Button.from_icon_name ("document-open-symbolic");
            open.add_css_class ("flat");
            open.valign = Align.CENTER;
            open.tooltip_text = _("Open");
            open.clicked.connect (() => {
                dlg.close ();
                win.open_object (o.kind, o.name);
            });
            row.add_suffix (open);
            return row;
        }

        public static void compact_and_repair (DatabaseWindow win) {
            if (win.db.path == ":memory:") return;
            int64 before = file_size (win.db.path);
            try {
                string[] notes = win.db.compact_and_repair ();
                Links.attach_all (win.db);
                win.load_runtime ();
                int64 after = file_size (win.db.path);
                win.rebuild_sidebar ();
                if (notes.length > 0) Dialogs.notes (win, _("Compact and Repair"), notes);
                else win.toast (_("Database compacted: %s to %s").printf (format_size (before), format_size (after)));
            } catch (Error e) {
                win.show_error (_("Could Not Compact and Repair"), e.message);
            }
        }

        private static int64 file_size (string path) {
            try {
                return File.new_for_path (path).query_info ("standard::size", FileQueryInfoFlags.NONE).get_size ();
            } catch (Error e) {
                return 0;
            }
        }
    }
}
