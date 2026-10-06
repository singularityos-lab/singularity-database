namespace Singularity.Apps.Database {

    public class ChartSeries {
        public string name;
        public double[] values;
    }

    public class ChartData {
        public string[] categories = {};
        public Gee.ArrayList<ChartSeries> series = new Gee.ArrayList<ChartSeries> ();
        public string title = "";

        public static ChartData load (Database db, string source, string category, string value, string aggregate, string series_field, string extra_where = "") {
            var d = new ChartData ();
            string src = source.strip ();
            if (src == "" || category == "") return d;
            try {
                string from = src.down ().has_prefix ("select ") ? "(%s)".printf (AccessSql.statement (src)) : Sql.quote_ident (src);
                string agg = aggregate.down ();
                string val = value == "" || value == "*" ? "*" : Sql.quote_ident (value);
                string expr;
                switch (agg) {
                    case "count": expr = val == "*" ? "count(*)" : "count(%s)".printf (val); break;
                    case "avg": expr = "avg(%s)".printf (val); break;
                    case "min": expr = "min(%s)".printf (val); break;
                    case "max": expr = "max(%s)".printf (val); break;
                    default: expr = val == "*" ? "count(*)" : "total(%s)".printf (val); break;
                }
                string where = extra_where != "" ? " WHERE " + extra_where : "";
                if (series_field != "") {
                    var rs = db.query ("SELECT %s, %s, %s FROM %s%s GROUP BY 1, 2 ORDER BY 1, 2".printf (Sql.quote_ident (category), Sql.quote_ident (series_field), expr, from, where), null, 20000);
                    var cats = new Gee.ArrayList<string> ();
                    var ser = new Gee.ArrayList<string> ();
                    var map = new Gee.HashMap<string, double?> ();
                    foreach (var r in rs.rows) {
                        string c = r.get (0).to_string ();
                        string s = r.get (1).to_string ();
                        if (!cats.contains (c)) cats.add (c);
                        if (!ser.contains (s)) ser.add (s);
                        map[c + "\x01" + s] = r.get (2).as_double ();
                    }
                    d.categories = cats.to_array ();
                    foreach (string s in ser) {
                        var cs = new ChartSeries ();
                        cs.name = s;
                        double[] vals = new double[cats.size];
                        for (int i = 0; i < cats.size; i++) {
                            var v = map[cats[i] + "\x01" + s];
                            vals[i] = v != null ? v : 0;
                        }
                        cs.values = vals;
                        d.series.add (cs);
                    }
                } else {
                    var rs = db.query ("SELECT %s, %s FROM %s%s GROUP BY 1 ORDER BY 1".printf (Sql.quote_ident (category), expr, from, where), null, 5000);
                    var cs = new ChartSeries ();
                    cs.name = value != "" ? value : _("Count");
                    string[] cats = {};
                    double[] vals = {};
                    foreach (var r in rs.rows) {
                        cats += r.get (0).to_string ();
                        vals += r.get (1).as_double ();
                    }
                    d.categories = cats;
                    cs.values = vals;
                    d.series.add (cs);
                }
            } catch (Error e) {
                d.title = e.message;
            }
            return d;
        }

        private static double[,] palette () {
            return { { 0.21, 0.52, 0.89 }, { 0.90, 0.38, 0.0 }, { 0.18, 0.62, 0.36 }, { 0.75, 0.11, 0.16 }, { 0.57, 0.25, 0.67 }, { 0.93, 0.70, 0.0 }, { 0.0, 0.6, 0.65 }, { 0.47, 0.47, 0.47 } };
        }

        public void draw (Cairo.Context cr, double x0, double y0, double w, double h, string type, bool print) {
            var pal = palette ();
            cr.save ();
            cr.rectangle (x0, y0, w, h);
            cr.clip ();
            var layout = Pango.cairo_create_layout (cr);
            layout.set_font_description (Pango.FontDescription.from_string ("Sans 8"));
            double fr = print ? 0.2 : 0.35;
            if (categories.length == 0 || series.size == 0) {
                cr.set_source_rgba (fr, fr, fr, 1);
                layout.set_text (title != "" ? title : _("No data"), -1);
                cr.move_to (x0 + 8, y0 + 8);
                Pango.cairo_show_layout (cr, layout);
                cr.restore ();
                return;
            }
            double legend_h = series.size > 1 || type == "pie" ? 18 : 0;
            if (type == "pie") {
                double total = 0;
                foreach (double v in series[0].values) total += double.max (0, v);
                double cx = x0 + w / 2, cy = y0 + (h - legend_h) / 2, rad = double.min (w, h - legend_h) / 2 - 8;
                double a = -Math.PI / 2;
                for (int i = 0; i < categories.length; i++) {
                    double frac = total > 0 ? double.max (0, series[0].values[i]) / total : 0;
                    cr.set_source_rgb (pal[i % 8, 0], pal[i % 8, 1], pal[i % 8, 2]);
                    cr.move_to (cx, cy);
                    cr.arc (cx, cy, rad, a, a + frac * 2 * Math.PI);
                    cr.close_path ();
                    cr.fill ();
                    a += frac * 2 * Math.PI;
                }
                double lx = x0 + 4;
                for (int i = 0; i < categories.length && lx < x0 + w - 20; i++) {
                    cr.set_source_rgb (pal[i % 8, 0], pal[i % 8, 1], pal[i % 8, 2]);
                    cr.rectangle (lx, y0 + h - 12, 8, 8);
                    cr.fill ();
                    cr.set_source_rgb (fr, fr, fr);
                    layout.set_text (categories[i], -1);
                    int tw, th;
                    layout.get_pixel_size (out tw, out th);
                    cr.move_to (lx + 11, y0 + h - 14);
                    Pango.cairo_show_layout (cr, layout);
                    lx += tw + 22;
                }
                cr.restore ();
                return;
            }
            double maxv = 0, minv = 0;
            foreach (var s in series) {
                foreach (double v in s.values) {
                    maxv = double.max (maxv, v);
                    minv = double.min (minv, v);
                }
            }
            if (maxv == minv) maxv = minv + 1;
            double left = x0 + 40, right = x0 + w - 8, top = y0 + 8, bottom = y0 + h - 24 - legend_h;
            cr.set_line_width (0.5);
            for (int g = 0; g <= 4; g++) {
                double v = minv + (maxv - minv) * g / 4.0;
                double y = bottom - (bottom - top) * g / 4.0;
                cr.set_source_rgba (fr, fr, fr, 0.25);
                cr.move_to (left, y);
                cr.line_to (right, y);
                cr.stroke ();
                cr.set_source_rgb (fr, fr, fr);
                layout.set_text (Codec.format_number (v, v == Math.floor (v) ? 0 : 1, true), -1);
                int tw, th;
                layout.get_pixel_size (out tw, out th);
                cr.move_to (left - tw - 4, y - th / 2.0);
                Pango.cairo_show_layout (cr, layout);
            }
            int n = categories.length;
            double slot = (right - left) / int.max (1, n);
            double zero_y = bottom - (bottom - top) * (0 - minv) / (maxv - minv);
            for (int s = 0; s < series.size; s++) {
                var ser = series[s];
                cr.set_source_rgb (pal[s % 8, 0], pal[s % 8, 1], pal[s % 8, 2]);
                if (type == "line" || type == "area") {
                    for (int i = 0; i < n; i++) {
                        double x = left + slot * (i + 0.5);
                        double y = bottom - (bottom - top) * (ser.values[i] - minv) / (maxv - minv);
                        if (i == 0) cr.move_to (x, y);
                        else cr.line_to (x, y);
                    }
                    if (type == "area") {
                        cr.line_to (left + slot * (n - 0.5), zero_y);
                        cr.line_to (left + slot * 0.5, zero_y);
                        cr.close_path ();
                        cr.set_source_rgba (pal[s % 8, 0], pal[s % 8, 1], pal[s % 8, 2], 0.45);
                        cr.fill ();
                    } else {
                        cr.set_line_width (2);
                        cr.stroke ();
                    }
                    continue;
                }
                double bw = slot * 0.7 / series.size;
                for (int i = 0; i < n; i++) {
                    double x = left + slot * i + slot * 0.15 + bw * s;
                    double y = bottom - (bottom - top) * (ser.values[i] - minv) / (maxv - minv);
                    if (type == "bar") {
                        double bh = (bottom - top) / int.max (1, n) * 0.7 / series.size;
                        double by = top + (bottom - top) / int.max (1, n) * i + bh * s + 2;
                        double len = (right - left) * (ser.values[i] - minv) / (maxv - minv);
                        cr.rectangle (left, by, len, bh);
                    } else {
                        cr.rectangle (x, double.min (y, zero_y), bw, Math.fabs (zero_y - y));
                    }
                    cr.fill ();
                }
            }
            cr.set_source_rgb (fr, fr, fr);
            int step = int.max (1, n / int.max (1, (int) ((right - left) / 60)));
            for (int i = 0; i < n; i += step) {
                layout.set_text (categories[i], -1);
                layout.set_width ((int) (slot * step * Pango.SCALE));
                layout.set_ellipsize (Pango.EllipsizeMode.END);
                layout.set_alignment (Pango.Alignment.CENTER);
                cr.move_to (left + slot * i, bottom + 4);
                Pango.cairo_show_layout (cr, layout);
            }
            layout.set_width (-1);
            if (series.size > 1) {
                double lx = left;
                for (int s = 0; s < series.size; s++) {
                    cr.set_source_rgb (pal[s % 8, 0], pal[s % 8, 1], pal[s % 8, 2]);
                    cr.rectangle (lx, y0 + h - 12, 8, 8);
                    cr.fill ();
                    cr.set_source_rgb (fr, fr, fr);
                    layout.set_text (series[s].name, -1);
                    int tw, th;
                    layout.get_pixel_size (out tw, out th);
                    cr.move_to (lx + 11, y0 + h - 14);
                    Pango.cairo_show_layout (cr, layout);
                    lx += tw + 22;
                }
            }
            cr.restore ();
        }
    }
}
