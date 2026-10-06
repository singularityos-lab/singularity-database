using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Database {

    public class ConnectionDialog : Object {
        public delegate void Connect (ConnectionConfig config, string? password, string? ssh_password);

        private AppDialog dlg;
        private ConnectionConfig config;
        private bool is_new;
        private Connect on_connect;
        private Cancellable? testing;

        private SelectionRow engine_row;
        private EntryRow name_row;
        private EntryRow host_row;
        private EntryRow port_row;
        private EntryRow socket_row;
        private EntryRow user_row;
        private PasswordRow password_row;
        private SwitchRow save_password_row;
        private EntryRow database_row;
        private ActionRow file_row;
        private SwitchRow create_row;
        private SelectionRow ssl_row;
        private ActionRow ca_row;
        private SwitchRow ssh_row;
        private EntryRow ssh_host_row;
        private EntryRow ssh_port_row;
        private EntryRow ssh_user_row;
        private SelectionRow ssh_auth_row;
        private ActionRow ssh_key_row;
        private PasswordRow ssh_password_row;
        private SwitchRow read_only_row;
        private PreferencesGroup server_group;
        private PreferencesGroup file_group;
        private PreferencesGroup security_group;
        private PreferencesGroup ssh_group;
        private Label status;
        private Spinner spinner;
        private Button test_button;
        private string file_path = "";
        private string ca_path = "";
        private string key_path = "";
        private string[] engine_labels = { EngineKind.POSTGRESQL.label (), EngineKind.MYSQL.label (), EngineKind.SQLITE.label () };
        private string[] ssl_labels = { SslMode.DISABLE.label (), SslMode.PREFER.label (), SslMode.REQUIRE.label (), SslMode.VERIFY_FULL.label () };

        public static void open (Gtk.Window parent, Gtk.Application app, ConnectionConfig? existing, owned Connect on_connect) {
            var d = new ConnectionDialog (parent, app, existing, (owned) on_connect);
            d.dlg.set_data ("controller", d);
            d.dlg.open_dialog ();
        }

        private ConnectionDialog (Gtk.Window parent, Gtk.Application app, ConnectionConfig? existing, owned Connect cb) {
            is_new = existing == null;
            config = existing != null ? existing.copy () : new ConnectionConfig ();
            if (is_new) config.id = "";
            on_connect = (owned) cb;
            file_path = config.file_path;
            ca_path = config.ssl_ca_file;
            key_path = config.ssh_key_file;

            dlg = new AppDialog (app, true);
            dlg.set_title (is_new ? _("New Connection") : _("Edit Connection"));
            dlg.transient_for = parent;
            dlg.set_default_size (560, -1);
            dlg.close_request.connect (() => {
                if (testing != null) testing.cancel ();
                return false;
            });

            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.propagate_natural_height = true;
            scroll.max_content_height = 560;
            var box = new Box (Orientation.VERTICAL, 14);
            box.margin_start = box.margin_end = 18;
            box.margin_top = 6;
            box.margin_bottom = 12;
            scroll.child = box;
            dlg.content_box.append (scroll);

            var g = new PreferencesGroup (_("Connection"), null);
            engine_row = new SelectionRow (_("Database Type"), engine_labels, config.kind.label ());
            engine_row.selected.connect ((item) => update_visibility ());
            g.add_row (engine_row);
            name_row = new EntryRow (_("Name"));
            name_row.text = config.name;
            g.add_row (name_row);
            box.append (g);

            server_group = new PreferencesGroup (_("Server"), null);
            host_row = new EntryRow (_("Host"));
            host_row.text = config.host;
            server_group.add_row (host_row);
            port_row = new EntryRow (_("Port"));
            port_row.text = config.port > 0 ? config.port.to_string () : "";
            server_group.add_row (port_row);
            user_row = new EntryRow (_("User"));
            user_row.text = config.user;
            server_group.add_row (user_row);
            password_row = new PasswordRow (_("Password"));
            server_group.add_row (password_row);
            save_password_row = new SwitchRow (_("Remember Password"), _("Kept in the system keyring"), true);
            server_group.add_row (save_password_row);
            database_row = new EntryRow (_("Database"));
            database_row.text = config.database;
            server_group.add_row (database_row);
            socket_row = new EntryRow (_("Local Socket Folder or File"));
            socket_row.text = config.socket_path;
            server_group.add_row (socket_row);
            box.append (server_group);

            file_group = new PreferencesGroup (_("File"), null);
            file_row = new ActionRow (_("Database File"), file_path != "" ? file_path : _("None chosen"));
            var choose = new Button.with_label (_("Choose"));
            choose.valign = Align.CENTER;
            choose.clicked.connect (() => choose_file ());
            file_row.add_suffix (choose);
            file_group.add_row (file_row);
            create_row = new SwitchRow (_("Create If Missing"), null, false);
            file_group.add_row (create_row);
            box.append (file_group);

            security_group = new PreferencesGroup (_("Encryption"), _("Required and Verified checks the server certificate and name against the certificate authority."));
            ssl_row = new SelectionRow (_("TLS"), ssl_labels, config.ssl_mode.label ());
            ssl_row.selected.connect ((item) => update_visibility ());
            security_group.add_row (ssl_row);
            ca_row = new ActionRow (_("Certificate Authority"), ca_path != "" ? ca_path : _("System certificates"));
            var ca_btn = new Button.with_label (_("Choose"));
            ca_btn.valign = Align.CENTER;
            ca_btn.clicked.connect (() => choose_path (_("Certificate Authority"), (p) => {
                ca_path = p;
                ca_row.subtitle = p != "" ? p : _("System certificates");
            }));
            ca_row.add_suffix (ca_btn);
            var ca_clear = new Button.from_icon_name ("edit-clear-symbolic");
            ca_clear.add_css_class ("flat");
            ca_clear.valign = Align.CENTER;
            ca_clear.tooltip_text = _("Use System Certificates");
            ca_clear.clicked.connect (() => {
                ca_path = "";
                ca_row.subtitle = _("System certificates");
            });
            ca_row.add_suffix (ca_clear);
            security_group.add_row (ca_row);
            box.append (security_group);

            ssh_group = new PreferencesGroup (_("SSH Tunnel"), _("Reach a server that only listens inside a private network."));
            ssh_row = new SwitchRow (_("Connect Through SSH"), null, config.ssh_enabled);
            ssh_row.switch_btn.notify["active"].connect (() => update_visibility ());
            ssh_group.add_row (ssh_row);
            ssh_host_row = new EntryRow (_("SSH Server"));
            ssh_host_row.text = config.ssh_host;
            ssh_group.add_row (ssh_host_row);
            ssh_port_row = new EntryRow (_("SSH Port"));
            ssh_port_row.text = config.ssh_port.to_string ();
            ssh_group.add_row (ssh_port_row);
            ssh_user_row = new EntryRow (_("SSH User"));
            ssh_user_row.text = config.ssh_user;
            ssh_group.add_row (ssh_user_row);
            string[] auths = { _("Key"), _("Password") };
            ssh_auth_row = new SelectionRow (_("Sign In With"), auths, config.ssh_use_password ? auths[1] : auths[0]);
            ssh_auth_row.selected.connect ((item) => update_visibility ());
            ssh_group.add_row (ssh_auth_row);
            ssh_key_row = new ActionRow (_("Private Key"), key_path != "" ? key_path : _("Default keys and agent"));
            var key_btn = new Button.with_label (_("Choose"));
            key_btn.valign = Align.CENTER;
            key_btn.clicked.connect (() => choose_path (_("Private Key"), (p) => {
                key_path = p;
                ssh_key_row.subtitle = p != "" ? p : _("Default keys and agent");
            }));
            ssh_key_row.add_suffix (key_btn);
            ssh_group.add_row (ssh_key_row);
            ssh_password_row = new PasswordRow (_("SSH Password"));
            ssh_group.add_row (ssh_password_row);
            box.append (ssh_group);

            var og = new PreferencesGroup (_("Safety"), null);
            read_only_row = new SwitchRow (_("Read Only"), _("Browse and query without changing data"), config.read_only);
            og.add_row (read_only_row);
            box.append (og);

            var bar = new Box (Orientation.HORIZONTAL, 8);
            bar.margin_start = bar.margin_end = 18;
            bar.margin_bottom = 16;
            bar.margin_top = 4;
            spinner = new Spinner ();
            spinner.visible = false;
            bar.append (spinner);
            status = new Label ("");
            status.xalign = 0;
            status.hexpand = true;
            status.wrap = true;
            status.max_width_chars = 34;
            status.selectable = true;
            status.add_css_class ("caption");
            status.add_css_class ("db-conn-status");
            bar.append (status);
            test_button = new Button.with_label (_("Test"));
            test_button.clicked.connect (() => run_test ());
            bar.append (test_button);
            var cancel = new Button.with_label (_("Cancel"));
            cancel.clicked.connect (() => dlg.close ());
            dlg.set_cancel_button (cancel);
            bar.append (cancel);
            var save = new Button.with_label (_("Save"));
            save.clicked.connect (() => {
                if (store (false)) dlg.close ();
            });
            bar.append (save);
            var connect = new Button.with_label (_("Connect"));
            connect.add_css_class ("suggested-action");
            connect.clicked.connect (() => {
                if (!store (true)) return;
                string pw = password_row.text;
                string spw = ssh_password_row.text;
                var c = config.copy ();
                dlg.close ();
                on_connect (c, pw != "" ? pw : null, spw != "" ? spw : null);
            });
            bar.append (connect);
            dlg.content_box.append (bar);
            dlg.default_widget = connect;
            update_visibility ();
            if (!is_new) prefill_passwords.begin ();
        }

        private async void prefill_passwords () {
            string? pw = yield ConnectionSecrets.lookup (config.id, "db");
            if (pw != null) password_row.text = pw;
            string? spw = yield ConnectionSecrets.lookup (config.id, "ssh");
            if (spw != null) ssh_password_row.text = spw;
        }

        private EngineKind current_kind () {
            string v = engine_row.current_value;
            if (v == EngineKind.MYSQL.label ()) return EngineKind.MYSQL;
            if (v == EngineKind.SQLITE.label ()) return EngineKind.SQLITE;
            return EngineKind.POSTGRESQL;
        }

        private SslMode current_ssl () {
            for (int i = 0; i < ssl_labels.length; i++) {
                if (ssl_row.current_value == ssl_labels[i]) return (SslMode) i;
            }
            return SslMode.PREFER;
        }

        private void update_visibility () {
            var k = current_kind ();
            bool server = k != EngineKind.SQLITE;
            server_group.visible = server;
            security_group.visible = server;
            ssh_group.visible = server;
            file_group.visible = !server;
            port_row.title = server ? _("Port (%d)").printf (k.default_port ()) : _("Port");
            ca_row.visible = current_ssl () == SslMode.VERIFY_FULL;
            bool ssh = ssh_row.active;
            ssh_host_row.visible = ssh;
            ssh_port_row.visible = ssh;
            ssh_user_row.visible = ssh;
            ssh_auth_row.visible = ssh;
            bool pw = ssh_auth_row.current_value == _("Password");
            ssh_key_row.visible = ssh && !pw;
            ssh_password_row.visible = ssh && pw;
        }

        private delegate void PathChosen (string path);

        private void choose_path (string title, owned PathChosen cb) {
            var fd = new FileDialog ();
            fd.title = title;
            fd.open.begin (dlg, null, (o, res) => {
                try {
                    var f = fd.open.end (res);
                    if (f != null && f.get_path () != null) cb (f.get_path ());
                } catch (Error e) {
                }
            });
        }

        private void choose_file () {
            var fd = new FileDialog ();
            fd.title = _("SQLite Database");
            var filter = new FileFilter ();
            filter.name = _("SQLite Databases");
            foreach (string s in new string[] { "sqlite", "sqlite3", "db", "db3", "sdb" }) filter.add_suffix (s);
            var all = new FileFilter ();
            all.name = _("All Files");
            all.add_pattern ("*");
            var filters = new GLib.ListStore (typeof (FileFilter));
            filters.append (filter);
            filters.append (all);
            fd.filters = filters;
            fd.open.begin (dlg, null, (o, res) => {
                try {
                    var f = fd.open.end (res);
                    if (f == null || f.get_path () == null) return;
                    file_path = f.get_path ();
                    file_row.subtitle = file_path;
                    if (name_row.text.strip () == "") name_row.text = f.get_basename ();
                } catch (Error e) {
                }
            });
        }

        private bool read_form (out string problem) {
            problem = "";
            var k = current_kind ();
            config.kind = k;
            config.host = host_row.text.strip ();
            string p = port_row.text.strip ();
            int port = 0;
            if (p != "" && (!int.try_parse (p, out port) || port <= 0 || port > 65535)) {
                problem = _("The port must be a number between 1 and 65535.");
                return false;
            }
            config.port = port;
            config.user = user_row.text.strip ();
            config.database = database_row.text.strip ();
            config.socket_path = socket_row.text.strip ();
            config.file_path = file_path;
            config.ssl_mode = current_ssl ();
            config.ssl_ca_file = ca_path;
            config.ssh_enabled = k != EngineKind.SQLITE && ssh_row.active;
            config.ssh_host = ssh_host_row.text.strip ();
            int sp = 22;
            if (config.ssh_enabled && (!int.try_parse (ssh_port_row.text.strip (), out sp) || sp <= 0 || sp > 65535)) {
                problem = _("The SSH port must be a number between 1 and 65535.");
                return false;
            }
            config.ssh_port = sp;
            config.ssh_user = ssh_user_row.text.strip ();
            config.ssh_use_password = ssh_auth_row.current_value == _("Password");
            config.ssh_key_file = config.ssh_use_password ? "" : key_path;
            config.read_only = read_only_row.active;
            if (k == EngineKind.SQLITE) {
                if (file_path == "") {
                    problem = _("Choose a database file.");
                    return false;
                }
                if (!create_row.active && !FileUtils.test (file_path, FileTest.EXISTS)) {
                    problem = _("The file does not exist. Turn on Create If Missing to start a new one.");
                    return false;
                }
            } else {
                if (config.host == "" && config.socket_path == "") {
                    problem = _("Enter the server host.");
                    return false;
                }
                if (config.user == "") {
                    problem = _("Enter the user name.");
                    return false;
                }
                if (config.ssh_enabled && config.ssh_host == "") {
                    problem = _("Enter the SSH server.");
                    return false;
                }
            }
            string n = name_row.text.strip ();
            if (n == "") {
                if (k == EngineKind.SQLITE) n = Path.get_basename (file_path);
                else if (config.database != "") n = "%s on %s".printf (config.database, config.host);
                else if (config.host != "") n = config.host;
                else n = k.label ();
            }
            config.name = n;
            return true;
        }

        private void show_status (string text, bool error) {
            status.label = text;
            if (error) {
                status.add_css_class ("error");
                status.remove_css_class ("success");
            } else {
                status.remove_css_class ("error");
                status.add_css_class ("success");
            }
        }

        private void run_test () {
            string problem;
            if (!read_form (out problem)) {
                show_status (problem, true);
                return;
            }
            if (testing != null) testing.cancel ();
            testing = new Cancellable ();
            var c = config.copy ();
            if (c.id == "") c.id = "test";
            spinner.visible = true;
            spinner.spinning = true;
            test_button.sensitive = false;
            show_status (_("Connecting"), false);
            status.remove_css_class ("success");
            string pw = password_row.text, spw = ssh_password_row.text;
            var cancel = testing;
            ClientSession.test.begin (c, pw != "" ? pw : null, spw != "" ? spw : null, cancel, (o, res) => {
                if (cancel.is_cancelled ()) return;
                spinner.spinning = false;
                spinner.visible = false;
                test_button.sensitive = true;
                try {
                    string info = ClientSession.test.end (res);
                    show_status (_("Connected: %s").printf (info), false);
                } catch (Error e) {
                    show_status (e.message, true);
                }
            });
        }

        private bool store (bool for_connect) {
            string problem;
            if (!read_form (out problem)) {
                show_status (problem, true);
                return false;
            }
            try {
                ConnectionStore.get_default ().put (config);
            } catch (Error e) {
                show_status (_("The connection could not be saved: %s").printf (e.message), true);
                return false;
            }
            if (config.kind != EngineKind.SQLITE) {
                string pw = save_password_row.active ? password_row.text : "";
                string spw = save_password_row.active && config.ssh_use_password ? ssh_password_row.text : "";
                var c = config.copy ();
                var win = dlg.transient_for;
                ConnectionSecrets.store.begin (c, "db", pw, (o, res) => {
                    try {
                        ConnectionSecrets.store.end (res);
                    } catch (Error e) {
                        var dw = win as ClientWindow;
                        if (dw != null) dw.toast (ConnectionSecrets.unavailable_message (e));
                    }
                });
                ConnectionSecrets.store.begin (c, "ssh", spw, (o, res) => {
                    try {
                        ConnectionSecrets.store.end (res);
                    } catch (Error e) {
                    }
                });
            }
            return true;
        }
    }
}
