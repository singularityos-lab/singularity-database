namespace Singularity.Apps.Database {

    public enum ReportLayoutKind {
        TABULAR,
        STACKED,
        LABELS;

        public string id () {
            switch (this) {
                case STACKED: return "stacked";
                case LABELS: return "labels";
                default: return "tabular";
            }
        }

        public static ReportLayoutKind from_id (string s) {
            switch (s) {
                case "stacked": return STACKED;
                case "labels": return LABELS;
                default: return TABULAR;
            }
        }

        public string label () {
            switch (this) {
                case STACKED: return _("Stacked");
                case LABELS: return _("Labels");
                default: return _("Tabular");
            }
        }
    }

    public enum ReportTotal {
        NONE,
        SUM,
        AVG,
        COUNT,
        MIN,
        MAX;

        public const ReportTotal[] ALL = { NONE, SUM, AVG, COUNT, MIN, MAX };

        public string id () {
            switch (this) {
                case SUM: return "sum";
                case AVG: return "avg";
                case COUNT: return "count";
                case MIN: return "min";
                case MAX: return "max";
                default: return "none";
            }
        }

        public static ReportTotal from_id (string s) {
            foreach (var t in ALL) {
                if (t.id () == s) return t;
            }
            return NONE;
        }

        public string label () {
            switch (this) {
                case SUM: return _("Sum");
                case AVG: return _("Average");
                case COUNT: return _("Count");
                case MIN: return _("Minimum");
                case MAX: return _("Maximum");
                default: return _("None");
            }
        }
    }

    public enum ReportAlign {
        AUTO,
        LEFT,
        CENTER,
        RIGHT
    }

    public class ReportColumn {
        public string field;
        public string label;
        public double width = 1;
        public ReportAlign align = ReportAlign.AUTO;
        public ReportTotal total = ReportTotal.NONE;

        public ReportColumn (string field, string label) {
            this.field = field;
            this.label = label;
        }
    }

    public class ReportGroup {
        public string field;
        public bool descending;
        public bool header = true;
        public bool footer = true;
        public bool page_break;
        public string interval = "each";
        public int interval_size = 1;
        public bool keep_together;

        public ReportGroup (string field) {
            this.field = field;
        }

        public string interval_label () {
            switch (interval) {
                case "prefix": return ngettext ("By first %d character", "By first %d characters", interval_size).printf (interval_size);
                case "year": return _("By year");
                case "quarter": return _("By quarter");
                case "month": return _("By month");
                case "week": return _("By week");
                case "day": return _("By day");
                case "hour": return _("By hour");
                case "interval": return _("By intervals of %d").printf (interval_size);
                default: return _("By entire value");
            }
        }

        public DbValue key_of (DbValue v) {
            if (v.is_null || interval == "each") return v;
            switch (interval) {
                case "prefix":
                    string t = v.to_string ();
                    int n = int.max (1, interval_size);
                    return new DbValue.text (t.char_count () <= n ? t.up () : t.substring (0, t.index_of_nth_char (n)).up ());
                case "interval":
                    double d = v.as_double ();
                    double step = double.max (1, interval_size);
                    return new DbValue.real (Math.floor (d / step) * step);
            }
            double serial;
            if (!Script.iso_to_serial (v.to_string (), out serial)) return v;
            int y, m, d, hh, mm, ss;
            Script.split_serial (serial, out y, out m, out d, out hh, out mm, out ss);
            switch (interval) {
                case "year": return new DbValue.int (y);
                case "quarter": return new DbValue.text ("%04d Q%d".printf (y, (m - 1) / 3 + 1));
                case "month": return new DbValue.text ("%04d-%02d".printf (y, m));
                case "week":
                    double start = Math.floor (serial) - (AccessFormat.weekday (serial) - 1);
                    return new DbValue.text (Script.serial_to_iso (start));
                case "day": return new DbValue.text ("%04d-%02d-%02d".printf (y, m, d));
                case "hour": return new DbValue.text ("%04d-%02d-%02d %02d:00".printf (y, m, d, hh));
            }
            return v;
        }

        public string key_label (DbValue key) {
            if (key.is_null) return _("(Empty)");
            switch (interval) {
                case "year": return key.to_string ();
                case "month":
                    string t = key.to_string ();
                    if (t.length == 7) return "%s %s".printf (AccessFormat.month_name (int.parse (t.substring (5, 2)), false), t.substring (0, 4));
                    return t;
                case "week": return _("Week of %s").printf (Codec.display_date (key.to_string ()));
                case "day": return Codec.display_date (key.to_string ());
                case "interval":
                    double a = key.as_double ();
                    return "%s - %s".printf (Codec.format_number (a, -1, true), Codec.format_number (a + interval_size - (interval_size >= 1 ? 1 : 0), -1, true));
                default: return key.to_string ();
            }
        }
    }

    public class ReportSection {
        public string kind;
        public int height = 24;
        public bool visible = true;
        public bool keep_together = true;
        public bool new_page_before;
        public bool new_page_after;
        public bool can_grow = true;
        public string back_color = "";
        public string on_format = "";

        public ReportSection (string kind, int height) {
            this.kind = kind;
            this.height = height;
        }

        public string label () {
            switch (kind) {
                case "report-header": return _("Report Header");
                case "page-header": return _("Page Header");
                case "detail": return _("Detail");
                case "page-footer": return _("Page Footer");
                case "report-footer": return _("Report Footer");
            }
            if (kind.has_prefix ("group-header:")) return _("Group Header %s").printf ((int.parse (kind.substring (13)) + 1).to_string ());
            if (kind.has_prefix ("group-footer:")) return _("Group Footer %s").printf ((int.parse (kind.substring (13)) + 1).to_string ());
            return kind;
        }
    }

    public class ReportControl {
        public string kind = "text";
        public string section = "detail";
        public string name = "";
        public double x;
        public double y;
        public double w = 120;
        public double h = 16;
        public string source = "";
        public string caption = "";
        public string format = "";
        public double font_size = 9;
        public bool bold;
        public bool italic;
        public string align = "left";
        public string fore = "";
        public string back = "";
        public string running_sum = "no";
        public bool can_grow = true;
        public bool hide_duplicates;
        public bool visible = true;
        public bool border;
        public string image = "";
        public string subreport = "";
        public string link_master = "";
        public string link_child = "";
        public string chart_type = "column";
        public string chart_source = "";
        public string chart_category = "";
        public string chart_value = "";
        public string chart_aggregate = "sum";
        public string chart_series = "";
        public Gee.ArrayList<CondRule> conditions = new Gee.ArrayList<CondRule> ();

        public void build (Json.Builder b) {
            b.begin_object ();
            b.set_member_name ("kind").add_string_value (kind);
            b.set_member_name ("section").add_string_value (section);
            b.set_member_name ("name").add_string_value (name);
            b.set_member_name ("x").add_double_value (x);
            b.set_member_name ("y").add_double_value (y);
            b.set_member_name ("w").add_double_value (w);
            b.set_member_name ("h").add_double_value (h);
            b.set_member_name ("source").add_string_value (source);
            b.set_member_name ("caption").add_string_value (caption);
            b.set_member_name ("format").add_string_value (format);
            b.set_member_name ("font-size").add_double_value (font_size);
            b.set_member_name ("bold").add_boolean_value (bold);
            b.set_member_name ("italic").add_boolean_value (italic);
            b.set_member_name ("align").add_string_value (align);
            b.set_member_name ("fore").add_string_value (fore);
            b.set_member_name ("back").add_string_value (back);
            b.set_member_name ("running-sum").add_string_value (running_sum);
            b.set_member_name ("can-grow").add_boolean_value (can_grow);
            b.set_member_name ("hide-duplicates").add_boolean_value (hide_duplicates);
            b.set_member_name ("visible").add_boolean_value (visible);
            b.set_member_name ("border").add_boolean_value (border);
            if (image != "") b.set_member_name ("image").add_string_value (image);
            if (subreport != "") {
                b.set_member_name ("subreport").add_string_value (subreport);
                b.set_member_name ("link-master").add_string_value (link_master);
                b.set_member_name ("link-child").add_string_value (link_child);
            }
            if (kind == "chart") {
                b.set_member_name ("chart-type").add_string_value (chart_type);
                b.set_member_name ("chart-source").add_string_value (chart_source);
                b.set_member_name ("chart-category").add_string_value (chart_category);
                b.set_member_name ("chart-value").add_string_value (chart_value);
                b.set_member_name ("chart-aggregate").add_string_value (chart_aggregate);
                b.set_member_name ("chart-series").add_string_value (chart_series);
                b.set_member_name ("link-master").add_string_value (link_master);
                b.set_member_name ("link-child").add_string_value (link_child);
            }
            CondRule.build_list (b, "conditions", conditions);
            b.end_object ();
        }

        public static ReportControl read (Json.Object o) {
            var c = new ReportControl ();
            c.kind = o.get_string_member_with_default ("kind", "text");
            c.section = o.get_string_member_with_default ("section", "detail");
            c.name = o.get_string_member_with_default ("name", "");
            c.x = o.get_double_member_with_default ("x", 0);
            c.y = o.get_double_member_with_default ("y", 0);
            c.w = o.get_double_member_with_default ("w", 120);
            c.h = o.get_double_member_with_default ("h", 16);
            c.source = o.get_string_member_with_default ("source", "");
            c.caption = o.get_string_member_with_default ("caption", "");
            c.format = o.get_string_member_with_default ("format", "");
            c.font_size = o.get_double_member_with_default ("font-size", 9);
            c.bold = o.get_boolean_member_with_default ("bold", false);
            c.italic = o.get_boolean_member_with_default ("italic", false);
            c.align = o.get_string_member_with_default ("align", "left");
            c.fore = o.get_string_member_with_default ("fore", "");
            c.back = o.get_string_member_with_default ("back", "");
            c.running_sum = o.get_string_member_with_default ("running-sum", "no");
            c.can_grow = o.get_boolean_member_with_default ("can-grow", true);
            c.hide_duplicates = o.get_boolean_member_with_default ("hide-duplicates", false);
            c.visible = o.get_boolean_member_with_default ("visible", true);
            c.border = o.get_boolean_member_with_default ("border", false);
            c.image = o.get_string_member_with_default ("image", "");
            c.subreport = o.get_string_member_with_default ("subreport", "");
            c.link_master = o.get_string_member_with_default ("link-master", "");
            c.link_child = o.get_string_member_with_default ("link-child", "");
            c.chart_type = o.get_string_member_with_default ("chart-type", "column");
            c.chart_source = o.get_string_member_with_default ("chart-source", "");
            c.chart_category = o.get_string_member_with_default ("chart-category", "");
            c.chart_value = o.get_string_member_with_default ("chart-value", "");
            c.chart_aggregate = o.get_string_member_with_default ("chart-aggregate", "sum");
            c.chart_series = o.get_string_member_with_default ("chart-series", "");
            c.conditions = CondRule.read_list (o, "conditions");
            return c;
        }

        public ReportControl copy () {
            var b = new Json.Builder ();
            build (b);
            return read (b.get_root ().get_object ());
        }
    }

    public class ReportDef {
        public string name = "";
        public string source = "";
        public string title = "";
        public string subtitle = "";
        public ReportLayoutKind layout = ReportLayoutKind.TABULAR;
        public Gee.ArrayList<ReportColumn> columns = new Gee.ArrayList<ReportColumn> ();
        public Gee.ArrayList<ReportGroup> groups = new Gee.ArrayList<ReportGroup> ();
        public ViewState state = new ViewState ();
        public bool landscape;
        public string paper = "a4";
        public double margin_mm = 15;
        public bool grand_total = true;
        public bool show_count = true;
        public bool show_date = true;
        public bool page_numbers = true;
        public int label_columns = 3;
        public double font_scale = 1.0;
        public bool designed;
        public Gee.ArrayList<ReportSection> sections = new Gee.ArrayList<ReportSection> ();
        public Gee.ArrayList<ReportControl> controls = new Gee.ArrayList<ReportControl> ();
        public OrderedMap<string> events = new OrderedMap<string> ();
        public string code = "";

        public ReportSection? section (string kind) {
            foreach (var s in sections) {
                if (s.kind == kind) return s;
            }
            return null;
        }

        public ReportSection ensure_section (string kind, int height) {
            var s = section (kind);
            if (s != null) return s;
            s = new ReportSection (kind, height);
            sections.add (s);
            return s;
        }

        public ReportControl? find_control (string name) {
            foreach (var c in controls) {
                if (c.name.casefold () == name.casefold ()) return c;
            }
            return null;
        }

        public string unique_control_name (string base_name) {
            if (find_control (base_name) == null) return base_name;
            for (int i = 1; ; i++) {
                if (find_control ("%s%d".printf (base_name, i)) == null) return "%s%d".printf (base_name, i);
            }
        }

        public static ReportDef generate (Database db, string source) throws Error {
            var r = new ReportDef ();
            r.source = source;
            r.name = db.unique_object_name (source);
            r.title = source;
            var rs = new RecordSource (db, source);
            int n = 0;
            foreach (var f in rs.def.fields) {
                if (f.field_type == FieldType.ATTACHMENT || f.field_type == FieldType.AUTONUMBER) continue;
                if (n++ >= 7) break;
                var c = new ReportColumn (f.name, f.name);
                c.width = f.field_type == FieldType.LONG_TEXT ? 2.5 : (f.field_type.is_text () || f.field_type == FieldType.LOOKUP ? 1.6 : 1);
                if (f.field_type == FieldType.CURRENCY) c.total = ReportTotal.SUM;
                r.columns.add (c);
            }
            if (r.columns.size > 5) r.landscape = true;
            return r;
        }

        public double page_w;
        public double page_h;
        public string open_where = "";
        public string open_args = "";

        public void paper_size (out double w, out double h) {
            if (page_w > 0 && page_h > 0) {
                w = page_w;
                h = page_h;
                return;
            }
            if (paper == "letter") {
                w = 612;
                h = 792;
            } else if (paper == "legal") {
                w = 612;
                h = 1008;
            } else if (paper == "a3") {
                w = 841.89;
                h = 1190.55;
            } else {
                w = 595.28;
                h = 841.89;
            }
            if (landscape) {
                double t = w;
                w = h;
                h = t;
            }
        }

        public string to_json () {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("source").add_string_value (source);
            b.set_member_name ("title").add_string_value (title);
            b.set_member_name ("subtitle").add_string_value (subtitle);
            b.set_member_name ("layout").add_string_value (layout.id ());
            b.set_member_name ("landscape").add_boolean_value (landscape);
            b.set_member_name ("paper").add_string_value (paper);
            b.set_member_name ("margin").add_double_value (margin_mm);
            b.set_member_name ("grand-total").add_boolean_value (grand_total);
            b.set_member_name ("count").add_boolean_value (show_count);
            b.set_member_name ("date").add_boolean_value (show_date);
            b.set_member_name ("page-numbers").add_boolean_value (page_numbers);
            b.set_member_name ("label-columns").add_int_value (label_columns);
            b.set_member_name ("font-scale").add_double_value (font_scale);
            b.set_member_name ("columns").begin_array ();
            foreach (var c in columns) {
                b.begin_object ();
                b.set_member_name ("field").add_string_value (c.field);
                b.set_member_name ("label").add_string_value (c.label);
                b.set_member_name ("width").add_double_value (c.width);
                b.set_member_name ("align").add_int_value ((int) c.align);
                b.set_member_name ("total").add_string_value (c.total.id ());
                b.end_object ();
            }
            b.end_array ();
            b.set_member_name ("groups").begin_array ();
            foreach (var g in groups) {
                b.begin_object ();
                b.set_member_name ("field").add_string_value (g.field);
                b.set_member_name ("desc").add_boolean_value (g.descending);
                b.set_member_name ("header").add_boolean_value (g.header);
                b.set_member_name ("footer").add_boolean_value (g.footer);
                b.set_member_name ("page-break").add_boolean_value (g.page_break);
                b.set_member_name ("interval").add_string_value (g.interval);
                b.set_member_name ("interval-size").add_int_value (g.interval_size);
                b.set_member_name ("keep-together").add_boolean_value (g.keep_together);
                b.end_object ();
            }
            b.end_array ();
            if (designed) {
                b.set_member_name ("designed").add_boolean_value (true);
                b.set_member_name ("sections").begin_array ();
                foreach (var sec in sections) {
                    b.begin_object ();
                    b.set_member_name ("kind").add_string_value (sec.kind);
                    b.set_member_name ("height").add_int_value (sec.height);
                    b.set_member_name ("visible").add_boolean_value (sec.visible);
                    b.set_member_name ("keep-together").add_boolean_value (sec.keep_together);
                    b.set_member_name ("new-page-before").add_boolean_value (sec.new_page_before);
                    b.set_member_name ("new-page-after").add_boolean_value (sec.new_page_after);
                    b.set_member_name ("can-grow").add_boolean_value (sec.can_grow);
                    b.set_member_name ("back-color").add_string_value (sec.back_color);
                    b.set_member_name ("on-format").add_string_value (sec.on_format);
                    b.end_object ();
                }
                b.end_array ();
                b.set_member_name ("controls").begin_array ();
                foreach (var c in controls) c.build (b);
                b.end_array ();
            }
            if (events.size > 0) {
                b.set_member_name ("events").begin_object ();
                foreach (var e in events.entries) b.set_member_name (e.key).add_string_value (e.value);
                b.end_object ();
            }
            if (code != "") b.set_member_name ("code").add_string_value (code);
            b.set_member_name ("state").begin_object ();
            state.build (b);
            b.end_object ();
            b.end_object ();
            return Json.to_string (b.get_root (), false);
        }

        public static ReportDef? from_json (string name, string? json) {
            var o = Meta.parse_object (json);
            if (o == null) return null;
            var r = new ReportDef ();
            r.name = name;
            r.source = o.get_string_member_with_default ("source", "");
            r.title = o.get_string_member_with_default ("title", name);
            r.subtitle = o.get_string_member_with_default ("subtitle", "");
            r.layout = ReportLayoutKind.from_id (o.get_string_member_with_default ("layout", "tabular"));
            r.landscape = o.get_boolean_member_with_default ("landscape", false);
            r.paper = o.get_string_member_with_default ("paper", "a4");
            r.margin_mm = o.get_double_member_with_default ("margin", 15);
            r.grand_total = o.get_boolean_member_with_default ("grand-total", true);
            r.show_count = o.get_boolean_member_with_default ("count", true);
            r.show_date = o.get_boolean_member_with_default ("date", true);
            r.page_numbers = o.get_boolean_member_with_default ("page-numbers", true);
            r.label_columns = (int) o.get_int_member_with_default ("label-columns", 3);
            r.font_scale = o.get_double_member_with_default ("font-scale", 1.0);
            if (o.has_member ("columns")) {
                o.get_array_member ("columns").foreach_element ((a, i, n) => {
                    var c = n.get_object ();
                    var rc = new ReportColumn (c.get_string_member_with_default ("field", ""), c.get_string_member_with_default ("label", ""));
                    rc.width = c.get_double_member_with_default ("width", 1);
                    rc.align = (ReportAlign) c.get_int_member_with_default ("align", 0);
                    rc.total = ReportTotal.from_id (c.get_string_member_with_default ("total", "none"));
                    r.columns.add (rc);
                });
            }
            if (o.has_member ("groups")) {
                o.get_array_member ("groups").foreach_element ((a, i, n) => {
                    var c = n.get_object ();
                    var g = new ReportGroup (c.get_string_member_with_default ("field", ""));
                    g.descending = c.get_boolean_member_with_default ("desc", false);
                    g.header = c.get_boolean_member_with_default ("header", true);
                    g.footer = c.get_boolean_member_with_default ("footer", true);
                    g.page_break = c.get_boolean_member_with_default ("page-break", false);
                    g.interval = c.get_string_member_with_default ("interval", "each");
                    g.interval_size = (int) c.get_int_member_with_default ("interval-size", 1);
                    g.keep_together = c.get_boolean_member_with_default ("keep-together", false);
                    r.groups.add (g);
                });
            }
            r.designed = o.get_boolean_member_with_default ("designed", false);
            if (o.has_member ("sections")) {
                o.get_array_member ("sections").foreach_element ((a, i, n) => {
                    var so = n.get_object ();
                    var sec = new ReportSection (so.get_string_member_with_default ("kind", "detail"), (int) so.get_int_member_with_default ("height", 24));
                    sec.visible = so.get_boolean_member_with_default ("visible", true);
                    sec.keep_together = so.get_boolean_member_with_default ("keep-together", true);
                    sec.new_page_before = so.get_boolean_member_with_default ("new-page-before", false);
                    sec.new_page_after = so.get_boolean_member_with_default ("new-page-after", false);
                    sec.can_grow = so.get_boolean_member_with_default ("can-grow", true);
                    sec.back_color = so.get_string_member_with_default ("back-color", "");
                    sec.on_format = so.get_string_member_with_default ("on-format", "");
                    r.sections.add (sec);
                });
            }
            if (o.has_member ("controls") && r.designed) {
                r.controls.clear ();
                o.get_array_member ("controls").foreach_element ((a, i, n) => {
                    var no = n.get_object ();
                    if (no.has_member ("kind") && no.has_member ("section")) r.controls.add (ReportControl.read (no));
                });
            }
            if (o.has_member ("events")) {
                var ev = o.get_object_member ("events");
                foreach (string k in ev.get_members ()) r.events[k] = ev.get_string_member (k);
            }
            r.code = o.get_string_member_with_default ("code", "");
            if (o.has_member ("state")) r.state = ViewState.read (o.get_object_member ("state"));
            return r;
        }
    }

    public enum TextRole {
        TITLE,
        SUBTITLE,
        COLUMN_HEADER,
        BODY,
        GROUP_HEADER,
        SUBTOTAL,
        GRAND_TOTAL,
        FOOTER,
        FIELD_LABEL;

        public double size () {
            switch (this) {
                case TITLE: return 20;
                case SUBTITLE: return 10;
                case COLUMN_HEADER: return 8.5;
                case GROUP_HEADER: return 11;
                case SUBTOTAL: return 9;
                case GRAND_TOTAL: return 10;
                case FOOTER: return 8;
                case FIELD_LABEL: return 8;
                default: return 9;
            }
        }

        public bool bold () {
            return this == TITLE || this == COLUMN_HEADER || this == GROUP_HEADER || this == SUBTOTAL || this == GRAND_TOTAL;
        }
    }

    public enum ItemKind {
        TEXT,
        LINE,
        FILL,
        RECT,
        IMAGE,
        CHART,
        CHECK
    }

    public class PageItem {
        public ItemKind kind;
        public double x;
        public double y;
        public double w;
        public double h;
        public string text = "";
        public string markup = "";
        public TextRole role = TextRole.BODY;
        public ReportAlign align = ReportAlign.LEFT;
        public double shade;
        public bool custom;
        public double font_size;
        public bool bold;
        public bool italic;
        public string color = "";
        public string fill_color = "";
        public Bytes? image;
        public ChartData? chart;
        public string chart_type = "column";
        public bool checked_state;
        public double x2;
        public double y2;

        public PageItem.label (double x, double y, double w, double h, string text, TextRole role, ReportAlign align) {
            kind = ItemKind.TEXT;
            this.x = x;
            this.y = y;
            this.w = w;
            this.h = h;
            this.text = text;
            this.role = role;
            this.align = align;
        }

        public PageItem.line (double x, double y, double w, double shade = 0.3) {
            kind = ItemKind.LINE;
            this.x = x;
            this.y = y;
            this.w = w;
            this.shade = shade;
        }

        public PageItem.fill (double x, double y, double w, double h, double shade) {
            kind = ItemKind.FILL;
            this.x = x;
            this.y = y;
            this.w = w;
            this.h = h;
            this.shade = shade;
        }
    }

    public class LayoutPage {
        public Gee.ArrayList<PageItem> items = new Gee.ArrayList<PageItem> ();
        public double width;
        public double height;
        public double font_scale = 1.0;

        public Gee.ArrayList<string> texts (TextRole? role = null) {
            var list = new Gee.ArrayList<string> ();
            foreach (var i in items) {
                if (i.kind == ItemKind.TEXT && (role == null || i.role == role)) list.add (i.text);
            }
            return list;
        }
    }

    public delegate double MeasureFunc (string text, TextRole role, double width, double scale);

    public delegate DbValue? ParamSupplier (string name);

    public class Accumulator {
        public double sum;
        public int count;
        public int numeric;
        public double min = double.INFINITY;
        public double max = -double.INFINITY;
        public string min_text = "";
        public string max_text = "";
        public bool text_mode;

        public void add (DbValue v) {
            if (v.is_null) return;
            count++;
            if (v.is_number ()) {
                double d = v.as_double ();
                numeric++;
                sum += d;
                min = double.min (min, d);
                max = double.max (max, d);
            } else {
                text_mode = true;
                string s = v.to_string ();
                if (min_text == "" || s.collate (min_text) < 0) min_text = s;
                if (max_text == "" || s.collate (max_text) > 0) max_text = s;
            }
        }

        public DbValue result (ReportTotal t) {
            switch (t) {
                case ReportTotal.SUM: return new DbValue.real (sum);
                case ReportTotal.AVG: return numeric > 0 ? new DbValue.real (sum / numeric) : new DbValue.null ();
                case ReportTotal.COUNT: return new DbValue.int (count);
                case ReportTotal.MIN:
                    if (numeric > 0) return new DbValue.real (min);
                    return min_text != "" ? new DbValue.text (min_text) : new DbValue.null ();
                case ReportTotal.MAX:
                    if (numeric > 0) return new DbValue.real (max);
                    return max_text != "" ? new DbValue.text (max_text) : new DbValue.null ();
                default: return new DbValue.null ();
            }
        }
    }

    public class ReportEngine {
        public const double ROW_PAD = 4;

        private ReportDef def;
        private RecordSource data;
        private unowned MeasureFunc measure;
        private Gee.ArrayList<LayoutPage> pages = new Gee.ArrayList<LayoutPage> ();
        private LayoutPage page;
        private double pw;
        private double ph;
        private double left;
        private double top;
        private double right;
        private double bottom;
        private double y;
        private double[] col_x = {};
        private double[] col_w = {};
        private Field?[] col_field = {};
        private Field?[] group_field = {};
        private Accumulator[,] acc;
        private int[] group_counts;
        private int total_count;
        private DbValue?[] group_keys;
        private string date_text;
        private double scale;
        private int label_index;
        private double label_row_top;
        private double label_row_h;

        public ReportEngine (ReportDef def, RecordSource data, MeasureFunc measure) {
            this.def = def;
            this.data = data;
            this.measure = measure;
            this.scale = def.font_scale;
            date_text = Codec.display_date (new DateTime.now_local ().format ("%Y-%m-%d"));
        }

        public void set_date_text (string text) {
            date_text = text;
        }

        public static RecordSource open_source (Database db, ReportDef def) throws Error {
            var st = def.state.copy ();
            st.sorts.clear ();
            st.group_by = "";
            foreach (var g in def.groups) st.sorts.add (new SortSpec (g.field, g.descending));
            foreach (var s in def.state.sorts) st.sorts.add (new SortSpec (s.column, s.descending));
            if (def.open_where.strip () != "") st.extra_where = st.extra_where.strip () != "" ? "(%s) And (%s)".printf (st.extra_where, def.open_where) : def.open_where;
            string s0 = def.source.strip ();
            if (s0.down ().has_prefix ("select ")) {
                var rs = new RecordSource.for_sql (db, AccessSql.statement (s0));
                rs.state = st;
                rs.invalidate ();
                return rs;
            }
            if (!db.object_exists (s0)) {
                var saved = SavedQueries.load (db, s0);
                if (saved != null) {
                    var rs = new RecordSource.for_sql (db, QueryPrep.prepare (db, saved.sql, report_params (db, saved.sql)));
                    rs.state = st;
                    rs.invalidate ();
                    return rs;
                }
            }
            return new RecordSource (db, def.source, st);
        }

        public static ParamSupplier? param_supplier;

        private static Gee.ArrayList<QueryParam> report_params (Database db, string sql) {
            var ps = QueryPrep.find_parameters (db, sql);
            foreach (var p in ps) {
                if (param_supplier != null) {
                    var v = param_supplier (p.name);
                    if (v != null) p.value = v;
                }
            }
            return ps;
        }

        private string rich (Field? f, DbValue v) {
            if (f == null || !f.rich_text || v.kind != ValueKind.TEXT) return "";
            return RichText.to_markup (v.text_value);
        }

        private string fmt (Field? f, DbValue v) {
            if (f == null) return v.to_string ();
            return data.display (f, v);
        }

        private string fmt_total (Field? f, ReportTotal t, DbValue v) {
            if (v.is_null) return "";
            if (t == ReportTotal.COUNT) return Codec.format_number (v.as_double (), 0, true);
            if (f != null && (f.field_type.is_numeric () || f.field_type == FieldType.LOOKUP)) {
                var shown = f.field_type == FieldType.INTEGER && t == ReportTotal.AVG ? new Field (f.name, FieldType.NUMBER) : f;
                if (shown.field_type == FieldType.NUMBER && shown.decimals < 0 && t == ReportTotal.AVG) shown.decimals = 2;
                if (f.field_type == FieldType.LOOKUP || f.field_type == FieldType.AUTONUMBER) return Codec.format_number (v.as_double (), -1, true);
                return Codec.display (shown, v);
            }
            if (v.kind == ValueKind.TEXT && f != null) return fmt (f, v);
            return Codec.format_number (v.as_double (), -1, true);
        }

        private ReportAlign align_for (ReportColumn c, Field? f) {
            if (c.align != ReportAlign.AUTO) return c.align;
            if (f != null && (f.field_type.is_numeric () && f.field_type != FieldType.AUTONUMBER)) return ReportAlign.RIGHT;
            if (f != null && f.field_type == FieldType.BOOLEAN) return ReportAlign.CENTER;
            return ReportAlign.LEFT;
        }

        private double text_h (string text, TextRole role, double width) {
            return measure (text, role, width, scale);
        }

        private void new_page () {
            page = new LayoutPage ();
            page.width = pw;
            page.height = ph;
            page.font_scale = scale;
            pages.add (page);
            y = top;
            if (def.layout == ReportLayoutKind.TABULAR) column_headers ();
            label_index = 0;
        }

        private void ensure (double h) {
            if (y + h > bottom && y > top + 0.5) {
                new_page ();
            }
        }

        private void column_headers () {
            double h = 0;
            for (int i = 0; i < def.columns.size; i++) h = double.max (h, text_h (def.columns[i].label, TextRole.COLUMN_HEADER, col_w[i] - 6));
            h += ROW_PAD * 2;
            page.items.add (new PageItem.fill (left, y, right - left, h, 0.08));
            for (int i = 0; i < def.columns.size; i++) {
                page.items.add (new PageItem.label (col_x[i] + 3, y + ROW_PAD, col_w[i] - 6, h - ROW_PAD * 2, def.columns[i].label, TextRole.COLUMN_HEADER, align_for (def.columns[i], col_field[i])));
            }
            y += h;
            page.items.add (new PageItem.line (left, y, right - left, 0.5));
            y += 2;
        }

        public Gee.ArrayList<LayoutPage> run () {
            def.paper_size (out pw, out ph);
            double margin = def.margin_mm / 25.4 * 72;
            left = margin;
            top = margin;
            right = pw - margin;
            bottom = ph - margin - 24;
            double total_w = 0;
            foreach (var c in def.columns) total_w += double.max (0.1, c.width);
            double x = left;
            col_x = new double[def.columns.size];
            col_w = new double[def.columns.size];
            col_field = new Field?[def.columns.size];
            for (int i = 0; i < def.columns.size; i++) {
                col_x[i] = x;
                col_w[i] = (right - left) * double.max (0.1, def.columns[i].width) / total_w;
                x += col_w[i];
                col_field[i] = data.def.find (def.columns[i].field);
            }
            int ng = def.groups.size;
            group_field = new Field?[ng];
            for (int g = 0; g < ng; g++) group_field[g] = data.def.find (def.groups[g].field);
            acc = new Accumulator[ng + 1, def.columns.size];
            for (int g = 0; g <= ng; g++) {
                for (int i = 0; i < def.columns.size; i++) acc[g, i] = new Accumulator ();
            }
            group_counts = new int[ng + 1];
            group_keys = new DbValue?[ng];

            page = new LayoutPage ();
            page.width = pw;
            page.height = ph;
            page.font_scale = scale;
            pages.add (page);
            y = top;
            if (def.title != "") {
                double th = text_h (def.title, TextRole.TITLE, right - left);
                page.items.add (new PageItem.label (left, y, right - left, th, def.title, TextRole.TITLE, ReportAlign.LEFT));
                y += th + 2;
            }
            if (def.subtitle != "") {
                double sh = text_h (def.subtitle, TextRole.SUBTITLE, right - left);
                page.items.add (new PageItem.label (left, y, right - left, sh, def.subtitle, TextRole.SUBTITLE, ReportAlign.LEFT));
                y += sh;
            }
            if (def.title != "" || def.subtitle != "") {
                y += 6;
                page.items.add (new PageItem.line (left, y, right - left, 0.8));
                y += 10;
            }
            if (def.layout == ReportLayoutKind.TABULAR) column_headers ();

            int64 n = data.count ();
            for (int64 r = 0; r < n; r++) {
                var row = data.row (r);
                if (row == null) break;
                int changed = ng;
                for (int g = 0; g < ng; g++) {
                    var f = group_field[g];
                    int idx = f != null ? data.def.index_of (f.name) : -1;
                    var key = idx >= 0 ? row.get (idx) : new DbValue.null ();
                    if (group_keys[g] == null || !same_key (group_keys[g], key, f)) {
                        changed = g;
                        break;
                    }
                }
                if (r == 0) changed = 0;
                if (changed < ng) {
                    if (r > 0) {
                        for (int g = ng - 1; g >= changed; g--) close_group (g);
                    }
                    for (int g = changed; g < ng; g++) {
                        var f = group_field[g];
                        int idx = f != null ? data.def.index_of (f.name) : -1;
                        group_keys[g] = idx >= 0 ? row.get (idx) : new DbValue.null ();
                        open_group (g, r == 0);
                    }
                }
                emit_row (row);
                total_count++;
                for (int g = 0; g <= ng; g++) group_counts[g]++;
                for (int i = 0; i < def.columns.size; i++) {
                    int idx = col_field[i] != null ? data.def.index_of (col_field[i].name) : -1;
                    if (idx < 0) continue;
                    var v = row.get (idx);
                    for (int g = 0; g <= ng; g++) acc[g, i].add (v);
                }
            }
            if (n > 0) {
                for (int g = ng - 1; g >= 0; g--) close_group (g);
            }
            finish_labels ();
            if (def.grand_total || def.show_count) grand_totals ();
            if (n == 0) {
                double h = text_h (_("No records to show."), TextRole.BODY, right - left);
                page.items.add (new PageItem.label (left, y + 8, right - left, h, _("No records to show."), TextRole.BODY, ReportAlign.LEFT));
            }
            page_footers ();
            return pages;
        }

        private static bool same_key (DbValue a, DbValue b, Field? f) {
            if (a.is_null || b.is_null) return a.is_null && b.is_null;
            if (f != null && f.field_type.is_text ()) return a.to_string ().casefold () == b.to_string ().casefold ();
            return a.equals (b);
        }

        private void open_group (int g, bool first) {
            var gd = def.groups[g];
            finish_labels ();
            if (gd.page_break && !first && y > top + 40) new_page ();
            for (int k = g; k < def.groups.size; k++) group_counts[k] = 0;
            for (int i = 0; i < def.columns.size; i++) {
                for (int k = g; k < def.groups.size; k++) acc[k, i] = new Accumulator ();
            }
            if (!gd.header) return;
            var f = group_field[g];
            string label = group_keys[g].is_null ? _("(Empty)") : fmt (f, group_keys[g]);
            string text = "%s: %s".printf (f != null ? f.name : gd.field, label);
            double indent = g * 12;
            double h = text_h (text, TextRole.GROUP_HEADER, right - left - indent) + ROW_PAD * 2 + 4;
            ensure (h + 24);
            y += 4;
            page.items.add (new PageItem.label (left + indent, y + ROW_PAD, right - left - indent, h - ROW_PAD * 2 - 4, text, TextRole.GROUP_HEADER, ReportAlign.LEFT));
            y += h - 4;
            page.items.add (new PageItem.line (left + indent, y, right - left - indent, 0.25));
            y += 2;
        }

        private void close_group (int g) {
            finish_labels ();
            var gd = def.groups[g];
            if (!gd.footer) return;
            bool any_total = false;
            foreach (var c in def.columns) {
                if (c.total != ReportTotal.NONE) any_total = true;
            }
            var f = group_field[g];
            string label = group_keys[g] == null || group_keys[g].is_null ? _("(Empty)") : fmt (f, group_keys[g]);
            string caption = def.show_count ? _("Total for %s (%d)").printf (label, group_counts[g]) : _("Total for %s").printf (label);
            totals_row (caption, g, TextRole.SUBTOTAL, any_total);
        }

        private void totals_row (string caption, int level, TextRole role, bool with_values) {
            if (def.layout != ReportLayoutKind.TABULAR || def.columns.size == 0) {
                double h = text_h (caption, role, right - left) + ROW_PAD * 2;
                ensure (h);
                page.items.add (new PageItem.label (left, y + ROW_PAD, right - left, h - ROW_PAD * 2, caption, role, ReportAlign.LEFT));
                string[] parts = {};
                if (with_values) {
                    for (int i = 0; i < def.columns.size; i++) {
                        var c = def.columns[i];
                        if (c.total == ReportTotal.NONE) continue;
                        parts += "%s %s: %s".printf (c.total.label (), c.label, fmt_total (col_field[i], c.total, acc[level, i].result (c.total)));
                    }
                }
                y += h;
                if (parts.length > 0) {
                    string t = string.joinv ("    ", parts);
                    double h2 = text_h (t, role, right - left) + ROW_PAD;
                    ensure (h2);
                    page.items.add (new PageItem.label (left, y, right - left, h2 - ROW_PAD, t, role, ReportAlign.LEFT));
                    y += h2;
                }
                y += 4;
                return;
            }
            double h = 0;
            string[] texts = new string[def.columns.size];
            int first_total = def.columns.size;
            for (int i = 0; i < def.columns.size; i++) {
                var c = def.columns[i];
                texts[i] = with_values && c.total != ReportTotal.NONE ? fmt_total (col_field[i], c.total, acc[level, i].result (c.total)) : "";
                if (texts[i] != "" && i < first_total) first_total = i;
                h = double.max (h, text_h (texts[i], role, col_w[i] - 6));
            }
            double cap_w = first_total > 0 ? col_x[int.min (first_total, def.columns.size - 1)] - left - 6 : right - left;
            if (first_total == def.columns.size) cap_w = right - left - 6;
            if (first_total == 0) cap_w = right - left - 6;
            double cap_h = text_h (caption, role, cap_w);
            h = double.max (h, cap_h) + ROW_PAD * 2;
            bool caption_own_line = first_total == 0;
            ensure (h * (caption_own_line ? 2 : 1));
            page.items.add (new PageItem.line (left, y, right - left, 0.35));
            page.items.add (new PageItem.fill (left, y, right - left, h * (caption_own_line ? 2 : 1), role == TextRole.GRAND_TOTAL ? 0.1 : 0.05));
            page.items.add (new PageItem.label (left + 3, y + ROW_PAD, cap_w, cap_h, caption, role, ReportAlign.LEFT));
            if (caption_own_line) y += h;
            for (int i = 0; i < def.columns.size; i++) {
                if (texts[i] == "") continue;
                page.items.add (new PageItem.label (col_x[i] + 3, y + ROW_PAD, col_w[i] - 6, h - ROW_PAD * 2, texts[i], role, align_for (def.columns[i], col_field[i])));
            }
            y += h + 6;
        }

        private void grand_totals () {
            bool any_total = false;
            foreach (var c in def.columns) {
                if (c.total != ReportTotal.NONE) any_total = true;
            }
            if (!def.grand_total) any_total = false;
            if (!any_total && !def.show_count) return;
            string caption = def.show_count ? ngettext ("Grand Total (%d record)", "Grand Total (%d records)", total_count).printf (total_count) : _("Grand Total");
            if (!any_total) caption = ngettext ("%d record", "%d records", total_count).printf (total_count);
            y += 4;
            totals_row (caption, def.groups.size, TextRole.GRAND_TOTAL, any_total);
        }

        private void emit_row (Row row) {
            switch (def.layout) {
                case ReportLayoutKind.STACKED:
                    emit_stacked (row);
                    return;
                case ReportLayoutKind.LABELS:
                    emit_label (row);
                    return;
                default:
                    break;
            }
            double h = 0;
            string[] texts = new string[def.columns.size];
            string[] marks = new string[def.columns.size];
            for (int i = 0; i < def.columns.size; i++) {
                int idx = col_field[i] != null ? data.def.index_of (col_field[i].name) : -1;
                texts[i] = idx >= 0 ? fmt (col_field[i], row.get (idx)) : "";
                marks[i] = idx >= 0 ? rich (col_field[i], row.get (idx)) : "";
                h = double.max (h, text_h (texts[i], TextRole.BODY, col_w[i] - 6));
            }
            h += ROW_PAD * 2;
            ensure (h);
            for (int i = 0; i < def.columns.size; i++) {
                if (texts[i] == "") continue;
                var it = new PageItem.label (col_x[i] + 3, y + ROW_PAD, col_w[i] - 6, h - ROW_PAD * 2, texts[i], TextRole.BODY, align_for (def.columns[i], col_field[i]));
                it.markup = marks[i];
                page.items.add (it);
            }
            y += h;
            page.items.add (new PageItem.line (left, y, right - left, 0.1));
        }

        private void emit_stacked (Row row) {
            double label_w = double.min (160, (right - left) * 0.3);
            double value_w = right - left - label_w - 12;
            double total = 0;
            double[] hs = new double[def.columns.size];
            string[] texts = new string[def.columns.size];
            string[] marks = new string[def.columns.size];
            for (int i = 0; i < def.columns.size; i++) {
                int idx = col_field[i] != null ? data.def.index_of (col_field[i].name) : -1;
                texts[i] = idx >= 0 ? fmt (col_field[i], row.get (idx)) : "";
                marks[i] = idx >= 0 ? rich (col_field[i], row.get (idx)) : "";
                hs[i] = double.max (text_h (def.columns[i].label, TextRole.FIELD_LABEL, label_w), text_h (texts[i], TextRole.BODY, value_w)) + 3;
                total += hs[i];
            }
            ensure (double.min (total + 12, bottom - top));
            for (int i = 0; i < def.columns.size; i++) {
                if (y + hs[i] > bottom) new_page ();
                page.items.add (new PageItem.label (left, y, label_w, hs[i] - 3, def.columns[i].label, TextRole.FIELD_LABEL, ReportAlign.LEFT));
                var vi = new PageItem.label (left + label_w + 12, y, value_w, hs[i] - 3, texts[i], TextRole.BODY, ReportAlign.LEFT);
                vi.markup = marks[i];
                page.items.add (vi);
                y += hs[i];
            }
            y += 6;
            page.items.add (new PageItem.line (left, y, right - left, 0.25));
            y += 8;
        }

        private void emit_label (Row row) {
            int per_row = int.max (1, def.label_columns);
            double gap = 10;
            double w = (right - left - gap * (per_row - 1)) / per_row;
            string[] lines = {};
            for (int i = 0; i < def.columns.size; i++) {
                int idx = col_field[i] != null ? data.def.index_of (col_field[i].name) : -1;
                string t = idx >= 0 ? fmt (col_field[i], row.get (idx)) : "";
                if (t != "") lines += t;
            }
            double h = 12;
            double[] hs = new double[lines.length];
            for (int i = 0; i < lines.length; i++) {
                hs[i] = text_h (lines[i], i == 0 ? TextRole.SUBTOTAL : TextRole.BODY, w - 16) + 2;
                h += hs[i];
            }
            h = double.max (h, 64);
            int col = label_index % per_row;
            if (col == 0) {
                if (label_index > 0) y = label_row_top + label_row_h + gap;
                if (y + h > bottom && y > top + 0.5) new_page ();
                label_row_top = y;
                label_row_h = 0;
            }
            label_row_h = double.max (label_row_h, h);
            double x = left + col * (w + gap);
            double ly = label_row_top + 8;
            page.items.add (new PageItem.fill (x, label_row_top, w, h, 0.04));
            for (int i = 0; i < lines.length; i++) {
                page.items.add (new PageItem.label (x + 8, ly, w - 16, hs[i] - 2, lines[i], i == 0 ? TextRole.SUBTOTAL : TextRole.BODY, ReportAlign.LEFT));
                ly += hs[i];
            }
            label_index++;
        }

        private void finish_labels () {
            if (def.layout != ReportLayoutKind.LABELS || label_index == 0) return;
            y = label_row_top + label_row_h + 12;
            label_index = 0;
        }

        private void page_footers () {
            int total = pages.size;
            for (int i = 0; i < total; i++) {
                var p = pages[i];
                double fy = ph - def.margin_mm / 25.4 * 72 - 12;
                p.items.add (new PageItem.line (left, fy - 6, right - left, 0.2));
                if (def.show_date) p.items.add (new PageItem.label (left, fy, (right - left) / 2, 12, date_text, TextRole.FOOTER, ReportAlign.LEFT));
                if (def.page_numbers) p.items.add (new PageItem.label (left + (right - left) / 2, fy, (right - left) / 2, 12, _("Page %d of %d").printf (i + 1, total), TextRole.FOOTER, ReportAlign.RIGHT));
            }
        }
    }

    public class ReportRenderer {
        private Pango.Context? pctx;
        private Cairo.ImageSurface? probe;

        public ReportRenderer () {
            probe = new Cairo.ImageSurface (Cairo.Format.ARGB32, 4, 4);
            var cr = new Cairo.Context (probe);
            pctx = Pango.cairo_create_context (cr);
            Pango.cairo_context_set_resolution (pctx, 72);
            var opts = new Cairo.FontOptions ();
            opts.set_hint_metrics (Cairo.HintMetrics.OFF);
            Pango.cairo_context_set_font_options (pctx, opts);
        }

        private static void rgba_hex (Cairo.Context cr, string hex, double r, double g, double b) {
            if (hex.length == 7 && hex[0] == '#') {
                int64 v = 0;
                if (int64.try_parse (hex.substring (1), out v, null, 16)) {
                    cr.set_source_rgb (((v >> 16) & 255) / 255.0, ((v >> 8) & 255) / 255.0, (v & 255) / 255.0);
                    return;
                }
            }
            cr.set_source_rgb (r, g, b);
        }

        public static Cairo.ImageSurface surface_from_pixbuf (Gdk.Pixbuf pb) {
            var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, pb.width, pb.height);
            surf.flush ();
            unowned uint8[] src = pb.get_pixels_with_length ();
            uint8* dst = surf.get_data ();
            int ds = surf.get_stride ();
            int ss = pb.rowstride;
            int nc = pb.n_channels;
            for (int y = 0; y < pb.height; y++) {
                for (int x = 0; x < pb.width; x++) {
                    int si = y * ss + x * nc;
                    uint8 r = src[si], g = src[si + 1], b = src[si + 2];
                    uint8 a = nc == 4 ? src[si + 3] : 255;
                    int di = y * ds + x * 4;
                    dst[di] = (uint8) (b * a / 255);
                    dst[di + 1] = (uint8) (g * a / 255);
                    dst[di + 2] = (uint8) (r * a / 255);
                    dst[di + 3] = a;
                }
            }
            surf.mark_dirty ();
            return surf;
        }

        public static Pango.FontDescription font_custom (PageItem it, double scale) {
            var fd = Pango.FontDescription.from_string ("Sans");
            fd.set_absolute_size ((it.font_size > 0 ? it.font_size : 9) * scale * Pango.SCALE);
            if (it.bold) fd.set_weight (Pango.Weight.BOLD);
            if (it.italic) fd.set_style (Pango.Style.ITALIC);
            return fd;
        }

        public double measure_custom (PageItem it, double width) {
            var layout = new Pango.Layout (pctx);
            layout.set_font_description (font_custom (it, 1.0));
            layout.set_width ((int) (double.max (1, width) * Pango.SCALE));
            layout.set_wrap (Pango.WrapMode.WORD_CHAR);
            if (it.markup != "") layout.set_markup (it.markup, -1);
            else layout.set_text (it.text == "" ? " " : it.text, -1);
            int w, h;
            layout.get_pixel_size (out w, out h);
            return h;
        }

        public static Pango.FontDescription font_for (TextRole role, double scale) {
            var fd = Pango.FontDescription.from_string ("Sans");
            fd.set_absolute_size (role.size () * scale * Pango.SCALE);
            if (role.bold ()) fd.set_weight (Pango.Weight.BOLD);
            return fd;
        }

        public double measure (string text, TextRole role, double width, double scale) {
            var layout = new Pango.Layout (pctx);
            layout.set_font_description (font_for (role, scale));
            layout.set_width ((int) (double.max (1, width) * Pango.SCALE));
            layout.set_wrap (Pango.WrapMode.WORD_CHAR);
            layout.set_text (text == "" ? " " : text, -1);
            int w, h;
            layout.get_pixel_size (out w, out h);
            return h;
        }

        public static ScriptRuntime? runtime;
        public string? fixed_date;

        public Gee.ArrayList<LayoutPage> layout (ReportDef def, RecordSource data) {
            if (def.designed) {
                var banded = new BandedEngine (def, data.db, runtime, this);
                return banded.run (data);
            }
            var engine = new ReportEngine (def, data, measure);
            if (fixed_date != null) engine.set_date_text (fixed_date);
            return engine.run ();
        }

        public static void draw_page (Cairo.Context cr, LayoutPage page, double scale) {
            cr.save ();
            cr.scale (scale, scale);
            cr.set_source_rgb (1, 1, 1);
            cr.rectangle (0, 0, page.width, page.height);
            cr.fill ();
            foreach (var it in page.items) {
                switch (it.kind) {
                    case ItemKind.FILL:
                        cr.set_source_rgba (0.16, 0.3, 0.55, it.shade);
                        cr.rectangle (it.x, it.y, it.w, it.h);
                        cr.fill ();
                        break;
                    case ItemKind.LINE:
                        cr.set_source_rgba (0.1, 0.12, 0.16, it.shade);
                        cr.set_line_width (0.6);
                        cr.move_to (it.x, Math.round (it.y) + 0.3);
                        cr.line_to (it.x + it.w, Math.round (it.y) + 0.3);
                        cr.stroke ();
                        break;
                    case ItemKind.RECT:
                        if (it.fill_color != "") {
                            rgba_hex (cr, it.fill_color, 1, 1, 1);
                            cr.rectangle (it.x, it.y, it.w, it.h);
                            cr.fill ();
                        }
                        if (it.shade > 0) {
                            rgba_hex (cr, it.color, 0.1, 0.12, 0.16);
                            cr.set_line_width (0.7);
                            cr.rectangle (it.x, it.y, it.w, it.h);
                            cr.stroke ();
                        }
                        break;
                    case ItemKind.IMAGE:
                        if (it.image == null) break;
                        try {
                            var loader = new Gdk.PixbufLoader ();
                            loader.write (it.image.get_data ());
                            loader.close ();
                            var pb = loader.get_pixbuf ();
                            if (pb == null) break;
                            double sx = it.w / pb.width, sy = it.h / pb.height;
                            double sc = double.min (sx, sy);
                            cr.save ();
                            cr.translate (it.x + (it.w - pb.width * sc) / 2, it.y + (it.h - pb.height * sc) / 2);
                            cr.scale (sc, sc);
                            cr.set_source_surface (surface_from_pixbuf (pb), 0, 0);
                            cr.paint ();
                            cr.restore ();
                        } catch (Error e) {
                        }
                        break;
                    case ItemKind.CHART:
                        if (it.chart != null) it.chart.draw (cr, it.x, it.y, it.w, it.h, it.chart_type, true);
                        break;
                    case ItemKind.CHECK:
                        cr.set_source_rgb (0.1, 0.12, 0.16);
                        cr.set_line_width (0.8);
                        double cs = double.min (it.h, 10);
                        cr.rectangle (it.x, it.y, cs, cs);
                        cr.stroke ();
                        if (it.checked_state) {
                            cr.move_to (it.x + 2, it.y + cs / 2);
                            cr.line_to (it.x + cs / 2.5, it.y + cs - 2);
                            cr.line_to (it.x + cs - 1.5, it.y + 1.5);
                            cr.stroke ();
                        }
                        break;
                    case ItemKind.TEXT:
                        if (it.custom) {
                            if (it.fill_color != "") {
                                rgba_hex (cr, it.fill_color, 1, 1, 1);
                                cr.rectangle (it.x, it.y, it.w, it.h);
                                cr.fill ();
                            }
                            var cl = Pango.cairo_create_layout (cr);
                            var copts = new Cairo.FontOptions ();
                            copts.set_hint_metrics (Cairo.HintMetrics.OFF);
                            copts.set_hint_style (Cairo.HintStyle.NONE);
                            Pango.cairo_context_set_font_options (cl.get_context (), copts);
                            Pango.cairo_context_set_resolution (cl.get_context (), 72);
                            cl.context_changed ();
                            cl.set_font_description (font_custom (it, 1.0));
                            cl.set_width ((int) (double.max (1, it.w) * Pango.SCALE));
                            cl.set_wrap (Pango.WrapMode.WORD_CHAR);
                            switch (it.align) {
                                case ReportAlign.RIGHT: cl.set_alignment (Pango.Alignment.RIGHT); break;
                                case ReportAlign.CENTER: cl.set_alignment (Pango.Alignment.CENTER); break;
                                default: cl.set_alignment (Pango.Alignment.LEFT); break;
                            }
                            if (it.markup != "") cl.set_markup (it.markup, -1);
                            else cl.set_text (it.text, -1);
                            rgba_hex (cr, it.color, 0.08, 0.09, 0.11);
                            cr.move_to (it.x, it.y);
                            Pango.cairo_show_layout (cr, cl);
                            break;
                        }
                        var layout = Pango.cairo_create_layout (cr);
                        var opts = new Cairo.FontOptions ();
                        opts.set_hint_metrics (Cairo.HintMetrics.OFF);
                        opts.set_hint_style (Cairo.HintStyle.NONE);
                        opts.set_antialias (Cairo.Antialias.GRAY);
                        Pango.cairo_context_set_font_options (layout.get_context (), opts);
                        Pango.cairo_context_set_resolution (layout.get_context (), 72);
                        layout.context_changed ();
                        layout.set_font_description (font_for (it.role, page.font_scale));
                        layout.set_width ((int) (double.max (1, it.w) * Pango.SCALE));
                        layout.set_wrap (Pango.WrapMode.WORD_CHAR);
                        switch (it.align) {
                            case ReportAlign.RIGHT: layout.set_alignment (Pango.Alignment.RIGHT); break;
                            case ReportAlign.CENTER: layout.set_alignment (Pango.Alignment.CENTER); break;
                            default: layout.set_alignment (Pango.Alignment.LEFT); break;
                        }
                        if (it.markup != "") layout.set_markup (it.markup, -1);
                        else layout.set_text (it.text, -1);
                        if (it.role == TextRole.SUBTITLE || it.role == TextRole.FOOTER || it.role == TextRole.FIELD_LABEL) cr.set_source_rgb (0.38, 0.4, 0.45);
                        else if (it.role == TextRole.TITLE || it.role == TextRole.GROUP_HEADER) cr.set_source_rgb (0.1, 0.22, 0.42);
                        else cr.set_source_rgb (0.08, 0.09, 0.11);
                        cr.move_to (it.x, it.y);
                        Pango.cairo_show_layout (cr, layout);
                        break;
                }
            }
            cr.restore ();
        }

        public static void export_pdf (Gee.ArrayList<LayoutPage> pages, string path, string title = "") throws Error {
            if (pages.size == 0) throw new SchemaError.INVALID (_("The report has no pages."));
            var surface = new Cairo.PdfSurface (path, pages[0].width, pages[0].height);
            surface.restrict_to_version (Cairo.PdfVersion.VERSION_1_4);
            if (title != "") surface.set_metadata (Cairo.PdfMetadata.TITLE, title);
            surface.set_metadata (Cairo.PdfMetadata.CREATOR, "Singularity Database");
            var cr = new Cairo.Context (surface);
            foreach (var p in pages) {
                surface.set_size (p.width, p.height);
                draw_page (cr, p, 1.0);
                cr.show_page ();
            }
            surface.finish ();
            if (surface.status () != Cairo.Status.SUCCESS) throw new IOError.FAILED (_("The PDF could not be written."));
        }
    }
}
