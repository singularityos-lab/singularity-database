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
    return Path.build_filename (Environment.get_tmp_dir (), "sdb-schema-%d-%s".printf (Random.int_range (0, 1000000), name));
}

bool fails (Database db, string sql) {
    try {
        db.run (sql);
        return false;
    } catch (Error e) {
        return true;
    }
}

TableDef sample_def () {
    var t = new TableDef ("Items");
    var id = t.add_field ("ID", FieldType.AUTONUMBER);
    id.primary_key = true;
    var name = t.add_field ("Name", FieldType.TEXT);
    name.required = true;
    name.max_length = 20;
    var code = t.add_field ("Code", FieldType.TEXT);
    code.unique = true;
    t.add_field ("Notes", FieldType.LONG_TEXT).description = "Free notes";
    t.add_field ("Qty", FieldType.INTEGER).default_value = "1";
    var price = t.add_field ("Price", FieldType.CURRENCY);
    price.decimals = 2;
    price.validation = "\"Price\" >= 0";
    t.add_field ("Discount", FieldType.PERCENT);
    t.add_field ("Weight", FieldType.NUMBER).indexed = true;
    t.add_field ("Added", FieldType.DATE).default_value = "Date()";
    t.add_field ("Updated", FieldType.DATETIME);
    t.add_field ("Opens", FieldType.TIME);
    t.add_field ("Active", FieldType.BOOLEAN).default_value = "Yes";
    var status = t.add_field ("Status", FieldType.CHOICE);
    status.choices = { "New", "Used", "Broken, old" };
    status.default_value = "New";
    t.add_field ("Contact", FieldType.EMAIL);
    t.add_field ("Site", FieldType.URL);
    t.add_field ("Phone", FieldType.PHONE);
    t.add_field ("Picture", FieldType.ATTACHMENT);
    t.indexes.add (new IndexDef ("idx_name_code", { "Name", "Code" }, false));
    t.description = "Things we own";
    return t;
}

void test_types () {
    foreach (var t in FieldType.ALL) {
        ok (FieldType.from_id (t.id ()) == t, "id roundtrip " + t.id ());
        ok (t.label () != "", "label " + t.id ());
    }
    ok (FieldType.from_declared ("VARCHAR(40)") == FieldType.TEXT, "varchar");
    ok (FieldType.from_declared ("bigint") == FieldType.INTEGER, "bigint");
    ok (FieldType.from_declared ("DOUBLE PRECISION") == FieldType.NUMBER, "double");
    ok (FieldType.from_declared ("LONG TEXT") == FieldType.LONG_TEXT, "long text");
    ok (FieldType.from_declared ("") == FieldType.TEXT, "no type");
    ok (FieldType.from_declared ("BLOB") == FieldType.ATTACHMENT, "blob");
    ok (FieldType.from_declared ("timestamp") == FieldType.DATETIME, "timestamp");
    ok (FieldType.from_declared ("DECIMAL(10,2)") == FieldType.NUMBER, "decimal");
}

void test_sql_helpers () {
    ok (Sql.quote_ident ("a\"b") == "\"a\"\"b\"", "quote ident");
    ok (Sql.quote_string ("it's") == "'it''s'", "quote string");
    ok (Sql.unquote_ident ("[My Field]") == "My Field", "unquote bracket");
    ok (Sql.unquote_ident ("`x``y`") == "x`y", "unquote backtick");
    var toks = Sql.tokenize ("SELECT count(*) AS n, 'a;b' FROM \"T\" -- c\nWHERE x >= 1.5e3 AND y <> ?");
    ok (toks[0].kind == TokenKind.KEYWORD && toks[1].kind == TokenKind.FUNCTION, "keyword and function");
    bool has_string = false, has_comment = false, has_param = false, has_number = false;
    foreach (var t in toks) {
        if (t.kind == TokenKind.STRING) has_string = t.text == "'a;b'";
        if (t.kind == TokenKind.COMMENT) has_comment = true;
        if (t.kind == TokenKind.PARAMETER) has_param = true;
        if (t.kind == TokenKind.NUMBER && t.text == "1.5e3") has_number = true;
    }
    ok (has_string && has_comment && has_param && has_number, "token kinds");
    var stmts = Sql.split_statements ("CREATE TABLE a(x); INSERT INTO a VALUES('1;2');\n-- only comment;\nCREATE TRIGGER t AFTER INSERT ON a BEGIN UPDATE a SET x = 1; DELETE FROM a WHERE 0; END; SELECT 1");
    ok (stmts.size == 4, "split statements %d".printf (stmts.size));
    ok (stmts[2].has_suffix ("END"), "trigger kept whole");
    ok (Sql.is_read_only ("  select 1") && Sql.is_read_only ("WITH x AS (SELECT 1) SELECT * FROM x") && !Sql.is_read_only ("WITH x AS (SELECT 1) DELETE FROM t"), "read only");
    ok (!Sql.is_read_only ("UPDATE t SET a = 1"), "update not read only");
    string f = Sql.format ("select a,count(*) from t where b=1 group by a order by a");
    ok (f.contains ("\nFROM") && f.contains ("\nGROUP BY") && f.contains ("COUNT(*)") == false && f.contains ("count(*)"), "format: " + f);
}

void test_codec () {
    Locale.set_default (Locale.neutral ());
    double d;
    ok (Codec.parse_number ("1,234.50", out d) && d == 1234.5, "grouped number");
    ok (Codec.parse_number ("$ 12", out d) && d == 12, "currency number");
    ok (Codec.parse_number ("(5)", out d) && d == -5, "negative parens");
    ok (!Codec.parse_number ("abc", out d), "not number");
    string iso;
    ok (Codec.parse_date ("2024-02-29", out iso) && iso == "2024-02-29", "iso date");
    ok (!Codec.parse_date ("2023-02-29", out iso), "invalid leap day");
    ok (Codec.parse_date ("3/14/2025", out iso) && iso == "2025-03-14", "us date");
    ok (Codec.parse_date ("14/3/2025", out iso) && iso == "2025-03-14", "swapped date");
    ok (Codec.parse_datetime ("2025-01-02T03:04:05Z", out iso) && iso == "2025-01-02 03:04:05", "iso datetime");
    ok (Codec.parse_time ("3:30 pm", out iso) && iso == "15:30:00", "time pm");
    ok (Codec.parse_date ("2024-08-09", out iso) && iso == "2024-08-09", "leading zero 08 and 09 are decimal");
    ok (Codec.parse_date ("09/08/2024", out iso) && iso == "2024-09-08", "leading zero in slashed date");
    ok (Codec.parse_time ("08:09", out iso) && iso == "08:09:00", "leading zero time");
    var status = new Field ("S", FieldType.CHOICE);
    status.choices = { "Open", "Closed" };
    try {
        ok (Codec.parse (status, "open").text_value == "Open", "choice case insensitive");
        var pct = new Field ("P", FieldType.PERCENT);
        ok (Math.fabs (Codec.parse (pct, "25%").real_value - 0.25) < 1e-12, "percent");
        var b = new Field ("B", FieldType.BOOLEAN);
        ok (Codec.parse (b, "yes").int_value == 1 && Codec.parse (b, "no").int_value == 0, "boolean");
        var i = new Field ("I", FieldType.INTEGER);
        ok (Codec.parse (i, "1,000").int_value == 1000, "integer grouped");
        ok (Codec.parse (i, "").is_null, "empty is null");
    } catch (Error e) {
        ok (false, e.message);
    }
    bool threw = false;
    try {
        Codec.parse (status, "Maybe");
    } catch (Error e) {
        threw = true;
    }
    ok (threw, "choice rejects");
    threw = false;
    try {
        Codec.parse (new Field ("I", FieldType.INTEGER), "1.5");
    } catch (Error e) {
        threw = true;
    }
    ok (threw, "integer rejects fraction");
    var cur = new Field ("C", FieldType.CURRENCY);
    cur.decimals = 2;
    ok (Codec.display (cur, new DbValue.real (1234.5)) == "$1,234.50", "currency display " + Codec.display (cur, new DbValue.real (1234.5)));
    ok (Codec.display (new Field ("D", FieldType.DATE), new DbValue.text ("2025-03-14")) == "03/14/2025", "date display");
    ok (Codec.display (new Field ("P", FieldType.PERCENT), new DbValue.real (0.125)) == "13%" || Codec.display (new Field ("P", FieldType.PERCENT), new DbValue.real (0.125)) == "12%", "percent display");
    var samples = new Gee.ArrayList<string> ();
    samples.add ("1");
    samples.add ("22");
    ok (Codec.infer (samples) == FieldType.INTEGER, "infer int");
    samples.add ("2.5");
    ok (Codec.infer (samples) == FieldType.NUMBER, "infer number");
    var ds = new Gee.ArrayList<string> ();
    ds.add ("2024-01-01");
    ds.add ("2024-05-06");
    ok (Codec.infer (ds) == FieldType.DATE, "infer date");
    var bs = new Gee.ArrayList<string> ();
    bs.add ("true");
    bs.add ("FALSE");
    ok (Codec.infer (bs) == FieldType.BOOLEAN, "infer bool");
    var es = new Gee.ArrayList<string> ();
    es.add ("a@b.example");
    ok (Codec.infer (es) == FieldType.EMAIL, "infer email");
    var packed = Attachment.pack ("photo.png", "image/png", new Bytes ({ 1, 2, 3 }));
    string fn, mime;
    Bytes content;
    ok (Attachment.unpack (packed, out fn, out mime, out content) && fn == "photo.png" && mime == "image/png" && content.get_size () == 3, "attachment pack");
    ok (Attachment.describe (packed).has_prefix ("photo.png"), "attachment describe");
}

void test_create_and_introspect () throws Error {
    var db = Database.create (tmp_path ("create.sdb"));
    ok (db.is_sdb, "sdb flag");
    var def = sample_def ();
    db.create_table (def);
    var back = db.load_table ("items");
    ok (back.name == "Items", "name case");
    ok (back.fields.size == def.fields.size, "field count");
    ok (back.description == "Things we own", "table description");
    for (int i = 0; i < def.fields.size; i++) {
        ok (back.fields[i].name == def.fields[i].name, "field name " + def.fields[i].name);
        ok (back.fields[i].field_type == def.fields[i].field_type, "field type %s %s".printf (def.fields[i].name, back.fields[i].field_type.id ()));
    }
    ok (back.find ("ID").primary_key, "pk");
    ok (back.find ("Name").required && back.find ("Name").max_length == 20, "required and max length");
    ok (back.find ("Code").unique, "unique");
    ok (back.find ("Notes").description == "Free notes", "field description");
    ok (back.find ("Qty").default_value == "1", "default");
    ok (back.find ("Added").default_value == "Date()", "date default");
    ok (back.find ("Price").decimals == 2, "decimals");
    ok (back.find ("Price").validation.contains ("Price") && back.find ("Price").validation.contains (">= 0"), "validation " + back.find ("Price").validation);
    ok (back.find ("Status").choices.length == 3 && back.find ("Status").choices[2] == "Broken, old", "choices");
    ok (back.find ("Weight").indexed, "field index");
    ok (back.indexes.size == 1 && back.indexes[0].columns.length == 2, "composite index");
    db.run ("INSERT INTO Items (Name) VALUES ('Chair')");
    var rs = db.query ("SELECT Qty, Active, Status, Added FROM Items");
    ok (rs.rows[0].get (0).as_int () == 1 && rs.rows[0].get (1).as_int () == 1 && rs.rows[0].get (2).to_string () == "New", "defaults applied");
    ok (rs.rows[0].get (3).to_string ().length == 10, "date default applied");
    ok (fails (db, "INSERT INTO Items (Name, Status) VALUES ('x', 'Lost')"), "choice check");
    ok (fails (db, "INSERT INTO Items (Name, Active) VALUES ('x', 2)"), "boolean check");
    ok (fails (db, "INSERT INTO Items (Name) VALUES ('this name is far too long for twenty')"), "max length check");
    ok (fails (db, "INSERT INTO Items (Name, Price) VALUES ('x', -1)"), "validation check");
    ok (fails (db, "INSERT INTO Items (Notes) VALUES ('no name')"), "required check");
    db.run ("INSERT INTO Items (Name, Code) VALUES ('A', 'X1')");
    ok (fails (db, "INSERT INTO Items (Name, Code) VALUES ('B', 'X1')"), "unique check");
    bool threw = false;
    try {
        db.run ("INSERT INTO Items (Name, Code) VALUES ('B', 'X1')");
    } catch (SchemaError e) {
        threw = e is SchemaError.CONSTRAINT && e.message.contains ("Code");
    }
    ok (threw, "friendly constraint message");
    var dup = sample_def ();
    threw = false;
    try {
        db.create_table (dup);
    } catch (Error e) {
        threw = true;
    }
    ok (threw, "duplicate table rejected");
    var bad = new TableDef ("Bad");
    bad.add_field ("A", FieldType.TEXT);
    bad.add_field ("a", FieldType.TEXT);
    threw = false;
    try {
        db.create_table (bad);
    } catch (Error e) {
        threw = true;
    }
    ok (threw, "duplicate field rejected");
    var reopened = Database.open (db.path);
    ok (reopened.load_table ("Items").find ("Price").field_type == FieldType.CURRENCY, "reopen keeps types");
    ok (reopened.table_names ().size == 1, "meta table hidden");
}

void test_plain_sqlite () throws Error {
    string p = tmp_path ("plain.sqlite");
    var db = Database.open (p, true);
    ok (!db.is_sdb, "plain sqlite not sdb");
    db.exec ("CREATE TABLE people (id INTEGER PRIMARY KEY, name VARCHAR(30) NOT NULL, kind TEXT CHECK (kind IN ('a', 'b')), born DATE, rate REAL DEFAULT 1.5, flag BOOLEAN)");
    db.exec ("CREATE TABLE pets (pid INTEGER PRIMARY KEY, owner INTEGER REFERENCES people(id) ON DELETE CASCADE, name TEXT)");
    var def = db.load_table ("people");
    ok (def.find ("id").field_type == FieldType.AUTONUMBER, "rowid alias is autonumber");
    ok (def.find ("name").max_length == 30 && def.find ("name").required, "varchar length");
    ok (def.find ("kind").field_type == FieldType.CHOICE && def.find ("kind").choices.length == 2, "check in becomes choice");
    ok (def.find ("born").field_type == FieldType.DATE, "date declared");
    ok (def.find ("rate").default_value == "1.5", "real default");
    var pets = db.load_table ("pets");
    ok (pets.relationships.size == 1 && pets.relationships[0].on_delete == RefAction.CASCADE, "fk introspected");
    ok (!db.has_meta_table (), "opening plain sqlite does not add metadata");
}

void test_relationships () throws Error {
    var db = Database.create (tmp_path ("rel.sdb"));
    var cust = new TableDef ("Customers");
    var cid = cust.add_field ("ID", FieldType.AUTONUMBER);
    cid.primary_key = true;
    cust.add_field ("Name", FieldType.TEXT);
    db.create_table (cust);
    var ord = new TableDef ("Orders");
    var oid = ord.add_field ("ID", FieldType.AUTONUMBER);
    oid.primary_key = true;
    var oc = ord.add_field ("Customer", FieldType.LOOKUP);
    oc.lookup_table = "Customers";
    oc.lookup_field = "ID";
    oc.lookup_display = "Name";
    ord.add_field ("Total", FieldType.CURRENCY);
    var rel = new Relationship ("Orders", "Customer", "Customers", "ID");
    rel.on_delete = RefAction.CASCADE;
    ord.relationships.add (rel);
    db.create_table (ord);
    var back = db.load_table ("Orders");
    ok (back.find ("Customer").field_type == FieldType.LOOKUP && back.find ("Customer").lookup_display == "Name", "lookup kept");
    ok (back.relationships.size == 1 && back.relationships[0].on_delete == RefAction.CASCADE, "cascade relationship");
    ok (db.relationships_to ("Customers").size == 1, "relationships to parent");
    db.run ("INSERT INTO Customers (Name) VALUES ('Ada'), ('Bob')");
    db.run ("INSERT INTO Orders (Customer, Total) VALUES (1, 10), (1, 20), (2, 5)");
    ok (fails (db, "INSERT INTO Orders (Customer, Total) VALUES (99, 1)"), "orphan rejected");
    db.run ("DELETE FROM Customers WHERE ID = 1");
    ok (db.count_rows ("Orders") == 1, "cascade delete");
    var rs = new RecordSource (db, "Orders");
    ok (rs.display (rs.def.find ("Customer"), new DbValue.int (2)) == "Bob", "lookup display");
    var weak = new TableDef ("Notes");
    var nid = weak.add_field ("ID", FieldType.AUTONUMBER);
    nid.primary_key = true;
    var nc = weak.add_field ("Customer Name", FieldType.LOOKUP);
    nc.lookup_table = "Customers";
    nc.lookup_field = "Name";
    bool threw = false;
    try {
        db.create_table (weak);
    } catch (Error e) {
        threw = e.message.contains ("unique");
    }
    ok (threw, "enforced relationship needs unique key");
    db.run ("INSERT INTO Customers (ID, Name) VALUES (7, 'Cy')");
    db.exec ("PRAGMA foreign_keys = OFF");
    db.run ("INSERT INTO Orders (Customer, Total) VALUES (42, 1)");
    db.exec ("PRAGMA foreign_keys = ON");
    var o2 = db.load_table ("Orders");
    o2.relationships.clear ();
    var of = o2.find ("Customer");
    of.field_type = FieldType.INTEGER;
    of.lookup_table = "";
    of.lookup_field = "";
    db.alter_table ("Orders", o2);
    ok (db.load_table ("Orders").effective_relationships ().size == 0, "relationship removed");
    var o3 = db.load_table ("Orders");
    var again = new Relationship ("Orders", "Customer", "Customers", "ID");
    o3.relationships.add (again);
    threw = false;
    try {
        db.alter_table ("Orders", o3);
    } catch (Error e) {
        threw = e is SchemaError.CONSTRAINT;
    }
    ok (threw, "integrity violation blocks relationship");
    ok (db.load_table ("Orders").relationships.size == 0, "failed change rolled back");
    ok (db.count_rows ("Orders") == 2, "data intact after rollback");
}

void test_alter_and_undo () throws Error {
    var db = Database.create (tmp_path ("alter.sdb"));
    var t = new TableDef ("People");
    var id = t.add_field ("ID", FieldType.AUTONUMBER);
    id.primary_key = true;
    t.add_field ("Name", FieldType.TEXT);
    t.add_field ("Age", FieldType.TEXT);
    db.create_table (t);
    db.run ("INSERT INTO People (Name, Age) VALUES ('Ada', '36'), ('Bob', 'n/a'), ('Cy', ' 7 ')");
    var child = new TableDef ("Pets");
    var pid = child.add_field ("ID", FieldType.AUTONUMBER);
    pid.primary_key = true;
    var owner = child.add_field ("Owner", FieldType.LOOKUP);
    owner.lookup_table = "People";
    owner.lookup_field = "ID";
    owner.lookup_display = "Name";
    db.create_table (child);
    db.run ("INSERT INTO Pets (Owner) VALUES (1), (3)");
    ok (db.can_undo && db.undo_label != "", "create recorded");
    var def = db.load_table ("People");
    def.find ("Name").name = "Full Name";
    def.find ("Age").field_type = FieldType.INTEGER;
    def.add_field ("Email", FieldType.EMAIL);
    var renames = new Gee.HashMap<string, string> ();
    renames["Full Name"] = "Name";
    db.alter_table ("People", def, renames);
    var rs = db.query ("SELECT \"Full Name\", Age, Email FROM People ORDER BY ID");
    ok (rs.rows[0].get (0).to_string () == "Ada" && rs.rows[0].get (1).kind == ValueKind.INTEGER && rs.rows[0].get (1).int_value == 36, "renamed and converted");
    ok (rs.rows[1].get (1).to_string () == "n/a", "unconvertible kept");
    ok (rs.rows[2].get (1).as_int () == 7, "trimmed number");
    db.undo ();
    var undone = db.load_table ("People");
    ok (undone.find ("Name") != null && undone.find ("Full Name") == null && undone.find ("Email") == null, "undo restores design");
    ok (db.query ("SELECT Age FROM People WHERE Name = 'Ada'").rows[0].get (0).kind == ValueKind.TEXT, "undo restores data type");
    ok (db.can_redo, "redo available");
    db.redo ();
    ok (db.load_table ("People").find ("Full Name") != null, "redo reapplies");
    ok (db.count_rows ("People") == 3, "rows kept through redo");
    db.rename_table ("People", "Humans");
    ok (db.object_exists ("Humans") && !db.object_exists ("People"), "renamed table");
    var pets = db.load_table ("Pets");
    ok (pets.find ("Owner").lookup_table == "Humans", "lookup retargeted " + pets.find ("Owner").lookup_table);
    db.run ("INSERT INTO Pets (Owner) VALUES (2)");
    ok (fails (db, "INSERT INTO Pets (Owner) VALUES (77)"), "fk follows rename");
    db.undo ();
    ok (db.object_exists ("People") && !db.object_exists ("Humans"), "undo rename");
    ok (db.load_table ("Pets").find ("Owner").lookup_table == "People", "undo rename child");
    ok (db.count_rows ("Pets") == 2, "undo rename restores child rows");
    db.drop_object ("Pets");
    ok (!db.object_exists ("Pets"), "dropped");
    db.undo ();
    ok (db.object_exists ("Pets") && db.count_rows ("Pets") == 2, "undo drop restores data");
    var extra = new TableDef ("Temp");
    extra.add_field ("X", FieldType.TEXT);
    db.create_table (extra);
    db.undo ();
    ok (!db.object_exists ("Temp"), "undo create drops");
    db.redo ();
    ok (db.object_exists ("Temp"), "redo create");
}

void test_data_undo () throws Error {
    var db = Database.create (tmp_path ("data.sdb"));
    var t = new TableDef ("T");
    var id = t.add_field ("ID", FieldType.AUTONUMBER);
    id.primary_key = true;
    t.add_field ("V", FieldType.TEXT);
    db.create_table (t);
    db.clear_history ();
    int64 a = db.insert_row ("T", { "V" }, { new DbValue.text ("one") });
    int64 b = db.insert_row ("T", { "V" }, { new DbValue.text ("two") });
    db.update_value ("T", a, "V", new DbValue.text ("uno"));
    ok (db.query ("SELECT V FROM T WHERE ID = ?", { new DbValue.int (a) }).rows[0].get (0).to_string () == "uno", "update");
    db.undo ();
    ok (db.query ("SELECT V FROM T WHERE ID = ?", { new DbValue.int (a) }).rows[0].get (0).to_string () == "one", "undo update");
    db.redo ();
    ok (db.query ("SELECT V FROM T WHERE ID = ?", { new DbValue.int (a) }).rows[0].get (0).to_string () == "uno", "redo update");
    db.delete_rows ("T", { a, b });
    ok (db.count_rows ("T") == 0, "deleted");
    db.undo ();
    ok (db.count_rows ("T") == 2, "undo delete");
    ok (db.query ("SELECT V FROM T WHERE ID = ?", { new DbValue.int (b) }).rows[0].get (0).to_string () == "two", "undo delete keeps ids");
    db.undo ();
    db.undo ();
    db.undo ();
    ok (db.count_rows ("T") == 0, "undo inserts");
}

void test_recordsource () throws Error {
    var db = Database.create (tmp_path ("rs.sdb"));
    var t = new TableDef ("Big");
    var id = t.add_field ("ID", FieldType.AUTONUMBER);
    id.primary_key = true;
    t.add_field ("Name", FieldType.TEXT);
    var g = t.add_field ("Group", FieldType.CHOICE);
    g.choices = { "Red", "Green", "Blue" };
    t.add_field ("Value", FieldType.NUMBER);
    t.add_field ("Done", FieldType.BOOLEAN);
    t.add_field ("When", FieldType.DATE);
    db.create_table (t);
    db.begin ();
    string[] groups = { "Red", "Green", "Blue" };
    for (int i = 0; i < 5000; i++) {
        db.run ("INSERT INTO Big (Name, \"Group\", Value, Done, \"When\") VALUES (?, ?, ?, ?, ?)", {
            new DbValue.text ("Item %04d".printf (i)), i % 10 == 0 ? new DbValue.null () : new DbValue.text (groups[i % 3]),
            new DbValue.real (i * 0.5), new DbValue.bool (i % 2 == 0), new DbValue.text ("2025-%02d-%02d".printf (1 + i % 12, 1 + i % 28))
        });
    }
    db.commit ();
    var rs = new RecordSource (db, "Big");
    ok (rs.count () == 5000 && rs.editable, "count");
    ok (rs.row (4999).get (1).to_string () == "Item 4999", "last row paged");
    ok (rs.row (250).get (1).to_string () == "Item 0250", "middle page");
    rs.state.sorts.add (new SortSpec ("Value", true));
    rs.invalidate ();
    ok (rs.row (0).get (1).to_string () == "Item 4999", "sort desc");
    rs.state.filters.add (new FilterSpec ("Group", FilterOp.EQUALS, "red"));
    rs.invalidate ();
    int64 reds = db.query_int ("SELECT count(*) FROM Big WHERE \"Group\" = 'Red'");
    ok (rs.count () == reds, "filter equals case insensitive");
    rs.state.filters.add (new FilterSpec ("Value", FilterOp.GREATER, "1000"));
    rs.invalidate ();
    ok (rs.count () == db.query_int ("SELECT count(*) FROM Big WHERE \"Group\" = 'Red' AND Value > 1000"), "filter and");
    rs.state.match_any = true;
    rs.invalidate ();
    ok (rs.count () == db.query_int ("SELECT count(*) FROM Big WHERE \"Group\" = 'Red' OR Value > 1000"), "filter or");
    rs.state.filters.clear ();
    rs.state.match_any = false;
    var between = new FilterSpec ("When", FilterOp.BETWEEN, "2025-03-01");
    between.value2 = "2025-03-31";
    rs.state.filters.add (between);
    rs.invalidate ();
    ok (rs.count () == db.query_int ("SELECT count(*) FROM Big WHERE \"When\" BETWEEN '2025-03-01' AND '2025-03-31'"), "between dates");
    rs.state.filters.clear ();
    rs.state.filters.add (new FilterSpec ("Group", FilterOp.IS_EMPTY));
    rs.invalidate ();
    ok (rs.count () == 500, "is empty");
    rs.state.filters.clear ();
    var any = new FilterSpec ("Group", FilterOp.ONE_OF);
    any.values = { "Blue", "" };
    rs.state.filters.add (any);
    rs.invalidate ();
    ok (rs.count () == db.query_int ("SELECT count(*) FROM Big WHERE \"Group\" = 'Blue' OR \"Group\" IS NULL"), "one of with empty");
    rs.state.filters.clear ();
    rs.state.filters.add (new FilterSpec ("Done", FilterOp.IS_TRUE));
    rs.invalidate ();
    ok (rs.count () == 2500, "is true");
    rs.state.filters.clear ();
    rs.state.search = "item 012";
    rs.invalidate ();
    ok (rs.count () == 10, "search %lld".printf (rs.count ()));
    rs.state.search = "";
    rs.state.sorts.clear ();
    rs.state.group_by = "Group";
    rs.invalidate ();
    var gs = rs.groups ();
    ok (gs.size == 4 && gs[0].key.is_null && gs[0].count == 500, "groups with empty first");
    int64 total = 0;
    foreach (var gi in gs) total += gi.count;
    ok (total == 5000 && gs[1].start == 500, "group starts");
    ok (rs.row (0).get (2).is_null && rs.row (500).get (2).to_string () == "Blue", "grouped order");
    rs.state.group_by = "";
    rs.invalidate ();
    ok (rs.index_of_rowid (4321) == 4320, "index of rowid");
    ok (rs.aggregate ("Value", Aggregate.SUM).as_double () == 0.5 * 4999 * 5000 / 2, "aggregate sum");
    ok (rs.distinct_values ("Group").size == 4, "distinct values");
    int64 nid = rs.add_row ({ "Name" }, { new DbValue.text ("New") });
    ok (rs.count () == 5001 && nid == 5001, "add row");
    rs.set_value (nid, "Value", new DbValue.real (3));
    ok (db.query_int ("SELECT Value FROM Big WHERE ID = 5001") == 3, "set value");
    rs.delete ({ nid });
    ok (rs.count () == 5000, "delete row");
    var timer = new Timer ();
    var rs2 = new RecordSource (db, "Big");
    rs2.state.sorts.add (new SortSpec ("Name", false));
    for (int64 i = 0; i < 5000; i += 7) rs2.row (i);
    ok (timer.elapsed () < 5, "paging speed");
}

void test_queries_and_objects () throws Error {
    var db = Database.create (tmp_path ("obj.sdb"));
    Templates.build (db, "invoices");
    ok (db.table_names ().size == 3, "invoice tables");
    ok (db.view_names ().size == 1, "invoice query");
    var q = db.load_query ("Invoice Totals");
    ok (q != null && q.sql.has_prefix ("SELECT"), "load query body");
    var rs = new RecordSource (db, "Invoice Totals");
    ok (rs.count () == 5 && !rs.editable, "query rows");
    var totals = db.query ("SELECT \"Total\" FROM \"Invoice Totals\" WHERE \"Number\" = '2026-001'");
    ok (Math.fabs (totals.rows[0].get (0).as_double () - (850 + 40 * 12.5) * 1.22) < 0.01, "computed total");
    bool threw = false;
    try {
        db.save_query (new QueryDef ("Bad", "DELETE FROM Invoices"));
    } catch (Error e) {
        threw = true;
    }
    ok (threw, "action query not saved as view");
    threw = false;
    try {
        db.save_query (new QueryDef ("Broken", "SELECT nope FROM Invoices"));
    } catch (Error e) {
        threw = true;
    }
    ok (threw && !db.object_exists ("Broken"), "invalid query rejected");
    var qd = new QueryDef ("Paid", "SELECT * FROM Invoices WHERE Status = 'Paid'");
    qd.description = "Only paid";
    qd.design = "{}";
    db.save_query (qd);
    var back = db.load_query ("Paid");
    ok (back.description == "Only paid" && back.design == "{}", "query meta");
    var changed = new QueryDef ("Settled", back.sql);
    db.save_query (changed, "Paid");
    ok (db.object_exists ("Settled") && !db.object_exists ("Paid"), "rename query");
    db.undo ();
    ok (db.object_exists ("Paid") && !db.object_exists ("Settled"), "undo query rename");
    var forms = db.object_names ("form:");
    ok (forms.size == 1, "template form");
    var form = FormDef.from_json (forms[0], db.get_meta ("form:" + forms[0]));
    ok (form != null && form.subforms.size == 1 && form.subforms[0].table == "Invoice Lines", "subform generated");
    var f2 = FormDef.from_json ("x", form.to_json ());
    ok (f2.controls.size == form.controls.size && f2.subforms[0].link_field == form.subforms[0].link_field, "form json roundtrip");
    var gen = FormDef.generate (db, "Customers");
    ok (gen.subforms.size == 1 && gen.subforms[0].table == "Invoices", "customer subform");
    gen.controls[1].x = 13;
    gen.controls[1].y = 5;
    gen.snap ();
    ok (gen.controls[1].x == 16 && gen.controls[1].y == 8, "snap to grid");
    db.save_object_meta ("Save Form", "form:", "Customers Form", gen.to_json ());
    ok (db.get_meta ("form:Customers Form") != null, "form saved");
    db.undo ();
    ok (db.get_meta ("form:Customers Form") == null, "undo form save");
    var views = ViewDef.load_all (db, "Invoices");
    ok (views.size == 3 && views[1].kind == ViewKind.KANBAN && views[2].kind == ViewKind.CALENDAR, "views");
    views[1].state.filters.add (new FilterSpec ("Status", FilterOp.NOT_EQUALS, "Paid"));
    views[1].state.hidden.add ("Notes");
    views[1].state.widths["Number"] = 140;
    db.set_meta ("views:Invoices", ViewDef.to_json_all (views));
    var v2 = ViewDef.load_all (db, "Invoices");
    ok (v2[1].state.filters.size == 1 && v2[1].state.hidden.contains ("Notes") && v2[1].state.widths["Number"] == 140, "view state roundtrip");
    foreach (var info in Templates.list ()) {
        var tdb = Database.create (tmp_path (info.id + ".sdb"));
        Templates.build (tdb, info.id);
        ok (tdb.table_names ().size >= 2, "template tables " + info.id);
        ok (tdb.object_names ("report:").size >= 1, "template report " + info.id);
        foreach (string rn in tdb.object_names ("report:")) {
            var rep = ReportDef.from_json (rn, tdb.get_meta ("report:" + rn));
            var src = ReportEngine.open_source (tdb, rep);
            ok (src.count () > 0, "report source rows " + rn);
        }
        ok (tdb.integrity_check ().has_prefix ("ok"), "template integrity " + info.id);
        ok (!tdb.can_undo, "template history cleared");
    }
    string text = db.integrity_check ();
    ok (text.has_prefix ("ok"), "integrity");
    string copy = tmp_path ("copy.sdb");
    db.vacuum_into (copy);
    var c = Database.open (copy);
    ok (c.table_names ().size == 3 && c.object_names ("form:").size == 1, "vacuum into keeps objects");
}

void test_sql_functions () throws Error {
    var db = Database.memory ();
    var rs = db.query ("SELECT year('2024-05-06'), month('2024-05-06'), day('2024-05-06'), ucase('ab'), lcase('AB'), len('città'), left('abcdef', 2), right('abcdef', 3), nz(NULL, 5), 'abc' REGEXP '^a.c$', hour('2024-01-01 13:45:00')");
    var r = rs.rows[0];
    ok (r.get (0).as_int () == 2024 && r.get (1).as_int () == 5 && r.get (2).as_int () == 6, "date parts");
    ok (r.get (3).to_string () == "AB" && r.get (4).to_string () == "ab", "case functions");
    ok (r.get (5).as_int () == 5, "len unicode");
    ok (r.get (6).to_string () == "ab" && r.get (7).to_string () == "def", "left right");
    ok (r.get (8).as_int () == 5 && r.get (9).as_int () == 1 && r.get (10).as_int () == 13, "nz regexp hour");
    ok (db.query_int ("SELECT month('2024-08-09') * 100 + day('2024-08-09')") == 809, "date parts with 08 and 09");
    ResultSet? last;
    int changed = db.execute_script ("CREATE TABLE s (a); INSERT INTO s VALUES (1), (2); UPDATE s SET a = a * 10; SELECT sum(a) FROM s;", out last);
    ok (changed == 4 && last != null && last.rows[0].get (0).as_int () == 30, "script");
}

int main (string[] args) {
    Locale.set_default (Locale.neutral ());
    try {
        test_types ();
        test_sql_helpers ();
        test_codec ();
        test_create_and_introspect ();
        test_plain_sqlite ();
        test_relationships ();
        test_alter_and_undo ();
        test_data_undo ();
        test_recordsource ();
        test_queries_and_objects ();
        test_sql_functions ();
    } catch (Error e) {
        stderr.printf ("FAIL: unexpected error: %s\n", e.message);
        return 1;
    }
    print ("schema: %d checks passed\n", checks);
    return 0;
}
