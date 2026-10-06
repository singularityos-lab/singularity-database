namespace Singularity.Apps.Database {

    public class RowScope : ScriptObject {
        private TableDef def;
        private Row row;

        public RowScope (RecordSource src, Row row) {
            this.def = src.def;
            this.row = row;
        }

        public RowScope.with_def (TableDef def, Row row) {
            this.def = def;
            this.row = row;
        }

        public override bool has_member (string name) {
            return def.find (name) != null;
        }

        public override SValue get_member (string name, SValue[] args) throws ScriptError {
            int i = def.index_of (name);
            if (i < 0) return base.get_member (name, args);
            return SValue.from_db (row.get (i), def.fields[i].field_type);
        }

        public override SValue bang (string name) throws ScriptError {
            return get_member (name, {});
        }
    }

    public class SpanAggregates : Object, AggregateProvider {
        private TableDef def;
        private Gee.List<Row> rows;
        public int start;
        public int end;

        public SpanAggregates (TableDef def, Gee.List<Row> rows, int start, int end) {
            this.def = def;
            this.rows = rows;
            this.start = start;
            this.end = end;
        }

        public bool aggregate (string function, SExpr? argument, ScriptRuntime rt, SFrame frame, out SValue result) throws ScriptError {
            result = new SValue.null ();
            string fn = function.down ();
            if (fn != "sum" && fn != "avg" && fn != "count" && fn != "min" && fn != "max" && fn != "stdev" && fn != "var" && fn != "first" && fn != "last") return false;
            if (argument == null) {
                if (fn != "count") return false;
                result = new SValue.int (end - start);
                return true;
            }
            bool star = argument is SName && ((SName) argument).name == "*";
            double sum = 0, mn = double.INFINITY, mx = -double.INFINITY, mean = 0, m2 = 0;
            int n = 0;
            SValue? first = null, last = null;
            for (int i = start; i < end && i < rows.size; i++) {
                if (star) {
                    n++;
                    continue;
                }
                var v = rt.eval_with (argument, new RowScope.with_def (def, rows[i]));
                if (first == null) first = v;
                last = v;
                if (v.is_null || v.is_empty) continue;
                if (fn == "count") {
                    n++;
                    continue;
                }
                if (fn == "min" || fn == "max") {
                    if (!v.looks_numeric () && v.kind != SKind.DATE) {
                        if (result.is_null || (fn == "min" ? ScriptRuntime.compare (v, result) < 0 : ScriptRuntime.compare (v, result) > 0)) result = v;
                        n++;
                        continue;
                    }
                }
                double d = v.to_double ();
                n++;
                sum += d;
                mn = double.min (mn, d);
                mx = double.max (mx, d);
                double delta = d - mean;
                mean += delta / n;
                m2 += delta * (d - mean);
            }
            switch (fn) {
                case "sum": result = new SValue.dbl (sum); break;
                case "avg": result = n > 0 ? new SValue.dbl (sum / n) : new SValue.null (); break;
                case "count": result = new SValue.int (n); break;
                case "min":
                    if (result.is_null) result = n > 0 ? new SValue.dbl (mn) : new SValue.null ();
                    break;
                case "max":
                    if (result.is_null) result = n > 0 ? new SValue.dbl (mx) : new SValue.null ();
                    break;
                case "stdev": result = n > 1 ? new SValue.dbl (Math.sqrt (m2 / (n - 1))) : new SValue.null (); break;
                case "var": result = n > 1 ? new SValue.dbl (m2 / (n - 1)) : new SValue.null (); break;
                case "first": result = first ?? new SValue.null (); break;
                default: result = last ?? new SValue.null (); break;
            }
            return true;
        }
    }

    public class ReportScope : ScriptObject {
        public BandedEngine engine;
        public Row? row;
        public Gee.HashMap<string, SValue> values = new Gee.HashMap<string, SValue> ();

        public ReportScope (BandedEngine engine) {
            this.engine = engine;
        }

        public override string type_name () {
            return "Report_" + engine.def.name;
        }

        public override bool has_member (string name) {
            string k = name.down ();
            if (k == "page" || k == "pages" || values.has_key (k)) return true;
            return engine.data_def.find (name) != null;
        }

        public override SValue get_member (string name, SValue[] args) throws ScriptError {
            string k = name.down ();
            if (k == "page") return new SValue.int (engine.page_number);
            if (k == "pages") return new SValue.int (engine.total_pages);
            if (k == "name") return new SValue.str (engine.def.name);
            if (k == "caption") return new SValue.str (engine.def.title);
            if (values.has_key (k)) return values[k];
            if (row != null) {
                int i = engine.data_def.index_of (name);
                if (i >= 0) return SValue.from_db (row.get (i), engine.data_def.fields[i].field_type);
            }
            return new SValue.null ();
        }

        public override SValue bang (string name) throws ScriptError {
            return get_member (name, {});
        }
    }

    public class BandedEngine {
        public ReportDef def;
        public Database db;
        public ScriptRuntime rt;
        public ReportRenderer renderer;
        public TableDef data_def;
        public int page_number;
        public int total_pages = 1;
        private Gee.ArrayList<Row> rows = new Gee.ArrayList<Row> ();
        private Gee.ArrayList<LayoutPage> pages = new Gee.ArrayList<LayoutPage> ();
        private LayoutPage page;
        private double pw;
        private double ph;
        private double left;
        private double top;
        private double bottom;
        private double y;
        private double footer_h;
        private ReportScope scope;
        private Gee.HashMap<string, double?> running = new Gee.HashMap<string, double?> ();
        private Gee.HashMap<string, string> last_shown = new Gee.HashMap<string, string> ();
        private int[,] spans;
        private int group_count;
        private bool page_has_content;
        private double x_offset;
        private int depth;
        private string date_text;

        public BandedEngine (ReportDef def, Database db, ScriptRuntime? runtime, ReportRenderer renderer) {
            this.def = def;
            this.db = db;
            this.rt = runtime ?? new ScriptRuntime (db);
            this.renderer = renderer;
            date_text = Codec.display_date (new DateTime.now_local ().format ("%Y-%m-%d"));
        }

        public void set_date_text (string text) {
            date_text = text;
        }

        public Gee.ArrayList<LayoutPage> run (RecordSource data) {
            data_def = data.def;
            rows.clear ();
            int64 n = data.count ();
            for (int64 i = 0; i < n; i++) {
                var r = data.row (i);
                if (r == null) break;
                rows.add (r);
            }
            scope = new ReportScope (this);
            if (rows.size == 0 && (def.events["NoData"] ?? "") != "") {
                bool cancel;
                try {
                    EventHandler.fire (rt, scope, "Report_" + def.name, "Report", "NoData", def.events["NoData"], {}, out cancel);
                    if (cancel) return new Gee.ArrayList<LayoutPage> ();
                } catch (Error e) {
                }
            }
            layout_all ();
            int first_pass = pages.size;
            if (first_pass != total_pages) {
                total_pages = first_pass;
                layout_all ();
            }
            return pages;
        }

        private void compute_spans () {
            group_count = def.groups.size;
            spans = new int[int.max (1, rows.size), int.max (1, group_count) * 2];
            for (int g = 0; g < group_count; g++) {
                int start = 0;
                for (int i = 0; i <= rows.size; i++) {
                    bool boundary = i == rows.size || (i > 0 && group_changed (i, g));
                    if (boundary) {
                        for (int k = start; k < i; k++) {
                            spans[k, g * 2] = start;
                            spans[k, g * 2 + 1] = i;
                        }
                        start = i;
                    }
                }
            }
        }

        private DbValue group_key (int row, int g) {
            var grp = def.groups[g];
            DbValue raw;
            if (grp.field.has_prefix ("=")) {
                try {
                    scope.row = rows[row];
                    raw = rt.evaluate (grp.field.substring (1), scope).to_db ();
                } catch (Error e) {
                    raw = new DbValue.null ();
                }
            } else {
                int idx = data_def.index_of (grp.field);
                raw = idx >= 0 ? rows[row].get (idx) : new DbValue.null ();
            }
            return grp.key_of (raw);
        }

        private bool group_changed (int row, int level) {
            for (int g = 0; g <= level; g++) {
                var a = group_key (row - 1, g);
                var b = group_key (row, g);
                if (a.is_null != b.is_null) return true;
                if (!a.is_null && a.to_string ().casefold () != b.to_string ().casefold ()) return true;
            }
            return false;
        }

        private void layout_all () {
            pages = new Gee.ArrayList<LayoutPage> ();
            running.clear ();
            last_shown.clear ();
            def.paper_size (out pw, out ph);
            double margin = def.margin_mm / 25.4 * 72;
            left = margin;
            top = margin;
            var pf = def.section ("page-footer");
            footer_h = pf != null && pf.visible ? pf.height : 0;
            bottom = ph - margin - footer_h;
            page_number = 0;
            compute_spans ();
            var rh = def.section ("report-header");
            bool has_rh = rh != null && rh.visible;
            skip_page_header = has_rh;
            start_page ();
            skip_page_header = false;
            if (has_rh) {
                emit_section (rh, -1, 0, rows.size);
                if (!rh.new_page_after) place_page_header ();
            }
            for (int i = 0; i < rows.size; i++) {
                int changed = group_count;
                if (i == 0) changed = 0;
                else {
                    for (int g = 0; g < group_count; g++) {
                        if (spans[i, g * 2] == i) {
                            changed = g;
                            break;
                        }
                    }
                }
                if (i > 0 && changed < group_count) {
                    for (int g = group_count - 1; g >= changed; g--) close_group (g, i - 1);
                }
                if (changed < group_count) {
                    for (int g = changed; g < group_count; g++) open_group (g, i);
                }
                var det = def.section ("detail");
                if (det != null && det.visible) emit_section (det, i, i, i + 1);
            }
            if (rows.size > 0) {
                for (int g = group_count - 1; g >= 0; g--) close_group (g, rows.size - 1);
            }
            var rf = def.section ("report-footer");
            if (rf != null && rf.visible) emit_section (rf, rows.size > 0 ? rows.size - 1 : -1, 0, rows.size);
            finish_page ();
        }

        private int scope_level (string section) {
            if (section == "detail") return group_count - 1;
            if (section.has_prefix ("group-header:") || section.has_prefix ("group-footer:")) return int.parse (section.substring (13)) - 1;
            return -1;
        }

        private void open_group (int g, int row) {
            foreach (var c in def.controls) {
                if (c.running_sum == "group" && g <= scope_level (c.section)) running.unset (c.name.down ());
                if (c.hide_duplicates) last_shown.unset (c.name.down ());
            }
            var sec = def.section ("group-header:%d".printf (g));
            var grp = def.groups[g];
            if (grp.page_break && row > 0 && page_has_content) new_page ();
            if (sec == null || !sec.visible || !grp.header) return;
            if (grp.keep_together && row >= 0) {
                double need = sec.height;
                var det = def.section ("detail");
                if (det != null) need += det.height;
                if (y + need > bottom && page_has_content) new_page ();
            }
            emit_section (sec, row, spans[row, g * 2], spans[row, g * 2 + 1]);
        }

        private void close_group (int g, int row) {
            var sec = def.section ("group-footer:%d".printf (g));
            if (sec == null || !sec.visible || !def.groups[g].footer) return;
            emit_section (sec, row, spans[row, g * 2], spans[row, g * 2 + 1]);
        }

        private bool skip_page_header;

        private void start_page () {
            page = new LayoutPage ();
            page.width = pw;
            page.height = ph;
            page.font_scale = def.font_scale;
            pages.add (page);
            page_number = pages.size;
            y = top;
            page_has_content = false;
            if (!skip_page_header) place_page_header ();
        }

        private void place_page_header () {
            var ph_sec = def.section ("page-header");
            if (ph_sec != null && ph_sec.visible && depth == 0) {
                int saved = depth;
                depth = 1;
                place_section (ph_sec, current_row, 0, rows.size, false);
                depth = saved;
            }
        }

        private int current_row = -1;

        private void finish_page () {
            var pf = def.section ("page-footer");
            if (pf == null || !pf.visible) return;
            double saved = y;
            y = ph - def.margin_mm / 25.4 * 72 - footer_h;
            int saved_depth = depth;
            depth = 1;
            place_section (pf, current_row, 0, rows.size, false);
            depth = saved_depth;
            y = saved;
        }

        private void new_page () {
            finish_page ();
            start_page ();
        }

        private void emit_section (ReportSection sec, int row, int span_start, int span_end) {
            current_row = row;
            if (sec.new_page_before && page_has_content) new_page ();
            if (sec.on_format != "") {
                scope.row = row >= 0 && row < rows.size ? rows[row] : null;
                try {
                    bool cancel;
                    EventHandler.fire (rt, scope, "Report_" + def.name, section_proc (sec.kind), "Format", sec.on_format, {}, out cancel);
                    if (cancel) return;
                } catch (Error e) {
                }
            }
            place_section (sec, row, span_start, span_end, true);
            if (sec.new_page_after) new_page ();
        }

        private static string section_proc (string kind) {
            switch (kind) {
                case "detail": return "Detail";
                case "report-header": return "ReportHeader";
                case "report-footer": return "ReportFooter";
                case "page-header": return "PageHeaderSection";
                case "page-footer": return "PageFooterSection";
            }
            if (kind.has_prefix ("group-header:")) return "GroupHeader" + kind.substring (13);
            if (kind.has_prefix ("group-footer:")) return "GroupFooter" + kind.substring (13);
            return kind;
        }

        private class Placed {
            public ReportControl c;
            public string text = "";
            public string markup = "";
            public double height;
            public DbValue value;
            public CondRule? rule;
            public bool hidden;
        }

        private string format_value (ReportControl c, SValue v, Field? f) {
            if (v.is_null || v.is_empty) return "";
            if (c.format != "") {
                try {
                    return AccessFormat.format (v, c.format);
                } catch (ScriptError e) {
                }
            }
            if (f != null) return Codec.display (f, v.to_db ());
            if (v.kind == SKind.DOUBLE) return Codec.format_number (v.d, v.d == Math.floor (v.d) ? 0 : 2, true);
            return v.to_text ();
        }

        private void place_section (ReportSection sec, int row, int span_start, int span_end, bool flow) {
            var aggs = new SpanAggregates (data_def, rows, span_start, span_end);
            scope.row = row >= 0 && row < rows.size ? rows[row] : null;
            var placed = new Gee.ArrayList<Placed> ();
            double height = sec.height;
            var evalr = new CondEval ();
            foreach (var c in def.controls) {
                if (c.section != sec.kind || !c.visible) continue;
                var p = new Placed ();
                p.c = c;
                p.height = c.h;
                Field? f = null;
                SValue v = new SValue.null ();
                string src = c.source.strip ();
                try {
                    if (c.kind == "label") {
                        v = new SValue.str (c.caption);
                    } else if (src.has_prefix ("=")) {
                        v = rt.eval_with (ScriptParser.parse_expression (src.substring (1)), scope, scope, aggs);
                    } else if (src != "") {
                        f = data_def.find (src);
                        if (f != null && scope.row != null) v = SValue.from_db (scope.row.get (data_def.index_of (src)), f.field_type);
                    }
                } catch (Error e) {
                    v = new SValue.str ("#" + _("Error"));
                }
                if (c.running_sum != "no" && (c.kind == "text") && !v.is_null) {
                    string key = c.name.down ();
                    double cur = running.has_key (key) ? running[key] : 0;
                    try {
                        cur += v.to_double ();
                    } catch (ScriptError e) {
                    }
                    running[key] = cur;
                    v = new SValue.dbl (cur);
                    f = null;
                }
                p.value = v.to_db ();
                if (c.name != "") scope.values[c.name.down ()] = v;
                if (c.kind == "label") p.text = c.caption;
                else p.text = format_value (c, v, f);
                if (c.kind == "text" && c.format == "" && f != null && f.rich_text && !v.is_null) p.markup = RichText.to_markup (v.to_text ());
                if (c.hide_duplicates) {
                    string key = c.name.down ();
                    if (last_shown.has_key (key) && last_shown[key] == p.text) p.hidden = true;
                    last_shown[key] = p.text;
                }
                if (c.conditions.size > 0) p.rule = evalr.first_match (c.conditions, c.name, f, p.value, rt, scope);
                if ((c.kind == "text" || c.kind == "label") && c.can_grow && sec.can_grow && !p.hidden) {
                    var probe = new PageItem.label (0, 0, c.w, c.h, p.text, TextRole.BODY, ReportAlign.LEFT);
                    probe.markup = p.markup;
                    probe.custom = true;
                    probe.font_size = c.font_size;
                    probe.bold = c.bold;
                    probe.italic = c.italic;
                    p.height = double.max (c.h, renderer.measure_custom (probe, c.w));
                }
                height = double.max (height, c.y + p.height);
                placed.add (p);
            }
            if (flow && y + height > bottom && page_has_content) new_page ();
            double base_y = y;
            if (sec.back_color != "") {
                var fill = new PageItem.fill (left + x_offset, base_y, pw - 2 * left - x_offset, height, 0);
                fill.kind = ItemKind.RECT;
                fill.fill_color = sec.back_color;
                page.items.add (fill);
            }
            var subreports = new Gee.ArrayList<ReportControl> ();
            foreach (var p in placed) {
                var c = p.c;
                if (p.hidden) continue;
                double x = left + x_offset + c.x;
                double iy = base_y + c.y;
                switch (c.kind) {
                    case "line":
                        var ln = new PageItem.line (x, iy, c.w, 0.6);
                        page.items.add (ln);
                        break;
                    case "rectangle":
                        var rc = new PageItem.fill (x, iy, c.w, c.h, 1);
                        rc.kind = ItemKind.RECT;
                        rc.fill_color = c.back;
                        rc.color = c.fore;
                        page.items.add (rc);
                        break;
                    case "image":
                        var im = new PageItem.fill (x, iy, c.w, c.h, 0);
                        im.kind = ItemKind.IMAGE;
                        if (c.image != "") im.image = new Bytes (Base64.decode (c.image));
                        else if (p.value.kind == ValueKind.BLOB) {
                            var files = Attachment.unpack_all (p.value.blob_value);
                            foreach (var fl in files) {
                                if (fl.mime.has_prefix ("image/") || fl.name.down ().has_suffix (".png") || fl.name.down ().has_suffix (".jpg")) {
                                    im.image = fl.content;
                                    break;
                                }
                            }
                        }
                        if (im.image != null) page.items.add (im);
                        break;
                    case "checkbox":
                        var ck = new PageItem.fill (x, iy, c.w, c.h, 0);
                        ck.kind = ItemKind.CHECK;
                        ck.checked_state = p.value.as_bool ();
                        page.items.add (ck);
                        break;
                    case "chart":
                        var chi = new PageItem.fill (x, iy, c.w, c.h, 0);
                        chi.kind = ItemKind.CHART;
                        chi.chart_type = c.chart_type;
                        string where = "";
                        if (c.link_master != "" && c.link_child != "" && scope.row != null) {
                            int mi = data_def.index_of (c.link_master);
                            if (mi >= 0) where = "%s = %s".printf (Sql.quote_ident (c.link_child), scope.row.get (mi).sql_literal ());
                        }
                        chi.chart = ChartData.load (db, c.chart_source, c.chart_category, c.chart_value, c.chart_aggregate, c.chart_series, where);
                        page.items.add (chi);
                        break;
                    case "pagebreak":
                        break;
                    case "subreport":
                        subreports.add (c);
                        break;
                    default:
                        double pad = c.border ? 3 : 0;
                        var t = new PageItem.label (x + pad, iy + pad * 0.4, c.w - 2 * pad, p.height, p.text, TextRole.BODY, c.align == "right" ? ReportAlign.RIGHT : (c.align == "center" ? ReportAlign.CENTER : ReportAlign.LEFT));
                        t.custom = true;
                        t.markup = p.markup;
                        t.font_size = c.font_size;
                        t.bold = p.rule != null ? p.rule.bold || c.bold : c.bold;
                        t.italic = p.rule != null ? p.rule.italic || c.italic : c.italic;
                        t.color = p.rule != null && p.rule.fore != "" ? p.rule.fore : c.fore;
                        t.fill_color = p.rule != null && p.rule.back != "" ? p.rule.back : c.back;
                        if (p.text != "" || t.fill_color != "") page.items.add (t);
                        if (c.border) {
                            var bx = new PageItem.fill (x, iy, c.w, p.height, 1);
                            bx.kind = ItemKind.RECT;
                            bx.color = "#a0a4ab";
                            page.items.add (bx);
                        }
                        break;
                }
            }
            y = base_y + height;
            if (flow) page_has_content = true;
            foreach (var p in placed) {
                if (p.c.kind == "pagebreak" && flow) {
                    new_page ();
                    break;
                }
            }
            foreach (var c in subreports) run_subreport (c, row);
        }

        private void run_subreport (ReportControl c, int row) {
            if (depth > 3) return;
            var sub = ReportDef.from_json (c.subreport, db.get_meta ("report:" + c.subreport));
            if (sub == null) return;
            try {
                var st = sub.state.copy ();
                if (c.link_master != "" && c.link_child != "" && row >= 0 && row < rows.size) {
                    string[] ms = c.link_master.split (";");
                    string[] cs = c.link_child.split (";");
                    string[] parts = {};
                    for (int k = 0; k < ms.length && k < cs.length; k++) {
                        int mi = data_def.index_of (ms[k].strip ());
                        if (mi < 0) continue;
                        var v = rows[row].get (mi);
                        parts += v.is_null ? "1 = 0" : "[%s] = %s".printf (cs[k].strip (), v.kind == ValueKind.TEXT ? "'" + v.text_value.replace ("'", "''") + "'" : v.to_string ());
                    }
                    sub.open_where = string.joinv (" And ", parts);
                }
                sub.state = st;
                var src = ReportEngine.open_source (db, sub);
                var engine = new BandedEngine (sub, db, rt, renderer);
                engine.depth = depth + 1;
                if (!sub.designed) sub = ReportDesign.convert (sub, src.def);
                engine.def = sub;
                engine.embed_into (this, src, c.x);
            } catch (Error e) {
            }
        }

        public void embed_into (BandedEngine parent, RecordSource data, double x) {
            data_def = data.def;
            rows.clear ();
            int64 n = data.count ();
            for (int64 i = 0; i < n; i++) {
                var r = data.row (i);
                if (r == null) break;
                rows.add (r);
            }
            scope = new ReportScope (this);
            pages = parent.pages;
            page = parent.page;
            pw = parent.pw;
            ph = parent.ph;
            left = parent.left;
            top = parent.top;
            bottom = parent.bottom;
            footer_h = parent.footer_h;
            y = parent.y;
            x_offset = parent.x_offset + x;
            page_number = parent.page_number;
            total_pages = parent.total_pages;
            page_has_content = true;
            compute_spans ();
            var rh = def.section ("report-header");
            if (rh != null && rh.visible) emit_section_embedded (parent, rh, -1, 0, rows.size);
            for (int i = 0; i < rows.size; i++) {
                int changed = group_count;
                if (i == 0) changed = 0;
                else {
                    for (int g = 0; g < group_count; g++) {
                        if (spans[i, g * 2] == i) {
                            changed = g;
                            break;
                        }
                    }
                }
                if (i > 0 && changed < group_count) {
                    for (int g = group_count - 1; g >= changed; g--) {
                        var fs = def.section ("group-footer:%d".printf (g));
                        if (fs != null && fs.visible) emit_section_embedded (parent, fs, i - 1, spans[i - 1, g * 2], spans[i - 1, g * 2 + 1]);
                    }
                }
                if (changed < group_count) {
                    for (int g = changed; g < group_count; g++) {
                        var hs = def.section ("group-header:%d".printf (g));
                        if (hs != null && hs.visible) emit_section_embedded (parent, hs, i, spans[i, g * 2], spans[i, g * 2 + 1]);
                    }
                }
                var det = def.section ("detail");
                if (det != null && det.visible) emit_section_embedded (parent, det, i, i, i + 1);
            }
            if (rows.size > 0) {
                for (int g = group_count - 1; g >= 0; g--) {
                    var fs = def.section ("group-footer:%d".printf (g));
                    if (fs != null && fs.visible) emit_section_embedded (parent, fs, rows.size - 1, spans[rows.size - 1, g * 2], spans[rows.size - 1, g * 2 + 1]);
                }
            }
            var rf = def.section ("report-footer");
            if (rf != null && rf.visible) emit_section_embedded (parent, rf, rows.size > 0 ? rows.size - 1 : -1, 0, rows.size);
        }

        private void emit_section_embedded (BandedEngine parent, ReportSection sec, int row, int a, int b) {
            page = parent.page;
            y = parent.y;
            if (y + sec.height > bottom) {
                parent.new_page ();
                page = parent.page;
                y = parent.y;
            }
            page_number = parent.page_number;
            place_section (sec, row, a, b, false);
            parent.y = y;
            parent.page_has_content = true;
        }
    }

    public class ReportDesign {
        public static ReportDef from_form (FormDef form, TableDef data) {
            var r = new ReportDef ();
            r.name = form.name;
            r.source = form.source;
            r.title = form.title != "" ? form.title : form.name;
            r.designed = true;
            double pw, ph;
            r.paper_size (out pw, out ph);
            double width = pw - 2 * r.margin_mm / 25.4 * 72;
            var rh = r.ensure_section ("page-header", 30);
            var title = new ReportControl ();
            title.kind = "label";
            title.section = rh.kind;
            title.name = "Title";
            title.caption = r.title;
            title.w = width;
            title.h = 22;
            title.font_size = 16;
            title.bold = true;
            title.fore = "#1a3869";
            r.controls.add (title);
            var tabs = new Gee.HashSet<string> ();
            foreach (var c in form.controls) {
                if (c.kind == ControlKind.TAB) tabs.add (c.display_name ());
            }
            double right = 1;
            foreach (var c in form.controls) {
                if (c.section != "detail" || !c.visible) continue;
                right = double.max (right, c.x + c.width);
            }
            double sc = double.min (1.0, width / right) * 0.75;
            int ci = 0;
            double bottom = 0;
            foreach (var c in form.controls) {
                if (c.section != "detail" || !c.visible) continue;
                if (c.kind == ControlKind.BUTTON || c.kind == ControlKind.TAB || c.kind == ControlKind.SUBFORM) continue;
                if (c.parent != "") {
                    int colon = c.parent.last_index_of (":");
                    if (colon <= 0 || c.parent.substring (colon + 1) != "0") continue;
                    if (!tabs.contains (c.parent.substring (0, colon))) continue;
                }
                double x = c.x * sc;
                double y = c.y * sc;
                double w = double.max (24, c.width * sc);
                double h = c.height > 0 ? c.height * sc : 0;
                var f = c.is_bound () ? data.find (c.field) : null;
                var kind = c.kind;
                if (kind == ControlKind.AUTO && f != null) {
                    if (f.field_type == FieldType.BOOLEAN) kind = ControlKind.CHECK;
                    else if (f.field_type == FieldType.ATTACHMENT) kind = ControlKind.ATTACHMENT;
                    else if (f.field_type == FieldType.LONG_TEXT) kind = ControlKind.MULTILINE;
                }
                var rc = new ReportControl ();
                rc.section = "detail";
                rc.name = "C%d".printf (++ci);
                rc.x = x;
                rc.w = w;
                rc.font_size = c.font_size > 0 ? c.font_size * 0.75 : 9;
                rc.bold = c.bold;
                rc.italic = c.italic;
                rc.fore = c.fore_color;
                rc.conditions.add_all (c.conditions);
                switch (kind) {
                    case ControlKind.LABEL:
                        rc.kind = "label";
                        rc.caption = c.caption != "" ? c.caption : c.label;
                        rc.y = y;
                        rc.h = h > 0 ? h : 14;
                        r.controls.add (rc);
                        bottom = double.max (bottom, rc.y + rc.h);
                        continue;
                    case ControlKind.LINE:
                        rc.kind = "line";
                        rc.y = y;
                        rc.h = 1;
                        r.controls.add (rc);
                        continue;
                    case ControlKind.RECTANGLE:
                        rc.kind = "rectangle";
                        rc.y = y;
                        rc.h = h > 0 ? h : 30;
                        rc.back = c.back_color;
                        r.controls.add (rc);
                        bottom = double.max (bottom, rc.y + rc.h);
                        continue;
                    case ControlKind.IMAGE:
                        rc.kind = "image";
                        rc.image = c.image;
                        rc.source = c.field;
                        rc.y = y;
                        rc.h = h > 0 ? h : 60;
                        r.controls.add (rc);
                        bottom = double.max (bottom, rc.y + rc.h);
                        continue;
                    case ControlKind.CHART:
                        rc.kind = "chart";
                        rc.y = y;
                        rc.h = h > 0 ? h : 120;
                        rc.chart_type = c.chart_type;
                        rc.chart_source = c.chart_source;
                        rc.chart_category = c.chart_category;
                        rc.chart_value = c.chart_value;
                        rc.chart_aggregate = c.chart_aggregate;
                        rc.chart_series = c.chart_series;
                        rc.link_master = c.link_master;
                        rc.link_child = c.link_child;
                        r.controls.add (rc);
                        bottom = double.max (bottom, rc.y + rc.h);
                        continue;
                    default:
                        break;
                }
                double vy = y;
                if (!c.hide_label && kind != ControlKind.CHECK && kind != ControlKind.TOGGLE) {
                    var lab = new ReportControl ();
                    lab.kind = "label";
                    lab.section = "detail";
                    lab.name = "L%d".printf (ci);
                    lab.caption = c.label != "" ? c.label : (f != null ? f.label () : c.display_name ());
                    lab.x = x;
                    lab.y = y;
                    lab.w = w;
                    lab.h = 11;
                    lab.font_size = 7;
                    lab.fore = "#61666f";
                    lab.can_grow = false;
                    r.controls.add (lab);
                    vy = y + 12;
                }
                rc.y = vy;
                if (kind == ControlKind.CHECK || kind == ControlKind.TOGGLE) {
                    rc.kind = "checkbox";
                    rc.source = c.field;
                    rc.w = 10;
                    rc.h = 10;
                    r.controls.add (rc);
                    var cl = new ReportControl ();
                    cl.kind = "label";
                    cl.section = "detail";
                    cl.name = "L%d".printf (ci);
                    cl.caption = c.label != "" ? c.label : (f != null ? f.label () : c.display_name ());
                    cl.x = x + 14;
                    cl.y = vy - 1;
                    cl.w = w - 14;
                    cl.h = 12;
                    r.controls.add (cl);
                    bottom = double.max (bottom, vy + 12);
                    continue;
                }
                if (kind == ControlKind.ATTACHMENT) {
                    rc.kind = "image";
                    rc.source = c.field;
                    rc.h = h > 0 ? double.max (20, h - 12) : 60;
                    r.controls.add (rc);
                    bottom = double.max (bottom, rc.y + rc.h);
                    continue;
                }
                rc.kind = "text";
                rc.source = c.field;
                rc.format = c.format;
                rc.border = true;
                rc.can_grow = kind == ControlKind.MULTILINE || kind == ControlKind.RICH_TEXT;
                rc.h = kind == ControlKind.MULTILINE || kind == ControlKind.RICH_TEXT ? double.max (14, h - 12) : 14;
                if (c.text_align != "") rc.align = c.text_align;
                else if (f != null && (f.field_type.is_numeric () || f.field_type == FieldType.CURRENCY)) rc.align = "right";
                r.controls.add (rc);
                bottom = double.max (bottom, rc.y + rc.h);
            }
            var det = r.ensure_section ("detail", (int) Math.ceil (bottom + 14));
            det.keep_together = true;
            var line = new ReportControl ();
            line.kind = "line";
            line.section = "detail";
            line.name = "Separator";
            line.y = bottom + 7;
            line.w = width;
            line.h = 1;
            r.controls.add (line);
            var pf = r.ensure_section ("page-footer", 18);
            var pg = new ReportControl ();
            pg.kind = "text";
            pg.section = pf.kind;
            pg.name = "PageNumber";
            pg.source = "=\"%s \" & [Page] & \" %s \" & [Pages]".printf (_("Page"), _("of"));
            pg.y = 4;
            pg.w = width;
            pg.h = 12;
            pg.align = "right";
            pg.fore = "#61666f";
            pg.font_size = 8;
            r.controls.add (pg);
            return r;
        }

        public static ReportDef convert (ReportDef src, TableDef data) {
            var r = ReportDef.from_json (src.name, src.to_json ());
            r.state = src.state.copy ();
            r.open_where = src.open_where;
            if (r.designed) return r;
            r.designed = true;
            r.sections.clear ();
            r.controls.clear ();
            double pw, ph;
            r.paper_size (out pw, out ph);
            double width = pw - 2 * r.margin_mm / 25.4 * 72;
            var rh = r.ensure_section ("report-header", 44);
            var ph_sec = r.ensure_section ("page-header", r.layout == ReportLayoutKind.TABULAR ? 22 : 0);
            var title = new ReportControl ();
            title.kind = "label";
            title.section = rh.kind;
            title.name = "Title";
            title.caption = r.title;
            title.w = width;
            title.h = 26;
            title.font_size = 20;
            title.bold = true;
            title.fore = "#1a3869";
            r.controls.add (title);
            if (r.subtitle != "") {
                var sub = new ReportControl ();
                sub.kind = "label";
                sub.section = rh.kind;
                sub.name = "Subtitle";
                sub.caption = r.subtitle;
                sub.y = 26;
                sub.w = width;
                sub.h = 14;
                sub.fore = "#61666f";
                r.controls.add (sub);
            }
            double total_w = 0;
            foreach (var c in r.columns) total_w += double.max (0.1, c.width);
            for (int g = 0; g < r.groups.size; g++) {
                var gh = r.ensure_section ("group-header:%d".printf (g), 22);
                var gl = new ReportControl ();
                gl.kind = "text";
                gl.section = gh.kind;
                gl.name = "Group%d".printf (g + 1);
                gl.source = "=\"%s: \" & [%s]".printf (r.groups[g].field.replace ("\"", "\"\""), r.groups[g].field);
                gl.x = g * 12;
                gl.y = 4;
                gl.w = width - g * 12;
                gl.h = 16;
                gl.font_size = 11;
                gl.bold = true;
                gl.fore = "#1a3869";
                r.controls.add (gl);
            }
            var det = r.ensure_section ("detail", 18);
            double x = 0;
            int ci = 0;
            foreach (var col in r.columns) {
                double w = width * double.max (0.1, col.width) / total_w;
                var f = data.find (col.field);
                bool right = f != null && f.field_type.is_numeric () && f.field_type != FieldType.AUTONUMBER;
                if (r.layout == ReportLayoutKind.TABULAR) {
                    var head = new ReportControl ();
                    head.kind = "label";
                    head.section = ph_sec.kind;
                    head.name = "Head%d".printf (++ci);
                    head.caption = col.label;
                    head.x = x;
                    head.y = 3;
                    head.w = w - 4;
                    head.h = 14;
                    head.bold = true;
                    head.font_size = 8.5;
                    head.align = right ? "right" : "left";
                    r.controls.add (head);
                    var t = new ReportControl ();
                    t.kind = "text";
                    t.section = det.kind;
                    t.name = col.field.replace (" ", "");
                    t.source = col.field;
                    t.x = x;
                    t.y = 2;
                    t.w = w - 4;
                    t.h = 14;
                    t.align = right ? "right" : "left";
                    r.controls.add (t);
                } else {
                    var lab = new ReportControl ();
                    lab.kind = "label";
                    lab.section = det.kind;
                    lab.name = "Label%d".printf (++ci);
                    lab.caption = col.label;
                    lab.y = det.height - 18;
                    lab.w = 140;
                    lab.h = 14;
                    lab.fore = "#61666f";
                    r.controls.add (lab);
                    var t = new ReportControl ();
                    t.kind = "text";
                    t.section = det.kind;
                    t.name = col.field.replace (" ", "");
                    t.source = col.field;
                    t.x = 152;
                    t.y = det.height - 18;
                    t.w = width - 152;
                    t.h = 14;
                    r.controls.add (t);
                    det.height += 18;
                }
                if (col.total != ReportTotal.NONE) {
                    string fn;
                    switch (col.total) {
                        case ReportTotal.AVG: fn = "Avg"; break;
                        case ReportTotal.COUNT: fn = "Count"; break;
                        case ReportTotal.MIN: fn = "Min"; break;
                        case ReportTotal.MAX: fn = "Max"; break;
                        default: fn = "Sum"; break;
                    }
                    for (int g = 0; g <= r.groups.size; g++) {
                        string sk = g < r.groups.size ? "group-footer:%d".printf (g) : "report-footer";
                        var fs = r.ensure_section (sk, 22);
                        var tt = new ReportControl ();
                        tt.kind = "text";
                        tt.section = fs.kind;
                        tt.name = "%s%s%d".printf (fn, col.field.replace (" ", ""), g);
                        tt.source = "=%s([%s])".printf (fn, col.field);
                        tt.x = r.layout == ReportLayoutKind.TABULAR ? x : 152;
                        tt.y = 4;
                        tt.w = r.layout == ReportLayoutKind.TABULAR ? w - 4 : width - 152;
                        tt.h = 14;
                        tt.bold = true;
                        tt.align = right ? "right" : "left";
                        if (f != null && f.field_type == FieldType.CURRENCY) tt.format = "Currency";
                        r.controls.add (tt);
                    }
                }
                x += w;
            }
            if (r.show_count) {
                for (int g = 0; g <= r.groups.size; g++) {
                    string sk = g < r.groups.size ? "group-footer:%d".printf (g) : "report-footer";
                    var fs = r.ensure_section (sk, 22);
                    var cnt = new ReportControl ();
                    cnt.kind = "text";
                    cnt.section = fs.kind;
                    cnt.name = "Count%d".printf (g);
                    cnt.source = g < r.groups.size ? "=\"%s\" & Count(*)".printf (_("Records: ")) : "=\"%s\" & Count(*)".printf (_("Total records: "));
                    cnt.y = 4;
                    cnt.w = 200;
                    cnt.h = 14;
                    cnt.fore = "#61666f";
                    r.controls.add (cnt);
                }
            }
            var pf = r.ensure_section ("page-footer", 20);
            if (r.show_date) {
                var d = new ReportControl ();
                d.kind = "text";
                d.section = pf.kind;
                d.name = "PrintDate";
                d.source = "=Date()";
                d.format = "Long Date";
                d.y = 4;
                d.w = width / 2;
                d.h = 12;
                d.font_size = 8;
                d.fore = "#61666f";
                r.controls.add (d);
            }
            if (r.page_numbers) {
                var pn = new ReportControl ();
                pn.kind = "text";
                pn.section = pf.kind;
                pn.name = "PageNumber";
                pn.source = "=\"%s \" & [Page] & \" %s \" & [Pages]".printf (_("Page"), _("of"));
                pn.x = width / 2;
                pn.y = 4;
                pn.w = width / 2;
                pn.h = 12;
                pn.font_size = 8;
                pn.align = "right";
                pn.fore = "#61666f";
                r.controls.add (pn);
            }
            order_sections (r);
            return r;
        }

        public static void order_sections (ReportDef r) {
            var ordered = new Gee.ArrayList<ReportSection> ();
            string[] kinds = { "report-header", "page-header" };
            foreach (string k in kinds) {
                var s = r.section (k);
                if (s != null) ordered.add (s);
            }
            for (int g = 0; g < r.groups.size; g++) {
                var s = r.section ("group-header:%d".printf (g));
                if (s != null) ordered.add (s);
            }
            var d = r.section ("detail");
            if (d != null) ordered.add (d);
            for (int g = r.groups.size - 1; g >= 0; g--) {
                var s = r.section ("group-footer:%d".printf (g));
                if (s != null) ordered.add (s);
            }
            foreach (string k in new string[] { "page-footer", "report-footer" }) {
                var s = r.section (k);
                if (s != null) ordered.add (s);
            }
            r.sections = ordered;
        }
    }
}
