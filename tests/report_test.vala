using Singularity.Apps.Database;

int checks = 0;

void ok (bool cond, string what) {
    checks++;
    if (!cond) {
        stderr.printf ("FAIL: %s\n", what);
        Process.exit (1);
    }
}

string tmp_path (string name) {
    return Path.build_filename (Environment.get_tmp_dir (), "sdb-report-%d-%s".printf (Random.int_range (0, 1000000), name));
}

double fixed_measure (string text, TextRole role, double width, double scale) {
    double size = role.size () * scale;
    double chars = double.max (1, text.char_count ()) * size * 0.5;
    double lines = double.max (1, Math.ceil (chars / double.max (1, width)));
    return lines * size * 1.3;
}

Database sample () throws Error {
    var db = Database.memory ();
    var t = new TableDef ("Sales");
    var id = t.add_field ("ID", FieldType.AUTONUMBER);
    id.primary_key = true;
    t.add_field ("Region", FieldType.TEXT);
    t.add_field ("Rep", FieldType.TEXT);
    var amt = t.add_field ("Amount", FieldType.CURRENCY);
    amt.decimals = 2;
    t.add_field ("Units", FieldType.INTEGER);
    t.add_field ("Day", FieldType.DATE);
    db.create_table (t);
    string[] regions = { "North", "South", "East" };
    string[] reps = { "Ada", "Bob" };
    db.begin ();
    for (int i = 0; i < 120; i++) {
        db.run ("INSERT INTO Sales (Region, Rep, Amount, Units, Day) VALUES (?, ?, ?, ?, ?)", {
            new DbValue.text (regions[i % 3]), new DbValue.text (reps[i % 2]), new DbValue.real (10 + i), new DbValue.int (i % 5 + 1), new DbValue.text ("2025-01-%02d".printf (1 + i % 28))
        });
    }
    db.commit ();
    return db;
}

ReportDef base_def () {
    var r = new ReportDef ();
    r.name = "Sales Report";
    r.source = "Sales";
    r.title = "Sales Report";
    r.subtitle = "January";
    r.columns.add (new ReportColumn ("Rep", "Rep"));
    var a = new ReportColumn ("Amount", "Amount");
    a.total = ReportTotal.SUM;
    r.columns.add (a);
    var u = new ReportColumn ("Units", "Units");
    u.total = ReportTotal.AVG;
    r.columns.add (u);
    r.columns.add (new ReportColumn ("Day", "Day"));
    return r;
}

Gee.ArrayList<LayoutPage> run (Database db, ReportDef def) throws Error {
    var src = ReportEngine.open_source (db, def);
    var engine = new ReportEngine (def, src, fixed_measure);
    engine.set_date_text ("DATE");
    return engine.run ();
}

Gee.ArrayList<string> all_texts (Gee.ArrayList<LayoutPage> pages, TextRole role) {
    var list = new Gee.ArrayList<string> ();
    foreach (var p in pages) list.add_all (p.texts (role));
    return list;
}

void test_tabular (Database db) throws Error {
    Locale.set_default (Locale.neutral ());
    var def = base_def ();
    def.groups.add (new ReportGroup ("Region"));
    var pages = run (db, def);
    ok (pages.size >= 3, "multiple pages (%d)".printf (pages.size));
    var titles = pages[0].texts (TextRole.TITLE);
    ok (titles.size == 1 && titles[0] == "Sales Report", "title on first page");
    ok (pages[1].texts (TextRole.TITLE).size == 0, "title only once");
    foreach (var p in pages) ok (p.texts (TextRole.COLUMN_HEADER).size == 4, "column headers repeat");
    var groups = all_texts (pages, TextRole.GROUP_HEADER);
    ok (groups.size == 3 && groups[0] == "Region: East" && groups[1] == "Region: North" && groups[2] == "Region: South", "group headers sorted");
    var subs = all_texts (pages, TextRole.SUBTOTAL);
    ok (subs.contains ("Total for East (40)"), "subtotal caption");
    double east = 0;
    for (int i = 0; i < 120; i++) {
        if (i % 3 == 2) east += 10 + i;
    }
    ok (subs.contains (Codec.format_currency (east, 2)), "east sum " + Codec.format_currency (east, 2));
    double units = 0;
    for (int i = 2; i < 120; i += 3) units += i % 5 + 1;
    ok (subs.contains (Codec.format_number (units / 40, 2, true)), "average units " + Codec.format_number (units / 40, 2, true));
    var grand = all_texts (pages, TextRole.GRAND_TOTAL);
    double total = 0;
    for (int i = 0; i < 120; i++) total += 10 + i;
    ok (grand.contains ("Grand Total (120 records)") && grand.contains (Codec.format_currency (total, 2)), "grand total");
    var footers = all_texts (pages, TextRole.FOOTER);
    ok (footers.contains ("Page 1 of %d".printf (pages.size)) && footers.contains ("Page %d of %d".printf (pages.size, pages.size)) && footers.contains ("DATE"), "page footers");
    int bodies = 0;
    foreach (var p in pages) {
        foreach (var it in p.items) {
            if (it.kind == ItemKind.TEXT && it.role == TextRole.BODY && it.text == "Ada") bodies++;
            if (it.kind == ItemKind.TEXT) ok (it.y + it.h <= p.height, "item inside page");
        }
    }
    ok (bodies == 60, "all rows rendered once");
    foreach (var p in pages) {
        foreach (var it in p.items) {
            if (it.kind == ItemKind.TEXT && it.role == TextRole.BODY && it.text.has_prefix ("$")) ok (it.align == ReportAlign.RIGHT, "currency right aligned");
        }
    }
}

void test_nested_and_breaks (Database db) throws Error {
    var def = base_def ();
    def.title = "";
    def.subtitle = "";
    def.groups.add (new ReportGroup ("Region"));
    def.groups.add (new ReportGroup ("Rep"));
    def.groups[0].page_break = true;
    def.groups[0].descending = true;
    var pages = run (db, def);
    var heads = all_texts (pages, TextRole.GROUP_HEADER);
    ok (heads.size == 9 && heads[0] == "Region: South" && heads[1] == "Rep: Ada" && heads[2] == "Rep: Bob" && heads[3] == "Region: North", "nested groups order");
    int starts = 0;
    foreach (var p in pages) {
        var h = p.texts (TextRole.GROUP_HEADER);
        if (h.size > 0 && h[0].has_prefix ("Region:")) starts++;
    }
    ok (starts >= 3, "page break before each region");
    var subs = all_texts (pages, TextRole.SUBTOTAL);
    ok (subs.contains ("Total for Ada (20)") && subs.contains ("Total for South (40)"), "nested subtotals");
    def.groups[1].footer = false;
    def.groups[1].header = false;
    pages = run (db, def);
    ok (all_texts (pages, TextRole.GROUP_HEADER).size == 3, "hidden inner header");
    ok (!all_texts (pages, TextRole.SUBTOTAL).contains ("Total for Ada (20)"), "hidden inner footer");
}

void test_filters_and_empty (Database db) throws Error {
    var def = base_def ();
    def.state.filters.add (new FilterSpec ("Region", FilterOp.EQUALS, "North"));
    def.state.sorts.add (new SortSpec ("Amount", true));
    var pages = run (db, def);
    var grand = all_texts (pages, TextRole.GRAND_TOTAL);
    ok (grand.contains ("Grand Total (40 records)"), "filtered grand total");
    string first_amount = "";
    foreach (var it in pages[0].items) {
        if (it.kind == ItemKind.TEXT && it.role == TextRole.BODY && it.text.has_prefix ("$")) {
            first_amount = it.text;
            break;
        }
    }
    ok (first_amount == Codec.format_currency (10 + 117, 2), "sorted desc first " + first_amount);
    def.state.filters.clear ();
    def.state.filters.add (new FilterSpec ("Region", FilterOp.EQUALS, "Nowhere"));
    pages = run (db, def);
    ok (pages.size == 1 && pages[0].texts ().contains ("No records to show."), "empty report");
    def.state.filters.clear ();
    def.grand_total = false;
    def.show_count = false;
    pages = run (db, def);
    ok (all_texts (pages, TextRole.GRAND_TOTAL).size == 0, "no grand total");
}

void test_layouts (Database db) throws Error {
    var def = base_def ();
    def.layout = ReportLayoutKind.STACKED;
    def.groups.add (new ReportGroup ("Region"));
    var pages = run (db, def);
    var labels = all_texts (pages, TextRole.FIELD_LABEL);
    ok (labels.size == 480, "stacked labels per record %d".printf (labels.size));
    ok (pages.size > 5, "stacked spans pages");
    foreach (var p in pages) ok (p.texts (TextRole.COLUMN_HEADER).size == 0, "no column headers in stacked");
    var subs = all_texts (pages, TextRole.SUBTOTAL);
    bool found = false;
    foreach (string s in subs) {
        if (s.has_prefix ("Sum Amount: ")) found = true;
    }
    ok (found, "stacked subtotal values");
    def.layout = ReportLayoutKind.LABELS;
    def.groups.clear ();
    def.label_columns = 3;
    pages = run (db, def);
    int fills = 0;
    foreach (var p in pages) {
        foreach (var it in p.items) {
            if (it.kind == ItemKind.FILL) fills++;
        }
    }
    ok (fills >= 120, "one card per label");
    double first_x = -1, second_x = -1;
    foreach (var it in pages[0].items) {
        if (it.kind != ItemKind.FILL) continue;
        if (first_x < 0) first_x = it.x;
        else if (second_x < 0) {
            second_x = it.x;
            break;
        }
    }
    ok (second_x > first_x, "labels flow across");
    def.landscape = true;
    def.paper = "letter";
    double w, h;
    def.paper_size (out w, out h);
    ok (w == 792 && h == 612, "letter landscape");
}

void test_json_and_generate (Database db) throws Error {
    var def = base_def ();
    def.groups.add (new ReportGroup ("Region"));
    def.groups[0].page_break = true;
    def.landscape = true;
    def.layout = ReportLayoutKind.STACKED;
    def.state.filters.add (new FilterSpec ("Units", FilterOp.GREATER, "2"));
    def.columns[0].align = ReportAlign.CENTER;
    def.columns[0].width = 2.5;
    var back = ReportDef.from_json ("x", def.to_json ());
    ok (back.groups.size == 1 && back.groups[0].page_break && back.landscape && back.layout == ReportLayoutKind.STACKED, "report json");
    ok (back.columns[1].total == ReportTotal.SUM && back.columns[0].align == ReportAlign.CENTER && back.columns[0].width == 2.5, "report json columns");
    ok (back.state.filters.size == 1, "report json filters");
    var gen = ReportDef.generate (db, "Sales");
    ok (gen.columns.size == 5 && gen.columns[2].total == ReportTotal.SUM, "generated report");
}

void test_pdf (Database db) throws Error {
    var def = base_def ();
    def.groups.add (new ReportGroup ("Region"));
    var renderer = new ReportRenderer ();
    var src = ReportEngine.open_source (db, def);
    var pages = renderer.layout (def, src);
    ok (pages.size >= 2, "real measure pages");
    string path = tmp_path ("sales.pdf");
    ReportRenderer.export_pdf (pages, path, def.title);
    uint8[] data;
    FileUtils.get_data (path, out data);
    ok (data.length > 1000 && Memory.cmp (data, "%PDF".data, 4) == 0, "pdf header");
    int count = 0;
    int pos = 0;
    while (true) {
        int i = find (data, "/Type /Page", pos);
        if (i < 0) break;
        if (i + 11 < data.length && data[i + 11] != 's') count++;
        pos = i + 1;
    }
    ok (count == pages.size, "pdf page count %d of %d".printf (count, pages.size));
    var img = new Cairo.ImageSurface (Cairo.Format.ARGB32, 300, 420);
    var cr = new Cairo.Context (img);
    ReportRenderer.draw_page (cr, pages[0], 300 / pages[0].width);
    img.flush ();
    uint8* px = img.get_data ();
    int len = img.get_stride () * img.get_height ();
    int dark = 0;
    for (int i = 0; i < len; i += 4) {
        if (px[i] < 180 && px[i + 1] < 180 && px[i + 2] < 180) dark++;
    }
    ok (dark > 100, "preview draws ink");
}

bool xml_ok (string text) {
    var doc = Xml.Parser.read_memory (text, text.length, null, null, Xml.ParserOption.NONET);
    return doc != null;
}

void test_exports (Database db) throws Error {
    var def = base_def ();
    def.groups.add (new ReportGroup ("Region"));
    var renderer = new ReportRenderer ();
    var pages = renderer.layout (def, ReportEngine.open_source (db, def));
    var doc = ReportDocument.build (pages, def.title);
    ok (doc.columns == def.columns.size, "export columns %d".printf (doc.columns));
    ok (doc.subtitle == "January", "export subtitle");
    int groups = 0, grand = 0, body = 0;
    foreach (var l in doc.lines) {
        if (l.role == TextRole.GROUP_HEADER) groups++;
        if (l.role == TextRole.GRAND_TOTAL) grand++;
        if (l.role == TextRole.BODY) body++;
    }
    ok (groups == 3 && grand == 1 && body == 120, "export lines %d %d %d".printf (groups, grand, body));
    string html = doc.to_html ();
    ok (html.contains ("<h1>Sales Report</h1>") && html.contains ("Region: East") && html.contains ("class=\"grand\""), "html export");
    string docx_path = tmp_path ("sales.docx");
    doc.save (docx_path);
    uint8[] raw;
    FileUtils.get_data (docx_path, out raw);
    var zr = new ZipReader (raw);
    string? dx = zr.read_text ("word/document.xml");
    ok (dx != null && xml_ok (dx) && dx.contains ("Region: North") && dx.contains ("<w:tblHeader/>"), "docx export");
    ok (zr.has ("[Content_Types].xml") && zr.has ("_rels/.rels"), "docx package parts");
    string odt_path = tmp_path ("sales.odt");
    doc.save (odt_path);
    FileUtils.get_data (odt_path, out raw);
    var zo = new ZipReader (raw);
    string? ox = zo.read_text ("content.xml");
    ok (ox != null && xml_ok (ox) && ox.contains ("Region: South") && zo.read_text ("mimetype") == "application/vnd.oasis.opendocument.text", "odt export");
    ok (xml_ok (zo.read_text ("styles.xml")) && xml_ok (zo.read_text ("META-INF/manifest.xml")), "odt parts well formed");
    string xlsx_path = tmp_path ("sales.xlsx");
    doc.save (xlsx_path);
    var sheets = Xlsx.load (xlsx_path);
    ok (sheets.size == 1 && sheets[0].columns[1] == "Amount" && sheets[0].rows.size == doc.lines.size - 1, "xlsx export round trip");
    string csv_path = tmp_path ("sales.csv");
    doc.save (csv_path);
    var back = Csv.load (csv_path);
    ok (back.columns[0] == "Rep" && back.rows.size == doc.lines.size - 1, "csv export round trip");
    bool numeric = false;
    foreach (var r in sheets[0].rows) {
        if (r.get (1).is_number ()) numeric = true;
    }
    ok (numeric, "xlsx keeps numbers");
}

Gee.ArrayList<string> every_text (Gee.List<LayoutPage> pages) {
    var list = new Gee.ArrayList<string> ();
    foreach (var p in pages) list.add_all (p.texts ());
    return list;
}

void test_banded (Database db) throws Error {
    var r = new ReportDef ();
    r.name = "Banded";
    r.source = "Sales";
    r.title = "Banded";
    r.designed = true;
    var g = new ReportGroup ("Day");
    g.interval = "month";
    r.groups.add (g);
    var g2 = new ReportGroup ("Rep");
    g2.interval = "prefix";
    g2.interval_size = 1;
    r.groups.add (g2);
    r.state.sorts.add (new SortSpec ("ID", false));
    var rh = r.ensure_section ("report-header", 30);
    var ph = r.ensure_section ("page-header", 16);
    var gh = r.ensure_section ("group-header:0", 20);
    var gh2 = r.ensure_section ("group-header:1", 18);
    var det = r.ensure_section ("detail", 14);
    var gf2 = r.ensure_section ("group-footer:1", 16);
    var gf = r.ensure_section ("group-footer:0", 16);
    var pf = r.ensure_section ("page-footer", 16);
    var rf = r.ensure_section ("report-footer", 20);
    ReportDesign.order_sections (r);
    ReportControl ctl (string section, string name, string kind, string source, double x, double w) {
        var c = new ReportControl ();
        c.section = section;
        c.name = name;
        c.kind = kind;
        if (kind == "label") c.caption = source;
        else c.source = source;
        c.x = x;
        c.w = w;
        c.h = 12;
        r.controls.add (c);
        return c;
    }
    ctl (rh.kind, "T", "label", "Sales by Month", 0, 300);
    ctl (ph.kind, "H1", "label", "Rep", 0, 100);
    ctl (gh.kind, "Month", "text", "=Format([Day], \"mmmm yyyy\")", 0, 300);
    ctl (gh2.kind, "Letter", "text", "=\"Reps \" & Left([Rep], 1)", 10, 200);
    var rep = ctl (det.kind, "RepName", "text", "Rep", 20, 80);
    rep.hide_duplicates = true;
    var amt = ctl (det.kind, "Amt", "text", "Amount", 120, 80);
    amt.format = "0.00";
    var run = ctl (det.kind, "Run", "text", "Amount", 220, 80);
    run.running_sum = "group";
    run.format = "0";
    var cond = ctl (det.kind, "Big", "text", "=IIf([Amount] > 125, \"big\", \"\")", 320, 60);
    var rule = new CondRule ();
    rule.kind = "expression";
    rule.expression = "[Amount] > 125";
    rule.fore = "#c01c28";
    cond.conditions.add (rule);
    ctl (gf2.kind, "SubRep", "text", "=\"sum \" & Format(Sum([Amount]), \"0\")", 20, 200);
    ctl (gf.kind, "SubMonth", "text", "=\"month \" & Format(Sum([Amount]), \"0\") & \" n=\" & Count(*)", 0, 300);
    ctl (pf.kind, "Pg", "text", "=\"Page \" & [Page] & \" of \" & [Pages]", 0, 200);
    ctl (rf.kind, "Grand", "text", "=\"grand \" & Format(Sum([Amount]), \"0\") & \" avg \" & Format(Avg([Amount]), \"0.0\")", 0, 300);
    var back = ReportDef.from_json ("Banded", r.to_json ());
    ok (back.designed && back.sections.size == 9 && back.controls.size == r.controls.size && back.groups[0].interval == "month", "banded json");
    ok (back.controls[6].running_sum == "group" && back.controls[5].format == "0.00" && back.controls[4].hide_duplicates, "banded control json");
    var renderer = new ReportRenderer ();
    var pages = renderer.layout (r, ReportEngine.open_source (db, r));
    var texts = every_text (pages);
    ok (pages.size >= 2, "banded pages %d".printf (pages.size));
    ok (texts.contains ("January 2025"), "month interval header");
    ok (texts.contains ("Reps A") && texts.contains ("Reps B"), "prefix interval header");
    double total = 0;
    foreach (var t in new string[] {}) total += 0;
    total = 0;
    for (int i = 0; i < 120; i++) total += 10 + i;
    ok (texts.contains ("grand %.0f avg %.1f".printf (total, total / 120).replace (",", ".")), "report footer aggregates");
    ok (texts.contains ("Page 1 of %d".printf (pages.size)) && texts.contains ("Page %d of %d".printf (pages.size, pages.size)), "page of pages");
    int month_footers = 0;
    foreach (string t in texts) if (t.has_prefix ("month ") && t.contains (" n=120")) month_footers++;
    string mf = "";
    foreach (string t in texts) if (t.has_prefix ("month ")) mf += t + "|";
    ok (month_footers == 1, "all sales in january group once: " + mf);
    ok (texts.contains ("10") && texts.contains ("22"), "running sum restarts per group");
    int ada = 0;
    foreach (string t in texts) if (t == "Ada") ada++;
    int a_groups = 0;
    foreach (string t in texts) if (t == "Reps A") a_groups++;
    ok (ada == a_groups && ada < 60, "hide duplicates shows the rep once per group (%d of %d)".printf (ada, a_groups));
    bool red = false;
    foreach (var p in pages) foreach (var it in p.items) if (it.text == "big" && it.color == "#c01c28") red = true;
    ok (red, "conditional formatting in report");
    var sub = new ReportDef ();
    sub.name = "SubUnits";
    sub.source = "Sales";
    sub.designed = true;
    var sd = sub.ensure_section ("detail", 12);
    var su = new ReportControl ();
    su.section = sd.kind;
    su.name = "U";
    su.source = "=\"unit \" & [Units]";
    su.w = 100;
    sub.controls.add (su);
    db.save_object_meta ("x", "report:", "SubUnits", sub.to_json ());
    var main = new ReportDef ();
    main.name = "Main";
    main.source = "SELECT DISTINCT Rep FROM Sales";
    main.designed = true;
    var md = main.ensure_section ("detail", 14);
    var mr = new ReportControl ();
    mr.section = md.kind;
    mr.name = "R";
    mr.source = "Rep";
    main.controls.add (mr);
    var sr = new ReportControl ();
    sr.section = md.kind;
    sr.kind = "subreport";
    sr.name = "Child";
    sr.subreport = "SubUnits";
    sr.link_master = "Rep";
    sr.link_child = "Rep";
    sr.x = 40;
    main.controls.add (sr);
    var mp = renderer.layout (main, ReportEngine.open_source (db, main));
    var mt = every_text (mp);
    int units = 0;
    foreach (string t in mt) if (t.has_prefix ("unit ")) units++;
    ok (mt.contains ("Ada") && mt.contains ("Bob") && units == 120, "subreport rows linked %d".printf (units));
    var conv = ReportDesign.convert (base_def (), db.load_table ("Sales"));
    ok (conv.designed && conv.section ("page-footer") != null && conv.find_control ("PageNumber") != null, "convert generated layout to design");
    var cp = renderer.layout (conv, ReportEngine.open_source (db, conv));
    ok (cp.size >= 1 && every_text (cp).contains ("Sales Report"), "converted report renders");
    string pdf = tmp_path ("banded.pdf");
    ReportRenderer.export_pdf (pages, pdf, "Banded");
    ok (FileUtils.test (pdf, FileTest.EXISTS), "banded pdf");
    ok (ReportDocument.build (pages, "Banded").to_html ().contains ("January 2025"), "banded html export");
}

int find (uint8[] hay, string needle, int from) {
    int n = needle.length;
    for (int i = from; i + n <= hay.length; i++) {
        bool m = true;
        for (int k = 0; k < n; k++) {
            if (hay[i + k] != needle[k]) {
                m = false;
                break;
            }
        }
        if (m) return i;
    }
    return -1;
}

void test_rich_text () throws Error {
    var db = Database.memory ();
    var t = new TableDef ("Notes");
    var id = t.add_field ("ID", FieldType.AUTONUMBER);
    id.primary_key = true;
    var body = t.add_field ("Body", FieldType.LONG_TEXT);
    body.rich_text = true;
    db.create_table (t);
    db.run ("INSERT INTO Notes (Body) VALUES (?)", { new DbValue.text ("<div>Call <strong>Ada</strong> about <em>invoices</em></div>") });
    var r = new ReportDef ();
    r.name = "Notes";
    r.source = "Notes";
    r.title = "Notes";
    r.columns.add (new ReportColumn ("Body", "Body"));
    var pages = run (db, r);
    string markup = "";
    string text = "";
    foreach (var p in pages) {
        foreach (var it in p.items) {
            if (it.markup != "") {
                markup = it.markup;
                text = it.text;
            }
        }
    }
    ok (markup.contains ("<b>Ada</b>") && markup.contains ("<i>invoices</i>"), "rich text field keeps bold and italic in the report: " + markup);
    ok (text == "Call Ada about invoices", "rich text field plain text for export: " + text);
    var renderer = new ReportRenderer ();
    var real = renderer.layout (r, ReportEngine.open_source (db, r));
    var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, 600, 800);
    var cr = new Cairo.Context (surface);
    cr.set_source_rgb (1, 1, 1);
    cr.paint ();
    ReportRenderer.draw_page (cr, real[0], 1.0);
    string? shot = Environment.get_variable ("SDB_REPORT_SHOT");
    if (shot != null) surface.write_to_png (shot);
    ok (true, "rich text report page draws");
}

void test_form_print (Database db) throws Error {
    var form = FormDef.generate (db, "Sales", FormLayout.COLUMNAR);
    form.title = "Sales Entry";
    var r = ReportDesign.from_form (form, db.load_table ("Sales"));
    ok (r.designed && r.section ("detail") != null, "form print becomes a designed report");
    var src = ReportEngine.open_source (db, r);
    var timer = new Timer ();
    var pages = new ReportRenderer ().layout (r, src);
    double secs = timer.elapsed ();
    ok (pages.size >= 10, "form print has a block per record: %d pages".printf (pages.size));
    ok (secs < 5, "form print lays out 120 records quickly: %.2fs".printf (secs));
    var texts = new Gee.ArrayList<string> ();
    foreach (var it in pages[0].items) texts.add (it.text);
    ok (texts.contains ("Sales Entry"), "form title printed");
    ok (texts.contains ("Region") && texts.contains ("North"), "form labels and values printed");
    bool page_no = false;
    foreach (string t in texts) {
        if (t.has_prefix ("Page 1 of")) page_no = true;
    }
    ok (page_no, "form print page numbers");
    string? shot = Environment.get_variable ("SDB_FORM_SHOT");
    if (shot != null) {
        var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, (int) pages[0].width, (int) pages[0].height);
        var cr = new Cairo.Context (surface);
        cr.set_source_rgb (1, 1, 1);
        cr.paint ();
        ReportRenderer.draw_page (cr, pages[0], 1.0);
        surface.write_to_png (shot);
    }
}

int main (string[] args) {
    Locale.set_default (Locale.neutral ());
    try {
        var db = sample ();
        test_tabular (db);
        test_nested_and_breaks (db);
        test_filters_and_empty (db);
        test_layouts (db);
        test_json_and_generate (db);
        test_pdf (db);
        test_exports (db);
        test_banded (db);
        test_rich_text ();
        test_form_print (db);
    } catch (Error e) {
        stderr.printf ("FAIL: unexpected error: %s\n", e.message);
        return 1;
    }
    print ("report: %d checks passed\n", checks);
    return 0;
}
