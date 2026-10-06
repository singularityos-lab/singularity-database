using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Database {

    public class GridPane : Box {
        public ResultGrid grid;
        public ScrolledWindow scroll;

        public GridPane () {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            grid = new ResultGrid ();
            scroll = new ScrolledWindow ();
            scroll.vexpand = true;
            scroll.hexpand = true;
            scroll.child = grid;
            append (scroll);
        }
    }

    public class TableTab : ClientTab {
        public const int PAGE = 500;
        private CatalogObject obj;
        private TableInfo? info;
        private string mode = "data";
        private SegmentedControl modes;
        private Stack stack;
        private GridPane pane;
        private Entry where_entry;
        private Label status;
        private Label pending_label;
        private Button apply_btn;
        private Button discard_btn;
        private Button add_btn;
        private Button del_btn;
        private Button null_btn;
        private Spinner spinner;
        private Gee.ArrayList<ColumnMeta> cols = new Gee.ArrayList<ColumnMeta> ();
        private Gee.ArrayList<Row> rows = new Gee.ArrayList<Row> ();
        private PendingChanges? pending;
        private int64 offset;
        private bool more;
        private bool loading;
        private int64 total = -1;
        private int order_col = -1;
        private bool order_desc;
        private string where_sql = "";
        private double last_ms;
        private Cancellable? cancel;
        private StructureEditor structure;
        private GtkSource.Buffer ddl;
        private bool data_loaded;
        private string read_only_reason = "";

        public TableTab (ClientWindow win, CatalogObject obj, string mode) {
            base (win, ClientWindow.object_key (obj));
            this.obj = obj;
            tab_title = obj.name;
            tab_icon = obj.kind == ObjectKind.TABLE ? "db-table-symbolic" : "db-view-symbolic";

            var head = toolbar ();
            head.add_css_class ("db-tab-head");
            modes = new SegmentedControl ();
            modes.add_option ("data", _("Data"));
            modes.add_option ("structure", _("Structure"));
            modes.add_option ("ddl", _("Definition"));
            modes.selected.connect ((m) => set_mode (m));
            head.append (modes);
            spacer (head);
            spinner = new Spinner ();
            head.append (spinner);
            append (head);

            stack = new Stack ();
            stack.vexpand = true;
            stack.add_named (build_data (), "data");
            structure = new StructureEditor (win, obj);
            structure.applied.connect (() => {
                info = null;
                data_loaded = false;
                load_ddl.begin ();
                win.load_catalog.begin ();
            });
            stack.add_named (structure, "structure");
            stack.add_named (build_ddl (), "ddl");
            append (stack);
            set_mode (mode);
        }

        public override bool has_changes () {
            return (pending != null && !pending.is_empty ()) || structure.has_changes ();
        }

        public override void focus_content () {
            if (mode == "data") pane.grid.grab_focus ();
        }

        public void set_mode (string m) {
            string next = m;
            if (mode != next) mode = next;
            modes.set_active (next);
            stack.visible_child_name = next;
            if (next == "data" && !data_loaded) load_data.begin (true);
            if (next == "structure") structure.ensure_loaded ();
            if (next == "ddl") load_ddl.begin ();
        }

        public override void reload () {
            info = null;
            data_loaded = false;
            structure.reload ();
            string current = mode;
            set_mode (current);
        }

        public override void closed () {
            if (cancel != null) cancel.cancel ();
        }

        private Widget build_data () {
            var box = new Box (Orientation.VERTICAL, 0);
            var bar = toolbar ();
            where_entry = new Entry ();
            where_entry.placeholder_text = _("Filter rows with a condition, for example price > 10");
            where_entry.primary_icon_name = "db-filter-symbolic";
            where_entry.hexpand = true;
            where_entry.add_css_class ("db-where");
            where_entry.tooltip_text = _("A SQL condition that is added as WHERE to the query");
            where_entry.activate.connect (() => {
                where_sql = where_entry.text.strip ();
                load_data.begin (true);
            });
            bar.append (where_entry);
            tool (bar, "view-refresh-symbolic", _("Reload"), () => load_data.begin (true));
            separator (bar);
            add_btn = tool (bar, "list-add-symbolic", _("Add Row"), () => pane.grid.add_row ());
            del_btn = tool (bar, "list-remove-symbolic", _("Delete Selected Rows (Shift+Delete)"), () => pane.grid.delete_selected_rows ());
            null_btn = tool (bar, "edit-clear-symbolic", _("Set to NULL (Delete)"), () => pane.grid.set_selection_null ());
            separator (bar);
            tool (bar, "document-send-symbolic", _("Export Data"), () => ClientDialogs.export_table (win, obj));
            var imp = tool (bar, "document-open-symbolic", _("Import Data"), () => ClientDialogs.import_into (win, obj));
            imp.visible = obj.kind == ObjectKind.TABLE && !win.config.read_only;
            box.append (bar);

            pane = new GridPane ();
            pane.grid.need_more.connect (() => {
                if (pending != null && pending.inserted.size > 0) return;
                if (more && !loading) load_data.begin (false);
            });
            pane.grid.sort_requested.connect ((c) => {
                if (pending != null && !pending.is_empty ()) {
                    win.toast (_("Apply or discard your changes before sorting."));
                    return;
                }
                if (order_col != c) {
                    order_col = c;
                    order_desc = false;
                } else if (!order_desc) {
                    order_desc = true;
                } else {
                    order_col = -1;
                }
                load_data.begin (true);
            });
            pane.grid.cell_menu.connect ((x, y) => cell_menu (x, y));
            pane.grid.edited.connect (() => sync_pending ());
            box.append (pane);

            var foot = toolbar ();
            foot.add_css_class ("db-status-bar");
            status = new Label ("");
            status.add_css_class ("db-status");
            status.xalign = 0;
            status.hexpand = true;
            status.ellipsize = Pango.EllipsizeMode.END;
            foot.append (status);
            pending_label = new Label ("");
            pending_label.add_css_class ("db-pending");
            foot.append (pending_label);
            discard_btn = tool_text (foot, _("Discard"), () => {
                if (pending != null) pending.discard ();
                sync_pending ();
            });
            var preview = tool (foot, "db-sql-symbolic", _("Preview SQL"), () => preview_changes (false));
            preview.set_data<bool> ("pending", true);
            apply_btn = tool_text (foot, _("Apply"), () => preview_changes (true), true);
            box.append (foot);
            sync_pending ();
            return box;
        }

        private void cell_menu (double x, double y) {
            var menu = new ContextMenu (pane.grid);
            var r = Gdk.Rectangle ();
            r.x = (int) x;
            r.y = (int) y;
            r.width = r.height = 1;
            menu.pointing_to = r;
            menu.add_item (_("Copy"), "edit-copy-symbolic", () => pane.grid.copy_selection ());
            menu.add_item (_("Copy with Column Names"), "edit-copy-symbolic", () => pane.grid.copy_selection (true));
            menu.add_item (_("Copy as INSERT"), "db-sql-symbolic", () => copy_as_insert ());
            string col = pane.grid.current_column_name ();
            if (col != "") {
                var v = pane.grid.current_value ();
                menu.add_item (_("Filter by This Value"), "db-filter-symbolic", () => {
                    string cond = v.is_null ? "%s IS NULL".printf (win.engine.quote_ident (col)) : "%s = %s".printf (win.engine.quote_ident (col), win.engine.literal (v));
                    where_entry.text = cond;
                    where_sql = cond;
                    load_data.begin (true);
                });
            }
            if (pane.grid.can_edit ()) {
                menu.add_separator ();
                menu.add_item (_("Edit Cell"), "document-edit-symbolic", () => pane.grid.begin_edit (null));
                menu.add_item (_("Set to NULL"), "edit-clear-symbolic", () => pane.grid.set_selection_null ());
                menu.add_item (_("Add Row"), "list-add-symbolic", () => pane.grid.add_row ());
                menu.add_item (_("Delete Rows"), "list-remove-symbolic", () => pane.grid.delete_selected_rows (), "destructive");
            }
            DatabaseWindow.popup_menu (menu);
        }

        private void copy_as_insert () {
            var e = win.engine;
            var sb = new StringBuilder ();
            string[] names = {};
            foreach (var c in cols) names += e.quote_ident (c.name);
            foreach (int r in pane.grid.selected_rows ()) {
                string[] vals = {};
                for (int c = 0; c < cols.size; c++) vals += e.literal (pane.grid.value_at (r, c));
                sb.append ("INSERT INTO %s (%s) VALUES (%s);\n".printf (e.qualified (obj.schema, obj.name), string.joinv (", ", names), string.joinv (", ", vals)));
            }
            get_clipboard ().set_text (sb.str);
        }

        private void sync_pending () {
            bool dirty = pending != null && !pending.is_empty ();
            int n = pending != null ? pending.count () : 0;
            pending_label.label = dirty ? ngettext ("%d change", "%d changes", n).printf (n) : "";
            apply_btn.visible = dirty;
            discard_btn.visible = dirty;
            for (var c = apply_btn.get_parent ().get_first_child (); c != null; c = c.get_next_sibling ()) {
                if (c.get_data<bool> ("pending")) c.visible = dirty;
            }
            bool editable = pending != null && pending.editable;
            add_btn.sensitive = editable;
            del_btn.sensitive = editable;
            null_btn.sensitive = editable;
            update_status ();
        }

        private void update_status () {
            var parts = new Gee.ArrayList<string> ();
            if (total >= 0) parts.add (_("%s of %s rows").printf (fmt (rows.size), fmt (total)));
            else parts.add (ngettext ("%s row", "%s rows", (ulong) rows.size).printf (fmt (rows.size)) + (more ? _(", more on scroll") : ""));
            if (last_ms > 0) parts.add (_("%.0f ms").printf (last_ms));
            if (read_only_reason != "") parts.add (read_only_reason);
            status.label = string.joinv ("   ", parts.to_array ());
        }

        private static string fmt (int64 n) {
            string s = n.to_string ();
            var sb = new StringBuilder ();
            int len = s.length;
            for (int i = 0; i < len; i++) {
                if (i > 0 && (len - i) % 3 == 0 && s[i - 1] != '-') sb.append_c (',');
                sb.append_c (s[i]);
            }
            return sb.str;
        }

        private async void load_data (bool reset) {
            if (loading && !reset) return;
            if (reset && pending != null && !pending.is_empty ()) {
                win.confirm (_("Discard Changes?"), _("Reloading drops the changes that were not applied."), _("Discard and Reload"), () => {
                    pending.discard ();
                    load_data.begin (true);
                });
                return;
            }
            if (cancel != null && reset) cancel.cancel ();
            cancel = new Cancellable ();
            var my_cancel = cancel;
            loading = true;
            spinner.spinning = true;
            try {
                var e = yield win.ready ();
                if (info == null) {
                    try {
                        info = yield e.describe_table (obj.schema, obj.name, my_cancel);
                    } catch (Error de) {
                        if (Engines.is_cancelled (de)) throw de;
                        info = null;
                    }
                }
                string[] pk = info != null && obj.kind == ObjectKind.TABLE ? info.primary_key () : new string[0];
                string target = e.qualified (obj.schema, obj.name);
                string order = "";
                if (order_col >= 0 && order_col < cols.size) order = " ORDER BY %s%s".printf (e.quote_ident (cols[order_col].name), order_desc ? " DESC" : "");
                else if (pk.length > 0) {
                    string[] q = {};
                    foreach (string k in pk) q += e.quote_ident (k);
                    order = " ORDER BY " + string.joinv (", ", q);
                }
                string where = where_sql != "" ? " WHERE " + where_sql : "";
                int64 start = reset ? 0 : offset;
                string sql = "SELECT * FROM %s%s%s%s".printf (target, where, order, e.limit_clause (PAGE, start));
                var r = yield e.execute (sql, null, my_cancel);
                if (my_cancel.is_cancelled ()) return;
                last_ms = r.elapsed_ms;
                if (reset) {
                    cols = r.columns;
                    if (cols.size == 0 && info != null) {
                        foreach (var c in info.columns) cols.add (new ColumnMeta (c.name));
                    }
                    rows = new Gee.ArrayList<Row> ();
                    string[] names = {};
                    foreach (var c in cols) names += c.name;
                    read_only_reason = "";
                    if (win.config.read_only) read_only_reason = _("Read only connection");
                    else if (obj.kind != ObjectKind.TABLE) read_only_reason = _("Views are read only");
                    else if (pk.length == 0) read_only_reason = _("No primary key, rows are read only");
                    pending = read_only_reason == "" ? new PendingChanges (obj.schema, obj.name, names, pk) : null;
                    if (pending != null) pending.changed.connect (() => sync_pending ());
                    int keep_sort = order_col;
                    pane.grid.set_result (cols, rows, pending, pk);
                    pane.grid.sort_col = keep_sort;
                    pane.grid.sort_desc = order_desc;
                    offset = 0;
                    total = -1;
                    data_loaded = true;
                    if (obj.kind == ObjectKind.TABLE) count_rows.begin (target, where);
                }
                rows.add_all (r.rows);
                offset += r.rows.size;
                more = r.rows.size >= PAGE;
                pane.grid.more_available = more;
                pane.grid.rows_appended ();
                status.remove_css_class ("error");
                sync_pending ();
            } catch (Error err) {
                if (!Engines.is_cancelled (err)) {
                    status.label = err.message;
                    status.add_css_class ("error");
                }
            } finally {
                loading = false;
                spinner.spinning = false;
            }
        }

        private async void count_rows (string target, string where) {
            try {
                var e = yield win.ready ();
                var r = yield e.execute ("SELECT COUNT(*) FROM %s%s".printf (target, where), null, cancel);
                if (r.rows.size > 0) total = r.rows[0].get (0).as_int ();
                if (!more) total = rows.size;
                update_status ();
            } catch (Error e) {
            }
        }

        private void preview_changes (bool then_apply) {
            if (pending == null || pending.is_empty ()) return;
            if (pane.grid.commit_edit () == false) return;
            Gee.ArrayList<EditStatement> list;
            try {
                list = pending.statements (win.engine, rows);
            } catch (Error e) {
                win.show_error (_("Could Not Prepare Changes"), e.message);
                return;
            }
            string[] sql = {};
            foreach (var s in list) sql += s.preview (win.engine) + ";";
            ClientDialogs.preview_sql (win, then_apply ? _("Apply Changes") : _("Pending Changes"),
                ngettext ("%d statement runs in one transaction.", "%d statements run in one transaction.", list.size).printf (list.size),
                string.joinv ("\n", sql), _("Apply"), () => apply.begin ());
        }

        private async void apply () {
            spinner.spinning = true;
            try {
                var e = yield win.ready ();
                int n = yield pending.apply (e, rows, null);
                win.toast (ngettext ("%d change applied", "%d changes applied", n).printf (n));
                load_data.begin (true);
            } catch (RemoteError.CONFLICT e) {
                var dlg = new ConfirmDialog (win.app, _("Changed on the Server"), "dialog-warning", e.message, _("Reload"), ConfirmDialog.ActionStyle.SUGGESTED);
                dlg.transient_for = win;
                dlg.response.connect ((r) => {
                    if (r == ConfirmDialog.Response.PRIMARY) {
                        pending.discard ();
                        load_data.begin (true);
                    }
                });
                dlg.present ();
            } catch (Error e) {
                win.show_error (_("Changes Were Not Applied"), _("Nothing was changed. The server said: %s").printf (e.message));
            } finally {
                spinner.spinning = false;
            }
        }

        private Widget build_ddl () {
            var box = new Box (Orientation.VERTICAL, 0);
            var bar = toolbar ();
            spacer (bar);
            tool (bar, "edit-copy-symbolic", _("Copy"), () => get_clipboard ().set_text (ddl.text));
            tool (bar, "db-sql-symbolic", _("Open in SQL Editor"), () => win.open_sql (ddl.text));
            box.append (bar);
            ddl = new GtkSource.Buffer (null);
            var lang = GtkSource.LanguageManager.get_default ().get_language ("sql");
            if (lang != null) ddl.language = lang;
            var view = new Singularity.Widgets.SourceView (ddl);
            view.toolbar_top_padding = 8;
            view.editable = false;
            view.monospace = true;
            view.show_line_numbers = true;
            SqlTab.apply_scheme (view, ddl, win.app.settings);
            var scroll = new ScrolledWindow ();
            scroll.vexpand = true;
            scroll.child = view;
            box.append (scroll);
            return box;
        }

        private async void load_ddl () {
            try {
                var e = yield win.ready ();
                string text;
                if (obj.kind == ObjectKind.TABLE) {
                    var t = yield e.describe_table (obj.schema, obj.name);
                    text = e.create_table_sql (t);
                } else {
                    text = yield e.object_definition (obj);
                }
                ddl.text = text;
            } catch (Error e) {
                ddl.text = "-- " + e.message;
            }
        }
    }

    public class StructureEditor : Box {
        private weak ClientWindow win;
        private CatalogObject obj;
        private TableInfo? before;
        private Entry name_entry;
        private Grid rows_grid;
        private Box index_box;
        private Box fk_box;
        private Label summary;
        private Button review_btn;
        private Button revert_btn;
        private Gee.ArrayList<ColumnEdit> edits = new Gee.ArrayList<ColumnEdit> ();
        private Gee.ArrayList<IndexInfo> indexes = new Gee.ArrayList<IndexInfo> ();
        private bool loaded;
        private bool editable;

        public signal void applied ();

        private class ColumnEdit {
            public ColumnInfo? original;
            public ColumnInfo current;
        }

        public StructureEditor (ClientWindow win, CatalogObject obj) {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            this.win = win;
            this.obj = obj;
            editable = obj.kind == ObjectKind.TABLE && !win.config.read_only;
            var bar = ClientTab.toolbar ();
            var nl = new Label (_("Name"));
            nl.add_css_class ("dim-label");
            nl.margin_start = 6;
            bar.append (nl);
            name_entry = new Entry ();
            name_entry.width_chars = 28;
            name_entry.sensitive = editable;
            name_entry.changed.connect (() => sync ());
            bar.append (name_entry);
            ClientTab.separator (bar);
            var add = ClientTab.tool_text (bar, _("Add Column"), () => add_column ());
            add.visible = editable;
            ClientTab.spacer (bar);
            revert_btn = ClientTab.tool_text (bar, _("Revert"), () => reload ());
            review_btn = ClientTab.tool_text (bar, _("Review Changes"), () => review (), true);
            append (bar);

            var scroll = new ScrolledWindow ();
            scroll.vexpand = true;
            scroll.hscrollbar_policy = PolicyType.NEVER;
            var content = new Box (Orientation.VERTICAL, 0);
            content.add_css_class ("db-dense");
            rows_grid = new Grid ();
            rows_grid.add_css_class ("db-struct-grid");
            rows_grid.column_spacing = 0;
            rows_grid.row_spacing = 0;
            content.append (rows_grid);
            var sec = new Label (_("Indexes"));
            sec.add_css_class ("db-sheet-title");
            sec.xalign = 0;
            sec.margin_start = 12;
            sec.margin_top = 18;
            var ih = new Box (Orientation.HORIZONTAL, 8);
            ih.append (sec);
            var add_ix = new Button.with_label (_("Add Index"));
            add_ix.add_css_class ("db-small-button");
            add_ix.margin_top = 14;
            add_ix.visible = editable;
            add_ix.clicked.connect (() => add_index (add_ix));
            ih.append (add_ix);
            content.append (ih);
            index_box = new Box (Orientation.VERTICAL, 0);
            index_box.margin_start = 12;
            index_box.margin_end = 12;
            content.append (index_box);
            var fsec = new Label (_("Foreign Keys and Checks"));
            fsec.add_css_class ("db-sheet-title");
            fsec.xalign = 0;
            fsec.margin_start = 12;
            fsec.margin_top = 18;
            content.append (fsec);
            fk_box = new Box (Orientation.VERTICAL, 0);
            fk_box.margin_start = 12;
            fk_box.margin_end = 12;
            fk_box.margin_bottom = 18;
            content.append (fk_box);
            scroll.child = content;
            append (scroll);
            var foot = ClientTab.toolbar ();
            foot.add_css_class ("db-status-bar");
            summary = new Label ("");
            summary.add_css_class ("db-status");
            summary.xalign = 0;
            summary.hexpand = true;
            foot.append (summary);
            append (foot);
            sync ();
        }

        public bool has_changes () {
            if (!loaded || before == null) return false;
            return build_changes (null).size > 0 || name_entry.text.strip () != before.name || !same_indexes ();
        }

        public void ensure_loaded () {
            if (!loaded) reload ();
        }

        public void reload () {
            load.begin ();
        }

        private async void load () {
            try {
                var e = yield win.ready ();
                before = yield e.describe_table (obj.schema, obj.name);
            } catch (Error e) {
                summary.label = e.message;
                summary.add_css_class ("error");
                return;
            }
            summary.remove_css_class ("error");
            loaded = true;
            name_entry.text = before.name;
            edits.clear ();
            foreach (var c in before.columns) {
                var ce = new ColumnEdit ();
                ce.original = c;
                ce.current = c.copy ();
                edits.add (ce);
            }
            indexes.clear ();
            foreach (var ix in before.indexes) indexes.add (ix.copy ());
            rebuild ();
        }

        private bool same_indexes () {
            if (before == null) return true;
            var a = new Gee.ArrayList<string> ();
            foreach (var ix in before.indexes) if (!ix.primary) a.add ("%s|%s|%s".printf (ix.name, string.joinv (",", ix.columns), ix.unique.to_string ()));
            var b = new Gee.ArrayList<string> ();
            foreach (var ix in indexes) if (!ix.primary) b.add ("%s|%s|%s".printf (ix.name, string.joinv (",", ix.columns), ix.unique.to_string ()));
            a.sort ();
            b.sort ();
            return string.joinv (";", a.to_array ()) == string.joinv (";", b.to_array ());
        }

        private void rebuild () {
            Widget? c;
            while ((c = rows_grid.get_first_child ()) != null) rows_grid.remove (c);
            string[] titles = { "", _("Column"), _("Type"), _("Not Null"), _("Default"), _("Comment"), "" };
            for (int t = 0; t < titles.length; t++) {
                var l = new Label (titles[t]);
                l.add_css_class ("db-grid-head");
                l.add_css_class ("db-struct-head");
                l.xalign = 0;
                if (t == 5) l.hexpand = true;
                rows_grid.attach (l, t, 0, 1, 1);
            }
            int i = 0;
            foreach (var ce in edits) {
                column_row (ce, i + 1);
                i++;
            }
            while ((c = index_box.get_first_child ()) != null) index_box.remove (c);
            foreach (var ix in indexes) index_box.append (index_row (ix));
            if (indexes.size == 0) index_box.append (dim (_("No indexes.")));
            while ((c = fk_box.get_first_child ()) != null) fk_box.remove (c);
            if (before != null) {
                foreach (var fk in before.foreign_keys) {
                    string t = "%s (%s)  %s.%s (%s)".printf (fk.name, string.joinv (", ", fk.columns), fk.ref_schema, fk.ref_table, string.joinv (", ", fk.ref_columns));
                    string rules = "";
                    if (fk.on_update != "" && fk.on_update != "NO ACTION") rules += _("on update %s").printf (fk.on_update.down ());
                    if (fk.on_delete != "" && fk.on_delete != "NO ACTION") rules += (rules != "" ? ", " : "") + _("on delete %s").printf (fk.on_delete.down ());
                    fk_box.append (item ("db-relationship-symbolic", t, rules));
                }
                foreach (string ch in before.checks) fk_box.append (item ("object-select-symbolic", "CHECK (%s)".printf (ch), ""));
                if (before.foreign_keys.size == 0 && before.checks.length == 0) fk_box.append (dim (_("None.")));
            }
            sync ();
        }

        private Label dim (string t) {
            var l = new Label (t);
            l.add_css_class ("dim-label");
            l.xalign = 0;
            l.margin_top = 4;
            return l;
        }

        private Widget item (string icon, string title, string sub) {
            var box = new Box (Orientation.HORIZONTAL, 8);
            box.add_css_class ("db-sheet-item");
            box.append (new Image.from_icon_name (icon));
            var tb = new Box (Orientation.VERTICAL, 0);
            var t = new Label (title);
            t.xalign = 0;
            t.selectable = true;
            t.wrap = true;
            tb.append (t);
            if (sub != "") {
                var s = new Label (sub);
                s.add_css_class ("caption");
                s.add_css_class ("dim-label");
                s.xalign = 0;
                tb.append (s);
            }
            box.append (tb);
            return box;
        }

        private void cell (Widget w, int col, int row, bool changed) {
            w.add_css_class ("db-struct-cell");
            if (row % 2 == 0) w.add_css_class ("odd");
            if (changed && col == 0) w.add_css_class ("db-changed");
            w.valign = Align.FILL;
            rows_grid.attach (w, col, row, 1, 1);
        }

        private void column_row (ColumnEdit ce, int row) {
            bool changed = ce.original == null || ce.original.name != ce.current.name || !ce.original.same_definition (ce.current) || ce.original.primary_key != ce.current.primary_key;
            var keybox = new Box (Orientation.HORIZONTAL, 0);
            keybox.width_request = 34;
            keybox.hexpand = false;
            var ki = new Image.from_icon_name ("db-key-symbolic");
            ki.add_css_class ("db-cell-icon");
            ki.halign = Align.CENTER;
            ki.hexpand = true;
            if (ce.current.primary_key) ki.add_css_class ("accent");
            else ki.opacity = 0.18;
            keybox.append (ki);
            keybox.tooltip_text = editable ? _("Primary Key, click to toggle") : _("Primary Key");
            if (editable) {
                var kc = new GestureClick ();
                kc.released.connect (() => {
                    ce.current.primary_key = !ce.current.primary_key;
                    if (ce.current.primary_key) ce.current.nullable = false;
                    rebuild ();
                });
                keybox.add_controller (kc);
            }
            cell (keybox, 0, row, changed);
            var name = new Entry ();
            name.add_css_class ("db-cell");
            name.text = ce.current.name;
            name.width_request = 170;
            name.width_chars = 1;
            name.sensitive = editable;
            name.changed.connect (() => {
                ce.current.name = name.text.strip ();
                sync ();
            });
            cell (name, 1, row, changed);
            var tbox = new Box (Orientation.HORIZONTAL, 0);
            tbox.width_request = 190;
            tbox.hexpand = false;
            var type = new Entry ();
            type.add_css_class ("db-cell");
            type.text = ce.current.data_type;
            type.hexpand = true;
            type.width_chars = 1;
            type.sensitive = editable;
            type.changed.connect (() => {
                ce.current.data_type = type.text.strip ();
                sync ();
            });
            tbox.append (type);
            if (editable) {
                var pick = new MenuButton ();
                pick.add_css_class ("flat");
                pick.add_css_class ("db-cell-menu");
                pick.icon_name = "pan-down-symbolic";
                pick.valign = Align.CENTER;
                pick.tooltip_text = _("Common Types");
                var pop = new Popover ();
                var lb = new Box (Orientation.VERTICAL, 0);
                var sc = new ScrolledWindow ();
                sc.hscrollbar_policy = PolicyType.NEVER;
                sc.propagate_natural_height = true;
                sc.max_content_height = 320;
                foreach (string tn in win.engine.type_names ()) {
                    var b = new Button.with_label (tn);
                    b.add_css_class ("flat");
                    ((Label) b.child).xalign = 0;
                    string v = tn;
                    b.clicked.connect (() => {
                        type.text = v;
                        pop.popdown ();
                    });
                    lb.append (b);
                }
                sc.child = lb;
                pop.child = sc;
                pick.popover = pop;
                tbox.append (pick);
            }
            cell (tbox, 2, row, changed);
            var nnb = new Box (Orientation.HORIZONTAL, 0);
            nnb.width_request = 76;
            var nn = new CheckButton ();
            nn.active = !ce.current.nullable;
            nn.margin_start = 8;
            nn.valign = Align.CENTER;
            nn.sensitive = editable && !ce.current.primary_key;
            nn.toggled.connect (() => {
                ce.current.nullable = !nn.active;
                sync ();
            });
            nnb.append (nn);
            cell (nnb, 3, row, changed);
            var def = new Entry ();
            def.add_css_class ("db-cell");
            def.text = ce.current.default_expr;
            def.width_request = 160;
            def.width_chars = 1;
            def.placeholder_text = ce.current.auto_increment ? _("auto") : "";
            def.sensitive = editable;
            def.changed.connect (() => {
                ce.current.default_expr = def.text.strip ();
                sync ();
            });
            cell (def, 4, row, changed);
            var com = new Entry ();
            com.add_css_class ("db-cell");
            com.text = ce.current.comment;
            com.hexpand = true;
            com.width_chars = 1;
            com.sensitive = editable && !win.is_sqlite;
            com.changed.connect (() => {
                ce.current.comment = com.text;
                sync ();
            });
            cell (com, 5, row, changed);
            var delbox = new Box (Orientation.HORIZONTAL, 0);
            delbox.margin_end = 6;
            delbox.hexpand = false;
            var del = new Button.from_icon_name ("user-trash-symbolic");
            del.add_css_class ("flat");
            del.add_css_class ("db-cell-menu");
            del.valign = Align.CENTER;
            del.tooltip_text = _("Drop Column");
            del.sensitive = editable;
            del.clicked.connect (() => {
                edits.remove (ce);
                rebuild ();
            });
            delbox.append (del);
            cell (delbox, 6, row, changed);
        }

        private Widget index_row (IndexInfo ix) {
            var box = new Box (Orientation.HORIZONTAL, 8);
            box.add_css_class ("db-sheet-item");
            box.append (new Image.from_icon_name (ix.primary ? "db-key-symbolic" : "db-index-symbolic"));
            var tb = new Box (Orientation.VERTICAL, 0);
            tb.hexpand = true;
            var t = new Label (ix.name);
            t.xalign = 0;
            tb.append (t);
            string[] bits = { string.joinv (", ", ix.columns) };
            if (ix.primary) bits += _("primary key");
            else if (ix.unique) bits += _("unique");
            if (ix.method != "" && ix.method != "c" && ix.method != "pk" && ix.method != "u") bits += ix.method;
            var s = new Label (string.joinv (", ", bits));
            s.add_css_class ("caption");
            s.add_css_class ("dim-label");
            s.xalign = 0;
            tb.append (s);
            box.append (tb);
            if (editable && !ix.primary) {
                var del = new Button.from_icon_name ("user-trash-symbolic");
                del.add_css_class ("flat");
                del.tooltip_text = _("Drop Index");
                del.clicked.connect (() => {
                    indexes.remove (ix);
                    rebuild ();
                });
                box.append (del);
            }
            return box;
        }

        private void add_column () {
            var ce = new ColumnEdit ();
            ce.original = null;
            ce.current = new ColumnInfo ();
            int n = edits.size + 1;
            string nm = "column_%d".printf (n);
            ce.current.name = nm;
            string[] types = win.engine.type_names ();
            ce.current.data_type = win.config.kind == EngineKind.POSTGRESQL ? "text" : (win.config.kind == EngineKind.MYSQL ? "VARCHAR(255)" : "TEXT");
            if (types.length == 0) ce.current.data_type = "TEXT";
            edits.add (ce);
            rebuild ();
        }

        private void add_index (Widget anchor) {
            var pop = new Popover ();
            pop.set_parent (anchor);
            var box = new Box (Orientation.VERTICAL, 6);
            box.margin_start = box.margin_end = box.margin_top = box.margin_bottom = 10;
            var name = new Entry ();
            name.placeholder_text = _("Index name");
            box.append (name);
            var checks = new Gee.ArrayList<CheckButton> ();
            foreach (var ce in edits) {
                var cb = new CheckButton.with_label (ce.current.name);
                checks.add (cb);
                box.append (cb);
            }
            var uniq = new CheckButton.with_label (_("Unique"));
            uniq.margin_top = 6;
            box.append (uniq);
            var ok = new Button.with_label (_("Add Index"));
            ok.add_css_class ("suggested-action");
            ok.clicked.connect (() => {
                string[] colsel = {};
                for (int i = 0; i < checks.size; i++) if (checks[i].active) colsel += edits[i].current.name;
                if (colsel.length == 0) return;
                var ix = new IndexInfo ();
                ix.columns = colsel;
                ix.unique = uniq.active;
                string tname = name_entry.text.strip ();
                ix.name = name.text.strip () != "" ? name.text.strip () : "%s_%s_%s".printf (tname, string.joinv ("_", colsel), ix.unique ? "key" : "idx");
                indexes.add (ix);
                pop.popdown ();
                rebuild ();
            });
            box.append (ok);
            pop.child = box;
            pop.closed.connect (() => Idle.add (() => {
                pop.unparent ();
                return Source.REMOVE;
            }));
            pop.popup ();
        }

        private Gee.ArrayList<ColumnChange> build_changes (TableInfo? after) {
            var list = new Gee.ArrayList<ColumnChange> ();
            if (before == null) return list;
            foreach (var c in before.columns) {
                bool kept = false;
                foreach (var ce in edits) if (ce.original == c) kept = true;
                if (!kept) list.add (new ColumnChange (c.name, null));
            }
            foreach (var ce in edits) {
                if (ce.original == null) list.add (new ColumnChange (null, ce.current));
                else if (ce.original.name != ce.current.name || !ce.original.same_definition (ce.current) || ce.original.primary_key != ce.current.primary_key) list.add (new ColumnChange (ce.original.name, ce.current));
            }
            return list;
        }

        private TableInfo build_after () {
            var after = new TableInfo ();
            after.schema = before.schema;
            after.name = name_entry.text.strip ();
            after.comment = before.comment;
            int pos = 1;
            foreach (var ce in edits) {
                var c = ce.current.copy ();
                c.position = pos++;
                after.columns.add (c);
            }
            foreach (var ix in indexes) {
                if (ix.primary) continue;
                after.indexes.add (ix.copy ());
            }
            string[] pk = after.primary_key ();
            if (pk.length > 0) {
                var pix = new IndexInfo ();
                pix.primary = true;
                pix.unique = true;
                pix.columns = pk;
                foreach (var ix in before.indexes) if (ix.primary) pix.name = ix.name;
                after.indexes.add (pix);
            }
            foreach (var fk in before.foreign_keys) after.foreign_keys.add (fk.copy ());
            after.checks = before.checks;
            return after;
        }

        private void sync () {
            bool dirty = has_changes ();
            review_btn.visible = editable;
            review_btn.sensitive = dirty;
            revert_btn.visible = editable && dirty;
            if (before != null) {
                string[] bits = { ngettext ("%d column", "%d columns", edits.size).printf (edits.size) };
                if (!editable) bits += obj.kind != ObjectKind.TABLE ? _("views are changed with SQL") : _("read only connection");
                if (dirty) bits += _("changes not applied yet");
                summary.label = string.joinv ("   ", bits);
            }
        }

        private void review () {
            if (before == null) return;
            var after = build_after ();
            var changes = build_changes (after);
            foreach (var ce in edits) {
                if (ce.current.name == "" || ce.current.data_type == "") {
                    win.show_error (_("Incomplete Column"), _("Every column needs a name and a type."));
                    return;
                }
            }
            string[] stmts = win.engine.alter_table_sql (before, after, changes);
            if (stmts.length == 0) {
                win.toast (_("There is nothing to change."));
                return;
            }
            ClientDialogs.preview_sql (win, _("Review Changes"), _("These statements change %s on the server.").printf (before.name),
                string.joinv ("\n", stmts), _("Apply"), () => apply.begin (stmts));
        }

        private async void apply (owned string[] stmts) {
            int done = 0;
            bool tx = win.config.kind == EngineKind.POSTGRESQL;
            try {
                var e = yield win.ready ();
                if (tx) yield e.begin_transaction ();
                foreach (string s in stmts) {
                    yield e.execute (s);
                    done++;
                }
                if (tx) yield e.commit ();
            } catch (Error err) {
                if (tx) {
                    try {
                        yield win.engine.rollback ();
                    } catch (Error ignored) {
                    }
                }
                string where = done < stmts.length ? stmts[done] : "";
                string msg = tx ? _("Nothing was changed. The server said: %s").printf (err.message) : _("%d of %d statements ran before the error. The server said: %s").printf (done, stmts.length, err.message);
                if (where != "") msg += "\n\n" + where;
                win.show_error (_("Changes Were Not Applied"), msg);
                reload ();
                return;
            }
            win.toast (_("%s updated").printf (name_entry.text.strip ()));
            if (name_entry.text.strip () != before.name) obj.name = name_entry.text.strip ();
            applied ();
            reload ();
        }
    }

    public class ResultEntry {
        public string title;
        public string sql;
        public QueryResult result;
        public Cursor? cursor;
        public bool plan;

        public ResultEntry (string title, string sql, QueryResult result) {
            this.title = title;
            this.sql = sql;
            this.result = result;
        }
    }

    public class SqlTab : ClientTab {
        public const int FIRST = 1000;
        private GtkSource.Buffer buffer;
        private Singularity.Widgets.SourceView view;
        private GtkSource.Buffer words;
        private GtkSource.CompletionWords provider;
        private Box result_strip;
        private Stack result_stack;
        private TextView messages;
        private Label status;
        private Spinner spinner;
        private Button stop_btn;
        private Button run_btn;
        private Button run_all_btn;
        private Cancellable? cancel;
        private bool running;
        private Gee.ArrayList<ResultEntry> results = new Gee.ArrayList<ResultEntry> ();
        private Gee.HashMap<ResultEntry, Button> result_buttons = new Gee.HashMap<ResultEntry, Button> ();
        private ResultEntry? shown;
        private MenuButton history_btn;
        private MenuButton snippets_btn;

        public SqlTab (ClientWindow win, int n) {
            base (win, "sql:%d:%lld".printf (n, get_monotonic_time ()));
            tab_title = n == 1 ? _("SQL") : _("SQL %d").printf (n);
            tab_icon = "db-sql-symbolic";
            var bar = toolbar ();
            run_btn = tool_text (bar, _("Run"), () => run_current (false), true);
            run_btn.tooltip_text = _("Run the statement at the cursor or the selection (Ctrl+Enter)");
            run_all_btn = tool (bar, "media-seek-forward-symbolic", _("Run Script (Ctrl+Shift+Enter)"), () => run_current (true));
            stop_btn = tool (bar, "db-stop-symbolic", _("Stop (Esc)"), () => stop ());
            stop_btn.sensitive = false;
            separator (bar);
            var explain = new MenuButton ();
            explain.has_frame = false;
            explain.add_css_class ("db-tool");
            explain.icon_name = "db-explain-symbolic";
            explain.tooltip_text = _("Explain");
            var em = new ContextMenu (explain);
            em.add_item (_("Explain Plan"), "db-explain-symbolic", () => explain_current (false));
            em.add_item (_("Explain and Measure"), "db-activity-symbolic", () => explain_current (true));
            explain.popover = em;
            bar.append (explain);
            tool (bar, "format-justify-left-symbolic", _("Format SQL"), () => format_sql ());
            separator (bar);
            history_btn = new MenuButton ();
            history_btn.has_frame = false;
            history_btn.add_css_class ("db-tool");
            history_btn.icon_name = "db-history-symbolic";
            history_btn.tooltip_text = _("History");
            history_btn.popover = new Popover ();
            history_btn.popover.notify["visible"].connect (() => {
                if (history_btn.popover.visible) fill_history ();
            });
            bar.append (history_btn);
            snippets_btn = new MenuButton ();
            snippets_btn.has_frame = false;
            snippets_btn.add_css_class ("db-tool");
            snippets_btn.icon_name = "db-snippet-symbolic";
            snippets_btn.tooltip_text = _("Snippets");
            snippets_btn.popover = new Popover ();
            snippets_btn.popover.notify["visible"].connect (() => {
                if (snippets_btn.popover.visible) fill_snippets ();
            });
            bar.append (snippets_btn);
            spacer (bar);
            spinner = new Spinner ();
            bar.append (spinner);
            tool (bar, "document-send-symbolic", _("Export Result"), () => export_result ());
            append (bar);

            buffer = new GtkSource.Buffer (null);
            var lang = GtkSource.LanguageManager.get_default ().get_language ("sql");
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
            apply_scheme (view, buffer, win.app.settings);
            words = new GtkSource.Buffer (null);
            provider = new GtkSource.CompletionWords (_("Database"));
            provider.minimum_word_size = 2;
            provider.register (words);
            provider.register (buffer);
            view.get_completion ().add_provider (provider);
            refresh_words ();
            win.catalog_changed.connect (refresh_words);
            var keys = new EventControllerKey ();
            keys.set_propagation_phase (PropagationPhase.CAPTURE);
            keys.key_pressed.connect ((kv, kc, st) => {
                bool ctrl = (st & Gdk.ModifierType.CONTROL_MASK) != 0;
                bool shift = (st & Gdk.ModifierType.SHIFT_MASK) != 0;
                if ((kv == Gdk.Key.Return || kv == Gdk.Key.KP_Enter) && ctrl) {
                    run_current (shift);
                    return true;
                }
                if (kv == Gdk.Key.Escape && running) {
                    stop ();
                    return true;
                }
                return false;
            });
            view.add_controller (keys);
            var escroll = new ScrolledWindow ();
            escroll.child = view;
            escroll.vexpand = true;

            var bottom = new Box (Orientation.VERTICAL, 0);
            result_strip = new Box (Orientation.HORIZONTAL, 2);
            result_strip.add_css_class ("db-result-strip");
            var rs_scroll = new ScrolledWindow ();
            rs_scroll.vscrollbar_policy = PolicyType.NEVER;
            rs_scroll.child = result_strip;
            bottom.append (rs_scroll);
            result_stack = new Stack ();
            result_stack.vexpand = true;
            messages = new TextView ();
            messages.editable = false;
            messages.monospace = true;
            messages.wrap_mode = WrapMode.WORD_CHAR;
            messages.left_margin = messages.right_margin = 12;
            messages.top_margin = 8;
            messages.add_css_class ("db-messages");
            var mscroll = new ScrolledWindow ();
            mscroll.child = messages;
            result_stack.add_named (mscroll, "messages");
            var empty = new Label (_("Run a statement to see its result here."));
            empty.add_css_class ("dim-label");
            result_stack.add_named (empty, "empty");
            result_stack.visible_child_name = "empty";
            bottom.append (result_stack);
            var foot = toolbar ();
            foot.add_css_class ("db-status-bar");
            status = new Label (_("Ctrl+Enter runs the statement at the cursor, Ctrl+Shift+Enter runs everything."));
            status.add_css_class ("db-status");
            status.xalign = 0;
            status.hexpand = true;
            status.ellipsize = Pango.EllipsizeMode.END;
            foot.append (status);
            bottom.append (foot);

            var paned = new Paned (Orientation.VERTICAL);
            paned.start_child = escroll;
            paned.end_child = bottom;
            paned.resize_start_child = true;
            paned.shrink_start_child = false;
            paned.shrink_end_child = false;
            paned.position = 260;
            paned.vexpand = true;
            append (paned);
            rebuild_strip ();
        }

        public static void apply_scheme (Widget view, GtkSource.Buffer buffer, GLib.Settings? settings) {
            var sm = GtkSource.StyleSchemeManager.get_default ();
            string id = settings != null ? settings.get_string ("sql-color-scheme") : "auto";
            var fg = view.get_color ();
            bool dark = Gtk.Settings.get_default ().gtk_application_prefer_dark_theme || (fg.red + fg.green + fg.blue) / 3 > 0.5;
            GtkSource.StyleScheme? scheme = null;
            if (id != "auto" && id != "") scheme = sm.get_scheme (id);
            if (scheme == null) scheme = sm.get_scheme (dark ? "Adwaita-dark" : "Adwaita");
            if (scheme == null) scheme = sm.get_scheme (dark ? "oblivion" : "classic");
            if (scheme != null) buffer.style_scheme = scheme;
        }

        public override void focus_content () {
            view.grab_focus ();
        }

        public override void closed () {
            if (cancel != null) cancel.cancel ();
            win.catalog_changed.disconnect (refresh_words);
            foreach (var r in results) if (r.cursor != null) win.release_cursor (r.cursor);
        }

        public void set_text (string text) {
            buffer.text = text;
        }

        private void refresh_words () {
            var set = new Gee.TreeSet<string> ();
            foreach (string w in win.completion_words ()) set.add (w);
            var sb = new StringBuilder ();
            foreach (string w in set) sb.append (w).append ("\n");
            words.text = sb.str;
        }

        private void format_sql () {
            TextIter a, b;
            if (buffer.get_selection_bounds (out a, out b)) {
                string t = buffer.get_text (a, b, true);
                buffer.begin_user_action ();
                buffer.delete (ref a, ref b);
                buffer.insert (ref a, Sql.format (t), -1);
                buffer.end_user_action ();
            } else {
                buffer.text = Sql.format (buffer.text);
            }
        }

        private string target_text (bool all) {
            TextIter a, b;
            if (buffer.get_selection_bounds (out a, out b)) return buffer.get_text (a, b, true);
            string text = buffer.text;
            if (all) return text;
            TextIter it;
            buffer.get_iter_at_mark (out it, buffer.get_insert ());
            int byte_off = text.index_of_nth_char (it.get_offset ());
            var st = SqlScript.statement_at (text, byte_off, win.config.kind);
            return st != null ? st.text : "";
        }

        private void run_current (bool all) {
            if (running) return;
            string sql = target_text (all);
            if (sql.strip () == "") {
                status.label = _("There is no statement to run.");
                return;
            }
            var list = SqlScript.split (sql, win.config.kind);
            bool risky = false;
            foreach (var s in list) if (SqlScript.is_destructive (s.text)) risky = true;
            if (risky) {
                win.confirm (_("Run a Destructive Statement?"), _("The script drops, empties or changes every row of a table:\n\n%s").printf (first_risky (list)), _("Run"), () => run_statements.begin (list));
                return;
            }
            run_statements.begin (list);
        }

        private static string first_risky (Gee.List<ScriptStatement> list) {
            foreach (var s in list) {
                if (SqlScript.is_destructive (s.text)) {
                    string t = s.text;
                    return t.length > 200 ? t.substring (0, t.index_of_nth_char (200)) + "..." : t;
                }
            }
            return "";
        }

        private void clear_results () {
            foreach (var r in results) if (r.cursor != null) win.release_cursor (r.cursor);
            results.clear ();
            messages.buffer.text = "";
            shown = null;
            var remove = new Gee.ArrayList<Widget> ();
            for (var c = result_stack.get_first_child (); c != null; c = c.get_next_sibling ()) {
                string? n = result_stack.get_page (c).name;
                if (n != "messages" && n != "empty") remove.add (c);
            }
            foreach (var w in remove) result_stack.remove (w);
            rebuild_strip ();
        }

        private void log (string text, bool error = false) {
            TextIter end;
            messages.buffer.get_end_iter (out end);
            if (error) {
                var tag = messages.buffer.tag_table.lookup ("error");
                if (tag == null) tag = messages.buffer.create_tag ("error", "foreground", "#e5484d");
                messages.buffer.insert_with_tags (ref end, text + "\n", -1, tag);
            } else {
                messages.buffer.insert (ref end, text + "\n", -1);
            }
        }

        private void set_running (bool on) {
            running = on;
            spinner.spinning = on;
            stop_btn.sensitive = on;
            run_btn.sensitive = !on;
            run_all_btn.sensitive = !on;
        }

        private void stop () {
            if (!running) return;
            if (cancel != null) cancel.cancel ();
            if (win.session.engine != null) win.engine.cancel_running ();
        }

        private static string short_sql (string sql) {
            string one = sql.strip ().replace ("\n", " ");
            while (one.contains ("  ")) one = one.replace ("  ", " ");
            return one.length > 90 ? one.substring (0, one.index_of_nth_char (90)) + "..." : one;
        }

        private async void run_statements (Gee.List<ScriptStatement> list) {
            clear_results ();
            set_running (true);
            cancel = new Cancellable ();
            var my = cancel;
            var total = new Timer ();
            int ok = 0;
            int n = 0;
            foreach (var st in list) {
                n++;
                bool last = n == list.size;
                var timer = new Timer ();
                try {
                    var e = yield win.ready ();
                    if (SqlScript.returns_rows (st.text)) {
                        var cursor = yield e.open_cursor (st.text, null, my);
                        var got = yield cursor.fetch (FIRST, my);
                        var res = new QueryResult ();
                        res.columns = cursor.columns;
                        res.rows = got;
                        res.elapsed_ms = timer.elapsed () * 1000;
                        var entry = new ResultEntry (_("Result %d").printf (results.size + 1), st.text, res);
                        if (!cursor.done) {
                            if (last) {
                                entry.cursor = cursor;
                                var ent = entry;
                                win.hold_cursor (cursor, () => {
                                    ent.cursor = null;
                                    update_result_status ();
                                    rebuild_strip ();
                                });
                            } else {
                                yield cursor.close_async ();
                                res.truncated = true;
                            }
                        } else {
                            win.release_cursor (cursor);
                        }
                        add_result (entry);
                        log ("%s\n  %s, %.1f ms%s".printf (short_sql (st.text), ngettext ("%d row", "%d rows", got.size).printf (got.size), res.elapsed_ms, entry.cursor != null || res.truncated ? _(", more available") : ""));
                    } else {
                        var r = yield e.execute (st.text, null, my);
                        foreach (string nt in r.notices) log ("  " + nt);
                        if (r.has_rows ()) {
                            add_result (new ResultEntry (_("Result %d").printf (results.size + 1), st.text, r));
                            log ("%s\n  %s, %.1f ms".printf (short_sql (st.text), ngettext ("%d row", "%d rows", r.rows.size).printf (r.rows.size), r.elapsed_ms));
                        } else {
                            string what = r.affected >= 0 ? ngettext ("%lld row affected", "%lld rows affected", (ulong) r.affected).printf (r.affected) : _("done");
                            log ("%s\n  %s %s, %.1f ms".printf (short_sql (st.text), r.command, what, r.elapsed_ms));
                        }
                    }
                    ok++;
                    win.session.history.add (st.text, timer.elapsed () * 1000, true, win.engine.current_database);
                } catch (Error err) {
                    if (Engines.is_cancelled (err)) {
                        log (_("Cancelled: %s").printf (short_sql (st.text)), true);
                    } else {
                        log ("%s\n  %s".printf (short_sql (st.text), err.message), true);
                        highlight_error (st);
                    }
                    win.session.history.add (st.text, timer.elapsed () * 1000, false, win.session.engine != null ? win.engine.current_database : "");
                    status.label = err.message;
                    status.add_css_class ("error");
                    show_messages ();
                    set_running (false);
                    rebuild_strip ();
                    return;
                }
            }
            set_running (false);
            status.remove_css_class ("error");
            status.label = ngettext ("%d statement ran in %.0f ms", "%d statements ran in %.0f ms", ok).printf (ok, total.elapsed () * 1000);
            if (results.size == 0) show_messages ();
            rebuild_strip ();
            bool ddl = false;
            foreach (var st in list) {
                string u = SqlScript.strip_comments (st.text).strip ().up ();
                if (u.has_prefix ("CREATE") || u.has_prefix ("DROP") || u.has_prefix ("ALTER") || u.has_prefix ("RENAME")) ddl = true;
            }
            if (ddl) win.load_catalog.begin ();
        }

        private void highlight_error (ScriptStatement st) {
            string text = buffer.text;
            if (!text.contains (st.text)) return;
            int at = text.index_of (st.text);
            TextIter a, b;
            buffer.get_iter_at_offset (out a, text.char_count (at));
            buffer.get_iter_at_offset (out b, text.char_count (at + st.text.length));
            buffer.select_range (a, b);
        }

        private void explain_current (bool analyze) {
            if (running) return;
            string sql = target_text (false).strip ();
            while (sql.has_suffix (";")) sql = sql.substring (0, sql.length - 1).strip ();
            if (sql == "") return;
            string ex = win.engine.explain_sql (sql, analyze);
            var one = new Gee.ArrayList<ScriptStatement> ();
            one.add (new ScriptStatement (ex, 0, ex.length));
            if (analyze && !SqlScript.returns_rows (sql)) {
                win.confirm (_("Run the Statement?"), _("Measuring the plan runs the statement for real, including its changes."), _("Run"), () => run_statements.begin (one));
                return;
            }
            run_statements.begin (one);
        }

        private void add_result (ResultEntry entry) {
            results.add (entry);
            bool plan = entry.result.columns.size == 1 && (entry.sql.strip ().up ().has_prefix ("EXPLAIN"));
            entry.plan = plan;
            Widget page;
            if (plan) {
                var tv = new TextView ();
                tv.editable = false;
                tv.monospace = true;
                tv.left_margin = 12;
                tv.top_margin = 8;
                var sb = new StringBuilder ();
                foreach (var r in entry.result.rows) sb.append (r.get (0).to_string ()).append ("\n");
                tv.buffer.text = sb.str;
                var sc = new ScrolledWindow ();
                sc.child = tv;
                page = sc;
            } else {
                var pane = new GridPane ();
                pane.grid.set_result (entry.result.columns, entry.result.rows, null);
                pane.grid.more_available = entry.cursor != null;
                pane.grid.need_more.connect (() => fetch_more.begin (entry, pane.grid));
                pane.grid.sort_requested.connect ((c) => sort_local (entry, pane.grid, c));
                pane.grid.cell_menu.connect ((x, y) => result_menu (pane.grid, x, y));
                pane.grid.cursor_moved.connect (() => update_result_status ());
                page = pane;
            }
            result_stack.add_named (page, "r%d".printf (results.size));
            show_result (entry);
        }

        private void sort_local (ResultEntry entry, ResultGrid grid, int c) {
            if (entry.cursor != null) {
                win.toast (_("Scroll to the end or add ORDER BY to sort every row."));
            }
            bool desc = grid.sort_col == c && !grid.sort_desc;
            entry.result.rows.sort ((a, b) => {
                int r = a.get (c).compare (b.get (c));
                return desc ? -r : r;
            });
            grid.sort_col = c;
            grid.sort_desc = desc;
            grid.rows_appended ();
        }

        private void result_menu (ResultGrid grid, double x, double y) {
            var menu = new ContextMenu (grid);
            var r = Gdk.Rectangle ();
            r.x = (int) x;
            r.y = (int) y;
            r.width = r.height = 1;
            menu.pointing_to = r;
            menu.add_item (_("Copy"), "edit-copy-symbolic", () => grid.copy_selection ());
            menu.add_item (_("Copy with Column Names"), "edit-copy-symbolic", () => grid.copy_selection (true));
            DatabaseWindow.popup_menu (menu);
        }

        private async void fetch_more (ResultEntry entry, ResultGrid grid) {
            if (entry.cursor == null || running || !win.cursor_active (entry.cursor)) {
                grid.more_available = false;
                grid.rows_appended ();
                return;
            }
            running = true;
            spinner.spinning = true;
            try {
                var got = yield entry.cursor.fetch (FIRST, null);
                entry.result.rows.add_all (got);
                if (entry.cursor.done) {
                    win.release_cursor (entry.cursor);
                    entry.cursor = null;
                }
            } catch (Error e) {
                status.label = e.message;
                if (entry.cursor != null) win.release_cursor (entry.cursor);
                entry.cursor = null;
            }
            running = false;
            spinner.spinning = false;
            grid.more_available = entry.cursor != null;
            grid.rows_appended ();
            update_result_status ();
            rebuild_strip ();
        }

        private void show_result (ResultEntry entry) {
            shown = entry;
            int idx = results.index_of (entry) + 1;
            result_stack.visible_child_name = "r%d".printf (idx);
            rebuild_strip ();
            update_result_status ();
        }

        private void show_messages () {
            shown = null;
            result_stack.visible_child_name = "messages";
            rebuild_strip ();
        }

        private void update_result_status () {
            if (shown == null || running) return;
            int n = shown.result.rows.size;
            string more = shown.cursor != null ? _(", more on scroll") : (shown.result.truncated ? _(", first rows only") : "");
            status.remove_css_class ("error");
            status.label = "%s%s   %.1f ms".printf (ngettext ("%d row", "%d rows", n).printf (n), more, shown.result.elapsed_ms);
        }

        private void rebuild_strip () {
            Widget? c;
            while ((c = result_strip.get_first_child ()) != null) result_strip.remove (c);
            result_buttons.clear ();
            foreach (var r in results) {
                string count = r.cursor != null ? "%d+".printf (r.result.rows.size) : r.result.rows.size.to_string ();
                var b = new Button.with_label ("%s  %s".printf (r.plan ? _("Plan") : r.title, count));
                b.add_css_class ("flat");
                b.add_css_class ("db-result-tab");
                if (r == shown) b.add_css_class ("active");
                b.tooltip_text = short_sql (r.sql);
                var rr = r;
                b.clicked.connect (() => show_result (rr));
                result_strip.append (b);
                result_buttons[r] = b;
            }
            var m = new Button.with_label (_("Messages"));
            m.add_css_class ("flat");
            m.add_css_class ("db-result-tab");
            if (shown == null && result_stack.visible_child_name == "messages") m.add_css_class ("active");
            m.clicked.connect (() => show_messages ());
            result_strip.append (m);
        }

        private void fill_history () {
            var pop = history_btn.popover;
            var box = new Box (Orientation.VERTICAL, 6);
            box.margin_start = box.margin_end = box.margin_top = box.margin_bottom = 8;
            box.width_request = 460;
            var search = new Gtk.SearchEntry ();
            search.placeholder_text = _("Search History");
            box.append (search);
            var list = new Box (Orientation.VERTICAL, 0);
            var sc = new ScrolledWindow ();
            sc.hscrollbar_policy = PolicyType.NEVER;
            sc.propagate_natural_height = true;
            sc.max_content_height = 420;
            sc.child = list;
            box.append (sc);
            var clear = new Button.with_label (_("Clear History"));
            clear.add_css_class ("flat");
            clear.halign = Align.END;
            clear.clicked.connect (() => {
                win.session.history.clear ();
                pop.popdown ();
            });
            box.append (clear);
            Callback fill = () => {
                Widget? ch;
                while ((ch = list.get_first_child ()) != null) list.remove (ch);
                string q = search.text.strip ().casefold ();
                int shown_n = 0;
                foreach (var h in win.session.history.entries) {
                    if (q != "" && !h.sql.casefold ().contains (q)) continue;
                    if (++shown_n > 200) break;
                    var b = new Button ();
                    b.add_css_class ("flat");
                    b.add_css_class ("db-history-row");
                    var vb = new Box (Orientation.VERTICAL, 2);
                    var t = new Label (short_sql (h.sql));
                    t.xalign = 0;
                    t.ellipsize = Pango.EllipsizeMode.END;
                    t.add_css_class ("monospace");
                    if (!h.ok) t.add_css_class ("error");
                    vb.append (t);
                    var when = new DateTime.from_unix_local (h.time);
                    var s = new Label ("%s   %.0f ms   %s".printf (when.format ("%x %X"), h.elapsed_ms, h.database));
                    s.xalign = 0;
                    s.add_css_class ("caption");
                    s.add_css_class ("dim-label");
                    vb.append (s);
                    b.child = vb;
                    string sql = h.sql;
                    b.clicked.connect (() => {
                        insert_sql (sql);
                        pop.popdown ();
                    });
                    list.append (b);
                }
                if (shown_n == 0) {
                    var l = new Label (_("No statements yet."));
                    l.add_css_class ("dim-label");
                    l.margin_top = l.margin_bottom = 12;
                    list.append (l);
                }
            };
            search.search_changed.connect (() => fill ());
            fill ();
            pop.child = box;
        }

        private delegate void Callback ();

        private void insert_sql (string sql) {
            TextIter a, b;
            if (buffer.get_selection_bounds (out a, out b)) buffer.delete (ref a, ref b);
            TextIter it;
            buffer.get_iter_at_mark (out it, buffer.get_insert ());
            string text = sql;
            if (buffer.text.strip () != "" && !it.starts_line ()) text = "\n" + text;
            if (!text.strip ().has_suffix (";")) text += ";";
            buffer.insert (ref it, text + "\n", -1);
            view.grab_focus ();
        }

        private void fill_snippets () {
            var pop = snippets_btn.popover;
            var store = SnippetStore.get_default ();
            var box = new Box (Orientation.VERTICAL, 6);
            box.margin_start = box.margin_end = box.margin_top = box.margin_bottom = 8;
            box.width_request = 380;
            var save_box = new Box (Orientation.HORIZONTAL, 6);
            var name = new Entry ();
            name.placeholder_text = _("Save the selection or the whole editor as");
            name.hexpand = true;
            save_box.append (name);
            var save = new Button.with_label (_("Save"));
            save.add_css_class ("suggested-action");
            save_box.append (save);
            box.append (save_box);
            var list = new Box (Orientation.VERTICAL, 0);
            var sc = new ScrolledWindow ();
            sc.hscrollbar_policy = PolicyType.NEVER;
            sc.propagate_natural_height = true;
            sc.max_content_height = 380;
            sc.child = list;
            box.append (sc);
            Callback fill = () => {
                Widget? ch;
                while ((ch = list.get_first_child ()) != null) list.remove (ch);
                foreach (var s in store.items) {
                    var row = new Box (Orientation.HORIZONTAL, 4);
                    var b = new Button ();
                    b.add_css_class ("flat");
                    b.hexpand = true;
                    var vb = new Box (Orientation.VERTICAL, 2);
                    var t = new Label (s.name);
                    t.xalign = 0;
                    vb.append (t);
                    var p = new Label (short_sql (s.sql));
                    p.xalign = 0;
                    p.ellipsize = Pango.EllipsizeMode.END;
                    p.add_css_class ("caption");
                    p.add_css_class ("dim-label");
                    vb.append (p);
                    b.child = vb;
                    string sql = s.sql;
                    b.clicked.connect (() => {
                        insert_sql (sql);
                        pop.popdown ();
                    });
                    row.append (b);
                    var del = new Button.from_icon_name ("user-trash-symbolic");
                    del.add_css_class ("flat");
                    del.valign = Align.CENTER;
                    del.tooltip_text = _("Delete Snippet");
                    string nm = s.name;
                    del.clicked.connect (() => {
                        try {
                            store.remove (nm);
                        } catch (Error e) {
                            win.toast (e.message);
                        }
                        fill_snippets ();
                    });
                    row.append (del);
                    list.append (row);
                }
                if (store.items.size == 0) {
                    var l = new Label (_("Saved snippets appear here in every connection."));
                    l.add_css_class ("dim-label");
                    l.wrap = true;
                    l.margin_top = l.margin_bottom = 12;
                    list.append (l);
                }
            };
            Callback do_save = () => {
                string n = name.text.strip ();
                string text = buffer.text.strip ();
                TextIter sa, sb2;
                if (buffer.get_selection_bounds (out sa, out sb2)) text = buffer.get_text (sa, sb2, true).strip ();
                if (n == "" || text == "") return;
                try {
                    store.put (n, text);
                    win.toast (_("Snippet %s saved").printf (n));
                } catch (Error e) {
                    win.toast (e.message);
                }
                name.text = "";
                fill ();
            };
            save.clicked.connect (() => do_save ());
            name.activate.connect (() => do_save ());
            fill ();
            pop.child = box;
        }

        private void export_result () {
            if (shown == null) {
                win.toast (_("Run a query first."));
                return;
            }
            string sql = shown.sql;
            ClientDialogs.export_query (win, sql, _("result"));
        }
    }

    public class UsersTab : ClientTab {
        private GridPane users;
        private GridPane privileges;
        private Label title;
        private Label status;
        private string current_user = "";

        public UsersTab (ClientWindow win) {
            base (win, "users");
            tab_title = _("Users");
            tab_icon = "db-users-symbolic";
            var bar = toolbar ();
            var l = new Label (_("Accounts and roles on this server"));
            l.add_css_class ("dim-label");
            l.margin_start = 6;
            bar.append (l);
            spacer (bar);
            tool (bar, "view-refresh-symbolic", _("Reload"), () => reload ());
            append (bar);
            var paned = new Paned (Orientation.VERTICAL);
            paned.vexpand = true;
            users = new GridPane ();
            users.grid.cursor_moved.connect (() => select_user ());
            paned.start_child = users;
            var bottom = new Box (Orientation.VERTICAL, 0);
            title = new Label (_("Select an account to see its privileges"));
            title.add_css_class ("db-sheet-title");
            title.xalign = 0;
            title.margin_start = 12;
            title.margin_top = 8;
            title.margin_bottom = 6;
            bottom.append (title);
            privileges = new GridPane ();
            privileges.vexpand = true;
            bottom.append (privileges);
            paned.end_child = bottom;
            paned.position = 300;
            append (paned);
            status = new Label ("");
            status.add_css_class ("db-status");
            status.xalign = 0;
            var foot = toolbar ();
            foot.add_css_class ("db-status-bar");
            foot.append (status);
            append (foot);
            reload ();
        }

        private QueryResult? current;

        public override void reload () {
            load.begin ();
        }

        private async void load () {
            try {
                var e = yield win.ready ();
                current = yield e.list_users ();
                users.grid.set_result (current.columns, current.rows, null);
                status.label = ngettext ("%d account", "%d accounts", current.rows.size).printf (current.rows.size);
                status.remove_css_class ("error");
            } catch (Error e) {
                status.label = e.message;
                status.add_css_class ("error");
            }
        }

        private void select_user () {
            if (current == null) return;
            int r = users.grid.cur_row;
            if (r < 0 || r >= current.rows.size) return;
            string user = current.rows[r].get (0).to_string ();
            int hi = current.index_of ("Host");
            if (hi >= 0) user = "'%s'@'%s'".printf (user, current.rows[r].get (hi).to_string ());
            if (user == current_user) return;
            current_user = user;
            load_privileges.begin (user);
        }

        private async void load_privileges (string user) {
            title.label = _("Privileges of %s").printf (user);
            try {
                var e = yield win.ready ();
                var p = yield e.list_privileges (user);
                if (user != current_user) return;
                privileges.grid.set_result (p.columns, p.rows, null);
            } catch (Error e) {
                title.label = e.message;
            }
        }
    }

    public class ActivityTab : ClientTab {
        private GridPane pane;
        private Label status;
        private Switch auto_switch;
        private uint timer_id;
        private QueryResult? current;
        private bool busy;

        public ActivityTab (ClientWindow win) {
            base (win, "activity");
            tab_title = _("Activity");
            tab_icon = "db-activity-symbolic";
            var bar = toolbar ();
            tool (bar, "view-refresh-symbolic", _("Reload"), () => reload ());
            var al = new Label (_("Refresh every 3 seconds"));
            al.margin_start = 8;
            bar.append (al);
            auto_switch = new Switch ();
            auto_switch.valign = Align.CENTER;
            auto_switch.notify["active"].connect (() => toggle_auto ());
            bar.append (auto_switch);
            spacer (bar);
            tool_text (bar, _("Cancel Query"), () => kill (false));
            var end = tool_text (bar, _("End Session"), () => kill (true));
            end.add_css_class ("destructive-action");
            end.remove_css_class ("flat");
            append (bar);
            pane = new GridPane ();
            pane.vexpand = true;
            append (pane);
            var foot = toolbar ();
            foot.add_css_class ("db-status-bar");
            status = new Label ("");
            status.add_css_class ("db-status");
            status.xalign = 0;
            foot.append (status);
            append (foot);
            reload ();
        }

        public override void closed () {
            if (timer_id != 0) Source.remove (timer_id);
            timer_id = 0;
        }

        private void toggle_auto () {
            if (timer_id != 0) Source.remove (timer_id);
            timer_id = 0;
            if (auto_switch.active) timer_id = Timeout.add_seconds (3, () => {
                if (!busy && get_mapped ()) reload ();
                return Source.CONTINUE;
            });
        }

        public override void reload () {
            load.begin ();
        }

        private async void load () {
            busy = true;
            try {
                var e = yield win.ready ();
                int keep = pane.grid.cur_row;
                current = yield e.list_activity ();
                pane.grid.set_result (current.columns, current.rows, null);
                if (keep > 0 && keep < current.rows.size) pane.grid.set_cursor (keep, 0, false);
                status.label = "%s   %s".printf (ngettext ("%d session", "%d sessions", current.rows.size).printf (current.rows.size), new DateTime.now_local ().format ("%X"));
                status.remove_css_class ("error");
            } catch (Error e) {
                status.label = e.message;
                status.add_css_class ("error");
            }
            busy = false;
        }

        private void kill (bool whole) {
            if (current == null || current.rows.size == 0) return;
            int r = pane.grid.cur_row;
            if (r < 0 || r >= current.rows.size) return;
            string id = current.rows[r].get (0).to_string ();
            string title = whole ? _("End Session %s?").printf (id) : _("Cancel the Query of Session %s?").printf (id);
            string msg = whole ? _("The client is disconnected and its open transaction is rolled back.") : _("The running statement stops with an error, the session stays connected.");
            win.confirm (title, msg, whole ? _("End Session") : _("Cancel Query"), () => do_kill.begin (id, whole));
        }

        private async void do_kill (string id, bool whole) {
            try {
                var e = yield win.ready ();
                yield e.kill_activity (id, whole);
                win.toast (whole ? _("Session %s ended").printf (id) : _("Query of session %s cancelled").printf (id));
            } catch (Error e) {
                win.show_error (_("Could Not Stop Session"), e.message);
            }
            reload ();
        }
    }
}
