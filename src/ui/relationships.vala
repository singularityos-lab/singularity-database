using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Database {

    public class DiagramBox {
        public string id;
        public string title;
        public string[] fields = {};
        public string[] keys = {};
        public double x;
        public double y;
        public double w = 210;

        public DiagramBox (string id, string title) {
            this.id = id;
            this.title = title;
        }

        public double height () {
            return DiagramCanvas.HEAD_H + fields.length * DiagramCanvas.ROW_H + 8;
        }

        public bool is_key (string f) {
            foreach (string k in keys) {
                if (k.casefold () == f.casefold ()) return true;
            }
            return false;
        }

        public int field_index (string f) {
            for (int i = 0; i < fields.length; i++) {
                if (fields[i].casefold () == f.casefold ()) return i;
            }
            return -1;
        }
    }

    public class DiagramLink {
        public string from_box;
        public string from_field;
        public string to_box;
        public string to_field;
        public string from_mark = "";
        public string to_mark = "";
        public bool dashed;
        public string badge = "";
        public Object? data;

        public DiagramLink (string from_box, string from_field, string to_box, string to_field) {
            this.from_box = from_box;
            this.from_field = from_field;
            this.to_box = to_box;
            this.to_field = to_field;
        }
    }

    public class DiagramCanvas : Widget {
        public const double HEAD_H = 32;
        public const double ROW_H = 22;

        public Gee.ArrayList<DiagramBox> boxes = new Gee.ArrayList<DiagramBox> ();
        public Gee.ArrayList<DiagramLink> links = new Gee.ArrayList<DiagramLink> ();
        public int selected_link = -1;
        public string selected_box = "";

        private DiagramBox? drag_box;
        private double drag_ox;
        private double drag_oy;
        private DiagramBox? link_box;
        private int link_field = -1;
        private double pointer_x;
        private double pointer_y;
        private bool linking;
        private Pango.Layout? layout;
        private Gdk.RGBA fg;
        private Gdk.RGBA accent;
        private bool dark;

        public signal void link_created (string from_box, string from_field, string to_box, string to_field);
        public signal void link_activated (int index);
        public signal void link_menu (int index, double x, double y);
        public signal void box_menu (string id, double x, double y);
        public signal void box_moved (string id);
        public signal void field_activated (string id, string field);
        public signal void link_delete (int index);
        public signal void background_menu (double x, double y);

        public DiagramCanvas () {
            focusable = true;
            add_css_class ("db-canvas");
            var drag = new GestureDrag ();
            drag.drag_begin.connect (on_begin);
            drag.drag_update.connect (on_update);
            drag.drag_end.connect (on_end);
            add_controller (drag);
            var click = new GestureClick ();
            click.button = 0;
            click.pressed.connect (on_click);
            add_controller (click);
            var keys = new EventControllerKey ();
            keys.key_pressed.connect ((kv, kc, st) => {
                if ((kv == Gdk.Key.Delete || kv == Gdk.Key.BackSpace) && selected_link >= 0) {
                    link_delete (selected_link);
                    return true;
                }
                return false;
            });
            add_controller (keys);
        }

        public DiagramBox? find (string id) {
            foreach (var b in boxes) {
                if (b.id == id) return b;
            }
            return null;
        }

        public void update_size () {
            double w = 400, h = 300;
            foreach (var b in boxes) {
                w = double.max (w, b.x + b.w + 40);
                h = double.max (h, b.y + b.height () + 40);
            }
            set_size_request ((int) w, (int) h);
            queue_draw ();
        }

        public void auto_layout (bool only_new = false) {
            double x = 24, y = 24, row_h = 0;
            double avail = double.max (700, get_width () > 0 ? get_width () : 1000);
            foreach (var b in boxes) {
                if (only_new && (b.x > 0 || b.y > 0)) continue;
                if (x + b.w > avail && x > 24) {
                    x = 24;
                    y += row_h + 40;
                    row_h = 0;
                }
                b.x = x;
                b.y = y;
                x += b.w + 110;
                row_h = double.max (row_h, b.height ());
            }
            update_size ();
        }

        public void layout_levels (Gee.Map<string, int> levels) {
            int max_level = 0;
            foreach (var v in levels.values) max_level = int.max (max_level, v);
            double x = 24;
            for (int lv = 0; lv <= max_level; lv++) {
                double y = 24;
                double w = 0;
                foreach (var b in boxes) {
                    int l = levels.has_key (b.id) ? levels[b.id] : 0;
                    if (l != lv) continue;
                    b.x = x;
                    b.y = y;
                    y += b.height () + 36;
                    w = double.max (w, b.w);
                }
                if (w > 0) x += w + 150;
            }
            update_size ();
        }

        private void colors () {
            fg = get_color ();
            dark = (fg.red + fg.green + fg.blue) / 3 > 0.5;
            if (!get_style_context ().lookup_color ("accent_bg_color", out accent)) accent = { 0.21f, 0.52f, 0.89f, 1 };
        }

        private static void rgba (Cairo.Context cr, Gdk.RGBA c, double a = 1) {
            cr.set_source_rgba (c.red, c.green, c.blue, c.alpha * a);
        }

        private static void rounded (Cairo.Context cr, double x, double y, double w, double h, double r) {
            cr.new_sub_path ();
            cr.arc (x + w - r, y + r, r, -Math.PI / 2, 0);
            cr.arc (x + w - r, y + h - r, r, 0, Math.PI / 2);
            cr.arc (x + r, y + h - r, r, Math.PI / 2, Math.PI);
            cr.arc (x + r, y + r, r, Math.PI, 1.5 * Math.PI);
            cr.close_path ();
        }

        private void text (Cairo.Context cr, string s, double x, double y, double w, bool bold, double alpha = 1, Gdk.RGBA? color = null) {
            layout.set_text (s, -1);
            layout.set_width ((int) (w * Pango.SCALE));
            layout.set_ellipsize (Pango.EllipsizeMode.END);
            var attrs = new Pango.AttrList ();
            if (bold) attrs.insert (Pango.attr_weight_new (Pango.Weight.BOLD));
            layout.set_attributes (attrs);
            rgba (cr, color ?? fg, alpha);
            cr.move_to (x, y);
            Pango.cairo_show_layout (cr, layout);
        }

        private bool anchor (DiagramBox b, string field, DiagramBox other, out double x, out double y, out double dir) {
            int i = b.field_index (field);
            y = b.y + HEAD_H + (i >= 0 ? i : 0) * ROW_H + ROW_H / 2 + 4;
            bool right = other.x + other.w / 2 > b.x + b.w / 2;
            x = right ? b.x + b.w : b.x;
            dir = right ? 1 : -1;
            return i >= 0;
        }

        private void link_points (DiagramLink l, out double x1, out double y1, out double x2, out double y2, out double d1, out double d2) {
            var a = find (l.from_box);
            var b = find (l.to_box);
            x1 = y1 = x2 = y2 = d1 = d2 = 0;
            if (a == null || b == null) return;
            anchor (a, l.from_field, b, out x1, out y1, out d1);
            anchor (b, l.to_field, a, out x2, out y2, out d2);
            if (a == b) {
                x1 = a.x + a.w;
                x2 = a.x + a.w;
                d1 = 1;
                d2 = 1;
            }
        }

        public override void snapshot (Gtk.Snapshot snapshot) {
            colors ();
            if (layout == null) layout = create_pango_layout (null);
            double w = get_width (), h = get_height ();
            var cr = snapshot.append_cairo (Graphene.Rect ().init (0, 0, (float) w, (float) h));
            paint (cr);
        }

        public void extents (out double w, out double h) {
            w = 0;
            h = 0;
            foreach (var b in boxes) {
                w = double.max (w, b.x + b.w + 20);
                h = double.max (h, b.y + b.height () + 20);
            }
        }

        public void paint_for_print (Cairo.Context cr) {
            var saved_layout = layout;
            var saved_fg = fg;
            bool saved_dark = dark;
            string saved_box = selected_box;
            int saved_link = selected_link;
            bool saved_linking = linking;
            fg = { 0.1f, 0.12f, 0.16f, 1 };
            dark = false;
            selected_box = "";
            selected_link = -1;
            linking = false;
            if (!get_style_context ().lookup_color ("accent_bg_color", out accent)) accent = { 0.21f, 0.52f, 0.89f, 1 };
            layout = Pango.cairo_create_layout (cr);
            layout.set_font_description (Pango.FontDescription.from_string ("Sans 10"));
            paint (cr);
            layout = saved_layout;
            fg = saved_fg;
            dark = saved_dark;
            selected_box = saved_box;
            selected_link = saved_link;
            linking = saved_linking;
        }

        private void paint (Cairo.Context cr) {
            for (int i = 0; i < links.size; i++) {
                var l = links[i];
                double x1, y1, x2, y2, d1, d2;
                link_points (l, out x1, out y1, out x2, out y2, out d1, out d2);
                double k = double.max (40, Math.fabs (x2 - x1) / 2);
                cr.move_to (x1, y1);
                cr.curve_to (x1 + d1 * k, y1, x2 + d2 * k, y2, x2, y2);
                if (i == selected_link) rgba (cr, accent);
                else rgba (cr, fg, 0.55);
                cr.set_line_width (i == selected_link ? 3 : 2);
                if (l.dashed) cr.set_dash ({ 6, 4 }, 0);
                cr.stroke ();
                cr.set_dash (null, 0);
                if (l.from_mark != "") text (cr, l.from_mark, x1 + d1 * 6 - (d1 < 0 ? 12 : 0), y1 - 20, 20, true, 0.8);
                if (l.to_mark != "") text (cr, l.to_mark, x2 + d2 * 6 - (d2 < 0 ? 12 : 0), y2 - 20, 20, true, 0.8);
                if (l.badge != "") {
                    double mx = (x1 + x2) / 2, my = (y1 + y2) / 2;
                    layout.set_text (l.badge, -1);
                    layout.set_width (-1);
                    var attrs = new Pango.AttrList ();
                    attrs.insert (Pango.attr_scale_new (0.82));
                    layout.set_attributes (attrs);
                    int lw, lh;
                    layout.get_pixel_size (out lw, out lh);
                    cr.set_source_rgb (dark ? 0.16 : 1, dark ? 0.165 : 1, dark ? 0.18 : 1);
                    rounded (cr, mx - lw / 2.0 - 7, my - lh / 2.0 - 2, lw + 14, lh + 4, (lh + 4) / 2.0);
                    cr.fill_preserve ();
                    rgba (cr, accent, 0.8);
                    cr.set_line_width (1);
                    cr.stroke ();
                    rgba (cr, accent);
                    cr.move_to (mx - lw / 2.0, my - lh / 2.0);
                    Pango.cairo_show_layout (cr, layout);
                    layout.set_attributes (null);
                }
            }
            foreach (var b in boxes) draw_box (cr, b);
            if (linking && link_box != null) {
                double x1 = pointer_x > link_box.x + link_box.w / 2 ? link_box.x + link_box.w : link_box.x;
                double y1 = link_box.y + HEAD_H + link_field * ROW_H + ROW_H / 2 + 4;
                rgba (cr, accent);
                cr.set_line_width (2);
                cr.set_dash ({ 4, 4 }, 0);
                cr.move_to (x1, y1);
                cr.line_to (pointer_x, pointer_y);
                cr.stroke ();
                cr.set_dash (null, 0);
            }
        }

        private void draw_box (Cairo.Context cr, DiagramBox b) {
            double bh = b.height ();
            cr.set_source_rgba (0, 0, 0, dark ? 0.35 : 0.1);
            rounded (cr, b.x + 1, b.y + 3, b.w, bh, 12);
            cr.fill ();
            cr.set_source_rgb (dark ? 0.17 : 1, dark ? 0.175 : 1, dark ? 0.19 : 1);
            rounded (cr, b.x, b.y, b.w, bh, 12);
            cr.fill ();
            rgba (cr, accent, b.id == selected_box ? 0.35 : (dark ? 0.22 : 0.14));
            cr.save ();
            rounded (cr, b.x, b.y, b.w, bh, 12);
            cr.clip ();
            cr.rectangle (b.x, b.y, b.w, HEAD_H);
            cr.fill ();
            cr.restore ();
            rgba (cr, fg, b.id == selected_box ? 0.5 : 0.15);
            cr.set_line_width (1);
            rounded (cr, b.x + 0.5, b.y + 0.5, b.w - 1, bh - 1, 12);
            cr.stroke ();
            text (cr, b.title, b.x + 12, b.y + 7, b.w - 24, true);
            for (int i = 0; i < b.fields.length; i++) {
                double fy = b.y + HEAD_H + 4 + i * ROW_H;
                bool key = b.is_key (b.fields[i]);
                if (linking && link_box == b && link_field == i) {
                    rgba (cr, accent, 0.2);
                    cr.rectangle (b.x + 4, fy, b.w - 8, ROW_H);
                    cr.fill ();
                }
                if (key) {
                    rgba (cr, accent);
                    cr.arc (b.x + 14, fy + ROW_H / 2, 3.5, 0, 2 * Math.PI);
                    cr.fill ();
                }
                text (cr, b.fields[i], b.x + 24, fy + 2, b.w - 32, key, key ? 1 : 0.85);
            }
        }

        private DiagramBox? box_at (double x, double y) {
            for (int i = boxes.size - 1; i >= 0; i--) {
                var b = boxes[i];
                if (x >= b.x && x <= b.x + b.w && y >= b.y && y <= b.y + b.height ()) return b;
            }
            return null;
        }

        private int field_at (DiagramBox b, double y) {
            int i = (int) ((y - b.y - HEAD_H - 4) / ROW_H);
            return y > b.y + HEAD_H && i >= 0 && i < b.fields.length ? i : -1;
        }

        private int link_at (double x, double y) {
            for (int i = links.size - 1; i >= 0; i--) {
                double x1, y1, x2, y2, d1, d2;
                link_points (links[i], out x1, out y1, out x2, out y2, out d1, out d2);
                double k = double.max (40, Math.fabs (x2 - x1) / 2);
                for (int s = 0; s <= 40; s++) {
                    double t = s / 40.0, u = 1 - t;
                    double px = u * u * u * x1 + 3 * u * u * t * (x1 + d1 * k) + 3 * u * t * t * (x2 + d2 * k) + t * t * t * x2;
                    double py = u * u * u * y1 + 3 * u * u * t * y1 + 3 * u * t * t * y2 + t * t * t * y2;
                    if (Math.fabs (px - x) < 6 && Math.fabs (py - y) < 6) return i;
                }
            }
            return -1;
        }

        private void on_begin (double x, double y) {
            grab_focus ();
            var b = box_at (x, y);
            linking = false;
            drag_box = null;
            link_box = null;
            if (b == null) return;
            selected_box = b.id;
            int f = field_at (b, y);
            if (f >= 0) {
                link_box = b;
                link_field = f;
            } else {
                drag_box = b;
                drag_ox = x - b.x;
                drag_oy = y - b.y;
                boxes.remove (b);
                boxes.add (b);
            }
            queue_draw ();
        }

        private void on_update (double dx, double dy) {
            double sx, sy;
            ((GestureDrag) get_last_controller ()).get_start_point (out sx, out sy);
            pointer_x = sx + dx;
            pointer_y = sy + dy;
            if (drag_box != null) {
                drag_box.x = double.max (0, pointer_x - drag_ox);
                drag_box.y = double.max (0, pointer_y - drag_oy);
                queue_draw ();
                return;
            }
            if (link_box != null && Math.fabs (dx) + Math.fabs (dy) > 6) {
                linking = true;
                queue_draw ();
            }
        }

        private Gtk.EventController? get_last_controller () {
            var list = observe_controllers ();
            for (uint i = 0; i < list.get_n_items (); i++) {
                var c = list.get_item (i) as GestureDrag;
                if (c != null) return c;
            }
            return null;
        }

        private void on_end (double dx, double dy) {
            if (drag_box != null) {
                string id = drag_box.id;
                drag_box = null;
                update_size ();
                box_moved (id);
                return;
            }
            if (linking && link_box != null) {
                var target = box_at (pointer_x, pointer_y);
                if (target != null) {
                    int f = field_at (target, pointer_y);
                    if (f >= 0 && !(target == link_box && f == link_field)) {
                        link_created (link_box.id, link_box.fields[link_field], target.id, target.fields[f]);
                    }
                }
            }
            linking = false;
            link_box = null;
            queue_draw ();
        }

        private void on_click (Gtk.GestureClick g, int n, double x, double y) {
            grab_focus ();
            uint button = g.get_current_button ();
            var b = box_at (x, y);
            if (b != null) {
                selected_link = -1;
                if (button == Gdk.BUTTON_SECONDARY) {
                    box_menu (b.id, x, y);
                    return;
                }
                if (n == 2) {
                    int f = field_at (b, y);
                    if (f >= 0) field_activated (b.id, b.fields[f]);
                }
                queue_draw ();
                return;
            }
            int l = link_at (x, y);
            selected_link = l;
            selected_box = "";
            queue_draw ();
            if (l >= 0) {
                if (button == Gdk.BUTTON_SECONDARY) link_menu (l, x, y);
                else if (n == 2) link_activated (l);
            } else if (button == Gdk.BUTTON_SECONDARY) {
                background_menu (x, y);
            }
        }
    }

    public class RelationshipsPage : ObjectPage {
        private DiagramCanvas canvas;
        private StatusPage empty;
        private Stack stack;

        public RelationshipsPage (DatabaseWindow win) {
            base (win, "relationships", "");
            add_css_class ("db-content");
            stack = new Stack ();
            stack.vexpand = true;
            canvas = new DiagramCanvas ();
            var scroll = new ScrolledWindow ();
            scroll.vexpand = true;
            scroll.hexpand = true;
            scroll.child = canvas;
            var box = new Box (Orientation.VERTICAL, 8);
            box.add_css_class ("db-pane-page");
            var hint = new Label (_("Drag a field onto the matching field of another table to relate them. Double-click a line to change it."));
            hint.add_css_class ("caption");
            hint.add_css_class ("dim-label");
            hint.halign = Align.START;
            box.append (hint);
            box.append (scroll);
            stack.add_named (box, "diagram");
            empty = new StatusPage ();
            empty.icon_name = "network-workgroup";
            empty.title = _("No Tables Yet");
            empty.description = _("Create at least two tables to relate them.");
            var b = new Button.with_label (_("New Table"));
            b.add_css_class ("suggested-action");
            b.halign = Align.CENTER;
            b.clicked.connect (() => win.run ("new-table"));
            empty.child = b;
            stack.add_named (empty, "empty");
            append (stack);
            canvas.link_created.connect (on_link_created);
            canvas.link_activated.connect ((i) => edit_link (i));
            canvas.link_delete.connect ((i) => delete_link (i));
            canvas.link_menu.connect ((i, x, y) => {
                var menu = new ContextMenu (canvas);
                var r = Gdk.Rectangle ();
                r.x = (int) x;
                r.y = (int) y;
                r.width = r.height = 1;
                menu.pointing_to = r;
                menu.add_item (_("Edit Relationship…"), "document-edit-symbolic", () => edit_link (i));
                menu.add_separator ();
                menu.add_item (_("Delete Relationship"), "user-trash-symbolic", () => delete_link (i), "destructive");
                DatabaseWindow.popup_menu (menu);
            });
            canvas.box_menu.connect ((id, x, y) => {
                var menu = new ContextMenu (canvas);
                var r = Gdk.Rectangle ();
                r.x = (int) x;
                r.y = (int) y;
                r.width = r.height = 1;
                menu.pointing_to = r;
                menu.add_item (_("Open"), "document-open-symbolic", () => win.open_object ("table", id));
                menu.add_item (_("Design View"), "document-edit-symbolic", () => win.open_object ("table", id, "design"));
                DatabaseWindow.popup_menu (menu);
            });
            canvas.field_activated.connect ((id, f) => win.open_object ("table", id, "design"));
            canvas.box_moved.connect (() => save_positions ());
            canvas.background_menu.connect ((x, y) => {
                var menu = new ContextMenu (canvas);
                var r = Gdk.Rectangle ();
                r.x = (int) x;
                r.y = (int) y;
                r.width = r.height = 1;
                menu.pointing_to = r;
                menu.add_item (_("Arrange Tables"), "db-layout-symbolic", () => arrange ());
                DatabaseWindow.popup_menu (menu);
            });
            reload ();
        }

        public override string title () {
            return _("Relationships");
        }

        public override string[] bubbles () {
            return { "layout" };
        }

        public override bool handles (string action) {
            return action == "tidy" || action == "print" || action == "export-pdf";
        }

        public override void run_action (string action, Variant? param) {
            switch (action) {
                case "tidy": arrange (); break;
                case "print":
                case "export-pdf":
                    export_diagram (action == "print");
                    break;
            }
        }

        private void export_diagram (bool print) {
            double w, h;
            canvas.extents (out w, out h);
            w = double.max (w, 100);
            h = double.max (h, 100);
            var source = new Singularity.Print.CallbackSource (_("Relationships"), (format) => 1, (cr, page, format) => {
                double avail_w = format.width - format.margin_left - format.margin_right;
                double avail_h = format.height - format.margin_top - format.margin_bottom - 30;
                double s = double.min (1, double.min (avail_w / w, avail_h / h));
                cr.save ();
                cr.set_source_rgb (0.1, 0.12, 0.16);
                var title = Pango.cairo_create_layout (cr);
                title.set_font_description (Pango.FontDescription.from_string ("Sans Bold 14"));
                title.set_text ("%s: %s".printf (win.db.display_name (), _("Relationships")), -1);
                cr.move_to (format.margin_left, format.margin_top);
                Pango.cairo_show_layout (cr, title);
                cr.translate (format.margin_left, format.margin_top + 30);
                cr.scale (s, s);
                canvas.paint_for_print (cr);
                cr.restore ();
            });
            Singularity.Print.run_source.begin (win, source);
        }

        private void arrange () {
            var levels = new Gee.HashMap<string, int> ();
            var rels = db.all_relationships ();
            foreach (var b in canvas.boxes) levels[b.id] = 0;
            for (int pass = 0; pass < canvas.boxes.size; pass++) {
                bool changed = false;
                foreach (var r in rels) {
                    if (r.table == r.ref_table || !levels.has_key (r.table) || !levels.has_key (r.ref_table)) continue;
                    int want = levels[r.ref_table] + 1;
                    if (levels[r.table] < want && want < canvas.boxes.size) {
                        levels[r.table] = want;
                        changed = true;
                    }
                }
                if (!changed) break;
            }
            canvas.layout_levels (levels);
            save_positions ();
        }

        private void save_positions () {
            var b = new Json.Builder ();
            b.begin_object ();
            foreach (var box in canvas.boxes) {
                b.set_member_name (box.id).begin_array ();
                b.add_double_value (box.x);
                b.add_double_value (box.y);
                b.end_array ();
            }
            b.end_object ();
            try {
                db.set_meta ("layout-relationships", Json.to_string (b.get_root (), false));
            } catch (Error e) {
            }
        }

        public override void reload () {
            if (db == null) return;
            var old = new Gee.HashMap<string, double?> ();
            foreach (var b in canvas.boxes) {
                old[b.id + "x"] = b.x;
                old[b.id + "y"] = b.y;
            }
            var saved = Meta.parse_object (db.get_meta ("layout-relationships"));
            canvas.boxes.clear ();
            canvas.links.clear ();
            var tables = db.table_names ();
            bool missing = false;
            foreach (string t in tables) {
                try {
                    var def = db.load_table (t);
                    var box = new DiagramBox (t, t);
                    string[] f = {};
                    string[] k = {};
                    foreach (var fd in def.fields) {
                        f += fd.name;
                        if (fd.primary_key) k += fd.name;
                    }
                    box.fields = f;
                    box.keys = k;
                    if (old.has_key (t + "x")) {
                        box.x = old[t + "x"];
                        box.y = old[t + "y"];
                    } else if (saved != null && saved.has_member (t)) {
                        var a = saved.get_array_member (t);
                        box.x = a.get_double_element (0);
                        box.y = a.get_double_element (1);
                    } else {
                        missing = true;
                    }
                    canvas.boxes.add (box);
                } catch (Error e) {
                }
            }
            foreach (var r in db.all_relationships ()) {
                if (r.columns.length == 0) continue;
                var l = new DiagramLink (r.ref_table, r.ref_columns[0], r.table, r.columns[0]);
                l.from_mark = r.enforce ? "1" : "";
                l.to_mark = r.enforce ? "∞" : "";
                l.dashed = !r.enforce;
                if (r.on_delete == RefAction.CASCADE) l.badge = _("cascade");
                l.data = new RelHolder (r);
                canvas.links.add (l);
            }
            if (missing) {
                if (saved == null && old.size == 0) arrange ();
                else canvas.auto_layout (true);
            }
            canvas.update_size ();
            stack.visible_child_name = tables.size == 0 ? "empty" : "diagram";
        }

        private void on_link_created (string a_table, string a_field, string b_table, string b_field) {
            try {
                var a = db.load_table (a_table);
                var b = db.load_table (b_table);
                var af = a.find (a_field);
                var bf = b.find (b_field);
                Relationship rel;
                if (bf.primary_key || bf.unique) rel = new Relationship (a_table, a_field, b_table, b_field);
                else if (af.primary_key || af.unique) rel = new Relationship (b_table, b_field, a_table, a_field);
                else {
                    rel = new Relationship (b_table, b_field, a_table, a_field);
                    rel.enforce = false;
                }
                RelationshipDialog.show (win, rel, false);
            } catch (Error e) {
                win.show_error (_("Could Not Relate the Tables"), e.message);
            }
        }

        private void edit_link (int i) {
            var holder = canvas.links[i].data as RelHolder;
            if (holder == null) return;
            RelationshipDialog.show (win, holder.rel, true);
        }

        private void delete_link (int i) {
            var holder = canvas.links[i].data as RelHolder;
            if (holder == null) return;
            RelationshipDialog.remove (win, holder.rel);
        }
    }

    public class RelHolder : Object {
        public Relationship rel;

        public RelHolder (Relationship r) {
            rel = r;
        }
    }

    public class RelationshipDialog {
        public static void show (DatabaseWindow win, Relationship rel, bool existing) {
            var db = win.db;
            var dlg = Dialogs.make (win, existing ? _("Edit Relationship") : _("New Relationship"), 480, 520);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (_("Tables"), _("Each record of the related table points to one record of the primary table."));
            g.add_row (new ActionRow (_("Primary Table"), "%s, %s".printf (rel.ref_table, string.joinv (", ", rel.ref_columns)), "db-key-symbolic"));
            g.add_row (new ActionRow (_("Related Table"), "%s, %s".printf (rel.table, string.joinv (", ", rel.columns)), "db-table-symbolic"));
            box.append (g);
            TableDef? parent = null;
            try {
                parent = db.load_table (rel.ref_table);
            } catch (Error e) {
            }
            bool can_enforce = false;
            if (parent != null && rel.ref_columns.length == 1) {
                var pf = parent.find (rel.ref_columns[0]);
                can_enforce = pf != null && (pf.primary_key && parent.primary_key ().size == 1 || pf.unique);
            }
            var ig = new PreferencesGroup (_("Integrity"), can_enforce ? null : _("To enforce integrity, the primary table's field must be its key or have no duplicates."));
            var enforce = new SwitchRow (_("Enforce Referential Integrity"), _("Related records must point to an existing record"), rel.enforce && can_enforce);
            enforce.sensitive = can_enforce;
            ig.add_row (enforce);
            var cup = new SwitchRow (_("Cascade Update Related Fields"), _("Changing a key updates the related records"), rel.on_update == RefAction.CASCADE);
            ig.add_row (cup);
            string[] del_opts = { _("Block the Deletion"), _("Delete Related Records"), _("Clear the Related Field") };
            string cur = rel.on_delete == RefAction.CASCADE ? del_opts[1] : (rel.on_delete == RefAction.SET_NULL ? del_opts[2] : del_opts[0]);
            var cdel = new SelectionRow (_("When a Record Is Deleted"), del_opts, cur);
            ig.add_row (cdel);
            cup.sensitive = enforce.active;
            cdel.sensitive = enforce.active;
            enforce.switch_btn.notify["active"].connect (() => {
                cup.sensitive = enforce.active;
                cdel.sensitive = enforce.active;
            });
            box.append (ig);
            string rel_key = rel.key ();
            Dialogs.footer (dlg, existing ? _("Apply") : _("Create"), () => {
                try {
                    var nr = rel.copy ();
                    nr.enforce = enforce.active;
                    nr.on_update = enforce.active && cup.active ? RefAction.CASCADE : RefAction.NO_ACTION;
                    nr.on_delete = !enforce.active ? RefAction.NO_ACTION : (cdel.current_value == del_opts[1] ? RefAction.CASCADE : (cdel.current_value == del_opts[2] ? RefAction.SET_NULL : RefAction.NO_ACTION));
                    apply (db, rel_key, existing ? rel : null, nr);
                } catch (Error e) {
                    win.show_error (_("Could Not Save the Relationship"), e.message);
                    return false;
                }
                return true;
            });
            dlg.open_dialog ();
        }

        private static void apply (Database db, string old_key, Relationship? old, Relationship nr) throws Error {
            var soft = db.soft_relationships ();
            var keep_soft = new Gee.ArrayList<Relationship> ();
            foreach (var s in soft) {
                if (s.key () != old_key && s.key () != nr.key ()) keep_soft.add (s);
            }
            var child = db.load_table (nr.table);
            var rels = new Gee.ArrayList<Relationship> ();
            foreach (var r in child.relationships) {
                if (r.key () != old_key && r.key () != nr.key ()) rels.add (r);
            }
            bool lookup_backed = false;
            if (nr.columns.length == 1) {
                var f = child.find (nr.columns[0]);
                if (f != null && f.field_type == FieldType.LOOKUP && f.lookup_table.casefold () == nr.ref_table.casefold ()) lookup_backed = true;
            }
            bool child_changes = false;
            if (nr.enforce) {
                rels.add (nr);
                child_changes = true;
            } else {
                keep_soft.add (nr);
                if (lookup_backed) {
                    var f = child.find (nr.columns[0]);
                    f.field_type = FieldType.INTEGER;
                    f.lookup_table = "";
                    f.lookup_field = "";
                }
                child_changes = child.relationships.size != rels.size || lookup_backed;
            }
            if (rels.size != child.relationships.size || child_changes) {
                child.relationships = rels;
                db.alter_table (child.name, child, null, _("Change Relationship"));
            }
            db.save_soft_relationships (keep_soft);
        }

        public static void remove (DatabaseWindow win, Relationship rel) {
            var dlg = new ConfirmDialog (win.app, _("Delete the Relationship?"), "user-trash",
                _("\"%s\" and \"%s\" stay as they are, but the link between them is removed.").printf (rel.table, rel.ref_table), _("Delete"), ConfirmDialog.ActionStyle.DESTRUCTIVE);
            dlg.transient_for = win;
            dlg.response.connect ((r) => {
                if (r != ConfirmDialog.Response.PRIMARY) return;
                try {
                    var db = win.db;
                    if (!rel.enforce) {
                        var keep = new Gee.ArrayList<Relationship> ();
                        foreach (var s in db.soft_relationships ()) {
                            if (s.key () != rel.key ()) keep.add (s);
                        }
                        db.save_soft_relationships (keep);
                        return;
                    }
                    var child = db.load_table (rel.table);
                    var rels = new Gee.ArrayList<Relationship> ();
                    foreach (var x in child.relationships) {
                        if (x.key () != rel.key ()) rels.add (x);
                    }
                    child.relationships = rels;
                    if (rel.columns.length == 1) {
                        var f = child.find (rel.columns[0]);
                        if (f != null && f.field_type == FieldType.LOOKUP && f.lookup_table.casefold () == rel.ref_table.casefold ()) {
                            f.field_type = FieldType.INTEGER;
                            f.lookup_table = "";
                            f.lookup_field = "";
                        }
                    }
                    db.alter_table (child.name, child, null, _("Delete Relationship"));
                } catch (Error e) {
                    win.show_error (_("Could Not Delete the Relationship"), e.message);
                }
            });
            dlg.present ();
        }
    }
}
