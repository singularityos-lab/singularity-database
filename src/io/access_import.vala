namespace Singularity.Apps.Database {

    public class AccessObjectImport {
        private static string event_key (string prop) {
            string p = prop;
            if (p.has_prefix ("On")) p = p.substring (2);
            if (p == "DblClick" || p == "Click" || p == "Current" || p == "Load" || p == "Open" || p == "Close" || p == "Unload" || p == "Delete" || p == "Dirty" || p == "Change" || p == "GotFocus" || p == "LostFocus" || p == "Format" || p == "NoData") return p;
            return p;
        }

        private static string handler (string value) {
            string v = value.strip ();
            if (v.has_prefix ("\"") && v.has_suffix ("\"")) v = AccessText.unquote (v);
            return v;
        }

        private static string source_of (string record_source) {
            string s = handler (record_source).strip ();
            while (s.has_suffix (";")) s = s.substring (0, s.length - 1).strip ();
            return s;
        }

        private static int px (int twips) {
            return (int) Math.round (twips / 15.0);
        }

        private static double pt (int twips) {
            return twips / 20.0;
        }

        private static string color (AccessTextNode n, string key) {
            string? v = n.get (key);
            if (v == null) return "";
            int64 c;
            if (!int64.try_parse (v.strip (), out c) || c < 0) return "";
            return Styling_hex (c);
        }

        private static string Styling_hex (int64 c) {
            return "#%02x%02x%02x".printf ((int) (c & 255), (int) ((c >> 8) & 255), (int) ((c >> 16) & 255));
        }

        private static ControlKind form_kind (string kind) {
            switch (kind) {
                case "Label": return ControlKind.LABEL;
                case "CommandButton": return ControlKind.BUTTON;
                case "ComboBox": return ControlKind.COMBO;
                case "ListBox": return ControlKind.LIST;
                case "CheckBox": return ControlKind.CHECK;
                case "OptionGroup": return ControlKind.OPTION_GROUP;
                case "ToggleButton": return ControlKind.TOGGLE;
                case "Image": return ControlKind.IMAGE;
                case "Line": return ControlKind.LINE;
                case "Rectangle": return ControlKind.RECTANGLE;
                case "Subform": return ControlKind.SUBFORM;
                case "Tab": return ControlKind.TAB;
                case "Chart": return ControlKind.CHART;
                default: return ControlKind.AUTO;
            }
        }

        public static FormDef convert_form (AccessTextObject obj, string name) {
            var f = new FormDef ();
            f.name = name;
            var root = obj.root;
            f.source = source_of (root.text ("RecordSource"));
            if (f.source.down ().has_prefix ("select ")) f.source = AccessSql.statement (f.source);
            f.title = handler (root.text ("Caption", name));
            if (f.title == "") f.title = name;
            switch (root.get_int ("DefaultView", 0)) {
                case 1: f.default_view = "continuous"; break;
                case 2: f.default_view = "datasheet"; break;
                case 5: f.default_view = "split"; break;
                default: f.default_view = "single"; break;
            }
            f.allow_add = root.get_bool ("AllowAdditions", true);
            f.allow_edit = root.get_bool ("AllowEdits", true);
            f.allow_delete = root.get_bool ("AllowDeletions", true);
            f.data_entry = root.get_bool ("DataEntry", false);
            f.filter = handler (root.text ("Filter"));
            f.filter_on_load = root.get_bool ("FilterOnLoad", false);
            f.sort = handler (root.text ("OrderBy"));
            f.navigation_buttons = root.get_bool ("NavigationButtons", true);
            foreach (string ev in root.events ()) f.events[event_key (ev)] = handler (root.text (ev));
            f.code = obj.code;
            foreach (var sec in root.sections ()) {
                string sk = sec.section_kind ();
                string section = sk == "FormHeader" ? "header" : (sk == "FormFooter" ? "footer" : "detail");
                if (sk == "PageHeader" || sk == "PageFooter") continue;
                int h = px (sec.get_int ("Height", 0));
                if (section == "header") f.header_height = h;
                if (section == "footer") f.footer_height = h;
                foreach (var n in sec.controls ()) {
                    if (n.kind == "Page") continue;
                    var cont = n.container ();
                    if (n.kind == "Label" && cont != null && !cont.is_section () && cont.kind != "Page" && cont.kind != "OptionGroup") continue;
                    var c = new FormControl ("", "");
                    c.kind = form_kind (n.kind);
                    c.name = n.name;
                    c.section = section;
                    c.x = px (n.get_int ("Left"));
                    c.y = px (n.get_int ("Top"));
                    c.width = int.max (8, px (n.get_int ("Width", 1440)));
                    c.height = int.max (4, px (n.get_int ("Height", 300)));
                    string cs = handler (n.text ("ControlSource"));
                    c.field = cs;
                    c.caption = handler (n.text ("Caption"));
                    c.format = handler (n.text ("Format"));
                    c.input_mask = handler (n.text ("InputMask"));
                    c.default_value = handler (n.text ("DefaultValue"));
                    c.validation_rule = handler (n.text ("ValidationRule"));
                    c.validation_text = handler (n.text ("ValidationText"));
                    c.row_source = handler (n.text ("RowSource"));
                    c.bound_column = n.get_int ("BoundColumn", 1);
                    c.column_count = n.get_int ("ColumnCount", 1);
                    c.visible = n.get_bool ("Visible", true);
                    c.enabled = n.get_bool ("Enabled", true);
                    c.read_only = n.get_bool ("Locked", false);
                    c.tab_index = n.get_int ("TabIndex", -1);
                    c.fore_color = color (n, "ForeColor");
                    c.bold = n.get_int ("FontWeight", 400) >= 600;
                    c.italic = n.get_bool ("FontItalic", false);
                    c.font_size = n.get_int ("FontSize", 0);
                    c.status_text = handler (n.text ("StatusBarText"));
                    if (c.kind == ControlKind.SUBFORM) {
                        string so = handler (n.text ("SourceObject"));
                        if (so.has_prefix ("Form.")) so = so.substring (5);
                        c.subform = so;
                        c.link_master = handler (n.text ("LinkMasterFields"));
                        c.link_child = handler (n.text ("LinkChildFields"));
                    }
                    if (c.kind == ControlKind.TAB) {
                        string[] pages = {};
                        foreach (var p in n.controls ()) {
                            if (p.kind == "Page" && p.container () == n) pages += handler (p.text ("Caption", p.name)) != "" ? handler (p.text ("Caption", p.name)) : p.name;
                        }
                        c.pages = pages;
                    }
                    if (cont != null && cont.kind == "Page") {
                        var tab = cont.container ();
                        if (tab != null) {
                            int idx = 0;
                            int k = 0;
                            foreach (var p in tab.controls ()) {
                                if (p.kind != "Page" || p.container () != tab) continue;
                                if (p == cont) idx = k;
                                k++;
                            }
                            c.parent = "%s:%d".printf (tab.name, idx);
                            c.x = int.max (0, c.x - px (cont.get_int ("Left")));
                            c.y = int.max (0, c.y - px (cont.get_int ("Top")));
                        }
                    }
                    foreach (var child in n.children) {
                        if (child.kind == "Label") {
                            c.label = handler (child.text ("Caption"));
                            int ly = px (child.get_int ("Top"));
                            if (ly < c.y) {
                                c.height += c.y - ly;
                                c.y = ly;
                            }
                        }
                    }
                    if (c.kind == ControlKind.LABEL) c.label = "";
                    if (c.kind.is_bound_kind () && c.label == "" && c.kind != ControlKind.BUTTON) c.hide_label = true;
                    foreach (string ev in n.events ()) c.events[event_key (ev)] = handler (n.text (ev));
                    if (c.kind == ControlKind.AUTO && n.kind != "TextBox" && n.kind != "BoundObjectFrame" && n.kind != "Attachment") c.kind = ControlKind.TEXT;
                    f.controls.add (c);
                }
            }
            f.name_controls ();
            return f;
        }

        public static ReportDef convert_report (AccessTextObject obj, string name) {
            var r = new ReportDef ();
            r.name = name;
            r.designed = true;
            var root = obj.root;
            r.source = source_of (root.text ("RecordSource"));
            if (r.source.down ().has_prefix ("select ")) r.source = AccessSql.statement (r.source);
            r.title = handler (root.text ("Caption", name));
            r.code = obj.code;
            foreach (string ev in root.events ()) r.events[event_key (ev)] = handler (root.text (ev));
            foreach (var g in root.children) {
                if (!g.is_group ()) continue;
                foreach (var c in g.children) {
                    if (c.kind != "BreakLevel") continue;
                    var grp = new ReportGroup (handler (c.text ("ControlSource")));
                    grp.descending = c.get_bool ("SortOrder", false);
                    grp.header = c.get_bool ("GroupHeader", false);
                    grp.footer = c.get_bool ("GroupFooter", false);
                    grp.keep_together = c.get_int ("KeepTogether", 0) > 0;
                    grp.interval_size = int.max (1, c.get_int ("GroupInterval", 1));
                    switch (c.get_int ("GroupOn", 0)) {
                        case 1: grp.interval = "prefix"; break;
                        case 2: grp.interval = "year"; break;
                        case 3: grp.interval = "quarter"; break;
                        case 4: grp.interval = "month"; break;
                        case 5: grp.interval = "week"; break;
                        case 6: grp.interval = "day"; break;
                        case 7: grp.interval = "hour"; break;
                        case 9: grp.interval = "interval"; break;
                        default: grp.interval = "each"; break;
                    }
                    if (grp.field.has_prefix ("=")) grp.interval = "each";
                    r.groups.add (grp);
                }
            }
            int header_seq = 0, footer_seq = 0;
            var header_groups = new Gee.ArrayList<int> ();
            var footer_groups = new Gee.ArrayList<int> ();
            for (int i = 0; i < r.groups.size; i++) {
                if (r.groups[i].header) header_groups.add (i);
                if (r.groups[i].footer) footer_groups.add (i);
            }
            foreach (var sec in root.sections ()) {
                string sk = sec.section_kind ();
                string kind;
                switch (sk) {
                    case "ReportHeader": kind = "report-header"; break;
                    case "ReportFooter": kind = "report-footer"; break;
                    case "PageHeader": kind = "page-header"; break;
                    case "PageFooter": kind = "page-footer"; break;
                    case "GroupHeader":
                        int gi = header_seq < header_groups.size ? header_groups[header_seq] : header_seq;
                        header_seq++;
                        kind = "group-header:%d".printf (gi);
                        break;
                    case "GroupFooter":
                        int gf = footer_seq < footer_groups.size ? footer_groups[footer_seq] : footer_seq;
                        footer_seq++;
                        kind = "group-footer:%d".printf (gf);
                        break;
                    default: kind = "detail"; break;
                }
                var s = r.ensure_section (kind, (int) pt (sec.get_int ("Height", 0)));
                s.visible = sec.get_bool ("Visible", true);
                s.can_grow = sec.get_bool ("CanGrow", false) || kind == "detail";
                s.keep_together = sec.get_bool ("KeepTogether", true);
                int fnp = sec.get_int ("ForceNewPage", 0);
                s.new_page_before = fnp == 1 || fnp == 3;
                s.new_page_after = fnp == 2 || fnp == 3;
                s.back_color = color (sec, "BackColor");
                if (s.back_color == "#ffffff") s.back_color = "";
                string of = handler (sec.text ("OnFormat"));
                if (of != "") s.on_format = of;
                foreach (var n in sec.controls ()) {
                    var c = new ReportControl ();
                    c.section = kind;
                    c.name = n.name;
                    switch (n.kind) {
                        case "Label": c.kind = "label"; break;
                        case "CheckBox": c.kind = "checkbox"; break;
                        case "Image":
                        case "BoundObjectFrame":
                        case "Attachment": c.kind = "image"; break;
                        case "Line": c.kind = "line"; break;
                        case "Rectangle": c.kind = "rectangle"; break;
                        case "PageBreak": c.kind = "pagebreak"; break;
                        case "Subform":
                        case "Subreport": c.kind = "subreport"; break;
                        case "Chart": c.kind = "chart"; break;
                        default: c.kind = "text"; break;
                    }
                    c.x = pt (n.get_int ("Left"));
                    c.y = pt (n.get_int ("Top"));
                    c.w = double.max (2, pt (n.get_int ("Width", 1440)));
                    c.h = double.max (2, pt (n.get_int ("Height", 300)));
                    c.source = handler (n.text ("ControlSource"));
                    c.caption = handler (n.text ("Caption"));
                    c.format = handler (n.text ("Format"));
                    int fs = n.get_int ("FontSize", 0);
                    if (fs > 0) c.font_size = fs;
                    c.bold = n.get_int ("FontWeight", 400) >= 600;
                    c.italic = n.get_bool ("FontItalic", false);
                    c.fore = color (n, "ForeColor");
                    if (c.fore == "#000000") c.fore = "";
                    switch (n.get_int ("TextAlign", 0)) {
                        case 2: c.align = "center"; break;
                        case 3: c.align = "right"; break;
                        default: c.align = "left"; break;
                    }
                    int rs = n.get_int ("RunningSum", 0);
                    c.running_sum = rs == 1 ? "group" : (rs == 2 ? "all" : "no");
                    c.hide_duplicates = n.get_bool ("HideDuplicates", false);
                    c.can_grow = n.get_bool ("CanGrow", false);
                    c.visible = n.get_bool ("Visible", true);
                    if (c.kind == "subreport") {
                        string so = handler (n.text ("SourceObject"));
                        if (so.has_prefix ("Report.")) so = so.substring (7);
                        c.subreport = so;
                        c.link_master = handler (n.text ("LinkMasterFields"));
                        c.link_child = handler (n.text ("LinkChildFields"));
                    }
                    r.controls.add (c);
                }
            }
            ReportDesign.order_sections (r);
            return r;
        }

        public static MacroItem convert_step (AccessMacroStep s) {
            var it = new MacroItem (s.kind, s.name);
            it.condition = s.condition;
            it.comment = s.comment;
            if (s.kind == "submacro" || s.kind == "group") it.name = s.name;
            if (s.kind == "submacro" || s.kind == "group") it.action = "";
            foreach (var e in s.arguments.entries) it.args[e.key] = e.value;
            foreach (var c in s.children) it.children.add (convert_step (c));
            return it;
        }

        public static MacroDef convert_macro (Gee.List<AccessMacroStep> steps, string name) {
            var m = new MacroDef ();
            m.name = name;
            foreach (var s in steps) m.items.add (convert_step (s));
            return m;
        }

        private static string base_name (string path) {
            string b = Path.get_basename (path);
            int dot = b.last_index_of (".");
            return dot > 0 ? b.substring (0, dot) : b;
        }

        public static ImportResult import_file (Database db, string path) throws Error {
            uint8[] raw;
            FileUtils.get_data (path, out raw);
            string text = AccessText.decode (raw);
            string low = path.down ();
            var result = new ImportResult ();
            string name = base_name (path);
            if (low.has_suffix (".bas") || low.has_suffix (".cls")) {
                var obj = AccessText.parse_object (text);
                string mname = obj.name != "" ? obj.name : name;
                string code = obj.code != "" ? obj.code : text;
                if (mname.has_prefix ("Form_") && db.get_meta ("form:" + mname.substring (5)) != null) {
                    var f = FormDef.from_json (mname.substring (5), db.get_meta ("form:" + mname.substring (5)));
                    f.code = code;
                    db.save_object_meta (_("Import Code"), "form:", f.name, f.to_json ());
                    result.table = f.name;
                    result.notes.add (_("The code was attached to the form \"%s\".").printf (f.name));
                    return result;
                }
                if (mname.has_prefix ("Report_") && db.get_meta ("report:" + mname.substring (7)) != null) {
                    var rp = ReportDef.from_json (mname.substring (7), db.get_meta ("report:" + mname.substring (7)));
                    rp.code = code;
                    db.save_object_meta (_("Import Code"), "report:", rp.name, rp.to_json ());
                    result.table = rp.name;
                    return result;
                }
                ScriptParser.parse_module (code, mname);
                var b = new Json.Builder ();
                b.begin_object ();
                b.set_member_name ("code").add_string_value (code);
                b.end_object ();
                db.save_object_meta (_("Import Module"), "module:", mname, Json.to_string (b.get_root (), false));
                result.table = mname;
                return result;
            }
            if (low.has_suffix (".macro") || text.contains ("<UserInterfaceMacro") || text.contains ("<AccessMacro")) {
                var steps = AccessText.parse_macro (text);
                var m = convert_macro (steps, name);
                db.save_object_meta (_("Import Macro"), "macro:", name, m.to_json ());
                result.table = name;
                int unknown = 0;
                foreach (var it in m.items) {
                    if (it.kind == "action" && MacroCatalog.find (it.action) == null) unknown++;
                }
                if (unknown > 0) result.notes.add (ngettext ("%d action has no equivalent and will report an error when it runs.", "%d actions have no equivalent and will report an error when they run.", unknown).printf (unknown));
                return result;
            }
            var obj = AccessText.parse_object (text);
            string oname = obj.name != "" ? obj.name : name;
            if (obj.kind == "form") {
                var f = convert_form (obj, oname);
                db.save_object_meta (_("Import Form"), "form:", oname, f.to_json ());
                result.table = oname;
                result.imported = f.controls.size;
                if (f.code.strip () != "") {
                    try {
                        ScriptParser.parse_module (f.code, "Form_" + oname);
                    } catch (Error e) {
                        result.notes.add (_("The form code has parts this database cannot run: %s").printf (e.message));
                    }
                }
                return result;
            }
            if (obj.kind == "report") {
                var r = convert_report (obj, oname);
                db.save_object_meta (_("Import Report"), "report:", oname, r.to_json ());
                result.table = oname;
                result.imported = r.controls.size;
                return result;
            }
            if (obj.kind == "query") {
                string sql = obj.root.text ("SQL", obj.code);
                SavedQueries.save (db, oname, Transfer.translate_access_query (sql));
                result.table = oname;
                return result;
            }
            throw new SchemaError.INVALID (_("The file is not an exported Access form, report, macro or module."));
        }
    }
}
