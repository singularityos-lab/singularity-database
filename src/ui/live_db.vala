namespace Singularity.Apps.Database {

    [DBus (name = "dev.sinty.Collab.Database1")]
    public class DatabaseCollabBus : Object {
        private unowned DatabaseApp app;

        public DatabaseCollabBus (DatabaseApp app) {
            this.app = app;
        }

        public void receive (string title, string payload, string from) throws Error {
            throw new IOError.NOT_SUPPORTED ("databases are shared in a session");
        }

        public void join (string session, string title, string snapshot, string role, string from) throws Error {
            var w = new DatabaseWindow (app);
            w.present ();
            DatabaseLive.join (w, session, title, snapshot, from);
        }
    }

    public class DatabaseLive : Object {
        private unowned DatabaseWindow win;
        public LiveSession session;
        private bool applying = false;
        private ulong data_id = 0;
        private ulong design_id = 0;
        private Singularity.Apps.Database.Database? watched = null;

        private DatabaseLive (DatabaseWindow win) {
            this.win = win;
            session = new LiveSession (Environment.get_real_name (), "database-live", "/database");
            session.message.connect (on_message);
            session.state_requested.connect (() => {
                var st = state ();
                if (st != null) session.publish_state (st);
            });
            session.peer_joined.connect ((p) => win.notify_live (_("%s joined").printf (p.name)));
            session.peer_left.connect ((p) => win.notify_live (_("%s left").printf (p.name)));
            session.ended.connect ((reason) => {
                win.notify_live (reason);
                stop (win);
            });
        }

        public static DatabaseLive? of (DatabaseWindow win) {
            return win.get_data<DatabaseLive> ("database-live");
        }

        public static bool supported (DatabaseWindow win) {
            return Singularity.Collab.Client.installed () && win.db != null && !win.db.is_sdb && win.db.path != ":memory:";
        }

        private Json.Object? state () {
            if (win.db == null) return null;
            try {
                var o = new Json.Object ();
                o.set_string_member ("db", Base64.encode (win.db.export_copy ().get_data ()));
                return o;
            } catch (Error e) {
                warning ("database: %s", e.message);
                return null;
            }
        }

        private void watch () {
            if (watched != null) {
                if (data_id != 0) watched.disconnect (data_id);
                if (design_id != 0) watched.disconnect (design_id);
            }
            watched = win.db;
            data_id = design_id = 0;
            if (watched == null) return;
            data_id = watched.data_recorded.connect ((stmts) => {
                if (applying) return;
                var o = new Json.Object ();
                o.set_string_member ("t", "sql");
                var arr = new Json.Array ();
                foreach (string st in stmts) arr.add_string_element (st);
                o.set_array_member ("stmts", arr);
                session.send (o);
            });
            design_id = watched.design_recorded.connect (() => {
                if (applying) return;
                var st = state ();
                if (st == null) return;
                st.set_string_member ("t", "db");
                session.send (st);
            });
        }

        private void on_message (Json.Object o) {
            string t = o.has_member ("t") ? o.get_string_member ("t") : "";
            if (win.db == null) return;
            if (t == "sql") {
                string[] stmts = {};
                foreach (var n in o.get_array_member ("stmts").get_elements ()) stmts += n.get_string ();
                applying = true;
                try {
                    win.db.apply_remote_sql (stmts);
                } catch (Error e) {
                    warning ("database: remote change skipped: %s", e.message);
                }
                applying = false;
            } else if (t == "db") {
                replace (o.get_string_member ("db"));
            }
        }

        private void replace (string encoded) {
            string path = win.db.path;
            applying = true;
            try {
                win.db.close ();
                FileUtils.set_data (path, Base64.decode (encoded));
                win.load (Singularity.Apps.Database.Database.open (path));
                watch ();
            } catch (Error e) {
                warning ("database: %s", e.message);
            }
            applying = false;
        }

        public static void share (DatabaseWindow win, Gtk.Widget anchor) {
            if (!supported (win)) return;
            var live = of (win);
            Singularity.Collab.Client.pick (anchor, true, (person) => {
                bool fresh = live == null;
                if (fresh) {
                    live = new DatabaseLive (win);
                    win.set_data<DatabaseLive> ("database-live", live);
                }
                var st = live.state ();
                if (st == null) return;
                live.session.host_collab.begin (st, person, "Database", win.db.display_name (), (o, res) => {
                    try {
                        live.session.host_collab.end (res);
                        if (fresh) live.watch ();
                        win.notify_live (_("Invitation sent to %s").printf (person.name));
                    } catch (Error e) {
                        win.notify_live (e.message);
                        if (fresh) stop (win);
                    }
                });
            });
        }

        public static void join (DatabaseWindow win, string session_id, string title, string snapshot, string from) {
            var live = new DatabaseLive (win);
            win.set_data<DatabaseLive> ("database-live", live);
            live.session.welcome.connect ((state) => {
                string dir = Path.build_filename (Environment.get_user_data_dir (), "singularity", "database", "shared");
                DirUtils.create_with_parents (dir, 0700);
                string name = (title != "" ? title : _("Shared Database")).replace ("/", "-");
                string path = Path.build_filename (dir, name.has_suffix (".db") ? name : name + ".db");
                try {
                    FileUtils.set_data (path, Base64.decode (state.get_string_member ("db")));
                    win.load (Singularity.Apps.Database.Database.open (path));
                    live.watch ();
                    win.notify_live (_("You are working with %s").printf (from));
                } catch (Error e) {
                    win.notify_live (e.message);
                    stop (win);
                }
            });
            live.session.join_collab (session_id, snapshot);
        }

        public static void stop (DatabaseWindow win) {
            var live = of (win);
            if (live == null) return;
            win.set_data<DatabaseLive> ("database-live", null);
            if (live.watched != null) {
                if (live.data_id != 0) live.watched.disconnect (live.data_id);
                if (live.design_id != 0) live.watched.disconnect (live.design_id);
            }
            live.session.leave ();
        }
    }
}
