using Gtk;

namespace Singularity.Apps.Database {

    public class ResultGrid : Widget, Scrollable {
        private Gee.List<ColumnMeta> columns = new Gee.ArrayList<ColumnMeta> ();
        private Gee.List<Row> rows = new Gee.ArrayList<Row> ();
        private int[] widths = {};
        private bool[] numeric = {};
        private bool[] key_cols = {};
        private bool[] bool_cols = {};
        public PendingChanges? pending { get; private set; }
        public int sort_col { get; set; default = -1; }
        public bool sort_desc { get; set; }
        public bool more_available { get; set; }
        public int cur_row { get; private set; }
        public int cur_col { get; private set; }
        private int anchor_row;
        private int anchor_col;
        private int gutter = 52;
        private int row_h = 26;
        private int head_h = 30;
        private Pango.Layout? layout;
        private Gdk.RGBA fg;
        private Gdk.RGBA accent;
        private bool dark;
        private bool updating_adj;
        private Entry editor;
        private bool editing;
        private int edit_row;
        private int edit_col;
        private bool committing;
        private int resize_col = -1;
        private int resize_start_w;
        private double drag_x0;
        private bool drag_select;
        private bool needs_size;
        private int sampled = -1;

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

        public signal void need_more ();
        public signal void sort_requested (int col);
        public signal void cell_menu (double x, double y);
        public signal void edited ();
        public signal void cursor_moved ();

        public ResultGrid () {
            focusable = true;
            can_focus = true;
            overflow = Overflow.HIDDEN;
            has_tooltip = true;
            add_css_class ("db-datasheet");
            add_css_class ("db-result-grid");
            editor = new Entry ();
            editor.add_css_class ("db-cell-editor");
            editor.has_frame = false;
            editor.set_parent (this);
            editor.visible = false;
            editor.activate.connect (() => {
                if (commit_edit ()) move (1, 0, false);
            });
            var ekeys = new EventControllerKey ();
            ekeys.key_pressed.connect ((kv, kc, st) => {
                if (kv == Gdk.Key.Escape) {
                    cancel_edit ();
                    return true;
                }
                if (kv == Gdk.Key.Tab) {
                    if (commit_edit ()) move (0, 1, false);
                    return true;
                }
                return false;
            });
            editor.add_controller (ekeys);
            var efocus = new EventControllerFocus ();
            efocus.leave.connect (() => {
                if (editing && !committing) Idle.add (() => {
                    if (editing && !editor.has_focus && !editor.get_delegate ().has_focus) commit_edit ();
                    return Source.REMOVE;
                });
            });
            editor.add_controller (efocus);

            var click = new GestureClick ();
            click.button = 0;
            click.pressed.connect (on_click);
            add_controller (click);
            var drag = new GestureDrag ();
            drag.drag_begin.connect ((x, y) => {
                drag_x0 = x;
                int edge = column_edge (x);
                if (y < head_h && edge >= 0) {
                    resize_col = edge;
                    resize_start_w = widths[edge];
                } else {
                    resize_col = -1;
                    drag_select = y >= head_h && x >= gutter;
                }
            });
            drag.drag_update.connect ((dx, dy) => {
                if (resize_col >= 0) {
                    widths[resize_col] = int.max (40, resize_start_w + (int) dx);
                    update_adjustments ();
                    queue_draw ();
                    return;
                }
                if (!drag_select) return;
                double sx, sy;
                drag.get_start_point (out sx, out sy);
                int r = row_at (sy + dy), c = col_at (sx + dx);
                if (r >= 0 && c >= 0 && (r != cur_row || c != cur_col)) {
                    cur_row = r;
                    cur_col = c;
                    queue_draw ();
                }
            });
            drag.drag_end.connect (() => {
                resize_col = -1;
                drag_select = false;
            });
            add_controller (drag);
            var keys = new EventControllerKey ();
            keys.key_pressed.connect (on_key);
            add_controller (keys);
            var motion = new EventControllerMotion ();
            motion.motion.connect ((x, y) => {
                set_cursor_from_name (y < head_h && column_edge (x) >= 0 ? "col-resize" : null);
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

        public bool get_border (out Gtk.Border border) {
            border = Gtk.Border ();
            return false;
        }

        public void set_result (Gee.List<ColumnMeta> cols, Gee.List<Row> data, PendingChanges? changes, string[] keys = {}) {
            if (editing) cancel_edit ();
            if (pending != null) pending.changed.disconnect (on_pending);
            columns = cols;
            rows = data;
            pending = changes;
            if (pending != null) pending.changed.connect (on_pending);
            widths = new int[cols.size];
            numeric = new bool[cols.size];
            key_cols = new bool[cols.size];
            bool_cols = new bool[cols.size];
            for (int c = 0; c < cols.size; c++) {
                string tn = cols[c].type_name.down ();
                bool_cols[c] = tn == "bool" || tn == "boolean";
            }
            for (int c = 0; c < cols.size; c++) {
                foreach (string k in keys) if (k == cols[c].name) key_cols[c] = true;
            }
            sampled = -1;
            autosize ();
            cur_row = cur_col = anchor_row = anchor_col = 0;
            if (_vadj != null) _vadj.value = 0;
            if (_hadj != null) _hadj.value = 0;
            update_adjustments ();
            queue_draw ();
        }

        private void on_pending () {
            update_adjustments ();
            queue_draw ();
        }

        public void rows_appended () {
            if (sampled < 200 && rows.size > sampled) autosize ();
            update_adjustments ();
            queue_draw ();
        }

        public int total_rows () {
            return rows.size + (pending != null ? pending.inserted.size : 0);
        }

        public bool is_inserted_row (int r) {
            return r >= rows.size;
        }

        private void autosize () {
            if (layout == null) layout = create_pango_layout (null);
            bool grow_only = sampled >= 0;
            int sample = int.min (rows.size, 200);
            sampled = sample;
            needs_size = false;
            for (int c = 0; c < columns.size; c++) {
                int w = text_width (columns[c].name, true) + 34 + (key_cols[c] ? 12 : 0);
                int nums = 0, seen = 0;
                for (int r = 0; r < sample; r++) {
                    var v = rows[r].get (c);
                    if (v.is_null) continue;
                    seen++;
                    if (v.is_number ()) nums++;
                    string t = display (v);
                    if (t.length > 80) t = t.substring (0, t.index_of_nth_char (80));
                    w = int.max (w, text_width (t, false) + 26);
                }
                numeric[c] = seen > 0 && nums == seen;
                int nw = w.clamp (64, 380);
                widths[c] = grow_only ? int.max (widths[c], nw) : nw;
            }
            int g = text_width (int.max (rows.size, 1).to_string (), false) + 22;
            gutter = int.max (44, g);
        }

        private int text_width (string t, bool bold) {
            layout.set_width (-1);
            layout.set_text (t.replace ("\n", " "), -1);
            var attrs = new Pango.AttrList ();
            if (bold) attrs.insert (Pango.attr_weight_new (Pango.Weight.BOLD));
            layout.set_attributes (attrs);
            int w, h;
            layout.get_pixel_size (out w, out h);
            return w;
        }

        public static string display (DbValue v) {
            switch (v.kind) {
                case ValueKind.NULL: return "NULL";
                case ValueKind.BLOB: return _("binary, %s").printf (format_size ((uint64) v.blob_value.get_size ()));
                default:
                    string s = v.to_string ();
                    return s;
            }
        }

        public DbValue value_at (int r, int c) {
            if (pending != null) {
                if (r >= rows.size) {
                    int i = r - rows.size;
                    if (i < pending.inserted.size) return pending.inserted[i].get (c);
                    return new DbValue.null ();
                }
                var e = pending.edited (r, c);
                if (e != null) return e;
            }
            if (r < 0 || r >= rows.size) return new DbValue.null ();
            return rows[r].get (c);
        }

        public DbValue original_at (int r, int c) {
            if (r < 0 || r >= rows.size) return new DbValue.null ();
            return rows[r].get (c);
        }

        private double hscroll () {
            return _hadj != null ? _hadj.value : 0;
        }

        private double vscroll () {
            return _vadj != null ? _vadj.value : 0;
        }

        private double col_x (int c) {
            double x = gutter - hscroll ();
            for (int i = 0; i < c && i < widths.length; i++) x += widths[i];
            return x;
        }

        private double row_y (int r) {
            return head_h + r * (double) row_h - vscroll ();
        }

        private int row_at (double y) {
            if (y < head_h) return -1;
            int r = (int) ((y - head_h + vscroll ()) / row_h);
            if (r < 0 || r >= total_rows ()) return -1;
            return r;
        }

        private int col_at (double x) {
            if (x < gutter) return -1;
            double cx = gutter - hscroll ();
            for (int c = 0; c < widths.length; c++) {
                if (x >= cx && x < cx + widths[c]) return c;
                cx += widths[c];
            }
            return -1;
        }

        private int column_edge (double x) {
            double cx = gutter - hscroll ();
            for (int c = 0; c < widths.length; c++) {
                cx += widths[c];
                if (Math.fabs (x - cx) <= 4 && cx > gutter) return c;
            }
            return -1;
        }

        private void update_adjustments () {
            if (updating_adj) return;
            updating_adj = true;
            double w = get_width (), h = get_height ();
            if (_hadj != null) {
                double total = gutter;
                foreach (int x in widths) total += x;
                total += 40;
                _hadj.configure (_hadj.value.clamp (0, double.max (0, total - w)), 0, double.max (total, w), 20, w * 0.9, w);
            }
            if (_vadj != null) {
                double page = double.max (0, h - head_h);
                double total = total_rows () * (double) row_h + (more_available ? row_h : 0);
                _vadj.configure (_vadj.value.clamp (0, double.max (0, total - page)), 0, double.max (total, page), row_h * 3, page * 0.9, page);
            }
            updating_adj = false;
        }

        private void on_scrolled () {
            if (editing) position_editor ();
            queue_draw ();
            if (more_available && _vadj != null && _vadj.value + _vadj.page_size >= _vadj.upper - row_h * 20) need_more ();
        }

        public override void measure (Orientation o, int for_size, out int minimum, out int natural, out int mb, out int nb) {
            minimum = natural = 120;
            mb = nb = -1;
        }

        public override void size_allocate (int width, int height, int baseline) {
            update_adjustments ();
            if (editing) position_editor ();
            if (more_available && total_rows () * row_h < height) need_more ();
        }

        private static void rgba (Cairo.Context cr, Gdk.RGBA c, double alpha = 1) {
            cr.set_source_rgba (c.red, c.green, c.blue, c.alpha * alpha);
        }

        private void draw_text (Cairo.Context cr, string text, double x, double y, double w, double h, bool right, bool bold = false, double alpha = 1, Gdk.RGBA? color = null, bool italic = false, bool strike = false) {
            if (text == "" || w < 8) return;
            if (!text.validate ()) return;
            string t = text.length > 400 ? text.substring (0, text.index_of_nth_char (400)) : text;
            layout.set_text (t.replace ("\n", " "), -1);
            layout.set_width ((int) ((w - 12) * Pango.SCALE));
            layout.set_ellipsize (Pango.EllipsizeMode.END);
            layout.set_alignment (right ? Pango.Alignment.RIGHT : Pango.Alignment.LEFT);
            var attrs = new Pango.AttrList ();
            if (bold) attrs.insert (Pango.attr_weight_new (Pango.Weight.BOLD));
            if (italic) attrs.insert (Pango.attr_style_new (Pango.Style.ITALIC));
            if (strike) attrs.insert (Pango.attr_strikethrough_new (true));
            if (right) attrs.insert (new Pango.AttrFontFeatures ("tnum"));
            layout.set_attributes (attrs);
            int lw, lh;
            layout.get_pixel_size (out lw, out lh);
            rgba (cr, color ?? fg, alpha);
            cr.move_to (x + 6, y + (h - lh) / 2);
            Pango.cairo_show_layout (cr, layout);
        }

        public override void snapshot (Gtk.Snapshot snapshot) {
            fg = get_color ();
            dark = (fg.red + fg.green + fg.blue) / 3 > 0.5;
            if (!get_style_context ().lookup_color ("accent_bg_color", out accent)) accent = { 0.21f, 0.52f, 0.89f, 1 };
            if (layout == null) layout = create_pango_layout (null);
            if (needs_size) autosize ();
            double w = get_width (), h = get_height ();
            var cr = snapshot.append_cairo (Graphene.Rect ().init (0, 0, (float) w, (float) h));
            cr.set_source_rgb (dark ? 0.118 : 1, dark ? 0.122 : 1, dark ? 0.133 : 1);
            cr.paint ();
            cr.set_line_width (1);
            int n = total_rows ();
            int first = int.max (0, (int) (vscroll () / row_h));
            int last = int.min (n - 1, first + (int) ((h - head_h) / row_h) + 1);
            cr.save ();
            cr.rectangle (0, head_h, w, h - head_h);
            cr.clip ();
            for (int r = first; r <= last; r++) draw_row (cr, r, w);
            if (more_available && last >= n - 1) {
                double y = row_y (n);
                draw_text (cr, _("Loading more rows"), gutter, y, 300, row_h, false, false, 0.5, null, true);
            }
            draw_selection (cr);
            cr.restore ();
            draw_header (cr, w);
            if (editing) snapshot_child (editor, snapshot);
        }

        private void draw_row (Cairo.Context cr, int r, double w) {
            double y = row_y (r);
            bool inserted = is_inserted_row (r);
            bool deleted = pending != null && !inserted && pending.is_deleted (r);
            if (r % 2 == 1) {
                rgba (cr, fg, dark ? 0.035 : 0.025);
                cr.rectangle (gutter, y, w - gutter, row_h);
                cr.fill ();
            }
            if (inserted) {
                cr.set_source_rgba (0.18, 0.66, 0.36, dark ? 0.16 : 0.1);
                cr.rectangle (0, y, w, row_h);
                cr.fill ();
            } else if (deleted) {
                cr.set_source_rgba (0.88, 0.25, 0.25, dark ? 0.18 : 0.1);
                cr.rectangle (0, y, w, row_h);
                cr.fill ();
            }
            for (int c = 0; c < columns.size; c++) {
                double x = col_x (c);
                if (x > w) break;
                double cw = widths[c];
                if (x + cw < gutter) continue;
                bool changed = pending != null && !inserted && pending.edited (r, c) != null;
                if (changed) {
                    cr.set_source_rgba (0.95, 0.65, 0.1, dark ? 0.24 : 0.2);
                    cr.rectangle (double.max (x, gutter), y, cw, row_h);
                    cr.fill ();
                }
                cr.save ();
                cr.rectangle (double.max (x, gutter), y, cw, row_h);
                cr.clip ();
                var v = value_at (r, c);
                if (v.is_null) {
                    draw_text (cr, inserted ? _("default") : "NULL", x, y, cw, row_h, false, false, 0.35, null, true);
                } else {
                    bool blob = v.kind == ValueKind.BLOB;
                    if (bool_cols[c] && v.kind == ValueKind.INTEGER) draw_bool (cr, v.int_value != 0, x, y, cw);
                    else draw_text (cr, display (v), x, y, cw, row_h, numeric[c] && v.is_number (), false, blob ? 0.55 : 1, null, blob, deleted);
                }
                cr.restore ();
                rgba (cr, fg, dark ? 0.1 : 0.08);
                cr.move_to (Math.round (x + cw) - 0.5, y);
                cr.line_to (Math.round (x + cw) - 0.5, y + row_h);
                cr.stroke ();
            }
            rgba (cr, fg, dark ? 0.1 : 0.08);
            cr.move_to (gutter, Math.round (y + row_h) - 0.5);
            cr.line_to (col_x (columns.size), Math.round (y + row_h) - 0.5);
            cr.stroke ();
            rgba (cr, fg, dark ? 0.05 : 0.04);
            cr.rectangle (0, y, gutter, row_h);
            cr.fill ();
            if (r == cur_row) {
                rgba (cr, accent);
                cr.rectangle (0, y + 4, 3, row_h - 8);
                cr.fill ();
            }
            string mark = inserted ? "+" : (r + 1).to_string ();
            draw_text (cr, mark, 0, y, gutter - 4, row_h, true, inserted, inserted ? 0.8 : 0.45);
        }

        private void draw_bool (Cairo.Context cr, bool on, double x, double y, double cw) {
            double bx = x + 8, by = y + row_h / 2.0 - 7;
            if (on) {
                rgba (cr, accent);
                cr.new_sub_path ();
                cr.arc (bx + 10, by + 3, 3, -Math.PI / 2, 0);
                cr.arc (bx + 10, by + 11, 3, 0, Math.PI / 2);
                cr.arc (bx + 4, by + 11, 3, Math.PI / 2, Math.PI);
                cr.arc (bx + 4, by + 3, 3, Math.PI, 1.5 * Math.PI);
                cr.close_path ();
                cr.fill ();
                cr.set_source_rgb (1, 1, 1);
                cr.set_line_width (1.8);
                cr.move_to (bx + 3.5, by + 7.5);
                cr.line_to (bx + 6, by + 10);
                cr.line_to (bx + 10.5, by + 4.5);
                cr.stroke ();
            } else {
                rgba (cr, fg, 0.35);
                cr.set_line_width (1.3);
                cr.rectangle (bx + 0.65, by + 0.65, 12.7, 12.7);
                cr.stroke ();
            }
            cr.set_line_width (1);
        }

        private void draw_selection (Cairo.Context cr) {
            if (columns.size == 0 || total_rows () == 0) return;
            int r1 = int.min (anchor_row, cur_row), r2 = int.max (anchor_row, cur_row);
            int c1 = int.min (anchor_col, cur_col), c2 = int.max (anchor_col, cur_col);
            if (r1 != r2 || c1 != c2) {
                double x1 = double.max (gutter, col_x (c1)), x2 = col_x (c2 + 1);
                rgba (cr, accent, 0.14);
                cr.rectangle (x1, row_y (r1), x2 - x1, row_y (r2 + 1) - row_y (r1));
                cr.fill ();
            }
            if (cur_col >= widths.length) return;
            double x = col_x (cur_col), y = row_y (cur_row);
            if (x + widths[cur_col] < gutter) return;
            rgba (cr, accent);
            cr.set_line_width (2);
            double left = double.max (x, gutter);
            cr.rectangle (left + 1, y + 1, x + widths[cur_col] - left - 2, row_h - 2);
            cr.stroke ();
            cr.set_line_width (1);
        }

        private void draw_header (Cairo.Context cr, double w) {
            cr.set_source_rgb (dark ? 0.16 : 0.965, dark ? 0.165 : 0.97, dark ? 0.18 : 0.975);
            cr.rectangle (0, 0, w, head_h);
            cr.fill ();
            for (int c = 0; c < columns.size; c++) {
                double x = col_x (c);
                if (x > w) break;
                if (x + widths[c] < gutter) continue;
                cr.save ();
                cr.rectangle (double.max (x, gutter), 0, widths[c], head_h);
                cr.clip ();
                double tx = x;
                if (key_cols[c]) {
                    cr.set_source_rgba (0.93, 0.66, 0.1, 1);
                    cr.arc (x + 11, head_h / 2.0, 3.5, 0, 2 * Math.PI);
                    cr.fill ();
                    tx += 10;
                }
                double reserve = c == sort_col ? 16 : 0;
                draw_text (cr, columns[c].name, tx, 0, widths[c] - reserve - (tx - x), head_h, false, true, 0.85);
                if (c == sort_col) {
                    rgba (cr, accent);
                    double ix = x + widths[c] - 12, cy = head_h / 2.0;
                    if (!sort_desc) {
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
                }
                cr.restore ();
                rgba (cr, fg, dark ? 0.14 : 0.12);
                cr.move_to (Math.round (x + widths[c]) - 0.5, 6);
                cr.line_to (Math.round (x + widths[c]) - 0.5, head_h - 6);
                cr.stroke ();
            }
            cr.set_source_rgb (dark ? 0.16 : 0.965, dark ? 0.165 : 0.97, dark ? 0.18 : 0.975);
            cr.rectangle (0, 0, gutter, head_h);
            cr.fill ();
            rgba (cr, fg, dark ? 0.16 : 0.14);
            cr.move_to (0, head_h - 0.5);
            cr.line_to (w, head_h - 0.5);
            cr.stroke ();
        }

        private bool on_tooltip (int x, int y, bool kb, Tooltip tip) {
            int r = row_at (y), c = col_at (x);
            if (y < head_h) {
                c = col_at (x);
                if (c < 0) return false;
                var m = columns[c];
                string t = m.name;
                if (m.type_name != "") t += "\n" + m.type_name;
                if (key_cols[c]) t += "\n" + _("Primary key");
                tip.set_text (t);
                return true;
            }
            if (r < 0 || c < 0) return false;
            var v = value_at (r, c);
            string s = display (v);
            if (s.length < 30 && !s.contains ("\n")) return false;
            if (s.length > 2000) s = s.substring (0, s.index_of_nth_char (2000)) + "...";
            tip.set_text (s);
            return true;
        }

        private void on_click (GestureClick g, int n, double x, double y) {
            grab_focus ();
            uint button = g.get_current_button ();
            if (y < head_h) {
                if (button == Gdk.BUTTON_PRIMARY && column_edge (x) < 0) {
                    int c = col_at (x);
                    if (c >= 0) sort_requested (c);
                }
                return;
            }
            int r = row_at (y);
            int c = col_at (x);
            if (r < 0) return;
            if (editing && !commit_edit ()) return;
            if (x < gutter) {
                anchor_row = r;
                anchor_col = 0;
                cur_row = r;
                cur_col = int.max (0, columns.size - 1);
                queue_draw ();
                cursor_moved ();
                if (button == Gdk.BUTTON_SECONDARY) cell_menu (x, y);
                return;
            }
            if (c < 0) return;
            if (button == Gdk.BUTTON_SECONDARY) {
                bool inside = r >= int.min (anchor_row, cur_row) && r <= int.max (anchor_row, cur_row) && c >= int.min (anchor_col, cur_col) && c <= int.max (anchor_col, cur_col);
                if (!inside) set_cursor (r, c, false);
                cell_menu (x, y);
                return;
            }
            var st = g.get_current_event_state ();
            set_cursor (r, c, (st & Gdk.ModifierType.SHIFT_MASK) != 0);
            if (n == 2) begin_edit (null);
        }

        public void set_cursor (int r, int c, bool extend) {
            int n = total_rows ();
            if (n == 0 || columns.size == 0) return;
            cur_row = r.clamp (0, n - 1);
            cur_col = c.clamp (0, columns.size - 1);
            if (!extend) {
                anchor_row = cur_row;
                anchor_col = cur_col;
            }
            ensure_visible ();
            queue_draw ();
            cursor_moved ();
        }

        private void move (int dr, int dc, bool extend) {
            set_cursor (cur_row + dr, cur_col + dc, extend);
        }

        private void ensure_visible () {
            if (_vadj != null) {
                double top = cur_row * (double) row_h;
                double page = _vadj.page_size;
                if (top < _vadj.value) _vadj.value = top;
                else if (top + row_h > _vadj.value + page) _vadj.value = top + row_h - page;
            }
            if (_hadj != null && cur_col < widths.length) {
                double x = 0;
                for (int i = 0; i < cur_col; i++) x += widths[i];
                double vis = _hadj.page_size - gutter;
                if (x < _hadj.value) _hadj.value = x;
                else if (x + widths[cur_col] > _hadj.value + vis) _hadj.value = x + widths[cur_col] - vis;
            }
        }

        private bool on_key (uint kv, uint kc, Gdk.ModifierType st) {
            bool shift = (st & Gdk.ModifierType.SHIFT_MASK) != 0;
            bool ctrl = (st & Gdk.ModifierType.CONTROL_MASK) != 0;
            int page = int.max (1, (int) ((get_height () - head_h) / row_h) - 1);
            switch (kv) {
                case Gdk.Key.Up: move (-1, 0, shift); return true;
                case Gdk.Key.Down: move (1, 0, shift); return true;
                case Gdk.Key.Left: move (0, -1, shift); return true;
                case Gdk.Key.Right: move (0, 1, shift); return true;
                case Gdk.Key.Tab: move (0, 1, false); return true;
                case Gdk.Key.ISO_Left_Tab: move (0, -1, false); return true;
                case Gdk.Key.Page_Down: move (page, 0, shift); return true;
                case Gdk.Key.Page_Up: move (-page, 0, shift); return true;
                case Gdk.Key.Home:
                    set_cursor (ctrl ? 0 : cur_row, 0, shift);
                    return true;
                case Gdk.Key.End:
                    set_cursor (ctrl ? total_rows () - 1 : cur_row, columns.size - 1, shift);
                    return true;
                case Gdk.Key.Return:
                case Gdk.Key.KP_Enter:
                case Gdk.Key.F2:
                    begin_edit (null);
                    return true;
                case Gdk.Key.Delete:
                    if (pending != null && pending.editable) {
                        if (shift) delete_selected_rows ();
                        else set_selection_null ();
                        return true;
                    }
                    return false;
            }
            if (ctrl && (kv == Gdk.Key.c || kv == Gdk.Key.C)) {
                copy_selection ();
                return true;
            }
            if (ctrl && (kv == Gdk.Key.a || kv == Gdk.Key.A)) {
                anchor_row = 0;
                anchor_col = 0;
                cur_row = int.max (0, total_rows () - 1);
                cur_col = int.max (0, columns.size - 1);
                queue_draw ();
                return true;
            }
            if (!ctrl && pending != null && pending.editable) {
                unichar u = Gdk.keyval_to_unicode (kv);
                if (u != 0 && !u.iscntrl ()) {
                    var sb = new StringBuilder ();
                    sb.append_unichar (u);
                    begin_edit (sb.str);
                    return true;
                }
            }
            return false;
        }

        public bool can_edit () {
            return pending != null && pending.editable && columns.size > 0;
        }

        public void begin_edit (string? initial) {
            if (!can_edit () || total_rows () == 0) return;
            if (!is_inserted_row (cur_row) && pending.is_deleted (cur_row)) return;
            edit_row = cur_row;
            edit_col = cur_col;
            var v = value_at (edit_row, edit_col);
            if (v.kind == ValueKind.BLOB) return;
            editing = true;
            string start_text = "";
            if (initial != null) start_text = initial;
            else if (!v.is_null) start_text = v.to_string ();
            editor.text = start_text;
            editor.placeholder_text = v.is_null ? "NULL" : "";
            editor.visible = true;
            position_editor ();
            editor.grab_focus ();
            if (initial != null) editor.set_position (-1);
            else editor.select_region (0, -1);
            queue_draw ();
        }

        private void position_editor () {
            double x = double.max (col_x (edit_col), gutter), y = row_y (edit_row);
            double wv = col_x (edit_col) + widths[edit_col] - x;
            int mw, nw, mh, nh, mb, nb;
            editor.measure (Orientation.HORIZONTAL, -1, out mw, out nw, out mb, out nb);
            editor.measure (Orientation.VERTICAL, -1, out mh, out nh, out mb, out nb);
            var alloc = Gtk.Allocation () { x = (int) x + 1, y = (int) y + 1, width = int.max ((int) wv - 2, mw), height = int.max (row_h - 2, mh) };
            editor.allocate_size (alloc, -1);
        }

        public DbValue parse_input (string text, int col) {
            if (text == "") return new DbValue.null ();
            var orig = original_at (edit_row < rows.size ? edit_row : 0, col);
            string t = columns[col].type_name.down ();
            bool looks_int = int64.try_parse (text);
            bool numeric_type = t.contains ("int") || t.contains ("serial") || t == "integer";
            if ((orig.kind == ValueKind.INTEGER || numeric_type) && looks_int) {
                int64 v;
                int64.try_parse (text, out v);
                return new DbValue.int (v);
            }
            if (orig.kind == ValueKind.REAL || t.contains ("float") || t.contains ("double") || t.contains ("real")) {
                double d;
                if (double.try_parse (text, out d)) return new DbValue.real (d);
            }
            return new DbValue.text (text);
        }

        public bool commit_edit () {
            if (!editing) return true;
            committing = true;
            var cur = value_at (edit_row, edit_col);
            DbValue v;
            if (editor.text == "") v = cur.is_null || numeric[edit_col] ? new DbValue.null () : new DbValue.text ("");
            else v = parse_input (editor.text, edit_col);
            apply_value (edit_row, edit_col, v);
            editing = false;
            editor.visible = false;
            committing = false;
            grab_focus ();
            queue_draw ();
            return true;
        }

        private void apply_value (int r, int c, DbValue v) {
            if (pending == null) return;
            if (is_inserted_row (r)) pending.set_insert_value (r - rows.size, c, v);
            else pending.set_value (r, c, rows[r].get (c), v);
            edited ();
        }

        public void cancel_edit () {
            if (!editing) return;
            editing = false;
            editor.visible = false;
            grab_focus ();
            queue_draw ();
        }

        public void set_selection_null () {
            if (!can_edit ()) return;
            int r1 = int.min (anchor_row, cur_row), r2 = int.max (anchor_row, cur_row);
            int c1 = int.min (anchor_col, cur_col), c2 = int.max (anchor_col, cur_col);
            for (int r = r1; r <= r2; r++) {
                for (int c = c1; c <= c2; c++) apply_value (r, c, new DbValue.null ());
            }
        }

        public void delete_selected_rows () {
            if (!can_edit ()) return;
            int r1 = int.min (anchor_row, cur_row), r2 = int.max (anchor_row, cur_row);
            for (int r = r2; r >= r1; r--) {
                if (is_inserted_row (r)) pending.remove_insert (r - rows.size);
                else pending.toggle_delete (r);
            }
            if (cur_row >= total_rows ()) set_cursor (total_rows () - 1, cur_col, false);
            edited ();
        }

        public void add_row () {
            if (!can_edit ()) return;
            pending.add_insert ();
            update_adjustments ();
            set_cursor (total_rows () - 1, 0, false);
            grab_focus ();
            edited ();
        }

        public int[] selected_rows () {
            int r1 = int.min (anchor_row, cur_row), r2 = int.max (anchor_row, cur_row);
            int[] out_rows = {};
            for (int r = r1; r <= r2 && r < total_rows (); r++) out_rows += r;
            return out_rows;
        }

        public string selection_text (bool with_headers) {
            int r1 = int.min (anchor_row, cur_row), r2 = int.max (anchor_row, cur_row);
            int c1 = int.min (anchor_col, cur_col), c2 = int.max (anchor_col, cur_col);
            var sb = new StringBuilder ();
            if (with_headers) {
                for (int c = c1; c <= c2; c++) {
                    if (c > c1) sb.append_c ('\t');
                    sb.append (columns[c].name);
                }
                sb.append_c ('\n');
            }
            for (int r = r1; r <= r2 && r < total_rows (); r++) {
                for (int c = c1; c <= c2; c++) {
                    if (c > c1) sb.append_c ('\t');
                    var v = value_at (r, c);
                    if (!v.is_null) sb.append (v.kind == ValueKind.BLOB ? display (v) : v.to_string ().replace ("\t", " ").replace ("\n", " "));
                }
                if (r < r2) sb.append_c ('\n');
            }
            return sb.str;
        }

        public void copy_selection (bool with_headers = false) {
            if (columns.size == 0) return;
            get_clipboard ().set_text (selection_text (with_headers));
        }

        public string current_column_name () {
            if (cur_col < 0 || cur_col >= columns.size) return "";
            return columns[cur_col].name;
        }

        public DbValue current_value () {
            return value_at (cur_row, cur_col);
        }

        public int column_count () {
            return columns.size;
        }
    }
}
