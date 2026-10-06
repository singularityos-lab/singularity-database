using Gtk;

namespace Singularity.Apps.Database {

    public delegate bool RecordLocker (string table, int64 rowid);
    public delegate void RecordUnlocker (string table, int64 rowid);

    public class DatasheetView : Widget, Scrollable {
        public static RecordLocker? locker;
        public static RecordUnlocker? unlocker;
        private string locked_table = "";
        private int64 locked_id = -1;

        private void release_lock () {
            if (locked_table != "" && unlocker != null) unlocker (locked_table, locked_id);
            locked_table = "";
            locked_id = -1;
        }

        private int sel_w = 48;

        public RecordSource? src { get; private set; }
        public int cur_row { get; private set; }
        public int cur_col { get; private set; }
        public bool read_only { get; set; }
        public bool allow_new { get; set; default = true; }
        public Gee.HashMap<string, DbValue> defaults = new Gee.HashMap<string, DbValue> ();

        private Gee.ArrayList<Field> cols = new Gee.ArrayList<Field> ();
        private int[] widths = {};
        private int[] base_widths = {};
        private int row_h = 32;
        private int head_h = 34;
        private int anchor_row;
        private int anchor_col;
        private Gee.TreeSet<int64?> selected_records;
        private int64 sel_anchor = -1;
        private int[] group_display = {};
        private Gee.ArrayList<GroupInfo> groups = new Gee.ArrayList<GroupInfo> ();
        private bool grouped;
        private Gee.HashMap<string, DbValue> pending = new Gee.HashMap<string, DbValue> ();

        private Adjustment? _hadj;
        private Adjustment? _vadj;
        public Adjustment hadjustment {
            get { return _hadj; }
            set construct {
                if (_hadj != null) _hadj.value_changed.disconnect (on_scrolled);
                _hadj = value;
                if (_hadj != null) _hadj.value_changed.connect (on_scrolled);
                update_adjustments ();
            }
        }
        public Adjustment vadjustment {
            get { return _vadj; }
            set construct {
                if (_vadj != null) _vadj.value_changed.disconnect (on_scrolled);
                _vadj = value;
                if (_vadj != null) _vadj.value_changed.connect (on_scrolled);
                update_adjustments ();
            }
        }
        public ScrollablePolicy hscroll_policy { get; set; }
        public ScrollablePolicy vscroll_policy { get; set; }

        private Entry editor;
        private bool editing;
        private int edit_row;
        private int edit_col;
        private bool committing;

        private Gdk.RGBA fg;
        private Gdk.RGBA accent;
        private bool dark;
        private Pango.Layout? layout;
        private bool gridlines = true;
        private bool zebra = true;

        private enum Drag {
            NONE,
            SELECT,
            RESIZE,
            ROWS
        }

        private Drag drag = Drag.NONE;
        private int resize_col;
        private int resize_start_w;
        private double drag_x0;
        private double drag_y0;

        public signal void selection_changed ();
        public signal void cell_menu (double x, double y);
        public signal void header_menu (int col, double x, double y);
        public signal void attachment_requested (int64 rowid, Field field);
        public signal void error (string message);
        public signal void layout_changed ();
        public signal void record_added (int64 rowid);

        public DatasheetView () {
            focusable = true;
            can_focus = true;
            overflow = Overflow.HIDDEN;
            add_css_class ("db-datasheet");
            has_tooltip = true;
            selected_records = new Gee.TreeSet<int64?> ((a, b) => a < b ? -1 : (a > b ? 1 : 0));

            editor = new Entry ();
            editor.add_css_class ("db-cell-editor");
            editor.has_frame = false;
            editor.set_parent (this);
            editor.visible = false;
            editor.activate.connect (() => {
                if (commit_edit ()) move (1, 0, false);
            });
            var ekeys = new EventControllerKey ();
            ekeys.key_pressed.connect (on_editor_key);
            editor.add_controller (ekeys);
            var efocus = new EventControllerFocus ();
            efocus.leave.connect (() => {
                if (editing && !committing) Idle.add (() => {
                    if (editing && !editor.has_focus && !editor.get_delegate ().has_focus) commit_edit ();
                    return Source.REMOVE;
                });
            });
            editor.add_controller (efocus);

            var drag_g = new GestureDrag ();
            drag_g.button = Gdk.BUTTON_PRIMARY;
            drag_g.drag_begin.connect (on_drag_begin);
            drag_g.drag_update.connect (on_drag_update);
            drag_g.drag_end.connect (() => {
                if (drag == Drag.RESIZE) layout_changed ();
                drag = Drag.NONE;
            });
            add_controller (drag_g);

            var click = new GestureClick ();
            click.button = 0;
            click.pressed.connect (on_click);
            add_controller (click);

            var keys = new EventControllerKey ();
            keys.key_pressed.connect (on_key);
            add_controller (keys);

            var motion = new EventControllerMotion ();
            motion.motion.connect ((x, y) => {
                bool edge = y < head_h && column_edge (x) >= 0;
                set_cursor_from_name (edge ? "col-resize" : null);
            });
            add_controller (motion);
            query_tooltip.connect (on_tooltip);
        }

        public override void dispose () {
            if (editor != null) {
                editor.unparent ();
                editor = null;
            }
            base.dispose ();
        }

        public void set_density (string density) {
            row_h = density == "compact" ? 26 : (density == "comfortable" ? 40 : 32);
            update_adjustments ();
            queue_draw ();
        }

        public void set_style (bool grid, bool alternate) {
            gridlines = grid;
            zebra = alternate;
            queue_draw ();
        }

        public bool get_border (out Gtk.Border border) {
            border = Gtk.Border ();
            return false;
        }

        public void set_source (RecordSource? s) {
            if (editing) cancel_edit ();
            if (src != null) src.reset.disconnect (on_reset);
            src = s;
            if (src != null) src.reset.connect (on_reset);
            pending.clear ();
            selected_records.clear ();
            rebuild_columns ();
            cur_row = 0;
            cur_col = 0;
            anchor_row = 0;
            anchor_col = 0;
            if (_vadj != null) _vadj.value = 0;
            if (_hadj != null) _hadj.value = 0;
            refresh ();
        }

        private void on_reset () {
            rebuild_groups ();
            update_adjustments ();
            queue_draw ();
        }

        public void rebuild_columns () {
            cols.clear ();
            if (src == null) {
                widths = {};
                return;
            }
            var order = new Gee.ArrayList<Field> ();
            foreach (string n in src.state.order) {
                var f = src.def.find (n);
                if (f != null && !order.contains (f)) order.add (f);
            }
            foreach (var f in src.def.fields) {
                if (!order.contains (f)) order.add (f);
            }
            foreach (var f in order) {
                if (!src.state.hidden.contains (f.name)) cols.add (f);
            }
            widths = new int[cols.size];
            for (int i = 0; i < cols.size; i++) {
                var f = cols[i];
                if (src.state.widths.has_key (f.name)) widths[i] = src.state.widths[f.name];
                else widths[i] = default_width (f);
            }
            base_widths = widths;
            fill_width ();
            cur_col = cur_col.clamp (0, int.max (0, cols.size - 1));
        }

        private int default_width (Field f) {
            return int.max (type_width (f), int.min (260, f.name.char_count () * 9 + 36));
        }

        private int type_width (Field f) {
            switch (f.field_type) {
                case FieldType.AUTONUMBER: return 80;
                case FieldType.BOOLEAN: return 90;
                case FieldType.INTEGER:
                case FieldType.PERCENT: return 110;
                case FieldType.NUMBER:
                case FieldType.CURRENCY:
                case FieldType.DATE:
                case FieldType.TIME: return 130;
                case FieldType.DATETIME: return 170;
                case FieldType.LONG_TEXT: return 280;
                case FieldType.EMAIL:
                case FieldType.URL: return 220;
                default:
                    return int.max (140, int.min (240, f.name.char_count () * 9 + 40));
            }
        }

        public Gee.ArrayList<Field> columns () {
            return cols;
        }

        public Field? current_field () {
            return cur_col >= 0 && cur_col < cols.size ? cols[cur_col] : null;
        }

        public void refresh () {
            bar_min.clear ();
            bar_max.clear ();
            int digits = record_count ().to_string ().length;
            sel_w = int.max (48, 24 + digits * 9);
            rebuild_groups ();
            update_adjustments ();
            queue_allocate ();
            queue_draw ();
            selection_changed ();
        }

        private void rebuild_groups () {
            groups.clear ();
            grouped = src != null && src.state.group_by != "" && src.def.find (src.state.group_by) != null;
            group_display = {};
            if (!grouped) return;
            groups.add_all (src.groups ());
            int[] starts = new int[groups.size + 1];
            int pos = 0;
            for (int g = 0; g < groups.size; g++) {
                starts[g] = pos;
                pos += 1 + (src.state.collapsed.contains (groups[g].label) ? 0 : (int) groups[g].count);
            }
            starts[groups.size] = pos;
            group_display = starts;
        }

        public bool can_add () {
            return src != null && src.editable && allow_new && !read_only && !grouped;
        }

        public int record_count () {
            return src == null ? 0 : (int) src.count ();
        }

        public int display_rows () {
            if (src == null) return 0;
            if (grouped) return group_display.length > 0 ? group_display[group_display.length - 1] : 0;
            return record_count () + (can_add () ? 1 : 0);
        }

        public bool is_new_row (int di) {
            return can_add () && di == record_count ();
        }

        private int group_at (int di) {
            int lo = 0, hi = groups.size - 1;
            while (lo < hi) {
                int mid = (lo + hi + 1) / 2;
                if (group_display[mid] <= di) lo = mid;
                else hi = mid - 1;
            }
            return lo;
        }

        public int64 record_at (int di, out int group_header) {
            group_header = -1;
            if (!grouped) return di < record_count () ? di : -1;
            if (groups.size == 0) return -1;
            int g = group_at (di);
            int off = di - group_display[g];
            if (off == 0) {
                group_header = g;
                return -1;
            }
            return groups[g].start + off - 1;
        }

        public int display_of_record (int64 rec) {
            if (!grouped) return (int) rec;
            for (int g = 0; g < groups.size; g++) {
                if (rec >= groups[g].start && rec < groups[g].start + groups[g].count) {
                    if (src.state.collapsed.contains (groups[g].label)) return group_display[g];
                    return group_display[g] + 1 + (int) (rec - groups[g].start);
                }
            }
            return 0;
        }

        public Row? current_row () {
            int gh;
            int64 rec = record_at (cur_row, out gh);
            return rec >= 0 ? src.row (rec) : null;
        }

        public int64 current_record_index () {
            int gh;
            return record_at (cur_row, out gh);
        }

        public int64[] selected_rowids () {
            int64[] ids = {};
            if (selected_records.size > 0) {
                foreach (var r in selected_records) {
                    var row = src.row (r);
                    if (row != null) ids += row.rowid;
                }
                return ids;
            }
            int r1 = int.min (anchor_row, cur_row), r2 = int.max (anchor_row, cur_row);
            for (int di = r1; di <= r2; di++) {
                int gh;
                int64 rec = record_at (di, out gh);
                if (rec < 0) continue;
                var row = src.row (rec);
                if (row != null) ids += row.rowid;
            }
            return ids;
        }

        private double content_top () {
            return head_h;
        }

        private double footer_h () {
            return src != null && src.state.totals.size > 0 ? row_h : 0;
        }

        private double hscroll () {
            return _hadj != null ? _hadj.value : 0;
        }

        private double vscroll () {
            return _vadj != null ? _vadj.value : 0;
        }

        private double col_x (int c) {
            double x = sel_w - hscroll ();
            for (int i = 0; i < c && i < widths.length; i++) x += widths[i];
            return x;
        }

        private double row_y (int di) {
            return content_top () + di * row_h - vscroll ();
        }

        private bool updating_adj;

        private void update_adjustments () {
            if (updating_adj) return;
            updating_adj = true;
            double w = get_width (), h = get_height ();
            if (_hadj != null) {
                double total = sel_w;
                foreach (int x in widths) total += x;
                total += 60;
                _hadj.configure (_hadj.value.clamp (0, double.max (0, total - w)), 0, double.max (total, w), 20, w * 0.9, w);
            }
            if (_vadj != null) {
                double page = double.max (0, h - content_top () - footer_h ());
                double total = display_rows () * (double) row_h + row_h;
                _vadj.configure (_vadj.value.clamp (0, double.max (0, total - page)), 0, double.max (total, page), row_h * 3, page * 0.9, page);
            }
            updating_adj = false;
        }

        private void on_scrolled () {
            if (editing) position_editor ();
            queue_draw ();
        }

        public override void measure (Orientation o, int for_size, out int minimum, out int natural, out int mb, out int nb) {
            minimum = natural = 120;
            mb = nb = -1;
        }

        private bool is_fill_column (Field f) {
            switch (f.field_type) {
                case FieldType.TEXT:
                case FieldType.LONG_TEXT:
                case FieldType.EMAIL:
                case FieldType.URL:
                case FieldType.LOOKUP:
                    return true;
                default:
                    return false;
            }
        }

        private void fill_width () {
            if (src == null || base_widths.length != cols.size) return;
            int avail = get_width () - sel_w - 2;
            int total = 0;
            var growable = new Gee.ArrayList<int> ();
            for (int i = 0; i < cols.size; i++) {
                bool fixed_w = src.state.widths.has_key (cols[i].name);
                if (!fixed_w) widths[i] = base_widths[i];
                total += widths[i];
                if (!fixed_w && is_fill_column (cols[i])) growable.add (i);
            }
            int extra = avail - total;
            if (extra <= 0 || growable.size == 0) return;
            int each = int.min (320, extra / growable.size);
            foreach (int i in growable) widths[i] += each;
        }

        public override void size_allocate (int width, int height, int baseline) {
            fill_width ();
            update_adjustments ();
            if (editing) position_editor ();
        }

        private void load_colors () {
            fg = get_color ();
            dark = (fg.red + fg.green + fg.blue) / 3 > 0.5;
            var ctx = get_style_context ();
            if (!ctx.lookup_color ("accent_bg_color", out accent)) accent = { 0.21f, 0.52f, 0.89f, 1 };
        }

        private static void rgba (Cairo.Context cr, Gdk.RGBA c, double alpha = 1) {
            cr.set_source_rgba (c.red, c.green, c.blue, c.alpha * alpha);
        }

        public static void choice_color (string value, out double r, out double g, out double b) {
            double[,] palette = {
                { 0.16, 0.47, 0.84 }, { 0.11, 0.69, 0.48 }, { 0.93, 0.63, 0.0 }, { 0.92, 0.41, 0.20 },
                { 0.89, 0.29, 0.28 }, { 0.54, 0.36, 0.96 }, { 0.10, 0.62, 0.72 }, { 0.84, 0.35, 0.64 }
            };
            uint hsh = value.casefold ().hash ();
            int k = (int) (hsh % 8);
            r = palette[k, 0];
            g = palette[k, 1];
            b = palette[k, 2];
        }

        private void draw_text (Cairo.Context cr, string text, double x, double y, double w, double h, bool right, bool bold = false, double alpha = 1, Gdk.RGBA? color = null, bool underline = false) {
            if (text == "" || w < 8) return;
            layout.set_text (text.replace ("\n", " "), -1);
            layout.set_width ((int) ((w - 12) * Pango.SCALE));
            layout.set_ellipsize (Pango.EllipsizeMode.END);
            layout.set_alignment (right ? Pango.Alignment.RIGHT : Pango.Alignment.LEFT);
            var attrs = new Pango.AttrList ();
            if (bold) attrs.insert (Pango.attr_weight_new (Pango.Weight.BOLD));
            if (underline) attrs.insert (Pango.attr_underline_new (Pango.Underline.SINGLE));
            if (right) attrs.insert (new Pango.AttrFontFeatures ("tnum"));
            layout.set_attributes (attrs);
            int lw, lh;
            layout.get_pixel_size (out lw, out lh);
            rgba (cr, color ?? fg, alpha);
            cr.move_to (x + 6, y + (h - lh) / 2);
            Pango.cairo_show_layout (cr, layout);
        }

        public override void snapshot (Gtk.Snapshot snapshot) {
            load_colors ();
            if (layout == null) layout = create_pango_layout (null);
            double w = get_width (), h = get_height ();
            var cr = snapshot.append_cairo (Graphene.Rect ().init (0, 0, (float) w, (float) h));
            cr.set_source_rgb (dark ? 0.118 : 1, dark ? 0.122 : 1, dark ? 0.133 : 1);
            cr.paint ();
            if (src == null) return;
            int rows = display_rows ();
            int first = int.max (0, (int) (vscroll () / row_h));
            double body_bottom = h - footer_h ();
            int last = int.min (rows - 1, first + (int) ((body_bottom - content_top ()) / row_h) + 1);
            int first_c = 0;
            while (first_c < cols.size - 1 && col_x (first_c + 1) < sel_w) first_c++;
            cr.save ();
            cr.rectangle (0, content_top (), w, body_bottom - content_top ());
            cr.clip ();
            for (int di = first; di <= last; di++) draw_row (cr, di, first_c, w);
            draw_selection (cr, first, last);
            cr.restore ();
            draw_header (cr, first_c, w);
            if (footer_h () > 0) draw_footer (cr, first_c, w, h);
            if (editing) snapshot_child (editor, snapshot);
        }

        private void draw_row (Cairo.Context cr, int di, int first_c, double w) {
            double y = row_y (di);
            int gh;
            int64 rec = record_at (di, out gh);
            if (gh >= 0) {
                var g = groups[gh];
                rgba (cr, accent, dark ? 0.16 : 0.1);
                cr.rectangle (0, y, w, row_h);
                cr.fill ();
                bool collapsed = src.state.collapsed.contains (g.label);
                rgba (cr, fg, 0.7);
                double cx = 18, cy = y + row_h / 2.0;
                if (collapsed) {
                    cr.move_to (cx - 3, cy - 5);
                    cr.line_to (cx + 3, cy);
                    cr.line_to (cx - 3, cy + 5);
                } else {
                    cr.move_to (cx - 5, cy - 3);
                    cr.line_to (cx + 5, cy - 3);
                    cr.line_to (cx, cy + 3);
                }
                cr.close_path ();
                cr.fill ();
                var gf = src.def.find (src.state.group_by);
                string text = "%s: %s".printf (gf != null ? gf.name : "", g.label);
                draw_text (cr, text, 30, y, w * 0.6, row_h, false, true);
                draw_text (cr, ngettext ("%lld record", "%lld records", (ulong) g.count).printf (g.count), w * 0.6, y, w * 0.4 - 12, row_h, true, false, 0.6);
                return;
            }
            bool newrow = is_new_row (di);
            Row? row = rec >= 0 ? src.row (rec) : null;
            if (zebra && !newrow && di % 2 == 1) {
                rgba (cr, fg, dark ? 0.035 : 0.025);
                cr.rectangle (sel_w, y, w - sel_w, row_h);
                cr.fill ();
            }
            bool row_selected = rec >= 0 && selected_records.contains (rec);
            if (row_selected) {
                rgba (cr, accent, 0.18);
                cr.rectangle (0, y, w, row_h);
                cr.fill ();
            }
            for (int c = first_c; c < cols.size; c++) {
                double x = col_x (c);
                if (x > w) break;
                double cw = widths[c];
                if (x + cw < sel_w) continue;
                cr.save ();
                cr.rectangle (double.max (x, sel_w), y, cw, row_h);
                cr.clip ();
                var f = cols[c];
                DbValue v;
                if (newrow) v = pending.has_key (f.name) ? pending[f.name] : new DbValue.null ();
                else v = row != null ? row.get (src.def.index_of (f.name)) : new DbValue.null ();
                CondRule? hit = null;
                if (!newrow && row != null && src.state.formats.size > 0) hit = apply_format (cr, f, v, row, x, y, cw);
                draw_value (cr, f, v, x, y, cw, newrow, hit);
                cr.restore ();
                if (gridlines) {
                    rgba (cr, fg, dark ? 0.1 : 0.08);
                    cr.set_line_width (1);
                    cr.move_to (Math.round (x + cw) - 0.5, y);
                    cr.line_to (Math.round (x + cw) - 0.5, y + row_h);
                    cr.stroke ();
                }
            }
            if (gridlines) {
                rgba (cr, fg, dark ? 0.1 : 0.08);
                cr.move_to (sel_w, Math.round (y + row_h) - 0.5);
                cr.line_to (col_x (cols.size), Math.round (y + row_h) - 0.5);
                cr.stroke ();
            }
            rgba (cr, fg, dark ? 0.05 : 0.04);
            cr.rectangle (0, y, sel_w, row_h);
            cr.fill ();
            if (di == cur_row) {
                rgba (cr, accent);
                cr.rectangle (0, y + 4, 3, row_h - 8);
                cr.fill ();
            }
            if (newrow) {
                rgba (cr, fg, 0.55);
                double cx = sel_w / 2.0, cy = y + row_h / 2.0;
                cr.set_line_width (1.6);
                cr.move_to (cx - 5, cy);
                cr.line_to (cx + 5, cy);
                cr.move_to (cx, cy - 5);
                cr.line_to (cx, cy + 5);
                cr.stroke ();
            } else if (rec >= 0) {
                draw_text (cr, (rec + 1).to_string (), 0, y, sel_w - 4, row_h, true, false, 0.45);
            }
        }

        private ScriptRuntime? format_rt;
        private Gee.HashMap<string, double?> bar_min = new Gee.HashMap<string, double?> ();
        private Gee.HashMap<string, double?> bar_max = new Gee.HashMap<string, double?> ();

        private CondRule? apply_format (Cairo.Context cr, Field f, DbValue v, Row row, double x, double y, double cw) {
            CondRuleSet? set = null;
            foreach (var fs in src.state.formats) if (fs.column == f.name) set = fs;
            if (set == null) return null;
            if (set.data_bar && v.is_number ()) {
                if (!bar_min.has_key (f.name)) {
                    bar_min[f.name] = src.aggregate (f.name, Aggregate.MIN).as_double ();
                    bar_max[f.name] = src.aggregate (f.name, Aggregate.MAX).as_double ();
                }
                double lo = double.min (0, bar_min[f.name]), hi = bar_max[f.name];
                double frac = hi > lo ? (v.as_double () - lo) / (hi - lo) : 0;
                var c = Gdk.RGBA ();
                if (!c.parse (set.bar_color)) c = accent;
                rgba (cr, c, 0.35);
                rounded (cr, x + 3, y + 4, double.max (0, (cw - 6) * frac.clamp (0, 1)), row_h - 8, 3);
                cr.fill ();
            }
            if (set.rules.size == 0) return null;
            if (format_rt == null) format_rt = ReportRenderer.runtime ?? new ScriptRuntime (src.db);
            var hit = new CondEval ().first_match (set.rules, f.name, f, v, format_rt, new RowScope (src, row));
            if (hit != null && hit.back != "") {
                var c = Gdk.RGBA ();
                if (c.parse (hit.back)) {
                    rgba (cr, c, 0.85);
                    cr.rectangle (x, y, cw, row_h);
                    cr.fill ();
                }
            }
            return hit;
        }

        private void draw_value (Cairo.Context cr, Field f, DbValue v, double x, double y, double cw, bool dim, CondRule? hit = null) {
            double alpha = dim ? 0.55 : 1;
            if (f.field_type == FieldType.BOOLEAN) {
                double bx = x + cw / 2 - 8, by = y + row_h / 2.0 - 8;
                bool on = v.as_bool ();
                if (dim && v.is_null) return;
                if (on) {
                    rgba (cr, accent, alpha);
                    rounded (cr, bx, by, 16, 16, 4);
                    cr.fill ();
                    cr.set_source_rgba (1, 1, 1, alpha);
                    cr.set_line_width (2);
                    cr.move_to (bx + 4, by + 8.5);
                    cr.line_to (bx + 7, by + 11.5);
                    cr.line_to (bx + 12, by + 5);
                    cr.stroke ();
                } else {
                    rgba (cr, fg, 0.35 * alpha);
                    cr.set_line_width (1.5);
                    rounded (cr, bx + 0.75, by + 0.75, 14.5, 14.5, 4);
                    cr.stroke ();
                }
                return;
            }
            if (v.is_null) {
                if (dim && f.default_value != "") {
                    string shown = f.default_value;
                    try {
                        if (shown == "Date()") shown = _("Today");
                        else if (shown == "Now()" || shown == "Time()") shown = _("Now");
                        else shown = Codec.display (f, Codec.parse (f, shown));
                    } catch (Error e) {
                    }
                    draw_text (cr, shown, x, y, cw, row_h, f.field_type.is_numeric (), false, 0.35);
                }
                return;
            }
            string text = src.display (f, v);
            if (f.field_type == FieldType.CHOICE && text != "") {
                layout.set_text (text, -1);
                layout.set_width (-1);
                layout.set_attributes (null);
                int lw, lh;
                layout.get_pixel_size (out lw, out lh);
                double pw = double.min (lw + 16, cw - 10);
                double r, g, b;
                choice_color (text, out r, out g, out b);
                cr.set_source_rgba (r, g, b, (dark ? 0.32 : 0.18) * alpha);
                rounded (cr, x + 5, y + (row_h - 22) / 2.0, pw, 22, 11);
                cr.fill ();
                var c = Gdk.RGBA ();
                c.red = (float) (dark ? double.min (1, r + 0.35) : r * 0.7);
                c.green = (float) (dark ? double.min (1, g + 0.35) : g * 0.7);
                c.blue = (float) (dark ? double.min (1, b + 0.35) : b * 0.7);
                c.alpha = 1;
                draw_text (cr, text, x + 3, y, pw + 8, row_h, false, false, alpha, c);
                return;
            }
            if (f.field_type == FieldType.LOOKUP) {
                layout.set_text (text, -1);
                layout.set_width (-1);
                layout.set_attributes (null);
                int lw, lh;
                layout.get_pixel_size (out lw, out lh);
                double pw = double.min (lw + 16, cw - 10);
                rgba (cr, fg, dark ? 0.1 : 0.07);
                rounded (cr, x + 5, y + (row_h - 22) / 2.0, pw, 22, 6);
                cr.fill ();
                draw_text (cr, text, x + 3, y, pw + 8, row_h, false, false, alpha);
                return;
            }
            bool right = f.field_type.is_numeric () && f.field_type != FieldType.AUTONUMBER;
            bool link = f.field_type == FieldType.URL || f.field_type == FieldType.EMAIL;
            Gdk.RGBA? color = null;
            if (link) color = accent;
            if (hit != null && hit.fore != "") {
                var hc = Gdk.RGBA ();
                if (hc.parse (hit.fore)) color = hc;
            }
            draw_text (cr, text, x, y, cw, row_h, right, hit != null && hit.bold, alpha * (f.field_type == FieldType.AUTONUMBER ? 0.7 : 1), color, link);
        }

        private static void rounded (Cairo.Context cr, double x, double y, double w, double h, double r) {
            r = double.min (r, double.min (w, h) / 2);
            cr.new_sub_path ();
            cr.arc (x + w - r, y + r, r, -Math.PI / 2, 0);
            cr.arc (x + w - r, y + h - r, r, 0, Math.PI / 2);
            cr.arc (x + r, y + h - r, r, Math.PI / 2, Math.PI);
            cr.arc (x + r, y + r, r, Math.PI, 1.5 * Math.PI);
            cr.close_path ();
        }

        private void draw_selection (Cairo.Context cr, int first, int last) {
            if (cols.size == 0 || display_rows () == 0) return;
            int r1 = int.min (anchor_row, cur_row), r2 = int.max (anchor_row, cur_row);
            int c1 = int.min (anchor_col, cur_col), c2 = int.max (anchor_col, cur_col);
            if (r1 != r2 || c1 != c2) {
                double x1 = double.max (sel_w, col_x (c1)), x2 = col_x (c2 + 1);
                double y1 = row_y (r1), y2 = row_y (r2 + 1);
                rgba (cr, accent, 0.14);
                cr.rectangle (x1, y1, x2 - x1, y2 - y1);
                cr.fill ();
            }
            int gh;
            record_at (cur_row, out gh);
            if (gh >= 0) return;
            double x = col_x (cur_col), y = row_y (cur_row);
            if (x + widths[cur_col] < sel_w) return;
            rgba (cr, accent);
            cr.set_line_width (2);
            cr.rectangle (double.max (x, sel_w) + 1, y + 1, widths[cur_col] - 2 - (x < sel_w ? sel_w - x : 0), row_h - 2);
            cr.stroke ();
        }

        private void draw_header (Cairo.Context cr, int first_c, double w) {
            cr.set_source_rgb (dark ? 0.16 : 0.965, dark ? 0.165 : 0.97, dark ? 0.18 : 0.975);
            cr.rectangle (0, 0, w, head_h);
            cr.fill ();
            for (int c = first_c; c < cols.size; c++) {
                double x = col_x (c);
                if (x > w) break;
                cr.save ();
                cr.rectangle (double.max (x, sel_w), 0, widths[c], head_h);
                cr.clip ();
                var f = cols[c];
                int sort = 0;
                for (int i = 0; i < src.state.sorts.size; i++) {
                    if (src.state.sorts[i].column == f.name) sort = src.state.sorts[i].descending ? -1 : 1;
                }
                bool filtered = false;
                foreach (var ff in src.state.filters) {
                    if (ff.column == f.name) filtered = true;
                }
                double reserve = (sort != 0 ? 16 : 0) + (filtered ? 14 : 0) + (f.primary_key ? 14 : 0);
                double tx = x;
                if (f.primary_key) {
                    rgba (cr, accent, 0.9);
                    cr.arc (x + 12, head_h / 2.0, 3.5, 0, 2 * Math.PI);
                    cr.fill ();
                    tx += 10;
                }
                bool right = f.field_type.is_numeric () && f.field_type != FieldType.AUTONUMBER;
                draw_text (cr, f.name, tx, 0, widths[c] - reserve, head_h, right, true, 0.85);
                double ix = x + widths[c] - 14;
                if (sort != 0) {
                    rgba (cr, accent);
                    double cy = head_h / 2.0;
                    if (sort > 0) {
                        cr.move_to (ix - 4, cy + 3);
                        cr.line_to (ix + 4, cy + 3);
                        cr.line_to (ix, cy - 3);
                    } else {
                        cr.move_to (ix - 4, cy - 3);
                        cr.line_to (ix + 4, cy - 3);
                        cr.line_to (ix, cy + 3);
                    }
                    cr.close_path ();
                    cr.fill ();
                    ix -= 14;
                }
                if (filtered) {
                    rgba (cr, accent);
                    double cy = head_h / 2.0;
                    cr.move_to (ix - 5, cy - 4);
                    cr.line_to (ix + 5, cy - 4);
                    cr.line_to (ix + 1, cy + 1);
                    cr.line_to (ix + 1, cy + 5);
                    cr.line_to (ix - 1, cy + 4);
                    cr.line_to (ix - 1, cy + 1);
                    cr.close_path ();
                    cr.fill ();
                }
                cr.restore ();
                rgba (cr, fg, dark ? 0.14 : 0.12);
                cr.set_line_width (1);
                cr.move_to (Math.round (x + widths[c]) - 0.5, 6);
                cr.line_to (Math.round (x + widths[c]) - 0.5, head_h - 6);
                cr.stroke ();
            }
            cr.set_source_rgb (dark ? 0.16 : 0.965, dark ? 0.165 : 0.97, dark ? 0.18 : 0.975);
            cr.rectangle (0, 0, sel_w, head_h);
            cr.fill ();
            rgba (cr, fg, dark ? 0.16 : 0.14);
            cr.move_to (0, head_h - 0.5);
            cr.line_to (w, head_h - 0.5);
            cr.stroke ();
        }

        private void draw_footer (Cairo.Context cr, int first_c, double w, double h) {
            double y = h - footer_h ();
            cr.set_source_rgb (dark ? 0.16 : 0.965, dark ? 0.165 : 0.97, dark ? 0.18 : 0.975);
            cr.rectangle (0, y, w, footer_h ());
            cr.fill ();
            rgba (cr, fg, dark ? 0.16 : 0.14);
            cr.set_line_width (1);
            cr.move_to (0, y + 0.5);
            cr.line_to (w, y + 0.5);
            cr.stroke ();
            draw_text (cr, _("Total"), 0, y, sel_w + 4, row_h, false, true, 0.7);
            for (int c = first_c; c < cols.size; c++) {
                double x = col_x (c);
                if (x > w) break;
                var f = cols[c];
                if (!src.state.totals.has_key (f.name)) continue;
                var agg = Aggregate.from_id (src.state.totals[f.name]);
                var v = src.aggregate (f.name, agg);
                string text;
                if (agg == Aggregate.COUNT) text = Codec.format_number (v.as_double (), 0, true);
                else if (v.is_null) text = "";
                else if (f.field_type.is_numeric () && agg != Aggregate.COUNT) {
                    var shown = f;
                    if (agg == Aggregate.AVG && f.field_type == FieldType.INTEGER) {
                        shown = new Field (f.name, FieldType.NUMBER);
                        shown.decimals = 2;
                    }
                    text = Codec.display (shown, v);
                } else text = Codec.display (f, v);
                cr.save ();
                cr.rectangle (double.max (x, sel_w), y, widths[c], row_h);
                cr.clip ();
                draw_text (cr, "%s %s".printf (agg.label (), text), x, y, widths[c], row_h, f.field_type.is_numeric (), true, 0.9);
                cr.restore ();
            }
        }

        private int column_at (double x) {
            if (x < sel_w) return -1;
            for (int c = 0; c < cols.size; c++) {
                double cx = col_x (c);
                if (x >= cx && x < cx + widths[c]) return c;
            }
            return -2;
        }

        private int column_edge (double x) {
            for (int c = 0; c < cols.size; c++) {
                double e = col_x (c) + widths[c];
                if (Math.fabs (x - e) <= 4 && e > sel_w) return c;
            }
            return -1;
        }

        private int row_at (double y) {
            if (y < content_top ()) return -1;
            int di = (int) ((y - content_top () + vscroll ()) / row_h);
            return di < display_rows () ? di : -2;
        }

        private void on_drag_begin (double x, double y) {
            drag_x0 = x;
            drag_y0 = y;
            drag = Drag.NONE;
            if (y < head_h) {
                int e = column_edge (x);
                if (e >= 0) {
                    drag = Drag.RESIZE;
                    resize_col = e;
                    resize_start_w = widths[e];
                }
                return;
            }
            if (x < sel_w) {
                drag = Drag.ROWS;
                return;
            }
            drag = Drag.SELECT;
        }

        private void on_drag_update (double dx, double dy) {
            if (drag == Drag.RESIZE) {
                widths[resize_col] = int.max (40, resize_start_w + (int) dx);
                src.state.widths[cols[resize_col].name] = widths[resize_col];
                base_widths[resize_col] = widths[resize_col];
                update_adjustments ();
                if (editing) position_editor ();
                queue_draw ();
                return;
            }
            if (drag == Drag.SELECT && !editing) {
                int r = row_at (drag_y0 + dy);
                int c = column_at (drag_x0 + dx);
                if (r >= 0 && c >= 0 && (r != cur_row || c != cur_col)) {
                    cur_row = r;
                    cur_col = c;
                    queue_draw ();
                    selection_changed ();
                }
                return;
            }
            if (drag == Drag.ROWS) {
                int r = row_at (drag_y0 + dy);
                if (r < 0) return;
                int r1 = int.min (row_at (drag_y0), r), r2 = int.max (row_at (drag_y0), r);
                selected_records.clear ();
                for (int di = r1; di <= r2; di++) {
                    int gh;
                    int64 rec = record_at (di, out gh);
                    if (rec >= 0) selected_records.add (rec);
                }
                queue_draw ();
                selection_changed ();
            }
        }

        private void on_click (Gtk.GestureClick g, int n, double x, double y) {
            grab_focus ();
            uint button = g.get_current_button ();
            var state = g.get_current_event_state ();
            bool shift = (state & Gdk.ModifierType.SHIFT_MASK) != 0;
            bool ctrl = (state & Gdk.ModifierType.CONTROL_MASK) != 0;
            if (y < head_h) {
                int c = column_at (x);
                if (c < 0 || column_edge (x) >= 0) return;
                if (button == Gdk.BUTTON_SECONDARY || n == 2) {
                    header_menu (c, x, y);
                    return;
                }
                if (editing && !commit_edit ()) return;
                cur_col = c;
                anchor_col = c;
                anchor_row = 0;
                cur_row = int.max (0, display_rows () - 1 - (can_add () ? 1 : 0));
                queue_draw ();
                selection_changed ();
                return;
            }
            if (y > get_height () - footer_h ()) {
                int c = column_at (x);
                if (c >= 0) header_menu (c, x, y);
                return;
            }
            int r = row_at (y);
            if (r < 0) return;
            int gh;
            int64 rec = record_at (r, out gh);
            if (gh >= 0) {
                string label = groups[gh].label;
                if (src.state.collapsed.contains (label)) src.state.collapsed.remove (label);
                else src.state.collapsed.add (label);
                if (editing) cancel_edit ();
                rebuild_groups ();
                update_adjustments ();
                cur_row = r;
                queue_draw ();
                layout_changed ();
                return;
            }
            if (x < sel_w) {
                if (editing && !commit_edit ()) return;
                if (rec < 0) return;
                if (ctrl) {
                    if (selected_records.contains (rec)) selected_records.remove (rec);
                    else selected_records.add (rec);
                } else if (shift && sel_anchor >= 0) {
                    selected_records.clear ();
                    for (int64 i = int64.min (sel_anchor, rec); i <= int64.max (sel_anchor, rec); i++) selected_records.add (i);
                } else {
                    selected_records.clear ();
                    selected_records.add (rec);
                    sel_anchor = rec;
                }
                leave_row_to (r);
                cur_row = r;
                anchor_row = r;
                queue_draw ();
                selection_changed ();
                if (button == Gdk.BUTTON_SECONDARY) cell_menu (x, y);
                return;
            }
            int c = column_at (x);
            if (c < 0) return;
            if (button == Gdk.BUTTON_SECONDARY) {
                bool inside = in_range (r, c);
                if (!inside) {
                    if (editing && !commit_edit ()) return;
                    select_cell (r, c, false);
                }
                cell_menu (x, y);
                return;
            }
            if (editing) {
                if (r == edit_row && c == edit_col) return;
                if (!commit_edit ()) return;
            }
            bool was_current = r == cur_row && c == cur_col;
            selected_records.clear ();
            select_cell (r, c, shift);
            var f = cols[c];
            if (n == 1 && was_current && f.field_type == FieldType.BOOLEAN) {
                toggle_boolean ();
                return;
            }
            if (n == 1 && ctrl && (f.field_type == FieldType.URL || f.field_type == FieldType.EMAIL)) {
                open_link ();
                return;
            }
            if (n == 2) {
                if (f.field_type == FieldType.ATTACHMENT) {
                    var row = current_row ();
                    if (row != null) attachment_requested (row.rowid, f);
                    return;
                }
                if (f.field_type != FieldType.BOOLEAN) begin_edit (null);
            }
        }

        private bool in_range (int r, int c) {
            int r1 = int.min (anchor_row, cur_row), r2 = int.max (anchor_row, cur_row);
            int c1 = int.min (anchor_col, cur_col), c2 = int.max (anchor_col, cur_col);
            return r >= r1 && r <= r2 && c >= c1 && c <= c2;
        }

        public void select_cell (int r, int c, bool extend) {
            if (display_rows () == 0 || cols.size == 0) return;
            r = r.clamp (0, display_rows () - 1);
            c = c.clamp (0, cols.size - 1);
            leave_row_to (r);
            cur_row = r;
            cur_col = c;
            if (!extend) {
                anchor_row = r;
                anchor_col = c;
            }
            scroll_to (r, c);
            queue_draw ();
            selection_changed ();
        }

        public void select_record (int64 rec) {
            select_cell (display_of_record (rec), cur_col, false);
        }

        private void leave_row_to (int r) {
            if (r != cur_row && is_new_row (cur_row) && pending.size > 0) commit_new_row ();
        }

        private void scroll_to (int r, int c) {
            if (_vadj != null) {
                double top = r * row_h, bottom = top + row_h;
                if (top < _vadj.value) _vadj.value = top;
                else if (bottom > _vadj.value + _vadj.page_size) _vadj.value = bottom - _vadj.page_size;
            }
            if (_hadj != null && c < widths.length) {
                double left = col_x (c) + hscroll () - sel_w, right = left + widths[c];
                double view = get_width () - sel_w;
                if (left < _hadj.value) _hadj.value = left;
                else if (right > _hadj.value + view) _hadj.value = right - view;
            }
        }

        private void move (int dr, int dc, bool extend) {
            if (display_rows () == 0) return;
            int r = cur_row + dr, c = cur_col + dc;
            if (dc != 0 && !extend) {
                if (c >= cols.size) {
                    c = 0;
                    r++;
                } else if (c < 0) {
                    c = cols.size - 1;
                    r--;
                }
            }
            if (r >= display_rows ()) r = display_rows () - 1;
            if (r < 0) r = 0;
            select_cell (r, c, extend);
        }

        private bool on_key (uint keyval, uint code, Gdk.ModifierType state) {
            if (editing || src == null) return false;
            bool shift = (state & Gdk.ModifierType.SHIFT_MASK) != 0;
            bool ctrl = (state & Gdk.ModifierType.CONTROL_MASK) != 0;
            bool alt = (state & Gdk.ModifierType.ALT_MASK) != 0;
            int page = int.max (1, (int) ((get_height () - content_top () - footer_h ()) / row_h) - 1);
            switch (keyval) {
                case Gdk.Key.Up: move (-1, 0, shift); return true;
                case Gdk.Key.Down:
                    if (alt) {
                        begin_edit (null);
                        return true;
                    }
                    move (1, 0, shift);
                    return true;
                case Gdk.Key.Left: move (0, -1, shift); return true;
                case Gdk.Key.Right: move (0, 1, shift); return true;
                case Gdk.Key.Tab: move (0, 1, false); return true;
                case Gdk.Key.ISO_Left_Tab: move (0, -1, false); return true;
                case Gdk.Key.Page_Up: move (-page, 0, shift); return true;
                case Gdk.Key.Page_Down: move (page, 0, shift); return true;
                case Gdk.Key.Home:
                    if (ctrl) select_cell (0, 0, shift);
                    else select_cell (cur_row, 0, shift);
                    return true;
                case Gdk.Key.End:
                    if (ctrl) select_cell (display_rows () - 1, cols.size - 1, shift);
                    else select_cell (cur_row, cols.size - 1, shift);
                    return true;
                case Gdk.Key.Return:
                case Gdk.Key.KP_Enter:
                    if (shift) {
                        if (is_new_row (cur_row)) commit_new_row ();
                        return true;
                    }
                    begin_edit (null);
                    return true;
                case Gdk.Key.F2:
                    begin_edit (null);
                    return true;
                case Gdk.Key.Escape:
                    if (is_new_row (cur_row) && pending.size > 0) {
                        pending.clear ();
                        queue_draw ();
                        return true;
                    }
                    if (selected_records.size > 0 || anchor_row != cur_row || anchor_col != cur_col) {
                        selected_records.clear ();
                        select_cell (cur_row, cur_col, false);
                        return true;
                    }
                    return false;
                case Gdk.Key.Delete:
                case Gdk.Key.BackSpace:
                    clear_cells ();
                    return true;
                case Gdk.Key.space:
                    var f = current_field ();
                    if (f != null && f.field_type == FieldType.BOOLEAN && !ctrl) {
                        toggle_boolean ();
                        return true;
                    }
                    break;
                case Gdk.Key.semicolon:
                    if (ctrl) {
                        var df = current_field ();
                        if (df != null) {
                            string today = new DateTime.now_local ().format (df.field_type == FieldType.TIME ? "%H:%M:%S" : "%Y-%m-%d");
                            set_current_value_text (df.field_type == FieldType.DATETIME ? new DateTime.now_local ().format ("%Y-%m-%d %H:%M:%S") : today);
                        }
                        return true;
                    }
                    break;
                case Gdk.Key.apostrophe:
                    if (ctrl) {
                        ditto ();
                        return true;
                    }
                    break;
                default:
                    break;
            }
            if (ctrl || alt) return false;
            unichar ch = Gdk.keyval_to_unicode (keyval);
            if (ch >= 32 && ch != 127) {
                var f = current_field ();
                if (f == null) return false;
                if (f.field_type == FieldType.BOOLEAN || f.field_type == FieldType.ATTACHMENT) return false;
                var sb = new StringBuilder ();
                sb.append_unichar (ch);
                begin_edit (sb.str);
                return true;
            }
            return false;
        }

        private bool editable_cell (Field f) {
            if (read_only || src == null || !src.editable) return false;
            if (f.field_type == FieldType.AUTONUMBER) return false;
            return src.field_updatable (f.name);
        }

        public void begin_edit (string? initial) {
            var f = current_field ();
            if (f == null) return;
            int gh;
            int64 rec = record_at (cur_row, out gh);
            if (gh >= 0) return;
            if (!editable_cell (f)) {
                if (f.field_type == FieldType.AUTONUMBER && !read_only) error (_("\"%s\" is numbered automatically.").printf (f.name));
                return;
            }
            if (rec >= 0 && locker != null) {
                string lt;
                int64 lid;
                if (src.lock_target (rec, out lt, out lid)) {
                    if (!locker (lt, lid)) return;
                    locked_table = lt;
                    locked_id = lid;
                }
            }
            if (f.field_type == FieldType.BOOLEAN) {
                toggle_boolean ();
                return;
            }
            if (f.field_type == FieldType.ATTACHMENT) {
                var row = current_row ();
                if (row != null) attachment_requested (row.rowid, f);
                else if (is_new_row (cur_row)) error (_("Save the record first, then add the attachment."));
                return;
            }
            if ((f.field_type == FieldType.CHOICE || f.field_type == FieldType.LOOKUP) && f.multi_value) {
                show_multi_picker (f);
                return;
            }
            if (f.field_type == FieldType.CHOICE || f.field_type == FieldType.LOOKUP) {
                show_picker (f, initial);
                return;
            }
            if (f.field_type == FieldType.LONG_TEXT && initial == null) {
                show_zoom (f);
                return;
            }
            DbValue v = current_value (f);
            editing = true;
            edit_row = cur_row;
            edit_col = cur_col;
            editor.text = initial ?? Codec.edit_text (f, v);
            editor.xalign = f.field_type.is_numeric () ? 1 : 0;
            editor.visible = true;
            position_editor ();
            editor.grab_focus ();
            if (initial != null) editor.set_position (-1);
            else editor.select_region (0, -1);
            if (f.field_type == FieldType.DATE || f.field_type == FieldType.DATETIME) {
                if (initial == null) show_calendar (f);
            }
            queue_draw ();
        }

        private DbValue current_value (Field f) {
            if (is_new_row (cur_row)) return pending.has_key (f.name) ? pending[f.name] : new DbValue.null ();
            var row = current_row ();
            if (row == null) return new DbValue.null ();
            return row.get (src.def.index_of (f.name));
        }

        private void position_editor () {
            if (!editing || edit_col >= widths.length) return;
            double x = double.max (sel_w, col_x (edit_col)), y = row_y (edit_row);
            int w = int.max (60, widths[edit_col]);
            int nat_w, min_w, nb, mb, nat_h, min_h;
            editor.measure (Orientation.HORIZONTAL, -1, out min_w, out nat_w, out mb, out nb);
            editor.measure (Orientation.VERTICAL, -1, out min_h, out nat_h, out mb, out nb);
            var alloc = Gtk.Allocation () { x = (int) x, y = (int) y + 1, width = int.max (w, min_w), height = int.max (row_h - 2, min_h) };
            editor.allocate_size (alloc, -1);
        }

        private bool on_editor_key (uint keyval, uint code, Gdk.ModifierType state) {
            switch (keyval) {
                case Gdk.Key.Escape:
                    cancel_edit ();
                    grab_focus ();
                    return true;
                case Gdk.Key.Tab:
                    if (commit_edit ()) move (0, 1, false);
                    return true;
                case Gdk.Key.ISO_Left_Tab:
                    if (commit_edit ()) move (0, -1, false);
                    return true;
                case Gdk.Key.Up:
                    if (commit_edit ()) move (-1, 0, false);
                    return true;
                case Gdk.Key.Down:
                    if ((state & Gdk.ModifierType.ALT_MASK) != 0) {
                        var f = current_field ();
                        if (f != null && (f.field_type == FieldType.DATE || f.field_type == FieldType.DATETIME)) show_calendar (f);
                        return true;
                    }
                    if (commit_edit ()) move (1, 0, false);
                    return true;
                case Gdk.Key.Return:
                case Gdk.Key.KP_Enter:
                    if ((state & Gdk.ModifierType.SHIFT_MASK) != 0) {
                        if (commit_edit () && is_new_row (cur_row)) commit_new_row ();
                        return true;
                    }
                    return false;
                default:
                    return false;
            }
        }

        public void cancel_edit () {
            release_lock ();
            if (!editing) return;
            editing = false;
            editor.visible = false;
            queue_draw ();
        }

        public bool commit_edit () {
            if (!editing) return true;
            if (committing) return false;
            committing = true;
            var f = cols[edit_col];
            bool ok = store_text (f, editor.text, edit_row);
            committing = false;
            if (!ok) {
                editor.grab_focus ();
                return false;
            }
            editing = false;
            editor.visible = false;
            release_lock ();
            grab_focus ();
            queue_draw ();
            return true;
        }

        private bool store_text (Field f, string text, int di) {
            DbValue v;
            try {
                v = Codec.parse (f, text);
            } catch (Error e) {
                error (e.message);
                return false;
            }
            return store_value (f, v, di);
        }

        private bool store_value (Field f, DbValue v, int di) {
            if (is_new_row (di)) {
                pending[f.name] = v;
                queue_draw ();
                return true;
            }
            int gh;
            int64 rec = record_at (di, out gh);
            var row = rec >= 0 ? src.row (rec) : null;
            if (row == null) return true;
            try {
                src.set_value (row.rowid, f.name, v);
                if (grouped && f.name == src.state.group_by) {
                    rebuild_groups ();
                    int64 idx = src.index_of_rowid (row.rowid);
                    if (idx >= 0) cur_row = display_of_record (idx);
                    anchor_row = cur_row;
                }
                if (src.state.sorts.size > 0 || src.state.filters.size > 0) {
                    int64 idx = src.index_of_rowid (row.rowid);
                    if (idx >= 0) {
                        cur_row = display_of_record (idx);
                        anchor_row = cur_row;
                    }
                }
            } catch (Error e) {
                error (e.message);
                return false;
            }
            selection_changed ();
            return true;
        }

        public bool commit_new_row () {
            if (pending.size == 0) return true;
            string[] names = {};
            DbValue[] vals = {};
            foreach (var e in pending.entries) {
                names += e.key;
                vals += e.value;
            }
            foreach (var e in defaults.entries) {
                if (pending.has_key (e.key)) continue;
                names += e.key;
                vals += e.value;
            }
            try {
                int64 id = src.add_row (names, vals);
                pending.clear ();
                update_adjustments ();
                record_added (id);
                int64 idx = src.index_of_rowid (id);
                if (idx >= 0 && idx != record_count () - 1) {
                    cur_row = display_of_record (idx);
                    anchor_row = cur_row;
                }
                queue_draw ();
                selection_changed ();
                return true;
            } catch (Error e) {
                error (e.message);
                return false;
            }
        }

        public bool has_pending () {
            return pending.size > 0;
        }

        public void new_record () {
            if (!can_add ()) return;
            if (editing && !commit_edit ()) return;
            select_cell (record_count (), 0, false);
            for (int c = 0; c < cols.size; c++) {
                if (editable_cell (cols[c])) {
                    select_cell (record_count (), c, false);
                    break;
                }
            }
            grab_focus ();
        }

        private void toggle_boolean () {
            var f = current_field ();
            if (f == null || !editable_cell (f)) return;
            var v = current_value (f);
            store_value (f, new DbValue.bool (!v.as_bool ()), cur_row);
            queue_draw ();
        }

        public void set_current_value_text (string text) {
            var f = current_field ();
            if (f == null || !editable_cell (f)) return;
            store_text (f, text, cur_row);
            queue_draw ();
        }

        public void set_current_value (DbValue v) {
            var f = current_field ();
            if (f == null || !editable_cell (f)) return;
            store_value (f, v, cur_row);
            queue_draw ();
        }

        private void ditto () {
            var f = current_field ();
            if (f == null || cur_row == 0) return;
            int gh;
            int64 prev = record_at (cur_row - 1, out gh);
            if (prev < 0) return;
            var row = src.row (prev);
            if (row == null) return;
            set_current_value (row.get (src.def.index_of (f.name)).copy ());
        }

        public void clear_cells () {
            if (read_only || src == null || !src.editable) return;
            int r1 = int.min (anchor_row, cur_row), r2 = int.max (anchor_row, cur_row);
            int c1 = int.min (anchor_col, cur_col), c2 = int.max (anchor_col, cur_col);
            for (int di = r1; di <= r2; di++) {
                for (int c = c1; c <= c2; c++) {
                    var f = cols[c];
                    if (!editable_cell (f)) continue;
                    if (!store_value (f, f.field_type == FieldType.BOOLEAN ? new DbValue.bool (false) : new DbValue.null (), di)) return;
                }
            }
            queue_draw ();
        }

        private void open_link () {
            var f = current_field ();
            var v = current_value (f);
            if (v.is_null) return;
            string uri = v.to_string ();
            if (f.field_type == FieldType.EMAIL && !uri.has_prefix ("mailto:")) uri = "mailto:" + uri;
            if (f.field_type == FieldType.URL && !uri.contains ("://")) uri = "https://" + uri;
            var launcher = new UriLauncher (uri);
            launcher.launch.begin (get_root () as Gtk.Window, null);
        }

        private Gdk.Rectangle cell_rect (int r, int c) {
            var rect = Gdk.Rectangle ();
            rect.x = (int) double.max (sel_w, col_x (c));
            rect.y = (int) row_y (r);
            rect.width = c < widths.length ? widths[c] : 100;
            rect.height = row_h;
            return rect;
        }

        private void show_multi_picker (Field f) {
            var pop = new Popover ();
            pop.set_parent (this);
            pop.pointing_to = cell_rect (cur_row, cur_col);
            pop.position = PositionType.BOTTOM;
            var box = new Box (Orientation.VERTICAL, 6);
            box.margin_start = box.margin_end = box.margin_top = box.margin_bottom = 8;
            var keys = new Gee.ArrayList<string> ();
            var labels = new Gee.ArrayList<string> ();
            if (f.field_type == FieldType.CHOICE) {
                foreach (string c in f.choices) {
                    keys.add (c);
                    labels.add (c);
                }
            } else {
                foreach (var r in src.lookup_choices (f)) {
                    keys.add (r.get (0).to_string ());
                    labels.add (r.get (1).to_string ());
                }
            }
            int di = cur_row;
            int gh;
            int64 rec = record_at (di, out gh);
            var row = rec >= 0 ? src.row (rec) : null;
            var current = row != null ? MultiValue.items (row.get (src.def.index_of (f.name))) : (pending.has_key (f.name) ? MultiValue.items (pending[f.name]) : new string[0]);
            var checks = new Gee.ArrayList<CheckButton> ();
            var list = new Box (Orientation.VERTICAL, 2);
            for (int i = 0; i < keys.size; i++) {
                var c = new CheckButton.with_label (labels[i]);
                foreach (string it in current) if (it == keys[i]) c.active = true;
                checks.add (c);
                list.append (c);
            }
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.propagate_natural_height = true;
            scroll.max_content_height = 320;
            scroll.min_content_width = 220;
            scroll.child = list;
            box.append (scroll);
            var ok = new Button.with_label (_("OK"));
            ok.add_css_class ("suggested-action");
            ok.halign = Align.END;
            ok.clicked.connect (() => {
                string[] on = {};
                for (int i = 0; i < checks.size; i++) if (checks[i].active) on += keys[i];
                pop.popdown ();
                store_value (f, MultiValue.from_list (on), di);
            });
            box.append (ok);
            pop.child = box;
            pop.closed.connect (() => Idle.add (() => {
                pop.unparent ();
                return Source.REMOVE;
            }));
            pop.popup ();
        }

        private void show_picker (Field f, string? initial) {
            var pop = new Popover ();
            pop.add_css_class ("menu");
            pop.set_parent (this);
            pop.pointing_to = cell_rect (cur_row, cur_col);
            pop.position = PositionType.BOTTOM;
            pop.has_arrow = false;
            var box = new Box (Orientation.VERTICAL, 6);
            box.margin_start = box.margin_end = box.margin_top = box.margin_bottom = 6;
            var search = new SearchEntry ();
            search.placeholder_text = _("Search");
            box.append (search);
            var list = new ListBox ();
            list.selection_mode = SelectionMode.BROWSE;
            list.add_css_class ("navigation-sidebar");
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.propagate_natural_height = true;
            scroll.max_content_height = 320;
            scroll.min_content_width = 240;
            scroll.child = list;
            box.append (scroll);
            pop.child = box;
            var values = new Gee.ArrayList<DbValue> ();
            var labels = new Gee.ArrayList<string> ();
            values.add (new DbValue.null ());
            labels.add (_("(Empty)"));
            if (f.field_type == FieldType.CHOICE) {
                foreach (string c in f.choices) {
                    values.add (new DbValue.text (c));
                    labels.add (c);
                }
            } else {
                foreach (var r in src.lookup_choices (f)) {
                    values.add (r.get (0));
                    labels.add (r.get (1).to_string ());
                }
            }
            for (int i = 0; i < labels.size; i++) {
                var l = new Label (labels[i]);
                l.halign = Align.START;
                l.margin_start = 6;
                l.margin_top = 4;
                l.margin_bottom = 4;
                list.append (l);
            }
            int di = cur_row;
            list.set_filter_func ((row) => {
                string q = search.text.strip ().casefold ();
                if (q == "") return true;
                return labels[row.get_index ()].casefold ().contains (q);
            });
            search.search_changed.connect (() => {
                list.invalidate_filter ();
                for (int i = 0; i < labels.size; i++) {
                    var row = list.get_row_at_index (i);
                    if (row.get_child_visible () && row.visible) {
                        string q = search.text.strip ().casefold ();
                        if (q == "" || labels[i].casefold ().contains (q)) {
                            list.select_row (row);
                            break;
                        }
                    }
                }
            });
            search.activate.connect (() => {
                var sel = list.get_selected_row ();
                if (sel != null) list.row_activated (sel);
            });
            var skeys = new EventControllerKey ();
            skeys.key_pressed.connect ((kv, kc, st) => {
                if (kv == Gdk.Key.Down || kv == Gdk.Key.Up) {
                    var sel = list.get_selected_row ();
                    int i = sel != null ? sel.get_index () : -1;
                    int step = kv == Gdk.Key.Down ? 1 : -1;
                    for (int k = i + step; k >= 0 && k < labels.size; k += step) {
                        var row = list.get_row_at_index (k);
                        string q = search.text.strip ().casefold ();
                        if (q == "" || labels[k].casefold ().contains (q)) {
                            list.select_row (row);
                            row.grab_focus ();
                            search.grab_focus ();
                            break;
                        }
                    }
                    return true;
                }
                return false;
            });
            search.add_controller (skeys);
            list.row_activated.connect ((row) => {
                int i = row.get_index ();
                pop.popdown ();
                store_value (f, values[i], di);
                queue_draw ();
            });
            var cur = current_value (f);
            for (int i = 0; i < values.size; i++) {
                if (values[i].kind == cur.kind && values[i].equals (cur)) list.select_row (list.get_row_at_index (i));
            }
            pop.closed.connect (() => Idle.add (() => {
                pop.unparent ();
                grab_focus ();
                return Source.REMOVE;
            }));
            pop.popup ();
            if (initial != null) {
                search.text = initial;
                search.set_position (-1);
            }
            search.grab_focus ();
        }

        private void show_zoom (Field f) {
            var pop = new Popover ();
            pop.set_parent (this);
            pop.pointing_to = cell_rect (cur_row, cur_col);
            pop.position = PositionType.BOTTOM;
            var box = new Box (Orientation.VERTICAL, 8);
            box.margin_start = box.margin_end = box.margin_top = box.margin_bottom = 8;
            var view = new TextView ();
            view.wrap_mode = WrapMode.WORD_CHAR;
            view.top_margin = view.bottom_margin = view.left_margin = view.right_margin = 6;
            view.buffer.text = current_value (f).to_string ();
            var scroll = new ScrolledWindow ();
            scroll.min_content_width = 420;
            scroll.min_content_height = 200;
            scroll.child = view;
            scroll.add_css_class ("db-sql-frame");
            box.append (scroll);
            var bar = new Box (Orientation.HORIZONTAL, 8);
            bar.halign = Align.END;
            var cancel = new Button.with_label (_("Cancel"));
            var ok = new Button.with_label (_("Save"));
            ok.add_css_class ("suggested-action");
            bar.append (cancel);
            bar.append (ok);
            box.append (bar);
            pop.child = box;
            int di = cur_row;
            cancel.clicked.connect (() => pop.popdown ());
            ok.clicked.connect (() => {
                if (store_text (f, view.buffer.text, di)) pop.popdown ();
            });
            pop.closed.connect (() => Idle.add (() => {
                pop.unparent ();
                grab_focus ();
                queue_draw ();
                return Source.REMOVE;
            }));
            pop.popup ();
            view.grab_focus ();
        }

        private void show_calendar (Field f) {
            var pop = new Popover ();
            pop.set_parent (this);
            pop.pointing_to = cell_rect (cur_row, cur_col);
            pop.position = PositionType.BOTTOM;
            pop.autohide = true;
            pop.can_focus = false;
            var cal = new Gtk.Calendar ();
            var v = current_value (f);
            string iso = v.to_string ();
            if (iso.length >= 10) {
                var dt = new DateTime.local (int.parse (iso.substring (0, 4)), int.parse (iso.substring (5, 2)), int.parse (iso.substring (8, 2)), 0, 0, 0);
                if (dt != null) cal.select_day (dt);
            }
            pop.child = cal;
            int di = cur_row;
            cal.day_selected.connect (() => {
                var d = cal.get_date ();
                string s = d.format ("%Y-%m-%d");
                if (f.field_type == FieldType.DATETIME && iso.length >= 19) s += iso.substring (10);
                cancel_edit ();
                pop.popdown ();
                store_value (f, new DbValue.text (s), di);
                queue_draw ();
            });
            pop.closed.connect (() => Idle.add (() => {
                pop.unparent ();
                return Source.REMOVE;
            }));
            pop.popup ();
            editor.grab_focus ();
        }

        public string copy_text () {
            var sb = new StringBuilder ();
            if (selected_records.size > 0) {
                for (int c = 0; c < cols.size; c++) {
                    if (c > 0) sb.append_c ('\t');
                    sb.append (cols[c].name);
                }
                sb.append_c ('\n');
                foreach (var rec in selected_records) {
                    var row = src.row (rec);
                    if (row == null) continue;
                    for (int c = 0; c < cols.size; c++) {
                        if (c > 0) sb.append_c ('\t');
                        sb.append (cell_text (row, cols[c]));
                    }
                    sb.append_c ('\n');
                }
                return sb.str;
            }
            int r1 = int.min (anchor_row, cur_row), r2 = int.max (anchor_row, cur_row);
            int c1 = int.min (anchor_col, cur_col), c2 = int.max (anchor_col, cur_col);
            for (int di = r1; di <= r2; di++) {
                int gh;
                int64 rec = record_at (di, out gh);
                if (rec < 0) continue;
                var row = src.row (rec);
                if (row == null) continue;
                for (int c = c1; c <= c2; c++) {
                    if (c > c1) sb.append_c ('\t');
                    sb.append (cell_text (row, cols[c]));
                }
                if (di < r2 || r1 != r2 || c1 != c2) sb.append_c ('\n');
            }
            return sb.str;
        }

        private string cell_text (Row row, Field f) {
            var v = row.get (src.def.index_of (f.name));
            if (v.is_null) return "";
            string s = f.field_type == FieldType.LOOKUP ? src.display (f, v) : Codec.edit_text (f, v);
            return s.replace ("\t", " ").replace ("\n", " ");
        }

        public void paste_text (string text) {
            if (read_only || src == null || !src.editable) return;
            if (editing) return;
            string[] lines = text.replace ("\r\n", "\n").split ("\n");
            int n = lines.length;
            if (n > 0 && lines[n - 1] == "") n--;
            int start_row = cur_row;
            int errors = 0;
            for (int i = 0; i < n; i++) {
                string[] cells = lines[i].split ("\t");
                int di = start_row + i;
                bool is_new = di >= record_count () || is_new_row (di);
                if (is_new && !can_add ()) break;
                if (is_new) {
                    pending.clear ();
                    for (int k = 0; k < cells.length && cur_col + k < cols.size; k++) {
                        var f = cols[cur_col + k];
                        if (!editable_cell (f)) continue;
                        try {
                            pending[f.name] = parse_for (f, cells[k]);
                        } catch (Error e) {
                            errors++;
                        }
                    }
                    if (!commit_new_row ()) break;
                    continue;
                }
                for (int k = 0; k < cells.length && cur_col + k < cols.size; k++) {
                    var f = cols[cur_col + k];
                    if (!editable_cell (f)) continue;
                    try {
                        var v = parse_for (f, cells[k]);
                        if (!store_value (f, v, di)) errors++;
                    } catch (Error e) {
                        errors++;
                    }
                }
            }
            if (errors > 0) error (ngettext ("%d value could not be pasted.", "%d values could not be pasted.", errors).printf (errors));
            queue_draw ();
        }

        private DbValue parse_for (Field f, string text) throws Error {
            if (f.field_type == FieldType.LOOKUP) {
                foreach (var r in src.lookup_choices (f, 5000)) {
                    if (r.get (1).to_string ().casefold () == text.strip ().casefold ()) return r.get (0);
                }
            }
            return Codec.parse (f, text);
        }

        private bool on_tooltip (int x, int y, bool keyboard, Tooltip tip) {
            if (src == null || y < head_h || y > get_height () - footer_h ()) return false;
            int r = row_at (y), c = column_at (x);
            if (r < 0 || c < 0) return false;
            int gh;
            int64 rec = record_at (r, out gh);
            if (rec < 0) return false;
            var row = src.row (rec);
            if (row == null) return false;
            var f = cols[c];
            var v = row.get (src.def.index_of (f.name));
            if (v.is_null || f.field_type == FieldType.BOOLEAN) return false;
            string text = src.display (f, v);
            if (layout == null) return false;
            layout.set_text (text, -1);
            layout.set_width (-1);
            int lw, lh;
            layout.get_pixel_size (out lw, out lh);
            if (lw < widths[c] - 14 && !text.contains ("\n")) return false;
            tip.set_text (text.length > 2000 ? text.substring (0, text.index_of_nth_char (2000)) + "…" : text);
            return true;
        }

        public void set_width (string field, int w) {
            for (int c = 0; c < cols.size; c++) {
                if (cols[c].name == field) {
                    widths[c] = w;
                    if (c < base_widths.length) base_widths[c] = w;
                    src.state.widths[field] = w;
                }
            }
            update_adjustments ();
            queue_draw ();
        }

        public void autofit (int c) {
            if (layout == null) layout = create_pango_layout (null);
            var f = cols[c];
            layout.set_width (-1);
            layout.set_attributes (null);
            layout.set_text (f.name, -1);
            int lw, lh;
            layout.get_pixel_size (out lw, out lh);
            int best = lw + 40;
            int64 n = int64.min (src.count (), 300);
            for (int64 i = 0; i < n; i++) {
                var row = src.row (i);
                if (row == null) continue;
                layout.set_text (src.display (f, row.get (src.def.index_of (f.name))).replace ("\n", " "), -1);
                layout.get_pixel_size (out lw, out lh);
                best = int.max (best, lw + 24);
            }
            set_width (f.name, int.min (best, 520));
            layout_changed ();
        }
    }
}
