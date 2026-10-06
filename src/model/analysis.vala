namespace Singularity.Apps.Database {

    public class DbObjectRef {
        public string kind;
        public string name;

        public DbObjectRef (string kind, string name) {
            this.kind = kind;
            this.name = name;
        }

        public string key () {
            return kind + ":" + name;
        }
    }

    public class Dependencies {
        private Database db;
        private Gee.HashMap<string, Gee.ArrayList<DbObjectRef>> uses = new Gee.HashMap<string, Gee.ArrayList<DbObjectRef>> ();

        public Dependencies (Database db) {
            this.db = db;
            build ();
        }

        private Gee.ArrayList<DbObjectRef> all_objects () {
            var list = new Gee.ArrayList<DbObjectRef> ();
            foreach (string t in db.table_names ()) list.add (new DbObjectRef ("table", t));
            foreach (string q in db.view_names ()) list.add (new DbObjectRef ("query", q));
            foreach (string q in db.object_names ("action:")) list.add (new DbObjectRef ("query", q));
            foreach (string f in db.object_names ("form:")) list.add (new DbObjectRef ("form", f));
            foreach (string r in db.object_names ("report:")) list.add (new DbObjectRef ("report", r));
            foreach (string m in db.object_names ("macro:")) list.add (new DbObjectRef ("macro", m));
            foreach (string m in db.object_names ("module:")) list.add (new DbObjectRef ("module", m));
            return list;
        }

        private static bool mentions (string text, string name) {
            if (text == "") return false;
            string low = text.casefold ();
            string n = name.casefold ();
            if (low.contains ("\"" + n + "\"") || low.contains ("[" + n + "]") || low.contains ("'" + n + "'") || low.contains ("`" + n + "`")) return true;
            if (n.contains (" ")) return false;
            try {
                var re = new Regex ("(^|[^A-Za-z0-9_])" + Regex.escape_string (n) + "($|[^A-Za-z0-9_])", RegexCompileFlags.CASELESS);
                return re.match (low);
            } catch (RegexError e) {
                return false;
            }
        }

        private string text_of (DbObjectRef o) {
            switch (o.kind) {
                case "query":
                    var q = SavedQueries.load (db, o.name);
                    return q != null ? q.sql : "";
                case "form":
                    return db.get_meta ("form:" + o.name) ?? "";
                case "report":
                    return db.get_meta ("report:" + o.name) ?? "";
                case "macro":
                    return db.get_meta ("macro:" + o.name) ?? "";
                case "module":
                    return db.get_meta ("module:" + o.name) ?? "";
                case "table":
                    var sb = new StringBuilder ();
                    try {
                        var def = db.load_table (o.name);
                        foreach (var r in def.effective_relationships ()) sb.append ("\"%s\" ".printf (r.ref_table));
                        foreach (var f in def.fields) {
                            if (f.field_type == FieldType.LOOKUP) sb.append ("\"%s\" ".printf (f.lookup_table));
                        }
                    } catch (Error e) {
                    }
                    return sb.str;
            }
            return "";
        }

        private void build () {
            var objs = all_objects ();
            foreach (var o in objs) {
                string text = text_of (o);
                var list = new Gee.ArrayList<DbObjectRef> ();
                foreach (var other in objs) {
                    if (other.key () == o.key ()) continue;
                    if (other.kind == "module" || (other.kind == "macro" && o.kind != "form" && o.kind != "report" && o.kind != "macro")) continue;
                    if (mentions (text, other.name)) list.add (other);
                }
                uses[o.key ()] = list;
            }
        }

        public Gee.ArrayList<DbObjectRef> used_by (string kind, string name) {
            return uses[kind + ":" + name] ?? new Gee.ArrayList<DbObjectRef> ();
        }

        public Gee.ArrayList<DbObjectRef> depending_on (string kind, string name) {
            var list = new Gee.ArrayList<DbObjectRef> ();
            foreach (var e in uses.entries) {
                foreach (var r in e.value) {
                    if (r.kind == kind && r.name == name) {
                        int c = e.key.index_of (":");
                        list.add (new DbObjectRef (e.key.substring (0, c), e.key.substring (c + 1)));
                    }
                }
            }
            return list;
        }
    }

    public class AnalyzerItem {
        public string severity;
        public string object_name;
        public string message;
        public string fix_sql = "";

        public AnalyzerItem (string severity, string object_name, string message) {
            this.severity = severity;
            this.object_name = object_name;
            this.message = message;
        }
    }

    public class PerformanceAnalyzer {
        public static Gee.ArrayList<AnalyzerItem> run (Database db) {
            var items = new Gee.ArrayList<AnalyzerItem> ();
            foreach (string t in db.table_names ()) {
                TableDef def;
                try {
                    def = db.load_table (t);
                } catch (Error e) {
                    continue;
                }
                if (db.is_linked (t)) continue;
                if (def.primary_key ().size == 0) items.add (new AnalyzerItem ("recommendation", t, _("\"%s\" has no primary key. A key makes records easy to find and relate.").printf (t)));
                var indexed_first = new Gee.HashSet<string> ();
                foreach (var ix in def.indexes) if (ix.columns.length > 0) indexed_first.add (ix.columns[0].casefold ());
                foreach (var f in def.fields) {
                    if (f.primary_key || f.unique || f.indexed) indexed_first.add (f.name.casefold ());
                }
                foreach (var r in def.effective_relationships ()) {
                    if (r.columns.length == 0 || indexed_first.contains (r.columns[0].casefold ())) continue;
                    var it = new AnalyzerItem ("recommendation", t, _("Index \"%s\" in \"%s\": it links to \"%s\" and is used in joins.").printf (r.columns[0], t, r.ref_table));
                    it.fix_sql = "CREATE INDEX %s ON %s (%s)".printf (Sql.quote_ident ("idx_%s_%s".printf (t, r.columns[0])), Sql.quote_ident (t), Sql.quote_ident (r.columns[0]));
                    items.add (it);
                    indexed_first.add (r.columns[0].casefold ());
                }
                int64 rows = db.count_rows (t);
                foreach (var f in def.fields) {
                    if (f.field_type != FieldType.TEXT || f.primary_key || rows < 20) continue;
                    try {
                        int64 distinct = db.query_int ("SELECT count(DISTINCT %s) FROM %s".printf (Sql.quote_ident (f.name), Sql.quote_ident (t)));
                        if (distinct > 0 && distinct <= 12 && rows >= 20 * distinct) items.add (new AnalyzerItem ("idea", t, _("\"%s\" repeats only %lld different values: a lookup table or a choice list would keep them consistent.").printf (f.name, distinct)));
                    } catch (Error e) {
                    }
                }
                if (def.fields.size > 60) items.add (new AnalyzerItem ("idea", t, _("\"%s\" has %d fields. Splitting it into related tables is usually easier to maintain.").printf (t, def.fields.size)));
            }
            foreach (string q in db.view_names ()) {
                var sq = SavedQueries.load (db, q);
                if (sq == null) continue;
                try {
                    var plan = db.query ("EXPLAIN QUERY PLAN SELECT * FROM %s".printf (Sql.quote_ident (q)));
                    foreach (var r in plan.rows) {
                        string detail = r.get (r.values.length - 1).to_string ();
                        if (detail.has_prefix ("SCAN ") && !detail.contains ("USING") && detail.contains (" ") && plan.rows.size > 1) {
                            items.add (new AnalyzerItem ("idea", q, _("The query \"%s\" reads every row of %s. An index on the joined or filtered fields can speed it up.").printf (q, detail.substring (5))));
                            break;
                        }
                    }
                } catch (Error e) {
                    items.add (new AnalyzerItem ("recommendation", q, _("The query \"%s\" does not run: %s").printf (q, e.message)));
                }
            }
            try {
                var fk = db.query ("PRAGMA foreign_key_check");
                if (fk.rows.size > 0) items.add (new AnalyzerItem ("recommendation", "", ngettext ("%d record breaks a relationship.", "%d records break relationships.", fk.rows.size).printf (fk.rows.size)));
            } catch (Error e) {
            }
            return items;
        }
    }

    public class Documenter {
        private static bool want (string[] kinds, string k) {
            foreach (string x in kinds) if (x == k) return true;
            return false;
        }

        private static void put (Database d, ref int seq, string kind, string obj, string section, string item, string detail) throws Error {
            seq++;
            d.run ("INSERT INTO Documentation VALUES (?, ?, ?, ?, ?, ?)", { new DbValue.int (seq), new DbValue.text (kind), new DbValue.text (obj), new DbValue.text (section), new DbValue.text (item), new DbValue.text (detail) });
        }

        public static ReportDef build (Database db, string[] kinds, out Database doc_db) throws Error {
            doc_db = Database.memory ();
            doc_db.exec ("CREATE TABLE Documentation (Seq INTEGER PRIMARY KEY, Kind TEXT, Object TEXT, Section TEXT, Item TEXT, Detail TEXT)");
            int seq = 0;
            if (want (kinds, "table")) {
                foreach (string t in db.table_names ()) {
                    var def = db.load_table (t);
                    put (doc_db, ref seq, _("Table"), t, _("Properties"), _("Records"), db.count_rows (t).to_string ());
                    if (def.description != "") put (doc_db, ref seq, _("Table"), t, _("Properties"), _("Description"), def.description);
                    if (def.link_path != "") put (doc_db, ref seq, _("Table"), t, _("Properties"), _("Linked To"), def.link_path);
                    if (def.validation_rule != "") put (doc_db, ref seq, _("Table"), t, _("Properties"), _("Validation Rule"), def.validation_rule);
                    foreach (var f in def.fields) {
                        string[] props = { f.is_calculated () ? _("Calculated: %s").printf (f.expression) : f.field_type.label () };
                        if (f.primary_key) props += _("Primary Key");
                        if (f.required) props += _("Required");
                        if (f.unique) props += _("Unique");
                        if (f.indexed) props += _("Indexed");
                        if (f.max_length > 0) props += _("Size %d").printf (f.max_length);
                        if (f.default_value != "") props += _("Default %s").printf (f.default_value);
                        if (f.format != "") props += _("Format %s").printf (f.format);
                        if (f.input_mask != "") props += _("Input Mask %s").printf (f.input_mask);
                        if (f.caption != "") props += _("Caption %s").printf (f.caption);
                        if (f.validation_rule != "" || f.validation != "") props += _("Validation %s").printf (f.validation_rule != "" ? f.validation_rule : f.validation);
                        if (f.multi_value) props += _("Multiple Values");
                        if (f.field_type == FieldType.CHOICE) props += string.joinv (", ", f.choices);
                        if (f.field_type == FieldType.LOOKUP) props += _("Lookup %s.%s").printf (f.lookup_table, f.lookup_field);
                        if (f.description != "") props += f.description;
                        put (doc_db, ref seq, _("Table"), t, _("Fields"), f.name, string.joinv ("; ", props));
                    }
                    foreach (var ix in def.indexes) put (doc_db, ref seq, _("Table"), t, _("Indexes"), ix.name, (ix.unique ? _("Unique: ") : "") + string.joinv (", ", ix.columns));
                    foreach (var r in def.effective_relationships ()) put (doc_db, ref seq, _("Table"), t, _("Relationships"), "%s > %s".printf (string.joinv (", ", r.columns), r.ref_table), string.joinv (", ", r.ref_columns) + (r.enforce ? "; " + _("Enforced") : ""));
                    foreach (var e in DataMacros.load (db, t).entries) put (doc_db, ref seq, _("Table"), t, _("Data Macros"), DataMacros.event_label (e.key), ngettext ("%d action", "%d actions", e.value.items.size).printf (e.value.items.size));
                }
            }
            if (want (kinds, "query")) {
                var names = db.view_names ();
                names.add_all (db.object_names ("action:"));
                foreach (string q in names) {
                    var sq = SavedQueries.load (db, q);
                    if (sq == null) continue;
                    put (doc_db, ref seq, _("Query"), q, _("Properties"), _("Type"), sq.kind);
                    put (doc_db, ref seq, _("Query"), q, _("SQL"), "", sq.sql);
                    foreach (var p in QueryPrep.find_parameters (db, sq.sql)) put (doc_db, ref seq, _("Query"), q, _("Parameters"), p.name, p.type_name);
                }
            }
            if (want (kinds, "form")) {
                foreach (string f in db.object_names ("form:")) {
                    var fd = FormDef.from_json (f, db.get_meta ("form:" + f));
                    if (fd == null) continue;
                    put (doc_db, ref seq, _("Form"), f, _("Properties"), _("Record Source"), fd.source);
                    put (doc_db, ref seq, _("Form"), f, _("Properties"), _("Default View"), fd.default_view);
                    foreach (var e in fd.events.entries) put (doc_db, ref seq, _("Form"), f, _("Events"), e.key, e.value.has_prefix ("{") ? _("[Embedded Macro]") : e.value);
                    foreach (var c in fd.controls) {
                        string detail = "%s; %s".printf (c.kind.label (), c.field != "" ? c.field : _("Unbound"));
                        foreach (var e in c.events.entries) detail += "; %s: %s".printf (e.key, e.value.has_prefix ("{") ? _("[Embedded Macro]") : e.value);
                        put (doc_db, ref seq, _("Form"), f, _("Controls"), c.display_name (), detail);
                    }
                    if (fd.code.strip () != "") put (doc_db, ref seq, _("Form"), f, _("Code"), "", fd.code);
                }
            }
            if (want (kinds, "report")) {
                foreach (string r in db.object_names ("report:")) {
                    var rd = ReportDef.from_json (r, db.get_meta ("report:" + r));
                    if (rd == null) continue;
                    put (doc_db, ref seq, _("Report"), r, _("Properties"), _("Record Source"), rd.source);
                    foreach (var g in rd.groups) put (doc_db, ref seq, _("Report"), r, _("Grouping"), g.field, g.interval_label ());
                    foreach (var c in rd.controls) put (doc_db, ref seq, _("Report"), r, _("Controls"), c.name, "%s; %s".printf (c.kind, c.kind == "label" ? c.caption : c.source));
                    foreach (var c in rd.columns) put (doc_db, ref seq, _("Report"), r, _("Columns"), c.label, c.field);
                }
            }
            if (want (kinds, "macro")) {
                foreach (string m in db.object_names ("macro:")) {
                    var md = MacroDef.from_json (m, db.get_meta ("macro:" + m));
                    if (md == null) continue;
                    int k = 0;
                    foreach (var it in md.items) {
                        string args = "";
                        foreach (var e in it.args.entries) if (e.value != "") args += "%s=%s; ".printf (e.key, e.value);
                        put (doc_db, ref seq, _("Macro"), m, _("Actions"), "%d. %s".printf (++k, it.kind == "action" ? it.action : it.kind), (it.condition != "" ? _("If %s: ").printf (it.condition) : "") + args);
                    }
                }
            }
            if (want (kinds, "module")) {
                foreach (string m in db.object_names ("module:")) {
                    var o = Meta.parse_object (db.get_meta ("module:" + m));
                    string code = o != null ? o.get_string_member_with_default ("code", "") : "";
                    try {
                        var mod = ScriptParser.parse_module (code, m);
                        foreach (var p in mod.procedures) put (doc_db, ref seq, _("Module"), m, _("Procedures"), p.name, "%s%s".printf (p.kind == "function" ? "Function" : "Sub", p.is_public ? "" : " (Private)"));
                    } catch (Error e) {
                        put (doc_db, ref seq, _("Module"), m, _("Procedures"), _("Error"), e.message);
                    }
                }
            }
            var r = new ReportDef ();
            r.name = _("Database Documenter");
            r.source = "Documentation";
            r.title = _("Database Documenter");
            r.subtitle = db.display_name ();
            var c1 = new ReportColumn ("Section", _("Section"));
            c1.width = 1;
            var c2 = new ReportColumn ("Item", _("Item"));
            c2.width = 1.3;
            var c3 = new ReportColumn ("Detail", _("Detail"));
            c3.width = 3;
            r.columns.add (c1);
            r.columns.add (c2);
            r.columns.add (c3);
            var g1 = new ReportGroup ("Kind");
            g1.footer = false;
            var g2 = new ReportGroup ("Object");
            g2.footer = false;
            r.groups.add (g1);
            r.groups.add (g2);
            r.state.sorts.add (new SortSpec ("Seq", false));
            r.show_count = false;
            r.grand_total = false;
            r.landscape = true;
            return r;
        }
    }
}
