using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Database {

    public class TransferDialogs {
        public static void import (DatabaseWindow win) {
            var dialog = new FileDialog ();
            dialog.title = _("Import Data");
            var filters = new GLib.ListStore (typeof (FileFilter));
            var all = new FileFilter ();
            all.name = _("Supported Files");
            foreach (string s in Transfer.import_extensions ()) all.add_suffix (s);
            filters.append (all);
            string[,] kinds = {
                { _("Comma or Tab Separated Values"), "csv tsv txt" }, { _("Excel Workbook"), "xlsx" }, { _("JSON"), "json ndjson" },
                { _("SQL Script"), "sql" }, { _("Access Database"), "mdb accdb" }, { _("Access Objects Saved as Text"), "form report macro bas cls" }, { _("XML Data"), "xml" }, { _("SQLite Database"), "sqlite sqlite3 db sdb" }
            };
            for (int i = 0; i < kinds.length[0]; i++) {
                var f = new FileFilter ();
                f.name = kinds[i, 0];
                foreach (string s in kinds[i, 1].split (" ")) f.add_suffix (s);
                filters.append (f);
            }
            dialog.filters = filters;
            dialog.open.begin (win, null, (obj, res) => {
                try {
                    var file = dialog.open.end (res);
                    if (file != null) import_file (win, file.get_path ());
                } catch (Error e) {
                }
            });
        }

        private static string ext (string path) {
            string p = path.down ();
            int dot = p.last_index_of (".");
            return dot >= 0 ? p.substring (dot + 1) : "";
        }

        public static void import_file (DatabaseWindow win, string path) {
            var db = win.db;
            if (db == null) return;
            string e = ext (path);
            try {
                switch (e) {
                    case "mdb":
                    case "accdb":
                        try {
                            var results = Transfer.import_mdb (db, path);
                            report (win, results, Path.get_basename (path));
                        } catch (MdbError.PASSWORD pe) {
                            ToolDialogs.ask_password (win.app, win, path, null, (pw) => {
                                try {
                                    report (win, Transfer.import_mdb (db, path, pw), Path.get_basename (path));
                                } catch (Error e2) {
                                    win.show_error (_("Could Not Import \"%s\"").printf (Path.get_basename (path)), e2.message);
                                }
                            });
                        }
                        return;
                    case "form":
                    case "report":
                    case "macro":
                    case "bas":
                    case "cls":
                        var r = AccessObjectImport.import_file (db, path);
                        win.load_runtime ();
                        win.rebuild_sidebar ();
                        string k = e == "bas" || e == "cls" ? "module" : e;
                        if (win.db.get_meta (k + ":" + r.table) != null) win.open_object (k, r.table);
                        win.toast (_("Imported \"%s\"").printf (r.table));
                        if (r.notes.size > 0) Dialogs.notes (win, _("Import Finished"), r.notes.to_array ());
                        return;
                    case "sqlite":
                    case "sqlite3":
                    case "db":
                    case "sdb":
                    case "db3":
                        var r2 = Transfer.import_sqlite (db, path);
                        report (win, r2, Path.get_basename (path));
                        return;
                    case "sql":
                        confirm_sql (win, path);
                        return;
                    case "xlsx":
                        wizard (win, path, Xlsx.load (path, true), true, false);
                        return;
                    case "json":
                    case "ndjson":
                        wizard (win, path, JsonIO.load (path), false, false);
                        return;
                    case "xml":
                        string xml_text;
                        FileUtils.get_contents (path, out xml_text);
                        wizard (win, path, DataExport.from_xml (xml_text, Path.get_basename (path)), false, false);
                        return;
                    default:
                        var list = new Gee.ArrayList<DataTable> ();
                        list.add (Csv.load (path));
                        wizard (win, path, list, true, true);
                        return;
                }
            } catch (Error err) {
                win.show_error (_("Could Not Import \"%s\"").printf (Path.get_basename (path)), err.message);
            }
        }

        private static void report (DatabaseWindow win, Gee.ArrayList<ImportResult> results, string from) {
            int rows = 0;
            string[] notes = {};
            foreach (var r in results) {
                rows += r.imported;
                notes += "%s: %s".printf (r.table, ngettext ("%d record", "%d records", r.imported).printf (r.imported));
                foreach (string n in r.notes) notes += n;
            }
            win.rebuild_sidebar ();
            win.toast (_("Imported %s from %s").printf (ngettext ("%d table", "%d tables", results.size).printf (results.size), from));
            if (results.size > 0) win.open_object ("table", results[0].table);
            bool important = false;
            foreach (var r in results) if (r.notes.size > 0) important = true;
            if (important) Dialogs.notes (win, _("Import Finished"), notes);
        }

        private static void confirm_sql (DatabaseWindow win, string path) {
            var dlg = new ConfirmDialog (win.app, _("Run the SQL Script?"), "dialog-warning",
                _("\"%s\" is run against this database. Scripts can create, change and delete tables, and the changes cannot be undone.").printf (Path.get_basename (path)),
                _("Run Script"), ConfirmDialog.ActionStyle.DESTRUCTIVE);
            dlg.transient_for = win;
            dlg.response.connect ((r) => {
                if (r != ConfirmDialog.Response.PRIMARY) return;
                try {
                    string text;
                    FileUtils.get_contents (path, out text);
                    int before = win.db.table_names ().size;
                    SqlDump.import_script (win.db, text);
                    win.db.invalidate ();
                    win.rebuild_sidebar ();
                    int after = win.db.table_names ().size;
                    win.toast (_("Script run: %s").printf (ngettext ("%d new table", "%d new tables", int.max (0, after - before)).printf (int.max (0, after - before))));
                } catch (Error e) {
                    win.show_error (_("Could Not Run the Script"), e.message);
                }
            });
            dlg.present ();
        }

        private static void wizard (DatabaseWindow win, string path, Gee.ArrayList<DataTable> tables, bool header_option, bool csv) {
            var db = win.db;
            if (tables.size == 0) {
                win.show_error (_("Nothing to Import"), _("The file does not contain any data."));
                return;
            }
            var dlg = Dialogs.make (win, _("Import \"%s\"").printf (Path.get_basename (path)), 760, 680);
            var box = Dialogs.body (dlg);
            DataTable current = tables[0];
            var types = new Gee.ArrayList<DropDown> ();
            var source_g = new PreferencesGroup (_("Source"), null);
            SelectionRow? sheet = null;
            if (tables.size > 1) {
                string[] names = {};
                foreach (var t in tables) names += t.name;
                sheet = new SelectionRow (_("Sheet"), names, names[0]);
                source_g.add_row (sheet);
            }
            SwitchRow? header = null;
            if (header_option) {
                header = new SwitchRow (_("First Row Has Field Names"), null, true);
                source_g.add_row (header);
            }
            SelectionRow? sep = null;
            string[] seps = { _("Comma"), _("Semicolon"), _("Tab"), _("Vertical Bar") };
            char[] sep_chars = { ',', ';', '\t', '|' };
            string text = "";
            if (csv) {
                try {
                    text = Csv.read_text (path);
                } catch (Error e) {
                }
                char detected = path.down ().has_suffix (".tsv") ? '\t' : Csv.detect (text);
                string cur = seps[0];
                for (int i = 0; i < 4; i++) if (sep_chars[i] == detected) cur = seps[i];
                sep = new SelectionRow (_("Separator"), seps, cur);
                source_g.add_row (sep);
            }
            if (source_g.get_first_child () != null && (sheet != null || header != null || sep != null)) box.append (source_g);
            var dest = new PreferencesGroup (_("Destination"), null);
            string[] modes = { _("New Table"), _("Append to a Table"), _("Replace the Records of a Table") };
            var mode = new SelectionRow (_("Import Into"), modes, modes[0]);
            dest.add_row (mode);
            var name = new EntryRow (_("New Table Name"));
            name.text = db.unique_object_name (current.name);
            dest.add_row (name);
            var tables_list = db.table_names ();
            SelectionRow? existing = null;
            if (tables_list.size > 0) {
                existing = new SelectionRow (_("Table"), tables_list.to_array (), tables_list[0]);
                existing.visible = false;
                dest.add_row (existing);
            }
            var add_id = new SwitchRow (_("Add an ID Field"), _("A numbered primary key for each record"), true);
            dest.add_row (add_id);
            box.append (dest);
            var preview_label = new Label (_("Preview and Field Types"));
            preview_label.add_css_class ("heading");
            preview_label.halign = Align.START;
            box.append (preview_label);
            var preview = new Grid ();
            preview.column_spacing = 12;
            preview.row_spacing = 4;
            var pscroll = new ScrolledWindow ();
            pscroll.vscrollbar_policy = PolicyType.NEVER;
            pscroll.child = preview;
            pscroll.add_css_class ("db-sql-frame");
            box.append (pscroll);
            var count = new Label ("");
            count.add_css_class ("caption");
            count.add_css_class ("dim-label");
            count.halign = Align.START;
            box.append (count);
            string[] type_names = {};
            foreach (var t in FieldType.ALL) {
                if (t != FieldType.AUTONUMBER && t != FieldType.LOOKUP) type_names += t.label ();
            }
            Callback fill = () => {
                Widget? c;
                while ((c = preview.get_first_child ()) != null) preview.remove (c);
                types.clear ();
                for (int col = 0; col < current.columns.length; col++) {
                    var h = new Label (current.columns[col]);
                    h.add_css_class ("heading");
                    h.halign = Align.START;
                    h.margin_start = h.margin_top = 6;
                    preview.attach (h, col, 0, 1, 1);
                    var dd = new DropDown.from_strings (type_names);
                    var inferred = Transfer.infer_column (current, col);
                    for (int k = 0; k < type_names.length; k++) if (type_names[k] == inferred.label ()) dd.selected = k;
                    preview.attach (dd, col, 1, 1, 1);
                    types.add (dd);
                    for (int r = 0; r < int.min (8, current.rows.size); r++) {
                        var v = current.rows[r].get (col);
                        var l = new Label (v.kind == ValueKind.BLOB ? _("(binary)") : v.to_string ().replace ("\n", " "));
                        l.halign = Align.START;
                        l.ellipsize = Pango.EllipsizeMode.END;
                        l.max_width_chars = 24;
                        l.margin_start = 6;
                        preview.attach (l, col, 2 + r, 1, 1);
                    }
                }
                count.label = ngettext ("%d record to import", "%d records to import", current.rows.size).printf (current.rows.size);
            };
            Callback reload_source = () => {
                if (csv) {
                    char sc = ',';
                    for (int i = 0; i < 4; i++) if (seps[i] == sep.current_value) sc = sep_chars[i];
                    string nm = Path.get_basename (path);
                    int dot = nm.last_index_of (".");
                    current = Csv.from_text (text, dot > 0 ? nm.substring (0, dot) : nm, sc, header == null || header.active);
                } else if (header_option) {
                    try {
                        var re = Xlsx.load (path, header.active);
                        int idx = 0;
                        if (sheet != null) for (int i = 0; i < tables.size; i++) if (tables[i].name == sheet.current_value) idx = i;
                        if (idx < re.size) current = re[idx];
                    } catch (Error e) {
                    }
                } else if (sheet != null) {
                    foreach (var t in tables) if (t.name == sheet.current_value) current = t;
                }
                fill ();
            };
            if (sheet != null) sheet.selected.connect ((v) => {
                reload_source ();
                name.text = db.unique_object_name (current.name);
            });
            if (header != null) header.switch_btn.notify["active"].connect (() => reload_source ());
            if (sep != null) sep.selected.connect ((v) => reload_source ());
            mode.selected.connect ((v) => {
                bool fresh = v == modes[0];
                name.visible = fresh;
                add_id.visible = fresh;
                if (existing != null) existing.visible = !fresh;
                pscroll.sensitive = fresh;
            });
            reload_source ();
            Dialogs.footer (dlg, _("Import"), () => {
                var im = mode.current_value == modes[0] ? ImportMode.NEW_TABLE : (mode.current_value == modes[1] ? ImportMode.APPEND : ImportMode.REPLACE);
                string target = im == ImportMode.NEW_TABLE ? name.text.strip () : (existing != null ? existing.current_value : "");
                if (target == "") return false;
                FieldType[] over = {};
                foreach (var dd in types) {
                    foreach (var t in FieldType.ALL) {
                        if (t.label () == type_names[dd.selected]) over += t;
                    }
                }
                try {
                    var res = Transfer.import_table (db, current, target, im, add_id.active, im == ImportMode.NEW_TABLE ? over : null);
                    var list = new Gee.ArrayList<ImportResult> ();
                    list.add (res);
                    report (win, list, Path.get_basename (path));
                } catch (Error e) {
                    win.show_error (_("Could Not Import"), e.message);
                    return false;
                }
                return true;
            });
            dlg.open_dialog ();
        }

        private delegate void Callback ();

        public static void write_source (RecordSource rs, string path) throws Error {
            if (path.down ().has_suffix (".pdf")) {
                var r = ReportDef.generate (rs.db, rs.source);
                r.title = rs.source;
                r.state = rs.state.copy ();
                ReportRenderer.export_pdf (new ReportRenderer ().layout (r, ReportEngine.open_source (rs.db, r)), path, r.title);
                return;
            }
            DataExport.write (Transfer.from_source (rs), path);
        }

        public static void import_path (DatabaseWindow win, string path, string table) throws Error {
            string e = ext (path);
            Gee.ArrayList<DataTable> tables;
            if (e == "xlsx") tables = Xlsx.load (path, true);
            else if (e == "json" || e == "ndjson") tables = JsonIO.load (path);
            else if (e == "xml") {
                string text;
                FileUtils.get_contents (path, out text);
                tables = DataExport.from_xml (text, table);
            } else {
                tables = new Gee.ArrayList<DataTable> ();
                tables.add (Csv.load (path));
            }
            if (tables.size == 0) return;
            bool exists = win.db.object_exists (table, "table");
            Transfer.import_table (win.db, tables[0], table, exists ? ImportMode.APPEND : ImportMode.NEW_TABLE);
            win.rebuild_sidebar ();
        }

        public static void export_object (DatabaseWindow win, string? name) {
            var db = win.db;
            string[] sources = {};
            foreach (string t in db.table_names ()) sources += t;
            foreach (string q in db.view_names ()) sources += q;
            if (sources.length == 0) {
                win.show_error (_("Nothing to Export"), _("The database has no tables yet."));
                return;
            }
            var dlg = Dialogs.make (win, _("Export"), 460, 460);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (_("Data"), null);
            var src = new SelectionRow (_("Table or Query"), sources, name ?? sources[0]);
            g.add_row (src);
            string[] formats = { _("Excel Workbook (.xlsx)"), _("Comma Separated Values (.csv)"), _("Tab Separated Values (.tsv)"), _("JSON (.json)"), _("XML Data and Schema (.xml)"), _("Web Page (.html)"), _("Word Rich Text (.rtf)"), _("Fixed Width Text (.txt)"), _("PDF Report (.pdf)"), _("SQL Statements (.sql)") };
            string[] exts = { "xlsx", "csv", "tsv", "json", "xml", "html", "rtf", "txt", "pdf", "sql" };
            var fmt = new SelectionRow (_("Format"), formats, formats[0]);
            g.add_row (fmt);
            var formatted = new SwitchRow (_("Formatted Values"), _("Export values as they are shown, such as currency symbols and lookup names"), false);
            g.add_row (formatted);
            TablePage? page = null;
            if (name != null) page = win.find_page ("table", name) as TablePage;
            SwitchRow? view_only = null;
            if (page != null && page.src != null && (page.src.state.filters.size > 0 || page.src.state.search != "" || page.src.state.sorts.size > 0 || page.src.state.hidden.size > 0)) {
                view_only = new SwitchRow (_("Only the Current View"), _("Use the filters, sorting and visible fields of the open view"), true);
                g.add_row (view_only);
            }
            box.append (g);
            Dialogs.footer (dlg, _("Export…"), () => {
                int fi = 0;
                for (int i = 0; i < formats.length; i++) if (formats[i] == fmt.current_value) fi = i;
                string source = src.current_value;
                RecordSource rs;
                try {
                    if (view_only != null && view_only.active && source == name) {
                        var st = page.src.state.copy ();
                        rs = new RecordSource (db, source, st);
                    } else {
                        rs = new RecordSource (db, source);
                    }
                } catch (Error e) {
                    win.show_error (_("Could Not Export"), e.message);
                    return false;
                }
                bool visible = view_only != null && view_only.active;
                save_export.begin (win, rs, exts[fi], formatted.active, visible);
                return true;
            });
            dlg.open_dialog ();
        }

        private static async void save_export (DatabaseWindow win, RecordSource rs, string ext, bool formatted, bool visible_only) {
            var dialog = new FileDialog ();
            dialog.title = _("Export");
            string base_name = (rs.source != "" ? rs.source : win.db.display_name ()).replace ("/", "-");
            dialog.initial_name = base_name + "." + ext;
            try {
                var file = yield dialog.save (win, null);
                if (file == null) return;
                string path = file.get_path ();
                if (!path.down ().has_suffix ("." + ext)) path += "." + ext;
                switch (ext) {
                    case "pdf":
                        var r = ReportDef.generate (win.db, rs.source);
                        r.title = rs.source;
                        r.state = rs.state.copy ();
                        var renderer = new ReportRenderer ();
                        ReportRenderer.export_pdf (renderer.layout (r, ReportEngine.open_source (win.db, r)), path, r.title);
                        break;
                    case "sql":
                        var dt = Transfer.from_source (rs, false, visible_only);
                        var sb = new StringBuilder ();
                        string tq = Sql.quote_ident (rs.source);
                        string[] cols = {};
                        foreach (string c in dt.columns) cols += Sql.quote_ident (c);
                        foreach (var row in dt.rows) {
                            string[] vals = {};
                            for (int i = 0; i < dt.columns.length; i++) vals += row.get (i).sql_literal ();
                            sb.append ("INSERT INTO %s (%s) VALUES (%s);\n".printf (tq, string.joinv (", ", cols), string.joinv (", ", vals)));
                        }
                        FileUtils.set_contents (path, sb.str);
                        break;
                    default:
                        var dt = Transfer.from_source (rs, formatted, visible_only);
                        if (ext == "xlsx") {
                            var list = new Gee.ArrayList<DataTable> ();
                            list.add (dt);
                            Xlsx.save (list, path);
                        } else {
                            DataExport.write (dt, path);
                        }
                        break;
                }
                win.toast (_("Exported \"%s\"").printf (Path.get_basename (path)));
            } catch (Error e) {
                if (!(e is Gtk.DialogError.DISMISSED) && !(e is IOError.CANCELLED)) win.show_error (_("Could Not Export"), e.message);
            }
        }

        public static void export_database (DatabaseWindow win, string kind) {
            if (kind == "sql") {
                var dlg = Dialogs.make (win, _("Export Database as SQL"), 440, 320);
                var box = Dialogs.body (dlg);
                var g = new PreferencesGroup (_("SQL Dialect"), _("SQLite keeps everything, including forms and reports. The others create tables and data for another server."));
                string[] ds = { SqlDialect.SQLITE.label (), SqlDialect.POSTGRESQL.label (), SqlDialect.MYSQL.label () };
                var d = new SelectionRow (_("Dialect"), ds, ds[0]);
                g.add_row (d);
                box.append (g);
                Dialogs.footer (dlg, _("Export…"), () => {
                    var dialect = d.current_value == ds[1] ? SqlDialect.POSTGRESQL : (d.current_value == ds[2] ? SqlDialect.MYSQL : SqlDialect.SQLITE);
                    save_database.begin (win, "sql", dialect);
                    return true;
                });
                dlg.open_dialog ();
                return;
            }
            save_database.begin (win, kind, SqlDialect.SQLITE);
        }

        private static async void save_database (DatabaseWindow win, string kind, SqlDialect dialect) {
            var dialog = new FileDialog ();
            dialog.title = _("Export Database");
            dialog.initial_name = win.db.display_name () + "." + kind;
            try {
                var file = yield dialog.save (win, null);
                if (file == null) return;
                string path = file.get_path ();
                if (!path.down ().has_suffix ("." + kind)) path += "." + kind;
                switch (kind) {
                    case "xlsx":
                        Xlsx.save (Transfer.all_tables (win.db), path);
                        break;
                    case "json":
                        FileUtils.set_contents (path, JsonIO.export_many (Transfer.all_tables (win.db)));
                        break;
                    default:
                        FileUtils.set_contents (path, SqlDump.dump (win.db, dialect));
                        break;
                }
                win.toast (_("Exported \"%s\"").printf (Path.get_basename (path)));
            } catch (Error e) {
                if (!(e is Gtk.DialogError.DISMISSED) && !(e is IOError.CANCELLED)) win.show_error (_("Could Not Export"), e.message);
            }
        }
    }
}
