namespace Singularity.Apps.Database {

    public class TemplateInfo {
        public string id;
        public string title;
        public string description;
        public string icon;
        public string color;

        public TemplateInfo (string id, string title, string description, string icon, string color) {
            this.id = id;
            this.title = title;
            this.description = description;
            this.icon = icon;
            this.color = color;
        }
    }

    public class Templates {
        public static Gee.ArrayList<TemplateInfo> list () {
            var l = new Gee.ArrayList<TemplateInfo> ();
            l.add (new TemplateInfo ("contacts", _("Contacts"), _("People and companies with categories and birthdays"), "dev.sinty.contacts", "#2a78d6"));
            l.add (new TemplateInfo ("inventory", _("Inventory"), _("Products, suppliers, stock levels and movements"), "x-office-inventory", "#1baf7a"));
            l.add (new TemplateInfo ("tasks", _("Tasks"), _("Projects and tasks with status, priority and due dates"), "dev.sinty.tasks", "#eb6834"));
            l.add (new TemplateInfo ("invoices", _("Invoices"), _("Customers, invoices and invoice lines with totals"), "x-office-invoice", "#8b5cf6"));
            return l;
        }

        private static string day (int offset) {
            return new DateTime.now_local ().add_days (offset).format ("%Y-%m-%d");
        }

        private static Field field (TableDef t, string name, FieldType type) {
            return t.add_field (name, type);
        }

        private static TableDef table (string name) {
            var t = new TableDef (name);
            var id = t.add_field ("ID", FieldType.AUTONUMBER);
            id.primary_key = true;
            return t;
        }

        private static Field lookup (TableDef t, string name, string target, string display) {
            var f = t.add_field (name, FieldType.LOOKUP);
            f.lookup_table = target;
            f.lookup_field = "ID";
            f.lookup_display = display;
            f.indexed = true;
            return f;
        }

        private static Field choice (TableDef t, string name, string[] items, string def = "") {
            var f = t.add_field (name, FieldType.CHOICE);
            f.choices = items;
            f.default_value = def;
            return f;
        }

        private static void rows (Database db, string table, string[] cols, DbValue[,] data) throws Error {
            string[] q = {};
            string[] ph = {};
            foreach (string c in cols) {
                q += Sql.quote_ident (c);
                ph += "?";
            }
            var stmt = "INSERT INTO %s (%s) VALUES (%s)".printf (Sql.quote_ident (table), string.joinv (", ", q), string.joinv (", ", ph));
            for (int r = 0; r < data.length[0]; r++) {
                DbValue[] args = new DbValue[cols.length];
                for (int c = 0; c < cols.length; c++) args[c] = data[r, c];
                db.run (stmt, args);
            }
        }

        private static DbValue t (string s) {
            return new DbValue.text (s);
        }

        private static DbValue i (int64 v) {
            return new DbValue.int (v);
        }

        private static DbValue r (double v) {
            return new DbValue.real (v);
        }

        private static DbValue n () {
            return new DbValue.null ();
        }

        private static void save_form (Database db, FormDef f) throws Error {
            db.set_meta ("form:" + f.name, f.to_json ());
        }

        private static void save_report (Database db, ReportDef r) throws Error {
            db.set_meta ("report:" + r.name, r.to_json ());
        }

        public static void build (Database db, string id) throws Error {
            db.set_meta ("template", id);
            switch (id) {
                case "contacts": contacts (db); break;
                case "inventory": inventory (db); break;
                case "tasks": tasks (db); break;
                case "invoices": invoices (db); break;
                default: throw new SchemaError.NOT_FOUND (_("Unknown template."));
            }
            db.clear_history ();
            db.invalidate ();
        }

        private static void contacts (Database db) throws Error {
            var co = table (_("Companies"));
            field (co, _("Name"), FieldType.TEXT).required = true;
            choice (co, _("Industry"), { _("Technology"), _("Retail"), _("Health"), _("Education"), _("Finance"), _("Other") }, _("Other"));
            field (co, _("Website"), FieldType.URL);
            field (co, _("Phone"), FieldType.PHONE);
            field (co, _("City"), FieldType.TEXT);
            db.create_table (co);
            var c = table (_("Contacts"));
            field (c, _("First Name"), FieldType.TEXT).required = true;
            field (c, _("Last Name"), FieldType.TEXT).indexed = true;
            lookup (c, _("Company"), _("Companies"), _("Name"));
            field (c, _("Email"), FieldType.EMAIL);
            field (c, _("Phone"), FieldType.PHONE);
            field (c, _("Birthday"), FieldType.DATE);
            choice (c, _("Category"), { _("Family"), _("Friend"), _("Work"), _("Customer"), _("Supplier") }, _("Work"));
            field (c, _("Favorite"), FieldType.BOOLEAN).default_value = "0";
            field (c, _("Notes"), FieldType.LONG_TEXT);
            field (c, _("Photo"), FieldType.ATTACHMENT);
            db.create_table (c);
            rows (db, co.name, { co.fields[1].name, co.fields[2].name, co.fields[3].name, co.fields[4].name, co.fields[5].name }, {
                { t ("Northwind Labs"), t (_("Technology")), t ("https://northwind.example"), t ("+39 02 5550 1100"), t ("Milano") },
                { t ("Blue Harbor Foods"), t (_("Retail")), t ("https://blueharbor.example"), t ("+39 06 5550 2200"), t ("Roma") },
                { t ("Clinica Aurora"), t (_("Health")), t ("https://aurora.example"), t ("+39 011 5550 3300"), t ("Torino") },
                { t ("Studio Vela"), t (_("Other")), n (), t ("+39 055 5550 4400"), t ("Firenze") }
            });
            string[] cc = { c.fields[1].name, c.fields[2].name, c.fields[3].name, c.fields[4].name, c.fields[5].name, c.fields[6].name, c.fields[7].name, c.fields[8].name, c.fields[9].name };
            rows (db, c.name, cc, {
                { t ("Ada"), t ("Ferri"), i (1), t ("ada.ferri@northwind.example"), t ("+39 333 100 2001"), t (day (-10000)), t (_("Work")), i (1), t (_("Leads the data team.")) },
                { t ("Luca"), t ("Bianchi"), i (1), t ("luca.bianchi@northwind.example"), t ("+39 333 100 2002"), t (day (-12040)), t (_("Work")), i (0), n () },
                { t ("Sara"), t ("Conti"), i (2), t ("sara@blueharbor.example"), t ("+39 333 100 2003"), t (day (-9100)), t (_("Customer")), i (1), t (_("Prefers email.")) },
                { t ("Marco"), t ("Rossi"), i (3), t ("m.rossi@aurora.example"), t ("+39 333 100 2004"), t (day (-15000)), t (_("Supplier")), i (0), n () },
                { t ("Giulia"), t ("Moretti"), n (), t ("giulia.moretti@mail.example"), t ("+39 333 100 2005"), t (day (-8000)), t (_("Friend")), i (1), n () },
                { t ("Paolo"), t ("Greco"), n (), t ("paolo.greco@mail.example"), t ("+39 333 100 2006"), t (day (-20000)), t (_("Family")), i (0), t (_("Uncle.")) },
                { t ("Elena"), t ("Galli"), i (4), t ("elena@studiovela.example"), t ("+39 333 100 2007"), t (day (-11000)), t (_("Customer")), i (0), n () },
                { t ("Davide"), t ("Costa"), i (2), t ("davide@blueharbor.example"), t ("+39 333 100 2008"), t (day (-10500)), t (_("Work")), i (0), n () }
            });
            db.save_query (new QueryDef (_("Favorite Contacts"), "SELECT %s, %s, %s, %s FROM %s WHERE %s = 1 ORDER BY %s".printf (
                Sql.quote_ident (cc[0]), Sql.quote_ident (cc[1]), Sql.quote_ident (cc[3]), Sql.quote_ident (cc[4]), Sql.quote_ident (c.name), Sql.quote_ident (cc[7]), Sql.quote_ident (cc[1]))));
            var views = ViewDef.load_all (db, c.name);
            var kb = new ViewDef (_("By Category"), ViewKind.KANBAN);
            kb.group_field = cc[6];
            kb.pick_defaults (db.load_table (c.name));
            kb.title_field = cc[0];
            views.add (kb);
            var gal = new ViewDef (_("Cards"), ViewKind.GALLERY);
            gal.pick_defaults (db.load_table (c.name));
            gal.title_field = cc[0];
            views.add (gal);
            db.set_meta ("views:" + c.name, ViewDef.to_json_all (views));
            var form = FormDef.generate (db, c.name, FormLayout.TWO_COLUMNS);
            form.name = _("Contact Details");
            form.title = _("Contact Details");
            save_form (db, form);
            var cform = FormDef.generate (db, co.name);
            cform.name = _("Companies and People");
            cform.title = _("Companies and People");
            save_form (db, cform);
            var rep = new ReportDef ();
            rep.name = _("Contacts by Company");
            rep.source = c.name;
            rep.title = _("Contacts by Company");
            rep.columns.add (new ReportColumn (cc[0], cc[0]));
            rep.columns.add (new ReportColumn (cc[1], cc[1]));
            var em = new ReportColumn (cc[3], cc[3]);
            em.width = 2;
            rep.columns.add (em);
            rep.columns.add (new ReportColumn (cc[4], cc[4]));
            rep.groups.add (new ReportGroup (cc[2]));
            rep.state.sorts.add (new SortSpec (cc[1], false));
            save_report (db, rep);
        }

        private static void inventory (Database db) throws Error {
            var cat = table (_("Categories"));
            var cn = field (cat, _("Name"), FieldType.TEXT);
            cn.required = true;
            cn.unique = true;
            field (cat, _("Description"), FieldType.LONG_TEXT);
            db.create_table (cat);
            var sup = table (_("Suppliers"));
            field (sup, _("Name"), FieldType.TEXT).required = true;
            field (sup, _("Contact"), FieldType.TEXT);
            field (sup, _("Email"), FieldType.EMAIL);
            field (sup, _("Phone"), FieldType.PHONE);
            db.create_table (sup);
            var p = table (_("Products"));
            field (p, _("Name"), FieldType.TEXT).required = true;
            var sku = field (p, _("SKU"), FieldType.TEXT);
            sku.unique = true;
            sku.max_length = 16;
            lookup (p, _("Category"), cat.name, cn.name);
            lookup (p, _("Supplier"), sup.name, _("Name"));
            var price = field (p, _("Unit Price"), FieldType.CURRENCY);
            price.decimals = 2;
            price.validation = "%s >= 0".printf (Sql.quote_ident (price.name));
            field (p, _("In Stock"), FieldType.INTEGER).default_value = "0";
            field (p, _("Reorder Level"), FieldType.INTEGER).default_value = "5";
            field (p, _("Discontinued"), FieldType.BOOLEAN).default_value = "0";
            field (p, _("Photo"), FieldType.ATTACHMENT);
            db.create_table (p);
            var mv = table (_("Stock Movements"));
            var mp = lookup (mv, _("Product"), p.name, _("Name"));
            mp.required = true;
            field (mv, _("Date"), FieldType.DATE).default_value = "Date()";
            choice (mv, _("Kind"), { _("In"), _("Out") }, _("In"));
            field (mv, _("Quantity"), FieldType.INTEGER).required = true;
            field (mv, _("Note"), FieldType.TEXT);
            var rel = new Relationship (mv.name, mp.name, p.name, "ID");
            rel.on_delete = RefAction.CASCADE;
            mv.relationships.add (rel);
            db.create_table (mv);
            rows (db, cat.name, { cn.name, cat.fields[2].name }, {
                { t (_("Beverages")), t (_("Coffee, tea and soft drinks")) },
                { t (_("Snacks")), t (_("Biscuits, chips and bars")) },
                { t (_("Stationery")), t (_("Paper, pens and office supplies")) }
            });
            rows (db, sup.name, { sup.fields[1].name, sup.fields[2].name, sup.fields[3].name, sup.fields[4].name }, {
                { t ("Caffe Alpino"), t ("Anna Riva"), t ("orders@alpino.example"), t ("+39 0461 555 010") },
                { t ("Dolce Forno"), t ("Piero Sala"), t ("sales@dolceforno.example"), t ("+39 051 555 020") },
                { t ("Carta Viva"), t ("Irene Neri"), t ("hello@cartaviva.example"), t ("+39 049 555 030") }
            });
            string[] pc = { p.fields[1].name, p.fields[2].name, p.fields[3].name, p.fields[4].name, p.fields[5].name, p.fields[6].name, p.fields[7].name, p.fields[8].name };
            rows (db, p.name, pc, {
                { t (_("Espresso Beans 1 kg")), t ("BEV-001"), i (1), i (1), r (18.9), i (42), i (10), i (0) },
                { t (_("Green Tea 100 bags")), t ("BEV-002"), i (1), i (1), r (6.5), i (8), i (10), i (0) },
                { t (_("Sparkling Water 24 pack")), t ("BEV-003"), i (1), i (1), r (7.2), i (3), i (6), i (0) },
                { t (_("Butter Biscuits")), t ("SNK-001"), i (2), i (2), r (3.4), i (60), i (20), i (0) },
                { t (_("Hazelnut Bars")), t ("SNK-002"), i (2), i (2), r (1.2), i (15), i (25), i (0) },
                { t (_("Rice Crackers")), t ("SNK-003"), i (2), i (2), r (2.1), i (0), i (10), i (1) },
                { t (_("A4 Paper 500 sheets")), t ("STA-001"), i (3), i (3), r (5.9), i (120), i (30), i (0) },
                { t (_("Gel Pens 12 pack")), t ("STA-002"), i (3), i (3), r (9.5), i (4), i (5), i (0) },
                { t (_("Sticky Notes")), t ("STA-003"), i (3), i (3), r (2.8), i (33), i (10), i (0) }
            });
            string[] mc = { mv.fields[1].name, mv.fields[2].name, mv.fields[3].name, mv.fields[4].name, mv.fields[5].name };
            rows (db, mv.name, mc, {
                { i (1), t (day (-20)), t (_("In")), i (50), t (_("Initial stock")) },
                { i (1), t (day (-6)), t (_("Out")), i (8), n () },
                { i (2), t (day (-15)), t (_("In")), i (20), n () },
                { i (2), t (day (-2)), t (_("Out")), i (12), t (_("Office restock")) },
                { i (5), t (day (-9)), t (_("Out")), i (25), n () },
                { i (7), t (day (-30)), t (_("In")), i (150), n () },
                { i (7), t (day (-1)), t (_("Out")), i (30), n () }
            });
            db.save_query (new QueryDef (_("Products to Reorder"), "SELECT p.%s, p.%s, s.%s AS %s, p.%s, p.%s FROM %s AS p LEFT JOIN %s AS s ON s.\"ID\" = p.%s WHERE p.%s <= p.%s AND p.%s = 0 ORDER BY p.%s".printf (
                Sql.quote_ident (pc[0]), Sql.quote_ident (pc[1]), Sql.quote_ident (sup.fields[1].name), Sql.quote_ident (_("Supplier")), Sql.quote_ident (pc[5]), Sql.quote_ident (pc[6]),
                Sql.quote_ident (p.name), Sql.quote_ident (sup.name), Sql.quote_ident (pc[3]), Sql.quote_ident (pc[5]), Sql.quote_ident (pc[6]), Sql.quote_ident (pc[7]), Sql.quote_ident (pc[5]))));
            db.save_query (new QueryDef (_("Stock Value"), "SELECT c.%s AS %s, p.%s, p.%s, p.%s, p.%s * p.%s AS %s FROM %s AS p JOIN %s AS c ON c.\"ID\" = p.%s".printf (
                Sql.quote_ident (cn.name), Sql.quote_ident (_("Category")), Sql.quote_ident (pc[0]), Sql.quote_ident (pc[4]), Sql.quote_ident (pc[5]), Sql.quote_ident (pc[4]), Sql.quote_ident (pc[5]), Sql.quote_ident (_("Value")),
                Sql.quote_ident (p.name), Sql.quote_ident (cat.name), Sql.quote_ident (pc[2]))));
            var views = ViewDef.load_all (db, p.name);
            var gal = new ViewDef (_("Catalog"), ViewKind.GALLERY);
            gal.pick_defaults (db.load_table (p.name));
            gal.card_fields = { pc[1], pc[4], pc[5] };
            views.add (gal);
            var kb = new ViewDef (_("By Category"), ViewKind.KANBAN);
            kb.pick_defaults (db.load_table (p.name));
            kb.group_field = pc[2];
            kb.card_fields = { pc[1], pc[5] };
            views.add (kb);
            db.set_meta ("views:" + p.name, ViewDef.to_json_all (views));
            var form = FormDef.generate (db, p.name, FormLayout.TWO_COLUMNS);
            form.name = _("Product Card");
            form.title = _("Product Card");
            save_form (db, form);
            var rep = new ReportDef ();
            rep.name = _("Stock Value by Category");
            rep.source = _("Stock Value");
            rep.title = _("Stock Value by Category");
            rep.subtitle = _("Units in stock at their unit price");
            var c0 = new ReportColumn (pc[0], pc[0]);
            c0.width = 2.4;
            rep.columns.add (c0);
            rep.columns.add (new ReportColumn (pc[4], pc[4]));
            var qty = new ReportColumn (pc[5], pc[5]);
            qty.total = ReportTotal.SUM;
            rep.columns.add (qty);
            var val = new ReportColumn (_("Value"), _("Value"));
            val.total = ReportTotal.SUM;
            rep.columns.add (val);
            rep.groups.add (new ReportGroup (_("Category")));
            save_report (db, rep);
        }

        private static void tasks (Database db) throws Error {
            var pr = table (_("Projects"));
            field (pr, _("Name"), FieldType.TEXT).required = true;
            field (pr, _("Owner"), FieldType.TEXT);
            field (pr, _("Start"), FieldType.DATE);
            field (pr, _("Due"), FieldType.DATE);
            choice (pr, _("Status"), { _("Planned"), _("Active"), _("On Hold"), _("Completed") }, _("Planned"));
            db.create_table (pr);
            var tk = table (_("Tasks"));
            field (tk, _("Title"), FieldType.TEXT).required = true;
            var tp = lookup (tk, _("Project"), pr.name, _("Name"));
            field (tk, _("Assigned To"), FieldType.TEXT);
            choice (tk, _("Status"), { _("Not Started"), _("In Progress"), _("Blocked"), _("Done") }, _("Not Started"));
            choice (tk, _("Priority"), { _("Low"), _("Medium"), _("High") }, _("Medium"));
            field (tk, _("Due Date"), FieldType.DATE);
            var est = field (tk, _("Estimate Hours"), FieldType.NUMBER);
            est.decimals = 1;
            field (tk, _("Notes"), FieldType.LONG_TEXT);
            var rel = new Relationship (tk.name, tp.name, pr.name, "ID");
            rel.on_delete = RefAction.CASCADE;
            tk.relationships.add (rel);
            db.create_table (tk);
            rows (db, pr.name, { pr.fields[1].name, pr.fields[2].name, pr.fields[3].name, pr.fields[4].name, pr.fields[5].name }, {
                { t (_("Website Redesign")), t ("Ada"), t (day (-21)), t (day (20)), t (_("Active")) },
                { t (_("Spring Campaign")), t ("Luca"), t (day (-5)), t (day (40)), t (_("Active")) },
                { t (_("Office Move")), t ("Sara"), t (day (10)), t (day (70)), t (_("Planned")) }
            });
            string[] tc = { tk.fields[1].name, tk.fields[2].name, tk.fields[3].name, tk.fields[4].name, tk.fields[5].name, tk.fields[6].name, tk.fields[7].name };
            rows (db, tk.name, tc, {
                { t (_("Collect requirements")), i (1), t ("Ada"), t (_("Done")), t (_("High")), t (day (-14)), r (6) },
                { t (_("Wireframes")), i (1), t ("Luca"), t (_("Done")), t (_("Medium")), t (day (-7)), r (10) },
                { t (_("Visual design")), i (1), t ("Sara"), t (_("In Progress")), t (_("High")), t (day (3)), r (16) },
                { t (_("Build pages")), i (1), t ("Ada"), t (_("Not Started")), t (_("High")), t (day (12)), r (24) },
                { t (_("Content review")), i (1), t ("Giulia"), t (_("Blocked")), t (_("Medium")), t (day (5)), r (4) },
                { t (_("Choose channels")), i (2), t ("Luca"), t (_("In Progress")), t (_("Medium")), t (day (1)), r (3) },
                { t (_("Write copy")), i (2), t ("Giulia"), t (_("Not Started")), t (_("Low")), t (day (9)), r (8) },
                { t (_("Budget approval")), i (2), t ("Luca"), t (_("Not Started")), t (_("High")), t (day (6)), r (2) },
                { t (_("Find movers")), i (3), t ("Sara"), t (_("Not Started")), t (_("Medium")), t (day (18)), r (3) },
                { t (_("Plan desks")), i (3), t ("Sara"), t (_("Not Started")), t (_("Low")), t (day (25)), r (5) }
            });
            db.save_query (new QueryDef (_("Open Tasks"), "SELECT t.%s, p.%s AS %s, t.%s, t.%s, t.%s, t.%s FROM %s AS t JOIN %s AS p ON p.\"ID\" = t.%s WHERE t.%s <> %s ORDER BY t.%s".printf (
                Sql.quote_ident (tc[0]), Sql.quote_ident (pr.fields[1].name), Sql.quote_ident (_("Project")), Sql.quote_ident (tc[2]), Sql.quote_ident (tc[3]), Sql.quote_ident (tc[4]), Sql.quote_ident (tc[5]),
                Sql.quote_ident (tk.name), Sql.quote_ident (pr.name), Sql.quote_ident (tc[1]), Sql.quote_ident (tc[3]), Sql.quote_string (_("Done")), Sql.quote_ident (tc[5]))));
            var views = ViewDef.load_all (db, tk.name);
            var kb = new ViewDef (_("Board"), ViewKind.KANBAN);
            kb.pick_defaults (db.load_table (tk.name));
            kb.group_field = tc[3];
            kb.card_fields = { tc[1], tc[2], tc[4], tc[5] };
            views.add (kb);
            var cal = new ViewDef (_("Due Dates"), ViewKind.CALENDAR);
            cal.pick_defaults (db.load_table (tk.name));
            cal.date_field = tc[5];
            views.add (cal);
            db.set_meta ("views:" + tk.name, ViewDef.to_json_all (views));
            var form = FormDef.generate (db, pr.name);
            form.name = _("Project Overview");
            form.title = _("Project Overview");
            save_form (db, form);
            var rep = new ReportDef ();
            rep.name = _("Tasks by Project");
            rep.source = tk.name;
            rep.title = _("Tasks by Project");
            var c0 = new ReportColumn (tc[0], tc[0]);
            c0.width = 2.2;
            rep.columns.add (c0);
            rep.columns.add (new ReportColumn (tc[2], tc[2]));
            rep.columns.add (new ReportColumn (tc[3], tc[3]));
            rep.columns.add (new ReportColumn (tc[5], tc[5]));
            var hc = new ReportColumn (tc[6], tc[6]);
            hc.total = ReportTotal.SUM;
            rep.columns.add (hc);
            rep.groups.add (new ReportGroup (tc[1]));
            rep.state.sorts.add (new SortSpec (tc[5], false));
            save_report (db, rep);
        }

        private static void invoices (Database db) throws Error {
            var cu = table (_("Customers"));
            field (cu, _("Name"), FieldType.TEXT).required = true;
            field (cu, _("Email"), FieldType.EMAIL);
            field (cu, _("Address"), FieldType.LONG_TEXT);
            field (cu, _("City"), FieldType.TEXT);
            field (cu, _("Country"), FieldType.TEXT).default_value = _("Italy");
            db.create_table (cu);
            var inv = table (_("Invoices"));
            var num = field (inv, _("Number"), FieldType.TEXT);
            num.required = true;
            num.unique = true;
            var ic = lookup (inv, _("Customer"), cu.name, _("Name"));
            ic.required = true;
            field (inv, _("Date"), FieldType.DATE).default_value = "Date()";
            field (inv, _("Due Date"), FieldType.DATE);
            choice (inv, _("Status"), { _("Draft"), _("Sent"), _("Paid"), _("Overdue") }, _("Draft"));
            field (inv, _("Notes"), FieldType.LONG_TEXT);
            db.create_table (inv);
            var ln = table (_("Invoice Lines"));
            var li = lookup (ln, _("Invoice"), inv.name, _("Number"));
            li.required = true;
            field (ln, _("Description"), FieldType.TEXT).required = true;
            var q = field (ln, _("Quantity"), FieldType.NUMBER);
            q.default_value = "1";
            var up = field (ln, _("Unit Price"), FieldType.CURRENCY);
            up.decimals = 2;
            var tax = field (ln, _("Tax Rate"), FieldType.PERCENT);
            tax.default_value = "0.22";
            var rel = new Relationship (ln.name, li.name, inv.name, "ID");
            rel.on_delete = RefAction.CASCADE;
            ln.relationships.add (rel);
            db.create_table (ln);
            rows (db, cu.name, { cu.fields[1].name, cu.fields[2].name, cu.fields[3].name, cu.fields[4].name, cu.fields[5].name }, {
                { t ("Blue Harbor Foods"), t ("billing@blueharbor.example"), t ("Via del Porto 12"), t ("Genova"), t (_("Italy")) },
                { t ("Studio Vela"), t ("admin@studiovela.example"), t ("Piazza Duomo 3"), t ("Firenze"), t (_("Italy")) },
                { t ("Alpine Tours GmbH"), t ("office@alpinetours.example"), t ("Hauptstrasse 8"), t ("Innsbruck"), t (_("Austria")) }
            });
            string[] ivc = { inv.fields[1].name, inv.fields[2].name, inv.fields[3].name, inv.fields[4].name, inv.fields[5].name };
            rows (db, inv.name, ivc, {
                { t ("2026-001"), i (1), t (day (-40)), t (day (-10)), t (_("Paid")) },
                { t ("2026-002"), i (2), t (day (-25)), t (day (5)), t (_("Sent")) },
                { t ("2026-003"), i (1), t (day (-12)), t (day (18)), t (_("Sent")) },
                { t ("2026-004"), i (3), t (day (-50)), t (day (-20)), t (_("Overdue")) },
                { t ("2026-005"), i (2), t (day (-1)), t (day (29)), t (_("Draft")) }
            });
            string[] lc = { ln.fields[1].name, ln.fields[2].name, ln.fields[3].name, ln.fields[4].name, ln.fields[5].name };
            rows (db, ln.name, lc, {
                { i (1), t (_("Catalog photography")), r (1), r (850), r (0.22) },
                { i (1), t (_("Retouching, per image")), r (40), r (12.5), r (0.22) },
                { i (2), t (_("Brand workshop")), r (2), r (600), r (0.22) },
                { i (3), t (_("Packaging design")), r (1), r (1200), r (0.22) },
                { i (3), t (_("Print proofs")), r (3), r (45), r (0.22) },
                { i (4), t (_("Tour booking system")), r (1), r (3400), r (0) },
                { i (4), t (_("Hosting, one year")), r (1), r (240), r (0) },
                { i (5), t (_("Social media kit")), r (1), r (480), r (0.22) }
            });
            string nq = Sql.quote_ident (ivc[0]);
            db.save_query (new QueryDef (_("Invoice Totals"), "SELECT i.%s, c.%s AS %s, i.%s, i.%s, i.%s, round(sum(l.%s * l.%s), 2) AS %s, round(sum(l.%s * l.%s * l.%s), 2) AS %s, round(sum(l.%s * l.%s * (1 + l.%s)), 2) AS %s FROM %s AS i JOIN %s AS c ON c.\"ID\" = i.%s JOIN %s AS l ON l.%s = i.\"ID\" GROUP BY i.\"ID\" ORDER BY i.%s".printf (
                nq, Sql.quote_ident (cu.fields[1].name), Sql.quote_ident (_("Customer")), Sql.quote_ident (ivc[2]), Sql.quote_ident (ivc[3]), Sql.quote_ident (ivc[4]),
                Sql.quote_ident (lc[2]), Sql.quote_ident (lc[3]), Sql.quote_ident (_("Net")),
                Sql.quote_ident (lc[2]), Sql.quote_ident (lc[3]), Sql.quote_ident (lc[4]), Sql.quote_ident (_("Tax")),
                Sql.quote_ident (lc[2]), Sql.quote_ident (lc[3]), Sql.quote_ident (lc[4]), Sql.quote_ident (_("Total")),
                Sql.quote_ident (inv.name), Sql.quote_ident (cu.name), Sql.quote_ident (ivc[1]), Sql.quote_ident (ln.name), Sql.quote_ident (lc[0]), nq)));
            var views = ViewDef.load_all (db, inv.name);
            var kb = new ViewDef (_("By Status"), ViewKind.KANBAN);
            kb.pick_defaults (db.load_table (inv.name));
            kb.group_field = ivc[4];
            kb.title_field = ivc[0];
            kb.card_fields = { ivc[1], ivc[3] };
            views.add (kb);
            var cal = new ViewDef (_("Due Calendar"), ViewKind.CALENDAR);
            cal.pick_defaults (db.load_table (inv.name));
            cal.date_field = ivc[3];
            cal.title_field = ivc[0];
            views.add (cal);
            db.set_meta ("views:" + inv.name, ViewDef.to_json_all (views));
            var form = FormDef.generate (db, inv.name, FormLayout.TWO_COLUMNS);
            form.name = _("Invoice");
            form.title = _("Invoice");
            save_form (db, form);
            var rep = new ReportDef ();
            rep.name = _("Invoices by Customer");
            rep.source = _("Invoice Totals");
            rep.title = _("Invoices by Customer");
            rep.subtitle = _("Net, tax and total per invoice");
            rep.columns.add (new ReportColumn (ivc[0], ivc[0]));
            rep.columns.add (new ReportColumn (ivc[2], ivc[2]));
            rep.columns.add (new ReportColumn (ivc[4], ivc[4]));
            string[] money = { _("Net"), _("Tax"), _("Total") };
            foreach (string m in money) {
                var c = new ReportColumn (m, m);
                c.total = ReportTotal.SUM;
                rep.columns.add (c);
            }
            rep.groups.add (new ReportGroup (_("Customer")));
            save_report (db, rep);
        }
    }
}
