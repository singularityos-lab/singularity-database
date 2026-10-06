using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Database {

    public class TablePage : ObjectPage {
        public RecordSource? src;
        public DatasheetView sheet;
        private Stack stack;
        private Stack view_stack;
        private ScrolledWindow sheet_scroll;
        private Box data_box;
        private TableDesigner? designer;
        private Gee.ArrayList<ViewDef> views = new Gee.ArrayList<ViewDef> ();
        private int view_index;
        private Widget? board;
        private Entry record_entry;
        private Label count_label;
        private Box filter_info;
        private Label filter_label;
        private Label status_label;
        private Button new_btn;
        private StatusPage empty_page;
        private uint save_state_id;
        private bool is_query;

        public TablePage (DatabaseWindow win, string name) throws Error {
            base (win, "table", name);
            build ();
            load_views ();
            open_source ();
            mode = "data";
            stack.visible_child_name = "data";
        }

        public TablePage.results (DatabaseWindow win, RecordSource source) {
            base (win, "results", source.def.name);
            is_query = true;
            build ();
            remove_css_class ("db-content");
            views.add (new ViewDef (_("Grid"), ViewKind.GRID));
            src = source;
            attach_source ();
            mode = "data";
        }

        private void build () {
            add_css_class ("db-content");
            stack = new Stack ();
            stack.transition_type = StackTransitionType.CROSSFADE;
            stack.vexpand = true;
            data_box = new Box (Orientation.VERTICAL, 0);
            view_stack = new Stack ();
            view_stack.vexpand = true;
            sheet = new DatasheetView ();
            var s = win.app.settings;
            if (s != null) {
                sheet.set_density (s.get_string ("row-density"));
                sheet.set_style (s.get_boolean ("show-gridlines"), s.get_boolean ("alternate-rows"));
                s.changed.connect ((k) => {
                    if (k == "row-density") sheet.set_density (s.get_string ("row-density"));
                    if (k == "show-gridlines" || k == "alternate-rows") sheet.set_style (s.get_boolean ("show-gridlines"), s.get_boolean ("alternate-rows"));
                });
            }
            sheet_scroll = new ScrolledWindow ();
            sheet_scroll.child = sheet;
            sheet_scroll.vexpand = true;
            sheet_scroll.hexpand = true;
            sheet_scroll.add_css_class ("db-datasheet-scroll");
            view_stack.add_named (sheet_scroll, "grid");
            empty_page = new StatusPage ();
            empty_page.icon_name = "edit-find";
            empty_page.title = _("No Matching Records");
            empty_page.description = _("No record matches the search or the filters of this view.");
            var clear = new Button.with_label (_("Clear Search and Filters"));
            clear.add_css_class ("suggested-action");
            clear.halign = Align.CENTER;
            clear.clicked.connect (() => clear_filters ());
            empty_page.child = clear;
            view_stack.add_named (empty_page, "empty");
            sub_paned = new Paned (Orientation.VERTICAL);
            sub_paned.start_child = view_stack;
            sub_paned.resize_start_child = true;
            sub_paned.shrink_end_child = false;
            sub_paned.vexpand = true;
            data_box.append (sub_paned);
            data_box.append (build_record_bar ());
            stack.add_named (data_box, "data");
            append (stack);
            sheet.selection_changed.connect (update_record_bar);
            sheet.selection_changed.connect (update_subdatasheet);
            sheet.error.connect ((m) => win.toast (m));
            sheet.cell_menu.connect (show_cell_menu);
            sheet.header_menu.connect (show_header_menu);
            sheet.layout_changed.connect (queue_save_state);
            sheet.attachment_requested.connect ((rowid, f) => Dialogs.attachment (win, src, rowid, f));
            sheet.record_added.connect (() => update_record_bar ());
        }

        private Widget build_record_bar () {
            var bar = new Box (Orientation.HORIZONTAL, 4);
            bar.add_css_class ("db-record-bar");
            bar.append (tool ("db-first-symbolic", _("First Record (Alt+Home)"), () => nav ("first")));
            bar.append (tool ("go-previous-symbolic", _("Previous Record (Alt+Page Up)"), () => nav ("prev")));
            var rec = new Label (_("Record"));
            rec.add_css_class ("db-status");
            rec.margin_start = 4;
            bar.append (rec);
            record_entry = new Entry ();
            record_entry.width_chars = 6;
            record_entry.max_width_chars = 8;
            record_entry.xalign = 1;
            record_entry.add_css_class ("db-status");
            record_entry.activate.connect (() => {
                int64 n = int64.parse (record_entry.text.strip ());
                if (n >= 1 && n <= sheet.record_count ()) sheet.select_record (n - 1);
                sheet.grab_focus ();
            });
            bar.append (record_entry);
            count_label = new Label ("");
            count_label.add_css_class ("db-status");
            count_label.add_css_class ("dim-label");
            count_label.margin_end = 4;
            bar.append (count_label);
            bar.append (tool ("go-next-symbolic", _("Next Record (Alt+Page Down)"), () => nav ("next")));
            bar.append (tool ("db-last-symbolic", _("Last Record (Alt+End)"), () => nav ("last")));
            new_btn = tool ("db-record-new-symbolic", _("New Record (Ctrl++)"), () => run_action ("new-record", null));
            bar.append (new_btn);
            filter_info = new Box (Orientation.HORIZONTAL, 4);
            filter_info.margin_start = 12;
            var ficon = new Image.from_icon_name ("db-filter-symbolic");
            filter_info.append (ficon);
            filter_label = new Label ("");
            filter_label.add_css_class ("db-status");
            filter_info.append (filter_label);
            var clear = new Button.with_label (_("Clear"));
            clear.add_css_class ("flat");
            clear.clicked.connect (() => clear_filters ());
            filter_info.append (clear);
            bar.append (filter_info);
            status_label = new Label ("");
            status_label.hexpand = true;
            status_label.halign = Align.END;
            status_label.add_css_class ("db-status");
            status_label.add_css_class ("dim-label");
            status_label.selectable = true;
            bar.append (status_label);
            return bar;
        }

        private delegate void Click ();

        private Button tool (string icon, string tip, owned Click cb) {
            var b = new Button.from_icon_name (icon);
            b.add_css_class ("flat");
            b.add_css_class ("db-tool");
            b.tooltip_text = tip;
            b.clicked.connect (() => cb ());
            return b;
        }

        private void nav (string where) {
            int64 n = sheet.record_count ();
            if (n == 0) return;
            int64 cur = sheet.current_record_index ();
            switch (where) {
                case "first": sheet.select_record (0); break;
                case "prev": sheet.select_record (int64.max (0, cur - 1)); break;
                case "next": sheet.select_record (int64.min (n - 1, cur + 1)); break;
                default: sheet.select_record (n - 1); break;
            }
            sheet.grab_focus ();
        }

        private void load_views () {
            views = ViewDef.load_all (db, object_name);
            view_index = 0;
        }

        public ViewDef current_view () {
            return views[view_index.clamp (0, views.size - 1)];
        }

        public string view_icon () {
            return current_view ().kind.icon_name ();
        }

        private void open_source () throws Error {
            src = new RecordSource (db, object_name, current_view ().state.copy ());
            attach_source ();
        }

        private void attach_source () {
            sheet.set_source (src);
            src.reset.connect (() => {
                update_record_bar ();
            });
            show_view ();
            update_record_bar ();
        }

        private void show_view () {
            var v = current_view ();
            if (board != null) {
                view_stack.remove (board);
                board = null;
            }
            if (v.kind == ViewKind.GRID) {
                view_stack.visible_child_name = src.count () == 0 && src.where_sql () != "" ? "empty" : "grid";
                return;
            }
            v.pick_defaults (src.def);
            switch (v.kind) {
                case ViewKind.GALLERY: board = new GalleryBoard (this, src, v); break;
                case ViewKind.KANBAN: board = new KanbanBoard (this, src, v); break;
                default: board = new CalendarBoard (this, src, v); break;
            }
            view_stack.add_named (board, "board");
            view_stack.visible_child = board;
        }

        public void refresh_view () {
            if (current_view ().kind == ViewKind.GRID) {
                bool empty = src.count () == 0 && src.where_sql () != "";
                view_stack.visible_child_name = empty ? "empty" : "grid";
            } else if (board is Board) {
                ((Board) board).rebuild ();
            }
        }

        private void update_record_bar () {
            if (src == null) return;
            int64 n = src.count ();
            int64 cur = sheet.current_record_index ();
            if (!record_entry.has_focus) {
                string rec = "";
                if (cur >= 0) rec = (cur + 1).to_string ();
                else if (sheet.is_new_row (sheet.cur_row)) rec = "*";
                record_entry.text = rec;
            }
            count_label.label = _("of %s").printf (Codec.format_number (n, 0, true));
            bool filtered = src.where_sql () != "";
            filter_info.visible = filtered;
            if (filtered) filter_label.label = _("Filtered, %s of %s").printf (Codec.format_number (n, 0, true), Codec.format_number (src.total_count (), 0, true));
            new_btn.sensitive = sheet.can_add ();
            status_label.label = selection_summary ();
        }

        private string selection_summary () {
            var ids = sheet.selected_rowids ();
            var f = sheet.current_field ();
            if (ids.length > 1) return ngettext ("%d record selected", "%d records selected", ids.length).printf (ids.length);
            if (f != null) return "%s, %s".printf (f.name, f.field_type.label ());
            return "";
        }

        public override string[] modes () {
            if (is_query) return {};
            return { "data", "design" };
        }

        public override void change_mode (string m) {
            if (m == mode) return;
            if (m == "design") {
                if (!sheet.commit_edit ()) return;
                if (sheet.has_pending ()) sheet.commit_new_row ();
                try {
                    if (designer == null) {
                        designer = new TableDesigner (this, db.load_table (object_name));
                        stack.add_named (designer, "design");
                        designer.changed.connect (() => {
                            win.sync_bubbles ();
                            title_changed ();
                        });
                    }
                } catch (Error e) {
                    win.show_error (_("Could Not Open Design"), e.message);
                    return;
                }
                stack.visible_child_name = "design";
            } else {
                stack.visible_child_name = "data";
            }
            base.change_mode (m);
        }

        public override string[] bubbles () {
            if (mode == "design") return { "add-field", "primary-key", "indexes" };
            var v = current_view ();
            string[] b = { "search" };
            if (!is_query) b += "views";
            b += "fields";
            b += "filter";
            b += "sort";
            if (v.kind == ViewKind.GRID) {
                b += "group";
                b += "totals";
            }
            b += "print";
            b += "export";
            return b;
        }

        public override bool dirty () {
            return designer != null && designer.dirty;
        }

        public override bool save () {
            if (designer == null || !designer.dirty) return true;
            return designer.apply ();
        }

        public override string title () {
            return object_name + (dirty () ? " *" : "");
        }

        public override void reload () {
            if (src == null) return;
            if (!is_query) {
                if (!db.object_exists (object_name, "table")) return;
                try {
                    var st = src.state;
                    src.reload_schema ();
                    src.state = st;
                } catch (Error e) {
                }
                if (designer != null && !designer.dirty) {
                    try {
                        designer.reset (db.load_table (object_name));
                    } catch (Error e) {
                    }
                }
            } else {
                src.invalidate ();
            }
            sheet.rebuild_columns ();
            sheet.refresh ();
            refresh_view ();
            update_record_bar ();
        }

        public override void search (string text) {
            if (src == null || src.state.search == text) return;
            src.state.search = text;
            src.invalidate ();
            sheet.refresh ();
            refresh_view ();
        }

        public override string search_text () {
            return src != null ? src.state.search : "";
        }

        public override void focus_content () {
            if (mode == "data") sheet.grab_focus ();
        }

        private void queue_save_state () {
            if (is_query) return;
            if (save_state_id != 0) Source.remove (save_state_id);
            save_state_id = Timeout.add (600, () => {
                save_state_id = 0;
                save_views ();
                return Source.REMOVE;
            });
        }

        public void save_views () {
            if (is_query || src == null) return;
            var v = current_view ();
            string search = src.state.search;
            v.state = src.state.copy ();
            v.state.search = "";
            src.state.search = search;
            try {
                db.set_meta ("views:" + object_name, ViewDef.to_json_all (views));
            } catch (Error e) {
            }
        }

        public void state_changed () {
            src.invalidate ();
            sheet.rebuild_columns ();
            sheet.refresh ();
            refresh_view ();
            queue_save_state ();
            win.sync_bubbles ();
        }

        public void clear_filters () {
            src.state.filters.clear ();
            src.state.sorts.clear ();
            src.state.search = "";
            win.search_changed_externally ("");
            state_changed ();
        }

        public void switch_view (int index) {
            if (index == view_index || index < 0 || index >= views.size) return;
            if (!sheet.commit_edit ()) return;
            save_views ();
            view_index = index;
            string search = src.state.search;
            src.state = current_view ().state.copy ();
            src.state.search = search;
            src.invalidate ();
            sheet.set_source (src);
            show_view ();
            update_record_bar ();
            win.sync_bubbles ();
            title_changed ();
        }

        public void add_view (ViewKind kind) {
            string base_name = kind.label ();
            string name = base_name;
            int n = 2;
            bool taken = true;
            while (taken) {
                taken = false;
                foreach (var v in views) {
                    if (v.name == name) taken = true;
                }
                if (taken) name = "%s %d".printf (base_name, n++);
            }
            var v = new ViewDef (name, kind);
            v.pick_defaults (src.def);
            views.add (v);
            save_views ();
            switch_view (views.size - 1);
            if (kind != ViewKind.GRID) Dialogs.view_settings (win, this, v);
        }

        public void rename_view (string name) {
            current_view ().name = name;
            save_views ();
        }

        public void delete_view () {
            if (view_index == 0) return;
            views.remove_at (view_index);
            view_index = 0;
            src.state = current_view ().state.copy ();
            src.invalidate ();
            sheet.set_source (src);
            show_view ();
            save_views ();
            win.sync_bubbles ();
        }

        public void view_settings_changed () {
            save_views ();
            show_view ();
        }

        private void show_views_menu () {
            var pop = new Popover ();
            pop.add_css_class ("menu");
            var box = new Box (Orientation.VERTICAL, 2);
            box.margin_start = box.margin_end = box.margin_top = box.margin_bottom = 6;
            var head = new Label (_("Views"));
            head.add_css_class ("heading");
            head.halign = Align.START;
            head.margin_start = 8;
            head.margin_bottom = 4;
            box.append (head);
            for (int i = 0; i < views.size; i++) {
                var v = views[i];
                var b = new Button ();
                b.add_css_class ("flat");
                var row = new Box (Orientation.HORIZONTAL, 10);
                row.append (new Image.from_icon_name (v.kind.icon_name ()));
                var l = new Label (v.name);
                l.hexpand = true;
                l.halign = Align.START;
                row.append (l);
                if (i == view_index) row.append (new Image.from_icon_name ("object-select-symbolic"));
                b.child = row;
                int idx = i;
                b.clicked.connect (() => {
                    pop.popdown ();
                    switch_view (idx);
                });
                box.append (b);
            }
            box.append (new Separator (Orientation.HORIZONTAL));
            ViewKind[] kinds = { ViewKind.GRID, ViewKind.GALLERY, ViewKind.KANBAN, ViewKind.CALENDAR };
            string[] labels = { _("New Grid View"), _("New Gallery View"), _("New Kanban View"), _("New Calendar View") };
            for (int i = 0; i < kinds.length; i++) {
                var k = kinds[i];
                var b = new Button ();
                b.add_css_class ("flat");
                var row = new Box (Orientation.HORIZONTAL, 10);
                row.append (new Image.from_icon_name (k.icon_name ()));
                var l = new Label (labels[i]);
                l.halign = Align.START;
                row.append (l);
                b.child = row;
                b.clicked.connect (() => {
                    pop.popdown ();
                    add_view (k);
                });
                box.append (b);
            }
            box.append (new Separator (Orientation.HORIZONTAL));
            var settings_b = new Button.with_label (_("View Settings…"));
            settings_b.add_css_class ("flat");
            settings_b.clicked.connect (() => {
                pop.popdown ();
                Dialogs.view_settings (win, this, current_view ());
            });
            settings_b.sensitive = current_view ().kind != ViewKind.GRID;
            box.append (settings_b);
            var rename_b = new Button.with_label (_("Rename View…"));
            rename_b.add_css_class ("flat");
            rename_b.clicked.connect (() => {
                pop.popdown ();
                Dialogs.rename_view (win, this);
            });
            box.append (rename_b);
            var del = new Button.with_label (_("Delete View"));
            del.add_css_class ("flat");
            del.add_css_class ("destructive-action");
            del.sensitive = view_index > 0;
            del.clicked.connect (() => {
                pop.popdown ();
                delete_view ();
            });
            box.append (del);
            foreach (var c in children_of (box)) {
                var btn = c as Button;
                if (btn != null && btn.child is Label) ((Label) btn.child).halign = Align.START;
            }
            pop.child = box;
            win.popup_at_bubble (pop, "views");
        }

        private static Gee.ArrayList<Widget> children_of (Widget w) {
            var list = new Gee.ArrayList<Widget> ();
            for (var c = w.get_first_child (); c != null; c = c.get_next_sibling ()) list.add (c);
            return list;
        }

        public override bool handles (string action) {
            if (mode == "design") {
                switch (action) {
                    case "add-field":
                    case "primary-key":
                    case "undo":
                    case "redo":
                    case "save-record":
                        return true;
                    default:
                        return false;
                }
            }
            switch (action) {
                case "cut":
                case "delete-record":
                case "new-record":
                case "paste":
                    return !is_query && src != null && src.editable;
                case "add-field":
                case "new-view":
                case "view-kind":
                case "views-menu":
                    return !is_query;
                case "filter-by-form":
                case "subdatasheet":
                case "copy":
                case "select-all":
                case "replace":
                case "goto":
                case "save-record":
                case "sort-asc":
                case "sort-desc":
                case "sort":
                case "filter":
                case "filter-selection":
                case "clear-filters":
                case "group":
                case "hide-fields":
                case "totals-row":
                case "first-record":
                case "prev-record":
                case "next-record":
                case "last-record":
                case "print":
                case "export-pdf":
                    return true;
                default:
                    return false;
            }
        }

        public override void run_action (string action, Variant? param) {
            if (mode == "design" && designer != null) {
                designer.run_action (action);
                return;
            }
            switch (action) {
                case "copy":
                    get_clipboard ().set_text (sheet.copy_text ());
                    break;
                case "cut":
                    get_clipboard ().set_text (sheet.copy_text ());
                    sheet.clear_cells ();
                    break;
                case "paste":
                    var cb = get_clipboard ();
                    cb.read_text_async.begin (null, (obj, res) => {
                        try {
                            string? t = cb.read_text_async.end (res);
                            if (t != null && t != "") sheet.paste_text (t);
                        } catch (Error e) {
                        }
                    });
                    break;
                case "select-all":
                    sheet.select_cell (0, 0, false);
                    sheet.select_cell (sheet.display_rows () - 1, sheet.columns ().size - 1, true);
                    break;
                case "new-record":
                    if (current_view ().kind != ViewKind.GRID) Dialogs.record_editor (win, src, -1);
                    else sheet.new_record ();
                    break;
                case "delete-record":
                    delete_records ();
                    break;
                case "filter-by-form":
                    FilterByForm.show (win, src.def, src.state.extra_where, (where) => {
                        src.state.extra_where = where;
                        state_changed ();
                    });
                    break;
                case "subdatasheet":
                    if (is_query) break;
                    var rels = db.relationships_to (object_name);
                    if (rels.size == 0) {
                        win.toast (_("No other table refers to this one."));
                        break;
                    }
                    var menu = new ContextMenu (sheet);
                    foreach (var r in rels) {
                        if (r.columns.length != 1) continue;
                        var rel = r;
                        menu.add_item (_("%s (by %s)").printf (r.table, r.columns[0]), "db-table-symbolic", () => show_subdatasheet (rel));
                    }
                    if (sub_rel != null) {
                        menu.add_separator ();
                        menu.add_item (_("Hide the Subdatasheet"), "window-close-symbolic", () => show_subdatasheet (null));
                    }
                    DatabaseWindow.popup_menu (menu);
                    break;
                case "save-record":
                    sheet.commit_edit ();
                    sheet.commit_new_row ();
                    break;
                case "add-field":
                    Dialogs.add_field (win, object_name);
                    break;
                case "goto":
                    record_entry.grab_focus ();
                    record_entry.select_region (0, -1);
                    break;
                case "replace":
                    Dialogs.find_replace (win, this);
                    break;
                case "sort-asc":
                case "sort-desc":
                    var f = sheet.current_field ();
                    if (f == null) break;
                    src.state.sorts.clear ();
                    src.state.sorts.add (new SortSpec (f.name, action == "sort-desc"));
                    state_changed ();
                    break;
                case "sort":
                    win.popup_at_bubble (new SortPopover (this), "sort");
                    break;
                case "filter":
                    win.popup_at_bubble (new FilterPopover (this), "filter");
                    break;
                case "filter-selection":
                    filter_by_selection (false);
                    break;
                case "clear-filters":
                    clear_filters ();
                    break;
                case "group":
                    win.popup_at_bubble (new GroupPopover (this), "group");
                    break;
                case "hide-fields":
                    win.popup_at_bubble (new FieldsPopover (this), "fields");
                    break;
                case "totals-row":
                    if (src.state.totals.size > 0) {
                        src.state.totals.clear ();
                    } else {
                        foreach (var fld in src.def.fields) {
                            if (fld.field_type == FieldType.CURRENCY || fld.field_type == FieldType.NUMBER) src.state.totals[fld.name] = "sum";
                        }
                        if (src.def.fields.size > 0) src.state.totals[src.def.fields[0].name] = "count";
                    }
                    state_changed ();
                    break;
                case "first-record": nav ("first"); break;
                case "prev-record": nav ("prev"); break;
                case "next-record": nav ("next"); break;
                case "last-record": nav ("last"); break;
                case "view-kind":
                    string k = param != null ? param.get_string () : "grid";
                    var kind = ViewKind.from_id (k);
                    for (int i = 0; i < views.size; i++) {
                        if (views[i].kind == kind) {
                            switch_view (i);
                            return;
                        }
                    }
                    add_view (kind);
                    break;
                case "new-view":
                    add_view (ViewKind.GRID);
                    break;
                case "views-menu":
                    show_views_menu ();
                    break;
                case "print":
                    ReportPrinter.print_source (win, quick_report (), src);
                    break;
                case "export-pdf":
                    ReportPrinter.export_pdf (win, quick_report (), src);
                    break;
            }
            update_record_bar ();
        }

        public ReportDef quick_report () {
            var r = new ReportDef ();
            r.source = src.source;
            r.title = is_query ? _("Query Results") : object_name;
            r.subtitle = current_view ().name != _("Grid") ? current_view ().name : "";
            foreach (var f in sheet.columns ()) {
                if (f.field_type == FieldType.ATTACHMENT) continue;
                var c = new ReportColumn (f.name, f.name);
                c.width = f.field_type == FieldType.LONG_TEXT ? 2.5 : (f.field_type.is_text () || f.field_type == FieldType.LOOKUP ? 1.6 : 1);
                if (src.state.totals.has_key (f.name)) {
                    switch (src.state.totals[f.name]) {
                        case "sum": c.total = ReportTotal.SUM; break;
                        case "avg": c.total = ReportTotal.AVG; break;
                        case "count": c.total = ReportTotal.COUNT; break;
                        case "min": c.total = ReportTotal.MIN; break;
                        case "max": c.total = ReportTotal.MAX; break;
                        default: break;
                    }
                }
                r.columns.add (c);
            }
            r.landscape = r.columns.size > 5;
            if (win.app.settings != null) r.paper = win.app.settings.get_string ("report-paper");
            r.state = src.state.copy ();
            if (src.state.group_by != "") r.groups.add (new ReportGroup (src.state.group_by));
            r.state.group_by = "";
            return r;
        }

        private void delete_records () {
            var ids = sheet.selected_rowids ();
            if (ids.length == 0) return;
            bool confirm = win.app.settings == null || win.app.settings.get_boolean ("confirm-delete");
            int64[] copy = ids;
            if (!confirm) {
                do_delete (copy);
                return;
            }
            var rels = db.relationships_to (object_name);
            bool cascade = false;
            foreach (var r in rels) {
                if (r.on_delete == RefAction.CASCADE) cascade = true;
            }
            string msg = cascade ? _("Related records in other tables are deleted too. You can undo this unless related records are removed.") : _("You can undo this with Ctrl+Z.");
            var dlg = new ConfirmDialog (win.app, ngettext ("Delete %d Record?", "Delete %d Records?", ids.length).printf (ids.length), "user-trash", msg, _("Delete"), ConfirmDialog.ActionStyle.DESTRUCTIVE);
            dlg.transient_for = win;
            dlg.response.connect ((r) => {
                if (r == ConfirmDialog.Response.PRIMARY) do_delete (copy);
            });
            dlg.present ();
        }

        private void do_delete (int64[] ids) {
            try {
                src.delete (ids);
                sheet.refresh ();
                refresh_view ();
                win.toast (ngettext ("%d record deleted", "%d records deleted", ids.length).printf (ids.length), db.can_undo ? _("Undo") : null, () => win.run ("undo"));
            } catch (Error e) {
                win.show_error (_("Could Not Delete"), e.message);
            }
        }

        private void filter_by_selection (bool exclude) {
            var f = sheet.current_field ();
            var row = sheet.current_row ();
            if (f == null || row == null) return;
            var v = row.get (src.def.index_of (f.name));
            FilterSpec spec;
            if (v.is_null) spec = new FilterSpec (f.name, exclude ? FilterOp.IS_NOT_EMPTY : FilterOp.IS_EMPTY);
            else if (f.field_type == FieldType.BOOLEAN) spec = new FilterSpec (f.name, v.as_bool () != exclude ? FilterOp.IS_TRUE : FilterOp.IS_FALSE);
            else spec = new FilterSpec (f.name, exclude ? FilterOp.NOT_EQUALS : FilterOp.EQUALS, Codec.edit_text (f, v));
            src.state.filters.add (spec);
            state_changed ();
        }

        private Gdk.Rectangle point (double x, double y) {
            var r = Gdk.Rectangle ();
            r.x = (int) x;
            r.y = (int) y;
            r.width = 1;
            r.height = 1;
            return r;
        }

        private void show_cell_menu (double x, double y) {
            var menu = new ContextMenu (sheet);
            menu.pointing_to = point (x, y);
            bool editable = !is_query && src.editable;
            if (editable) menu.add_item (_("Cut"), "edit-cut-symbolic", () => run_action ("cut", null));
            menu.add_item (_("Copy"), "edit-copy-symbolic", () => run_action ("copy", null));
            if (editable) menu.add_item (_("Paste"), "edit-paste-symbolic", () => run_action ("paste", null));
            menu.add_separator ();
            var row = sheet.current_row ();
            if (row != null && editable) {
                int64 rid = row.rowid;
                menu.add_item (_("Open Record…"), "db-form-symbolic", () => Dialogs.record_editor (win, src, rid));
            }
            if (editable) menu.add_item (_("New Record"), "db-record-new-symbolic", () => run_action ("new-record", null));
            var f = sheet.current_field ();
            if (f != null) {
                menu.add_separator ();
                menu.add_item (_("Sort A to Z"), "view-sort-ascending-symbolic", () => run_action ("sort-asc", null));
                menu.add_item (_("Sort Z to A"), "view-sort-descending-symbolic", () => run_action ("sort-desc", null));
                if (row != null) {
                    menu.add_item (_("Filter by Selection"), "db-filter-symbolic", () => filter_by_selection (false));
                    menu.add_item (_("Filter Excluding Selection"), "db-filter-symbolic", () => filter_by_selection (true));
                }
                if (src.state.filters.size > 0 || src.state.sorts.size > 0) menu.add_item (_("Clear Filters and Sorting"), "edit-clear-symbolic", () => clear_filters ());
            }
            if (editable && row != null) {
                menu.add_separator ();
                int n = sheet.selected_rowids ().length;
                menu.add_item (ngettext ("Delete Record", "Delete %d Records", n).printf (n), "user-trash-symbolic", () => delete_records (), "destructive");
            }
            DatabaseWindow.popup_menu (menu);
        }

        private Paned sub_paned;
        private DatasheetView? sub_sheet;
        private Relationship? sub_rel;
        private Label? sub_title;

        public void show_subdatasheet (Relationship? rel) {
            sub_rel = rel;
            if (rel == null) {
                sub_paned.end_child = null;
                sub_sheet = null;
                return;
            }
            var box = new Box (Orientation.VERTICAL, 0);
            box.add_css_class ("db-subdatasheet");
            var head = new Box (Orientation.HORIZONTAL, 6);
            head.add_css_class ("db-record-bar");
            sub_title = new Label ("");
            sub_title.add_css_class ("heading");
            sub_title.hexpand = true;
            sub_title.xalign = 0;
            head.append (sub_title);
            var open = new Button.from_icon_name ("document-open-symbolic");
            open.add_css_class ("flat");
            open.tooltip_text = _("Open the Related Table");
            open.clicked.connect (() => win.open_object ("table", rel.table));
            head.append (open);
            var close = new Button.from_icon_name ("window-close-symbolic");
            close.add_css_class ("flat");
            close.tooltip_text = _("Hide the Subdatasheet");
            close.clicked.connect (() => show_subdatasheet (null));
            head.append (close);
            box.append (head);
            try {
                var st = new ViewState ();
                st.hidden.add (rel.columns[0]);
                st.filters.add (new FilterSpec (rel.columns[0], FilterOp.EQUALS, "\u0001"));
                var csrc = new RecordSource (db, rel.table, st);
                sub_sheet = new DatasheetView ();
                sub_sheet.set_source (csrc);
                sub_sheet.error.connect ((m) => win.toast (m));
                sub_sheet.attachment_requested.connect ((rowid, f) => Dialogs.attachment (win, csrc, rowid, f));
                var sc = new ScrolledWindow ();
                sc.vexpand = true;
                sc.child = sub_sheet;
                box.append (sc);
            } catch (Error e) {
                win.show_error (_("Could Not Show Related Records"), e.message);
                return;
            }
            sub_paned.end_child = box;
            sub_paned.position = int.max (200, get_height () / 2);
            update_subdatasheet ();
        }

        private void update_subdatasheet () {
            if (sub_sheet == null || sub_rel == null || src == null) return;
            var row = sheet.current_row ();
            DbValue mv = new DbValue.null ();
            if (row != null) {
                int idx = src.def.index_of (sub_rel.ref_columns[0]);
                if (idx >= 0) mv = row.get (idx);
            }
            var spec = sub_sheet.src.state.filters[0];
            spec.value = mv.is_null ? "\u0001" : mv.to_string ();
            sub_sheet.src.invalidate ();
            sub_sheet.defaults.clear ();
            if (!mv.is_null) sub_sheet.defaults[sub_rel.columns[0]] = mv;
            sub_sheet.allow_new = !mv.is_null;
            sub_sheet.refresh ();
            if (sub_title != null) sub_title.label = row != null ? _("%s for %s").printf (sub_rel.table, src.display (src.def.find (sub_rel.ref_columns[0]) ?? new Field (sub_rel.ref_columns[0], FieldType.TEXT), mv)) : sub_rel.table;
        }

        private void show_header_menu (int col, double x, double y) {
            var cols = sheet.columns ();
            if (col < 0 || col >= cols.size) return;
            var f = cols[col];
            var menu = new ContextMenu (sheet);
            menu.pointing_to = point (x, y);
            menu.add_item (_("Sort A to Z"), "view-sort-ascending-symbolic", () => {
                src.state.sorts.clear ();
                src.state.sorts.add (new SortSpec (f.name, false));
                state_changed ();
            });
            menu.add_item (_("Sort Z to A"), "view-sort-descending-symbolic", () => {
                src.state.sorts.clear ();
                src.state.sorts.add (new SortSpec (f.name, true));
                state_changed ();
            });
            menu.add_item (_("Filter…"), "db-filter-symbolic", () => {
                var pop = new FilterPopover (this, f.name);
                win.popup_at_bubble (pop, "filter");
            });
            if (src.state.group_by == f.name) {
                menu.add_item (_("Remove Grouping"), "db-group-symbolic", () => {
                    src.state.group_by = "";
                    state_changed ();
                });
            } else if (current_view ().kind == ViewKind.GRID) {
                menu.add_item (_("Group by This Field"), "db-group-symbolic", () => {
                    src.state.group_by = f.name;
                    src.state.collapsed.clear ();
                    state_changed ();
                });
            }
            menu.add_separator ();
            var totals = menu.add_submenu (_("Total"), "db-totals-symbolic");
            totals.add_item (_("None"), null, () => {
                src.state.totals.unset (f.name);
                state_changed ();
            });
            Aggregate[] aggs = { Aggregate.COUNT, Aggregate.SUM, Aggregate.AVG, Aggregate.MIN, Aggregate.MAX, Aggregate.STDEV, Aggregate.VAR };
            foreach (var a in aggs) {
                if ((a == Aggregate.SUM || a == Aggregate.AVG || a == Aggregate.STDEV || a == Aggregate.VAR) && !f.field_type.is_numeric ()) continue;
                var agg = a;
                totals.add_item (a.label (), null, () => {
                    src.state.totals[f.name] = agg.id ();
                    state_changed ();
                });
            }
            menu.add_item (_("Conditional Formatting…"), "db-filter-symbolic", () => {
                CondRuleSet? set = null;
                foreach (var fs in src.state.formats) if (fs.column == f.name) set = fs;
                var current = set != null ? set.rules : new Gee.ArrayList<CondRule> ();
                CondFormatDialog.show (win, _("Conditional Formatting: %s").printf (f.label ()), current, (rules) => {
                    if (set == null) {
                        set = new CondRuleSet ();
                        set.column = f.name;
                        src.state.formats.add (set);
                    }
                    set.rules = rules;
                    state_changed ();
                });
            });
            if (f.field_type.is_numeric ()) {
                bool has_bar = false;
                foreach (var fs in src.state.formats) if (fs.column == f.name && fs.data_bar) has_bar = true;
                menu.add_item (has_bar ? _("Remove Data Bars") : _("Show Data Bars"), "db-totals-symbolic", () => {
                    CondRuleSet? set = null;
                    foreach (var fs in src.state.formats) if (fs.column == f.name) set = fs;
                    if (set == null) {
                        set = new CondRuleSet ();
                        set.column = f.name;
                        src.state.formats.add (set);
                    }
                    set.data_bar = !has_bar;
                    state_changed ();
                });
            }
            menu.add_item (_("Fit Width to Contents"), "zoom-fit-best-symbolic", () => sheet.autofit (col));
            menu.add_item (_("Hide Field"), "view-conceal-symbolic", () => {
                src.state.hidden.add (f.name);
                state_changed ();
            });
            if (col > 0) menu.add_item (_("Move Left"), "go-previous-symbolic", () => move_column (f.name, -1));
            if (col < cols.size - 1) menu.add_item (_("Move Right"), "go-next-symbolic", () => move_column (f.name, 1));
            if (!is_query && !db.read_only) {
                menu.add_separator ();
                menu.add_item (_("Insert Field…"), "db-field-add-symbolic", () => Dialogs.add_field (win, object_name, f.name));
                menu.add_item (_("Rename Field…"), "document-edit-symbolic", () => Dialogs.rename_field (win, object_name, f.name));
                menu.add_item (_("Field Properties"), "document-properties-symbolic", () => {
                    win.open_object ("table", object_name, "design");
                    if (designer != null) designer.select_field (f.name);
                });
                menu.add_separator ();
                menu.add_item (_("Delete Field…"), "user-trash-symbolic", () => Dialogs.delete_field (win, object_name, f.name), "destructive");
            }
            DatabaseWindow.popup_menu (menu);
        }

        private void move_column (string name, int delta) {
            var order = new Gee.ArrayList<string> ();
            foreach (var f in sheet.columns ()) order.add (f.name);
            foreach (string h in src.state.hidden) {
                if (!order.contains (h)) order.add (h);
            }
            int i = order.index_of (name);
            int j = (i + delta).clamp (0, order.size - 1);
            order.remove_at (i);
            order.insert (j, name);
            src.state.order = order.to_array ();
            state_changed ();
        }
    }

    public class FilterPopover : Popover {
        private TablePage page;
        private Box rows;

        public FilterPopover (TablePage page, string? add_for = null) {
            this.page = page;
            var box = new Box (Orientation.VERTICAL, 8);
            box.margin_start = box.margin_end = box.margin_top = box.margin_bottom = 10;
            var head = new Box (Orientation.HORIZONTAL, 8);
            var title = new Label (_("Filters"));
            title.add_css_class ("heading");
            title.hexpand = true;
            title.halign = Align.START;
            head.append (title);
            var any = new DropDown.from_strings ({ _("Match All"), _("Match Any") });
            any.selected = page.src.state.match_any ? 1 : 0;
            any.notify["selected"].connect (() => {
                page.src.state.match_any = any.selected == 1;
                page.state_changed ();
            });
            head.append (any);
            box.append (head);
            rows = new Box (Orientation.VERTICAL, 4);
            box.append (rows);
            var add = new Button.with_label (_("Add Filter"));
            add.halign = Align.START;
            add.clicked.connect (() => {
                var f = page.src.def.fields.size > 0 ? page.src.def.fields[0].name : "";
                var spec = new FilterSpec (f, FilterOp.CONTAINS);
                page.src.state.filters.add (spec);
                add_row (spec);
            });
            box.append (add);
            child = box;
            foreach (var f in page.src.state.filters) add_row (f);
            if (add_for != null) {
                var fld = page.src.def.find (add_for);
                var spec = new FilterSpec (add_for, fld != null && !fld.field_type.is_text () ? FilterOp.EQUALS : FilterOp.CONTAINS);
                page.src.state.filters.add (spec);
                add_row (spec);
            }
        }

        private static FilterOp[] ops_for (Field f) {
            if (f.field_type == FieldType.BOOLEAN) return { FilterOp.IS_TRUE, FilterOp.IS_FALSE, FilterOp.IS_EMPTY };
            if (f.field_type.is_numeric () || f.field_type.is_temporal ()) return { FilterOp.EQUALS, FilterOp.NOT_EQUALS, FilterOp.GREATER, FilterOp.GREATER_EQUAL, FilterOp.LESS, FilterOp.LESS_EQUAL, FilterOp.BETWEEN, FilterOp.IS_EMPTY, FilterOp.IS_NOT_EMPTY };
            if (f.field_type == FieldType.CHOICE || f.field_type == FieldType.LOOKUP) return { FilterOp.EQUALS, FilterOp.NOT_EQUALS, FilterOp.ONE_OF, FilterOp.IS_EMPTY, FilterOp.IS_NOT_EMPTY };
            return { FilterOp.CONTAINS, FilterOp.NOT_CONTAINS, FilterOp.EQUALS, FilterOp.NOT_EQUALS, FilterOp.STARTS_WITH, FilterOp.ENDS_WITH, FilterOp.IS_EMPTY, FilterOp.IS_NOT_EMPTY };
        }

        private void add_row (FilterSpec spec) {
            var row = new Box (Orientation.HORIZONTAL, 6);
            row.add_css_class ("db-filter-row");
            string[] names = {};
            foreach (var f in page.src.def.fields) names += f.name;
            var field_dd = new DropDown.from_strings (names);
            int fi = page.src.def.index_of (spec.column);
            field_dd.selected = fi >= 0 ? fi : 0;
            row.append (field_dd);
            var op_dd = new DropDown.from_strings ({ "" });
            row.append (op_dd);
            var value = new Entry ();
            value.hexpand = true;
            value.width_chars = 14;
            value.placeholder_text = _("Value");
            value.text = spec.op == FilterOp.ONE_OF ? string.joinv (", ", spec.values) : spec.value;
            row.append (value);
            var value2 = new Entry ();
            value2.width_chars = 10;
            value2.placeholder_text = _("and");
            value2.text = spec.value2;
            row.append (value2);
            var remove = new Button.from_icon_name ("list-remove-symbolic");
            remove.add_css_class ("flat");
            remove.tooltip_text = _("Remove Filter");
            row.append (remove);
            FilterOp[] current_ops = {};
            bool updating = false;
            Callback refresh_ops = () => {
                var f = page.src.def.fields[(int) field_dd.selected];
                current_ops = ops_for (f);
                string[] labels = {};
                int sel = 0;
                for (int i = 0; i < current_ops.length; i++) {
                    labels += current_ops[i].label ();
                    if (current_ops[i] == spec.op) sel = i;
                }
                updating = true;
                op_dd.model = new StringList (labels);
                op_dd.selected = sel;
                spec.op = current_ops[sel];
                updating = false;
                value.visible = spec.op.operands () >= 1;
                value2.visible = spec.op.operands () == 2;
                value.placeholder_text = spec.op == FilterOp.ONE_OF ? _("Values separated by commas") : (f.field_type.is_temporal () ? _("Date") : _("Value"));
            };
            refresh_ops ();
            field_dd.notify["selected"].connect (() => {
                spec.column = page.src.def.fields[(int) field_dd.selected].name;
                refresh_ops ();
                page.state_changed ();
            });
            op_dd.notify["selected"].connect (() => {
                if (updating || op_dd.selected >= current_ops.length) return;
                spec.op = current_ops[op_dd.selected];
                value.visible = spec.op.operands () >= 1;
                value2.visible = spec.op.operands () == 2;
                page.state_changed ();
            });
            value.changed.connect (() => {
                if (spec.op == FilterOp.ONE_OF) {
                    string[] items = {};
                    foreach (string p in value.text.split (",")) items += p.strip ();
                    spec.values = items;
                } else {
                    spec.value = value.text;
                }
                page.state_changed ();
            });
            value2.changed.connect (() => {
                spec.value2 = value2.text;
                page.state_changed ();
            });
            remove.clicked.connect (() => {
                page.src.state.filters.remove (spec);
                rows.remove (row);
                page.state_changed ();
            });
            rows.append (row);
        }

        private delegate void Callback ();
    }

    public class SortPopover : Popover {
        private TablePage page;
        private Box rows;

        public SortPopover (TablePage page) {
            this.page = page;
            var box = new Box (Orientation.VERTICAL, 8);
            box.margin_start = box.margin_end = box.margin_top = box.margin_bottom = 10;
            var title = new Label (_("Sort"));
            title.add_css_class ("heading");
            title.halign = Align.START;
            box.append (title);
            rows = new Box (Orientation.VERTICAL, 4);
            box.append (rows);
            var add = new Button.with_label (_("Add Sort Level"));
            add.halign = Align.START;
            add.clicked.connect (() => {
                var spec = new SortSpec (page.src.def.fields[0].name, false);
                page.src.state.sorts.add (spec);
                add_row (spec);
                page.state_changed ();
            });
            box.append (add);
            child = box;
            foreach (var s in page.src.state.sorts) add_row (s);
        }

        private void add_row (SortSpec spec) {
            var row = new Box (Orientation.HORIZONTAL, 6);
            string[] names = {};
            foreach (var f in page.src.def.fields) names += f.name;
            var dd = new DropDown.from_strings (names);
            int i = page.src.def.index_of (spec.column);
            dd.selected = i >= 0 ? i : 0;
            row.append (dd);
            var dir = new DropDown.from_strings ({ _("A to Z"), _("Z to A") });
            dir.selected = spec.descending ? 1 : 0;
            row.append (dir);
            var remove = new Button.from_icon_name ("list-remove-symbolic");
            remove.add_css_class ("flat");
            remove.tooltip_text = _("Remove Sort Level");
            row.append (remove);
            dd.notify["selected"].connect (() => {
                spec.column = page.src.def.fields[(int) dd.selected].name;
                page.state_changed ();
            });
            dir.notify["selected"].connect (() => {
                spec.descending = dir.selected == 1;
                page.state_changed ();
            });
            remove.clicked.connect (() => {
                page.src.state.sorts.remove (spec);
                rows.remove (row);
                page.state_changed ();
            });
            rows.append (row);
        }
    }

    public class GroupPopover : Popover {
        public GroupPopover (TablePage page) {
            var box = new Box (Orientation.VERTICAL, 8);
            box.margin_start = box.margin_end = box.margin_top = box.margin_bottom = 10;
            var title = new Label (_("Group Records"));
            title.add_css_class ("heading");
            title.halign = Align.START;
            box.append (title);
            string[] names = { _("No Grouping") };
            foreach (var f in page.src.def.fields) {
                if (f.field_type != FieldType.ATTACHMENT && f.field_type != FieldType.LONG_TEXT) names += f.name;
            }
            var dd = new DropDown.from_strings (names);
            for (int i = 1; i < names.length; i++) {
                if (names[i] == page.src.state.group_by) dd.selected = i;
            }
            dd.notify["selected"].connect (() => {
                page.src.state.group_by = dd.selected == 0 ? "" : names[dd.selected];
                page.src.state.collapsed.clear ();
                page.state_changed ();
            });
            box.append (dd);
            var hint = new Label (_("Click a group header to collapse or expand it."));
            hint.add_css_class ("caption");
            hint.add_css_class ("dim-label");
            hint.halign = Align.START;
            box.append (hint);
            child = box;
        }
    }

    public class FieldsPopover : Popover {
        public FieldsPopover (TablePage page) {
            var box = new Box (Orientation.VERTICAL, 4);
            box.margin_start = box.margin_end = box.margin_top = box.margin_bottom = 10;
            var head = new Box (Orientation.HORIZONTAL, 6);
            var title = new Label (_("Fields"));
            title.add_css_class ("heading");
            title.hexpand = true;
            title.halign = Align.START;
            head.append (title);
            var show_all = new Button.with_label (_("Show All"));
            show_all.add_css_class ("flat");
            head.append (show_all);
            box.append (head);
            var list = new Box (Orientation.VERTICAL, 2);
            var checks = new Gee.ArrayList<CheckButton> ();
            foreach (var f in page.src.def.fields) {
                var row = new Box (Orientation.HORIZONTAL, 8);
                var check = new CheckButton ();
                check.active = !page.src.state.hidden.contains (f.name);
                row.append (check);
                row.append (new Image.from_icon_name (f.field_type.icon_name ()));
                var l = new Label (f.name);
                l.halign = Align.START;
                row.append (l);
                string name = f.name;
                check.toggled.connect (() => {
                    if (check.active) page.src.state.hidden.remove (name);
                    else page.src.state.hidden.add (name);
                    page.state_changed ();
                });
                checks.add (check);
                list.append (row);
            }
            show_all.clicked.connect (() => {
                foreach (var c in checks) c.active = true;
            });
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.propagate_natural_height = true;
            scroll.max_content_height = 420;
            scroll.child = list;
            box.append (scroll);
            child = box;
        }
    }
}
