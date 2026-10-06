using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Database {

    public class ClientDialogs {
        public delegate void Action ();

        private static AppDialog make (ClientWindow win, string title, int width) {
            var dlg = new AppDialog (win.app, true);
            dlg.set_title (title);
            dlg.transient_for = win;
            dlg.set_default_size (width, -1);
            return dlg;
        }

        private static Box footer (AppDialog dlg, string label, owned Action action, bool destructive = false) {
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
                dlg.close ();
                action ();
            });
            bar.append (cancel);
            bar.append (ok);
            dlg.content_box.append (bar);
            dlg.default_widget = ok;
            return bar;
        }

        public static void preview_sql (ClientWindow win, string title, string subtitle, string sql, string action_label, owned Action action) {
            var dlg = make (win, title, 720);
            var box = new Box (Orientation.VERTICAL, 10);
            box.margin_start = box.margin_end = 18;
            box.margin_top = 6;
            box.margin_bottom = 8;
            var sub = new Label (subtitle);
            sub.xalign = 0;
            sub.wrap = true;
            sub.add_css_class ("dim-label");
            box.append (sub);
            var buffer = new GtkSource.Buffer (null);
            var lang = GtkSource.LanguageManager.get_default ().get_language ("sql");
            if (lang != null) buffer.language = lang;
            buffer.text = sql;
            var view = new Singularity.Widgets.SourceView (buffer);
            view.toolbar_top_padding = 8;
            view.editable = false;
            view.monospace = true;
            view.show_line_numbers = true;
            view.wrap_mode = WrapMode.WORD_CHAR;
            SqlTab.apply_scheme (view, buffer, win.app.settings);
            var scroll = new ScrolledWindow ();
            scroll.child = view;
            scroll.min_content_height = 220;
            scroll.max_content_height = 440;
            scroll.propagate_natural_height = true;
            scroll.add_css_class ("db-sql-frame");
            box.append (scroll);
            var copy = new Button.with_label (_("Copy SQL"));
            copy.add_css_class ("flat");
            copy.halign = Align.START;
            copy.clicked.connect (() => {
                win.get_clipboard ().set_text (sql);
                win.toast (_("SQL copied"));
            });
            box.append (copy);
            dlg.content_box.append (box);
            footer (dlg, action_label, (owned) action);
            dlg.open_dialog ();
        }

        private static ExportFormat format_for (string path) {
            string p = path.down ();
            if (p.has_suffix (".json")) return ExportFormat.JSON;
            if (p.has_suffix (".sql")) return ExportFormat.SQL;
            return ExportFormat.CSV;
        }

        private static FileDialog save_dialog (string title, string name) {
            var fd = new FileDialog ();
            fd.title = title;
            fd.initial_name = name;
            var filters = new GLib.ListStore (typeof (FileFilter));
            string[,] kinds = { { "CSV", "csv" }, { "JSON", "json" }, { "SQL", "sql" } };
            for (int i = 0; i < kinds.length[0]; i++) {
                var f = new FileFilter ();
                f.name = kinds[i, 0];
                f.add_suffix (kinds[i, 1]);
                filters.append (f);
            }
            fd.filters = filters;
            return fd;
        }

        public static void export_table (ClientWindow win, CatalogObject o) {
            var fd = save_dialog (_("Export %s").printf (o.name), o.name + ".csv");
            fd.save.begin (win, null, (obj, res) => {
                try {
                    var f = fd.save.end (res);
                    if (f == null) return;
                    run_export_table.begin (win, o, f);
                } catch (Error e) {
                }
            });
        }

        private static async void run_export_table (ClientWindow win, CatalogObject o, File f) {
            var t = new Toast (_("Exporting %s").printf (o.name));
            t.timeout = 0;
            win.add_toast (t);
            try {
                var e = yield win.ready ();
                int64 n = yield RemoteTransfer.export_table (e, o.schema, o.name, f, format_for (f.get_path ()), null, (rows) => t.title = ngettext ("Exporting %s: %lld row", "Exporting %s: %lld rows", (ulong) rows).printf (o.name, rows));
                t.dismiss ();
                win.toast (ngettext ("Exported %lld row to %s", "Exported %lld rows to %s", (ulong) n).printf (n, f.get_basename ()));
            } catch (Error e) {
                t.dismiss ();
                win.show_error (_("Could Not Export"), e.message);
            }
        }

        public static void export_query (ClientWindow win, string sql, string name) {
            var fd = save_dialog (_("Export Result"), name + ".csv");
            fd.save.begin (win, null, (obj, res) => {
                try {
                    var f = fd.save.end (res);
                    if (f == null) return;
                    run_export_query.begin (win, sql, f);
                } catch (Error e) {
                }
            });
        }

        private static async void run_export_query (ClientWindow win, string sql, File f) {
            var t = new Toast (_("Exporting the result"));
            t.timeout = 0;
            win.add_toast (t);
            try {
                var e = yield win.ready ();
                string clean = sql.strip ();
                while (clean.has_suffix (";")) clean = clean.substring (0, clean.length - 1).strip ();
                string base_name = f.get_basename ();
                int dot = base_name.last_index_of (".");
                if (dot > 0) base_name = base_name.substring (0, dot);
                int64 n = yield RemoteTransfer.export_query (e, clean, f, format_for (f.get_path ()), e.quote_ident (base_name), null, (rows) => t.title = ngettext ("Exporting: %lld row", "Exporting: %lld rows", (ulong) rows).printf (rows));
                t.dismiss ();
                win.toast (ngettext ("Exported %lld row to %s", "Exported %lld rows to %s", (ulong) n).printf (n, f.get_basename ()));
            } catch (Error e) {
                t.dismiss ();
                win.show_error (_("Could Not Export"), e.message);
            }
        }

        public static void import_into (ClientWindow win, CatalogObject o) {
            var fd = new FileDialog ();
            fd.title = _("Import into %s").printf (o.name);
            var filter = new FileFilter ();
            filter.name = _("Data Files");
            foreach (string s in new string[] { "csv", "tsv", "txt", "json", "ndjson", "xlsx" }) filter.add_suffix (s);
            var filters = new GLib.ListStore (typeof (FileFilter));
            filters.append (filter);
            fd.filters = filters;
            fd.open.begin (win, null, (obj, res) => {
                try {
                    var f = fd.open.end (res);
                    if (f == null || f.get_path () == null) return;
                    prepare_import.begin (win, o, f.get_path ());
                } catch (Error e) {
                }
            });
        }

        private static DataTable load_data (string path) throws Error {
            string p = path.down ();
            if (p.has_suffix (".json") || p.has_suffix (".ndjson")) {
                var list = JsonIO.load (path);
                if (list.size == 0) throw new RemoteError.UNSUPPORTED (_("The file has no records."));
                return list[0];
            }
            if (p.has_suffix (".xlsx")) {
                var list = Xlsx.load (path);
                if (list.size == 0) throw new RemoteError.UNSUPPORTED (_("The workbook has no sheets."));
                return list[0];
            }
            return Csv.load (path);
        }

        private static async void prepare_import (ClientWindow win, CatalogObject o, string path) {
            DataTable data;
            TableInfo info;
            try {
                data = load_data (path);
                var e = yield win.ready ();
                info = yield e.describe_table (o.schema, o.name);
            } catch (Error e) {
                win.show_error (_("Could Not Import"), e.message);
                return;
            }
            var dlg = make (win, _("Import into %s").printf (o.name), 520);
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.propagate_natural_height = true;
            scroll.max_content_height = 480;
            var box = new Box (Orientation.VERTICAL, 12);
            box.margin_start = box.margin_end = 18;
            box.margin_top = 6;
            box.margin_bottom = 8;
            scroll.child = box;
            var g = new PreferencesGroup (_("Columns"), ngettext ("%d row in %s. Choose where each column goes.", "%d rows in %s. Choose where each column goes.", data.rows.size).printf (data.rows.size, Path.get_basename (path)));
            string skip = _("Skip");
            string[] targets = { skip };
            foreach (var c in info.columns) targets += c.name;
            var rows = new Gee.ArrayList<SelectionRow> ();
            foreach (string src in data.columns) {
                string pick = skip;
                foreach (var c in info.columns) if (c.name.casefold () == src.strip ().casefold ()) pick = c.name;
                var row = new SelectionRow (src, targets, pick);
                rows.add (row);
                g.add_row (row);
            }
            box.append (g);
            dlg.content_box.append (scroll);
            footer (dlg, _("Import"), () => {
                string[] map = {};
                foreach (var r in rows) map += r.current_value == skip ? "" : r.current_value;
                run_import.begin (win, o, data, map);
            });
            dlg.open_dialog ();
        }

        private static async void run_import (ClientWindow win, CatalogObject o, DataTable data, owned string[] map) {
            var t = new Toast (_("Importing into %s").printf (o.name));
            t.timeout = 0;
            win.add_toast (t);
            try {
                var e = yield win.ready ();
                int64 n = yield RemoteTransfer.import_rows (e, o.schema, o.name, data, map, null, (rows) => t.title = ngettext ("Importing: %lld row", "Importing: %lld rows", (ulong) rows).printf (rows));
                t.dismiss ();
                win.toast (ngettext ("Imported %lld row", "Imported %lld rows", (ulong) n).printf (n));
                var tab = win.find_tab (ClientWindow.object_key (o));
                if (tab != null) tab.reload ();
                win.load_catalog.begin ();
            } catch (Error e) {
                t.dismiss ();
                win.show_error (_("Nothing Was Imported"), e.message);
            }
        }

        public static void new_table (ClientWindow win) {
            var dlg = make (win, _("New Table"), 460);
            var box = new Box (Orientation.VERTICAL, 12);
            box.margin_start = box.margin_end = 18;
            box.margin_top = 6;
            box.margin_bottom = 8;
            var g = new PreferencesGroup (_("Table"), _("It starts with an id key and a name column. Add columns in Structure."));
            var name = new EntryRow (_("Name"));
            g.add_row (name);
            box.append (g);
            dlg.content_box.append (box);
            footer (dlg, _("Create"), () => {
                string n = name.text.strip ();
                if (n == "") return;
                var e = win.engine;
                string q = e.qualified (win.schema, n);
                string sql;
                switch (win.config.kind) {
                    case EngineKind.POSTGRESQL:
                        sql = "CREATE TABLE %s (\n    id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,\n    name text\n)".printf (q);
                        break;
                    case EngineKind.MYSQL:
                        sql = "CREATE TABLE %s (\n    id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,\n    name VARCHAR(255)\n)".printf (q);
                        break;
                    default:
                        sql = "CREATE TABLE %s (\n    id INTEGER PRIMARY KEY AUTOINCREMENT,\n    name TEXT\n)".printf (q);
                        break;
                }
                create_table.begin (win, sql, n);
            });
            dlg.open_dialog ();
            name.grab_focus ();
        }

        private static async void create_table (ClientWindow win, string sql, string name) {
            try {
                var e = yield win.ready ();
                yield e.execute (sql);
            } catch (Error e) {
                win.show_error (_("Could Not Create Table"), e.message);
                return;
            }
            yield win.load_catalog ();
            foreach (var o in win.objects) {
                if (o.kind == ObjectKind.TABLE && o.name == name) {
                    win.open_object (o, "structure");
                    break;
                }
            }
        }

        public static void run_file (ClientWindow win) {
            var fd = new FileDialog ();
            fd.title = _("Run SQL File");
            var filter = new FileFilter ();
            filter.name = _("SQL Scripts");
            filter.add_suffix ("sql");
            var filters = new GLib.ListStore (typeof (FileFilter));
            filters.append (filter);
            fd.filters = filters;
            fd.open.begin (win, null, (obj, res) => {
                try {
                    var f = fd.open.end (res);
                    if (f == null || f.get_path () == null) return;
                    string text;
                    FileUtils.get_contents (f.get_path (), out text);
                    int n = SqlScript.split (text, win.config.kind).size;
                    win.confirm (_("Run %s?").printf (f.get_basename ()), ngettext ("The file has %d statement. It runs against %s.", "The file has %d statements. They run against %s.", n).printf (n, win.config.name), _("Run"), () => run_script.begin (win, text, f.get_basename ()), false);
                } catch (Error e) {
                    win.show_error (_("Could Not Read File"), e.message);
                }
            });
        }

        private static async void run_script (ClientWindow win, string text, string name) {
            var t = new Toast (_("Running %s").printf (name));
            t.timeout = 0;
            win.add_toast (t);
            try {
                var e = yield win.ready ();
                int64 n = yield RemoteTransfer.run_script (e, text, null);
                t.dismiss ();
                win.toast (ngettext ("%lld statement ran", "%lld statements ran", (ulong) n).printf (n));
            } catch (Error e) {
                t.dismiss ();
                win.show_error (_("The Script Stopped"), e.message);
            }
            yield win.load_catalog ();
        }

        public static void dump_schema (ClientWindow win) {
            var dlg = make (win, _("Export Schema as SQL"), 460);
            var box = new Box (Orientation.VERTICAL, 12);
            box.margin_start = box.margin_end = 18;
            box.margin_top = 6;
            box.margin_bottom = 8;
            string gtitle = win.config.name;
            if (!win.is_sqlite && win.schema != "") gtitle = win.schema;
            var g = new PreferencesGroup (gtitle, _("Tables, views, functions and triggers as one SQL script."));
            var data = new SwitchRow (_("Include Data"), _("Adds an INSERT for every row"), true);
            g.add_row (data);
            box.append (g);
            dlg.content_box.append (box);
            footer (dlg, _("Export"), () => {
                bool with_data = data.active;
                var fd = new FileDialog ();
                fd.title = _("Export Schema as SQL");
                fd.initial_name = (win.schema != "" && win.schema != "main" ? win.schema : win.config.name) + ".sql";
                fd.save.begin (win, null, (obj, res) => {
                    try {
                        var f = fd.save.end (res);
                        if (f == null) return;
                        run_dump.begin (win, f, with_data);
                    } catch (Error e) {
                    }
                });
            });
            dlg.open_dialog ();
        }

        private static async void run_dump (ClientWindow win, File f, bool with_data) {
            var t = new Toast (_("Exporting the schema"));
            t.timeout = 0;
            win.add_toast (t);
            try {
                var e = yield win.ready ();
                int64 n = yield RemoteTransfer.dump_schema (e, win.schema, f, with_data, null, (rows) => t.title = ngettext ("Exporting: %lld row", "Exporting: %lld rows", (ulong) rows).printf (rows));
                t.dismiss ();
                win.toast (with_data ? ngettext ("Schema and %lld row exported", "Schema and %lld rows exported", (ulong) n).printf (n) : _("Schema exported"));
            } catch (Error e) {
                t.dismiss ();
                win.show_error (_("Could Not Export"), e.message);
            }
        }
    }
}
