using Gtk;

namespace Singularity.Apps.Database {

    public class PropertySheet : Box {
        public delegate void TextChanged (string text);
        public delegate void BoolChanged (bool value);
        public delegate void NumberChanged (double value);
        public delegate void ChoiceChanged (int index, string value);
        public delegate void Clicked ();

        private Grid grid;
        private int row;

        public PropertySheet () {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            add_css_class ("db-sheet");
            add_css_class ("db-dense");
            grid = new Grid ();
            grid.column_spacing = 12;
            grid.row_spacing = 4;
            append (grid);
        }

        public void clear () {
            Widget? c;
            while ((c = grid.get_first_child ()) != null) grid.remove (c);
            row = 0;
        }

        public Box section (string title, string? subtitle = null) {
            var box = new Box (Orientation.HORIZONTAL, 6);
            box.add_css_class ("db-sheet-section");
            if (row > 0) box.margin_top = 14;
            var l = new Label (title);
            l.add_css_class ("db-sheet-title");
            l.halign = Align.START;
            l.hexpand = true;
            l.xalign = 0;
            box.append (l);
            grid.attach (box, 0, row++, 2, 1);
            if (subtitle != null && subtitle != "") {
                var s = new Label (subtitle);
                s.add_css_class ("caption");
                s.add_css_class ("dim-label");
                s.halign = Align.START;
                s.xalign = 0;
                s.wrap = true;
                s.max_width_chars = 40;
                s.margin_bottom = 2;
                grid.attach (s, 0, row++, 2, 1);
            }
            return box;
        }

        public Button section_button (Box section, string label, owned Clicked cb) {
            var b = new Button.with_label (label);
            b.add_css_class ("db-small-button");
            b.valign = Align.CENTER;
            b.clicked.connect (() => cb ());
            section.append (b);
            return b;
        }

        private Label label_for (string text) {
            var l = new Label (text);
            l.add_css_class ("db-sheet-label");
            l.halign = Align.START;
            l.xalign = 0;
            l.valign = Align.CENTER;
            l.ellipsize = Pango.EllipsizeMode.END;
            l.width_chars = 12;
            l.max_width_chars = 16;
            return l;
        }

        public void add_widget (string? label, Widget w) {
            w.hexpand = true;
            if (label == null) {
                grid.attach (w, 0, row++, 2, 1);
                return;
            }
            var l = label_for (label);
            l.tooltip_text = label;
            grid.attach (l, 0, row, 1, 1);
            grid.attach (w, 1, row++, 1, 1);
        }

        public Entry add_entry (string label, string value, owned TextChanged cb, string placeholder = "") {
            var e = new Entry ();
            e.text = value;
            e.placeholder_text = placeholder;
            e.changed.connect (() => cb (e.text));
            add_widget (label, e);
            return e;
        }

        public Switch add_switch (string label, bool active, owned BoolChanged cb) {
            var s = new Switch ();
            s.active = active;
            s.halign = Align.START;
            s.valign = Align.CENTER;
            s.notify["active"].connect (() => cb (s.active));
            var box = new Box (Orientation.HORIZONTAL, 0);
            box.append (s);
            add_widget (label, box);
            return s;
        }

        public CheckButton add_check (string label, bool active, owned BoolChanged cb) {
            var c = new CheckButton.with_label (label);
            c.active = active;
            c.toggled.connect (() => cb (c.active));
            add_widget (null, c);
            return c;
        }

        public SpinButton add_spin (string label, double min, double max, double step, double value, owned NumberChanged cb, int digits = 0) {
            var s = new SpinButton.with_range (min, max, step);
            s.digits = digits;
            s.value = value;
            s.value_changed.connect (() => cb (s.value));
            add_widget (label, s);
            return s;
        }

        public DropDown add_choice (string label, string[] items, int selected, owned ChoiceChanged cb) {
            string[] safe = {};
            foreach (string it in items) safe += it;
            var d = new DropDown.from_strings (safe);
            if (selected >= 0 && selected < items.length) d.selected = selected;
            d.enable_search = items.length > 12;
            d.expression = new PropertyExpression (typeof (StringObject), null, "string");
            string[] copy = items;
            d.notify["selected"].connect (() => {
                if (d.selected < copy.length) cb ((int) d.selected, copy[d.selected]);
            });
            add_widget (label, d);
            return d;
        }

        public Label add_value (string label, string value) {
            var v = new Label (value);
            v.halign = Align.START;
            v.xalign = 0;
            v.selectable = true;
            v.wrap = true;
            v.add_css_class ("db-sheet-value");
            add_widget (label, v);
            return v;
        }

        public Label add_note (string text) {
            var l = new Label (text);
            l.add_css_class ("caption");
            l.add_css_class ("dim-label");
            l.halign = Align.START;
            l.xalign = 0;
            l.wrap = true;
            l.max_width_chars = 40;
            add_widget (null, l);
            return l;
        }

        public Box add_item (string icon, string title, string subtitle, string? action_label, owned Clicked? action) {
            var box = new Box (Orientation.HORIZONTAL, 8);
            box.add_css_class ("db-sheet-item");
            var img = new Image.from_icon_name (icon);
            img.valign = Align.CENTER;
            box.append (img);
            var texts = new Box (Orientation.VERTICAL, 0);
            texts.hexpand = true;
            var t = new Label (title);
            t.halign = Align.START;
            t.xalign = 0;
            t.ellipsize = Pango.EllipsizeMode.END;
            texts.append (t);
            if (subtitle != "") {
                var s = new Label (subtitle);
                s.add_css_class ("caption");
                s.add_css_class ("dim-label");
                s.halign = Align.START;
                s.xalign = 0;
                s.ellipsize = Pango.EllipsizeMode.END;
                texts.append (s);
            }
            box.append (texts);
            if (action_label != null) {
                var b = new Button.from_icon_name (action_label);
                b.add_css_class ("flat");
                b.add_css_class ("db-small-button");
                b.valign = Align.CENTER;
                b.clicked.connect (() => action ());
                box.append (b);
            }
            add_widget (null, box);
            return box;
        }
    }

    public class StatusStrip : Box {
        private Label label;

        public StatusStrip () {
            Object (orientation: Orientation.HORIZONTAL, spacing: 6);
            add_css_class ("db-record-bar");
            label = new Label ("");
            label.add_css_class ("db-status");
            label.add_css_class ("dim-label");
            label.hexpand = true;
            label.halign = Align.START;
            label.ellipsize = Pango.EllipsizeMode.END;
            append (label);
        }

        public void set_text (string text) {
            label.label = text;
        }
    }
}
