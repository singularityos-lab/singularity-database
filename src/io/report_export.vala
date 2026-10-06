namespace Singularity.Apps.Database {

    public class RCell {
        public int column;
        public int span = 1;
        public string text;
        public ReportAlign align;

        public RCell (int column, string text, ReportAlign align) {
            this.column = column;
            this.text = text;
            this.align = align;
        }
    }

    public class RLine {
        public TextRole role;
        public Gee.ArrayList<RCell> cells = new Gee.ArrayList<RCell> ();
        public bool page_start;

        public RLine (TextRole role) {
            this.role = role;
        }

        public string joined () {
            string[] t = {};
            foreach (var c in cells) t += c.text;
            return string.joinv (" ", t);
        }
    }

    public class ReportDocument {
        public string title = "";
        public string subtitle = "";
        public double[] column_x = {};
        public Gee.ArrayList<RLine> lines = new Gee.ArrayList<RLine> ();
        public bool landscape;
        public double page_width = 595.28;
        public double page_height = 841.89;

        public int columns {
            get { return int.max (1, column_x.length); }
        }

        public static ReportDocument build (Gee.List<LayoutPage> pages, string title = "") {
            var doc = new ReportDocument ();
            doc.title = title;
            if (pages.size > 0) {
                doc.page_width = pages[0].width;
                doc.page_height = pages[0].height;
                doc.landscape = pages[0].width > pages[0].height;
            }
            var xs = new Gee.TreeMap<int, int> ();
            foreach (var p in pages) {
                foreach (var it in p.items) {
                    if (it.kind != ItemKind.TEXT) continue;
                    if (it.role == TextRole.BODY || it.role == TextRole.COLUMN_HEADER) {
                        int key = (int) Math.round (it.x);
                        xs[key] = (xs.has_key (key) ? xs[key] : 0) + 1;
                    }
                }
            }
            double[] cols = {};
            foreach (var e in xs.entries) {
                if (cols.length > 0 && e.key - cols[cols.length - 1] < 4) continue;
                cols += e.key;
            }
            doc.column_x = cols;
            bool first_page = true;
            foreach (var p in pages) {
                var rows = new Gee.TreeMap<int, Gee.ArrayList<PageItem>> ();
                foreach (var it in p.items) {
                    if (it.kind != ItemKind.TEXT || it.text == "") continue;
                    if (it.role == TextRole.FOOTER) continue;
                    if (!first_page && it.role == TextRole.COLUMN_HEADER) continue;
                    if (it.role == TextRole.TITLE && doc.title == "") doc.title = it.text;
                    if (it.role == TextRole.TITLE) continue;
                    if (it.role == TextRole.SUBTITLE) {
                        doc.subtitle = it.text;
                        continue;
                    }
                    int y = (int) Math.round (it.y);
                    int key = y;
                    foreach (int k in rows.keys) {
                        if ((k - y).abs () <= 2) key = k;
                    }
                    if (!rows.has_key (key)) rows[key] = new Gee.ArrayList<PageItem> ();
                    rows[key].add (it);
                }
                bool first_line = true;
                foreach (var e in rows.entries) {
                    var items = e.value;
                    items.sort ((a, b) => a.x < b.x ? -1 : (a.x > b.x ? 1 : 0));
                    var role = items[0].role;
                    foreach (var it in items) {
                        if (it.role == TextRole.GROUP_HEADER || it.role == TextRole.GRAND_TOTAL || it.role == TextRole.SUBTOTAL) role = it.role;
                    }
                    var line = new RLine (role);
                    line.page_start = first_line && !first_page;
                    first_line = false;
                    foreach (var it in items) {
                        int c = doc.column_for (it.x);
                        if (it.role == TextRole.FIELD_LABEL || it.role == TextRole.GROUP_HEADER) c = line.cells.size == 0 ? 0 : c;
                        line.cells.add (new RCell (c, it.text, it.align));
                    }
                    for (int k = 0; k < line.cells.size; k++) {
                        int next = k + 1 < line.cells.size ? line.cells[k + 1].column : doc.columns;
                        line.cells[k].span = int.max (1, next - line.cells[k].column);
                    }
                    doc.lines.add (line);
                }
                first_page = false;
            }
            return doc;
        }

        public int column_for (double x) {
            int best = 0;
            for (int i = 0; i < column_x.length; i++) {
                if (x + 3 >= column_x[i]) best = i;
            }
            return best;
        }

        private static string esc (string s) {
            return Markup.escape_text (s);
        }

        public string to_html () {
            var sb = new StringBuilder ();
            sb.append ("<!DOCTYPE html>\n<html>\n<head>\n<meta charset=\"utf-8\">\n");
            sb.append ("<title>%s</title>\n".printf (esc (title)));
            sb.append ("<style>body{font-family:sans-serif;margin:24px;color:#15171c}h1{font-size:20pt;color:#1a3869;margin:0}p.sub{color:#61666f}table{border-collapse:collapse;width:100%}th{background:#e8edf5;text-align:left;padding:4px 6px;border-bottom:1px solid #999}td{padding:3px 6px;border-bottom:1px solid #e5e5e5}tr.group td{font-weight:bold;color:#1a3869;padding-top:10px}tr.total td{font-weight:bold;background:#f3f5f9}tr.grand td{font-weight:bold;background:#e8edf5}.r{text-align:right}.c{text-align:center}</style>\n");
            sb.append ("</head>\n<body>\n");
            if (title != "") sb.append ("<h1>%s</h1>\n".printf (esc (title)));
            if (subtitle != "") sb.append ("<p class=\"sub\">%s</p>\n".printf (esc (subtitle)));
            sb.append ("<table>\n");
            foreach (var l in lines) {
                string cls = "";
                string tag = "td";
                switch (l.role) {
                    case TextRole.COLUMN_HEADER: tag = "th"; break;
                    case TextRole.GROUP_HEADER: cls = " class=\"group\""; break;
                    case TextRole.SUBTOTAL: cls = " class=\"total\""; break;
                    case TextRole.GRAND_TOTAL: cls = " class=\"grand\""; break;
                    default: break;
                }
                sb.append ("<tr%s>".printf (cls));
                int col = 0;
                foreach (var c in l.cells) {
                    if (c.column > col) sb.append ("<%s colspan=\"%d\"></%s>".printf (tag, c.column - col, tag));
                    string align = c.align == ReportAlign.RIGHT ? " class=\"r\"" : (c.align == ReportAlign.CENTER ? " class=\"c\"" : "");
                    string span = c.span > 1 ? " colspan=\"%d\"".printf (c.span) : "";
                    sb.append ("<%s%s%s>%s</%s>".printf (tag, span, align, esc (c.text).replace ("\n", "<br>"), tag));
                    col = c.column + c.span;
                }
                if (col < columns) sb.append ("<%s colspan=\"%d\"></%s>".printf (tag, columns - col, tag));
                sb.append ("</tr>\n");
            }
            sb.append ("</table>\n</body>\n</html>\n");
            return sb.str;
        }

        public DataTable to_table () {
            var dt = new DataTable (title != "" ? title : _("Report"));
            string[] cols = {};
            bool header = false;
            foreach (var l in lines) {
                if (l.role == TextRole.COLUMN_HEADER) {
                    string[] h = new string[columns];
                    for (int i = 0; i < columns; i++) h[i] = "";
                    foreach (var c in l.cells) h[c.column] = c.text;
                    cols = h;
                    header = true;
                    break;
                }
            }
            if (!header) {
                cols = new string[columns];
                for (int i = 0; i < columns; i++) cols[i] = _("Column %d").printf (i + 1);
            }
            dt.columns = cols;
            foreach (var l in lines) {
                if (l.role == TextRole.COLUMN_HEADER) continue;
                DbValue[] vals = new DbValue[columns];
                for (int i = 0; i < columns; i++) vals[i] = new DbValue.null ();
                foreach (var c in l.cells) {
                    double d = 0;
                    string raw = c.text;
                    bool num = c.align == ReportAlign.RIGHT && !raw.contains ("/") && Codec.parse_number (raw, out d);
                    if (num) vals[c.column] = new DbValue.real (d);
                    else vals[c.column] = new DbValue.text (raw);
                }
                dt.add_row ((owned) vals);
            }
            return dt;
        }

        public uint8[] to_docx () throws Error {
            var z = new ZipWriter ();
            z.add_text ("[Content_Types].xml", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/><Override PartName=\"/docProps/core.xml\" ContentType=\"application/vnd.openxmlformats-package.core-properties+xml\"/></Types>");
            z.add_text ("_rels/.rels", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties\" Target=\"docProps/core.xml\"/></Relationships>");
            z.add_text ("docProps/core.xml", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<cp:coreProperties xmlns:cp=\"http://schemas.openxmlformats.org/package/2006/metadata/core-properties\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\"><dc:title>%s</dc:title><dc:creator>Singularity Database</dc:creator></cp:coreProperties>".printf (esc (title)));
            var sb = new StringBuilder ();
            sb.append ("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body>");
            if (title != "") sb.append ("<w:p><w:pPr><w:spacing w:after=\"120\"/></w:pPr><w:r><w:rPr><w:b/><w:color w:val=\"1A3869\"/><w:sz w:val=\"40\"/></w:rPr><w:t xml:space=\"preserve\">%s</w:t></w:r></w:p>".printf (esc (title)));
            if (subtitle != "") sb.append ("<w:p><w:r><w:rPr><w:color w:val=\"61666F\"/></w:rPr><w:t xml:space=\"preserve\">%s</w:t></w:r></w:p>".printf (esc (subtitle)));
            double usable = page_width * 20 - 2 * 1134;
            int colw = (int) (usable / columns);
            sb.append ("<w:tbl><w:tblPr><w:tblW w:w=\"%d\" w:type=\"dxa\"/><w:tblBorders><w:insideH w:val=\"single\" w:sz=\"2\" w:color=\"DDDDDD\"/></w:tblBorders></w:tblPr><w:tblGrid>".printf ((int) usable));
            for (int i = 0; i < columns; i++) sb.append ("<w:gridCol w:w=\"%d\"/>".printf (colw));
            sb.append ("</w:tblGrid>");
            foreach (var l in lines) {
                bool bold = l.role == TextRole.COLUMN_HEADER || l.role == TextRole.GROUP_HEADER || l.role == TextRole.SUBTOTAL || l.role == TextRole.GRAND_TOTAL;
                string shade = l.role == TextRole.COLUMN_HEADER || l.role == TextRole.GRAND_TOTAL ? "E8EDF5" : (l.role == TextRole.SUBTOTAL ? "F3F5F9" : "");
                sb.append ("<w:tr>");
                if (l.role == TextRole.COLUMN_HEADER) sb.append ("<w:trPr><w:tblHeader/></w:trPr>");
                int col = 0;
                foreach (var c in l.cells) {
                    if (c.column > col) {
                        sb.append (docx_cell ("", c.column - col, colw, false, shade, ReportAlign.LEFT));
                    }
                    sb.append (docx_cell (c.text, c.span, colw, bold, shade, c.align));
                    col = c.column + c.span;
                }
                if (col < columns) sb.append (docx_cell ("", columns - col, colw, false, shade, ReportAlign.LEFT));
                sb.append ("</w:tr>");
            }
            sb.append ("</w:tbl>");
            int pw = (int) (page_width * 20), ph = (int) (page_height * 20);
            sb.append ("<w:sectPr><w:pgSz w:w=\"%d\" w:h=\"%d\"%s/><w:pgMar w:top=\"1134\" w:right=\"1134\" w:bottom=\"1134\" w:left=\"1134\" w:header=\"567\" w:footer=\"567\" w:gutter=\"0\"/></w:sectPr>".printf (pw, ph, landscape ? " w:orient=\"landscape\"" : ""));
            sb.append ("</w:body></w:document>");
            z.add_text ("word/document.xml", sb.str);
            return z.finish ();
        }

        private static string docx_cell (string text, int span, int colw, bool bold, string shade, ReportAlign align) {
            var sb = new StringBuilder ("<w:tc><w:tcPr>");
            sb.append ("<w:tcW w:w=\"%d\" w:type=\"dxa\"/>".printf (colw * span));
            if (span > 1) sb.append ("<w:gridSpan w:val=\"%d\"/>".printf (span));
            if (shade != "") sb.append ("<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"%s\"/>".printf (shade));
            sb.append ("</w:tcPr><w:p>");
            if (align == ReportAlign.RIGHT) sb.append ("<w:pPr><w:jc w:val=\"right\"/></w:pPr>");
            else if (align == ReportAlign.CENTER) sb.append ("<w:pPr><w:jc w:val=\"center\"/></w:pPr>");
            string[] parts = text.split ("\n");
            for (int i = 0; i < parts.length; i++) {
                sb.append ("<w:r>");
                if (bold) sb.append ("<w:rPr><w:b/></w:rPr>");
                if (i > 0) sb.append ("<w:br/>");
                sb.append ("<w:t xml:space=\"preserve\">%s</w:t></w:r>".printf (esc (parts[i])));
            }
            sb.append ("</w:p></w:tc>");
            return sb.str;
        }

        public uint8[] to_odt () throws Error {
            var z = new ZipWriter ();
            z.add_text ("mimetype", "application/vnd.oasis.opendocument.text", false);
            z.add_text ("META-INF/manifest.xml", "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<manifest:manifest xmlns:manifest=\"urn:oasis:names:tc:opendocument:xmlns:manifest:1.0\" manifest:version=\"1.3\"><manifest:file-entry manifest:full-path=\"/\" manifest:version=\"1.3\" manifest:media-type=\"application/vnd.oasis.opendocument.text\"/><manifest:file-entry manifest:full-path=\"content.xml\" manifest:media-type=\"text/xml\"/><manifest:file-entry manifest:full-path=\"styles.xml\" manifest:media-type=\"text/xml\"/><manifest:file-entry manifest:full-path=\"meta.xml\" manifest:media-type=\"text/xml\"/></manifest:manifest>");
            z.add_text ("meta.xml", "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<office:document-meta xmlns:office=\"urn:oasis:names:tc:opendocument:xmlns:office:1.0\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:meta=\"urn:oasis:names:tc:opendocument:xmlns:meta:1.0\" office:version=\"1.3\"><office:meta><dc:title>%s</dc:title><meta:generator>Singularity Database</meta:generator></office:meta></office:document-meta>".printf (esc (title)));
            string pw = "%.2fpt".printf (page_width).replace (",", "."), ph = "%.2fpt".printf (page_height).replace (",", ".");
            z.add_text ("styles.xml", "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<office:document-styles xmlns:office=\"urn:oasis:names:tc:opendocument:xmlns:office:1.0\" xmlns:style=\"urn:oasis:names:tc:opendocument:xmlns:style:1.0\" xmlns:fo=\"urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0\" office:version=\"1.3\"><office:automatic-styles><style:page-layout style:name=\"pm1\"><style:page-layout-properties fo:page-width=\"%s\" fo:page-height=\"%s\" style:print-orientation=\"%s\" fo:margin-top=\"2cm\" fo:margin-bottom=\"2cm\" fo:margin-left=\"2cm\" fo:margin-right=\"2cm\"/></style:page-layout></office:automatic-styles><office:master-styles><style:master-page style:name=\"Standard\" style:page-layout-name=\"pm1\"/></office:master-styles></office:document-styles>".printf (pw, ph, landscape ? "landscape" : "portrait"));
            var sb = new StringBuilder ();
            sb.append ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<office:document-content xmlns:office=\"urn:oasis:names:tc:opendocument:xmlns:office:1.0\" xmlns:style=\"urn:oasis:names:tc:opendocument:xmlns:style:1.0\" xmlns:text=\"urn:oasis:names:tc:opendocument:xmlns:text:1.0\" xmlns:table=\"urn:oasis:names:tc:opendocument:xmlns:table:1.0\" xmlns:fo=\"urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0\" office:version=\"1.3\">");
            sb.append ("<office:automatic-styles><style:style style:name=\"Title\" style:family=\"paragraph\"><style:text-properties fo:font-size=\"20pt\" fo:font-weight=\"bold\" fo:color=\"#1a3869\"/></style:style><style:style style:name=\"Sub\" style:family=\"paragraph\"><style:text-properties fo:color=\"#61666f\"/></style:style><style:style style:name=\"B\" style:family=\"paragraph\"><style:text-properties fo:font-weight=\"bold\"/></style:style><style:style style:name=\"R\" style:family=\"paragraph\"><style:paragraph-properties fo:text-align=\"end\"/></style:style><style:style style:name=\"BR\" style:family=\"paragraph\"><style:paragraph-properties fo:text-align=\"end\"/><style:text-properties fo:font-weight=\"bold\"/></style:style><style:style style:name=\"H\" style:family=\"table-cell\"><style:table-cell-properties fo:background-color=\"#e8edf5\" fo:padding=\"0.05cm\" fo:border-bottom=\"0.5pt solid #999999\"/></style:style><style:style style:name=\"T\" style:family=\"table-cell\"><style:table-cell-properties fo:background-color=\"#f3f5f9\" fo:padding=\"0.05cm\"/></style:style><style:style style:name=\"C\" style:family=\"table-cell\"><style:table-cell-properties fo:padding=\"0.05cm\" fo:border-bottom=\"0.5pt solid #e5e5e5\"/></style:style></office:automatic-styles>");
            sb.append ("<office:body><office:text>");
            if (title != "") sb.append ("<text:p text:style-name=\"Title\">%s</text:p>".printf (esc (title)));
            if (subtitle != "") sb.append ("<text:p text:style-name=\"Sub\">%s</text:p>".printf (esc (subtitle)));
            sb.append ("<table:table table:name=\"Report\"><table:table-column table:number-columns-repeated=\"%d\"/>".printf (columns));
            bool in_header = false;
            foreach (var l in lines) {
                bool bold = l.role == TextRole.COLUMN_HEADER || l.role == TextRole.GROUP_HEADER || l.role == TextRole.SUBTOTAL || l.role == TextRole.GRAND_TOTAL;
                string cell_style = l.role == TextRole.COLUMN_HEADER || l.role == TextRole.GRAND_TOTAL ? "H" : (l.role == TextRole.SUBTOTAL ? "T" : "C");
                if (l.role == TextRole.COLUMN_HEADER && !in_header) {
                    sb.append ("<table:table-header-rows>");
                    in_header = true;
                }
                sb.append ("<table:table-row>");
                int col = 0;
                foreach (var c in l.cells) {
                    if (c.column > col) {
                        for (int k = col; k < c.column; k++) sb.append ("<table:table-cell table:style-name=\"%s\"/>".printf (cell_style));
                    }
                    string ps = c.align == ReportAlign.RIGHT ? (bold ? "BR" : "R") : (bold ? "B" : "");
                    sb.append ("<table:table-cell table:style-name=\"%s\" office:value-type=\"string\"%s>".printf (cell_style, c.span > 1 ? " table:number-columns-spanned=\"%d\"".printf (c.span) : ""));
                    foreach (string part in c.text.split ("\n")) sb.append ("<text:p%s>%s</text:p>".printf (ps != "" ? " text:style-name=\"%s\"".printf (ps) : "", esc (part)));
                    sb.append ("</table:table-cell>");
                    for (int k = 1; k < c.span; k++) sb.append ("<table:covered-table-cell/>");
                    col = c.column + c.span;
                }
                for (int k = col; k < columns; k++) sb.append ("<table:table-cell table:style-name=\"%s\"/>".printf (cell_style));
                sb.append ("</table:table-row>");
                if (l.role == TextRole.COLUMN_HEADER && in_header) {
                    sb.append ("</table:table-header-rows>");
                    in_header = false;
                }
            }
            sb.append ("</table:table></office:text></office:body></office:document-content>");
            z.add_text ("content.xml", sb.str);
            return z.finish ();
        }

        public void save (string path) throws Error {
            string low = path.down ();
            if (low.has_suffix (".html") || low.has_suffix (".htm")) FileUtils.set_contents (path, to_html ());
            else if (low.has_suffix (".docx")) FileUtils.set_data (path, to_docx ());
            else if (low.has_suffix (".odt")) FileUtils.set_data (path, to_odt ());
            else if (low.has_suffix (".xlsx")) {
                var list = new Gee.ArrayList<DataTable> ();
                list.add (to_table ());
                Xlsx.save (list, path);
            } else if (low.has_suffix (".csv")) Csv.save (to_table (), path, ',');
            else throw new SchemaError.INVALID (_("This file type is not supported."));
        }
    }
}
