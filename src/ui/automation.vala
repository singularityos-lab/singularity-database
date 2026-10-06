using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Database {

    public class DbHost : Object, ScriptHost {
        private weak DatabaseWindow win;
        public StringBuilder immediate = new StringBuilder ();
        public signal void printed (string text);

        public DbHost (DatabaseWindow win) {
            this.win = win;
        }

        private int run_modal (AppDialog dlg, ref int result) {
            var loop = new MainLoop ();
            dlg.close_request.connect (() => {
                if (loop.is_running ()) loop.quit ();
                return false;
            });
            dlg.open_dialog ();
            loop.run ();
            return result;
        }

        public int message_box (string prompt, int buttons, string title) {
            if (win == null) return 1;
            var dlg = new AppDialog (win.app, true);
            dlg.set_title (title != "" ? title : _("Database"));
            dlg.transient_for = win;
            dlg.set_default_size (420, -1);
            var body = new Box (Orientation.HORIZONTAL, 14);
            body.margin_start = body.margin_end = 20;
            body.margin_top = 8;
            body.margin_bottom = 12;
            int icon_kind = buttons & 0x70;
            string icon = icon_kind == 16 ? "dialog-error" : (icon_kind == 32 ? "dialog-question" : (icon_kind == 48 ? "dialog-warning" : (icon_kind == 64 ? "dialog-information" : "")));
            if (icon != "") {
                var img = new Image.from_icon_name (icon);
                img.pixel_size = 48;
                img.valign = Align.START;
                body.append (img);
            }
            var label = new Label (prompt);
            label.wrap = true;
            label.max_width_chars = 60;
            label.width_chars = int.min (prompt.char_count (), 40);
            label.xalign = 0;
            label.halign = Align.START;
            label.selectable = true;
            body.append (label);
            dlg.content_box.append (body);
            var bar = new Box (Orientation.HORIZONTAL, 8);
            bar.halign = Align.END;
            bar.margin_start = bar.margin_end = 18;
            bar.margin_bottom = 16;
            int result = 2;
            string[] labels;
            int[] codes;
            switch (buttons & 7) {
                case 1: labels = { _("Cancel"), _("OK") }; codes = { 2, 1 }; break;
                case 2: labels = { _("Abort"), _("Retry"), _("Ignore") }; codes = { 3, 4, 5 }; break;
                case 3: labels = { _("Cancel"), _("No"), _("Yes") }; codes = { 2, 7, 6 }; break;
                case 4: labels = { _("No"), _("Yes") }; codes = { 7, 6 }; break;
                case 5: labels = { _("Cancel"), _("Retry") }; codes = { 2, 4 }; break;
                default: labels = { _("OK") }; codes = { 1 }; result = 1; break;
            }
            for (int i = 0; i < labels.length; i++) {
                var b = new Button.with_label (labels[i]);
                int code = codes[i];
                if (i == labels.length - 1) {
                    b.add_css_class ("suggested-action");
                    dlg.default_widget = b;
                }
                b.clicked.connect (() => {
                    result = code;
                    dlg.close ();
                });
                if (labels[i] == _("Cancel")) dlg.set_cancel_button (b);
                bar.append (b);
            }
            dlg.content_box.append (bar);
            return run_modal (dlg, ref result);
        }

        public string? input_box (string prompt, string title, string default_value) {
            if (win == null) return default_value;
            var dlg = Dialogs.make (win, title != "" ? title : _("Database"), 420, 260);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (prompt, null);
            var e = new EntryRow (_("Value"));
            e.text = default_value;
            g.add_row (e);
            box.append (g);
            string? answer = null;
            Dialogs.footer (dlg, _("OK"), () => {
                answer = e.text;
                return true;
            });
            int dummy = 0;
            run_modal (dlg, ref dummy);
            return answer;
        }

        public void debug_print (string text) {
            immediate.append (text).append ("\n");
            printed (text);
        }

        public ScriptObject? find_object (string kind, string name) {
            if (win == null) return null;
            switch (kind) {
                case "form":
                    var p = win.find_page ("form", name) as FormPage;
                    return p != null ? p.script_object () : null;
                case "report":
                    var r = win.find_page ("report", name) as ReportPage;
                    return r != null ? r.script_object () : null;
                case "active-form":
                    var cf = win.current_page () as FormPage;
                    return cf != null ? cf.script_object () : null;
                case "active-control":
                    var cp = win.current_page () as FormPage;
                    return cp != null ? cp.active_control_object () : null;
                case "active-report":
                    var cr = win.current_page () as ReportPage;
                    return cr != null ? cr.script_object () : null;
            }
            return null;
        }

        public string[] open_objects (string kind) {
            return win != null ? win.open_names (kind) : new string[0];
        }

        private static string arg (SValue[] args, int i) {
            if (i >= args.length || args[i] is MissingValue) return "";
            return args[i].to_text ();
        }

        private static int num (SValue[] args, int i, int fallback) {
            if (i >= args.length || args[i] is MissingValue || args[i].is_empty) return fallback;
            try {
                return (int) args[i].to_int ();
            } catch (ScriptError e) {
                return fallback;
            }
        }

        private static string kind_for (int type) {
            switch (type) {
                case 0: return "table";
                case 1: return "query";
                case 2: return "form";
                case 3: return "report";
                case 4: return "macro";
                case 5: return "module";
                default: return "";
            }
        }

        public void run_command (string command, SValue[] args, string[] names) throws ScriptError {
            if (win == null || win.db == null) return;
            switch (command.down ()) {
                case "openform":
                    string form = arg (args, 0);
                    if (win.db.get_meta ("form:" + form) == null) throw Script.fail (2102, _("The form \"%s\" does not exist.").printf (form));
                    int view = num (args, 1, 0);
                    win.open_object ("form", form, view == 1 ? "design" : null);
                    var fp = win.find_page ("form", form) as FormPage;
                    if (fp != null) {
                        string where = arg (args, 3);
                        string filter = arg (args, 2);
                        if (filter != "" && where == "") {
                            var q = SavedQueries.load (win.db, filter);
                            if (q != null) where = QueryWhere.extract (q.sql);
                        }
                        fp.open_with (where, num (args, 4, -1), arg (args, 6), view == 3);
                    }
                    return;
                case "openreport":
                    string report = arg (args, 0);
                    if (win.db.get_meta ("report:" + report) == null) throw Script.fail (2103, _("The report \"%s\" does not exist.").printf (report));
                    int rview = num (args, 1, 5);
                    win.open_object ("report", report, rview == 1 ? "design" : null);
                    var rp = win.find_page ("report", report) as ReportPage;
                    if (rp != null) {
                        rp.open_with (arg (args, 3), arg (args, 5));
                        if (rview == 0) rp.run_action ("print", null);
                    }
                    return;
                case "opentable":
                    win.open_object ("table", arg (args, 0), num (args, 1, 0) == 1 ? "design" : null);
                    return;
                case "openquery":
                    string qn = arg (args, 0);
                    var sq = SavedQueries.load (win.db, qn);
                    if (sq != null && !QueryPrep.is_select_like (sq.sql)) {
                        try {
                            win.run_saved_action (qn);
                        } catch (Error e) {
                            throw Script.fail (3061, e.message);
                        }
                        return;
                    }
                    win.open_object ("query", qn, num (args, 1, 0) == 1 ? "design" : null);
                    return;
                case "openqueryaction":
                    try {
                        win.run_saved_action (arg (args, 0));
                    } catch (Error e) {
                        throw Script.fail (3061, e.message);
                    }
                    return;
                case "openmodule":
                    win.open_object ("module", arg (args, 0));
                    return;
                case "close":
                case "closewindow":
                    string k = kind_for (num (args, 0, -1));
                    string n = arg (args, 1);
                    win.close_object (k, n);
                    return;
                case "selectobject":
                    win.open_object (kind_for (num (args, 0, 0)), arg (args, 1));
                    return;
                case "browseto":
                    win.open_object (kind_for (num (args, 0, 2)), arg (args, 1));
                    return;
                case "gotorecord":
                    var target = arg (args, 1) != "" ? win.find_page (kind_for (num (args, 0, 2)) != "" ? kind_for (num (args, 0, 2)) : "form", arg (args, 1)) : win.current_page ();
                    if (target == null) return;
                    int rec = num (args, 2, 1);
                    int offset = num (args, 3, 1);
                    string[] actions = { "prev-record", "next-record", "first-record", "last-record", "goto-record", "new-record" };
                    if (rec == 4) {
                        var f = target as FormPage;
                        if (f != null) f.go_to_record (offset - 1);
                        return;
                    }
                    if (rec >= 0 && rec < actions.length && target.handles (actions[rec])) {
                        for (int i = 0; i < ((rec == 0 || rec == 1) ? int.max (1, offset) : 1); i++) target.run_action (actions[rec], null);
                    }
                    return;
                case "gotocontrol":
                    var fc = win.current_page () as FormPage;
                    if (fc != null) fc.focus_control (arg (args, 0));
                    return;
                case "requery":
                case "refresh":
                case "refreshrecord":
                case "showallrecords":
                case "saverecord":
                case "deleterecord":
                case "undorecord":
                case "applyfilter":
                case "findrecord":
                case "setproperty":
                case "runcommand":
                    var page = win.current_page ();
                    var formp = page as FormPage;
                    if (formp != null) {
                        formp.script_command (command.down (), args);
                        return;
                    }
                    if (page != null) {
                        string c = command.down ();
                        if (c == "saverecord" && page.handles ("save-record")) page.run_action ("save-record", null);
                        else if (c == "deleterecord" && page.handles ("delete-record")) page.run_action ("delete-record", null);
                        else if ((c == "showallrecords") && page.handles ("clear-filters")) page.run_action ("clear-filters", null);
                        else page.reload ();
                    }
                    return;
                case "datachanged":
                    win.db.data_changed ("");
                    return;
                case "beep":
                    win.error_bell ();
                    return;
                case "quit":
                case "quitaccess":
                    win.close_database ();
                    return;
                case "printobject":
                    win.run ("print");
                    return;
                case "exportwithformatting":
                case "outputto":
                    string okind = kind_for (num (args, 0, 3));
                    string oname = arg (args, 1);
                    string file = arg (args, 3);
                    try {
                        win.export_object_to (okind, oname, file != "" ? file : Path.build_filename (Environment.get_user_special_dir (UserDirectory.DOCUMENTS) ?? Environment.get_home_dir (), oname + ".pdf"));
                    } catch (Error e) {
                        throw Script.fail (2302, e.message);
                    }
                    return;
                case "emaildatabaseobject":
                case "sendobject":
                    win.share_object (kind_for (num (args, 0, 3)), arg (args, 1));
                    return;
                case "transferspreadsheet":
                case "transfertext":
                case "importexportspreadsheet":
                case "importexporttext":
                    int mode = num (args, 0, 0);
                    string tname = arg (args, 2);
                    string path = arg (args, 3);
                    try {
                        win.transfer (mode == 1, tname, path);
                    } catch (Error e) {
                        throw Script.fail (3011, e.message);
                    }
                    return;
                case "setwarnings":
                case "echo":
                case "hourglass":
                case "maximize":
                case "minimize":
                case "restore":
                case "setoption":
                case "refreshdatabasewindow":
                case "navigateto":
                case "lockNavigationpane":
                    return;
            }
            throw Script.fail (2046, _("The command \"%s\" is not available.").printf (command));
        }
    }

    public class QueryWhere {
        public static string extract (string sql) {
            var toks = Sql.tokenize (sql);
            int depth = 0;
            int where = -1;
            int end = sql.length;
            for (int i = 0; i < toks.size; i++) {
                if (toks[i].text == "(") depth++;
                else if (toks[i].text == ")") depth--;
                else if (depth == 0 && toks[i].text.up () == "WHERE") where = i;
                else if (depth == 0 && where >= 0 && (toks[i].text.up () == "ORDER" || toks[i].text.up () == "GROUP")) {
                    end = toks[i].start;
                    break;
                }
            }
            if (where < 0) return "";
            return sql.substring (toks[where].end, end - toks[where].end).strip ();
        }
    }

    public class ParamPrompt {
        public delegate void Done (Gee.List<QueryParam>? values);

        public static void resolve (DatabaseWindow win, string sql, owned Done done) {
            var params = QueryPrep.find_parameters (win.db, sql);
            if (params.size == 0) {
                done (params);
                return;
            }
            var ask = new Gee.ArrayList<QueryParam> ();
            foreach (var p in params) {
                var auto = win.reference_value (p.name);
                if (auto != null) p.value = auto;
                else ask.add (p);
            }
            if (ask.size == 0) {
                done (params);
                return;
            }
            var dlg = Dialogs.make (win, _("Enter Parameter Values"), 440, 200 + ask.size * 60);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (_("Parameters"), _("The query asks for these values."));
            var rows = new Gee.ArrayList<EntryRow> ();
            foreach (var p in ask) {
                var e = new EntryRow (p.name);
                if (p.type_name != "") e.tooltip_text = p.type_name;
                g.add_row (e);
                rows.add (e);
            }
            box.append (g);
            bool ok = false;
            dlg.close_request.connect (() => {
                if (!ok) done (null);
                return false;
            });
            Dialogs.footer (dlg, _("OK"), () => {
                for (int i = 0; i < ask.size; i++) ask[i].value = QueryPrep.coerce (ask[i], rows[i].text);
                ok = true;
                done (params);
                return true;
            });
            dlg.open_dialog ();
        }
    }
}
