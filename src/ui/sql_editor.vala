using Gtk;

namespace Singularity.Apps.Database {

    public class SqlEditor : Box {
        public GtkSource.Buffer buffer;
        public Singularity.Widgets.SourceView view;
        private GtkSource.Buffer words;
        private GtkSource.CompletionWords? provider;
        private Label message;
        private Database db;

        public signal void run_requested (string sql);

        public SqlEditor (Database db, GLib.Settings? settings) {
            Object (orientation: Orientation.VERTICAL, spacing: 8);
            this.db = db;
            buffer = new GtkSource.Buffer (null);
            var lm = GtkSource.LanguageManager.get_default ();
            var lang = lm.get_language ("sql");
            if (lang != null) buffer.language = lang;
            buffer.highlight_syntax = true;
            view = new Singularity.Widgets.SourceView (buffer);
            view.toolbar_top_padding = 8;
            view.show_line_numbers = true;
            view.highlight_current_line = true;
            view.auto_indent = true;
            view.tab_width = 4;
            view.insert_spaces_instead_of_tabs = true;
            view.monospace = true;
            view.add_css_class ("db-sql-view");
            apply_scheme (settings);
            if (settings != null) settings.changed["sql-color-scheme"].connect (() => apply_scheme (settings));
            Gtk.Settings.get_default ().notify["gtk-application-prefer-dark-theme"].connect (() => apply_scheme (settings));
            var scroll = new ScrolledWindow ();
            scroll.vexpand = true;
            scroll.child = view;
            scroll.add_css_class ("db-sql-frame");
            append (scroll);
            message = new Label ("");
            message.add_css_class ("db-message");
            message.halign = Align.START;
            message.xalign = 0;
            message.wrap = true;
            message.selectable = true;
            message.visible = false;
            append (message);
            words = new GtkSource.Buffer (null);
            refresh_words ();
            provider = new GtkSource.CompletionWords (_("Tables and Fields"));
            provider.minimum_word_size = 2;
            provider.register (words);
            provider.register (buffer);
            view.get_completion ().add_provider (provider);
            var keys = new EventControllerKey ();
            keys.set_propagation_phase (PropagationPhase.CAPTURE);
            keys.key_pressed.connect ((kv, kc, st) => {
                if ((kv == Gdk.Key.Return || kv == Gdk.Key.KP_Enter) && (st & Gdk.ModifierType.CONTROL_MASK) != 0) {
                    run_requested (statement_to_run ());
                    return true;
                }
                if (kv == Gdk.Key.F5) {
                    run_requested (statement_to_run ());
                    return true;
                }
                return false;
            });
            view.add_controller (keys);
        }

        private void apply_scheme (GLib.Settings? settings) {
            var sm = GtkSource.StyleSchemeManager.get_default ();
            string id = settings != null ? settings.get_string ("sql-color-scheme") : "auto";
            bool dark = Gtk.Settings.get_default ().gtk_application_prefer_dark_theme;
            var fg = view.get_color ();
            if ((fg.red + fg.green + fg.blue) / 3 > 0.5) dark = true;
            GtkSource.StyleScheme? scheme = null;
            if (id != "auto" && id != "") scheme = sm.get_scheme (id);
            if (scheme == null) scheme = sm.get_scheme (dark ? "Adwaita-dark" : "Adwaita");
            if (scheme == null) scheme = sm.get_scheme (dark ? "oblivion" : "classic");
            if (scheme != null) buffer.style_scheme = scheme;
        }

        public void refresh_words () {
            var sb = new StringBuilder ();
            foreach (string t in db.table_names ()) {
                sb.append (t.contains (" ") ? Sql.quote_ident (t) : t).append ("\n");
                foreach (string c in db.columns_of (t)) sb.append (c.contains (" ") ? Sql.quote_ident (c) : c).append ("\n");
            }
            foreach (string v in db.view_names ()) sb.append (v.contains (" ") ? Sql.quote_ident (v) : v).append ("\n");
            foreach (string k in Sql.KEYWORDS) sb.append (k).append ("\n");
            foreach (string f in Sql.FUNCTIONS) sb.append (f.down ()).append ("\n");
            words.text = sb.str;
        }

        public string text {
            owned get { return buffer.text; }
            set { buffer.text = value; }
        }

        public string statement_to_run () {
            TextIter a, b;
            if (buffer.get_selection_bounds (out a, out b)) return buffer.get_text (a, b, true);
            return buffer.text;
        }

        public void show_message (string text, bool error) {
            message.label = text;
            message.visible = text != "";
            if (error) message.add_css_class ("error");
            else message.remove_css_class ("error");
        }

        public void format () {
            buffer.text = Sql.format (buffer.text);
        }
    }
}
