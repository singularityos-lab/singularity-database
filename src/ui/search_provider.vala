namespace Singularity.Apps.Database {

    public class DatabaseSearchProvider : Singularity.SearchProviderService {
        private const int MAX_RESULTS = 20;
        private weak DatabaseApp app;
        private Gee.HashMap<string, string> descriptions = new Gee.HashMap<string, string> ();

        public DatabaseSearchProvider (DatabaseApp app) {
            this.app = app;
        }

        private static string[] normalize (string[] terms) {
            string[] out_terms = {};
            foreach (string t in terms) {
                string s = t.strip ().casefold ();
                if (s != "") out_terms += s;
            }
            return out_terms;
        }

        private static bool all_in (string hay, string[] needles) {
            string h = hay.casefold ();
            foreach (string n in needles) {
                if (!h.contains (n)) return false;
            }
            return true;
        }

        private static Gee.ArrayList<string> recent_databases () {
            var list = new Gee.ArrayList<string> ();
            var items = new Gee.ArrayList<Gtk.RecentInfo> ();
            foreach (var info in Gtk.RecentManager.get_default ().get_items ()) {
                string uri = info.get_uri ();
                if (!uri.has_prefix ("file:")) continue;
                string? p = File.new_for_uri (uri).get_path ();
                if (p != null && DatabaseApp.is_database_file (p) && FileUtils.test (p, FileTest.EXISTS)) items.add (info);
            }
            items.sort ((a, b) => b.get_modified ().compare (a.get_modified ()));
            foreach (var i in items) {
                if (list.size >= 8) break;
                list.add (File.new_for_uri (i.get_uri ()).get_path ());
            }
            return list;
        }

        public override async string[] get_initial_results (string[] terms, Cancellable? cancellable) throws Error {
            string[] needles = normalize (terms);
            if (needles.length == 0) return {};
            string[] ids = {};
            descriptions.clear ();
            foreach (string path in recent_databases ()) {
                if (cancellable != null && cancellable.is_cancelled ()) break;
                Database db;
                try {
                    db = Database.open (path);
                } catch (Error e) {
                    continue;
                }
                string dbname = db.display_name ();
                string[] kinds = { "table", "query", "form", "report" };
                Gee.ArrayList<string>[] lists = { db.table_names (), db.view_names (), db.object_names ("form:"), db.object_names ("report:") };
                for (int k = 0; k < 4; k++) {
                    foreach (string n in lists[k]) {
                        if (!all_in (n, needles)) continue;
                        string id = "%s\t%s\t%s".printf (path, kinds[k], n);
                        descriptions[id] = "%s, %s".printf (Dialogs.kind_label (kinds[k]), dbname);
                        ids += id;
                        if (ids.length >= MAX_RESULTS) return ids;
                    }
                }
                foreach (string t in db.table_names ()) {
                    try {
                        var def = db.load_table (t);
                        string[] conds = {};
                        foreach (var f in def.fields) {
                            if (!f.field_type.is_text ()) continue;
                            string[] all = {};
                            foreach (string n in needles) all += "instr(casefold(%s), %s) > 0".printf (Sql.quote_ident (f.name), Sql.quote_string (n));
                            conds += "(" + string.joinv (" AND ", all) + ")";
                        }
                        if (conds.length == 0) continue;
                        var rs = db.query ("SELECT rowid, * FROM %s WHERE %s LIMIT 3".printf (Sql.quote_ident (t), string.joinv (" OR ", conds)));
                        foreach (var r in rs.rows) {
                            string title = "";
                            for (int i = 1; i < rs.columns.length && title == ""; i++) {
                                var f = def.find (rs.columns[i]);
                                if (f != null && f.field_type.is_text () && !r.get (i).is_null) title = r.get (i).to_string ();
                            }
                            string id = "%s\trecord\t%s\t%lld\t%s".printf (path, t, r.get (0).as_int (), title.replace ("\t", " ").replace ("\n", " "));
                            descriptions[id] = _("Record in %s, %s").printf (t, dbname);
                            ids += id;
                            if (ids.length >= MAX_RESULTS) return ids;
                        }
                    } catch (Error e) {
                    }
                }
                db.close ();
            }
            return ids;
        }

        public override async SearchResultMeta[] get_result_metas (string[] ids, Cancellable? cancellable) throws Error {
            SearchResultMeta[] metas = {};
            foreach (string id in ids) {
                string[] p = id.split ("\t");
                if (p.length < 3) continue;
                string name = p[1] == "record" && p.length >= 5 ? p[4] : p[2];
                if (name == "") name = _("Record %s").printf (p.length >= 4 ? p[3] : "");
                var meta = new SearchResultMeta (id, name);
                meta.description = descriptions[id] ?? Path.get_basename (p[0]);
                string icon = "x-office-database";
                switch (p[1]) {
                    case "form": icon = "x-office-addressbook"; break;
                    case "report": icon = "x-office-document"; break;
                    case "query": icon = "system-search"; break;
                    default: break;
                }
                meta.icon = new ThemedIcon (icon);
                metas += meta;
            }
            return metas;
        }

        public override async SearchActivationReply? activate_result (string id, string[] terms, uint32 timestamp) throws Error {
            string[] p = id.split ("\t");
            if (p.length < 3) return null;
            app.activate ();
            var win = app.get_active_window () as DatabaseWindow;
            if (win == null) return null;
            if (win.db == null || win.db.path != p[0]) {
                app.open_file (File.new_for_path (p[0]), win);
                win = app.get_active_window () as DatabaseWindow;
            }
            if (win == null || win.db == null) return null;
            if (p[1] == "record") {
                win.open_object ("table", p[2]);
                var page = win.find_page ("table", p[2]) as TablePage;
                if (page != null && page.src != null && p.length >= 4) {
                    int64 idx = page.src.index_of_rowid (int64.parse (p[3]));
                    if (idx >= 0) page.sheet.select_record (idx);
                }
            } else {
                win.open_object (p[1], p[2]);
            }
            win.present ();
            return null;
        }

        public override void launch_search (string[] terms, uint32 timestamp) {
            app.activate ();
        }
    }
}
