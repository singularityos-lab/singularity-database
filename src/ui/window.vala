using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Database {

    public abstract class ObjectPage : Box {
        public weak DatabaseWindow win;
        public string kind { get; protected set; default = ""; }
        public string object_name { get; set; default = ""; }
        public string mode { get; protected set; default = ""; }

        public signal void mode_changed ();
        public signal void title_changed ();

        protected ObjectPage (DatabaseWindow win, string kind, string name) {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            this.win = win;
            this.kind = kind;
            this.object_name = name;
        }

        public Database db {
            get { return win.db; }
        }

        public string key () {
            return kind + ":" + object_name;
        }

        public virtual string[] modes () {
            return {};
        }

        public virtual string mode_label (string m) {
            switch (m) {
                case "data": return _("Data");
                case "design": return _("Design");
                case "sql": return _("SQL");
                case "results": return _("Results");
                case "form": return _("Form");
                case "preview": return _("Preview");
                default: return m;
            }
        }

        public virtual void change_mode (string m) {
            mode = m;
            mode_changed ();
        }

        public virtual string[] bubbles () {
            return {};
        }

        public virtual bool handles (string action) {
            return false;
        }

        public virtual void run_action (string action, Variant? param) {
        }

        public virtual bool dirty () {
            return false;
        }

        public virtual bool save () {
            return true;
        }

        public virtual void reload () {
        }

        public virtual void search (string text) {
        }

        public virtual string search_text () {
            return "";
        }

        public virtual string title () {
            return object_name;
        }

        public virtual string icon_name () {
            switch (kind) {
                case "table": return "db-table-symbolic";
                case "query": return "db-query-symbolic";
                case "form": return "db-form-symbolic";
                case "report": return "db-report-symbolic";
                default: return "db-relationship-symbolic";
            }
        }

        public virtual void focus_content () {
        }
    }

    public class DatabaseWindow : Singularity.Widgets.Window {
        public Database? db { get; private set; }
        public DatabaseApp app;
        public ScriptRuntime? runtime;
        public DbHost? host;
        private Stack content_stack;
        private WelcomeView welcome;
        private Box db_box;
        private Stack page_stack;
        private WelcomePage home;
        private AppSidebar sidebar;
        private Box object_list;
        private string object_filter = "";
        private Gee.HashMap<string, SidebarRow> rows = new Gee.HashMap<string, SidebarRow> ();
        private Gee.HashMap<string, ObjectPage> pages = new Gee.HashMap<string, ObjectPage> ();
        private ObjectPage? current;
        private Gee.HashMap<string, Widget> bubble_map = new Gee.HashMap<string, Widget> ();
        private Gee.ArrayList<Widget> doc_bubbles = new Gee.ArrayList<Widget> ();
        private ContextRibbon ribbon;
        private RibbonSelector view_selector;
        private string[] switcher_modes = {};
        private bool switching;
        private RibbonButton undo_item;
        private RibbonButton redo_item;
        private RibbonButton views_item;
        private Gee.HashMap<string, Widget> anchors = new Gee.HashMap<string, Widget> ();
        private Gee.HashMap<string, string> callback_items = new Gee.HashMap<string, string> ();
        private Gee.HashMap<string, RibbonItem> gated_items = new Gee.HashMap<string, RibbonItem> ();
        private string[] design_contexts = { "table-design", "query-design", "form-design", "report-design", "print-preview", "relationship-design" };
        private string shown_design = "";
        private SearchBubble search_bubble;
        private bool close_confirmed;
        private string[] doc_actions = {};
        private string[] page_actions = {};
        private uint refresh_id;

        public DatabaseWindow (DatabaseApp app) {
            Object (application: app);
            this.app = app;
            set_default_size (1280, 820);
            set_title (_("Database"));

            content_stack = new Stack ();
            content_stack.transition_type = StackTransitionType.CROSSFADE;
            welcome = new WelcomeView (this);
            content_stack.add_named (welcome, "welcome");

            db_box = new Box (Orientation.VERTICAL, 0);
            page_stack = new Stack ();
            page_stack.transition_type = StackTransitionType.CROSSFADE;
            page_stack.vexpand = true;
            home = build_home ();
            page_stack.add_named (home, "home");
            ribbon = build_ribbon ();
            apply_view_edge (db_box);
            db_box.append (ribbon);
            db_box.append (page_stack);
            content_stack.add_named (db_box, "database");

            sidebar = new AppSidebar (236);
            object_list = new Box (Orientation.VERTICAL, 2);
            sidebar.box.append (object_list);
            var create = sidebar.add_bubble_icon ("list-add-symbolic", _("Create"), () => { });
            create.clicked.connect (() => show_create_menu (create));
            sidebar.add_bubble_search (_("Search Objects"), (t) => {
                object_filter = t.strip ().casefold ();
                rebuild_sidebar ();
            });
            set_sidebar (sidebar);

            build_bubbles ();
            set_content (content_stack);
            install_actions ();
            close_request.connect (on_close_request);

            var drop = new DropTarget (typeof (Gdk.FileList), Gdk.DragAction.COPY);
            drop.drop.connect ((value, x, y) => {
                var list = (Gdk.FileList) value.get_boxed ();
                foreach (var file in list.get_files ()) {
                    string? p = file.get_path ();
                    if (p == null) continue;
                    if (db != null && !DatabaseApp.is_database_file (p) && !DatabaseApp.is_access_file (p)) {
                        TransferDialogs.import_file (this, p);
                    } else {
                        app.open_file (file, this);
                    }
                    break;
                }
                return true;
            });
            ((Widget) this).add_controller (drop);
            show_welcome ();
        }

        private WelcomePage build_home () {
            var wp = new WelcomePage ();
            wp.is_section = true;
            wp.app_icon_name = "x-office-database";
            wp.add_action ("x-office-database", _("New Table"), _("Design fields, types and keys"), () => run ("new-table"));
            wp.add_action ("text-csv", _("Import Data"), _("CSV, Excel, JSON, SQL and Access files"), () => run ("import"));
            wp.add_action ("system-search", _("New Query"), _("Combine and filter tables visually or in SQL"), () => run ("new-query"));
            wp.add_action ("x-office-addressbook", _("New Form"), _("A friendly screen to enter and browse records"), () => run ("new-form"));
            wp.add_action ("x-office-document", _("New Report"), _("Grouped, totalled pages to print or share"), () => run ("new-report"));
            wp.add_action ("network-workgroup", _("Relationships"), _("Connect tables and keep related data consistent"), () => run ("relationships"));
            return wp;
        }

        private void update_home () {
            if (db == null) return;
            int t = db.table_names ().size, q = db.view_names ().size + db.object_names ("action:").size, f = db.object_names ("form:").size, r = db.object_names ("report:").size;
            home.title = db.display_name ();
            home.subtitle = _("%s, %s, %s and %s").printf (
                ngettext ("%d table", "%d tables", t).printf (t), ngettext ("%d query", "%d queries", q).printf (q),
                ngettext ("%d form", "%d forms", f).printf (f), ngettext ("%d report", "%d reports", r).printf (r));
        }

        private Widget track (string name, Widget w) {
            bubble_map[name] = w;
            doc_bubbles.add (w);
            return w;
        }

        private void build_bubbles () {
            track ("back", add_bubble_icon ("go-previous-symbolic", _("Close Database (Ctrl+W)"), () => run ("close-db")));
            ribbon.attach (this);
            track ("tabs", ribbon.tabs);
            search_bubble = add_bubble_search (_("Search Records"), (text) => {
                if (current != null) current.search (text);
            });
            track ("search", search_bubble);
            var save = add_bubble_suggested (_("Save"), () => run ("save"));
            track ("save", save);
        }

        private RibbonButton anchored (RibbonContext c, string name, string icon, string label, string? action, bool with_label = false) {
            var b = c.add_button (icon, label, null, action != null ? "win." + action : null);
            b.label_in_compact = with_label;
            anchors[name] = b.widget;
            return b;
        }

        private RibbonButton page_button (RibbonContext c, string name, string icon, string label, string bubble_name, bool with_label = false) {
            var b = c.add_button (icon, label);
            b.label_in_compact = with_label;
            anchors[bubble_name] = b.widget;
            callback_items[name] = bubble_name;
            gated_items[name] = b;
            b.activated.connect (() => page_action (name));
            return b;
        }

        private RibbonButton design_button (RibbonContext c, string icon, string label, string action, Variant? param = null, bool with_label = false) {
            var b = c.add_button (icon, label);
            b.label_in_compact = with_label;
            string key = param != null ? action + ":" + param.print (false) : action;
            gated_items[key] = b;
            callback_items[key] = "";
            b.activated.connect (() => {
                page_action (action, param);
                sync_bubbles ();
            });
            return b;
        }

        private ContextRibbon build_ribbon () {
            var r = new ContextRibbon ();
            build_home_context (r.add_context ("home", _("Home"), "go-home-symbolic"));
            build_create_context (r.add_context ("create", _("Create"), "list-add-symbolic"));
            build_external_context (r.add_context ("external", _("External Data"), "document-send-symbolic"));
            build_tools_context (r.add_context ("tools", _("Database Tools"), "db-key-symbolic"));
            build_table_design (r.add_context ("table-design", _("Table Design"), "db-table-symbolic"));
            build_query_design (r.add_context ("query-design", _("Query Design"), "db-query-symbolic"));
            build_form_design (r.add_context ("form-design", _("Form Design"), "db-form-symbolic"));
            build_report_design (r.add_context ("report-design", _("Report Design"), "db-report-symbolic"));
            build_print_preview (r.add_context ("print-preview", _("Print Preview"), "document-print-symbolic"));
            build_relationship_design (r.add_context ("relationship-design", _("Relationship Design"), "db-relationship-symbolic"));
            return r;
        }

        private void build_home_context (RibbonContext c) {
            view_selector = c.add_selector (_("View"), 9, "db-view-symbolic");
            view_selector.text = _("View");
            view_selector.changed.connect ((m) => {
                if (switching || current == null) return;
                switch_mode (m);
            });
            c.add_separator ();
            undo_item = c.add_button ("edit-undo-symbolic", _("Undo"));
            undo_item.shortcut = "Ctrl+Z";
            undo_item.activated.connect (() => history ("undo"));
            redo_item = c.add_button ("edit-redo-symbolic", _("Redo"));
            redo_item.shortcut = "Ctrl+Shift+Z";
            redo_item.activated.connect (() => history ("redo"));
            c.add_separator ();
            c.add_button ("edit-cut-symbolic", _("Cut"), null, "win.cut");
            c.add_button ("edit-copy-symbolic", _("Copy"), null, "win.copy");
            c.add_button ("edit-paste-symbolic", _("Paste"), null, "win.paste");
            c.add_separator ();
            c.add_button ("view-sort-ascending-symbolic", _("Ascending"), _("Sort Ascending"), "win.sort-asc");
            c.add_button ("view-sort-descending-symbolic", _("Descending"), _("Sort Descending"), "win.sort-desc");
            anchored (c, "sort", "db-sort-symbolic", _("Sort…"), "sort");
            anchored (c, "filter", "db-filter-symbolic", _("Filter…"), "filter", true);
            var adv = c.add_menu ("db-filter-symbolic", _("Advanced Filter"), _("Advanced Filter Options"));
            gated_items["filter"] = adv;
            callback_items["filter"] = "";
            adv.set_builder ((m) => {
                m.add_item (_("Filter by Selection"), null, () => run ("filter-selection"));
                m.add_item (_("Filter by Form…"), null, () => run ("filter-by-form"));
                m.add_separator ();
                m.add_item (_("Clear Filters and Sorting"), "edit-clear-all-symbolic", () => run ("clear-filters"));
            });
            c.add_button ("edit-clear-all-symbolic", _("Clear Filters and Sorting"), null, "win.clear-filters");
            c.add_separator ();
            c.add_button ("db-record-new-symbolic", _("New Record"), null, "win.new-record");
            c.add_button ("document-save-symbolic", _("Save Record"), null, "win.save-record");
            c.add_button ("edit-delete-symbolic", _("Delete Record"), null, "win.delete-record");
            anchored (c, "totals", "db-totals-symbolic", _("Totals"), "totals-row", true);
            c.add_button ("view-refresh-symbolic", _("Refresh All"), null, "win.refresh-records");
            c.add_separator ();
            views_item = page_button (c, "views-menu", "db-view-grid-symbolic", _("Views"), "views", true);
            anchored (c, "group", "db-group-symbolic", _("Group…"), "group");
            anchored (c, "fields", "db-fields-symbolic", _("Hide Fields…"), "hide-fields");
            c.add_button ("db-table-symbolic", _("Subdatasheet…"), null, "win.subdatasheet");
            c.add_separator ();
            c.add_button ("edit-find-replace-symbolic", _("Replace…"), null, "win.replace");
            c.add_button ("go-jump-symbolic", _("Go To Record…"), null, "win.goto");
            c.add_separator ();
            var run_item = c.add_button ("db-run-symbolic", _("Run"), null, "win.run");
            run_item.label_in_compact = true;
        }

        private void build_create_context (RibbonContext c) {
            var t = c.add_button ("db-table-symbolic", _("Table"), _("New Table"), "win.new-table");
            t.label_in_compact = true;
            c.add_separator ();
            var q = c.add_button ("db-query-symbolic", _("Query Design"), _("New Query"), "win.new-query");
            q.label_in_compact = true;
            var sql = c.add_button ("db-sql-symbolic", _("SQL Query"), _("New SQL Query"), "win.new-sql");
            sql.label_in_compact = true;
            c.add_separator ();
            var f = c.add_button ("db-form-symbolic", _("Form"), _("New Form"), "win.new-form");
            f.label_in_compact = true;
            var r = c.add_button ("db-report-symbolic", _("Report"), _("New Report"), "win.new-report");
            r.label_in_compact = true;
            c.add_separator ();
            var m = c.add_button ("db-run-symbolic", _("Macro"), _("New Macro"), "win.new-macro");
            m.label_in_compact = true;
            var mod = c.add_button ("db-snippet-symbolic", _("Module"), _("New Module"), "win.new-module");
            mod.label_in_compact = true;
            c.add_separator ();
            c.add_button ("db-view-symbolic", _("Saved View…"), null, "win.new-view");
        }

        private void build_external_context (RibbonContext c) {
            var imp = c.add_button ("document-open-symbolic", _("Import…"), _("Import Data"), "win.import");
            imp.label_in_compact = true;
            var link = c.add_button ("db-connection-symbolic", _("Link Tables…"), null, "win.link-tables");
            link.label_in_compact = true;
            c.add_button ("db-schema-symbolic", _("Linked Table Manager…"), null, "win.linked-tables");
            c.add_separator ();
            var ex = anchored (c, "export", "document-send-symbolic", _("Export…"), "export", true);
            ex.tooltip = _("Export Object");
            var whole = c.add_menu ("document-save-as-symbolic", _("Export Database"), _("Export the Whole Database"));
            whole.set_builder ((m) => {
                m.add_item (_("Excel Workbook…"), "x-office-spreadsheet-symbolic", () => run ("export-workbook"));
                m.add_item (_("SQL Script…"), "db-sql-symbolic", () => run ("export-sql"));
                m.add_item (_("JSON…"), null, () => run ("export-json"));
            });
            c.add_separator ();
            anchored (c, "print", "document-print-symbolic", _("Print…"), "print", true);
            anchored (c, "pdf", "x-office-document-symbolic", _("Export Report…"), "export-pdf");
            c.add_separator ();
            anchored (c, "share", "singularity-share-symbolic", _("Share"), "share", true);
            c.add_button ("x-office-spreadsheet-symbolic", _("Share as Workbook"), null, "win.share-export");
        }

        private void build_tools_context (RibbonContext c) {
            var rel = c.add_button ("db-relationship-symbolic", _("Relationships"), null, "win.relationships");
            rel.label_in_compact = true;
            c.add_button ("db-index-symbolic", _("Object Dependencies…"), null, "win.dependencies");
            c.add_separator ();
            var doc = c.add_button ("db-report-symbolic", _("Documenter…"), _("Database Documenter"), "win.documenter");
            doc.label_in_compact = true;
            c.add_button ("db-explain-symbolic", _("Analyze Performance…"), null, "win.analyze");
            c.add_separator ();
            var compact = c.add_button ("db-history-symbolic", _("Compact and Repair"), _("Compact and Repair Database"), "win.compact");
            compact.label_in_compact = true;
            c.add_button ("emblem-ok-symbolic", _("Check Integrity"), null, "win.check");
            c.add_button ("changes-prevent-symbolic", _("Encrypt with Password…"), null, "win.encrypt");
            c.add_separator ();
            c.add_button ("db-server-symbolic", _("Split Database…"), null, "win.split-database");
            c.add_button ("db-run-symbolic", _("Run Macro…"), null, "win.run-macro");
            c.add_separator ();
            c.add_button ("document-edit-symbolic", _("Rename…"), null, "win.rename");
            c.add_button ("edit-delete-symbolic", _("Delete Object…"), null, "win.delete-object");
            c.add_separator ();
            var opt = c.add_button ("document-properties-symbolic", _("Options…"), _("Current Database Options"), "win.startup-options");
            opt.label_in_compact = true;
        }

        private void build_table_design (RibbonContext c) {
            page_button (c, "primary-key", "db-key-symbolic", _("Primary Key"), "primary-key", true);
            anchored (c, "add-field", "db-field-add-symbolic", _("Add Field"), "add-field", true);
            c.add_separator ();
            c.add_button ("db-relationship-symbolic", _("Relationships"), null, "win.relationships");
            c.add_button ("db-index-symbolic", _("Object Dependencies…"), null, "win.dependencies");
        }

        private void build_query_design (RibbonContext c) {
            var run_item = c.add_button ("db-run-symbolic", _("Run"), null, "win.run");
            run_item.label_in_compact = true;
            page_button (c, "add-table", "db-table-symbolic", _("Add Table"), "add-table", true);
            c.add_separator ();
            c.add_button ("db-sql-symbolic", _("SQL View"), null, "win.view-sql");
            c.add_button ("db-view-grid-symbolic", _("Results"), _("Datasheet View"), "win.view-data");
        }

        private void build_form_design (RibbonContext c) {
            ControlKind[] kinds = { ControlKind.TEXT, ControlKind.LABEL, ControlKind.BUTTON, ControlKind.COMBO, ControlKind.LIST, ControlKind.CHECK, ControlKind.OPTION_GROUP, ControlKind.TOGGLE, ControlKind.TAB, ControlKind.IMAGE, ControlKind.LINE, ControlKind.RECTANGLE, ControlKind.SUBFORM, ControlKind.CHART };
            string[] icons = FormDesigner.CONTROL_ICONS;
            for (int i = 0; i < kinds.length; i++) {
                var b = design_button (c, icons[i], kinds[i].label (), "design-add", new Variant.int32 ((int) kinds[i]));
                b.tooltip = _("Add %s").printf (kinds[i].label ());
            }
            var calc = design_button (c, "db-function-symbolic", _("Calculated Text Box"), "design-calc");
            calc.tooltip = _("Add Calculated Text Box");
            c.add_separator ();
            anchored (c, "form-add-field", "db-field-add-symbolic", _("Add Existing Fields"), "add-field", true);
            design_button (c, "db-layout-symbolic", _("Arrange Controls"), "tidy", null, true);
            c.add_separator ();
            design_button (c, "db-sql-symbolic", _("View Code"), "view-code", null, true);
        }

        private void build_report_design (RibbonContext c) {
            design_button (c, "document-edit-symbolic", _("Customize"), "customize", null, true).tooltip = _("Turn the report into a banded design you can edit freely");
            c.add_separator ();
            string[] kinds = ReportDesigner.CONTROL_KINDS;
            string[] labels = ReportDesigner.control_labels ();
            string[] icons = ReportDesigner.CONTROL_ICONS;
            for (int i = 0; i < kinds.length; i++) {
                var b = design_button (c, icons[i], labels[i], "design-add", new Variant.string (kinds[i]));
                b.tooltip = _("Add %s").printf (labels[i]);
            }
            c.add_separator ();
            design_button (c, "db-group-symbolic", _("Group and Sort…"), "group-sort", null, true);
            design_button (c, "db-sql-symbolic", _("View Code"), "view-code", null, true);
        }

        private void build_print_preview (RibbonContext c) {
            var print = c.add_button ("document-print-symbolic", _("Print…"), null, "win.print");
            print.label_in_compact = true;
            var pdf = c.add_button ("x-office-document-symbolic", _("Export Report…"), _("Export the Report as PDF"), "win.export-pdf");
            pdf.label_in_compact = true;
            c.add_separator ();
            c.add_button ("zoom-out-symbolic", _("Zoom Out"), null, "win.zoom-out");
            c.add_button ("zoom-in-symbolic", _("Zoom In"), null, "win.zoom-in");
            c.add_separator ();
            design_button (c, "view-refresh-symbolic", _("Refresh"), "refresh", null, true).tooltip = _("Run the report again");
            c.add_button ("document-edit-symbolic", _("Design View"), null, "win.view-design");
        }

        private void build_relationship_design (RibbonContext c) {
            design_button (c, "db-layout-symbolic", _("Arrange"), "tidy", null, true).tooltip = _("Arrange Tables");
            c.add_separator ();
            c.add_button ("document-print-symbolic", _("Print…"), null, "win.print");
            c.add_button ("x-office-document-symbolic", _("Export as PDF…"), null, "win.export-pdf");
        }

        private string design_context_for (ObjectPage? page) {
            if (page == null) return "";
            switch (page.kind) {
                case "table": return page.mode == "design" ? "table-design" : "";
                case "query": return page.mode == "design" || page.mode == "sql" ? "query-design" : "";
                case "form": return page.mode == "design" ? "form-design" : "";
                case "report": return page.mode == "design" ? "report-design" : "print-preview";
                case "relationships": return "relationship-design";
                default: return "";
            }
        }

        private void sync_ribbon () {
            string want = design_context_for (current);
            foreach (string id in design_contexts) {
                var context = ribbon.get_context (id);
                if (context != null) context.shown = id == want;
            }
            if (want != shown_design) {
                string was = shown_design;
                shown_design = want;
                if (want != "") ribbon.active_context = want;
                else if (ribbon.active_context == was) ribbon.active_context = "home";
            }
            string? active = ribbon.active_context;
            if (active != null && active in design_contexts && active != want) ribbon.active_context = "home";
            var wanted = new Gee.HashSet<string> ();
            if (current != null) foreach (string b in current.bubbles ()) wanted.add (b);
            foreach (var e in gated_items.entries) {
                string bubble_name = callback_items[e.key] ?? "";
                bool ok;
                if (bubble_name != "") ok = wanted.contains (bubble_name);
                else {
                    int colon = e.key.index_of (":");
                    ok = current != null && current.handles (colon > 0 ? e.key.substring (0, colon) : e.key);
                }
                e.value.widget.sensitive = ok;
            }
        }

        private void history (string name) {
            if (current != null && current.handles (name)) {
                current.run_action (name, null);
            } else if (name == "undo") {
                run_db_undo ();
            } else {
                run_db_redo ();
            }
            sync_bubbles ();
        }

        public void run_db_undo () {
            if (db == null || !db.can_undo) return;
            try {
                db.undo ();
            } catch (Error e) {
                show_error (_("Could Not Undo"), e.message);
            }
            sync_bubbles ();
        }

        public void run_db_redo () {
            if (db == null || !db.can_redo) return;
            try {
                db.redo ();
            } catch (Error e) {
                show_error (_("Could Not Redo"), e.message);
            }
            sync_bubbles ();
        }

        public void search_changed_externally (string text) {
            if (search_bubble.text != text) search_bubble.text = text;
        }

        public void page_action (string name, Variant? param = null) {
            if (current != null && current.handles (name)) current.run_action (name, param);
        }

        public Widget? bubble (string name) {
            return bubble_map[name];
        }

        public void popup_at_bubble (Popover pop, string name) {
            var anchor = anchors.has_key (name) ? anchors[name] : bubble_map[name];
            pop.set_parent (content_stack);
            Graphene.Rect bounds = Graphene.Rect ();
            if (anchor != null && anchor.get_mapped () && anchor.compute_bounds (content_stack, out bounds)) {
                var rect = Gdk.Rectangle ();
                rect.x = (int) bounds.origin.x;
                rect.y = (int) bounds.origin.y;
                rect.width = (int) bounds.size.width;
                rect.height = (int) bounds.size.height;
                pop.pointing_to = rect;
            } else {
                var rect = Gdk.Rectangle ();
                rect.x = content_stack.get_width () / 2;
                rect.y = 48;
                rect.width = 1;
                rect.height = 1;
                pop.pointing_to = rect;
            }
            pop.position = PositionType.BOTTOM;
            pop.closed.connect (() => Idle.add (() => {
                pop.unparent ();
                return Source.REMOVE;
            }));
            pop.popup ();
        }

        public void sync_bubbles () {
            var wanted = new Gee.HashSet<string> ();
            if (db != null) {
                wanted.add ("back");
                wanted.add ("tabs");
            }
            if (current != null) {
                foreach (string b in current.bubbles ()) wanted.add (b);
                if (current.dirty ()) wanted.add ("save");
            }
            foreach (var e in bubble_map.entries) e.value.visible = wanted.contains (e.key);
            if (db != null) {
                undo_item.widget.sensitive = db.can_undo || (current != null && current.handles ("undo"));
                redo_item.widget.sensitive = db.can_redo || (current != null && current.handles ("redo"));
                undo_item.tooltip = db.can_undo ? _("Undo %s").printf (db.undo_label) : null;
                redo_item.tooltip = db.can_redo ? _("Redo %s").printf (db.redo_label) : null;
            }
            sync_ribbon ();
            if (current is TablePage) views_item.icon_name = ((TablePage) current).view_icon ();
        }

        private void sync_switcher () {
            if (current == null) {
                view_selector.clear_options ();
                switcher_modes = {};
                view_selector.text = _("View");
                view_selector.widget.sensitive = false;
                return;
            }
            string[] m = current.modes ();
            bool same = m.length == switcher_modes.length;
            for (int i = 0; same && i < m.length; i++) same = m[i] == switcher_modes[i];
            switching = true;
            if (!same) {
                view_selector.clear_options ();
                foreach (string x in m) view_selector.add_option (x, current.mode_label (x));
                switcher_modes = m;
            }
            view_selector.widget.sensitive = m.length > 1;
            if (current.mode != "") view_selector.selected = current.mode;
            else view_selector.text = _("View");
            switching = false;
        }

        private void switch_mode (string m) {
            if (current == null || current.mode == m) return;
            if (current.dirty () && current.kind == "table" && current.mode == "design") {
                var page = current;
                confirm_save_design (page, () => {
                    page.change_mode (m);
                    after_mode ();
                }, () => sync_switcher ());
                return;
            }
            current.change_mode (m);
            after_mode ();
        }

        private void after_mode () {
            sync_switcher ();
            sync_bubbles ();
            sync_actions ();
            update_title ();
            if (current != null) current.focus_content ();
        }

        public void show_welcome () {
            content_stack.visible_child_name = "welcome";
            welcome.refresh ();
            set_title (_("Database"));
            current = null;
            set_sidebar_visible (false);
            sync_bubbles ();
            sync_actions ();
        }

        public void show_error (string title, string message) {
            var dlg = new ConfirmDialog (app, title, "dialog-error", message, _("OK"), ConfirmDialog.ActionStyle.SUGGESTED);
            dlg.transient_for = this;
            dlg.present ();
        }

        public void toast (string text, string? button = null, owned Callback? cb = null) {
            var t = new Toast (text);
            if (button != null) {
                t.button_label = button;
                t.button_clicked.connect (() => {
                    if (cb != null) cb ();
                });
            }
            add_toast (t);
        }

        public delegate void Callback ();

        public void open_database (string path) {
            Database d;
            try {
                d = Database.open (path);
            } catch (CryptError e) {
                ToolDialogs.ask_password (app, this, path, null, (pw) => {
                    try {
                        load (Database.open_with_password (path, pw));
                    } catch (Error e2) {
                        show_error (_("Could Not Open"), e2.message);
                    }
                });
                return;
            } catch (Error e) {
                show_error (_("Could Not Open"), _("\"%s\" could not be opened: %s").printf (Path.get_basename (path), e.message));
                return;
            }
            load (d);
        }

        public void load (Database d) {
            if (db != null) db.close ();
            foreach (var p in pages.values) page_stack.remove (p);
            pages.clear ();
            db = d;
            load_runtime ();
            db.schema_changed.connect (on_schema_changed);
            db.data_changed.connect (on_data_changed);
            db.history_changed.connect (() => sync_bubbles ());
            if (db.path != ":memory:") app.remember (db.path);
            content_stack.visible_child_name = "database";
            rebuild_sidebar ();
            show_home ();
            set_sidebar_visible (app.settings == null || app.settings.get_boolean ("sidebar-visible"));
            sync_actions ();
            apply_startup ();
            apply_sharing_options ();
            connect_server_links ();
        }

        private Gee.HashMap<string, ClientSession> link_sessions = new Gee.HashMap<string, ClientSession> ();
        private bool link_flush_scheduled;
        private bool link_flushing;

        private void connect_server_links () {
            foreach (var s in link_sessions.values) s.disconnect.begin ();
            link_sessions.clear ();
            db.link_changed.connect (on_link_changed);
            foreach (var l in Links.list (db)) {
                if (l.kind == "server") {
                    refresh_server_links.begin (null);
                    return;
                }
            }
        }

        private async ClientSession link_session (string connection) throws Error {
            if (link_sessions.has_key (connection)) return link_sessions[connection];
            var cfg = find_connection (connection);
            if (cfg == null) throw new RemoteError.CONNECT (_("The server connection \"%s\" is not saved on this computer. Add it with Connect to Server.").printf (connection));
            var s = new ClientSession (cfg);
            string? pw = yield ConnectionSecrets.lookup (cfg.id, "db");
            string? spw = yield ConnectionSecrets.lookup (cfg.id, "ssh");
            yield s.connect (pw, spw, null);
            link_sessions[connection] = s;
            return s;
        }

        public async ClientSession open_link_session (string connection) throws Error {
            return yield link_session (connection);
        }

        public async void refresh_server_links (string? only) {
            var target = db;
            foreach (var l in Links.list (target)) {
                if (l.kind != "server" || (only != null && only.casefold () != l.name.casefold ())) continue;
                try {
                    var s = yield link_session (l.path);
                    target.server_data[l.name.casefold ()] = yield ServerLinks.fetch (s.engine, l.remote_schema, l.table);
                } catch (Error e) {
                    var snap = new ServerSnapshot ();
                    snap.error = e.message;
                    target.server_data[l.name.casefold ()] = snap;
                }
            }
            if (target != db) return;
            Links.attach_all (db);
            db.invalidate ();
            db.schema_changed ();
            rebuild_sidebar ();
        }

        private void on_link_changed () {
            if (link_flush_scheduled) return;
            link_flush_scheduled = true;
            Idle.add (() => {
                link_flush_scheduled = false;
                flush_server_links.begin ();
                return false;
            });
        }

        private async void flush_server_links () {
            if (link_flushing || db == null) return;
            link_flushing = true;
            var target = db;
            var refetch = new Gee.TreeSet<string> ();
            string[] errors = {};
            while (target.link_changes.size > 0) {
                var c = target.link_changes.remove_at (0);
                var l = target.linked[c.link.casefold ()];
                var snap = target.server_data[c.link.casefold ()];
                if (l == null || snap == null) continue;
                try {
                    var s = yield link_session (l.path);
                    DbValue[] args;
                    string sql = ServerLinks.statement (s.engine, l, snap, c, out args);
                    yield s.engine.execute (sql, args);
                    if (c.op == "insert" && snap.serial.length > 0) refetch.add (l.name);
                } catch (Error e) {
                    errors += e.message;
                    refetch.add (l.name);
                }
            }
            link_flushing = false;
            if (target != db) return;
            if (errors.length > 0) show_error (_("Could Not Save to the Server"), errors[0]);
            foreach (string n in refetch) yield refresh_server_links (n);
        }

        private uint heartbeat_id;
        private ulong external_id;

        public void apply_sharing_options () {
            DatasheetView.locker = (t, id) => lock_record (t, id);
            DatasheetView.unlocker = (t, id) => unlock_record (t, id);
            if (db == null || db.path == ":memory:") return;
            var opts = StartupOptions.load (db);
            db.stop_change_watch ();
            if (external_id != 0) db.disconnect (external_id);
            external_id = db.external_change.connect (() => {
                db.invalidate ();
                foreach (var p in pages.values) {
                    if (!p.dirty ()) p.reload ();
                }
                rebuild_sidebar ();
            });
            db.start_change_watch (int.max (1, opts.refresh_seconds));
            if (heartbeat_id != 0) Source.remove (heartbeat_id);
            heartbeat_id = Timeout.add_seconds (30, () => {
                if (db == null) {
                    heartbeat_id = 0;
                    return Source.REMOVE;
                }
                try {
                    db.record_locks.heartbeat ();
                } catch (Error e) {
                }
                return Source.CONTINUE;
            });
        }

        public bool lock_record (string table, int64 rowid) {
            if (db == null || table == "" || rowid < 0) return true;
            if (!StartupOptions.load (db).record_locking) return true;
            try {
                db.record_locks.acquire (table, rowid);
                return true;
            } catch (Error e) {
                show_error (_("Record Locked"), e.message);
                return false;
            }
        }

        public void unlock_record (string table, int64 rowid) {
            if (db == null || table == "" || rowid < 0) return;
            try {
                db.record_locks.release (table, rowid);
            } catch (Error e) {
            }
        }

        public void show_pages (string title, Gee.ArrayList<LayoutPage> pages_list, ReportDef def) {
            var dlg = Dialogs.make (this, title, 900, 800);
            var preview = new ReportPreview ();
            preview.vexpand = true;
            preview.height_request = 560;
            preview.show_pages (pages_list);
            dlg.content_box.append (preview);
            var bar = new Box (Orientation.HORIZONTAL, 8);
            bar.halign = Align.END;
            bar.margin_start = bar.margin_end = 18;
            bar.margin_bottom = 16;
            var pdf = new Button.with_label (_("Export…"));
            pdf.clicked.connect (() => save_pages.begin (title, pages_list));
            var print = new Button.with_label (_("Print…"));
            print.add_css_class ("suggested-action");
            print.clicked.connect (() => {
                var source = new Singularity.Print.CallbackSource (title, (format) => pages_list.size, (cr, page, format) => {
                    var p = pages_list[page];
                    double sc = double.min (format.width / p.width, format.height / p.height);
                    ReportRenderer.draw_page (cr, p, sc);
                });
                Singularity.Print.run_source.begin (this, source);
            });
            bar.append (pdf);
            bar.append (print);
            dlg.content_box.append (bar);
            dlg.open_dialog ();
        }

        private async void save_pages (string title, Gee.ArrayList<LayoutPage> pages_list) {
            var fd = new FileDialog ();
            fd.initial_name = title + ".pdf";
            try {
                var file = yield fd.save (this, null);
                if (file == null) return;
                string path = file.get_path ();
                if (path.down ().has_suffix (".pdf")) ReportRenderer.export_pdf (pages_list, path, title);
                else ReportDocument.build (pages_list, title).save (path);
                toast (_("Exported \"%s\"").printf (Path.get_basename (path)));
            } catch (Error e) {
                if (!(e is Gtk.DialogError.DISMISSED)) show_error (_("Could Not Export"), e.message);
            }
        }

        private void on_schema_changed () {
            if (refresh_id != 0) return;
            refresh_id = Idle.add (() => {
                refresh_id = 0;
                if (db == null) return Source.REMOVE;
                rebuild_sidebar ();
                update_home ();
                var gone = new Gee.ArrayList<string> ();
                foreach (var e in pages.entries) {
                    if (!object_alive (e.value)) gone.add (e.key);
                }
                foreach (string k in gone) {
                    var p = pages[k];
                    bool was_current = p == current;
                    pages.unset (k);
                    page_stack.remove (p);
                    if (was_current) show_home ();
                }
                foreach (var p in pages.values) p.reload ();
                sync_bubbles ();
                return Source.REMOVE;
            });
        }

        private void on_data_changed (string table) {
            foreach (var p in pages.values) {
                if (p != current || table == "") p.reload ();
            }
            sync_bubbles ();
        }

        private bool object_alive (ObjectPage p) {
            switch (p.kind) {
                case "table": return db.object_exists (p.object_name, "table");
                case "query": return p.object_name.has_prefix ("\n") || db.object_exists (p.object_name, "view") || db.get_meta ("action:" + p.object_name) != null || ((QueryPage) p).unsaved;
                case "form": return db.get_meta ("form:" + p.object_name) != null || ((FormPage) p).unsaved;
                case "report": return db.get_meta ("report:" + p.object_name) != null || ((ReportPage) p).unsaved;
                case "macro": return db.get_meta ("macro:" + p.object_name) != null || ((MacroPage) p).unsaved;
                case "module": return db.get_meta ("module:" + p.object_name) != null || ((ModulePage) p).unsaved;
                default: return true;
            }
        }

        public void show_home () {
            current = null;
            update_home ();
            page_stack.visible_child_name = "home";
            foreach (var r in rows.values) r.set_active (false);
            if (rows.has_key ("home")) rows["home"].set_active (true);
            update_title ();
            sync_switcher ();
            sync_bubbles ();
            sync_actions ();
        }

        private void update_title () {
            if (db == null) {
                set_title (_("Database"));
                return;
            }
            string name = db.display_name ();
            if (current != null) set_title ("%s: %s".printf (name, current.title ()));
            else set_title (name);
        }

        private void add_section (string title) {
            var label = new SidebarSectionLabel (title);
            object_list.append (label);
        }

        private SidebarRow add_row (string key, string icon, string title, owned Callback open_cb, string? badge = null) {
            var row = new SidebarRow (icon, title);
            if (badge != null && badge != "") {
                var inner = row.get_child () as Box;
                if (inner != null) {
                    var b = new Label (badge);
                    b.add_css_class ("db-sidebar-badge");
                    inner.append (b);
                }
            }
            row.clicked.connect (() => open_cb ());
            var click = new GestureClick ();
            click.button = 3;
            string k = key;
            click.pressed.connect ((n, x, y) => object_menu (k, row, x, y));
            row.add_controller (click);
            rows[key] = row;
            object_list.append (row);
            if (current != null && current.key () == key) row.set_active (true);
            return row;
        }

        private bool matches (string name) {
            return object_filter == "" || name.casefold ().contains (object_filter);
        }

        public void rebuild_sidebar () {
            Widget? child;
            while ((child = object_list.get_first_child ()) != null) object_list.remove (child);
            rows.clear ();
            if (db == null) return;
            if (object_filter == "") {
                var h = add_row ("home", "user-home-symbolic", _("Overview"), () => show_home ());
                if (current == null) h.set_active (true);
                add_row ("relationships:", "db-relationship-symbolic", _("Relationships"), () => open_relationships ());
            }
            var tables = db.table_names ();
            var queries = db.view_names ();
            queries.add_all (db.object_names ("action:"));
            queries.sort ((a, b) => a.collate (b));
            var forms = db.object_names ("form:");
            var reports = db.object_names ("report:");
            var macros = db.object_names ("macro:");
            var modules = db.object_names ("module:");
            bool any = false;
            string[] titles = { _("Tables"), _("Queries"), _("Forms"), _("Reports"), _("Macros"), _("Modules") };
            string[] kinds = { "table", "query", "form", "report", "macro", "module" };
            string[] icons = { "db-table-symbolic", "db-query-symbolic", "db-form-symbolic", "db-report-symbolic", "db-run-symbolic", "db-sql-symbolic" };
            Gee.ArrayList<string>[] lists = { tables, queries, forms, reports, macros, modules };
            for (int s = 0; s < 6; s++) {
                bool header = false;
                int shown = 0;
                foreach (string n in lists[s]) if (matches (n)) shown++;
                foreach (string n in lists[s]) {
                    if (!matches (n)) continue;
                    if (!header) {
                        add_section ("%s  %d".printf (titles[s], shown));
                        header = true;
                    }
                    any = true;
                    string kind = kinds[s];
                    string name = n;
                    string badge = kind == "table" ? compact_count (db.count_rows (name)) : "";
                    if (kind == "table" && db.is_linked (name)) badge = _("linked");
                    add_row (kind + ":" + name, icons[s], name, () => open_object (kind, name), badge);
                }
            }
            if (!any && object_filter != "") {
                var none = new Label (_("No objects match."));
                none.add_css_class ("dim-label");
                none.margin_top = 12;
                object_list.append (none);
            }
        }

        private void object_menu (string key, Widget anchor, double x, double y) {
            int colon = key.index_of (":");
            string kind = key.substring (0, colon);
            string name = key.substring (colon + 1);
            if (kind == "home" || kind == "relationships") return;
            var menu = new ContextMenu (anchor);
            var r = Gdk.Rectangle ();
            r.x = (int) x;
            r.y = (int) y;
            r.width = 1;
            r.height = 1;
            menu.pointing_to = r;
            menu.add_item (_("Open"), "document-open-symbolic", () => open_object (kind, name));
            if (kind == "table" || kind == "query") menu.add_item (_("Design View"), "document-edit-symbolic", () => open_object (kind, name, "design"));
            if (kind == "form" || kind == "report") menu.add_item (_("Design View"), "document-edit-symbolic", () => open_object (kind, name, "design"));
            if (kind == "macro") menu.add_item (_("Run"), "db-run-symbolic", () => run_macro (name));
            if (kind == "table") menu.add_item (_("Data Macros…"), "db-run-symbolic", () => DataMacroDialog.show (this, name));
            menu.add_separator ();
            if (kind == "table" || kind == "query") {
                menu.add_item (_("New Form"), "db-form-symbolic", () => create_form (name));
                menu.add_item (_("New Report"), "db-report-symbolic", () => create_report (name));
                menu.add_item (_("Export…"), "document-send-symbolic", () => TransferDialogs.export_object (this, name));
            }
            if (kind == "table") menu.add_item (_("Duplicate…"), "edit-copy-symbolic", () => Dialogs.duplicate_table (this, name));
            menu.add_item (_("Object Dependencies…"), "db-relationship-symbolic", () => ToolDialogs.dependencies (this, kind, name));
            menu.add_item (_("Rename…"), "document-edit-symbolic", () => Dialogs.rename_object (this, kind, name));
            menu.add_separator ();
            menu.add_item (_("Delete…"), "user-trash-symbolic", () => Dialogs.delete_object (this, kind, name), "destructive");
            DatabaseWindow.popup_menu (menu);
        }

        public static string compact_count (int64 n) {
            if (n < 1000) return n.to_string ();
            if (n < 1000000) return "%.1fk".printf (n / 1000.0).replace (".0k", "k");
            return "%.1fM".printf (n / 1000000.0).replace (".0M", "M");
        }

        public static void popup_menu (ContextMenu menu) {
            menu.closed.connect (() => Idle.add (() => {
                menu.unparent ();
                return Source.REMOVE;
            }));
            menu.popup ();
        }

        private void show_create_menu (Widget anchor) {
            var menu = new ContextMenu (anchor);
            menu.add_item (_("Table"), "db-table-symbolic", () => run ("new-table"));
            menu.add_item (_("Query"), "db-query-symbolic", () => run ("new-query"));
            menu.add_item (_("SQL Query"), "db-sql-symbolic", () => run ("new-sql"));
            menu.add_item (_("Form"), "db-form-symbolic", () => run ("new-form"));
            menu.add_item (_("Report"), "db-report-symbolic", () => run ("new-report"));
            menu.add_item (_("Macro"), "db-run-symbolic", () => run ("new-macro"));
            menu.add_item (_("Module"), "db-sql-symbolic", () => run ("new-module"));
            menu.add_separator ();
            menu.add_item (_("Import Data…"), "document-open-symbolic", () => run ("import"));
            popup_menu (menu);
        }

        public ObjectPage? find_page (string kind, string name) {
            return pages[kind + ":" + name];
        }

        public void open_object (string kind, string name, string? mode = null) {
            if (db == null) return;
            string key = kind + ":" + name;
            ObjectPage? page = pages[key];
            if (page == null) {
                try {
                    switch (kind) {
                        case "table": page = new TablePage (this, name); break;
                        case "query": page = new QueryPage (this, name); break;
                        case "form": page = new FormPage (this, name); break;
                        case "report": page = new ReportPage (this, name); break;
                        case "relationships": page = new RelationshipsPage (this); break;
                        case "macro": page = new MacroPage (this, name); break;
                        case "module": page = new ModulePage (this, name); break;
                        default: return;
                    }
                } catch (Error e) {
                    show_error (_("Could Not Open"), e.message);
                    return;
                }
                pages[key] = page;
                page_stack.add_named (page, key);
                page.mode_changed.connect (() => {
                    if (page == current) after_mode ();
                });
                page.title_changed.connect (() => {
                    if (page == current) update_title ();
                    sync_bubbles ();
                });
            }
            show_page (page);
            if (mode != null && page.mode != mode) {
                page.change_mode (mode);
                after_mode ();
            }
        }

        public void show_page (ObjectPage page) {
            current = page;
            page_stack.visible_child = page;
            foreach (var r in rows.values) r.set_active (false);
            if (rows.has_key (page.key ())) rows[page.key ()].set_active (true);
            search_bubble.text = page.search_text ();
            sync_switcher ();
            sync_bubbles ();
            sync_actions ();
            update_title ();
            page.focus_content ();
        }

        public void adopt_page (ObjectPage page, string old_key) {
            if (pages.has_key (old_key) && pages[old_key] == page) pages.unset (old_key);
            pages[page.key ()] = page;
            rebuild_sidebar ();
            show_page (page);
        }

        public void forget_page (ObjectPage page) {
            pages.unset (page.key ());
            page_stack.remove (page);
            if (current == page) show_home ();
        }

        public void open_relationships () {
            open_object ("relationships", "");
        }

        public void new_database () {
            if (db != null) {
                var w = new DatabaseWindow (app);
                w.present ();
                w.new_database ();
                return;
            }
            string path = app.unique_path (_("Database"));
            try {
                load (Database.create (path));
                toast (_("Created \"%s\" in %s").printf (Path.get_basename (path), friendly_folder (Path.get_dirname (path))));
            } catch (Error e) {
                show_error (_("Could Not Create Database"), e.message);
            }
        }

        public void new_from_template (string id) {
            if (db != null) {
                var w = new DatabaseWindow (app);
                w.present ();
                w.new_from_template (id);
                return;
            }
            string title = id;
            foreach (var t in Templates.list ()) {
                if (t.id == id) title = t.title;
            }
            string path = app.unique_path (title);
            try {
                var d = Database.create (path);
                Templates.build (d, id);
                load (d);
                var tables = d.table_names ();
                var forms = d.object_names ("form:");
                if (forms.size > 0) open_object ("form", forms[0]);
                else if (tables.size > 0) open_object ("table", tables[0]);
                toast (_("Created \"%s\" in %s").printf (Path.get_basename (path), friendly_folder (Path.get_dirname (path))));
            } catch (Error e) {
                show_error (_("Could Not Create Database"), e.message);
            }
        }

        public static string friendly_folder (string path) {
            string home = Environment.get_home_dir ();
            if (path.has_prefix (home)) return "~" + path.substring (home.length);
            return path;
        }

        public void convert_access (string path) {
            string base_name = Path.get_basename (path);
            int dot = base_name.last_index_of (".");
            if (dot > 0) base_name = base_name.substring (0, dot);
            string target = app.unique_path (base_name);
            try {
                var d = Database.create (target);
                Gee.ArrayList<ImportResult> results;
                try {
                    results = Transfer.import_mdb (d, path);
                } catch (MdbError.PASSWORD pe) {
                    d.close ();
                    FileUtils.remove (target);
                    when_mapped (() => ToolDialogs.ask_password (app, this, path, null, (pw) => convert_access_with (path, pw)));
                    return;
                }
                d.clear_history ();
                load (d);
                int rows_n = 0;
                string[] notes = {};
                foreach (var r in results) {
                    rows_n += r.imported;
                    foreach (string n in r.notes) notes += n;
                }
                toast (_("Converted %s: %s").printf (Path.get_basename (path), ngettext ("%d table", "%d tables", results.size).printf (results.size) + ", " + ngettext ("%d record", "%d records", rows_n).printf (rows_n)));
                if (notes.length > 0) when_mapped (() => Dialogs.notes (this, _("Access Database Converted"), notes));
                if (results.size > 0) open_object ("table", results[0].table);
            } catch (Error e) {
                FileUtils.remove (target);
                show_error (_("Could Not Open Access Database"), e.message);
            }
        }

        public void convert_access_with (string path, string password) {
            string base_name = Path.get_basename (path);
            int dot = base_name.last_index_of (".");
            if (dot > 0) base_name = base_name.substring (0, dot);
            string target = app.unique_path (base_name);
            try {
                var d = Database.create (target);
                var results = Transfer.import_mdb (d, path, password);
                d.clear_history ();
                load (d);
                if (results.size > 0) open_object ("table", results[0].table);
            } catch (MdbError.PASSWORD pe) {
                FileUtils.remove (target);
                ToolDialogs.ask_password (app, this, path, null, (pw) => convert_access_with (path, pw), pe.message);
            } catch (Error e) {
                FileUtils.remove (target);
                show_error (_("Could Not Open Access Database"), e.message);
            }
        }

        public void import_into_new (string path) {
            string base_name = Path.get_basename (path);
            int dot = base_name.last_index_of (".");
            if (dot > 0) base_name = base_name.substring (0, dot);
            string target = app.unique_path (base_name);
            try {
                var d = Database.create (target);
                load (d);
                when_mapped (() => TransferDialogs.import_file (this, path));
            } catch (Error e) {
                show_error (_("Could Not Import"), e.message);
            }
        }

        public void when_mapped (owned Callback cb) {
            if (get_mapped ()) {
                Timeout.add (150, () => {
                    cb ();
                    return Source.REMOVE;
                });
                return;
            }
            ulong id = 0;
            id = map.connect (() => {
                disconnect (id);
                Timeout.add (300, () => {
                    cb ();
                    return Source.REMOVE;
                });
            });
        }

        public void close_database () {
            if (db == null) {
                show_welcome ();
                return;
            }
            confirm_pages (() => {
                foreach (var p in pages.values) page_stack.remove (p);
                pages.clear ();
                db.close ();
                db = null;
                rebuild_sidebar ();
                show_welcome ();
            });
        }

        private void confirm_pages (owned Callback then) {
            ObjectPage? dirty = null;
            foreach (var p in pages.values) {
                if (p.dirty ()) dirty = p;
            }
            if (dirty == null) {
                then ();
                return;
            }
            show_page (dirty);
            confirm_save_design (dirty, () => confirm_pages ((owned) then), null);
        }

        public void confirm_save_design (ObjectPage page, owned Callback then, owned Callback? cancelled) {
            var dlg = new ConfirmDialog (app, _("Save Changes to \"%s\"?").printf (page.title ()), "dialog-warning",
                _("The design has changes that are not saved yet."), _("Discard"), ConfirmDialog.ActionStyle.DESTRUCTIVE);
            dlg.set_secondary (_("Save"), ConfirmDialog.ActionStyle.SUGGESTED);
            dlg.transient_for = this;
            dlg.response.connect ((r) => {
                if (r == ConfirmDialog.Response.CANCEL) {
                    if (cancelled != null) cancelled ();
                    return;
                }
                if (r == ConfirmDialog.Response.SECONDARY) {
                    if (!page.save ()) {
                        if (cancelled != null) cancelled ();
                        return;
                    }
                } else {
                    page.reload ();
                    if (page.dirty ()) {
                        pages.unset (page.key ());
                        page_stack.remove (page);
                        if (current == page) current = null;
                    }
                }
                sync_bubbles ();
                then ();
            });
            dlg.present ();
        }

        private bool on_close_request () {
            if (close_confirmed || db == null) {
                if (db != null) db.close ();
                return false;
            }
            bool any = false;
            foreach (var p in pages.values) {
                if (p.dirty ()) any = true;
            }
            if (!any) {
                db.close ();
                return false;
            }
            confirm_pages (() => {
                close_confirmed = true;
                close ();
            });
            return true;
        }

        public void create_table () {
            Dialogs.new_table (this);
        }

        public void create_query (bool sql) {
            if (db == null) return;
            var page = new QueryPage.untitled (this, sql);
            pages[page.key ()] = page;
            page_stack.add_named (page, page.key ());
            page.mode_changed.connect (() => {
                if (page == current) after_mode ();
            });
            page.title_changed.connect (() => {
                if (page == current) update_title ();
                sync_bubbles ();
            });
            show_page (page);
        }

        private void add_untitled (ObjectPage page) {
            pages[page.key ()] = page;
            page_stack.add_named (page, page.key ());
            page.mode_changed.connect (() => {
                if (page == current) after_mode ();
            });
            page.title_changed.connect (() => {
                if (page == current) update_title ();
                sync_bubbles ();
            });
            show_page (page);
        }

        public void create_macro () {
            if (db == null) return;
            add_untitled (new MacroPage.untitled (this));
        }

        public void create_module () {
            if (db == null) return;
            add_untitled (new ModulePage.untitled (this));
        }

        public void load_runtime () {
            host = new DbHost (this);
            runtime = new ScriptRuntime (db, host);
            ReportRenderer.runtime = runtime;
            ReportEngine.param_supplier = (n) => reference_value (n);
            runtime.macro_runner = (name) => {
                var r = new MacroRunner (runtime);
                r.run_named (name);
            };
            foreach (string m in db.object_names ("module:")) {
                var o = Meta.parse_object (db.get_meta ("module:" + m));
                if (o == null) continue;
                try {
                    runtime.load_module (o.get_string_member_with_default ("code", ""), m);
                } catch (Error e) {
                    host.debug_print (_("Module %s: %s").printf (m, e.message));
                }
            }
        }

        public void run_macro (string name) {
            if (runtime == null) return;
            try {
                var r = new MacroRunner (runtime);
                r.context = (current is FormPage) ? ((FormPage) current).script_object () : null;
                r.run_named (name);
            } catch (Error e) {
                if (!(e is ScriptError.CANCELLED)) show_error (_("The Macro Stopped"), e.message);
            }
            sync_bubbles ();
        }

        public ObjectPage? current_page () {
            return current;
        }

        public string[] open_names (string kind) {
            string[] names = {};
            foreach (var p in pages.values) {
                if (p.kind == kind && !p.object_name.has_prefix ("\n")) names += p.object_name;
            }
            return names;
        }

        public void close_object (string kind, string name) {
            ObjectPage? p = null;
            if (kind == "" && name == "") p = current;
            else if (kind == "") {
                foreach (var x in pages.values) {
                    if (x.object_name == name) p = x;
                }
            } else {
                p = pages[kind + ":" + name];
            }
            if (p == null) return;
            if (p is FormPage && !((FormPage) p).before_close ()) return;
            forget_page (p);
        }

        public void run_saved_action (string name) throws Error {
            var q = SavedQueries.load (db, name);
            if (q == null) throw new SchemaError.NOT_FOUND (_("The query \"%s\" does not exist.").printf (name));
            var params = QueryPrep.find_parameters (db, q.sql);
            foreach (var p in params) {
                var v = reference_value (p.name);
                if (v != null) p.value = v;
                else if (host != null) {
                    string? typed = host.input_box (p.name, _("Enter Parameter Value"), "");
                    if (typed == null) return;
                    p.value = QueryPrep.coerce (p, typed);
                }
            }
            string sql = QueryPrep.prepare (db, q.sql, params);
            ResultSet? last;
            db.execute_script (sql, out last);
            rebuild_sidebar ();
        }

        public DbValue? reference_value (string name) {
            string n = name.strip ();
            string low = n.down ();
            if (low.has_prefix ("forms!") || low.has_prefix ("forms.") || low.has_prefix ("tempvars!") || low.has_prefix ("tempvars.") || low.has_prefix ("reports!")) {
                if (runtime == null) return null;
                string expr = n.replace (".", "!");
                string[] parts = expr.split ("!");
                var sb = new StringBuilder (parts[0]);
                for (int i = 1; i < parts.length; i++) sb.append ("![").append (parts[i].replace ("[", "").replace ("]", "")).append ("]");
                try {
                    return runtime.evaluate (sb.str).to_db ();
                } catch (Error e) {
                    return null;
                }
            }
            return null;
        }

        public delegate void PassError (string message);

        public ConnectionConfig? find_connection (string key) {
            foreach (var c in ConnectionStore.get_default ().items) {
                if (c.id == key || c.name.casefold () == key.casefold ()) return c;
            }
            return null;
        }

        public void run_pass_through (string connection, string sql, Box into, owned PassError on_error) {
            var cfg = find_connection (connection);
            if (cfg == null) {
                on_error (_("The server connection \"%s\" is not saved on this computer. Add it with Connect to Server.").printf (connection));
                return;
            }
            pass_through_async.begin (cfg, sql, into, (obj, res) => {
                try {
                    pass_through_async.end (res);
                } catch (Error e) {
                    on_error (e.message);
                }
            });
        }

        private async void pass_through_async (ConnectionConfig cfg, string sql, Box into) throws Error {
            var session = new ClientSession (cfg);
            string? pw = yield ConnectionSecrets.lookup (cfg.id, "db");
            string? spw = yield ConnectionSecrets.lookup (cfg.id, "ssh");
            yield session.connect (pw, spw, null);
            try {
                var result = yield session.engine.execute (sql, null, null, 50000);
                Widget? c;
                while ((c = into.get_first_child ()) != null) into.remove (c);
                if (!result.has_rows ()) {
                    var sp = new StatusPage ();
                    sp.icon_name = "db-run-symbolic";
                    sp.title = _("Statement Run on the Server");
                    if (result.affected >= 0) sp.description = ngettext ("%lld row affected.", "%lld rows affected.", (ulong) result.affected).printf (result.affected);
                    else sp.description = result.command;
                    sp.vexpand = true;
                    into.append (sp);
                    return;
                }
                var grid = new ResultGrid ();
                grid.set_result (result.columns, result.rows, null);
                var scroll = new ScrolledWindow ();
                scroll.vexpand = true;
                scroll.child = grid;
                into.append (scroll);
                var status = new StatusStrip ();
                status.set_text (_("%s from %s, read only").printf (ngettext ("%d row", "%d rows", result.rows.size).printf (result.rows.size), cfg.name));
                into.append (status);
            } finally {
                yield session.disconnect ();
            }
        }

        public void error_bell () {
            var surface = get_surface ();
            if (surface != null) surface.beep ();
        }

        public void export_object_to (string kind, string name, string path) throws Error {
            if (kind == "report") {
                var def = ReportDef.from_json (name, db.get_meta ("report:" + name));
                if (def == null) throw new SchemaError.NOT_FOUND (_("The report \"%s\" does not exist.").printf (name));
                var src = ReportEngine.open_source (db, def);
                var pages_list = new ReportRenderer ().layout (def, src);
                if (path.down ().has_suffix (".pdf")) ReportRenderer.export_pdf (pages_list, path, def.title);
                else ReportDocument.build (pages_list, def.title).save (path);
                return;
            }
            var rs = new RecordSource (db, name);
            TransferDialogs.write_source (rs, path);
        }

        public void share_object (string kind, string name) {
            try {
                string dir = Path.build_filename (Environment.get_user_cache_dir (), "dev.sinty.database", "share");
                DirUtils.create_with_parents (dir, 0700);
                string path = Path.build_filename (dir, name.replace ("/", "_") + (kind == "report" ? ".pdf" : ".xlsx"));
                export_object_to (kind, name, path);
                var file = File.new_for_path (path);
                Singularity.Share.files (this, { file });
            } catch (Error e) {
                show_error (_("Could Not Share"), e.message);
            }
        }

        public void transfer (bool export, string table, string path) throws Error {
            if (export) {
                TransferDialogs.write_source (new RecordSource (db, table), path);
                return;
            }
            TransferDialogs.import_path (this, path, table);
        }

        private void apply_startup () {
            if (db == null) return;
            var opts = StartupOptions.load (db);
            if (opts.app_title != "") set_title (opts.app_title);
            if (opts.hide_navigation) set_sidebar_visible (false);
            if (opts.startup_form != "" && db.get_meta ("form:" + opts.startup_form) != null) open_object ("form", opts.startup_form);
            if (db.get_meta ("macro:AutoExec") != null) {
                when_mapped (() => run_macro ("AutoExec"));
            }
        }

        public void create_form (string? source = null) {
            if (db == null) return;
            if (source == null) {
                Dialogs.choose_source (this, _("New Form"), _("Create"), (src, layout) => create_form_from (src, layout));
                return;
            }
            create_form_from (source, FormLayout.COLUMNAR);
        }

        private void create_form_from (string source, FormLayout layout) {
            try {
                var def = FormDef.generate (db, source, layout);
                db.save_object_meta (_("Create Form"), "form:", def.name, def.to_json ());
                rebuild_sidebar ();
                open_object ("form", def.name);
            } catch (Error e) {
                show_error (_("Could Not Create Form"), e.message);
            }
        }

        public void create_report (string? source = null) {
            if (db == null) return;
            if (source == null) {
                Dialogs.choose_source (this, _("New Report"), _("Create"), (src, layout) => create_report_from (src));
                return;
            }
            create_report_from (source);
        }

        private void create_report_from (string source) {
            try {
                var def = ReportDef.generate (db, source);
                if (app.settings != null) def.paper = app.settings.get_string ("report-paper");
                db.save_object_meta (_("Create Report"), "report:", def.name, def.to_json ());
                rebuild_sidebar ();
                open_object ("report", def.name);
            } catch (Error e) {
                show_error (_("Could Not Create Report"), e.message);
            }
        }

        private async void save_copy () {
            if (db == null) return;
            var dialog = new FileDialog ();
            dialog.title = _("Save a Copy");
            dialog.initial_name = db.display_name () + " " + _("copy") + (db.is_sdb ? ".sdb" : ".sqlite");
            try {
                var file = yield dialog.save (this, null);
                if (file == null) return;
                string target = file.get_path ();
                if (target == db.path) return;
                db.vacuum_into (target);
                toast (_("Saved a copy as \"%s\"").printf (Path.get_basename (target)), _("Open"), () => app.open_file (File.new_for_path (target), null));
            } catch (Error e) {
                if (!(e is Gtk.DialogError.DISMISSED) && !(e is IOError.CANCELLED)) show_error (_("Could Not Save"), e.message);
            }
        }

        private void run_compact () {
            if (db == null) return;
            int64 before = file_size (db.path);
            try {
                db.compact ();
                int64 after = file_size (db.path);
                toast (_("Database compacted: %s to %s").printf (format_size (before), format_size (after)));
                sync_bubbles ();
            } catch (Error e) {
                show_error (_("Could Not Compact"), e.message);
            }
        }

        private static int64 file_size (string path) {
            try {
                return File.new_for_path (path).query_info ("standard::size", FileQueryInfoFlags.NONE).get_size ();
            } catch (Error e) {
                return 0;
            }
        }

        private void run_check () {
            if (db == null) return;
            try {
                string r = db.integrity_check ();
                if (r.strip () == "ok") toast (_("No problems found."));
                else Dialogs.notes (this, _("Integrity Check"), r.split ("\n"));
            } catch (Error e) {
                show_error (_("Could Not Check"), e.message);
            }
        }

        private static string? text_action (string name) {
            switch (name) {
                case "copy": return "clipboard.copy";
                case "cut": return "clipboard.cut";
                case "paste": return "clipboard.paste";
                case "select-all": return "selection.select-all";
                case "undo": return "text.undo";
                case "redo": return "text.redo";
                default: return null;
            }
        }

        private bool focus_in_text () {
            var f = get_focus ();
            return f != null && (f is Gtk.Text || f is Gtk.TextView);
        }

        private delegate void Act ();

        private void act (string name, owned Act handler, bool needs_db = true, VariantType? param = null) {
            var a = new SimpleAction (name, param);
            if (needs_db) doc_actions += name;
            string? forward = text_action (name);
            a.activate.connect ((p) => {
                if (forward != null && focus_in_text ()) {
                    get_focus ().activate_action_variant (forward, null);
                    return;
                }
                if (needs_db && db == null) return;
                if (current != null && current.handles (name)) {
                    current.run_action (name, p);
                    sync_bubbles ();
                    return;
                }
                handler ();
            });
            add_action (a);
        }

        private void page_only (string name, VariantType? param = null) {
            var a = new SimpleAction (name, param);
            page_actions += name;
            a.activate.connect ((p) => {
                if (current != null && current.handles (name)) {
                    current.run_action (name, p);
                    sync_bubbles ();
                }
            });
            add_action (a);
        }

        private void install_actions () {
            act ("save", () => {
                if (current != null && current.dirty ()) {
                    current.save ();
                    sync_bubbles ();
                } else {
                    toast (_("Changes are saved as you make them."));
                }
            });
            act ("save-as", () => save_copy.begin ());
            act ("close-db", () => close_database ());
            act ("close", () => close (), false);
            act ("import", () => TransferDialogs.import (this));
            act ("export", () => {
                string? name = null;
                if (current != null && (current.kind == "table" || current.kind == "query") && db.object_exists (current.object_name)) name = current.object_name;
                TransferDialogs.export_object (this, name);
            });
            act ("export-workbook", () => TransferDialogs.export_database (this, "xlsx"));
            act ("export-sql", () => TransferDialogs.export_database (this, "sql"));
            act ("export-json", () => TransferDialogs.export_database (this, "json"));
            Singularity.Share.add_action (this, this, () => {
                var file = share_file ();
                return file != null ? new Singularity.ShareContent.for_files ({ file }) : null;
            });
            Singularity.Share.add_action (this, this, () => {
                var file = export_for_share ();
                return file != null ? new Singularity.ShareContent.for_files ({ file }) : null;
            }, "share-export");
            act ("undo", () => run_db_undo ());
            act ("redo", () => run_db_redo ());
            act ("rename", () => {
                if (current != null && current.kind != "relationships") Dialogs.rename_object (this, current.kind, current.object_name);
            });
            act ("delete-object", () => {
                if (current != null && current.kind != "relationships") Dialogs.delete_object (this, current.kind, current.object_name);
            });
            act ("new-table", () => create_table ());
            act ("new-query", () => create_query (false));
            act ("new-sql", () => create_query (true));
            act ("new-form", () => create_form (current != null && (current.kind == "table" || current.kind == "query") ? current.object_name : null));
            act ("new-report", () => create_report (current != null && (current.kind == "table" || current.kind == "query") ? current.object_name : null));
            act ("new-macro", () => create_macro ());
            act ("new-module", () => create_module ());
            act ("relationships", () => open_relationships ());
            act ("compact", () => ToolDialogs.compact_and_repair (this));
            act ("encrypt", () => ToolDialogs.password (this));
            act ("link-tables", () => ToolDialogs.link_tables (this));
            act ("linked-tables", () => ToolDialogs.linked_table_manager (this));
            act ("split-database", () => ToolDialogs.split_database (this));
            act ("documenter", () => ToolDialogs.documenter (this));
            act ("analyze", () => ToolDialogs.analyzer (this));
            act ("dependencies", () => {
                if (current != null && current.kind != "relationships" && !current.object_name.has_prefix ("\n")) ToolDialogs.dependencies (this, current.kind, current.object_name);
                else toast (_("Open an object first."));
            });
            act ("startup-options", () => ToolDialogs.startup_options (this));
            act ("run-macro", () => {
                var macros = db.object_names ("macro:");
                if (macros.size == 0) {
                    toast (_("There are no macros yet."));
                    return;
                }
                var dlg = Dialogs.make (this, _("Run Macro"), 420, 300);
                var box = Dialogs.body (dlg);
                var g = new PreferencesGroup (_("Macro"), null);
                var sel = new SelectionRow (_("Macro Name"), macros.to_array (), macros[0]);
                g.add_row (sel);
                box.append (g);
                Dialogs.footer (dlg, _("Run"), () => {
                    string chosen = sel.current_value;
                    Idle.add (() => {
                        run_macro (chosen);
                        return Source.REMOVE;
                    });
                    return true;
                });
                dlg.open_dialog ();
            });
            act ("check", () => run_check ());
            act ("toggle-pane", () => {
                bool v = !get_sidebar_visible ();
                set_sidebar_visible (v);
                if (app.settings != null) app.settings.set_boolean ("sidebar-visible", v);
            });
            act ("fullscreen", () => {
                if (fullscreened) unfullscreen ();
                else fullscreen ();
            }, false);
            act ("refresh", () => {
                db.invalidate ();
                rebuild_sidebar ();
                foreach (var p in pages.values) p.reload ();
            });
            act ("find", () => {
                search_bubble.grab_focus_entry ();
            });
            act ("view-data", () => {
                if (current != null && current.modes ().length > 0) switch_mode (current.modes ()[0]);
            });
            act ("view-design", () => switch_mode ("design"));
            act ("view-sql", () => switch_mode ("sql"));
            act ("print", () => {
                if (current != null) toast (_("Open a report or a table to print."));
            });
            act ("export-pdf", () => {
                if (current != null) toast (_("Open a report or a table to export."));
            });
            string[] page_names = {
                "cut", "copy", "paste", "select-all", "replace", "goto", "new-record", "delete-record", "save-record",
                "add-field", "run", "sort-asc", "sort-desc", "sort", "filter", "filter-selection", "clear-filters", "group",
                "hide-fields", "totals-row", "first-record", "prev-record", "next-record", "last-record", "zoom-in", "zoom-out", "new-view", "filter-by-form", "refresh-records", "subdatasheet"
            };
            foreach (string n in page_names) {
                if (n == "cut" || n == "copy" || n == "paste" || n == "select-all") {
                    act (n, () => { });
                } else {
                    page_only (n);
                }
            }
            page_only ("view-kind", VariantType.STRING);
            var open_obj = new SimpleAction ("open-object", VariantType.STRING);
            open_obj.activate.connect ((p) => {
                string v = p.get_string ();
                int colon = v.index_of (":");
                if (db == null || colon < 0) return;
                string kind = v.substring (0, colon);
                string rest = v.substring (colon + 1);
                string? mode = null;
                int at = rest.last_index_of ("@");
                if (at > 0) {
                    mode = rest.substring (at + 1);
                    rest = rest.substring (0, at);
                }
                open_object (kind, rest, mode);
            });
            add_action (open_obj);
        }

        public void sync_actions () {
            foreach (string name in doc_actions) {
                var a = lookup_action (name) as SimpleAction;
                if (a != null) a.set_enabled (db != null);
            }
            foreach (string name in page_actions) {
                var a = lookup_action (name) as SimpleAction;
                if (a != null) a.set_enabled (current != null && current.handles (name));
            }
            string[] mode_actions = { "view-data", "view-design", "view-sql" };
            string[] mode_names = { "data", "design", "sql" };
            for (int i = 0; i < 3; i++) {
                var a = lookup_action (mode_actions[i]) as SimpleAction;
                bool ok = false;
                if (current != null) {
                    foreach (string m in current.modes ()) {
                        if (m == mode_names[i] || (i == 0 && (m == "results" || m == "form" || m == "preview"))) ok = true;
                    }
                }
                if (a != null) a.set_enabled (ok);
            }
            var pr = lookup_action ("print") as SimpleAction;
            if (pr != null) pr.set_enabled (current != null && current.handles ("print"));
            var pdf = lookup_action ("export-pdf") as SimpleAction;
            if (pdf != null) pdf.set_enabled (current != null && current.handles ("export-pdf"));
            var share = lookup_action ("share") as SimpleAction;
            if (share != null) share.set_enabled (share_file () != null);
            var share_export = lookup_action ("share-export") as SimpleAction;
            if (share_export != null) share_export.set_enabled (db != null);
        }

        private File? share_file () {
            if (db == null || db.path == ":memory:" || !FileUtils.test (db.path, FileTest.EXISTS)) return null;
            return File.new_for_path (db.path);
        }

        private File? export_for_share () {
            if (db == null) return null;
            try {
                string dir = Path.build_filename (Environment.get_user_cache_dir (), "dev.sinty.database", "share");
                DirUtils.create_with_parents (dir, 0700);
                string path = Path.build_filename (dir, db.display_name ().replace ("/", "_") + ".xlsx");
                Xlsx.save (Transfer.all_tables (db), path);
                return File.new_for_path (path);
            } catch (Error e) {
                show_error (_("Could Not Export"), e.message);
                return null;
            }
        }

        public void run (string name) {
            activate_action (name, null);
        }
    }
}
