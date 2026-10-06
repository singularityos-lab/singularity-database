using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Database {

    public interface Board : Widget {
        public abstract void rebuild ();
    }

    public class CoverPicture : Widget {
        private Gdk.Texture texture;

        public CoverPicture (Gdk.Texture texture) {
            this.texture = texture;
            overflow = Overflow.HIDDEN;
            hexpand = true;
        }

        public override void measure (Orientation o, int for_size, out int minimum, out int natural, out int mb, out int nb) {
            minimum = o == Orientation.VERTICAL ? 120 : 40;
            natural = o == Orientation.VERTICAL ? 120 : 200;
            mb = nb = -1;
        }

        public override void snapshot (Gtk.Snapshot snap) {
            float w = get_width (), h = get_height ();
            float tw = texture.get_width (), th = texture.get_height ();
            float scale = float.max (w / tw, h / th);
            float dw = tw * scale, dh = th * scale;
            var rect = Graphene.Rect ().init (0, 0, w, h);
            var rr = Gsk.RoundedRect ();
            rr.init_from_rect (rect, 10);
            snap.push_rounded_clip (rr);
            snap.append_texture (texture, Graphene.Rect ().init ((w - dw) / 2, (h - dh) / 2, dw, dh));
            snap.pop ();
        }
    }

    public class BoardCard : Button {
        public int64 rowid;

        public BoardCard (TablePage page, RecordSource src, ViewDef view, Row row, bool with_image) {
            rowid = row.rowid;
            add_css_class ("flat");
            add_css_class ("db-card");
            var box = new Box (Orientation.VERTICAL, 6);
            if (with_image && view.image_field != "") {
                var f = src.def.find (view.image_field);
                if (f != null) {
                    var v = row.get (src.def.index_of (f.name));
                    Widget cover;
                    Gdk.Texture? tex = null;
                    if (v.kind == ValueKind.BLOB) {
                        string n, m;
                        Bytes content;
                        if (!Attachment.unpack (v.blob_value, out n, out m, out content)) content = v.blob_value;
                        try {
                            tex = Gdk.Texture.from_bytes (content);
                        } catch (Error e) {
                        }
                    }
                    if (tex != null) {
                        var pic = new CoverPicture (tex);
                        pic.add_css_class ("db-card-image");
                        cover = pic;
                    } else {
                        var img = new Image.from_icon_name ("image-x-generic");
                        img.pixel_size = 64;
                        img.height_request = 120;
                        img.opacity = 0.5;
                        cover = img;
                    }
                    box.append (cover);
                }
            }
            var tf = src.def.find (view.title_field);
            string title = tf != null ? src.display (tf, row.get (src.def.index_of (tf.name))) : "";
            if (title == "") title = _("Untitled");
            var t = new Label (title);
            t.add_css_class ("db-card-title");
            t.halign = Align.START;
            t.xalign = 0;
            t.ellipsize = Pango.EllipsizeMode.END;
            t.max_width_chars = 30;
            box.append (t);
            foreach (string name in view.card_fields) {
                var f = src.def.find (name);
                if (f == null || f.name == view.title_field || f.field_type == FieldType.ATTACHMENT) continue;
                var v = row.get (src.def.index_of (f.name));
                if (v.is_null) continue;
                var line = new Box (Orientation.HORIZONTAL, 6);
                var icon = new Image.from_icon_name (f.field_type.icon_name ());
                icon.pixel_size = 12;
                icon.opacity = 0.55;
                icon.tooltip_text = f.name;
                line.append (icon);
                string text = src.display (f, v);
                var l = new Label (text.replace ("\n", " "));
                l.add_css_class ("db-card-field");
                l.halign = Align.START;
                l.ellipsize = Pango.EllipsizeMode.END;
                l.max_width_chars = 34;
                if (f.field_type == FieldType.CHOICE) {
                    double r, g, b;
                    DatasheetView.choice_color (text, out r, out g, out b);
                    var css = new CssProvider ();
                    css.load_from_string ("label { background-color: rgba(%d,%d,%d,0.22); border-radius: 99px; padding: 0 8px; }".printf ((int) (r * 255), (int) (g * 255), (int) (b * 255)));
                    l.get_style_context ().add_provider (css, STYLE_PROVIDER_PRIORITY_APPLICATION);
                }
                line.append (l);
                box.append (line);
            }
            child = box;
            clicked.connect (() => {
                if (src.editable) Dialogs.record_editor (page.win, src, rowid);
            });
        }
    }

    public class GalleryBoard : Box, Board {
        private TablePage page;
        private RecordSource src;
        private ViewDef view;
        private FlowBox flow;
        private Stack stack;

        public GalleryBoard (TablePage page, RecordSource src, ViewDef view) {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            this.page = page;
            this.src = src;
            this.view = view;
            stack = new Stack ();
            stack.vexpand = true;
            flow = new FlowBox ();
            flow.selection_mode = SelectionMode.NONE;
            flow.homogeneous = true;
            flow.min_children_per_line = 1;
            flow.max_children_per_line = 8;
            flow.column_spacing = 12;
            flow.row_spacing = 12;
            flow.valign = Align.START;
            flow.margin_start = flow.margin_end = 12;
            flow.margin_bottom = 12;
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.vexpand = true;
            scroll.child = flow;
            stack.add_named (scroll, "cards");
            var empty = new StatusPage ();
            empty.icon_name = "x-office-database";
            empty.title = _("No Records");
            empty.description = _("Add a record to see it as a card.");
            var add = new Button.with_label (_("New Record"));
            add.add_css_class ("suggested-action");
            add.halign = Align.CENTER;
            add.clicked.connect (() => Dialogs.record_editor (page.win, src, -1));
            empty.child = add;
            stack.add_named (empty, "empty");
            append (stack);
            rebuild ();
        }

        public void rebuild () {
            Widget? c;
            while ((c = flow.get_first_child ()) != null) flow.remove (c);
            int64 n = int64.min (src.count (), 2000);
            for (int64 i = 0; i < n; i++) {
                var row = src.row (i);
                if (row == null) continue;
                var card = new BoardCard (page, src, view, row, true);
                card.width_request = 240;
                flow.append (card);
            }
            stack.visible_child_name = n > 0 ? "cards" : "empty";
        }
    }

    public class KanbanBoard : Box, Board {
        private TablePage page;
        private RecordSource src;
        private ViewDef view;
        private Box lanes;

        public KanbanBoard (TablePage page, RecordSource src, ViewDef view) {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            this.page = page;
            this.src = src;
            this.view = view;
            lanes = new Box (Orientation.HORIZONTAL, 12);
            lanes.margin_start = lanes.margin_end = 12;
            lanes.margin_bottom = 12;
            var scroll = new ScrolledWindow ();
            scroll.vscrollbar_policy = PolicyType.NEVER;
            scroll.vexpand = true;
            scroll.child = lanes;
            append (scroll);
            rebuild ();
        }

        private Gee.ArrayList<DbValue> lane_values (Field f) {
            var list = new Gee.ArrayList<DbValue> ();
            if (f.field_type == FieldType.CHOICE) {
                foreach (string c in f.choices) list.add (new DbValue.text (c));
                list.add (new DbValue.null ());
                return list;
            }
            if (f.field_type == FieldType.BOOLEAN) {
                list.add (new DbValue.bool (false));
                list.add (new DbValue.bool (true));
                return list;
            }
            if (f.field_type == FieldType.LOOKUP) {
                foreach (var r in src.lookup_choices (f, 60)) list.add (r.get (0));
                list.add (new DbValue.null ());
                return list;
            }
            bool has_null = false;
            foreach (var v in src.distinct_values (f.name, 60)) {
                if (v.is_null) has_null = true;
                else list.add (v);
            }
            if (has_null || list.size == 0) list.add (new DbValue.null ());
            return list;
        }

        public void rebuild () {
            Widget? c;
            while ((c = lanes.get_first_child ()) != null) lanes.remove (c);
            var f = src.def.find (view.group_field);
            if (f == null) {
                var sp = new StatusPage ();
                sp.icon_name = "dialog-information";
                sp.title = _("Choose a Field to Stack By");
                sp.description = _("A choice list or a yes/no field works best for a board.");
                var b = new Button.with_label (_("View Settings…"));
                b.add_css_class ("suggested-action");
                b.halign = Align.CENTER;
                b.clicked.connect (() => Dialogs.view_settings (page.win, page, view));
                sp.child = b;
                sp.hexpand = true;
                lanes.append (sp);
                return;
            }
            var values = lane_values (f);
            var boxes = new Gee.ArrayList<Box> ();
            var counts = new Gee.ArrayList<Label> ();
            foreach (var v in values) {
                var lane = new Box (Orientation.VERTICAL, 8);
                lane.add_css_class ("db-lane");
                lane.width_request = 280;
                var head = new Box (Orientation.HORIZONTAL, 6);
                string label = v.is_null ? _("(Empty)") : src.display (f, v);
                var title = new Label (label);
                title.add_css_class ("db-lane-title");
                title.halign = Align.START;
                title.hexpand = true;
                title.ellipsize = Pango.EllipsizeMode.END;
                head.append (title);
                var count = new Label ("0");
                count.add_css_class ("dim-label");
                count.add_css_class ("caption");
                head.append (count);
                var add = new Button.from_icon_name ("list-add-symbolic");
                add.add_css_class ("flat");
                add.tooltip_text = _("New Record in %s").printf (label);
                var lane_value = v;
                add.clicked.connect (() => {
                    try {
                        var tf = src.def.find (view.title_field);
                        string[] cols = { f.name };
                        DbValue[] vals = { lane_value };
                        if (tf != null && tf != f && tf.field_type.is_text ()) {
                            cols += tf.name;
                            vals += new DbValue.text (_("New Record"));
                        }
                        int64 id = src.add_row (cols, vals);
                        rebuild ();
                        Dialogs.record_editor (page.win, src, id);
                    } catch (Error e) {
                        page.win.show_error (_("Could Not Add Record"), e.message);
                    }
                });
                add.sensitive = src.editable;
                head.append (add);
                lane.append (head);
                var cards = new Box (Orientation.VERTICAL, 8);
                var scroll = new ScrolledWindow ();
                scroll.hscrollbar_policy = PolicyType.NEVER;
                scroll.vexpand = true;
                scroll.child = cards;
                lane.append (scroll);
                var drop = new DropTarget (typeof (int64), Gdk.DragAction.MOVE);
                drop.enter.connect (() => {
                    lane.add_css_class ("drop-target");
                    return Gdk.DragAction.MOVE;
                });
                drop.leave.connect (() => lane.remove_css_class ("drop-target"));
                drop.drop.connect ((val, x, y) => {
                    lane.remove_css_class ("drop-target");
                    int64 rowid = val.get_int64 ();
                    try {
                        src.set_value (rowid, f.name, lane_value);
                        Idle.add (() => {
                            rebuild ();
                            return Source.REMOVE;
                        });
                    } catch (Error e) {
                        page.win.show_error (_("Could Not Move Card"), e.message);
                    }
                    return true;
                });
                if (src.editable) lane.add_controller (drop);
                boxes.add (cards);
                counts.add (count);
                lanes.append (lane);
            }
            int[] n = new int[values.size];
            int64 total = int64.min (src.count (), 3000);
            int fi = src.def.index_of (f.name);
            for (int64 i = 0; i < total; i++) {
                var row = src.row (i);
                if (row == null) continue;
                var v = row.get (fi);
                int lane = -1;
                for (int k = 0; k < values.size; k++) {
                    var lv = values[k];
                    if (lv.is_null && (v.is_null || (v.kind == ValueKind.TEXT && v.text_value == ""))) lane = k;
                    else if (!lv.is_null && !v.is_null && (f.field_type == FieldType.BOOLEAN ? lv.as_bool () == v.as_bool () : (f.field_type.is_text () ? lv.to_string ().casefold () == v.to_string ().casefold () : lv.equals (v)))) lane = k;
                    if (lane >= 0) break;
                }
                if (lane < 0) continue;
                var card = new BoardCard (page, src, view, row, false);
                if (src.editable) {
                    var ds = new DragSource ();
                    ds.actions = Gdk.DragAction.MOVE;
                    int64 rid = row.rowid;
                    ds.prepare.connect ((x, y) => {
                        var gv = GLib.Value (typeof (int64));
                        gv.set_int64 (rid);
                        return new Gdk.ContentProvider.for_value (gv);
                    });
                    ds.drag_begin.connect ((d) => {
                        var paint = new WidgetPaintable (card);
                        ds.set_icon (paint, 20, 20);
                    });
                    card.add_controller (ds);
                }
                boxes[lane].append (card);
                n[lane]++;
            }
            for (int k = 0; k < values.size; k++) counts[k].label = n[k].to_string ();
        }
    }

    public class CalendarBoard : Box, Board {
        private TablePage page;
        private RecordSource src;
        private ViewDef view;
        private Grid grid;
        private Label month_label;
        private DateTime month;

        public CalendarBoard (TablePage page, RecordSource src, ViewDef view) {
            Object (orientation: Orientation.VERTICAL, spacing: 8);
            this.page = page;
            this.src = src;
            this.view = view;
            var now = new DateTime.now_local ();
            month = new DateTime.local (now.get_year (), now.get_month (), 1, 0, 0, 0);
            var head = new Box (Orientation.HORIZONTAL, 6);
            head.margin_start = head.margin_end = 12;
            var prev = new Button.from_icon_name ("go-previous-symbolic");
            prev.add_css_class ("flat");
            prev.tooltip_text = _("Previous Month");
            prev.clicked.connect (() => {
                month = month.add_months (-1);
                rebuild ();
            });
            var next = new Button.from_icon_name ("go-next-symbolic");
            next.add_css_class ("flat");
            next.tooltip_text = _("Next Month");
            next.clicked.connect (() => {
                month = month.add_months (1);
                rebuild ();
            });
            var today = new Button.with_label (_("Today"));
            today.clicked.connect (() => {
                var t = new DateTime.now_local ();
                month = new DateTime.local (t.get_year (), t.get_month (), 1, 0, 0, 0);
                rebuild ();
            });
            month_label = new Label ("");
            month_label.add_css_class ("title-3");
            month_label.hexpand = true;
            month_label.halign = Align.START;
            month_label.margin_start = 6;
            head.append (month_label);
            head.append (today);
            head.append (prev);
            head.append (next);
            append (head);
            grid = new Grid ();
            grid.column_homogeneous = true;
            grid.row_homogeneous = true;
            grid.column_spacing = 6;
            grid.row_spacing = 6;
            grid.vexpand = true;
            grid.margin_start = grid.margin_end = 12;
            grid.margin_bottom = 12;
            append (grid);
            rebuild ();
        }

        public void rebuild () {
            Widget? c;
            while ((c = grid.get_first_child ()) != null) grid.remove (c);
            month_label.label = month.format ("%B %Y");
            var f = src.def.find (view.date_field);
            if (f == null) {
                var sp = new StatusPage ();
                sp.icon_name = "x-office-calendar";
                sp.title = _("No Date Field");
                sp.description = _("Add a date field to the table to place records on the calendar.");
                sp.hexpand = true;
                sp.vexpand = true;
                grid.attach (sp, 0, 0, 7, 6);
                return;
            }
            var t0 = new DateTime.local (2024, 1, 1, 0, 0, 0);
            for (int d = 0; d < 7; d++) {
                var day = t0.add_days (d);
                var l = new Label (day.format ("%a"));
                l.add_css_class ("dim-label");
                l.add_css_class ("caption");
                grid.attach (l, d, 0, 1, 1);
            }
            int offset = month.get_day_of_week () - 1;
            var start = month.add_days (-offset);
            var end = start.add_days (42);
            var by_day = new Gee.HashMap<string, Gee.ArrayList<Row>> ();
            var st = src.state.copy ();
            var fs = new FilterSpec (f.name, FilterOp.BETWEEN, start.format ("%Y-%m-%d"));
            fs.value2 = end.format ("%Y-%m-%d") + " 23:59:59";
            st.filters.add (fs);
            st.sorts.clear ();
            st.sorts.add (new SortSpec (f.name, false));
            st.group_by = "";
            try {
                var ranged = new RecordSource (src.db, src.source, st);
                int fi = ranged.def.index_of (f.name);
                int64 n = int64.min (ranged.count (), 2000);
                for (int64 i = 0; i < n; i++) {
                    var row = ranged.row (i);
                    if (row == null) continue;
                    string iso = row.get (fi).to_string ();
                    if (iso.length < 10) continue;
                    string k = iso.substring (0, 10);
                    if (!by_day.has_key (k)) by_day[k] = new Gee.ArrayList<Row> ();
                    by_day[k].add (row);
                }
            } catch (Error e) {
            }
            var tf = src.def.find (view.title_field);
            string today = new DateTime.now_local ().format ("%Y-%m-%d");
            for (int i = 0; i < 42; i++) {
                var day = start.add_days (i);
                string k = day.format ("%Y-%m-%d");
                var cell = new Box (Orientation.VERTICAL, 2);
                cell.add_css_class ("db-calendar-cell");
                if (day.get_month () != month.get_month ()) cell.add_css_class ("other-month");
                if (k == today) cell.add_css_class ("today");
                var num = new Label (day.get_day_of_month ().to_string ());
                num.halign = Align.END;
                num.add_css_class ("caption");
                cell.append (num);
                if (by_day.has_key (k)) {
                    int shown = 0;
                    foreach (var row in by_day[k]) {
                        if (shown == 3) {
                            var more = new Label (_("%d more").printf (by_day[k].size - 3));
                            more.add_css_class ("caption");
                            more.add_css_class ("dim-label");
                            more.halign = Align.START;
                            cell.append (more);
                            break;
                        }
                        string title = tf != null ? src.display (tf, row.get (src.def.index_of (tf.name))) : _("Record");
                        var ev = new Button.with_label (title == "" ? _("Untitled") : title);
                        ev.add_css_class ("flat");
                        ev.add_css_class ("db-calendar-event");
                        var lbl = ev.child as Label;
                        if (lbl != null) {
                            lbl.ellipsize = Pango.EllipsizeMode.END;
                            lbl.halign = Align.START;
                        }
                        int64 rid = row.rowid;
                        ev.clicked.connect (() => Dialogs.record_editor (page.win, src, rid));
                        cell.append (ev);
                        shown++;
                    }
                }
                if (src.editable) {
                    var click = new GestureClick ();
                    click.set_propagation_phase (PropagationPhase.BUBBLE);
                    string dk = k;
                    click.released.connect ((n, x, y) => {
                        if (n != 2) return;
                        try {
                            string[] cols = { f.name };
                            DbValue[] vals = { new DbValue.text (f.field_type == FieldType.DATETIME ? dk + " 09:00:00" : dk) };
                            int64 id = src.add_row (cols, vals);
                            rebuild ();
                            Dialogs.record_editor (page.win, src, id);
                        } catch (Error e) {
                            page.win.show_error (_("Could Not Add Record"), e.message);
                        }
                    });
                    cell.add_controller (click);
                    cell.tooltip_text = _("Double-click to add a record on this day");
                }
                grid.attach (cell, i % 7, 1 + i / 7, 1, 1);
            }
        }
    }
}
