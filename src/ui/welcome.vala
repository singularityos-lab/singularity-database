using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Database {

    public class WelcomeView : Box {
        private weak DatabaseWindow win;
        private Box recent_list;
        private Label recent_empty;
        private Box conn_list;
        private Label conn_title;

        public WelcomeView (DatabaseWindow win) {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            this.win = win;
            var wp = new WelcomePage ();
            wp.vexpand = true;
            wp.app_icon_name = "dev.sinty.database";
            wp.title = _("Database");
            wp.subtitle = _("Organize records in tables, ask questions, enter data with forms and print reports");
            wp.add_action ("x-office-database", _("New Database"), _("Start from an empty database"), () => win.app.activate_action ("new", null));
            wp.add_action ("document-open", _("Open"), _("Database, SQLite and Access files"), () => win.app.choose_file (win));
            wp.add_action ("text-csv", _("Import Data"), _("Create a database from CSV, Excel, JSON or SQL"), () => choose_import ());
            wp.add_action ("network-server", _("Connect to Server"), _("PostgreSQL, MySQL, MariaDB or a SQLite file"), () => win.app.new_connection (win));
            wp.set_extra_widget (build_extra ());
            append (wp);
        }

        private void choose_import () {
            var dialog = new FileDialog ();
            dialog.title = _("Import Data");
            var filter = new FileFilter ();
            filter.name = _("Data Files");
            foreach (string s in new string[] { "csv", "tsv", "txt", "xlsx", "json", "ndjson", "sql", "mdb", "accdb" }) filter.add_suffix (s);
            var filters = new GLib.ListStore (typeof (FileFilter));
            filters.append (filter);
            dialog.filters = filters;
            dialog.open.begin (win, null, (obj, res) => {
                try {
                    var file = dialog.open.end (res);
                    if (file == null) return;
                    string p = file.get_path ();
                    if (DatabaseApp.is_access_file (p)) win.convert_access (p);
                    else win.import_into_new (p);
                } catch (Error e) {
                }
            });
        }

        private Widget build_extra () {
            var wrap = new Box (Orientation.VERTICAL, 12);
            var t_title = new Label (_("Templates"));
            t_title.add_css_class ("title-2");
            t_title.halign = Align.START;
            wrap.append (t_title);
            var flow = new FlowBox ();
            flow.selection_mode = SelectionMode.NONE;
            flow.min_children_per_line = 1;
            flow.max_children_per_line = 2;
            flow.column_spacing = 10;
            flow.row_spacing = 10;
            flow.homogeneous = true;
            foreach (var t in Templates.list ()) flow.append (template_card (t.icon, t.title, t.description, t.id));
            wrap.append (flow);
            conn_title = new Label (_("Connections"));
            conn_title.add_css_class ("title-2");
            conn_title.halign = Align.START;
            conn_title.margin_top = 12;
            wrap.append (conn_title);
            conn_list = new Box (Orientation.VERTICAL, 0);
            wrap.append (conn_list);
            ConnectionStore.get_default ().changed.connect (() => refresh_connections ());
            var r_title = new Label (_("Recent"));
            r_title.add_css_class ("title-2");
            r_title.halign = Align.START;
            r_title.margin_top = 12;
            wrap.append (r_title);
            recent_list = new Box (Orientation.VERTICAL, 0);
            wrap.append (recent_list);
            recent_empty = new Label (_("Databases you open appear here."));
            recent_empty.add_css_class ("dim-label");
            recent_empty.halign = Align.START;
            wrap.append (recent_empty);
            return wrap;
        }

        private Widget template_card (string icon, string title, string desc, string id) {
            var btn = new Button ();
            btn.add_css_class ("flat");
            btn.add_css_class ("db-template-card");
            var box = new Box (Orientation.HORIZONTAL, 12);
            var img = new Image.from_icon_name (icon);
            img.pixel_size = 48;
            box.append (img);
            var texts = new Box (Orientation.VERTICAL, 2);
            texts.valign = Align.CENTER;
            var name = new Label (title);
            name.add_css_class ("heading");
            name.halign = Align.START;
            var d = new Label (desc);
            d.add_css_class ("caption");
            d.add_css_class ("dim-label");
            d.halign = Align.START;
            d.xalign = 0;
            d.wrap = true;
            d.max_width_chars = 26;
            d.lines = 2;
            d.ellipsize = Pango.EllipsizeMode.END;
            texts.append (name);
            texts.append (d);
            box.append (texts);
            btn.child = box;
            btn.tooltip_text = _("Create a %s database").printf (title);
            btn.clicked.connect (() => win.new_from_template (id));
            return btn;
        }

        private void refresh_connections () {
            Widget? child;
            while ((child = conn_list.get_first_child ()) != null) conn_list.remove (child);
            var store = ConnectionStore.get_default ();
            foreach (var c in store.items) {
                var row = new Button ();
                row.add_css_class ("flat");
                row.add_css_class ("db-recent-row");
                var box = new Box (Orientation.HORIZONTAL, 12);
                var icon = new Image.from_icon_name (c.kind == EngineKind.SQLITE ? "x-office-database-symbolic" : "db-server-symbolic");
                icon.pixel_size = 20;
                box.append (icon);
                var texts = new Box (Orientation.VERTICAL, 2);
                texts.hexpand = true;
                var name = new Label (c.name);
                name.halign = Align.START;
                name.ellipsize = Pango.EllipsizeMode.END;
                name.add_css_class ("heading");
                var detail = new Label ("%s   %s".printf (c.kind.label (), c.summary ()));
                detail.halign = Align.START;
                detail.ellipsize = Pango.EllipsizeMode.MIDDLE;
                detail.add_css_class ("caption");
                detail.add_css_class ("dim-label");
                texts.append (name);
                texts.append (detail);
                box.append (texts);
                if (c.ssh_enabled) {
                    var ssh = new Label ("SSH");
                    ssh.add_css_class ("db-sidebar-badge");
                    ssh.valign = Align.CENTER;
                    box.append (ssh);
                }
                row.child = box;
                var cfg = c;
                row.clicked.connect (() => win.app.open_connection (cfg, null, null));
                var click = new GestureClick ();
                click.button = 3;
                click.pressed.connect ((n, x, y) => connection_menu (cfg, row, x, y));
                row.add_controller (click);
                conn_list.append (row);
            }
            conn_title.visible = store.items.size > 0;
            conn_list.visible = store.items.size > 0;
        }

        private void connection_menu (ConnectionConfig c, Widget anchor, double x, double y) {
            var menu = new ContextMenu (anchor);
            var r = Gdk.Rectangle ();
            r.x = (int) x;
            r.y = (int) y;
            r.width = r.height = 1;
            menu.pointing_to = r;
            menu.add_item (_("Connect"), "db-connection-symbolic", () => win.app.open_connection (c, null, null));
            menu.add_item (_("Edit…"), "document-edit-symbolic", () => ConnectionDialog.open (win, win.app, c, (nc, pw, spw) => win.app.open_connection (nc, pw, spw)));
            menu.add_item (_("Duplicate"), "edit-copy-symbolic", () => {
                var d = c.copy ();
                d.id = "";
                d.name = _("%s Copy").printf (c.name);
                try {
                    ConnectionStore.get_default ().put (d);
                } catch (Error e) {
                    win.toast (e.message);
                }
            });
            menu.add_separator ();
            menu.add_item (_("Remove"), "user-trash-symbolic", () => {
                try {
                    ConnectionStore.get_default ().remove (c.id);
                    ConnectionSecrets.clear.begin (c.id, "db");
                    ConnectionSecrets.clear.begin (c.id, "ssh");
                } catch (Error e) {
                    win.toast (e.message);
                }
            }, "destructive");
            DatabaseWindow.popup_menu (menu);
        }

        public void refresh () {
            refresh_connections ();
            Widget? child;
            while ((child = recent_list.get_first_child ()) != null) recent_list.remove (child);
            var items = new Gee.ArrayList<RecentInfo> ();
            foreach (var info in RecentManager.get_default ().get_items ()) {
                string uri = info.get_uri ();
                if (!uri.has_prefix ("file:")) continue;
                string? path = File.new_for_uri (uri).get_path ();
                if (path == null) continue;
                if (DatabaseApp.is_database_file (path) && info.exists ()) items.add (info);
            }
            items.sort ((a, b) => b.get_modified ().compare (a.get_modified ()));
            int count = 0;
            foreach (var info in items) {
                if (count++ >= 8) break;
                var file = File.new_for_uri (info.get_uri ());
                var row = new Button ();
                row.add_css_class ("flat");
                row.add_css_class ("db-recent-row");
                var box = new Box (Orientation.HORIZONTAL, 12);
                var icon = new Image.from_icon_name ("x-office-database-symbolic");
                icon.pixel_size = 20;
                box.append (icon);
                var texts = new Box (Orientation.VERTICAL, 2);
                texts.hexpand = true;
                var name = new Label (file.get_basename ());
                name.halign = Align.START;
                name.ellipsize = Pango.EllipsizeMode.MIDDLE;
                name.add_css_class ("heading");
                var path = new Label (DatabaseWindow.friendly_folder (file.get_parent ().get_path () ?? ""));
                path.halign = Align.START;
                path.ellipsize = Pango.EllipsizeMode.START;
                path.add_css_class ("caption");
                path.add_css_class ("dim-label");
                texts.append (name);
                texts.append (path);
                box.append (texts);
                row.child = box;
                row.clicked.connect (() => win.app.open_file (file, win));
                recent_list.append (row);
            }
            recent_list.visible = count > 0;
            recent_empty.visible = count == 0;
        }
    }
}
