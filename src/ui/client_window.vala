using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Database {

    public abstract class ClientTab : Box {
        public weak ClientWindow win;
        public string key { get; protected set; default = ""; }
        public string tab_title { get; protected set; default = ""; }
        public string tab_icon { get; protected set; default = "db-table-symbolic"; }

        protected ClientTab (ClientWindow win, string key) {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            this.win = win;
            this.key = key;
        }

        public virtual bool has_changes () {
            return false;
        }

        public virtual void reload () {
        }

        public virtual void closed () {
        }

        public virtual void focus_content () {
        }

        public static Box toolbar () {
            var bar = new Box (Orientation.HORIZONTAL, 4);
            bar.add_css_class ("db-toolbar");
            return bar;
        }

        public static Button tool (Box bar, string icon, string tooltip, owned ClientWindow.Callback cb) {
            var b = new Button.from_icon_name (icon);
            b.add_css_class ("flat");
            b.add_css_class ("db-tool");
            b.tooltip_text = tooltip;
            b.valign = Align.CENTER;
            b.clicked.connect (() => cb ());
            bar.append (b);
            return b;
        }

        public static Button tool_text (Box bar, string label, owned ClientWindow.Callback cb, bool suggested = false) {
            var b = new Button.with_label (label);
            b.add_css_class ("db-tool-text");
            if (suggested) b.add_css_class ("suggested-action");
            else b.add_css_class ("flat");
            b.valign = Align.CENTER;
            b.clicked.connect (() => cb ());
            bar.append (b);
            return b;
        }

        public static void separator (Box bar) {
            var s = new Separator (Orientation.VERTICAL);
            s.margin_start = s.margin_end = 4;
            s.margin_top = s.margin_bottom = 6;
            bar.append (s);
        }

        public static Widget spacer (Box bar) {
            var s = new Box (Orientation.HORIZONTAL, 0);
            s.hexpand = true;
            bar.append (s);
            return s;
        }
    }

    public class ClientWindow : Singularity.Widgets.Window {
        public delegate void Callback ();

        public DatabaseApp app;
        public ClientSession session;
        public ConnectionConfig config;
        public Gee.ArrayList<CatalogObject> objects = new Gee.ArrayList<CatalogObject> ();
        public Gee.HashMap<string, Gee.ArrayList<string>> column_cache = new Gee.HashMap<string, Gee.ArrayList<string>> ();
        public string schema { get; private set; default = ""; }
        public signal void catalog_changed ();

        private Stack stack;
        private StatusPage connecting_page;
        private StatusPage error_page;
        private Box main_box;
        private Box tab_strip;
        private Stack tab_stack;
        private Gee.ArrayList<ClientTab> tabs = new Gee.ArrayList<ClientTab> ();
        private Gee.HashMap<ClientTab, Button> tab_buttons = new Gee.HashMap<ClientTab, Button> ();
        private ClientTab? current_tab;
        private AppSidebar sidebar;
        private Label conn_title;
        private Label conn_detail;
        private Image conn_icon;
        private DropDown db_drop;
        private DropDown schema_drop;
        private Box db_box;
        private Box schema_box;
        private Box object_list;
        private string filter = "";
        private Gee.HashSet<ObjectKind> collapsed = new Gee.HashSet<ObjectKind> ();
        private string[] db_names = {};
        private string[] schema_names = {};
        private bool syncing_drops;
        private Cancellable? connect_cancel;
        private Cursor? active_cursor;
        private Callback? active_cursor_closed;
        private Gee.ArrayList<Widget> server_bubbles = new Gee.ArrayList<Widget> ();
        private Gee.HashMap<string, SidebarRow> rows = new Gee.HashMap<string, SidebarRow> ();
        private string? pending_password;
        private string? pending_ssh_password;

        public ClientWindow (DatabaseApp app, ConnectionConfig config) {
            Object (application: app);
            this.app = app;
            this.config = config;
            session = new ClientSession (config);
            set_default_size (1280, 820);
            set_title (config.name);
            collapsed.add (ObjectKind.INDEX);
            collapsed.add (ObjectKind.TRIGGER);
            collapsed.add (ObjectKind.SEQUENCE);

            stack = new Stack ();
            stack.transition_type = StackTransitionType.CROSSFADE;
            connecting_page = new StatusPage ();
            connecting_page.icon_name = "db-connection-symbolic";
            connecting_page.title = _("Connecting");
            connecting_page.description = config.summary ();
            var cbox = new Box (Orientation.VERTICAL, 12);
            cbox.halign = Align.CENTER;
            var spin = new Spinner ();
            spin.spinning = true;
            spin.width_request = spin.height_request = 24;
            cbox.append (spin);
            var cancel = new Button.with_label (_("Cancel"));
            cancel.add_css_class ("pill");
            cancel.clicked.connect (() => {
                if (connect_cancel != null) connect_cancel.cancel ();
            });
            cbox.append (cancel);
            connecting_page.child = cbox;
            stack.add_named (connecting_page, "connecting");

            error_page = new StatusPage ();
            error_page.icon_name = "dialog-error-symbolic";
            error_page.title = _("Could Not Connect");
            var ebox = new Box (Orientation.HORIZONTAL, 8);
            ebox.halign = Align.CENTER;
            var edit = new Button.with_label (_("Edit Connection"));
            edit.add_css_class ("pill");
            edit.clicked.connect (() => edit_connection ());
            ebox.append (edit);
            var retry = new Button.with_label (_("Try Again"));
            retry.add_css_class ("pill");
            retry.add_css_class ("suggested-action");
            retry.clicked.connect (() => start (pending_password, pending_ssh_password));
            ebox.append (retry);
            error_page.child = ebox;
            stack.add_named (error_page, "error");

            main_box = new Box (Orientation.VERTICAL, 0);
            tab_strip = new Box (Orientation.HORIZONTAL, 4);
            tab_strip.add_css_class ("db-tab-strip");
            var strip_scroll = new ScrolledWindow ();
            strip_scroll.vscrollbar_policy = PolicyType.NEVER;
            strip_scroll.hscrollbar_policy = PolicyType.AUTOMATIC;
            strip_scroll.child = tab_strip;
            main_box.append (strip_scroll);
            tab_stack = new Stack ();
            tab_stack.vexpand = true;
            tab_stack.hexpand = true;
            main_box.append (tab_stack);
            stack.add_named (main_box, "main");

            sidebar = new AppSidebar (268);
            sidebar.box.append (build_sidebar_head ());
            object_list = new Box (Orientation.VERTICAL, 1);
            sidebar.box.append (object_list);
            var add = sidebar.add_bubble_icon ("list-add-symbolic", _("New"), () => { });
            add.clicked.connect (() => show_new_menu (add));
            sidebar.add_bubble_search (_("Filter Objects"), (t) => {
                filter = t.strip ().casefold ();
                rebuild_objects ();
            });
            set_sidebar (sidebar);
            set_sidebar_visible (false);
            build_bubbles ();
            set_content (stack);
            install_actions ();
            close_request.connect (on_close_request);
        }

        private Widget build_sidebar_head () {
            var box = new Box (Orientation.VERTICAL, 8);
            box.add_css_class ("db-conn-head");
            var top = new Box (Orientation.HORIZONTAL, 10);
            conn_icon = new Image.from_icon_name ("db-server-symbolic");
            conn_icon.pixel_size = 20;
            conn_icon.add_css_class ("db-conn-icon");
            conn_icon.valign = Align.CENTER;
            top.append (conn_icon);
            var texts = new Box (Orientation.VERTICAL, 1);
            texts.hexpand = true;
            conn_title = new Label (config.name);
            conn_title.add_css_class ("heading");
            conn_title.xalign = 0;
            conn_title.ellipsize = Pango.EllipsizeMode.END;
            texts.append (conn_title);
            conn_detail = new Label (config.summary ());
            conn_detail.add_css_class ("caption");
            conn_detail.add_css_class ("dim-label");
            conn_detail.xalign = 0;
            conn_detail.wrap = true;
            conn_detail.lines = 2;
            conn_detail.ellipsize = Pango.EllipsizeMode.END;
            texts.append (conn_detail);
            top.append (texts);
            box.append (top);
            db_box = new Box (Orientation.HORIZONTAL, 6);
            var dl = new Image.from_icon_name ("db-server-symbolic");
            dl.tooltip_text = _("Database");
            db_box.append (dl);
            db_drop = new DropDown.from_strings ({ "" });
            db_drop.hexpand = true;
            db_drop.tooltip_text = _("Database");
            db_drop.notify["selected"].connect (() => {
                if (syncing_drops) return;
                if (db_drop.selected < db_names.length) switch_database.begin (db_names[db_drop.selected]);
            });
            db_box.append (db_drop);
            box.append (db_box);
            schema_box = new Box (Orientation.HORIZONTAL, 6);
            var sl = new Image.from_icon_name ("db-schema-symbolic");
            sl.tooltip_text = _("Schema");
            schema_box.append (sl);
            schema_drop = new DropDown.from_strings ({ "" });
            schema_drop.hexpand = true;
            schema_drop.tooltip_text = _("Schema");
            schema_drop.notify["selected"].connect (() => {
                if (syncing_drops) return;
                if (schema_drop.selected < schema_names.length) {
                    schema = schema_names[schema_drop.selected];
                    remember_schema (schema);
                    load_catalog.begin ();
                }
            });
            schema_box.append (schema_drop);
            box.append (schema_box);
            return box;
        }

        private void build_bubbles () {
            add_bubble_icon ("go-previous-symbolic", _("Disconnect"), () => close ());
            server_bubbles.add (add_bubble_icon ("db-sql-symbolic", _("New SQL Editor (Ctrl+T)"), () => open_sql (null)));
            server_bubbles.add (add_bubble_icon ("view-refresh-symbolic", _("Refresh Objects (F5)"), () => load_catalog.begin ()));
            var users = add_bubble_icon ("db-users-symbolic", _("Users and Privileges"), () => open_users ());
            users.set_data<bool> ("server-only", true);
            server_bubbles.add (users);
            var act = add_bubble_icon ("db-activity-symbolic", _("Server Activity"), () => open_activity ());
            act.set_data<bool> ("server-only", true);
            server_bubbles.add (act);
            var more = add_bubble_icon ("view-more-symbolic", _("More"), () => { });
            more.clicked.connect (() => show_more_menu (more));
            server_bubbles.add (more);
            foreach (var b in server_bubbles) b.visible = false;
        }

        private void install_actions () {
            var a = new SimpleAction ("new-sql", null);
            a.activate.connect (() => {
                if (session.engine != null) open_sql (null);
            });
            add_action (a);
            var r = new SimpleAction ("refresh-objects", null);
            r.activate.connect (() => {
                if (session.engine != null) load_catalog.begin ();
            });
            add_action (r);
            var c = new SimpleAction ("close-tab", null);
            c.activate.connect (() => {
                if (current_tab != null) request_close_tab (current_tab);
            });
            add_action (c);
            var o = new SimpleAction ("open-tab", VariantType.STRING);
            o.activate.connect ((p) => open_by_key (p.get_string ()));
            add_action (o);
            app.set_accels_for_action ("win.new-sql", { "<Control>t" });
            app.set_accels_for_action ("win.refresh-objects", { "F5" });
            app.set_accels_for_action ("win.close-tab", { "<Control>w" });
        }

        private string? remembered_schema () {
            var root = ClientStore.load ("state.json");
            if (root == null || root.get_node_type () != Json.NodeType.OBJECT || config.id == "") return null;
            var o = root.get_object ();
            string key = "%s:%s".printf (config.id, session.engine != null ? engine.current_database : "");
            return o.has_member (key) ? o.get_string_member (key) : null;
        }

        private void remember_schema (string s) {
            if (config.id == "" || session.engine == null) return;
            var root = ClientStore.load ("state.json");
            if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
                root = new Json.Node (Json.NodeType.OBJECT);
                root.set_object (new Json.Object ());
            }
            root.get_object ().set_string_member ("%s:%s".printf (config.id, engine.current_database), s);
            try {
                ClientStore.save ("state.json", root);
            } catch (Error e) {
            }
        }

        public void toast (string text) {
            add_toast (new Toast (text));
        }

        public void show_error (string title, string message) {
            var dlg = new ConfirmDialog (app, title, "dialog-error", message, _("OK"), ConfirmDialog.ActionStyle.SUGGESTED);
            dlg.transient_for = this;
            dlg.present ();
        }

        public void confirm (string title, string message, string action, owned Callback cb, bool destructive = true) {
            var dlg = new ConfirmDialog (app, title, destructive ? "dialog-warning" : null, message, action, destructive ? ConfirmDialog.ActionStyle.DESTRUCTIVE : ConfirmDialog.ActionStyle.SUGGESTED);
            dlg.transient_for = this;
            dlg.response.connect ((resp) => {
                if (resp == ConfirmDialog.Response.PRIMARY) cb ();
            });
            dlg.present ();
        }

        public Engine engine {
            get { return session.engine; }
        }

        public bool is_sqlite {
            get { return config.kind == EngineKind.SQLITE; }
        }

        public async Engine ready () throws Error {
            if (session.engine == null) throw new RemoteError.CONNECT (_("Not connected."));
            if (active_cursor != null) {
                var c = active_cursor;
                active_cursor = null;
                try {
                    yield c.close_async ();
                } catch (Error e) {
                }
                if (active_cursor_closed != null) active_cursor_closed ();
                active_cursor_closed = null;
            }
            return session.engine;
        }

        public void hold_cursor (Cursor c, owned Callback on_closed) {
            active_cursor = c;
            active_cursor_closed = (owned) on_closed;
        }

        public bool cursor_active (Cursor c) {
            return active_cursor == c;
        }

        public void release_cursor (Cursor c) {
            if (active_cursor == c) {
                active_cursor = null;
                active_cursor_closed = null;
            }
        }

        public void start (string? password, string? ssh_password) {
            pending_password = password;
            pending_ssh_password = ssh_password;
            stack.visible_child_name = "connecting";
            connecting_page.description = config.summary ();
            set_sidebar_visible (false);
            connect_cancel = new Cancellable ();
            do_connect.begin (password, ssh_password);
        }

        private async void do_connect (string? password, string? ssh_password) {
            string? pw = password;
            string? spw = ssh_password;
            if (!is_sqlite && pw == null && config.id != "") pw = yield ConnectionSecrets.lookup (config.id, "db");
            if (!is_sqlite && spw == null && config.ssh_enabled && config.ssh_use_password && config.id != "") spw = yield ConnectionSecrets.lookup (config.id, "ssh");
            try {
                yield session.connect (pw, spw, connect_cancel);
            } catch (Error e) {
                if (Engines.is_cancelled (e)) {
                    close ();
                    return;
                }
                if (e is RemoteError.AUTH && (pw == null || pw == "")) {
                    ask_password (null);
                    return;
                }
                if (e is RemoteError.AUTH) {
                    ask_password (e.message);
                    return;
                }
                error_page.description = e.message;
                stack.visible_child_name = "error";
                return;
            }
            pending_password = pw;
            pending_ssh_password = spw;
            if (config.read_only) {
                try {
                    if (config.kind == EngineKind.POSTGRESQL) yield engine.execute ("SET SESSION CHARACTERISTICS AS TRANSACTION READ ONLY");
                    else if (config.kind == EngineKind.MYSQL) yield engine.execute ("SET SESSION TRANSACTION READ ONLY");
                } catch (Error e) {
                    warning ("read only: %s", e.message);
                }
            }
            on_connected ();
        }

        private void ask_password (string? problem) {
            var dlg = new AppDialog (app, true);
            dlg.set_title (_("Password Required"));
            dlg.transient_for = this;
            dlg.set_default_size (420, -1);
            var box = new Box (Orientation.VERTICAL, 12);
            box.margin_start = box.margin_end = 18;
            box.margin_top = 6;
            box.margin_bottom = 12;
            string who = config.user;
            if (who == "") who = config.summary ();
            string note = _("Enter the password for %s.").printf (who);
            if (problem != null) note = problem;
            var g = new PreferencesGroup (config.name, note);
            var pw = new PasswordRow (_("Password"));
            g.add_row (pw);
            var save = new SwitchRow (_("Remember Password"), _("Kept in the system keyring"), config.id != "");
            save.visible = config.id != "";
            g.add_row (save);
            box.append (g);
            dlg.content_box.append (box);
            var bar = new Box (Orientation.HORIZONTAL, 8);
            bar.margin_start = bar.margin_end = 18;
            bar.margin_bottom = 16;
            bar.halign = Align.END;
            var cancel = new Button.with_label (_("Cancel"));
            cancel.clicked.connect (() => {
                dlg.close ();
                error_page.description = problem ?? _("A password is needed to connect.");
                stack.visible_child_name = "error";
            });
            dlg.set_cancel_button (cancel);
            var ok = new Button.with_label (_("Connect"));
            ok.add_css_class ("suggested-action");
            ok.clicked.connect (() => {
                string p = pw.text;
                if (save.active && config.id != "") {
                    var c = config.copy ();
                    ConnectionSecrets.store.begin (c, "db", p, (o, res) => {
                        try {
                            ConnectionSecrets.store.end (res);
                        } catch (Error e) {
                            toast (ConnectionSecrets.unavailable_message (e));
                        }
                    });
                }
                dlg.close ();
                start (p, pending_ssh_password);
            });
            pw.entry_activated.connect (() => ok.activate ());
            bar.append (cancel);
            bar.append (ok);
            dlg.content_box.append (bar);
            dlg.default_widget = ok;
            dlg.open_dialog ();
            pw.grab_focus ();
        }

        private void on_connected () {
            stack.visible_child_name = "main";
            set_sidebar_visible (true);
            foreach (var b in server_bubbles) b.visible = !(is_sqlite && b.get_data<bool> ("server-only"));
            string tls = "";
            var pg = engine as PgEngine;
            if (pg != null && pg.tls_active) tls = _("encrypted");
            var my = engine as MysqlEngine;
            if (my != null && my.tls_active) tls = _("encrypted");
            string ver = engine.server_version;
            int paren = ver.index_of (" (");
            if (paren > 0) ver = ver.substring (0, paren);
            int maria = ver.index_of ("-MariaDB");
            if (maria > 0) ver = ver.substring (0, maria) + " MariaDB";
            string[] bits = { ver };
            if (tls != "") bits += tls;
            if (config.ssh_enabled) bits += _("through SSH");
            if (config.read_only) bits += _("read only");
            conn_detail.label = string.joinv (", ", bits);
            conn_detail.tooltip_text = config.summary ();
            conn_icon.icon_name = is_sqlite ? "x-office-database-symbolic" : "db-server-symbolic";
            set_title (config.name);
            load_databases.begin ();
            open_overview ();
        }

        private async void load_databases () {
            try {
                var e = yield ready ();
                var dbs = yield e.list_databases ();
                db_names = dbs.to_array ();
                string cur = e.current_database;
                var schemas = yield e.list_schemas ();
                schema_names = schemas.to_array ();
                syncing_drops = true;
                string[] dsafe = {};
                foreach (string d in db_names) dsafe += d;
                db_drop.model = new StringList (dsafe);
                for (int i = 0; i < db_names.length; i++) if (db_names[i] == cur) db_drop.selected = i;
                db_box.visible = !is_sqlite && db_names.length > 0;
                string want = config.kind == EngineKind.POSTGRESQL ? "public" : (config.kind == EngineKind.MYSQL ? cur : "main");
                string? remembered = remembered_schema ();
                if (config.kind == EngineKind.POSTGRESQL && remembered != null && remembered in schema_names) want = remembered;
                if (config.kind == EngineKind.MYSQL) schema_names = { cur };
                string[] ssafe = {};
                foreach (string s in schema_names) ssafe += s;
                schema_drop.model = new StringList (ssafe);
                int sel = 0;
                for (int i = 0; i < schema_names.length; i++) if (schema_names[i] == want) sel = i;
                if (schema_names.length > 0) schema_drop.selected = sel;
                schema = schema_names.length > 0 ? schema_names[sel] : "";
                schema_box.visible = config.kind == EngineKind.POSTGRESQL || (is_sqlite && schema_names.length > 1);
                syncing_drops = false;
            } catch (Error e) {
                syncing_drops = false;
                toast (_("Could not list databases: %s").printf (e.message));
            }
            yield load_catalog ();
        }

        private async void switch_database (string name) {
            if (session.engine == null || name == engine.current_database) return;
            bool dirty = false;
            foreach (var t in tabs) if (t.has_changes ()) dirty = true;
            if (dirty) {
                toast (_("Apply or discard your pending changes before switching databases."));
                syncing_drops = true;
                for (int i = 0; i < db_names.length; i++) if (db_names[i] == engine.current_database) db_drop.selected = i;
                syncing_drops = false;
                return;
            }
            try {
                var e = yield ready ();
                yield e.use_database (name);
                if (config.read_only && config.kind == EngineKind.POSTGRESQL) yield e.execute ("SET SESSION CHARACTERISTICS AS TRANSACTION READ ONLY");
            } catch (Error e) {
                show_error (_("Could Not Switch Database"), e.message);
                return;
            }
            foreach (var t in tabs.to_array ()) {
                if (!(t is OverviewTab) && !(t is ActivityTab) && !(t is UsersTab) && !(t is SqlTab)) close_tab (t);
            }
            column_cache.clear ();
            yield load_databases ();
            foreach (var t in tabs) t.reload ();
        }

        public async void load_catalog () {
            if (session.engine == null) return;
            try {
                var e = yield ready ();
                var list = yield e.list_objects (schema);
                objects = list;
            } catch (Error e) {
                toast (_("Could not read the schema: %s").printf (e.message));
                objects = new Gee.ArrayList<CatalogObject> ();
            }
            rebuild_objects ();
            catalog_changed ();
            prefetch_columns.begin ();
        }

        private async void prefetch_columns () {
            int n = 0;
            foreach (var o in objects.to_array ()) {
                if (o.kind != ObjectKind.TABLE && o.kind != ObjectKind.VIEW) continue;
                string k = o.schema + "." + o.name;
                if (column_cache.has_key (k)) continue;
                if (++n > 150) break;
                if (active_cursor != null) return;
                try {
                    if (o.kind == ObjectKind.TABLE) {
                        var info = yield engine.describe_table (o.schema, o.name);
                        var cols = new Gee.ArrayList<string> ();
                        foreach (var c in info.columns) cols.add (c.name);
                        column_cache[k] = cols;
                    }
                } catch (Error e) {
                }
            }
            catalog_changed ();
        }

        private static string kind_icon (ObjectKind k) {
            switch (k) {
                case ObjectKind.TABLE: return "db-table-symbolic";
                case ObjectKind.VIEW: return "db-view-symbolic";
                case ObjectKind.MATERIALIZED_VIEW: return "db-view-symbolic";
                case ObjectKind.INDEX: return "db-index-symbolic";
                case ObjectKind.FUNCTION: return "db-function-symbolic";
                case ObjectKind.PROCEDURE: return "db-function-symbolic";
                case ObjectKind.TRIGGER: return "db-trigger-symbolic";
                case ObjectKind.SEQUENCE: return "db-sequence-symbolic";
                case ObjectKind.EVENT: return "db-history-symbolic";
                default: return "db-schema-symbolic";
            }
        }

        public static string object_key (CatalogObject o) {
            return "obj:%d:%s:%s".printf ((int) o.kind, o.schema, o.name);
        }

        public void rebuild_objects () {
            Widget? child;
            while ((child = object_list.get_first_child ()) != null) object_list.remove (child);
            rows.clear ();
            ObjectKind[] order = { ObjectKind.TABLE, ObjectKind.VIEW, ObjectKind.MATERIALIZED_VIEW, ObjectKind.FUNCTION, ObjectKind.PROCEDURE, ObjectKind.TRIGGER, ObjectKind.SEQUENCE, ObjectKind.EVENT, ObjectKind.INDEX };
            bool any = false;
            foreach (var k in order) {
                var items = new Gee.ArrayList<CatalogObject> ();
                foreach (var o in objects) {
                    if (o.kind != k) continue;
                    if (filter != "" && !o.name.casefold ().contains (filter) && !o.parent.casefold ().contains (filter)) continue;
                    items.add (o);
                }
                if (items.size == 0) continue;
                any = true;
                bool is_collapsed = collapsed.contains (k) && filter == "";
                var head = new Button ();
                head.add_css_class ("flat");
                head.add_css_class ("db-section-toggle");
                var hb = new Box (Orientation.HORIZONTAL, 6);
                var arrow = new Image.from_icon_name (is_collapsed ? "pan-end-symbolic" : "pan-down-symbolic");
                arrow.pixel_size = 12;
                hb.append (arrow);
                var hl = new Label (k.plural ());
                hl.xalign = 0;
                hl.hexpand = true;
                hb.append (hl);
                var hc = new Label (items.size.to_string ());
                hc.add_css_class ("db-sidebar-badge");
                hb.append (hc);
                head.child = hb;
                var kk = k;
                head.clicked.connect (() => {
                    if (collapsed.contains (kk)) collapsed.remove (kk);
                    else collapsed.add (kk);
                    rebuild_objects ();
                });
                object_list.append (head);
                if (is_collapsed) continue;
                foreach (var o in items) {
                    string title = o.name;
                    var row = new SidebarRow (kind_icon (k), title);
                    string badge = "";
                    if (o.row_estimate >= 0 && (k == ObjectKind.TABLE || k == ObjectKind.MATERIALIZED_VIEW)) badge = DatabaseWindow.compact_count (o.row_estimate);
                    else if (o.parent != "" && k != ObjectKind.TABLE) badge = o.parent;
                    if (badge != "") {
                        var inner = row.get_child () as Box;
                        if (inner != null) {
                            var b = new Label (badge);
                            b.add_css_class ("db-sidebar-badge");
                            b.ellipsize = Pango.EllipsizeMode.END;
                            b.max_width_chars = 12;
                            inner.append (b);
                        }
                    }
                    string tip = o.comment != "" ? "%s\n%s".printf (o.name, o.comment) : o.name;
                    if (o.detail != "" && o.detail != o.parent) tip += "\n" + o.detail;
                    row.tooltip_text = tip;
                    var obj = o;
                    row.clicked.connect (() => open_object (obj));
                    var click = new GestureClick ();
                    click.button = 3;
                    click.pressed.connect ((n, x, y) => object_menu (obj, row, x, y));
                    row.add_controller (click);
                    string key = object_key (o);
                    rows[key] = row;
                    if (current_tab != null && current_tab.key == key) row.set_active (true);
                    object_list.append (row);
                }
            }
            if (!any) {
                var none = new Label (filter != "" ? _("No objects match.") : _("This schema is empty."));
                none.add_css_class ("dim-label");
                none.margin_top = 16;
                object_list.append (none);
            }
        }

        private void object_menu (CatalogObject o, Widget anchor, double x, double y) {
            var menu = new ContextMenu (anchor);
            var r = Gdk.Rectangle ();
            r.x = (int) x;
            r.y = (int) y;
            r.width = r.height = 1;
            menu.pointing_to = r;
            bool data = o.kind == ObjectKind.TABLE || o.kind == ObjectKind.VIEW || o.kind == ObjectKind.MATERIALIZED_VIEW;
            if (data) {
                menu.add_item (_("Open Data"), "db-table-symbolic", () => open_object (o, "data"));
                menu.add_item (_("Structure"), "db-fields-symbolic", () => open_object (o, "structure"));
            }
            menu.add_item (_("Definition"), "db-sql-symbolic", () => open_object (o, "ddl"));
            menu.add_separator ();
            if (data) {
                menu.add_item (_("New SELECT"), "db-sql-symbolic", () => open_sql ("SELECT *\nFROM %s%s;".printf (engine.qualified (o.schema, o.name), engine.limit_clause (100, 0))));
                menu.add_item (_("Export Data…"), "document-send-symbolic", () => ClientDialogs.export_table (this, o));
            }
            if (o.kind == ObjectKind.TABLE && !config.read_only) menu.add_item (_("Import Data…"), "document-open-symbolic", () => ClientDialogs.import_into (this, o));
            menu.add_item (_("Copy Name"), "edit-copy-symbolic", () => get_clipboard ().set_text (engine.qualified (o.schema, o.name)));
            if (!config.read_only && (o.kind == ObjectKind.TABLE || o.kind == ObjectKind.VIEW || o.kind == ObjectKind.MATERIALIZED_VIEW || o.kind == ObjectKind.INDEX || o.kind == ObjectKind.SEQUENCE)) {
                menu.add_separator ();
                if (o.kind == ObjectKind.TABLE) menu.add_item (_("Empty Table…"), "edit-clear-symbolic", () => drop_object (o, true), "destructive");
                menu.add_item (_("Drop…"), "user-trash-symbolic", () => drop_object (o, false), "destructive");
            }
            DatabaseWindow.popup_menu (menu);
        }

        private string drop_sql (CatalogObject o, bool truncate) {
            string q = engine.qualified (o.schema, o.name);
            if (truncate) return is_sqlite ? "DELETE FROM %s".printf (q) : "TRUNCATE TABLE %s".printf (q);
            switch (o.kind) {
                case ObjectKind.VIEW: return "DROP VIEW %s".printf (q);
                case ObjectKind.MATERIALIZED_VIEW: return "DROP MATERIALIZED VIEW %s".printf (q);
                case ObjectKind.SEQUENCE: return "DROP SEQUENCE %s".printf (q);
                case ObjectKind.INDEX:
                    if (config.kind == EngineKind.MYSQL) return "DROP INDEX %s ON %s".printf (engine.quote_ident (o.name), engine.qualified (o.schema, o.parent));
                    return "DROP INDEX %s".printf (q);
                default: return "DROP TABLE %s".printf (q);
            }
        }

        private void drop_object (CatalogObject o, bool truncate) {
            string sql = drop_sql (o, truncate);
            string title = truncate ? _("Empty %s?").printf (o.name) : _("Drop %s?").printf (o.name);
            string msg = _("This runs:\n%s\n\nIt cannot be undone.").printf (sql);
            confirm (title, msg, truncate ? _("Empty") : _("Drop"), () => run_ddl.begin (sql, o, !truncate));
        }

        private async void run_ddl (string sql, CatalogObject o, bool dropped) {
            try {
                var e = yield ready ();
                yield e.execute (sql);
            } catch (Error e) {
                show_error (_("Could Not Change %s").printf (o.name), e.message);
                return;
            }
            if (dropped) {
                var t = find_tab (object_key (o));
                if (t != null) close_tab (t);
            } else {
                var t = find_tab (object_key (o));
                if (t != null) t.reload ();
            }
            yield load_catalog ();
        }

        private void show_new_menu (Widget anchor) {
            var menu = new ContextMenu (anchor);
            menu.add_item (_("SQL Editor"), "db-sql-symbolic", () => open_sql (null));
            if (!config.read_only) {
                menu.add_item (_("Table…"), "db-table-symbolic", () => ClientDialogs.new_table (this));
                menu.add_separator ();
                menu.add_item (_("Run SQL File…"), "document-open-symbolic", () => ClientDialogs.run_file (this));
            }
            DatabaseWindow.popup_menu (menu);
        }

        private void show_more_menu (Widget anchor) {
            var menu = new ContextMenu (anchor);
            menu.add_item (_("Export Schema as SQL…"), "document-send-symbolic", () => ClientDialogs.dump_schema (this));
            if (!config.read_only) menu.add_item (_("Run SQL File…"), "document-open-symbolic", () => ClientDialogs.run_file (this));
            menu.add_separator ();
            menu.add_item (_("Edit Connection…"), "document-edit-symbolic", () => edit_connection ());
            menu.add_item (_("Reconnect"), "view-refresh-symbolic", () => reconnect.begin ());
            DatabaseWindow.popup_menu (menu);
        }

        private async void reconnect () {
            foreach (var t in tabs) {
                if (t.has_changes ()) {
                    toast (_("Apply or discard your pending changes first."));
                    return;
                }
            }
            active_cursor = null;
            yield session.disconnect ();
            session = new ClientSession (config);
            foreach (var t in tabs.to_array ()) close_tab (t);
            start (pending_password, pending_ssh_password);
        }

        private void edit_connection () {
            var existing = ConnectionStore.get_default ().find (config.id) ?? config;
            ConnectionDialog.open (this, app, existing, (c, pw, spw) => {
                config = c;
                conn_title.label = c.name;
                reconnect_with.begin (pw, spw);
            });
        }

        private async void reconnect_with (string? pw, string? spw) {
            active_cursor = null;
            yield session.disconnect ();
            session = new ClientSession (config);
            foreach (var t in tabs.to_array ()) close_tab (t);
            start (pw, spw);
        }

        public ClientTab? find_tab (string key) {
            foreach (var t in tabs) if (t.key == key) return t;
            return null;
        }

        private void open_by_key (string key) {
            if (key == "overview") {
                open_overview ();
                return;
            }
            if (key == "users") {
                open_users ();
                return;
            }
            if (key == "activity") {
                open_activity ();
                return;
            }
            if (key == "sql") {
                open_sql (null);
                return;
            }
            foreach (var o in objects) {
                if (object_key (o) == key || o.name == key) {
                    open_object (o);
                    return;
                }
            }
            string[] parts = key.split ("@", 2);
            foreach (var o in objects) {
                if (o.name == parts[0]) {
                    open_object (o, parts.length > 1 ? parts[1] : null);
                    return;
                }
            }
        }

        public void add_tab (ClientTab tab) {
            tabs.add (tab);
            tab_stack.add_child (tab);
            var btn = new Button ();
            btn.add_css_class ("flat");
            btn.add_css_class ("db-tab");
            var box = new Box (Orientation.HORIZONTAL, 6);
            var icon = new Image.from_icon_name (tab.tab_icon);
            icon.pixel_size = 14;
            box.append (icon);
            var label = new Label (tab.tab_title);
            label.ellipsize = Pango.EllipsizeMode.END;
            label.max_width_chars = 22;
            box.append (label);
            tab.notify["tab-title"].connect (() => label.label = tab.tab_title);
            var close_btn = new Button.from_icon_name ("window-close-symbolic");
            close_btn.add_css_class ("flat");
            close_btn.add_css_class ("db-tab-close");
            close_btn.tooltip_text = _("Close Tab (Ctrl+W)");
            close_btn.clicked.connect (() => request_close_tab (tab));
            box.append (close_btn);
            btn.child = box;
            btn.clicked.connect (() => select_tab (tab));
            var middle = new GestureClick ();
            middle.button = 2;
            middle.pressed.connect (() => request_close_tab (tab));
            btn.add_controller (middle);
            tab_buttons[tab] = btn;
            tab_strip.append (btn);
            select_tab (tab);
        }

        public void select_tab (ClientTab tab) {
            current_tab = tab;
            tab_stack.visible_child = tab;
            foreach (var e in tab_buttons.entries) {
                if (e.key == tab) e.value.add_css_class ("active");
                else e.value.remove_css_class ("active");
            }
            foreach (var e in rows.entries) e.value.set_active (e.key == tab.key);
            set_title ("%s: %s".printf (config.name, tab.tab_title));
            tab.focus_content ();
        }

        public void request_close_tab (ClientTab tab) {
            if (tab.has_changes ()) {
                confirm (_("Discard Changes?"), _("%s has changes that were not applied to the database.").printf (tab.tab_title), _("Discard"), () => close_tab (tab));
                return;
            }
            close_tab (tab);
        }

        public void close_tab (ClientTab tab) {
            int idx = tabs.index_of (tab);
            if (idx < 0) return;
            tab.closed ();
            tabs.remove (tab);
            var btn = tab_buttons[tab];
            if (btn != null) tab_strip.remove (btn);
            tab_buttons.unset (tab);
            tab_stack.remove (tab);
            if (current_tab == tab) {
                current_tab = null;
                if (tabs.size > 0) select_tab (tabs[int.min (idx, tabs.size - 1)]);
                else open_overview ();
            }
        }

        public void open_overview () {
            var t = find_tab ("overview");
            if (t == null) {
                t = new OverviewTab (this);
                add_tab (t);
            } else {
                select_tab (t);
            }
        }

        public void open_object (CatalogObject o, string? mode = null) {
            string key = object_key (o);
            var t = find_tab (key);
            if (t == null) {
                if (o.kind == ObjectKind.TABLE || o.kind == ObjectKind.VIEW || o.kind == ObjectKind.MATERIALIZED_VIEW) t = new TableTab (this, o, mode ?? "data");
                else t = new DefinitionTab (this, o);
                add_tab (t);
            } else {
                select_tab (t);
                var tt = t as TableTab;
                if (tt != null && mode != null) tt.set_mode (mode);
            }
        }

        public void open_sql (string? text) {
            int n = 1;
            foreach (var t in tabs) if (t is SqlTab) n++;
            var tab = new SqlTab (this, n);
            add_tab (tab);
            if (text != null) tab.set_text (text);
        }

        public void open_users () {
            if (is_sqlite) return;
            var t = find_tab ("users");
            if (t == null) add_tab (new UsersTab (this));
            else select_tab (t);
        }

        public void open_activity () {
            if (is_sqlite) return;
            var t = find_tab ("activity");
            if (t == null) add_tab (new ActivityTab (this));
            else select_tab (t);
        }

        public Gee.ArrayList<string> completion_words () {
            var list = new Gee.ArrayList<string> ();
            if (session.engine == null) return list;
            foreach (string k in engine.keywords ()) list.add (k.up ());
            foreach (string t in engine.type_names ()) list.add (t);
            foreach (var o in objects) {
                list.add (o.name);
                if (o.kind == ObjectKind.FUNCTION || o.kind == ObjectKind.PROCEDURE) continue;
            }
            foreach (var cols in column_cache.values) list.add_all (cols);
            return list;
        }

        private bool on_close_request () {
            foreach (var t in tabs) {
                if (t.has_changes ()) {
                    select_tab (t);
                    confirm (_("Discard Changes?"), _("%s has changes that were not applied to the database.").printf (t.tab_title), _("Disconnect"), () => {
                        foreach (var x in tabs.to_array ()) close_tab (x);
                        close ();
                    });
                    return true;
                }
            }
            foreach (var t in tabs.to_array ()) t.closed ();
            if (connect_cancel != null) connect_cancel.cancel ();
            var s = session;
            active_cursor = null;
            s.disconnect.begin ();
            app.connection_window_closed (this);
            return false;
        }
    }

    public class OverviewTab : ClientTab {
        private Box body;

        public OverviewTab (ClientWindow win) {
            base (win, "overview");
            tab_title = _("Overview");
            tab_icon = "db-server-symbolic";
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.vexpand = true;
            var clamp = new Box (Orientation.VERTICAL, 18);
            clamp.margin_top = 28;
            clamp.margin_bottom = 28;
            clamp.margin_start = clamp.margin_end = 32;
            clamp.halign = Align.CENTER;
            clamp.width_request = 680;
            body = clamp;
            scroll.child = clamp;
            append (scroll);
            win.catalog_changed.connect (() => rebuild ());
            rebuild ();
        }

        public override void reload () {
            rebuild ();
        }

        private void rebuild () {
            Widget? c;
            while ((c = body.get_first_child ()) != null) body.remove (c);
            if (win.session.engine == null) return;
            var e = win.engine;
            var head = new Box (Orientation.HORIZONTAL, 16);
            var icon = new Image.from_icon_name (win.is_sqlite ? "x-office-database" : "dev.sinty.database");
            icon.pixel_size = 64;
            head.append (icon);
            var texts = new Box (Orientation.VERTICAL, 4);
            texts.valign = Align.CENTER;
            var t = new Label (win.config.name);
            t.add_css_class ("title-1");
            t.xalign = 0;
            texts.append (t);
            var s = new Label ("%s  %s".printf (e.server_version, win.config.summary ()));
            s.add_css_class ("dim-label");
            s.xalign = 0;
            s.wrap = true;
            s.selectable = true;
            texts.append (s);
            head.append (texts);
            body.append (head);

            var stats = new Box (Orientation.HORIZONTAL, 10);
            stats.homogeneous = true;
            ObjectKind[] kinds = { ObjectKind.TABLE, ObjectKind.VIEW, ObjectKind.FUNCTION, ObjectKind.INDEX };
            foreach (var k in kinds) {
                int n = 0;
                int64 rows_total = 0;
                foreach (var o in win.objects) {
                    if (o.kind == k || (k == ObjectKind.VIEW && o.kind == ObjectKind.MATERIALIZED_VIEW) || (k == ObjectKind.FUNCTION && o.kind == ObjectKind.PROCEDURE)) {
                        n++;
                        if (o.row_estimate > 0) rows_total += o.row_estimate;
                    }
                }
                var card = new Box (Orientation.VERTICAL, 2);
                card.add_css_class ("db-stat-card");
                var num = new Label (n.to_string ());
                num.add_css_class ("title-2");
                num.xalign = 0;
                card.append (num);
                var lbl = new Label (k.plural ());
                lbl.add_css_class ("dim-label");
                lbl.xalign = 0;
                card.append (lbl);
                if (k == ObjectKind.TABLE && rows_total > 0) {
                    var rl = new Label (ngettext ("about %s row", "about %s rows", (ulong) rows_total).printf (DatabaseWindow.compact_count (rows_total)));
                    rl.add_css_class ("caption");
                    rl.add_css_class ("dim-label");
                    rl.xalign = 0;
                    card.append (rl);
                }
                stats.append (card);
            }
            body.append (stats);

            var g = new PreferencesGroup (_("Connection"), null);
            g.add_row (new ActionRow (_("Engine"), win.config.kind.label ()));
            g.add_row (new ActionRow (_("Server"), e.server_version));
            if (!win.is_sqlite) {
                g.add_row (new ActionRow (_("Database"), e.current_database != "" ? e.current_database : _("None")));
                g.add_row (new ActionRow (_("Schema"), win.schema));
                bool tls = false;
                var pg = e as PgEngine;
                if (pg != null) tls = pg.tls_active;
                var my = e as MysqlEngine;
                if (my != null) tls = my.tls_active;
                g.add_row (new ActionRow (_("Encryption"), tls ? _("TLS, %s").printf (win.config.ssl_mode.label ()) : _("Not encrypted")));
                if (win.config.ssh_enabled) g.add_row (new ActionRow (_("SSH Tunnel"), "%s@%s:%d".printf (win.config.ssh_user, win.config.ssh_host, win.config.ssh_port)));
            } else {
                g.add_row (new ActionRow (_("File"), win.config.file_path));
            }
            g.add_row (new ActionRow (_("Access"), win.config.read_only ? _("Read only") : _("Read and write")));
            body.append (g);

            var actions = new PreferencesGroup (_("Start"), null);
            var sql = new ActionRow (_("New SQL Editor"), _("Write queries with completion, run them and compare results in tabs"), "db-sql-symbolic");
            sql.activatable = true;
            sql.activated.connect (() => win.open_sql (null));
            actions.add_row (sql);
            if (!win.is_sqlite) {
                var users = new ActionRow (_("Users and Privileges"), _("Accounts, roles and what they can access"), "db-users-symbolic");
                users.activatable = true;
                users.activated.connect (() => win.open_users ());
                actions.add_row (users);
                var act = new ActionRow (_("Server Activity"), _("Running sessions and queries, cancel or end them"), "db-activity-symbolic");
                act.activatable = true;
                act.activated.connect (() => win.open_activity ());
                actions.add_row (act);
            }
            var dump = new ActionRow (_("Export Schema as SQL"), _("Structure and data in one script"), "document-send-symbolic");
            dump.activatable = true;
            dump.activated.connect (() => ClientDialogs.dump_schema (win));
            actions.add_row (dump);
            body.append (actions);
        }
    }

    public class DefinitionTab : ClientTab {
        private CatalogObject obj;
        private GtkSource.Buffer buffer;
        private Label status;

        public DefinitionTab (ClientWindow win, CatalogObject obj) {
            base (win, ClientWindow.object_key (obj));
            this.obj = obj;
            tab_title = obj.name;
            tab_icon = "db-sql-symbolic";
            var bar = toolbar ();
            var title = new Label ("%s  %s".printf (obj.kind.label (), obj.parent != "" ? _("on %s").printf (obj.parent) : ""));
            title.add_css_class ("dim-label");
            title.margin_start = 6;
            bar.append (title);
            spacer (bar);
            tool (bar, "edit-copy-symbolic", _("Copy"), () => get_clipboard ().set_text (buffer.text));
            tool (bar, "db-sql-symbolic", _("Open in SQL Editor"), () => win.open_sql (buffer.text));
            tool (bar, "view-refresh-symbolic", _("Reload"), () => reload ());
            append (bar);
            buffer = new GtkSource.Buffer (null);
            var lang = GtkSource.LanguageManager.get_default ().get_language ("sql");
            if (lang != null) buffer.language = lang;
            var view = new Singularity.Widgets.SourceView (buffer);
            view.toolbar_top_padding = 8;
            view.editable = false;
            view.monospace = true;
            view.show_line_numbers = true;
            SqlTab.apply_scheme (view, buffer, win.app.settings);
            var scroll = new ScrolledWindow ();
            scroll.vexpand = true;
            scroll.child = view;
            append (scroll);
            status = new Label ("");
            status.add_css_class ("db-status");
            status.xalign = 0;
            append (status);
            reload ();
        }

        public override void reload () {
            load.begin ();
        }

        private async void load () {
            try {
                var e = yield win.ready ();
                string def = yield e.object_definition (obj);
                buffer.text = def != "" ? def : _("-- The server did not return a definition.");
            } catch (Error e) {
                buffer.text = "-- " + e.message;
            }
        }
    }
}
