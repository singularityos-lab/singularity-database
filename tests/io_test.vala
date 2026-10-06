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
    return Path.build_filename (Environment.get_tmp_dir (), "sdb-io-%d-%s".printf (Random.int_range (0, 1000000), name));
}

Database sample () throws Error {
    var db = Database.create (tmp_path ("sample.sdb"));
    Templates.build (db, "inventory");
    return db;
}

void test_csv () throws Error {
    string text = "\xef\xbb\xbfName;Qty;Price;Note;When;Ok\r\n\"Apple; green\";3;1.5;\"say \"\"hi\"\"\";2024-01-02;yes\nPear;;2;\"multi\nline\";2024-02-03;no\n\n";
    ok (Csv.detect (text) == ';', "detect semicolon");
    var dt = Csv.from_text (text, "Fruit", ';', true);
    ok (dt.columns.length == 6 && dt.columns[0] == "Name", "header");
    ok (dt.rows.size == 2, "rows skip blank");
    ok (dt.rows[0].get (0).to_string () == "Apple; green", "quoted separator");
    ok (dt.rows[0].get (3).to_string () == "say \"hi\"", "escaped quote");
    ok (dt.rows[1].get (3).to_string () == "multi\nline", "multiline field");
    ok (dt.rows[1].get (1).is_null, "empty is null");
    ok (Transfer.infer_column (dt, 1) == FieldType.INTEGER && Transfer.infer_column (dt, 2) == FieldType.NUMBER, "infer numbers");
    ok (Transfer.infer_column (dt, 4) == FieldType.DATE && Transfer.infer_column (dt, 5) == FieldType.BOOLEAN, "infer date bool");
    ok (Transfer.infer_column (dt, 3) == FieldType.LONG_TEXT, "infer long text");
    var dup = Csv.from_text ("a,a,\n1,2,3\n", "D", ',', true);
    ok (dup.columns[1] == "a 2" && dup.columns[2] == "Field 3", "unique and blank header names");
    var nohead = Csv.from_text ("1,2\n3,4\n", "N", ',', false);
    ok (nohead.rows.size == 2 && nohead.columns[0] == "Field 1", "no header");
    var db = Database.create (tmp_path ("csv.sdb"));
    var res = Transfer.import_table (db, dt, "Fruit", ImportMode.NEW_TABLE);
    ok (res.imported == 2 && res.failed == 0, "import csv");
    var def = db.load_table ("Fruit");
    ok (def.fields[0].name == "ID" && def.fields[0].field_type == FieldType.AUTONUMBER, "id added");
    ok (def.find ("When").field_type == FieldType.DATE && def.find ("Ok").field_type == FieldType.BOOLEAN, "types stored");
    ok (db.query ("SELECT \"Ok\", \"When\" FROM Fruit ORDER BY ID").rows[0].get (0).as_int () == 1, "bool converted");
    ok (db.can_undo, "import undoable");
    db.undo ();
    ok (!db.object_exists ("Fruit"), "undo import");
    db.redo ();
    ok (db.count_rows ("Fruit") == 2, "redo import");
    var more = Csv.from_text ("Name,Qty,Extra\nKiwi,x,1\nPlum,4,2\n", "More", ',', true);
    var r2 = Transfer.import_table (db, more, "Fruit", ImportMode.APPEND);
    ok (r2.imported == 2 && r2.failed == 1 && r2.notes.size == 1, "append with conversion failure");
    ok (db.count_rows ("Fruit") == 4, "appended");
    var r3 = Transfer.import_table (db, more, "Fruit", ImportMode.REPLACE);
    ok (db.count_rows ("Fruit") == 2 && r3.imported == 2, "replace");
    var r4 = Transfer.import_table (db, more, "Fruit", ImportMode.NEW_TABLE);
    ok (r4.table == "Fruit 2", "new table gets unique name");
    var out_dt = Transfer.from_source (new RecordSource (db, "Fruit"));
    string csv = Csv.export (out_dt, ',');
    ok (csv.has_prefix ("ID,Name,Qty,Price,Note,When,Ok\r\n"), "export header");
    var again = Csv.from_text (csv, "Again", ',', true);
    ok (again.rows.size == 2 && again.rows[0].get (1).to_string () == "Kiwi", "csv roundtrip");
    string path = tmp_path ("fruit.csv");
    Csv.save (out_dt, path);
    var loaded = Csv.load (path);
    ok (loaded.name.has_suffix ("fruit") && loaded.rows.size == 2, "csv file roundtrip");
    string latin = tmp_path ("latin.csv");
    FileUtils.set_data (latin, { 'N', 'a', 'm', 'e', '\n', 'C', 'a', 'f', 0xE9, '\n' });
    ok (Csv.load (latin).rows[0].get (0).to_string () == "Café", "windows-1252 fallback");
    var formatted = Transfer.from_source (new RecordSource (db, "Fruit"), true);
    ok (formatted.rows[1].get (2).kind == ValueKind.TEXT && formatted.rows[1].get (2).to_string () == "4" && formatted.rows[0].get (6).is_null, "formatted export");
}

void test_xlsx () throws Error {
    var db = sample ();
    var tables = Transfer.all_tables (db);
    ok (tables.size == 4, "all tables");
    string path = tmp_path ("inventory.xlsx");
    Xlsx.save (tables, path);
    var back = Xlsx.load (path);
    ok (back.size == 4, "sheet count");
    DataTable? products = null;
    foreach (var t in back) {
        if (t.name == "Products") products = t;
    }
    ok (products != null, "products sheet");
    ok (products.columns.length == 10 && products.columns[1] == "Name", "columns");
    ok (products.rows.size == 9, "rows");
    ok (products.rows[0].get (1).to_string () == "Espresso Beans 1 kg", "text cell");
    ok (products.rows[0].get (5).kind == ValueKind.REAL && products.rows[0].get (5).real_value == 18.9, "currency number");
    ok (products.rows[0].get (6).kind == ValueKind.INTEGER && products.rows[0].get (6).int_value == 42, "integer");
    ok (products.rows[5].get (8).kind == ValueKind.INTEGER && products.rows[5].get (8).int_value == 1, "boolean cell");
    DataTable? moves = null;
    foreach (var t in back) {
        if (t.name == "Stock Movements") moves = t;
    }
    string first_date = db.query ("SELECT \"Date\" FROM \"Stock Movements\" ORDER BY ID LIMIT 1").rows[0].get (0).to_string ();
    ok (moves.rows[0].get (2).to_string () == first_date, "date cell roundtrip " + moves.rows[0].get (2).to_string ());
    var target = Database.create (tmp_path ("x.sdb"));
    var res = Transfer.import_table (target, products, "Products", ImportMode.NEW_TABLE);
    ok (res.imported == 9, "import xlsx");
    var def = target.load_table ("Products");
    ok (def.find ("ID").primary_key && def.find ("ID").field_type == FieldType.AUTONUMBER, "existing unique ID becomes key");
    ok (def.find ("Unit Price").field_type == FieldType.NUMBER && def.find ("In Stock").field_type == FieldType.INTEGER, "xlsx types");
    ok (Xlsx.column_name (0) == "A" && Xlsx.column_name (25) == "Z" && Xlsx.column_name (26) == "AA" && Xlsx.column_name (701) == "ZZ", "column names");
    int r, c;
    Xlsx.parse_ref ("AB12", out r, out c);
    ok (r == 11 && c == 27, "parse ref");
    ok (Xlsx.serial_to_iso (45292, false) == "2024-01-01", "serial to date");
    ok (Xlsx.serial_to_iso (45292.5, true) == "2024-01-01 12:00:00", "serial to datetime");
    ok (Xlsx.iso_to_serial ("2024-01-01 12:00:00") == 45292.5, "iso to serial");
    ok (Xlsx.is_date_format ("dd/mm/yyyy") && Xlsx.is_date_format ("[h]:mm:ss") && !Xlsx.is_date_format ("0.00") && !Xlsx.is_date_format ("\"d\"0"), "date format detection");
    var weird = new DataTable ("A/B:C*[x]?");
    weird.columns = { "N" };
    weird.add_row ({ new DbValue.text ("x") });
    var w2 = new DataTable ("A/B:C*[x]?");
    w2.columns = { "N" };
    var list = new Gee.ArrayList<DataTable> ();
    list.add (weird);
    list.add (w2);
    string wp = tmp_path ("weird.xlsx");
    Xlsx.save (list, wp);
    var wb = Xlsx.load (wp);
    ok (wb.size == 2 && wb[0].name == "ABCx" && wb[1].name == "ABCx 2", "sheet names sanitized");
    ok (wb[1].rows.size == 0, "empty sheet");
    var zr = new ZipReader (read_bytes (wp));
    ok (zr.has ("xl/workbook.xml") && zr.has ("[Content_Types].xml") && zr.has ("xl/sharedStrings.xml"), "package parts");
    bool threw = false;
    try {
        string junk = tmp_path ("junk.xlsx");
        FileUtils.set_contents (junk, "not a zip");
        Xlsx.load (junk);
    } catch (Error e) {
        threw = true;
    }
    ok (threw, "bad xlsx rejected");
}

void test_json () throws Error {
    var db = sample ();
    var dt = Transfer.from_source (new RecordSource (db, "Products"));
    string json = JsonIO.export (dt);
    ok (json.has_prefix ("[") && json.contains ("\"Discontinued\" : false"), "json booleans");
    var back = JsonIO.parse (json, "Products");
    ok (back.size == 1 && back[0].rows.size == 9 && back[0].columns.length == 10, "json roundtrip shape");
    ok (back[0].rows[0].get (5).real_value == 18.9 && back[0].rows[0].get (1).to_string () == "Espresso Beans 1 kg", "json values");
    ok (back[0].types[8] == FieldType.BOOLEAN, "json bool column");
    var target = Database.create (tmp_path ("j.sdb"));
    var res = Transfer.import_table (target, back[0], "Products", ImportMode.NEW_TABLE);
    ok (res.imported == 9 && target.load_table ("Products").find ("Discontinued").field_type == FieldType.BOOLEAN, "json import");
    var all = JsonIO.export_many (Transfer.all_tables (db));
    var many = JsonIO.parse (all, "x");
    ok (many.size == 4, "json many tables");
    var nd = JsonIO.parse ("{\"a\": 1, \"b\": \"x\"}\n{\"a\": 2, \"c\": null}\n", "nd");
    ok (nd.size == 1 && nd[0].rows.size == 2 && nd[0].columns.length == 3, "ndjson");
    var single = JsonIO.parse ("{\"name\": \"x\", \"tags\": [1, 2]}", "one");
    ok (single[0].rows.size == 1 && single[0].rows[0].get (1).to_string () == "[1,2]", "nested kept as json text");
    var scalars = JsonIO.parse ("[1, 2, 3]", "s");
    ok (scalars[0].columns[0] == "Value" && scalars[0].rows.size == 3, "scalar array");
    bool threw = false;
    try {
        JsonIO.parse ("42", "n");
    } catch (Error e) {
        threw = true;
    }
    ok (threw, "json scalar rejected");
}

void test_sql_dump () throws Error {
    var db = sample ();
    db.run ("UPDATE Products SET Photo = X'89504E47' WHERE ID = 1");
    db.run ("UPDATE Products SET Name = 'It''s; tricky' WHERE ID = 2");
    string dump = SqlDump.dump (db);
    ok (dump.has_prefix ("PRAGMA foreign_keys=OFF;\nBEGIN TRANSACTION;\n") && dump.has_suffix ("COMMIT;\n"), "dump frame");
    ok (dump.contains ("X'89504E47'") && dump.contains ("'It''s; tricky'"), "dump literals");
    ok (dump.contains ("CREATE VIEW"), "dump views");
    var copy = Database.create (tmp_path ("dump.sdb"));
    SqlDump.import_script (copy, dump);
    foreach (string t in db.table_names ()) ok (copy.count_rows (t) == db.count_rows (t), "dump rows " + t);
    ok (copy.view_names ().size == db.view_names ().size, "dump views restored");
    ok (copy.load_table ("Products").find ("Unit Price").field_type == FieldType.CURRENCY, "meta restored");
    ok (copy.object_names ("report:").size == db.object_names ("report:").size, "reports restored");
    ok (copy.query ("SELECT Name FROM Products WHERE ID = 2").rows[0].get (0).to_string () == "It's; tricky", "tricky string");
    ok (copy.integrity_check ().has_prefix ("ok"), "restored integrity");
    string pg = SqlDump.dump (db, SqlDialect.POSTGRESQL);
    ok (pg.contains ("BIGSERIAL") && pg.contains ("DECIMAL(19,4)") && pg.contains ("ALTER TABLE \"Products\" ADD FOREIGN KEY") && pg.contains ("::bytea") && pg.contains ("setval("), "postgres dialect");
    ok (pg.contains ("FALSE") || pg.contains ("TRUE"), "postgres booleans");
    string my = SqlDump.dump (db, SqlDialect.MYSQL);
    ok (my.contains ("`Products`") && my.contains ("AUTO_INCREMENT") && my.contains ("SET FOREIGN_KEY_CHECKS=0"), "mysql dialect");
    int64 n = db.count_rows ("Products");
    var mem = Database.memory ();
    string portable = SqlDump.dump (db, SqlDialect.POSTGRESQL);
    int inserts = 0;
    foreach (string line in portable.split ("\n")) {
        if (line.has_prefix ("INSERT INTO \"Products\"")) inserts++;
    }
    ok (inserts == n, "portable inserts");
    mem.close ();
}

void test_sqlite_import () throws Error {
    string p = tmp_path ("other.sqlite");
    var other = Database.open (p, true);
    other.exec ("CREATE TABLE notes (id INTEGER PRIMARY KEY, body TEXT, stars INTEGER)");
    other.exec ("INSERT INTO notes (body, stars) VALUES ('a', 1), ('b', 5)");
    other.close ();
    var db = Database.create (tmp_path ("imp.sdb"));
    var res = Transfer.import_sqlite (db, p);
    ok (res.size == 1 && res[0].imported == 2, "sqlite import");
    ok (db.load_table ("notes").find ("id").field_type == FieldType.AUTONUMBER, "sqlite key");
}

void test_mdb () throws Error {
    string? dir = Environment.get_variable ("MDB_FIXTURES");
    if (dir == null || !FileUtils.test (Path.build_filename (dir, "nwind.mdb"), FileTest.EXISTS)) {
        print ("io: Access fixtures not found, set MDB_FIXTURES to run the import checks\n");
        return;
    }
    string enc = Path.build_filename (dir, "encrypted", "db2013-enc.accdb");
    if (FileUtils.test (enc, FileTest.EXISTS)) {
        var edb = Database.create (tmp_path ("enc.sdb"));
        bool asked = false;
        try {
            Transfer.import_mdb (edb, enc);
        } catch (MdbError.PASSWORD e) {
            asked = true;
        }
        ok (asked, "encrypted accdb asks for the password");
        bool wrong = false;
        try {
            Transfer.import_mdb (edb, enc, "0000");
        } catch (MdbError.PASSWORD e) {
            wrong = e.message == "The password is not correct.";
        }
        ok (wrong, "encrypted accdb rejects a wrong password");
        Transfer.import_mdb (edb, enc, "1234");
        ok (edb.count_rows ("Customers") == 7, "encrypted accdb imported with the right password");
        edb.close ();
    }
    var db = Database.create (tmp_path ("nwind.sdb"));
    var results = Transfer.import_mdb (db, Path.build_filename (dir, "nwind.mdb"));
    int total = 0;
    foreach (var r in results) total += r.imported;
    ok (db.count_rows ("Customers") == 91 && db.count_rows ("Orders") == 830 && db.count_rows ("Order Details") == 2155, "northwind rows");
    ok (total >= 91 + 830 + 2155 + 77, "total imported");
    var orders = db.load_table ("Orders");
    bool rel = false;
    foreach (var r in orders.effective_relationships ()) {
        if (r.ref_table == "Customers") rel = true;
    }
    ok (rel, "orders to customers relationship");
    ok (orders.find ("OrderDate").field_type == FieldType.DATE || orders.find ("OrderDate").field_type == FieldType.DATETIME, "order date type");
    ok (db.load_table ("Products").find ("UnitPrice").field_type == FieldType.CURRENCY, "money type");
    ok (db.query ("SELECT CompanyName FROM Customers WHERE CustomerID = 'ALFKI'").rows[0].get (0).to_string () == "Alfreds Futterkiste", "customer value");
    ok (db.integrity_check ().has_prefix ("ok"), "northwind integrity");
    ok (db.query_int ("SELECT count(*) FROM Orders WHERE OrderDate IS NULL") == 0, "every order date converted");
    ok (db.query ("SELECT OrderDate FROM Orders WHERE OrderID = 10330").rows[0].get (0).to_string () == "1994-11-16", "order date value");
    int failed = 0;
    foreach (var r in results) failed += r.failed;
    ok (failed == 0, "no conversion failures (%d)".printf (failed));
    ok (db.can_undo, "access import undoable");
    var db2 = Database.create (tmp_path ("sample.sdb"));
    var r2 = Transfer.import_mdb (db2, Path.build_filename (dir, "ASampleDatabase.accdb"));
    ok (r2.size == 1 && r2[0].imported == 65, "accdb rows");
    var db3 = Database.create (tmp_path ("dates.sdb"));
    Transfer.import_mdb (db3, Path.build_filename (dir, "DateTestDatabase.mdb"));
    ok (db3.table_names ().size >= 1, "date test tables");
    string[] converted = {};
    foreach (var r in results) {
        foreach (string n in r.notes) converted += n;
    }
    string notes = string.joinv ("\n", converted);
    ok (notes.contains ("queries were converted"), "northwind queries converted: " + notes);
    var views = db.view_names ();
    int saved = views.size + db.object_names ("action:").size;
    ok (saved >= 20, "northwind saved queries %d".printf (saved));
    var cat = SavedQueries.load (db, "Category Sales for 1995");
    if (cat != null) {
        var rs = db.query (QueryPrep.prepare (db, cat.sql));
        ok (rs.rows.size > 0, "converted query runs");
    }
    var cross = SavedQueries.load (db, "Quarterly Orders by Product");
    if (cross != null) {
        ok (cross.kind == "crosstab", "crosstab imported as crosstab");
        var params = QueryPrep.find_parameters (db, cross.sql);
        var rs = db.query (QueryPrep.prepare (db, cross.sql, params));
        ok (rs.columns.length >= 3, "imported crosstab runs");
    }
    var sales = SavedQueries.load (db, "Employee Sales by Country");
    if (sales != null) {
        var params = QueryPrep.find_parameters (db, sales.sql);
        ok (params.size == 2, "parameter query keeps parameters");
        params[0].value = new DbValue.text ("1994-01-01");
        params[1].value = new DbValue.text ("1996-12-31");
        var rs = db.query (QueryPrep.prepare (db, sales.sql, params));
        ok (rs.rows.size > 0, "imported parameter query runs");
    }
    ok (notes.contains ("SaveAsText"), "forms and reports explained");
    string complex = Path.build_filename (dir, "complexDataTestV2010.accdb");
    if (FileUtils.test (complex, FileTest.EXISTS)) {
        var db4 = Database.create (tmp_path ("complex.sdb"));
        Transfer.import_mdb (db4, complex);
        int attach = 0, multi = 0;
        foreach (string t in db4.table_names ()) {
            var def = db4.load_table (t);
            foreach (var f in def.fields) {
                if (f.field_type == FieldType.ATTACHMENT) {
                    var rs = db4.query ("SELECT %s FROM %s WHERE %s IS NOT NULL".printf (Sql.quote_ident (f.name), Sql.quote_ident (t), Sql.quote_ident (f.name)));
                    foreach (var r in rs.rows) attach += Attachment.unpack_all (r.get (0).blob_value).size;
                }
                if (f.multi_value) {
                    var rs = db4.query ("SELECT %s FROM %s WHERE %s IS NOT NULL".printf (Sql.quote_ident (f.name), Sql.quote_ident (t), Sql.quote_ident (f.name)));
                    foreach (var r in rs.rows) multi += MultiValue.items (r.get (0)).length;
                }
            }
        }
        ok (attach >= 2 && multi == 6, "attachments %d and multi values %d imported".printf (attach, multi));
    }
}

uint8[] read_bytes (string path) throws Error {
    uint8[] data;
    FileUtils.get_data (path, out data);
    return data;
}

void test_data_exports () throws Error {
    var dt = new DataTable ("Price List");
    dt.columns = { "Item Name", "Price", "In Stock", "Note" };
    dt.types = { FieldType.TEXT, FieldType.CURRENCY, FieldType.BOOLEAN, FieldType.LONG_TEXT };
    dt.add_row ({ new DbValue.text ("Pen & Ink"), new DbValue.real (2.5), new DbValue.bool (true), new DbValue.text ("città {curly}") });
    dt.add_row ({ new DbValue.text ("Paper"), new DbValue.real (10), new DbValue.bool (false), new DbValue.null () });
    string path = tmp_path ("prices.xml");
    DataExport.write (dt, path);
    string xml, xsd;
    FileUtils.get_contents (path, out xml);
    FileUtils.get_contents (path.substring (0, path.length - 4) + ".xsd", out xsd);
    ok (xml.contains ("<Price_List>") && xml.contains ("<Item_Name>Pen &amp; Ink</Item_Name>") && xml.contains ("prices.xsd\""), "xml export");
    ok (xsd.contains ("name=\"Price\" minOccurs=\"0\" type=\"xsd:decimal\"") && xsd.contains ("xsd:boolean"), "xsd export");
    var back = DataExport.from_xml (xml, "x");
    ok (back.size == 1 && back[0].name == "Price_List" && back[0].rows.size == 2 && back[0].rows[0].get (0).to_string () == "Pen & Ink" && back[0].rows[1].get (3).is_null, "xml round trip");
    string html = DataExport.to_html (dt);
    ok (html.contains ("<th>Item Name</th>") && html.contains ("<td class=\"n\">2.5</td>"), "html export");
    string rtf = DataExport.to_rtf (dt);
    ok (rtf.has_prefix ("{\\rtf1") && rtf.contains ("\\{curly\\}") && rtf.contains ("citt\\u224?") && rtf.contains ("\\cell"), "rtf export");
    string fixed_text = DataExport.to_fixed_width (dt);
    string[] lines = fixed_text.split ("\n");
    ok (lines[0].index_of ("Price") == lines[1].index_of ("  2.5") || lines[1].contains ("  2.5"), "fixed width right aligns numbers");
    ok (lines[0].char_count () == lines[1].char_count (), "fixed width columns");
    var db = Database.memory ();
    var r = Transfer.import_table (db, back[0], "Imported", ImportMode.NEW_TABLE);
    ok (r.imported == 2, "xml import into table");
}

int main (string[] args) {
    Locale.set_default (Locale.neutral ());
    try {
        test_csv ();
        test_xlsx ();
        test_json ();
        test_sql_dump ();
        test_sqlite_import ();
        test_mdb ();
        test_data_exports ();
    } catch (Error e) {
        stderr.printf ("FAIL: unexpected error: %s\n", e.message);
        return 1;
    }
    print ("io: %d checks passed\n", checks);
    return 0;
}
