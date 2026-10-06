using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Database {

    public class QueryDesigner : Box {
        public QueryDesign design;
        private weak QueryPage page;
        private DiagramCanvas canvas;
        private Grid grid;
        private DropDown type_dd;
        private Entry target;
        private CheckButton totals;
        private CheckButton distinct;
        private SpinButton limit;
        private Banner banner;
        private StatusPage empty;
        private bool building;

        public signal void changed ();

        public QueryDesigner (QueryPage page, QueryDesign d) {
            Object (orientation: Orientation.VERTICAL, spacing: 8);
            this.page = page;
            design = d;
            add_css_class ("db-pane-page");
            add_css_class ("db-dense");
            banner = new Banner (_("This query was changed in the SQL view, so the design no longer matches it."), BannerStyle.WARNING);
            banner.button_label = _("Keep the SQL");
            banner.secondary_label = _("Use the Design");
            banner.visible = false;
            banner.button_clicked.connect (() => page.change_mode ("sql"));
            banner.secondary_clicked.connect (() => {
                banner.visible = false;
                page.sql_edited = false;
                emit_changed ();
            });
            append (banner);
            var bar = new Box (Orientation.HORIZONTAL, 8);
            var tl = new Label (_("Query Type"));
            tl.add_css_class ("dim-label");
            bar.append (tl);
            string[] types = {};
            foreach (var qt in QueryType.ALL) types += qt.label ();
            type_dd = new DropDown.from_strings (types);
            type_dd.notify["selected"].connect (() => {
                if (building) return;
                design.query_type = QueryType.ALL[type_dd.selected];
                if (design.query_type == QueryType.CROSSTAB) design.totals = true;
                sync_options ();
                rebuild_grid ();
                emit_changed ();
            });
            bar.append (type_dd);
            target = new Entry ();
            target.placeholder_text = _("Target Table");
            target.width_chars = 16;
            target.changed.connect (() => {
                if (building) return;
                design.target = target.text.strip ();
                emit_changed ();
            });
            bar.append (target);
            totals = new CheckButton.with_label (_("Totals"));
            totals.tooltip_text = _("Group records and compute sums, averages and counts");
            totals.toggled.connect (() => {
                if (building) return;
                design.totals = totals.active;
                rebuild_grid ();
                emit_changed ();
            });
            bar.append (totals);
            distinct = new CheckButton.with_label (_("Unique Values"));
            distinct.toggled.connect (() => {
                if (building) return;
                design.distinct = distinct.active;
                emit_changed ();
            });
            bar.append (distinct);
            var ll = new Label (_("Top"));
            ll.add_css_class ("dim-label");
            ll.margin_start = 8;
            bar.append (ll);
            limit = new SpinButton.with_range (0, 1000000, 1);
            limit.tooltip_text = _("Return only the first records, zero for all");
            limit.value_changed.connect (() => {
                if (building) return;
                design.limit = (int) limit.value;
                emit_changed ();
            });
            bar.append (limit);
            var params_b = new Button.with_label (_("Parameters…"));
            params_b.tooltip_text = _("Declare the values the query asks for when it runs");
            params_b.clicked.connect (() => edit_parameters ());
            bar.append (params_b);
            append (bar);
            canvas = new DiagramCanvas ();
            var cscroll = new ScrolledWindow ();
            cscroll.child = canvas;
            cscroll.height_request = 240;
            cscroll.vexpand = true;
            var overlay = new Overlay ();
            overlay.child = cscroll;
            empty = new StatusPage ();
            empty.icon_name = "system-search";
            empty.title = _("Add Tables");
            empty.description = _("Choose the tables and queries to combine. Double-click a field to add it as a column.");
            var add_b = new Button.with_label (_("Add Table"));
            add_b.add_css_class ("suggested-action");
            add_b.halign = Align.CENTER;
            add_b.clicked.connect (() => add_table_menu ());
            empty.child = add_b;
            overlay.add_overlay (empty);
            var paned = new Paned (Orientation.VERTICAL);
            paned.start_child = overlay;
            paned.resize_start_child = true;
            paned.shrink_start_child = false;
            grid = new Grid ();
            grid.add_css_class ("db-query-grid");
            grid.column_spacing = 8;
            grid.row_spacing = 4;
            grid.margin_top = 8;
            var gscroll = new ScrolledWindow ();
            gscroll.child = grid;
            gscroll.height_request = 260;
            gscroll.vexpand = true;
            paned.end_child = gscroll;
            paned.resize_end_child = true;
            paned.shrink_end_child = false;
            paned.vexpand = true;
            append (paned);
            canvas.link_created.connect ((a, af, b, bf) => {
                design.joins.add (new QueryJoin (a, af, b, bf));
                refresh_canvas ();
                emit_changed ();
            });
            canvas.link_activated.connect ((i) => edit_join (i));
            canvas.link_delete.connect ((i) => {
                design.joins.remove_at (i);
                refresh_canvas ();
                emit_changed ();
            });
            canvas.link_menu.connect ((i, x, y) => {
                var menu = new ContextMenu (canvas);
                menu.pointing_to = point (x, y);
                menu.add_item (_("Join Properties…"), "document-edit-symbolic", () => edit_join (i));
                menu.add_separator ();
                menu.add_item (_("Delete Join"), "user-trash-symbolic", () => {
                    design.joins.remove_at (i);
                    refresh_canvas ();
                    emit_changed ();
                }, "destructive");
                DatabaseWindow.popup_menu (menu);
            });
            canvas.box_menu.connect ((id, x, y) => {
                var menu = new ContextMenu (canvas);
                menu.pointing_to = point (x, y);
                menu.add_item (_("Add All Fields"), "list-add-symbolic", () => {
                    design.add_column (id, "*");
                    rebuild_grid ();
                    emit_changed ();
                });
                menu.add_separator ();
                menu.add_item (_("Remove Table"), "list-remove-symbolic", () => {
                    design.remove_table (id);
                    refresh_canvas ();
                    rebuild_grid ();
                    emit_changed ();
                }, "destructive");
                DatabaseWindow.popup_menu (menu);
            });
            canvas.field_activated.connect ((id, f) => {
                design.add_column (id, f);
                rebuild_grid ();
                emit_changed ();
            });
            canvas.box_moved.connect ((id) => {
                var b = canvas.find (id);
                var t = design.find_table (id);
                if (b != null && t != null) {
                    t.x = b.x;
                    t.y = b.y;
                    emit_changed ();
                }
            });
            load (d);
        }

        private Gdk.Rectangle point (double x, double y) {
            var r = Gdk.Rectangle ();
            r.x = (int) x;
            r.y = (int) y;
            r.width = r.height = 1;
            return r;
        }

        public void show_stale (bool stale) {
            banner.visible = stale;
        }

        public void load (QueryDesign d) {
            design = d;
            building = true;
            for (int i = 0; i < QueryType.ALL.length; i++) if (QueryType.ALL[i] == d.query_type) type_dd.selected = i;
            target.text = d.target;
            totals.active = d.totals;
            distinct.active = d.distinct;
            limit.value = d.limit;
            building = false;
            sync_options ();
            refresh_canvas ();
            rebuild_grid ();
        }

        private void edit_parameters () {
            var dlg = Dialogs.make (page.win, _("Query Parameters"), 520, 520);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (_("Parameters"), _("Use the names in brackets in the criteria, for example >= [Start Date]."));
            string[] types = { "Text", "Long", "Double", "Currency", "DateTime", "YesNo" };
            var names = new Gee.ArrayList<EntryRow> ();
            var kinds = new Gee.ArrayList<SelectionRow> ();
            for (int i = 0; i < design.params.size + 3; i++) {
                var p = i < design.params.size ? design.params[i] : null;
                var n = new EntryRow (_("Parameter %d").printf (i + 1));
                n.text = p != null ? p.name : "";
                var t = new SelectionRow (_("Data Type"), types, p != null && p.type_name != "" ? p.type_name : types[0]);
                g.add_row (n);
                g.add_row (t);
                names.add (n);
                kinds.add (t);
            }
            box.append (g);
            Dialogs.footer (dlg, _("Apply"), () => {
                design.params.clear ();
                for (int i = 0; i < names.size; i++) {
                    string n = names[i].text.strip ();
                    if (n.has_prefix ("[") && n.has_suffix ("]")) n = n.substring (1, n.length - 2);
                    if (n != "") design.params.add (new QueryParam (n, kinds[i].current_value));
                }
                emit_changed ();
                return true;
            });
            dlg.open_dialog ();
        }

        private void sync_options () {
            bool sel = design.query_type == QueryType.SELECT || design.query_type == QueryType.MAKE_TABLE || design.query_type == QueryType.CROSSTAB;
            target.visible = design.query_type == QueryType.MAKE_TABLE || design.query_type == QueryType.APPEND;
            target.placeholder_text = design.query_type == QueryType.MAKE_TABLE ? _("New Table Name") : _("Table to Append To");
            totals.visible = sel && design.query_type != QueryType.CROSSTAB;
            distinct.visible = sel && design.query_type != QueryType.CROSSTAB;
            limit.sensitive = sel;
        }

        private void emit_changed () {
            if (!building) changed ();
        }

        public void refresh_canvas () {
            canvas.boxes.clear ();
            canvas.links.clear ();
            foreach (var t in design.tables) {
                var box = new DiagramBox (t.alias, t.alias == t.name ? t.name : "%s (%s)".printf (t.alias, t.name));
                string[] fields = { "*" };
                string[] keys = {};
                try {
                    if (page.db.object_exists (t.name, "table")) {
                        foreach (var f in page.db.load_table (t.name).fields) {
                            fields += f.name;
                            if (f.primary_key) keys += f.name;
                        }
                    } else {
                        foreach (string c in page.db.view_columns (t.name)) fields += c;
                    }
                } catch (Error e) {
                }
                box.fields = fields;
                box.keys = keys;
                box.x = t.x;
                box.y = t.y;
                canvas.boxes.add (box);
            }
            foreach (var j in design.joins) {
                var l = new DiagramLink (j.left, j.left_field, j.right, j.right_field);
                if (j.kind != JoinKind.INNER) l.badge = j.kind == JoinKind.LEFT ? _("left") : (j.kind == JoinKind.RIGHT ? _("right") : _("full"));
                canvas.links.add (l);
            }
            canvas.update_size ();
            empty.visible = design.tables.size == 0;
        }

        private void edit_join (int i) {
            var j = design.joins[i];
            var dlg = Dialogs.make (page.win, _("Join Properties"), 460, 400);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (_("Join"), "%s.%s = %s.%s".printf (j.left, j.left_field, j.right, j.right_field));
            string[] labels = {
                _("Only rows where both tables match"),
                _("All rows from \"%s\" and matching rows from \"%s\"").printf (j.left, j.right),
                _("All rows from \"%s\" and matching rows from \"%s\"").printf (j.right, j.left),
                _("All rows from both tables")
            };
            JoinKind[] kinds = { JoinKind.INNER, JoinKind.LEFT, JoinKind.RIGHT, JoinKind.FULL };
            string cur = labels[0];
            for (int k = 0; k < 4; k++) if (kinds[k] == j.kind) cur = labels[k];
            var sel = new SelectionRow (_("Include"), labels, cur);
            g.add_row (sel);
            box.append (g);
            Dialogs.footer (dlg, _("Apply"), () => {
                for (int k = 0; k < 4; k++) if (labels[k] == sel.current_value) j.kind = kinds[k];
                refresh_canvas ();
                emit_changed ();
                return true;
            });
            dlg.open_dialog ();
        }

        public void add_table_menu () {
            var pop = new Popover ();
            pop.add_css_class ("menu");
            var box = new Box (Orientation.VERTICAL, 2);
            box.margin_start = box.margin_end = box.margin_top = box.margin_bottom = 6;
            var names = new Gee.ArrayList<string> ();
            names.add_all (page.db.table_names ());
            var views = page.db.view_names ();
            foreach (string n in names) box.append (table_button (pop, n, "db-table-symbolic"));
            if (views.size > 0) box.append (new Separator (Orientation.HORIZONTAL));
            foreach (string n in views) {
                if (n != page.object_name) box.append (table_button (pop, n, "db-query-symbolic"));
            }
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.propagate_natural_height = true;
            scroll.max_content_height = 420;
            scroll.child = box;
            pop.child = scroll;
            page.win.popup_at_bubble (pop, "add-table");
        }

        private Widget table_button (Popover pop, string name, string icon) {
            var b = new Button ();
            b.add_css_class ("flat");
            var row = new Box (Orientation.HORIZONTAL, 10);
            row.append (new Image.from_icon_name (icon));
            var l = new Label (name);
            l.halign = Align.START;
            row.append (l);
            b.child = row;
            b.clicked.connect (() => {
                pop.popdown ();
                add_table (name);
            });
            return b;
        }

        public void add_table (string name) {
            var t = design.add_table (name);
            double x = 24;
            foreach (var o in design.tables) {
                if (o != t) x = double.max (x, o.x + 250);
            }
            t.x = x;
            t.y = 24;
            design.auto_join (page.db);
            refresh_canvas ();
            emit_changed ();
        }

        private string[] field_choices (out Gee.ArrayList<string> tables_of, out Gee.ArrayList<string> fields_of) {
            string[] labels = {};
            tables_of = new Gee.ArrayList<string> ();
            fields_of = new Gee.ArrayList<string> ();
            foreach (var t in design.tables) {
                labels += "%s.*".printf (t.alias);
                tables_of.add (t.alias);
                fields_of.add ("*");
                string[] cols = page.db.columns_of (t.name);
                foreach (string c in cols) {
                    labels += "%s.%s".printf (t.alias, c);
                    tables_of.add (t.alias);
                    fields_of.add (c);
                }
            }
            labels += _("Expression…");
            tables_of.add ("");
            fields_of.add ("");
            return labels;
        }

        private Label head (string text) {
            var l = new Label (text);
            l.add_css_class ("db-grid-label");
            l.halign = Align.END;
            return l;
        }

        public void rebuild_grid () {
            building = true;
            Widget? c;
            while ((c = grid.get_first_child ()) != null) grid.remove (c);
            bool upd = design.query_type == QueryType.UPDATE;
            bool app = design.query_type == QueryType.APPEND;
            bool del = design.query_type == QueryType.DELETE;
            bool xtab = design.query_type == QueryType.CROSSTAB;
            string[] rows = { _("Field"), _("Alias") };
            if ((design.totals || xtab) && !upd && !del && !app) rows += _("Total");
            if (xtab) rows += _("Crosstab");
            if (!upd && !del && !app) rows += _("Sort");
            if (!upd && !del && !app) rows += _("Show");
            if (upd) rows += _("Update To");
            if (app) rows += _("Append To");
            int crit_rows = int.max (2, design.criteria_rows () + 1);
            rows += _("Criteria");
            for (int i = 1; i < crit_rows; i++) rows += _("Or");
            for (int r = 0; r < rows.length; r++) grid.attach (head (rows[r]), 0, r, 1, 1);
            Gee.ArrayList<string> tables_of, fields_of;
            string[] choices = field_choices (out tables_of, out fields_of);
            string[] target_cols = {};
            if (app && design.target != "") target_cols = page.db.columns_of (design.target);
            for (int ci = 0; ci < design.columns.size; ci++) {
                var col = design.columns[ci];
                int r = 0;
                var fbox = new Box (Orientation.HORIZONTAL, 2);
                var field = new DropDown.from_strings (choices);
                field.width_request = 170;
                uint sel = choices.length - 1;
                for (int k = 0; k < tables_of.size; k++) {
                    if (col.expression == "" && tables_of[k] == col.table && fields_of[k] == col.field) sel = k;
                }
                field.selected = sel;
                fbox.append (field);
                var menu_b = new Button.from_icon_name ("view-more-symbolic");
                menu_b.add_css_class ("flat");
                menu_b.tooltip_text = _("Column Options");
                int index = ci;
                menu_b.clicked.connect (() => {
                    var menu = new ContextMenu (menu_b);
                    if (index > 0) menu.add_item (_("Move Left"), "go-previous-symbolic", () => move_col (index, -1));
                    if (index < design.columns.size - 1) menu.add_item (_("Move Right"), "go-next-symbolic", () => move_col (index, 1));
                    menu.add_separator ();
                    menu.add_item (_("Remove Column"), "list-remove-symbolic", () => {
                        design.columns.remove_at (index);
                        rebuild_grid ();
                        emit_changed ();
                    }, "destructive");
                    DatabaseWindow.popup_menu (menu);
                });
                fbox.append (menu_b);
                grid.attach (fbox, ci + 1, r++, 1, 1);
                var alias = new Entry ();
                alias.placeholder_text = col.expression != "" || fields_of.size == 0 ? _("Expression") : _("Name");
                var expr = new Entry ();
                expr.placeholder_text = _("Expression, e.g. [Qty] * [Price]");
                expr.text = col.expression;
                alias.text = col.alias;
                alias.changed.connect (() => {
                    if (building) return;
                    col.alias = alias.text.strip ();
                    emit_changed ();
                });
                var abox = new Box (Orientation.VERTICAL, 2);
                if (col.expression != "" || sel == choices.length - 1) {
                    expr.changed.connect (() => {
                        if (building) return;
                        col.expression = expr.text.strip ();
                        emit_changed ();
                    });
                    abox.append (expr);
                }
                alias.placeholder_text = _("Name");
                abox.append (alias);
                grid.attach (abox, ci + 1, r++, 1, 1);
                field.notify["selected"].connect (() => {
                    if (building) return;
                    int k = (int) field.selected;
                    if (k >= tables_of.size || tables_of[k] == "") {
                        col.table = "";
                        col.field = "";
                        if (col.expression == "") col.expression = "1";
                    } else {
                        col.table = tables_of[k];
                        col.field = fields_of[k];
                        col.expression = "";
                    }
                    Idle.add (() => {
                        rebuild_grid ();
                        return Source.REMOVE;
                    });
                    emit_changed ();
                });
                if ((design.totals || xtab) && !upd && !del && !app) {
                    string[] aggs = {};
                    foreach (var a in Aggregate.ALL) aggs += a.label ();
                    var total = new DropDown.from_strings (aggs);
                    for (int k = 0; k < Aggregate.ALL.length; k++) if (Aggregate.ALL[k] == col.total) total.selected = k;
                    total.notify["selected"].connect (() => {
                        if (building) return;
                        col.total = Aggregate.ALL[total.selected];
                        emit_changed ();
                    });
                    grid.attach (total, ci + 1, r++, 1, 1);
                }
                if (xtab) {
                    string[] roles = { "", "row", "column", "value" };
                    var role = new DropDown.from_strings ({ _("Not Shown"), _("Row Heading"), _("Column Heading"), _("Value") });
                    for (int k = 0; k < roles.length; k++) if (roles[k] == col.crosstab) role.selected = k;
                    role.notify["selected"].connect (() => {
                        if (building) return;
                        col.crosstab = roles[role.selected];
                        if (col.crosstab == "row" || col.crosstab == "column") col.total = Aggregate.GROUP_BY;
                        else if (col.crosstab == "value" && !col.total.is_aggregate ()) col.total = Aggregate.SUM;
                        Idle.add (() => {
                            rebuild_grid ();
                            return Source.REMOVE;
                        });
                        emit_changed ();
                    });
                    grid.attach (role, ci + 1, r++, 1, 1);
                }
                if (!upd && !del && !app) {
                    var sort = new DropDown.from_strings ({ _("Not Sorted"), _("Ascending"), _("Descending") });
                    sort.selected = (uint) col.sort;
                    sort.notify["selected"].connect (() => {
                        if (building) return;
                        col.sort = (SortOrder) sort.selected;
                        emit_changed ();
                    });
                    grid.attach (sort, ci + 1, r++, 1, 1);
                    var show = new CheckButton ();
                    show.active = col.show;
                    show.halign = Align.CENTER;
                    show.toggled.connect (() => {
                        if (building) return;
                        col.show = show.active;
                        emit_changed ();
                    });
                    grid.attach (show, ci + 1, r++, 1, 1);
                }
                if (upd) {
                    var to = new Entry ();
                    to.placeholder_text = _("New value or =[Field] * 2");
                    to.text = col.update_to;
                    to.changed.connect (() => {
                        if (building) return;
                        col.update_to = to.text;
                        emit_changed ();
                    });
                    grid.attach (to, ci + 1, r++, 1, 1);
                }
                if (app) {
                    string[] opts = { _("Do Not Append") };
                    foreach (string t in target_cols) opts += t;
                    var to = new DropDown.from_strings (opts);
                    for (int k = 1; k < opts.length; k++) if (opts[k] == col.append_to) to.selected = k;
                    to.notify["selected"].connect (() => {
                        if (building) return;
                        col.append_to = to.selected == 0 ? "" : opts[to.selected];
                        emit_changed ();
                    });
                    grid.attach (to, ci + 1, r++, 1, 1);
                }
                for (int k = 0; k < crit_rows; k++) {
                    var e = new Entry ();
                    e.text = col.criterion (k);
                    e.placeholder_text = k == 0 ? _("e.g. > 100 or Like \"A*\"") : "";
                    int row_index = k;
                    e.changed.connect (() => {
                        if (building) return;
                        col.set_criterion (row_index, e.text);
                        emit_changed ();
                    });
                    e.activate.connect (() => page.win.run ("run"));
                    var f = new EventControllerFocus ();
                    f.leave.connect (() => {
                        if (row_index == crit_rows - 1 && e.text.strip () != "") rebuild_grid ();
                    });
                    e.add_controller (f);
                    grid.attach (e, ci + 1, r++, 1, 1);
                }
            }
            var add = new Button.from_icon_name ("list-add-symbolic");
            add.tooltip_text = _("Add Column");
            add.valign = Align.START;
            add.clicked.connect (() => {
                if (design.tables.size == 0) {
                    page.win.toast (_("Add a table first."));
                    return;
                }
                design.add_column (design.tables[0].alias, "*");
                rebuild_grid ();
                emit_changed ();
            });
            grid.attach (add, design.columns.size + 1, 0, 1, 1);
            building = false;
        }

        private void move_col (int i, int delta) {
            var c = design.columns.remove_at (i);
            design.columns.insert (i + delta, c);
            rebuild_grid ();
            emit_changed ();
        }
    }

    public class QueryPage : ObjectPage {
        public bool unsaved;
        public bool sql_edited;
        public bool action_query;
        public string pass_through = "";
        private Stack stack;
        private QueryDesigner designer;
        private SqlEditor editor;
        private Box results_box;
        private TablePage? results;
        private string saved_sql = "";
        private string saved_design = "";
        private bool syncing;
        private static int counter;

        public QueryPage (DatabaseWindow win, string name) throws Error {
            base (win, "query", name);
            QueryDesign? design = null;
            string sql = "";
            var saved = SavedQueries.load (win.db, name);
            if (saved == null) throw new SchemaError.NOT_FOUND (_("The query \"%s\" does not exist.").printf (name));
            sql = saved.sql;
            if (saved.design != "") design = QueryDesign.from_json (saved.design);
            action_query = !QueryPrep.is_select_like (sql);
            pass_through = saved.connection;
            bool matches = false;
            if (design != null) {
                try {
                    matches = design.to_sql ().strip () == sql.strip ();
                } catch (Error e) {
                }
            }
            build (design ?? new QueryDesign ());
            editor.text = sql;
            sql_edited = design == null || !matches;
            saved_sql = sql;
            saved_design = designer.design.to_json ();
            if (sql_edited) {
                mode = "results";
                if (action_query) mode = "sql";
            } else {
                mode = action_query ? "design" : "results";
            }
            stack.visible_child_name = mode;
            if (mode == "results") run_select (sql);
        }

        public QueryPage.untitled (DatabaseWindow win, bool sql) {
            base (win, "query", "\n%d".printf (++counter));
            unsaved = true;
            build (new QueryDesign ());
            mode = sql ? "sql" : "design";
            stack.visible_child_name = mode;
            if (sql) {
                var tables = win.db.table_names ();
                editor.text = tables.size > 0 ? "SELECT *\nFROM %s\nLIMIT 100".printf (Sql.quote_ident (tables[0])) : "SELECT 1";
                sql_edited = true;
            }
        }

        private void build (QueryDesign d) {
            add_css_class ("db-content");
            stack = new Stack ();
            stack.transition_type = StackTransitionType.CROSSFADE;
            stack.vexpand = true;
            designer = new QueryDesigner (this, d);
            designer.changed.connect (() => {
                if (!sql_edited) {
                    try {
                        syncing = true;
                        editor.text = designer.design.to_sql ();
                        syncing = false;
                    } catch (Error e) {
                        syncing = false;
                    }
                }
                title_changed ();
                win.sync_bubbles ();
            });
            stack.add_named (designer, "design");
            editor = new SqlEditor (win.db, win.app.settings);
            editor.add_css_class ("db-pane-page");
            editor.buffer.changed.connect (() => {
                if (syncing) return;
                sql_edited = true;
                designer.show_stale (true);
                title_changed ();
                win.sync_bubbles ();
            });
            editor.run_requested.connect ((s) => execute (s));
            var target_bar = new Box (Orientation.HORIZONTAL, 8);
            var tl = new Label (_("Run On"));
            tl.add_css_class ("dim-label");
            target_bar.append (tl);
            string[] targets = { _("This Database") };
            string[] ids = { "" };
            foreach (var c in ConnectionStore.get_default ().items) {
                targets += _("Server: %s").printf (c.name);
                ids += c.id;
            }
            var target_dd = new DropDown.from_strings (targets);
            for (int i = 0; i < ids.length; i++) if (ids[i] != "" && ids[i] == pass_through) target_dd.selected = i;
            target_dd.notify["selected"].connect (() => {
                pass_through = ids[target_dd.selected];
                title_changed ();
                win.sync_bubbles ();
            });
            target_dd.tooltip_text = _("A query run on a server is a pass-through query: the SQL goes to the server unchanged.");
            target_bar.append (target_dd);
            if (ids.length > 1 || pass_through != "") editor.prepend (target_bar);
            stack.add_named (editor, "sql");
            results_box = new Box (Orientation.VERTICAL, 0);
            stack.add_named (results_box, "results");
            append (stack);
            designer.show_stale (false);
        }

        public override string title () {
            string n = unsaved ? _("Query %s").printf (object_name.strip ()) : object_name;
            return n + (dirty () ? " *" : "");
        }

        public override string[] modes () {
            return { "design", "sql", "results" };
        }

        public override string mode_label (string m) {
            if (m == "results") return _("Results");
            return base.mode_label (m);
        }

        public override void change_mode (string m) {
            if (m == mode) return;
            if (m == "results") {
                run_select (current_sql ());
                return;
            }
            if (m == "sql" && !sql_edited) {
                try {
                    syncing = true;
                    editor.text = Sql.format (designer.design.to_sql ());
                    syncing = false;
                } catch (Error e) {
                    syncing = false;
                }
            }
            if (m == "design") designer.show_stale (sql_edited);
            if (m == "sql") editor.refresh_words ();
            stack.visible_child_name = m;
            base.change_mode (m);
        }

        public string current_sql () {
            if (!sql_edited) {
                try {
                    return designer.design.to_sql ();
                } catch (Error e) {
                    return editor.text;
                }
            }
            return editor.text;
        }

        public override string[] bubbles () {
            switch (mode) {
                case "design": return { "run", "add-table" };
                case "sql": return { "run" };
                default:
                    string[] b = { "run" };
                    if (results != null) foreach (string x in results.bubbles ()) b += x;
                    return b;
            }
        }

        public override bool dirty () {
            if (unsaved) return designer.design.tables.size > 0 || (sql_edited && editor.text.strip () != "");
            if (sql_edited) return editor.text.strip () != saved_sql.strip ();
            return designer.design.to_json () != saved_design;
        }

        public override bool handles (string action) {
            if (action == "run" || action == "add-table") return true;
            if (mode == "results" && results != null) return results.handles (action);
            return false;
        }

        public override void run_action (string action, Variant? param) {
            if (action == "run") {
                execute (mode == "sql" ? editor.statement_to_run () : current_sql ());
                return;
            }
            if (action == "add-table") {
                if (mode != "design") change_mode ("design");
                designer.add_table_menu ();
                return;
            }
            if (results != null) results.run_action (action, param);
        }

        public override void search (string text) {
            if (results != null) results.search (text);
        }

        public override string search_text () {
            return results != null ? results.search_text () : "";
        }

        public override void reload () {
            if (results != null && mode == "results") results.reload ();
            designer.refresh_canvas ();
        }

        private bool run_select (string sql) {
            if (pass_through != "") {
                win.run_pass_through (pass_through, sql, results_box, (err) => editor.show_message (err, true));
                return true;
            }
            if (!QueryPrep.is_select_like (sql)) {
                win.toast (_("This is an action query. Use Run to apply it."));
                return false;
            }
            string s = sql;
            ParamPrompt.resolve (win, s, (vals) => {
                if (vals == null) return;
                try {
                    string final_sql = QueryPrep.prepare (win.db, s, vals);
                    var src = new RecordSource.for_sql (win.db, final_sql);
                    src.count ();
                    var page = new TablePage.results (win, src);
                    if (unsaved) page.object_name = title ();
                    else page.object_name = object_name;
                    Widget? c;
                    while ((c = results_box.get_first_child ()) != null) results_box.remove (c);
                    results_box.append (page);
                    page.vexpand = true;
                    results = page;
                    if (mode != "results") {
                        stack.visible_child_name = "results";
                        base.change_mode ("results");
                    }
                    win.sync_bubbles ();
                } catch (Error e) {
                    editor.show_message (e.message, true);
                    if (mode != "sql") {
                        stack.visible_child_name = "sql";
                        base.change_mode ("sql");
                    }
                }
            });
            return false;
        }

        private void execute (string sql) {
            string s = sql.strip ();
            if (s == "") return;
            if (pass_through != "" || (QueryPrep.is_select_like (s) && Sql.split_statements (s).size <= 1) || QueryPrep.kind_of (s) == "parameter" || QueryPrep.kind_of (s) == "crosstab") {
                editor.show_message ("", false);
                run_select (s);
                return;
            }
            var declared = new Gee.ArrayList<QueryParam> ();
            string body = QueryPrep.strip_parameters (s, declared);
            var unresolved = QueryPrep.find_parameters (win.db, s);
            if (unresolved.size > 0) {
                ParamPrompt.resolve (win, s, (vals) => {
                    if (vals == null) return;
                    try {
                        execute (QueryPrep.prepare (win.db, s, vals));
                    } catch (Error e) {
                        win.show_error (_("Could Not Run the Query"), e.message);
                    }
                });
                return;
            }
            s = body;
            var d = designer.design;
            bool from_design = !sql_edited && mode != "sql";
            string label = from_design ? d.query_type.label () : _("Run SQL");
            var dlg = new ConfirmDialog (win.app, _("Run This Action Query?"), "dialog-warning",
                from_design ? _("The query changes data in the database. You can undo it with Ctrl+Z.") : _("The statements change the database directly. Changes made from the SQL view cannot be undone."),
                _("Run"), from_design ? ConfirmDialog.ActionStyle.SUGGESTED : ConfirmDialog.ActionStyle.DESTRUCTIVE);
            dlg.transient_for = win;
            dlg.response.connect ((r) => {
                if (r != ConfirmDialog.Response.PRIMARY) return;
                try {
                    int changed = 0;
                    if (from_design && d.tables.size > 0) {
                        string[] names = { d.query_type == QueryType.MAKE_TABLE || d.query_type == QueryType.APPEND ? d.target : d.tables[0].name };
                        win.db.design_change (label, names, () => {
                            changed = win.db.run (s);
                        });
                        win.db.data_changed ("");
                    } else {
                        ResultSet? last;
                        changed = win.db.execute_script (s, out last);
                        if (last != null) {
                            editor.show_message (ngettext ("%d row returned", "%d rows returned", last.rows.size).printf (last.rows.size), false);
                        }
                    }
                    editor.show_message (ngettext ("%d record changed.", "%d records changed.", changed).printf (changed), false);
                    win.toast (ngettext ("%d record changed", "%d records changed", changed).printf (changed));
                    win.rebuild_sidebar ();
                } catch (Error e) {
                    editor.show_message (e.message, true);
                    win.show_error (_("Could Not Run the Query"), e.message);
                }
                win.sync_bubbles ();
            });
            dlg.present ();
        }

        public override bool save () {
            if (unsaved) {
                ask_name ();
                return false;
            }
            return store (object_name, null);
        }

        private void ask_name () {
            var dlg = Dialogs.make (win, _("Save Query"), 420, 240);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (_("Query"), null);
            var name = new EntryRow (_("Name"));
            name.text = win.db.unique_object_name (_("Query"));
            g.add_row (name);
            box.append (g);
            Dialogs.footer (dlg, _("Save"), () => {
                string n = name.text.strip ();
                if (n == "") return false;
                if (win.db.object_exists (n) || win.db.get_meta ("action:" + n) != null) {
                    win.show_error (_("Could Not Save"), _("An object named \"%s\" already exists.").printf (n));
                    return false;
                }
                string old_key = key ();
                if (!store (n, null)) return false;
                unsaved = false;
                object_name = n;
                win.adopt_page (this, old_key);
                title_changed ();
                return true;
            });
            dlg.open_dialog ();
        }

        private bool store (string name, string? old) {
            string sql = current_sql ().strip ();
            while (sql.has_suffix (";")) sql = sql.substring (0, sql.length - 1).strip ();
            try {
                string design = sql_edited ? "" : designer.design.to_json ();
                SavedQueries.save (win.db, name, sql, design, pass_through);
                action_query = !QueryPrep.is_select_like (sql);
                saved_sql = sql;
                saved_design = designer.design.to_json ();
                win.rebuild_sidebar ();
                win.toast (_("Query saved"));
                title_changed ();
                return true;
            } catch (Error e) {
                win.show_error (_("Could Not Save the Query"), e.message);
                return false;
            }
        }
    }
}
