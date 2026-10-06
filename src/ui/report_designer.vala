using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Database {

    public class ReportDesigner : Box {
        public const double SCALE = 1.3;
        private weak ReportPage page;
        private ReportDef def;
        private Box canvas;
        private Box inspector;
        private PropertySheet sheet;
        private int selected = -1;
        private string selected_section = "";
        private string tab = "format";
        private bool building;
        private Gee.ArrayList<string> undo_stack = new Gee.ArrayList<string> ();
        private Gee.ArrayList<string> redo_stack = new Gee.ArrayList<string> ();
        private Gee.HashMap<int, Widget> frames = new Gee.HashMap<int, Widget> ();

        public signal void changed ();

        public ReportDesigner (ReportPage page) {
            Object (orientation: Orientation.HORIZONTAL, spacing: 12);
            this.page = page;
            add_css_class ("db-pane-page");
            var left = new Box (Orientation.VERTICAL, 6);
            left.hexpand = true;
            canvas = new Box (Orientation.VERTICAL, 0);
            canvas.margin_start = canvas.margin_top = canvas.margin_end = canvas.margin_bottom = 12;
            canvas.halign = Align.START;
            var scroll = new ScrolledWindow ();
            scroll.vexpand = true;
            scroll.hexpand = true;
            scroll.child = canvas;
            scroll.add_css_class ("db-canvas");
            left.append (scroll);
            append (left);
            var iscroll = new ScrolledWindow ();
            iscroll.hscrollbar_policy = PolicyType.NEVER;
            iscroll.width_request = 340;
            inspector = new Box (Orientation.VERTICAL, 8);
            inspector.add_css_class ("db-inspector");
            iscroll.child = inspector;
            iscroll.add_css_class ("db-panel");
            append (iscroll);
            sheet = new PropertySheet ();
        }

        public const string[] CONTROL_KINDS = { "text", "label", "checkbox", "image", "line", "rectangle", "pagebreak", "subreport", "chart" };
        public const string[] CONTROL_ICONS = { "db-type-text-symbolic", "format-text-bold-symbolic", "db-type-boolean-symbolic", "image-x-generic-symbolic", "list-remove-symbolic", "checkbox-symbolic", "view-paged-symbolic", "db-report-symbolic", "db-view-grid-symbolic" };

        public static string[] control_labels () {
            return { _("Text Box"), _("Label"), _("Check Box"), _("Image"), _("Line"), _("Rectangle"), _("Page Break"), _("Subreport"), _("Chart") };
        }

        public void view_code () {
            CodeDialog.show (page.win, _("Code of %s").printf (def.name), def.code != "" ? def.code : "Option Compare Database\n", null, (text) => {
                snapshot ();
                def.code = text;
                touched ();
            });
        }

        public void load (ReportDef d) {
            def = ReportDef.from_json (d.name, d.to_json ());
            def.state = d.state.copy ();
            selected = -1;
            selected_section = "";
            undo_stack.clear ();
            redo_stack.clear ();
            rebuild ();
        }

        public ReportDef current () {
            return def;
        }

        private void snapshot () {
            undo_stack.add (def.to_json ());
            redo_stack.clear ();
        }

        private void touched () {
            if (!building) changed ();
        }

        public bool undo () {
            if (undo_stack.size == 0) return false;
            redo_stack.add (def.to_json ());
            def = ReportDef.from_json (def.name, undo_stack.remove_at (undo_stack.size - 1));
            selected = -1;
            rebuild ();
            changed ();
            return true;
        }

        public bool redo () {
            if (redo_stack.size == 0) return false;
            undo_stack.add (def.to_json ());
            def = ReportDef.from_json (def.name, redo_stack.remove_at (redo_stack.size - 1));
            selected = -1;
            rebuild ();
            changed ();
            return true;
        }

        private double content_width () {
            double pw, ph;
            def.paper_size (out pw, out ph);
            return pw - 2 * def.margin_mm / 25.4 * 72;
        }

        public void add_control (string kind) {
            snapshot ();
            string sec = selected_section != "" ? selected_section : (selected >= 0 ? def.controls[selected].section : "detail");
            if (def.section (sec) == null) sec = "detail";
            var c = new ReportControl ();
            c.kind = kind;
            c.section = sec;
            string base_name = kind.substring (0, 1).up () + kind.substring (1);
            c.name = def.unique_control_name (base_name);
            switch (kind) {
                case "label": c.caption = _("Label"); break;
                case "line": c.w = content_width (); c.h = 2; break;
                case "rectangle":
                case "image": c.w = 120; c.h = 80; break;
                case "subreport":
                case "chart": c.w = content_width (); c.h = 140; break;
                case "pagebreak": c.w = 40; c.h = 4; break;
                case "checkbox": c.w = 14; c.h = 14; break;
                default: break;
            }
            var s = def.section (sec);
            if (s != null && c.h > s.height) s.height = (int) c.h + 4;
            def.controls.add (c);
            selected = def.controls.size - 1;
            rebuild ();
            touched ();
        }

        private void rebuild () {
            building = true;
            Widget? ch;
            while ((ch = canvas.get_first_child ()) != null) canvas.remove (ch);
            frames.clear ();
            ReportDesign.order_sections (def);
            double width = content_width ();
            foreach (var s in def.sections) {
                var bar = new Box (Orientation.HORIZONTAL, 6);
                bar.add_css_class ("db-section-bar");
                if (s.kind == selected_section && selected < 0) bar.add_css_class ("selected");
                var l = new Label (s.label ());
                l.xalign = 0;
                l.hexpand = true;
                bar.append (l);
                string kind = s.kind;
                var click = new GestureClick ();
                click.pressed.connect (() => {
                    selected = -1;
                    selected_section = kind;
                    rebuild ();
                });
                bar.add_controller (click);
                bar.width_request = (int) (width * SCALE);
                canvas.append (bar);
                var fixed = new Fixed ();
                fixed.add_css_class ("db-design-section");
                if (!s.visible) fixed.add_css_class ("dim-label");
                fixed.set_size_request ((int) (width * SCALE), (int) (s.height * SCALE));
                var fclick = new GestureClick ();
                fclick.pressed.connect ((n, x, y) => {
                    if (fixed.pick (x, y, PickFlags.DEFAULT) != fixed) return;
                    selected = -1;
                    selected_section = kind;
                    refresh_frames ();
                    build_inspector ();
                });
                fixed.add_controller (fclick);
                for (int i = 0; i < def.controls.size; i++) {
                    var c = def.controls[i];
                    if (c.section != s.kind) continue;
                    var fr = frame (c, i);
                    fixed.put (fr, c.x * SCALE, c.y * SCALE);
                    frames[i] = fr;
                }
                canvas.append (fixed);
                var grip = new Box (Orientation.HORIZONTAL, 0);
                grip.add_css_class ("db-section-grip");
                grip.height_request = 6;
                grip.width_request = (int) (width * SCALE);
                grip.set_cursor_from_name ("ns-resize");
                var drag = new GestureDrag ();
                int h0 = 0;
                var sec = s;
                drag.drag_begin.connect (() => {
                    snapshot ();
                    h0 = sec.height;
                });
                drag.drag_update.connect ((dx, dy) => {
                    sec.height = int.max (0, (int) Math.round ((h0 * SCALE + dy) / SCALE));
                    fixed.set_size_request ((int) (width * SCALE), (int) (sec.height * SCALE));
                });
                drag.drag_end.connect (() => {
                    rebuild ();
                    touched ();
                });
                grip.add_controller (drag);
                canvas.append (grip);
            }
            build_inspector ();
            building = false;
        }

        private void refresh_frames () {
            foreach (var e in frames.entries) {
                if (e.key == selected) e.value.add_css_class ("selected");
                else e.value.remove_css_class ("selected");
            }
        }

        private Widget frame (ReportControl c, int index) {
            var fr = new Box (Orientation.VERTICAL, 0);
            fr.add_css_class ("db-design-control");
            fr.add_css_class ("db-report-control");
            if (index == selected) fr.add_css_class ("selected");
            fr.set_size_request ((int) (c.w * SCALE), (int) (double.max (4, c.h) * SCALE));
            string text;
            switch (c.kind) {
                case "label": text = c.caption; break;
                case "line": text = ""; break;
                case "pagebreak": text = _("Page Break"); break;
                case "subreport": text = _("Subreport: %s").printf (c.subreport); break;
                case "chart": text = _("Chart: %s").printf (c.chart_source); break;
                case "image": text = _("Image"); break;
                case "rectangle": text = ""; break;
                default: text = c.source != "" ? c.source : _("Unbound"); break;
            }
            if (text != "") {
                var l = new Label (text);
                l.xalign = c.align == "right" ? 1 : (c.align == "center" ? 0.5f : 0);
                l.ellipsize = Pango.EllipsizeMode.END;
                l.hexpand = true;
                l.add_css_class (c.kind == "label" ? "db-form-label" : "caption");
                fr.append (l);
            }
            var drag = new GestureDrag ();
            double x0 = 0, y0 = 0;
            bool moved = false;
            drag.drag_begin.connect (() => {
                selected = index;
                selected_section = c.section;
                x0 = c.x;
                y0 = c.y;
                moved = false;
                refresh_frames ();
                building = true;
                build_inspector ();
                building = false;
                drag.set_state (EventSequenceState.CLAIMED);
            });
            drag.drag_update.connect ((dx, dy) => {
                if (!moved && Math.fabs (dx) + Math.fabs (dy) < 3) return;
                if (!moved) snapshot ();
                moved = true;
                c.x = double.max (0, Math.round ((x0 * SCALE + dx) / SCALE / 2) * 2);
                c.y = double.max (0, Math.round ((y0 * SCALE + dy) / SCALE / 2) * 2);
                var parent = fr.get_parent () as Fixed;
                if (parent != null) parent.move (fr, c.x * SCALE, c.y * SCALE);
            });
            drag.drag_end.connect (() => {
                if (moved) {
                    var s = def.section (c.section);
                    if (s != null && c.y + c.h > s.height) s.height = (int) (c.y + c.h);
                    rebuild ();
                    touched ();
                }
            });
            fr.add_controller (drag);
            var handle = new Box (Orientation.HORIZONTAL, 0);
            handle.width_request = 8;
            handle.height_request = 8;
            handle.halign = Align.END;
            handle.valign = Align.END;
            handle.vexpand = true;
            handle.add_css_class ("db-resize-handle");
            handle.set_cursor_from_name ("se-resize");
            var rdrag = new GestureDrag ();
            rdrag.set_propagation_phase (PropagationPhase.CAPTURE);
            double w0 = 0, hh0 = 0;
            rdrag.drag_begin.connect (() => {
                snapshot ();
                w0 = c.w;
                hh0 = c.h;
                rdrag.set_state (EventSequenceState.CLAIMED);
            });
            rdrag.drag_update.connect ((dx, dy) => {
                c.w = double.max (4, Math.round ((w0 * SCALE + dx) / SCALE));
                c.h = double.max (2, Math.round ((hh0 * SCALE + dy) / SCALE));
                fr.set_size_request ((int) (c.w * SCALE), (int) (c.h * SCALE));
            });
            rdrag.drag_end.connect (() => {
                rebuild ();
                touched ();
            });
            handle.add_controller (rdrag);
            fr.append (handle);
            return fr;
        }

        private string[] fields () {
            string[] names = {};
            try {
                var src = ReportEngine.open_source (page.win.db, def);
                foreach (var f in src.def.fields) names += f.name;
            } catch (Error e) {
            }
            return names;
        }

        private void build_inspector () {
            Widget? ch;
            while ((ch = inspector.get_first_child ()) != null) inspector.remove (ch);
            var switcher = new SidebarTabs ();
            switcher.add_option ("format", _("Format"));
            switcher.add_option ("data", _("Data"));
            switcher.add_option ("event", _("Event"));
            switcher.set_active (tab);
            switcher.selected.connect ((n) => {
                tab = n;
                Idle.add (() => {
                    build_inspector ();
                    return Source.REMOVE;
                });
            });
            switcher.margin_top = 8;
            inspector.append (switcher);
            sheet = new PropertySheet ();
            inspector.append (sheet);
            if (selected >= 0 && selected < def.controls.size) control_props (def.controls[selected]);
            else if (selected_section != "" && def.section (selected_section) != null) section_props (def.section (selected_section));
            else report_props ();
        }

        private void control_props (ReportControl c) {
            var sec = sheet.section (c.name, c.kind);
            sheet.section_button (sec, _("Remove"), () => {
                snapshot ();
                def.controls.remove (c);
                selected = -1;
                rebuild ();
                touched ();
            });
            if (tab == "format") {
                if (c.kind == "label") {
                    sheet.add_entry (_("Caption"), c.caption, (t) => {
                        if (building) return;
                        c.caption = t;
                        touched ();
                    });
                }
                if (c.kind == "text") {
                    sheet.add_entry (_("Format"), c.format, (t) => {
                        if (building) return;
                        c.format = t;
                        touched ();
                    }, _("e.g. Currency, 0.00, Short Date"));
                }
                sheet.add_spin (_("Left"), 0, 2000, 1, c.x, (v) => {
                    if (building) return;
                    c.x = v;
                    rebuild ();
                    touched ();
                });
                sheet.add_spin (_("Top"), 0, 2000, 1, c.y, (v) => {
                    if (building) return;
                    c.y = v;
                    rebuild ();
                    touched ();
                });
                sheet.add_spin (_("Width"), 2, 2000, 1, c.w, (v) => {
                    if (building) return;
                    c.w = v;
                    rebuild ();
                    touched ();
                });
                sheet.add_spin (_("Height"), 1, 2000, 1, c.h, (v) => {
                    if (building) return;
                    c.h = v;
                    rebuild ();
                    touched ();
                });
                if (c.kind == "text" || c.kind == "label") {
                    sheet.add_spin (_("Font Size"), 5, 72, 0.5, c.font_size, (v) => {
                        if (building) return;
                        c.font_size = v;
                        touched ();
                    }, 1);
                    sheet.add_switch (_("Bold"), c.bold, (v) => {
                        if (building) return;
                        c.bold = v;
                        touched ();
                    });
                    sheet.add_switch (_("Italic"), c.italic, (v) => {
                        if (building) return;
                        c.italic = v;
                        touched ();
                    });
                    string[] al = { "left", "center", "right" };
                    string[] all = { _("Left"), _("Center"), _("Right") };
                    int ai = 0;
                    for (int i = 0; i < 3; i++) if (al[i] == c.align) ai = i;
                    sheet.add_choice (_("Text Align"), all, ai, (i, v) => {
                        if (building) return;
                        c.align = al[i];
                        touched ();
                    });
                    sheet.add_switch (_("Can Grow"), c.can_grow, (v) => {
                        if (building) return;
                        c.can_grow = v;
                        touched ();
                    });
                    sheet.add_switch (_("Border"), c.border, (v) => {
                        if (building) return;
                        c.border = v;
                        touched ();
                    });
                }
                sheet.add_entry (_("Text Color"), c.fore, (t) => {
                    if (building) return;
                    c.fore = t.strip ();
                    touched ();
                }, "#1a3869");
                sheet.add_entry (_("Fill Color"), c.back, (t) => {
                    if (building) return;
                    c.back = t.strip ();
                    touched ();
                }, "#ffffff");
                sheet.add_switch (_("Visible"), c.visible, (v) => {
                    if (building) return;
                    c.visible = v;
                    touched ();
                });
                if (c.kind == "image") {
                    sheet.add_item ("image-x-generic-symbolic", _("Picture"), c.image != "" ? _("Embedded") : _("None"), "document-open-symbolic", () => {
                        var fd = new FileDialog ();
                        fd.open.begin (page.win, null, (obj, res) => {
                            try {
                                var file = fd.open.end (res);
                                if (file == null) return;
                                uint8[] data;
                                FileUtils.get_data (file.get_path (), out data);
                                snapshot ();
                                c.image = Base64.encode (data);
                                touched ();
                                build_inspector ();
                            } catch (Error e) {
                            }
                        });
                    });
                }
                if (c.kind == "text") {
                    sheet.add_item ("db-filter-symbolic", _("Conditional Formatting"), ngettext ("%d rule", "%d rules", c.conditions.size).printf (c.conditions.size), "document-edit-symbolic", () => {
                        CondFormatDialog.show (page.win, _("Conditional Formatting: %s").printf (c.name), c.conditions, (rules) => {
                            snapshot ();
                            c.conditions = rules;
                            build_inspector ();
                            touched ();
                        });
                    });
                }
                return;
            }
            if (tab == "data") {
                if (c.kind == "text" || c.kind == "checkbox" || c.kind == "image") {
                    string[] fs = { _("Unbound") };
                    int fi = 0;
                    foreach (string f in fields ()) {
                        fs += f;
                        if (f == c.source) fi = fs.length - 1;
                    }
                    sheet.add_choice (_("Control Source"), fs, fi, (i, v) => {
                        if (building) return;
                        c.source = i == 0 ? "" : v;
                        touched ();
                    });
                    sheet.add_entry (_("Expression"), c.source.has_prefix ("=") ? c.source.substring (1) : "", (t) => {
                        if (building) return;
                        if (t.strip () != "") c.source = "=" + t.strip ();
                        touched ();
                    }, _("e.g. Sum([Amount]) or [Page] & \" of \" & [Pages]"));
                    if (c.kind == "text") {
                        string[] rs = { "no", "group", "all" };
                        string[] rl = { _("No"), _("Over Group"), _("Over All") };
                        int ri = 0;
                        for (int i = 0; i < 3; i++) if (rs[i] == c.running_sum) ri = i;
                        sheet.add_choice (_("Running Sum"), rl, ri, (i, v) => {
                            if (building) return;
                            c.running_sum = rs[i];
                            touched ();
                        });
                        sheet.add_switch (_("Hide Duplicates"), c.hide_duplicates, (v) => {
                            if (building) return;
                            c.hide_duplicates = v;
                            touched ();
                        });
                    }
                }
                if (c.kind == "subreport") {
                    string[] rs = {};
                    int si = -1;
                    foreach (string r in page.win.db.object_names ("report:")) {
                        if (r == def.name) continue;
                        rs += r;
                        if (r == c.subreport) si = rs.length - 1;
                    }
                    sheet.add_choice (_("Source Object"), rs, si, (i, v) => {
                        if (building) return;
                        c.subreport = v;
                        touched ();
                    });
                }
                if (c.kind == "chart") {
                    sheet.add_entry (_("Data Source"), c.chart_source, (t) => {
                        if (building) return;
                        c.chart_source = t;
                        touched ();
                    });
                    sheet.add_entry (_("Axis"), c.chart_category, (t) => {
                        if (building) return;
                        c.chart_category = t;
                        touched ();
                    });
                    sheet.add_entry (_("Values"), c.chart_value, (t) => {
                        if (building) return;
                        c.chart_value = t;
                        touched ();
                    });
                    string[] types = { "column", "bar", "line", "area", "pie" };
                    string[] tl = { _("Column"), _("Bar"), _("Line"), _("Area"), _("Pie") };
                    int ti = 0;
                    for (int i = 0; i < types.length; i++) if (types[i] == c.chart_type) ti = i;
                    sheet.add_choice (_("Chart Type"), tl, ti, (i, v) => {
                        if (building) return;
                        c.chart_type = types[i];
                        touched ();
                    });
                }
                if (c.kind == "subreport" || c.kind == "chart") {
                    sheet.add_entry (_("Link Master Fields"), c.link_master, (t) => {
                        if (building) return;
                        c.link_master = t;
                        touched ();
                    });
                    sheet.add_entry (_("Link Child Fields"), c.link_child, (t) => {
                        if (building) return;
                        c.link_child = t;
                        touched ();
                    });
                }
                sheet.add_entry (_("Name"), c.name, (t) => {
                    if (building || t.strip () == "") return;
                    c.name = t.strip ();
                    touched ();
                });
                return;
            }
            sheet.add_note (_("Report controls have no events. Use the section On Format event."));
        }

        private void section_props (ReportSection s) {
            sheet.section (s.label (), null);
            if (tab == "event") {
                event_entry (_("On Format"), s.on_format, (t) => s.on_format = t);
                return;
            }
            sheet.add_spin (_("Height"), 0, 1000, 1, s.height, (v) => {
                if (building) return;
                s.height = (int) v;
                rebuild ();
                touched ();
            });
            sheet.add_switch (_("Visible"), s.visible, (v) => {
                if (building) return;
                s.visible = v;
                touched ();
            });
            sheet.add_switch (_("Can Grow"), s.can_grow, (v) => {
                if (building) return;
                s.can_grow = v;
                touched ();
            });
            sheet.add_switch (_("New Page Before"), s.new_page_before, (v) => {
                if (building) return;
                s.new_page_before = v;
                touched ();
            });
            sheet.add_switch (_("New Page After"), s.new_page_after, (v) => {
                if (building) return;
                s.new_page_after = v;
                touched ();
            });
            sheet.add_entry (_("Fill Color"), s.back_color, (t) => {
                if (building) return;
                s.back_color = t.strip ();
                touched ();
            }, "#f3f5f9");
        }

        private delegate void TextSet (string t);

        private void event_entry (string label, string value, owned TextSet set) {
            var box = new Box (Orientation.HORIZONTAL, 4);
            var e = new Entry ();
            e.text = value;
            e.hexpand = true;
            e.placeholder_text = _("Macro name, =Function() or [Event Procedure]");
            e.changed.connect (() => {
                if (building) return;
                set (e.text.strip ());
                touched ();
            });
            box.append (e);
            sheet.add_widget (label, box);
        }

        private void report_props () {
            sheet.section (_("Report"), def.name);
            if (tab == "event") {
                string[,] evs = { { _("On Open"), "Open" }, { _("On No Data"), "NoData" }, { _("On Close"), "Close" } };
                for (int i = 0; i < evs.length[0]; i++) {
                    string key = evs[i, 1];
                    event_entry (evs[i, 0], def.events[key] ?? "", (t) => {
                        if (t == "") def.events.unset (key);
                        else def.events[key] = t;
                    });
                }
                return;
            }
            if (tab == "data") {
                string[] sources = {};
                foreach (string t in page.win.db.table_names ()) sources += t;
                foreach (string q in page.win.db.view_names ()) sources += q;
                foreach (string q in page.win.db.object_names ("action:")) sources += q;
                int si = -1;
                for (int i = 0; i < sources.length; i++) if (sources[i] == def.source) si = i;
                sheet.add_choice (_("Record Source"), sources, si, (i, v) => {
                    if (building) return;
                    snapshot ();
                    def.source = v;
                    touched ();
                });
                sheet.add_entry (_("Filter"), def.state.extra_where, (t) => {
                    if (building) return;
                    def.state.extra_where = t;
                    touched ();
                }, "[Country] = 'Italy'");
                return;
            }
            sheet.add_entry (_("Caption"), def.title, (t) => {
                if (building) return;
                def.title = t;
                touched ();
            });
            string[] papers = { "a4", "letter", "legal", "a3" };
            string[] pl = { "A4", "Letter", "Legal", "A3" };
            int pi = 0;
            for (int i = 0; i < 4; i++) if (papers[i] == def.paper) pi = i;
            sheet.add_choice (_("Paper"), pl, pi, (i, v) => {
                if (building) return;
                def.paper = papers[i];
                rebuild ();
                touched ();
            });
            sheet.add_switch (_("Landscape"), def.landscape, (v) => {
                if (building) return;
                def.landscape = v;
                rebuild ();
                touched ();
            });
            sheet.add_spin (_("Margins (mm)"), 0, 60, 1, def.margin_mm, (v) => {
                if (building) return;
                def.margin_mm = v;
                rebuild ();
                touched ();
            });
            sheet.section (_("Sections"), null);
            string[] optional = { "report-header", "page-header", "page-footer", "report-footer" };
            foreach (string k in optional) {
                string kind = k;
                bool has = def.section (k) != null;
                sheet.add_check (new ReportSection (k, 0).label (), has, (on) => {
                    if (building) return;
                    snapshot ();
                    if (on) def.ensure_section (kind, 24);
                    else {
                        var s = def.section (kind);
                        if (s != null) def.sections.remove (s);
                        var keep = new Gee.ArrayList<ReportControl> ();
                        foreach (var c in def.controls) if (c.section != kind) keep.add (c);
                        def.controls = keep;
                    }
                    Idle.add (() => {
                        rebuild ();
                        return Source.REMOVE;
                    });
                    touched ();
                });
            }
        }

        public void group_dialog () {
            var dlg = Dialogs.make (page.win, _("Group, Sort and Total"), 560, 640);
            var box = Dialogs.body (dlg);
            string[] fs = fields ();
            string[] intervals = { "each", "prefix", "year", "quarter", "month", "week", "day", "hour", "interval" };
            string[] il = { _("Entire Value"), _("First Characters"), _("Year"), _("Quarter"), _("Month"), _("Week"), _("Day"), _("Hour"), _("Interval") };
            var work = new Gee.ArrayList<ReportGroup> ();
            foreach (var g in def.groups) {
                var c = new ReportGroup (g.field);
                c.descending = g.descending;
                c.header = g.header;
                c.footer = g.footer;
                c.page_break = g.page_break;
                c.interval = g.interval;
                c.interval_size = g.interval_size;
                c.keep_together = g.keep_together;
                work.add (c);
            }
            var list = new Box (Orientation.VERTICAL, 12);
            box.append (list);
            FilterByForm.Callback fill = null;
            fill = () => {
                Widget? c;
                while ((c = list.get_first_child ()) != null) list.remove (c);
                for (int i = 0; i < work.size; i++) {
                    var g = work[i];
                    int idx = i;
                    var grp = new PreferencesGroup (_("Group %d").printf (i + 1), null);
                    var field = new SelectionRow (_("Group On"), fs, g.field);
                    field.notify["current-value"].connect (() => g.field = field.current_value);
                    grp.add_row (field);
                    int ii = 0;
                    for (int k = 0; k < intervals.length; k++) if (intervals[k] == g.interval) ii = k;
                    var interval = new SelectionRow (_("Interval"), il, il[ii]);
                    interval.notify["current-value"].connect (() => {
                        for (int k = 0; k < il.length; k++) if (il[k] == interval.current_value) g.interval = intervals[k];
                    });
                    grp.add_row (interval);
                    var size = new EntryRow (_("Characters or Interval Size"));
                    size.text = g.interval_size.to_string ();
                    size.entry_changed.connect (() => g.interval_size = int.max (1, int.parse (size.text)));
                    grp.add_row (size);
                    var desc = new SwitchRow (_("Descending"), null, g.descending);
                    desc.notify["active"].connect (() => g.descending = desc.active);
                    grp.add_row (desc);
                    var hdr = new SwitchRow (_("With a Header Section"), null, g.header);
                    hdr.notify["active"].connect (() => g.header = hdr.active);
                    grp.add_row (hdr);
                    var ftr = new SwitchRow (_("With a Footer Section"), null, g.footer);
                    ftr.notify["active"].connect (() => g.footer = ftr.active);
                    grp.add_row (ftr);
                    var keep = new SwitchRow (_("Keep Header with First Record"), null, g.keep_together);
                    keep.notify["active"].connect (() => g.keep_together = keep.active);
                    grp.add_row (keep);
                    var brk = new SwitchRow (_("New Page for Each Group"), null, g.page_break);
                    brk.notify["active"].connect (() => g.page_break = brk.active);
                    grp.add_row (brk);
                    list.append (grp);
                    var rm = new Button.with_label (_("Remove Group"));
                    rm.halign = Align.START;
                    rm.add_css_class ("destructive-action");
                    rm.clicked.connect (() => {
                        work.remove_at (idx);
                        fill ();
                    });
                    list.append (rm);
                }
            };
            fill ();
            var add = new Button.with_label (_("Add a Group"));
            add.halign = Align.START;
            add.sensitive = fs.length > 0;
            add.clicked.connect (() => {
                work.add (new ReportGroup (fs.length > 0 ? fs[0] : ""));
                fill ();
            });
            box.append (add);
            Dialogs.footer (dlg, _("Apply"), () => {
                snapshot ();
                int old = def.groups.size;
                def.groups = work;
                for (int g = 0; g < work.size; g++) {
                    if (work[g].header) def.ensure_section ("group-header:%d".printf (g), 22);
                    if (work[g].footer) def.ensure_section ("group-footer:%d".printf (g), 20);
                }
                for (int g = work.size; g < old; g++) {
                    foreach (string k in new string[] { "group-header:%d".printf (g), "group-footer:%d".printf (g) }) {
                        var s = def.section (k);
                        if (s != null) def.sections.remove (s);
                        var keep = new Gee.ArrayList<ReportControl> ();
                        foreach (var c in def.controls) if (c.section != k) keep.add (c);
                        def.controls = keep;
                    }
                }
                rebuild ();
                touched ();
                return true;
            });
            dlg.open_dialog ();
        }
    }
}
