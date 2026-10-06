using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Database {

    public class ReportPrinter {
        public static Gee.ArrayList<LayoutPage>? layout (DatabaseWindow win, ReportDef def, RecordSource? src) {
            try {
                var s = ReportEngine.open_source (win.db, def);
                var renderer = new ReportRenderer ();
                return renderer.layout (def, s);
            } catch (Error e) {
                win.show_error (_("Could Not Build the Report"), e.message);
                return null;
            }
        }

        public static void print_source (DatabaseWindow win, ReportDef def, RecordSource? src) {
            var source = new ReportPageSource (win.db, def);
            Singularity.Print.run_source.begin (win, source);
        }

        public static void print_pages (DatabaseWindow win, Gee.ArrayList<LayoutPage> pages, ReportDef def) {
            print_source (win, def, null);
        }

        public static void export_pdf (DatabaseWindow win, ReportDef def, RecordSource? src) {
            export_report.begin (win, def);
        }

        public static void save_pdf (DatabaseWindow win, Gee.ArrayList<LayoutPage> pages, ReportDef def) {
            export_report.begin (win, def);
        }

        private static Gtk.FileFilter filter (string name, string pattern) {
            var f = new Gtk.FileFilter ();
            f.name = name;
            f.add_pattern (pattern);
            return f;
        }

        public static async void export_report (DatabaseWindow win, ReportDef def) {
            var dialog = new FileDialog ();
            dialog.title = _("Export Report");
            var filters = new GLib.ListStore (typeof (Gtk.FileFilter));
            string[] names = { _("PDF Document"), _("OpenDocument Text"), _("Word Document"), _("Web Page"), _("Excel Workbook"), _("Comma-Separated Values") };
            string[] exts = { "pdf", "odt", "docx", "html", "xlsx", "csv" };
            for (int i = 0; i < names.length; i++) filters.append (filter ("%s (.%s)".printf (names[i], exts[i]), "*." + exts[i]));
            dialog.filters = filters;
            dialog.default_filter = (Gtk.FileFilter) filters.get_item (0);
            string base_name = (def.title != "" ? def.title : (def.name != "" ? def.name : _("Report"))).replace ("/", "-");
            dialog.initial_name = base_name + ".pdf";
            try {
                var file = yield dialog.save (win, null);
                if (file == null) return;
                string path = file.get_path ();
                string low = path.down ();
                bool known = false;
                foreach (string e in exts) {
                    if (low.has_suffix ("." + e)) known = true;
                }
                if (!known) path += ".pdf";
                var pages = layout (win, def, null);
                if (pages == null) return;
                if (path.down ().has_suffix (".pdf")) ReportRenderer.export_pdf (pages, path, def.title);
                else ReportDocument.build (pages, def.title).save (path);
                win.toast (_("Exported \"%s\"").printf (Path.get_basename (path)), _("Open"), () => {
                    new FileLauncher (File.new_for_path (path)).launch.begin (win, null);
                });
            } catch (Error e) {
                if (!(e is Gtk.DialogError.DISMISSED) && !(e is IOError.CANCELLED)) win.show_error (_("Could Not Export"), e.message);
            }
        }
    }

    public class TextPrinter {
        private const double FONT = 9;

        private static Pango.Layout make_layout (Pango.Context ctx, double width, bool mono) {
            var layout = new Pango.Layout (ctx);
            var fd = Pango.FontDescription.from_string (mono ? "Monospace" : "Sans");
            fd.set_absolute_size (FONT * Pango.SCALE);
            layout.set_font_description (fd);
            layout.set_width ((int) (width * Pango.SCALE));
            layout.set_wrap (Pango.WrapMode.WORD_CHAR);
            return layout;
        }

        public static Gee.ArrayList<Gee.ArrayList<string>> paginate (string text, double width, double height, bool mono) {
            var font_map = Pango.CairoFontMap.get_default ();
            var ctx = font_map.create_context ();
            Pango.cairo_context_set_resolution (ctx, 72);
            var layout = make_layout (ctx, width, mono);
            var pages = new Gee.ArrayList<Gee.ArrayList<string>> ();
            var page = new Gee.ArrayList<string> ();
            double used = 0;
            foreach (string line in text.replace ("\t", "    ").split ("\n")) {
                layout.set_text (line == "" ? " " : line, -1);
                int w, h;
                layout.get_size (out w, out h);
                double lh = (double) h / Pango.SCALE;
                if (used + lh > height && page.size > 0) {
                    pages.add (page);
                    page = new Gee.ArrayList<string> ();
                    used = 0;
                }
                page.add (line);
                used += lh;
            }
            if (page.size > 0 || pages.size == 0) pages.add (page);
            return pages;
        }

        public static void print (DatabaseWindow win, string title, string text, bool mono = true) {
            var pages = new Gee.ArrayList<Gee.ArrayList<string>> ();
            var source = new Singularity.Print.CallbackSource (title, (format) => {
                double ml = double.max (40, format.margin_left);
                double mr = double.max (40, format.margin_right);
                double mt = double.max (40, format.margin_top);
                double mb = double.max (40, format.margin_bottom);
                pages = paginate (text, format.width - ml - mr, format.height - mt - mb - 44, mono);
                return pages.size;
            }, (cr, index, format) => {
                if (index < 0 || index >= pages.size) return;
                double ml = double.max (40, format.margin_left);
                double mr = double.max (40, format.margin_right);
                double mt = double.max (40, format.margin_top);
                double mb = double.max (40, format.margin_bottom);
                double width = format.width - ml - mr;
                var head = Pango.cairo_create_layout (cr);
                Pango.cairo_context_set_resolution (head.get_context (), 72);
                head.context_changed ();
                var hf = Pango.FontDescription.from_string ("Sans Bold");
                hf.set_absolute_size (11 * Pango.SCALE);
                head.set_font_description (hf);
                head.set_width ((int) (width * Pango.SCALE));
                head.set_ellipsize (Pango.EllipsizeMode.END);
                head.set_text (title, -1);
                cr.set_source_rgb (0.1, 0.22, 0.42);
                cr.move_to (ml, mt);
                Pango.cairo_show_layout (cr, head);
                cr.set_source_rgb (0.75, 0.77, 0.8);
                cr.set_line_width (0.5);
                cr.move_to (ml, mt + 20);
                cr.line_to (ml + width, mt + 20);
                cr.stroke ();
                var body = Pango.cairo_create_layout (cr);
                Pango.cairo_context_set_resolution (body.get_context (), 72);
                body.context_changed ();
                var fd = Pango.FontDescription.from_string (mono ? "Monospace" : "Sans");
                fd.set_absolute_size (FONT * Pango.SCALE);
                body.set_font_description (fd);
                body.set_width ((int) (width * Pango.SCALE));
                body.set_wrap (Pango.WrapMode.WORD_CHAR);
                double y = mt + 28;
                cr.set_source_rgb (0.08, 0.09, 0.11);
                foreach (string line in pages[index]) {
                    body.set_text (line == "" ? " " : line, -1);
                    cr.move_to (ml, y);
                    Pango.cairo_show_layout (cr, body);
                    int w, h;
                    body.get_size (out w, out h);
                    y += (double) h / Pango.SCALE;
                }
                var foot = Pango.cairo_create_layout (cr);
                Pango.cairo_context_set_resolution (foot.get_context (), 72);
                foot.context_changed ();
                var ff = Pango.FontDescription.from_string ("Sans");
                ff.set_absolute_size (8 * Pango.SCALE);
                foot.set_font_description (ff);
                foot.set_width ((int) (width * Pango.SCALE));
                foot.set_alignment (Pango.Alignment.RIGHT);
                foot.set_text (_("Page %d of %d").printf (index + 1, pages.size), -1);
                cr.set_source_rgb (0.38, 0.4, 0.45);
                cr.move_to (ml, format.height - mb - 10);
                Pango.cairo_show_layout (cr, foot);
            });
            Singularity.Print.run_source.begin (win, source);
        }
    }

    public class ReportPageSource : Singularity.Print.PageSource {
        private Database db;
        private ReportDef def;
        private Gee.ArrayList<LayoutPage> pages = new Gee.ArrayList<LayoutPage> ();

        public ReportPageSource (Database db, ReportDef def) {
            this.db = db;
            this.def = ReportDef.from_json (def.name, def.to_json ());
            this.def.state = def.state.copy ();
            this.def.open_where = def.open_where;
            title = def.title != "" ? def.title : def.name;
        }

        public override bool can_reflow {
            get { return true; }
        }

        public override async int paginate (Singularity.Print.PageFormat format) throws Error {
            def.page_w = format.width;
            def.page_h = format.height;
            def.landscape = format.width > format.height;
            double m = double.min (double.min (format.margin_top, format.margin_bottom), double.min (format.margin_left, format.margin_right));
            if (m > 0) def.margin_mm = m / 72.0 * 25.4;
            var src = ReportEngine.open_source (db, def);
            pages = new ReportRenderer ().layout (def, src);
            page_width = format.width;
            page_height = format.height;
            document_pages = pages.size;
            return pages.size;
        }

        public override void render_page (Cairo.Context cr, int index) {
            if (index < 0 || index >= pages.size) return;
            ReportRenderer.draw_page (cr, pages[index], 1.0);
        }
    }

    public class ReportObject : ScriptObject {
        private weak ReportPage page;

        public ReportObject (ReportPage page) {
            this.page = page;
        }

        public override string type_name () {
            return "Report_" + page.object_name;
        }

        public override SValue get_member (string name, SValue[] args) throws ScriptError {
            switch (name.down ()) {
                case "name": return new SValue.str (page.object_name);
                case "caption": return new SValue.str (page.def.title);
                case "filter": return new SValue.str (page.def.open_where);
                case "filteron": return new SValue.bool (page.def.open_where != "");
                case "openargs": return page.def.open_args != "" ? new SValue.str (page.def.open_args) : new SValue.null ();
                case "recordsource": return new SValue.str (page.def.source);
            }
            return base.get_member (name, args);
        }

        public override void set_member (string name, SValue[] args, SValue value) throws ScriptError {
            switch (name.down ()) {
                case "filter":
                    page.open_with (value.to_text (), page.def.open_args);
                    return;
                case "filteron":
                    if (!value.to_bool ()) page.open_with ("", page.def.open_args);
                    return;
                case "caption":
                    page.def.title = value.to_text ();
                    page.run_action ("refresh", null);
                    return;
            }
            base.set_member (name, args, value);
        }
    }

    public class ReportPreview : Box {
        private Box pages_box;
        private Gee.ArrayList<LayoutPage> pages = new Gee.ArrayList<LayoutPage> ();
        public double zoom { get; private set; default = 0.9; }
        private ScrolledWindow scroll;

        public ReportPreview () {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            scroll = new ScrolledWindow ();
            scroll.vexpand = true;
            scroll.hexpand = true;
            scroll.add_css_class ("db-report-scroll");
            pages_box = new Box (Orientation.VERTICAL, 18);
            pages_box.halign = Align.CENTER;
            pages_box.margin_top = pages_box.margin_bottom = 18;
            pages_box.margin_start = pages_box.margin_end = 18;
            scroll.child = pages_box;
            append (scroll);
            var zoom_ctl = new EventControllerScroll (EventControllerScrollFlags.VERTICAL);
            zoom_ctl.set_propagation_phase (PropagationPhase.CAPTURE);
            zoom_ctl.scroll.connect ((dx, dy) => {
                if ((zoom_ctl.get_current_event_state () & Gdk.ModifierType.CONTROL_MASK) == 0) return false;
                zoom_to (zoom * (dy < 0 ? 1.1 : 1 / 1.1));
                return true;
            });
            scroll.add_controller (zoom_ctl);
        }

        public int page_count () {
            return pages.size;
        }

        public void show_pages (Gee.ArrayList<LayoutPage> p) {
            pages = p;
            rebuild ();
        }

        public void zoom_to (double z) {
            zoom = z.clamp (0.3, 3);
            rebuild ();
        }

        private void rebuild () {
            Widget? c;
            while ((c = pages_box.get_first_child ()) != null) pages_box.remove (c);
            foreach (var p in pages) {
                var area = new DrawingArea ();
                area.content_width = (int) (p.width * zoom);
                area.content_height = (int) (p.height * zoom);
                area.add_css_class ("db-report-page");
                var page = p;
                double z = zoom;
                area.set_draw_func ((a, cr, w, h) => ReportRenderer.draw_page (cr, page, z));
                pages_box.append (area);
            }
        }
    }

    public class ReportPage : ObjectPage {
        public ReportDef def;
        public bool unsaved;
        private string saved_json;
        private Stack stack;
        private ReportPreview preview;
        private ReportPreview design_preview;
        private Box inspector;
        private PropertySheet sheet;
        private Label page_label;
        private Gee.ArrayList<LayoutPage> pages = new Gee.ArrayList<LayoutPage> ();
        private Gee.ArrayList<string> undo_stack = new Gee.ArrayList<string> ();
        private Gee.ArrayList<string> redo_stack = new Gee.ArrayList<string> ();
        private bool building;
        private uint relayout_id;

        public ReportPage (DatabaseWindow win, string name) throws Error {
            base (win, "report", name);
            def = ReportDef.from_json (name, win.db.get_meta ("report:" + name));
            if (def == null) throw new SchemaError.NOT_FOUND (_("The report \"%s\" could not be read.").printf (name));
            saved_json = def.to_json ();
            add_css_class ("db-content");
            stack = new Stack ();
            stack.transition_type = StackTransitionType.CROSSFADE;
            stack.vexpand = true;
            var pbox = new Box (Orientation.VERTICAL, 0);
            pbox.add_css_class ("db-pane-page");
            preview = new ReportPreview ();
            preview.vexpand = true;
            pbox.append (preview);
            var bar = new Box (Orientation.HORIZONTAL, 6);
            bar.add_css_class ("db-record-bar");
            page_label = new Label ("");
            page_label.add_css_class ("db-status");
            page_label.add_css_class ("dim-label");
            page_label.hexpand = true;
            page_label.halign = Align.START;
            bar.append (page_label);
            var zout = new Button.from_icon_name ("zoom-out-symbolic");
            zout.add_css_class ("flat");
            zout.tooltip_text = _("Zoom Out (Ctrl+Alt+-)");
            zout.clicked.connect (() => run_action ("zoom-out", null));
            bar.append (zout);
            var zin = new Button.from_icon_name ("zoom-in-symbolic");
            zin.add_css_class ("flat");
            zin.tooltip_text = _("Zoom In (Ctrl+Alt+=)");
            zin.clicked.connect (() => run_action ("zoom-in", null));
            bar.append (zin);
            pbox.append (bar);
            stack.add_named (pbox, "preview");
            var dbox = new Box (Orientation.HORIZONTAL, 12);
            dbox.add_css_class ("db-pane-page");
            design_preview = new ReportPreview ();
            design_preview.hexpand = true;
            design_preview.zoom_to (0.6);
            dbox.append (design_preview);
            var iscroll = new ScrolledWindow ();
            iscroll.hscrollbar_policy = PolicyType.NEVER;
            iscroll.width_request = 330;
            iscroll.hexpand = false;
            inspector = new Box (Orientation.VERTICAL, 0);
            inspector.add_css_class ("db-inspector");
            sheet = new PropertySheet ();
            inspector.append (sheet);
            iscroll.child = inspector;
            iscroll.add_css_class ("db-panel");
            dbox.append (iscroll);
            stack.add_named (dbox, "design");
            append (stack);
            mode = "preview";
            relayout ();
        }

        public override string[] modes () {
            return { "preview", "design" };
        }

        private ReportDesigner? banded;

        private void to_banded () {
            try {
                var src = ReportEngine.open_source (win.db, def);
                snapshot ();
                def = ReportDesign.convert (def, src.def);
                show_banded ();
                light_change ();
            } catch (Error e) {
                win.show_error (_("Could Not Convert the Report"), e.message);
            }
        }

        private void show_banded () {
            if (banded == null) {
                banded = new ReportDesigner (this);
                banded.changed.connect (() => {
                    def = banded.current ();
                    light_change ();
                });
                stack.add_named (banded, "banded");
            }
            banded.load (def);
            stack.visible_child_name = "banded";
        }

        private ReportObject? robj;

        public ScriptObject script_object () {
            if (robj == null) robj = new ReportObject (this);
            return robj;
        }

        public void open_with (string where, string args) {
            def.open_where = where;
            def.open_args = args;
            relayout ();
        }

        public override void change_mode (string m) {
            if (m == mode) return;
            if (m == "design" && def.designed) {
                show_banded ();
                base.change_mode (m);
                return;
            }
            stack.visible_child_name = m;
            if (m == "design") {
                building = true;
                build_inspector ();
                building = false;
            }
            base.change_mode (m);
            relayout ();
        }

        public override string[] bubbles () {
            return { "print", "pdf" };
        }

        public override bool dirty () {
            return def.to_json () != saved_json;
        }

        public override bool save () {
            try {
                win.db.save_object_meta (_("Save Report"), "report:", object_name, def.to_json ());
                saved_json = def.to_json ();
                undo_stack.clear ();
                redo_stack.clear ();
                win.toast (_("Report saved"));
                title_changed ();
                return true;
            } catch (Error e) {
                win.show_error (_("Could Not Save the Report"), e.message);
                return false;
            }
        }

        public override void reload () {
            if (!dirty ()) {
                var fresh = ReportDef.from_json (object_name, win.db.get_meta ("report:" + object_name));
                if (fresh != null) {
                    def = fresh;
                    saved_json = def.to_json ();
                }
            }
            relayout ();
            if (mode == "design") {
                building = true;
                build_inspector ();
                building = false;
            }
        }

        public override string title () {
            return object_name + (dirty () ? " *" : "");
        }

        public override bool handles (string action) {
            switch (action) {
                case "print":
                case "export-pdf":
                case "zoom-in":
                case "zoom-out":
                case "refresh":
                    return true;
                case "undo":
                case "redo":
                    return mode == "design";
                case "design-add":
                case "group-sort":
                case "view-code":
                    return mode == "design" && def.designed && banded != null;
                case "customize":
                    return mode == "design" && !def.designed;
                default:
                    return false;
            }
        }

        public override void run_action (string action, Variant? param) {
            switch (action) {
                case "print":
                    if (pages.size > 0) ReportPrinter.print_pages (win, pages, def);
                    break;
                case "export-pdf":
                    if (pages.size > 0) ReportPrinter.save_pdf (win, pages, def);
                    break;
                case "zoom-in":
                    preview.zoom_to (preview.zoom * 1.15);
                    break;
                case "zoom-out":
                    preview.zoom_to (preview.zoom / 1.15);
                    break;
                case "refresh":
                    relayout ();
                    break;
                case "design-add":
                    if (banded != null && param != null) banded.add_control (param.get_string ());
                    break;
                case "group-sort":
                    if (banded != null) banded.group_dialog ();
                    break;
                case "view-code":
                    if (banded != null) banded.view_code ();
                    break;
                case "customize":
                    to_banded ();
                    break;
                case "undo":
                    if (banded != null && def.designed && mode == "design" && banded.undo ()) {
                        def = banded.current ();
                        light_change ();
                        return;
                    }
                    if (undo_stack.size == 0) {
                        win.run_db_undo ();
                        return;
                    }
                    redo_stack.add (def.to_json ());
                    def = ReportDef.from_json (object_name, undo_stack.remove_at (undo_stack.size - 1));
                    changed (false);
                    break;
                case "redo":
                    if (banded != null && def.designed && mode == "design" && banded.redo ()) {
                        def = banded.current ();
                        light_change ();
                        return;
                    }
                    if (redo_stack.size == 0) {
                        win.run_db_redo ();
                        return;
                    }
                    undo_stack.add (def.to_json ());
                    def = ReportDef.from_json (object_name, redo_stack.remove_at (redo_stack.size - 1));
                    changed (false);
                    break;
            }
        }

        private void relayout () {
            if (relayout_id != 0) Source.remove (relayout_id);
            relayout_id = Idle.add (() => {
                relayout_id = 0;
                try {
                    var src = ReportEngine.open_source (win.db, def);
                    var renderer = new ReportRenderer ();
                    pages = renderer.layout (def, src);
                } catch (Error e) {
                    pages = new Gee.ArrayList<LayoutPage> ();
                    page_label.label = _("The record source \"%s\" is missing.").printf (def.source);
                    preview.show_pages (pages);
                    design_preview.show_pages (pages);
                    return Source.REMOVE;
                }
                if (mode == "design") design_preview.show_pages (pages);
                else preview.show_pages (pages);
                page_label.label = ngettext ("%d page", "%d pages", pages.size).printf (pages.size);
                return Source.REMOVE;
            });
        }

        private void snapshot () {
            undo_stack.add (def.to_json ());
            redo_stack.clear ();
        }

        private void changed (bool rebuild_inspector = true) {
            title_changed ();
            win.sync_bubbles ();
            relayout ();
            if (rebuild_inspector || true) {
                Idle.add (() => {
                    building = true;
                    build_inspector ();
                    building = false;
                    return Source.REMOVE;
                });
            }
        }

        private void light_change () {
            title_changed ();
            win.sync_bubbles ();
            relayout ();
        }

        private string[] source_fields () {
            string[] names = {};
            try {
                foreach (var f in new RecordSource (win.db, def.source).def.fields) names += f.name;
            } catch (Error e) {
            }
            return names;
        }

        private static string[] total_labels () {
            string[] l = {};
            foreach (var t in ReportTotal.ALL) l += t.label ();
            return l;
        }

        private static string[] align_labels () {
            return { _("Automatic"), _("Left"), _("Center"), _("Right") };
        }

        private void build_inspector () {
            sheet.clear ();
            var db = win.db;
            var conv = sheet.section (_("Layout"), _("Place fields, labels, calculated boxes, images, charts and subreports freely in report sections."));
            sheet.section_button (conv, _("Customize"), () => to_banded ());
            sheet.section (_("Report"));
            sheet.add_entry (_("Title"), def.title, (t) => {
                if (building) return;
                def.title = t;
                light_change ();
            });
            sheet.add_entry (_("Subtitle"), def.subtitle, (t) => {
                if (building) return;
                def.subtitle = t;
                light_change ();
            });
            string[] sources = {};
            foreach (string t in db.table_names ()) sources += t;
            foreach (string q in db.view_names ()) sources += q;
            int si = -1;
            for (int i = 0; i < sources.length; i++) if (sources[i] == def.source) si = i;
            sheet.add_choice (_("Record Source"), sources, si, (i, v) => {
                if (building || v == def.source) return;
                snapshot ();
                try {
                    var nd = ReportDef.generate (db, v);
                    def.source = v;
                    def.columns = nd.columns;
                    def.groups.clear ();
                    def.state = new ViewState ();
                } catch (Error e) {
                }
                changed ();
            });
            string[] layouts = { ReportLayoutKind.TABULAR.label (), ReportLayoutKind.STACKED.label (), ReportLayoutKind.LABELS.label () };
            sheet.add_choice (_("Layout"), layouts, (int) def.layout, (i, v) => {
                if (building) return;
                snapshot ();
                def.layout = (ReportLayoutKind) i;
                changed ();
            });
            if (def.layout == ReportLayoutKind.LABELS) {
                sheet.add_spin (_("Labels Across"), 1, 6, 1, def.label_columns, (v) => {
                    if (building) return;
                    def.label_columns = (int) v;
                    light_change ();
                });
            }

            sheet.section (_("Page"));
            string[] papers = { "A4", "Letter", "Legal", "A3" };
            string[] paper_ids = { "a4", "letter", "legal", "a3" };
            int pi = 0;
            for (int i = 0; i < 4; i++) if (paper_ids[i] == def.paper) pi = i;
            sheet.add_choice (_("Paper Size"), papers, pi, (i, v) => {
                if (building) return;
                snapshot ();
                def.paper = paper_ids[i];
                light_change ();
            });
            sheet.add_switch (_("Landscape"), def.landscape, (v) => {
                if (building) return;
                snapshot ();
                def.landscape = v;
                light_change ();
            });
            sheet.add_spin (_("Margins (mm)"), 5, 40, 1, def.margin_mm, (v) => {
                if (building) return;
                def.margin_mm = v;
                light_change ();
            });
            sheet.add_spin (_("Text Size (%)"), 60, 200, 5, def.font_scale * 100, (v) => {
                if (building) return;
                def.font_scale = v / 100.0;
                light_change ();
            });

            string[] fields = source_fields ();
            var cols = sheet.section (_("Columns"), _("Width is relative to the other columns."));
            string[] unused = {};
            foreach (string f in fields) {
                bool used = false;
                foreach (var c in def.columns) if (c.field == f) used = true;
                if (!used) unused += f;
            }
            if (unused.length > 0) {
                var addb = sheet.section_button (cols, _("Add"), () => { });
                string[] copy = unused;
                addb.clicked.connect (() => {
                    var menu = new Singularity.Widgets.ContextMenu (addb);
                    foreach (string f in copy) {
                        string name = f;
                        menu.add_item (name, null, () => {
                            snapshot ();
                            def.columns.add (new ReportColumn (name, name));
                            changed ();
                        });
                    }
                    DatabaseWindow.popup_menu (menu);
                });
            }
            string[] tl = total_labels ();
            for (int i = 0; i < def.columns.size; i++) {
                var c = def.columns[i];
                int idx = i;
                var box = new Box (Orientation.HORIZONTAL, 4);
                var lbl = new Entry ();
                lbl.text = c.label;
                lbl.hexpand = true;
                lbl.width_chars = 6;
                lbl.tooltip_text = _("Heading of %s").printf (c.field);
                lbl.changed.connect (() => {
                    if (building) return;
                    c.label = lbl.text;
                    light_change ();
                });
                box.append (lbl);
                var width = new SpinButton.with_range (0.2, 10, 0.1);
                width.digits = 1;
                width.width_chars = 3;
                width.value = c.width;
                width.tooltip_text = _("Relative Width");
                width.value_changed.connect (() => {
                    if (building) return;
                    c.width = width.value;
                    light_change ();
                });
                box.append (width);
                string[] safe = {};
                foreach (string x in tl) safe += x;
                var total = new DropDown.from_strings (safe);
                total.selected = (uint) c.total;
                total.tooltip_text = _("Total");
                total.notify["selected"].connect (() => {
                    if (building) return;
                    snapshot ();
                    c.total = ReportTotal.ALL[total.selected];
                    light_change ();
                });
                box.append (total);
                var more = new Button.from_icon_name ("view-more-symbolic");
                more.add_css_class ("flat");
                more.add_css_class ("db-small-button");
                more.tooltip_text = _("Column Actions");
                more.clicked.connect (() => {
                    var menu = new Singularity.Widgets.ContextMenu (more);
                    string[] al = align_labels ();
                    var align = menu.add_submenu (_("Alignment"), "format-justify-left-symbolic");
                    for (int k = 0; k < al.length; k++) {
                        int kk = k;
                        align.add_item (al[k], null, () => {
                            c.align = (ReportAlign) kk;
                            light_change ();
                        });
                    }
                    if (idx > 0) menu.add_item (_("Move Up"), "go-up-symbolic", () => {
                        snapshot ();
                        var x = def.columns.remove_at (idx);
                        def.columns.insert (idx - 1, x);
                        changed ();
                    });
                    if (idx < def.columns.size - 1) menu.add_item (_("Move Down"), "go-down-symbolic", () => {
                        snapshot ();
                        var x = def.columns.remove_at (idx);
                        def.columns.insert (idx + 1, x);
                        changed ();
                    });
                    menu.add_separator ();
                    menu.add_item (_("Remove"), "list-remove-symbolic", () => {
                        snapshot ();
                        def.columns.remove_at (idx);
                        changed ();
                    }, "destructive");
                    DatabaseWindow.popup_menu (menu);
                });
                box.append (more);
                sheet.add_widget (c.field, box);
            }

            var groups = sheet.section (_("Grouping"), def.groups.size == 0 ? _("Records are grouped in this order, with headers and subtotals.") : null);
            if (fields.length > 0) {
                var addg = sheet.section_button (groups, _("Add"), () => { });
                string[] fcopy = fields;
                addg.clicked.connect (() => {
                    var menu = new Singularity.Widgets.ContextMenu (addg);
                    foreach (string f in fcopy) {
                        string name = f;
                        menu.add_item (name, null, () => {
                            snapshot ();
                            def.groups.add (new ReportGroup (name));
                            changed ();
                        });
                    }
                    DatabaseWindow.popup_menu (menu);
                });
            }
            for (int i = 0; i < def.groups.size; i++) {
                var gr = def.groups[i];
                int idx = i;
                var box = new Box (Orientation.HORIZONTAL, 4);
                string[] opts = { _("A to Z"), _("Z to A") };
                var dir = new DropDown.from_strings (opts);
                dir.selected = gr.descending ? 1 : 0;
                dir.hexpand = true;
                dir.notify["selected"].connect (() => {
                    if (building) return;
                    gr.descending = dir.selected == 1;
                    light_change ();
                });
                box.append (dir);
                var more = new Button.from_icon_name ("view-more-symbolic");
                more.add_css_class ("flat");
                more.add_css_class ("db-small-button");
                more.tooltip_text = _("Group Options");
                more.clicked.connect (() => {
                    var menu = new Singularity.Widgets.ContextMenu (more);
                    menu.add_item (gr.header ? _("Hide Group Header") : _("Show Group Header"), null, () => {
                        gr.header = !gr.header;
                        light_change ();
                    });
                    menu.add_item (gr.footer ? _("Hide Subtotals") : _("Show Subtotals"), null, () => {
                        gr.footer = !gr.footer;
                        light_change ();
                    });
                    menu.add_item (gr.page_break ? _("Do Not Start a New Page") : _("Start on a New Page"), null, () => {
                        gr.page_break = !gr.page_break;
                        light_change ();
                    });
                    menu.add_separator ();
                    menu.add_item (_("Remove Group"), "list-remove-symbolic", () => {
                        snapshot ();
                        def.groups.remove_at (idx);
                        changed ();
                    }, "destructive");
                    DatabaseWindow.popup_menu (menu);
                });
                box.append (more);
                sheet.add_widget (gr.field, box);
            }

            sheet.section (_("Sorting and Filter"), _("Sorting applies inside each group."));
            if (fields.length > 0) {
                string[] with_none = { _("Record Order") };
                foreach (string f in fields) with_none += f;
                int cur = 0;
                if (def.state.sorts.size > 0) for (int i = 1; i < with_none.length; i++) if (with_none[i] == def.state.sorts[0].column) cur = i;
                sheet.add_choice (_("Sort By"), with_none, cur, (i, v) => {
                    if (building) return;
                    snapshot ();
                    def.state.sorts.clear ();
                    if (i > 0) def.state.sorts.add (new SortSpec (v, false));
                    changed ();
                });
                if (def.state.sorts.size > 0) {
                    sheet.add_switch (_("Descending"), def.state.sorts[0].descending, (v) => {
                        if (building) return;
                        def.state.sorts[0].descending = v;
                        light_change ();
                    });
                }
                string[] filter_fields = { _("No Filter") };
                foreach (string f in fields) filter_fields += f;
                int fi = 0;
                if (def.state.filters.size > 0) for (int i = 1; i < filter_fields.length; i++) if (filter_fields[i] == def.state.filters[0].column) fi = i;
                sheet.add_choice (_("Filter Field"), filter_fields, fi, (i, v) => {
                    if (building) return;
                    snapshot ();
                    string keep = def.state.filters.size > 0 ? def.state.filters[0].value : "";
                    def.state.filters.clear ();
                    if (i > 0) def.state.filters.add (new FilterSpec (v, FilterOp.CONTAINS, keep));
                    changed ();
                });
                if (def.state.filters.size > 0) {
                    sheet.add_entry (_("Contains"), def.state.filters[0].value, (t) => {
                        if (building || def.state.filters.size == 0) return;
                        def.state.filters[0].value = t;
                        light_change ();
                    });
                }
            }

            sheet.section (_("Totals and Footer"));
            sheet.add_switch (_("Grand Total"), def.grand_total, (v) => {
                if (building) return;
                def.grand_total = v;
                light_change ();
            });
            sheet.add_switch (_("Record Count"), def.show_count, (v) => {
                if (building) return;
                def.show_count = v;
                light_change ();
            });
            sheet.add_switch (_("Date"), def.show_date, (v) => {
                if (building) return;
                def.show_date = v;
                light_change ();
            });
            sheet.add_switch (_("Page Numbers"), def.page_numbers, (v) => {
                if (building) return;
                def.page_numbers = v;
                light_change ();
            });
        }
    }
}
