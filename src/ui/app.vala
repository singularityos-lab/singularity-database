using Gtk;

namespace Singularity.Apps.Database {

    public class DatabaseApp : Singularity.Application {
        public GLib.Settings? settings;

        public DatabaseApp () {
            Object (application_id: "dev.sinty.database", flags: ApplicationFlags.HANDLES_OPEN);
            add_main_option ("new", 0, OptionFlags.NONE, OptionArg.NONE, _("Create a new database"), null);
        }

        protected override int handle_local_options (VariantDict options) {
            if (!options.contains ("new")) return -1;
            try {
                register (null);
            } catch (Error e) {
                warning ("database: %s", e.message);
                return 1;
            }
            activate_action ("new", null);
            return get_is_remote () ? 0 : -1;
        }

        protected override void startup () {
            base.startup ();
            about_description = _("Build databases with tables, queries, forms and reports");
            var schema = SettingsSchemaSource.get_default ()?.lookup ("dev.sinty.database", true);
            if (schema != null) settings = new GLib.Settings ("dev.sinty.database");
            IconTheme.get_for_display (Gdk.Display.get_default ()).add_resource_path ("/dev/sinty/database/icons");
            var lm = GtkSource.LanguageManager.get_default ();
            string[] search = lm.get_search_path ();
            search += "resource:///dev/sinty/database/language-specs";
            lm.set_search_path (search);
            Singularity.Application.add_app_css (CSS);
            app_action ("new", () => {
                var w = target_window ();
                w.new_database ();
            });
            app_action ("open", () => choose_file (target_window ()));
            app_action ("new-connection", () => new_connection (get_active_window () ?? target_window ()));
            var conn = new SimpleAction ("connect", VariantType.STRING);
            conn.activate.connect ((p) => {
                var c = ConnectionStore.get_default ().find (p.get_string ());
                if (c != null) open_connection (c, null, null);
            });
            add_action (conn);
            var tmpl = new SimpleAction ("template", VariantType.STRING);
            tmpl.activate.connect ((p) => target_window ().new_from_template (p.get_string ()));
            add_action (tmpl);
            app_action ("quit", () => {
                foreach (var w in get_windows ()) w.close ();
            });
            app_action ("settings", () => {
                try {
                    Singularity.Shell.ShellService shell = Bus.get_proxy_sync (BusType.SESSION, "dev.sinty.desktop", "/dev/sinty/Shell");
                    shell.open_app_settings ("dev.sinty.database");
                } catch (Error e) {
                    warning ("Failed to open settings: %s", e.message);
                }
            });
            build_menu ();
            string[,] accels = {
                { "app.quit", "<Control>q" }, { "app.new", "<Control>n" }, { "app.open", "<Control>o" },
                { "app.settings", "<Control>comma" }, { "win.save", "<Control>s" }, { "win.save-as", "<Control><Shift>s" },
                { "win.close-db", "<Control>w" }, { "win.close", "<Control><Shift>w" }, { "win.import", "<Control><Shift>i" },
                { "win.export", "<Control><Shift>e" }, { "win.print", "<Control>p" },
                { "win.cut", "<Control>x" }, { "win.copy", "<Control>c" }, { "win.paste", "<Control>v" },
                { "win.select-all", "<Control>a" }, { "win.find", "<Control>f" }, { "win.replace", "<Control>h" },
                { "win.goto", "<Control>g" }, { "win.rename", "F2" },
                { "win.save-record", "<Shift>Return" },
                { "win.view-data", "<Control>1" }, { "win.view-design", "<Control>2" }, { "win.view-sql", "<Control>3" },
                { "win.refresh", "F5" }, { "win.run", "<Control>Return" }, { "win.relationships", "<Control><Shift>r" },
                { "win.new-table", "<Control><Shift>t" }, { "win.new-query", "<Control><Shift>q" },
                { "win.new-form", "<Control><Shift>f" }, { "win.new-report", "<Control><Shift>p" },
                { "win.sort-asc", "<Control><Alt>a" }, { "win.sort-desc", "<Control><Alt>d" },
                { "win.filter", "<Control><Shift>l" }, { "win.clear-filters", "<Control><Shift>k" },
                { "win.fullscreen", "F11" }, { "win.add-field", "<Control><Shift>n" }
            };
            for (int i = 0; i < accels.length[0]; i++) set_accels_for_action (accels[i, 0], { accels[i, 1] });
            set_accels_for_action ("win.undo", { "<Control>z" });
            set_accels_for_action ("win.redo", { "<Control><Shift>z", "<Control>y" });
            set_accels_for_action ("win.totals-row", { "<Control><Alt>t" });
            set_accels_for_action ("win.new-record", { "<Control>plus", "<Control>KP_Add" });
            set_accels_for_action ("win.delete-record", { "<Control>minus", "<Control>KP_Subtract" });
            set_accels_for_action ("win.zoom-in", { "<Control><Alt>equal", "<Control><Alt>plus" });
            set_accels_for_action ("win.zoom-out", { "<Control><Alt>minus" });
            set_accels_for_action ("win.next-record", { "<Alt>Page_Down" });
            set_accels_for_action ("win.prev-record", { "<Alt>Page_Up" });
            set_accels_for_action ("win.first-record", { "<Alt>Home" });
            set_accels_for_action ("win.last-record", { "<Alt>End" });
        }

        private delegate void Handler ();

        private void app_action (string name, owned Handler h) {
            var a = new SimpleAction (name, null);
            a.activate.connect (() => h ());
            add_action (a);
        }

        private DatabaseWindow target_window () {
            var w = get_active_window () as DatabaseWindow;
            if (w != null && w.db == null) return w;
            if (w == null) {
                foreach (var x in get_windows ()) {
                    var dw = x as DatabaseWindow;
                    if (dw != null && dw.db == null) return dw;
                }
            }
            if (w != null && w.db == null) return w;
            var nw = new DatabaseWindow (this);
            nw.present ();
            return nw;
        }

        private static GLib.Menu section (string[,] items) {
            var m = new GLib.Menu ();
            for (int i = 0; i < items.length[0]; i++) m.append (items[i, 0], items[i, 1]);
            return m;
        }

        private static GLib.Menu submenu_section (string label, GLib.Menu sub) {
            var m = new GLib.Menu ();
            m.append_submenu (label, sub);
            return m;
        }

        private void build_menu () {
            var menu = new GLib.Menu ();

            var file = new GLib.Menu ();
            var templates = new GLib.Menu ();
            foreach (var t in Templates.list ()) templates.append (t.title, "app.template::" + t.id);
            var new_section = section ({ { _("New Database"), "app.new" } });
            new_section.append_submenu (_("New from Template"), templates);
            new_section.append (_("Open…"), "app.open");
            new_section.append (_("Connect to Server…"), "app.new-connection");
            file.append_section (null, new_section);
            file.append_section (null, section ({ { _("Save"), "win.save" }, { _("Save a Copy…"), "win.save-as" } }));
            var export = section ({ { _("Export Object…"), "win.export" }, { _("Export Database as Excel Workbook…"), "win.export-workbook" }, { _("Export Database as SQL…"), "win.export-sql" }, { _("Export Database as JSON…"), "win.export-json" } });
            var io = section ({ { _("Import Data…"), "win.import" } });
            io.append_submenu (_("Export"), export);
            io.append (_("Share…"), "win.share");
            io.append (_("Share as Excel Workbook…"), "win.share-export");
            file.append_section (null, io);
            file.append_section (null, section ({ { _("Print…"), "win.print" }, { _("Export Report…"), "win.export-pdf" } }));
            file.append_section (null, section ({ { _("Close Database"), "win.close-db" } }));
            file.append_section (null, section ({ { _("Close Window"), "win.close" }, { _("Quit"), "app.quit" } }));
            menu.append_submenu (_("File"), file);

            var edit = new GLib.Menu ();
            edit.append_section (null, section ({ { _("Undo"), "win.undo" }, { _("Redo"), "win.redo" } }));
            edit.append_section (null, section ({ { _("Cut"), "win.cut" }, { _("Copy"), "win.copy" }, { _("Paste"), "win.paste" }, { _("Select All"), "win.select-all" } }));
            edit.append_section (null, section ({ { _("Find…"), "win.find" }, { _("Replace…"), "win.replace" }, { _("Go to Record…"), "win.goto" } }));
            edit.append_section (null, section ({ { _("Rename…"), "win.rename" }, { _("Delete Object…"), "win.delete-object" } }));
            edit.append_section (null, section ({ { _("Settings"), "app.settings" } }));
            menu.append_submenu (_("Edit"), edit);

            var view = new GLib.Menu ();
            view.append_section (null, section ({ { _("Datasheet View"), "win.view-data" }, { _("Design View"), "win.view-design" }, { _("SQL View"), "win.view-sql" } }));
            var kinds = section ({ { _("Grid"), "win.view-kind::grid" }, { _("Gallery"), "win.view-kind::gallery" }, { _("Kanban"), "win.view-kind::kanban" }, { _("Calendar"), "win.view-kind::calendar" } });
            var kinds_section = submenu_section (_("Table View"), kinds);
            kinds_section.append (_("Totals Row"), "win.totals-row");
            view.append_section (null, kinds_section);
            view.append_section (null, section ({ { _("Navigation Pane"), "win.toggle-pane" }, { _("Relationships"), "win.relationships" } }));
            view.append_section (null, section ({ { _("Zoom In"), "win.zoom-in" }, { _("Zoom Out"), "win.zoom-out" }, { _("Refresh"), "win.refresh" }, { _("Fullscreen"), "win.fullscreen" } }));
            menu.append_submenu (_("View"), view);

            var insert = new GLib.Menu ();
            insert.append_section (null, section ({ { _("Table…"), "win.new-table" }, { _("Query…"), "win.new-query" }, { _("SQL Query"), "win.new-sql" }, { _("Form…"), "win.new-form" }, { _("Report…"), "win.new-report" }, { _("Macro"), "win.new-macro" }, { _("Module"), "win.new-module" } }));
            insert.append_section (null, section ({ { _("Record"), "win.new-record" }, { _("Field"), "win.add-field" }, { _("Saved View…"), "win.new-view" } }));
            menu.append_submenu (_("Insert"), insert);

            var records = new GLib.Menu ();
            records.append_section (null, section ({ { _("Sort Ascending"), "win.sort-asc" }, { _("Sort Descending"), "win.sort-desc" }, { _("Sort…"), "win.sort" } }));
            records.append_section (null, section ({ { _("Filter…"), "win.filter" }, { _("Filter by Form…"), "win.filter-by-form" }, { _("Filter by Selection"), "win.filter-selection" }, { _("Clear Filters and Sorting"), "win.clear-filters" } }));
            records.append_section (null, section ({ { _("Group…"), "win.group" }, { _("Hide Fields…"), "win.hide-fields" }, { _("Subdatasheet…"), "win.subdatasheet" } }));
            records.append_section (null, section ({ { _("Save Record"), "win.save-record" }, { _("Delete Record"), "win.delete-record" } }));
            records.append_section (null, section ({ { _("First Record"), "win.first-record" }, { _("Previous Record"), "win.prev-record" }, { _("Next Record"), "win.next-record" }, { _("Last Record"), "win.last-record" } }));
            menu.append_submenu (_("Records"), records);

            var tools = new GLib.Menu ();
            tools.append_section (null, section ({ { _("Run"), "win.run" }, { _("Run Macro…"), "win.run-macro" }, { _("Relationships"), "win.relationships" } }));
            tools.append_section (null, section ({ { _("Database Documenter…"), "win.documenter" }, { _("Analyze Performance…"), "win.analyze" }, { _("Object Dependencies…"), "win.dependencies" } }));
            tools.append_section (null, section ({ { _("Link Tables…"), "win.link-tables" }, { _("Linked Table Manager…"), "win.linked-tables" }, { _("Split Database…"), "win.split-database" } }));
            tools.append_section (null, section ({ { _("Compact and Repair Database"), "win.compact" }, { _("Check Integrity"), "win.check" }, { _("Encrypt with Password…"), "win.encrypt" } }));
            tools.append_section (null, section ({ { _("Current Database Options…"), "win.startup-options" } }));
            menu.append_submenu (_("Tools"), tools);

            set_menubar (menu);
        }

        public override void activate () {
            var w = get_active_window ();
            if (w == null) {
                var dw = new DatabaseWindow (this);
                dw.present ();
                if (settings != null && settings.get_boolean ("reopen-last")) {
                    string last = settings.get_string ("last-database");
                    if (last != "" && FileUtils.test (last, FileTest.EXISTS)) open_file (File.new_for_path (last), dw);
                }
                return;
            }
            w.present ();
        }

        public override void open (File[] files, string hint) {
            foreach (var f in files) open_file (f, null);
        }

        public void open_connection (ConnectionConfig config, string? password, string? ssh_password) {
            foreach (var w in get_windows ()) {
                var cw = w as ClientWindow;
                if (cw != null && config.id != "" && cw.config.id == config.id) {
                    cw.present ();
                    return;
                }
            }
            var win = new ClientWindow (this, config);
            win.present ();
            win.start (password, ssh_password);
            var idle = new Gee.ArrayList<DatabaseWindow> ();
            foreach (var w in get_windows ()) {
                var dw = w as DatabaseWindow;
                if (dw != null && dw.db == null) idle.add (dw);
            }
            Idle.add (() => {
                foreach (var dw in idle) dw.close ();
                return Source.REMOVE;
            });
        }

        public void connection_window_closed (ClientWindow win) {
            int others = 0;
            foreach (var w in get_windows ()) if (w != win) others++;
            if (others == 0) {
                var nw = new DatabaseWindow (this);
                nw.present ();
            }
        }

        public void new_connection (Gtk.Window parent) {
            ConnectionDialog.open (parent, this, null, (c, pw, spw) => open_connection (c, pw, spw));
        }

        public static bool is_database_file (string path) {
            string p = path.down ();
            return p.has_suffix (".sdb") || p.has_suffix (".sqlite") || p.has_suffix (".sqlite3") || p.has_suffix (".db") || p.has_suffix (".db3");
        }

        public static bool is_access_file (string path) {
            string p = path.down ();
            return p.has_suffix (".mdb") || p.has_suffix (".accdb");
        }

        public void open_file (File file, DatabaseWindow? target) {
            string? path = file.get_path ();
            if (path == null) return;
            foreach (var w in get_windows ()) {
                var dw = w as DatabaseWindow;
                if (dw != null && dw.db != null && dw.db.path == path) {
                    dw.present ();
                    return;
                }
            }
            DatabaseWindow? win = target != null && target.db == null ? target : null;
            if (win == null) {
                foreach (var w in get_windows ()) {
                    var dw = w as DatabaseWindow;
                    if (dw != null && dw.db == null) win = dw;
                }
            }
            if (win == null) win = new DatabaseWindow (this);
            win.present ();
            if (is_access_file (path)) {
                win.convert_access (path);
                return;
            }
            if (!is_database_file (path) && !sniff_sqlite (path)) {
                win.import_into_new (path);
                return;
            }
            win.open_database (path);
        }

        public static bool sniff_sqlite (string path) {
            var f = FileStream.open (path, "rb");
            if (f == null) return false;
            uint8[] head = new uint8[16];
            size_t n = f.read (head);
            return n == 16 && Memory.cmp (head, "SQLite format 3\0".data, 16) == 0;
        }

        public void remember (string path) {
            RecentManager.get_default ().add_item (File.new_for_path (path).get_uri ());
            if (settings != null) settings.set_string ("last-database", path);
        }

        public void choose_file (DatabaseWindow parent) {
            var dialog = new FileDialog ();
            dialog.title = _("Open Database");
            var filters = new GLib.ListStore (typeof (FileFilter));
            var all = new FileFilter ();
            all.name = _("Databases and Data Files");
            foreach (string s in new string[] { "sdb", "sqlite", "sqlite3", "db", "db3", "mdb", "accdb", "csv", "tsv", "xlsx", "json", "sql" }) all.add_suffix (s);
            var dbs = new FileFilter ();
            dbs.name = _("Databases");
            foreach (string s in new string[] { "sdb", "sqlite", "sqlite3", "db", "db3" }) dbs.add_suffix (s);
            var access = new FileFilter ();
            access.name = _("Access Databases");
            access.add_suffix ("mdb");
            access.add_suffix ("accdb");
            filters.append (all);
            filters.append (dbs);
            filters.append (access);
            dialog.filters = filters;
            dialog.open.begin (parent, null, (obj, res) => {
                try {
                    var file = dialog.open.end (res);
                    if (file != null) open_file (file, parent);
                } catch (Error e) {
                }
            });
        }

        public string new_database_folder () {
            string folder = settings != null ? settings.get_string ("new-database-folder").strip () : "";
            if (folder.has_prefix ("~/")) folder = Path.build_filename (Environment.get_home_dir (), folder.substring (2));
            if (folder == "" || !FileUtils.test (folder, FileTest.IS_DIR)) {
                folder = Environment.get_user_special_dir (UserDirectory.DOCUMENTS) ?? Environment.get_home_dir ();
                if (!FileUtils.test (folder, FileTest.IS_DIR)) folder = Environment.get_home_dir ();
            }
            return folder;
        }

        public string unique_path (string name) {
            string folder = new_database_folder ();
            string clean = name.replace ("/", "-").strip ();
            if (clean == "") clean = _("Database");
            string path = Path.build_filename (folder, clean + ".sdb");
            for (int i = 2; FileUtils.test (path, FileTest.EXISTS); i++) path = Path.build_filename (folder, "%s %d.sdb".printf (clean, i));
            return path;
        }

        private const string CSS = """
.db-datasheet {
    color: @window_fg_color;
}

.db-datasheet-scroll {
    margin: 0 12px;
    border-radius: 12px;
    border: 1px solid alpha(@window_fg_color, 0.1);
}

.db-cell-editor,
.db-cell-editor text {
    background-color: @window_bg_color;
    color: @window_fg_color;
}

.db-cell-editor {
    box-shadow: 0 0 0 2px @accent_bg_color, 0 6px 18px alpha(black, 0.18);
    border-radius: 2px;
    min-height: 0;
    padding: 0 4px;
}

.db-record-bar {
    padding: 6px 12px;
}

.db-record-bar entry {
    min-height: 26px;
    padding: 0 6px;
}

.db-status {
    font-feature-settings: "tnum";
    font-size: 12px;
}

.db-tool,
.db-record-bar button.db-tool {
    min-width: 30px;
    min-height: 30px;
    padding: 2px 6px;
    border-radius: 8px;
}

.db-pane-page {
    padding: 0 12px 12px 12px;
}

.db-canvas {
    background-color: alpha(@window_fg_color, 0.03);
    border-radius: 12px;
    border: 1px solid alpha(@window_fg_color, 0.08);
}

.db-conn-status.error {
    color: @error_color;
}

.db-conn-status.success {
    color: mix(@success_color, @window_fg_color, 0.35);
}

.db-toolbar {
    padding: 5px 10px;
    border-bottom: 1px solid alpha(@window_fg_color, 0.08);
}

.db-toolbar.db-status-bar {
    border-bottom: none;
    border-top: 1px solid alpha(@window_fg_color, 0.08);
    padding: 3px 12px;
    min-height: 30px;
}

.db-toolbar.db-tab-head {
    padding: 6px 12px;
}

button.db-tool-text {
    min-height: 28px;
    padding: 0 12px;
    border-radius: 8px;
}

.db-toolbar entry.db-where {
    min-height: 28px;
}

.db-status.error,
.db-messages .error {
    color: @error_color;
}

.db-pending {
    font-size: 12px;
    font-weight: 600;
    color: #c98a0c;
    margin-right: 6px;
}

.db-tab-strip {
    padding: 6px 10px 0 10px;
    border-bottom: 1px solid alpha(@window_fg_color, 0.08);
}

button.db-tab {
    padding: 4px 6px 4px 10px;
    border-radius: 8px 8px 0 0;
    min-height: 26px;
}

button.db-tab.active {
    background: alpha(@window_fg_color, 0.08);
    box-shadow: inset 0 -2px @accent_bg_color;
}

button.db-tab-close {
    min-width: 20px;
    min-height: 20px;
    padding: 0;
    border-radius: 99px;
}

button.db-tab-close image {
    -gtk-icon-size: 12px;
}

.db-result-strip {
    padding: 4px 10px;
    border-bottom: 1px solid alpha(@window_fg_color, 0.08);
    border-top: 1px solid alpha(@window_fg_color, 0.12);
}

button.db-result-tab {
    min-height: 24px;
    padding: 0 10px;
    border-radius: 7px;
    font-size: 12px;
    font-feature-settings: "tnum";
}

button.db-result-tab.active {
    background: alpha(@accent_bg_color, 0.16);
    color: @accent_color;
}

.db-conn-head {
    padding: 4px 6px 10px 6px;
    margin-bottom: 6px;
    border-bottom: 1px solid alpha(@window_fg_color, 0.08);
}

.db-conn-head dropdown > button {
    min-height: 28px;
    padding: 0 8px;
}

.db-conn-icon {
    color: @accent_color;
}

button.db-section-toggle {
    padding: 4px 8px;
    margin-top: 6px;
    min-height: 24px;
    font-size: 12px;
    font-weight: 700;
    color: alpha(@window_fg_color, 0.62);
}

.db-stat-card {
    padding: 14px 16px;
    border-radius: 12px;
    background: alpha(@window_fg_color, 0.045);
}

.db-struct-grid {
    border-bottom: 1px solid alpha(@window_fg_color, 0.08);
}

.db-struct-head {
    padding: 6px 8px;
    border-bottom: 1px solid alpha(@window_fg_color, 0.1);
    background: alpha(@window_fg_color, 0.03);
}

.db-struct-cell {
    min-height: 34px;
    padding: 0 2px;
}

.db-struct-cell.odd,
entry.db-cell.db-struct-cell.odd {
    background: alpha(@window_fg_color, 0.03);
}

.db-struct-cell entry.db-cell,
entry.db-cell.db-struct-cell {
    background: transparent;
    box-shadow: none;
}

.db-struct-cell.odd entry.db-cell,
entry.db-cell.db-struct-cell.odd {
    background: alpha(@window_fg_color, 0.03);
}

menubutton.db-cell-menu > button {
    min-width: 24px;
    min-height: 24px;
    padding: 0;
    border-radius: 6px;
    background: none;
}

.db-struct-cell.db-changed {
    box-shadow: inset 3px 0 #e0a21a;
}

button.db-cell-menu {
    min-width: 26px;
    min-height: 26px;
    padding: 0;
    border-radius: 6px;
}

button.db-history-row {
    padding: 6px 8px;
}

.db-messages {
    font-size: 12px;
}

.db-sidebar-badge {
    font-size: 11px;
    font-feature-settings: "tnum";
    color: alpha(@window_fg_color, 0.5);
}

.db-panel {
    background-color: alpha(@window_fg_color, 0.035);
    border: 1px solid alpha(@window_fg_color, 0.09);
    border-radius: 12px;
}

.db-grid-header {
    padding: 6px 6px 6px 6px;
    border-bottom: 1px solid alpha(@window_fg_color, 0.1);
}

.db-grid-head {
    font-size: 12px;
    font-weight: 700;
    color: alpha(@window_fg_color, 0.6);
}

.db-grid-footer {
    padding: 6px;
    border-top: 1px solid alpha(@window_fg_color, 0.1);
}

.db-design-row {
    padding: 1px 6px;
    min-height: 32px;
}

.db-design-row.odd {
    background-color: alpha(@window_fg_color, 0.025);
}

.db-design-row.selected {
    background-color: alpha(@accent_bg_color, 0.16);
}

.db-dense entry,
.db-dense spinbutton {
    min-height: 22px;
    padding: 2px 8px;
    border-radius: 6px;
}

.db-dense entry.db-cell {
    background-color: transparent;
    border-color: transparent;
    box-shadow: none;
    margin: 1px 2px;
}

.db-dense entry.db-cell:hover {
    background-color: alpha(@window_fg_color, 0.05);
}

.db-dense entry.db-cell:focus-within {
    background-color: @card_bg;
    border-color: @accent_color;
}

.db-dense dropdown > button,
.db-dense dropdown.db-cell > button {
    min-height: 22px;
    padding: 2px 8px;
    border-radius: 6px;
}

.db-dense dropdown.db-cell > button {
    background-color: transparent;
    border-color: transparent;
    box-shadow: none;
    margin: 1px 2px;
}

.db-dense dropdown.db-cell > button:hover {
    background-color: alpha(@window_fg_color, 0.05);
}

.db-dense switch {
    margin: 2px 0;
}

.db-cell-icon {
    min-width: 24px;
    min-height: 24px;
    padding: 2px;
    border-radius: 6px;
}

.db-cell-icon.accent {
    color: @accent_color;
}

button.db-small-button {
    min-height: 24px;
    padding: 2px 10px;
    font-size: 12px;
}

button.db-small-button.flat {
    padding: 2px 4px;
}

.db-inspector {
    padding: 12px;
}

.db-sheet-title {
    font-weight: 700;
    font-size: 13px;
}

.db-sheet-label {
    font-size: 12px;
    color: alpha(@window_fg_color, 0.72);
}

.db-sheet-value {
    font-size: 12px;
}

.db-sheet-item {
    padding: 2px 0;
}

.db-sheet-item image {
    opacity: 0.7;
}

.db-join-badge {
    border-radius: 99px;
    padding: 0 6px;
    font-size: 11px;
    background-color: @accent_bg_color;
    color: @accent_fg_color;
}

.db-query-grid .db-grid-label {
    font-size: 12px;
    color: alpha(@window_fg_color, 0.65);
    padding-right: 8px;
}

.db-filter-row {
    padding: 2px 0;
}

.db-card {
    border-radius: 14px;
    background-color: alpha(@window_fg_color, 0.05);
    border: 1px solid alpha(@window_fg_color, 0.08);
    padding: 12px;
}

.db-card:hover {
    background-color: alpha(@window_fg_color, 0.08);
}

.db-card-title {
    font-weight: 700;
}

.db-card-field {
    font-size: 12px;
}

.db-card-image {
    border-radius: 10px;
}

.db-lane {
    border-radius: 14px;
    background-color: alpha(@window_fg_color, 0.035);
    padding: 8px;
}

.db-lane.drop-target {
    background-color: alpha(@accent_bg_color, 0.14);
}

.db-lane-title {
    font-weight: 700;
    padding: 4px 6px;
}

.db-calendar-cell {
    border-radius: 10px;
    background-color: alpha(@window_fg_color, 0.03);
    padding: 4px;
}

.db-calendar-cell.today {
    box-shadow: inset 0 0 0 2px alpha(@accent_bg_color, 0.7);
}

.db-calendar-cell.other-month {
    opacity: 0.45;
}

.db-calendar-event {
    border-radius: 6px;
    padding: 1px 6px;
    font-size: 12px;
    background-color: alpha(@accent_bg_color, 0.22);
}

.db-template-card {
    border-radius: 16px;
    padding: 12px;
    background-color: alpha(@window_fg_color, 0.05);
    border: 1px solid alpha(@window_fg_color, 0.08);
}

.db-template-card:hover {
    background-color: alpha(@window_fg_color, 0.09);
}

.db-recent-row {
    border-radius: 10px;
    padding: 8px 10px;
}

.db-sql-view,
.db-sql-view text {
    font-family: monospace;
}

.db-sql-frame {
    border-radius: 12px;
    border: 1px solid alpha(@window_fg_color, 0.1);
}

.db-message {
    font-family: monospace;
    font-size: 12px;
    padding: 6px 12px;
}

.db-form-sheet {
    padding: 4px 0;
}

.db-form-sheet entry {
    min-height: 22px;
    padding-top: 5px;
    padding-bottom: 5px;
}

.db-form-sheet dropdown > button {
    min-height: 34px;
    padding-top: 0;
    padding-bottom: 0;
}

.db-form-sheet button:not(.flat) {
    min-height: 34px;
    min-width: 34px;
    padding: 0 8px;
    border-radius: 8px;
}

.db-form-multiline {
    border-radius: 10px;
    background: alpha(@window_fg_color, 0.07);
}

.db-form-multiline textview,
.db-form-multiline textview text {
    background: transparent;
}

entry.db-record-number {
    min-width: 0;
}

.db-form-label {
    font-size: 12px;
    font-weight: 600;
    color: alpha(@window_fg_color, 0.7);
}

.db-form-title {
    font-size: 22px;
    font-weight: 800;
}

.db-design-control {
    border-radius: 8px;
    border: 1px dashed alpha(@window_fg_color, 0.3);
    background-color: alpha(@window_fg_color, 0.04);
    padding: 4px 8px;
}

.db-design-control.selected {
    border: 2px solid @accent_bg_color;
    background-color: alpha(@accent_bg_color, 0.1);
}

.db-subform {
    border-radius: 12px;
    border: 1px solid alpha(@window_fg_color, 0.1);
}

.db-report-scroll {
    background-color: alpha(@window_fg_color, 0.06);
    border-radius: 12px;
}

.db-report-page {
    box-shadow: 0 2px 10px alpha(black, 0.25);
}

""";
    }

    public static int main (string[] args) {
        if (SshTunnel.handle_askpass ()) return 0;
        Intl.setlocale (LocaleCategory.ALL, "");
        string locale_dir = "/usr/share/locale";
        try {
            string exe = FileUtils.read_link ("/proc/self/exe");
            locale_dir = Path.build_filename (Path.get_dirname (Path.get_dirname (exe)), "share", "locale");
        } catch (Error e) {
        }
        Intl.bindtextdomain ("singularity-database", locale_dir);
        Intl.bind_textdomain_codeset ("singularity-database", "UTF-8");
        Intl.textdomain ("singularity-database");
        var app = new DatabaseApp ();
        new DatabaseSearchProvider (app).export (app);
        return app.run (args);
    }
}
