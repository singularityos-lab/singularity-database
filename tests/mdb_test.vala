using Singularity.Apps.Database;

string hex (uint8[] data) {
    var sb = new StringBuilder ();
    foreach (uint8 b in data) sb.append ("%02X".printf (b));
    return sb.str;
}

void test_helpers () {
    assert (hex (MdbCodec.rc4 ("Key".data, "Plaintext".data)) == "BBF316E8D940AF0AD3");
    assert (hex (MdbCodec.rc4 ("Wiki".data, "pedia".data)) == "1021BF0420");
    uint8[] back = MdbCodec.rc4 ("Key".data, MdbCodec.rc4 ("Key".data, "round trip".data));
    assert (hex (back) == hex ("round trip".data));

    uint8[] compressed = { 0xFF, 0xFE, 'A', 'b', 0x00, 0xA9, 0x03, 0x00, 'z' };
    assert (MdbCodec.jet4_text (compressed, 0, compressed.length) == "AbΩz");
    uint8[] plain = { 'H', 0, 'i', 0, 0xE8, 0x00 };
    assert (MdbCodec.jet4_text (plain, 0, plain.length) == "Hiè");
    uint8[] surrogate = { 0x3D, 0xD8, 0x00, 0xDE };
    assert (MdbCodec.ucs2 (surrogate, 0, 4) == "😀");
    uint8[] cp = { 'C', 'a', 'f', 0xE9, ' ', 0x80, 0x93 };
    assert (MdbCodec.cp1252 (cp, 0, cp.length) == "Café €“");

    assert (MdbCodec.ole_date (0) == "1899-12-30 00:00:00");
    assert (MdbCodec.ole_date (1.5) == "1899-12-31 12:00:00");
    assert (MdbCodec.ole_date (-1.25) == "1899-12-29 06:00:00");
    assert (MdbCodec.ole_date (36526) == "2000-01-01 00:00:00");
    assert (MdbCodec.ole_date (36526.75) == "2000-01-01 18:00:00");
    assert (MdbCodec.ole_date (1e12) == "");

    assert (MdbCodec.money (127500) == 12.75);
    assert (MdbCodec.money (-50000) == -5.0);

    uint8[] g = { 0x33, 0x22, 0x11, 0x00, 0x55, 0x44, 0x77, 0x66, 0x88, 0x99, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF };
    assert (MdbCodec.guid (g, 0) == "{00112233-4455-6677-8899-AABBCCDDEEFF}");

    uint8[] num = new uint8[17];
    num[0] = 0x80;
    num[13] = 0x39;
    num[14] = 0x30;
    assert (Math.fabs (MdbCodec.numeric (num, 0, 2) + 123.45) < 1e-9);
    num[0] = 0;
    num[1] = 0x01;
    double big = Math.pow (2, 96) + 12345;
    assert (Math.fabs (MdbCodec.numeric (num, 0, 0) - big) / big < 1e-12);

    assert (MdbColumnType.from_code (0x0A) == MdbColumnType.TEXT);
    assert (MdbColumnType.from_code (0x0C) == MdbColumnType.MEMO);
    assert (MdbColumnType.from_code (0x0F) == MdbColumnType.GUID);
    assert (MdbColumnType.from_code (0x42) == MdbColumnType.UNKNOWN);
    print ("helpers: ok\n");
}

void test_errors () {
    uint8[] junk = new uint8[4096];
    try {
        MdbFile.from_data ((owned) junk);
        assert_not_reached ();
    } catch (MdbError.FORMAT e) {
    } catch (Error e) {
        assert_not_reached ();
    }
    uint8[] fake = new uint8[4096 * 4];
    Memory.copy ((uint8*) fake + 4, "Standard Jet DB".data, 15);
    fake[0x14] = 1;
    fake[2 * 4096] = 0x7F;
    try {
        MdbFile.from_data ((owned) fake);
        assert_not_reached ();
    } catch (MdbError.UNSUPPORTED e) {
    } catch (Error e) {
        assert_not_reached ();
    }
    print ("errors: ok\n");
}

Row? find_row (MdbTable t, string column, string value) {
    int c = t.index_of (column);
    assert (c >= 0);
    foreach (var r in t.rows) {
        if (r.get (c).to_string () == value) return r;
    }
    return null;
}

string cell (MdbTable t, Row r, string column) {
    return r.get (t.index_of (column)).to_string ();
}

MdbRelationship? find_rel (MdbFile f, string table, string ref_table) {
    foreach (var r in f.relationships) {
        if (r.table == table && r.ref_table == ref_table) return r;
    }
    return null;
}

void test_northwind (string path) throws Error {
    int64 t0 = get_monotonic_time ();
    var f = MdbFile.open (path);
    double ms = (get_monotonic_time () - t0) / 1000.0;
    assert (f.version == 0);
    string[] names = { "Customers", "Orders", "Order Details", "Products", "Suppliers", "Employees", "Categories", "Shippers" };
    int[] counts = { 91, 830, 2155, 77, 29, 9, 8, 3 };
    for (int i = 0; i < names.length; i++) {
        var t = f.find_table (names[i]);
        assert (t != null);
        assert (t.rows.size == counts[i]);
    }
    foreach (var t in f.tables) assert (!t.name.has_prefix ("MSys"));

    var customers = f.find_table ("Customers");
    var alfki = find_row (customers, "CustomerID", "ALFKI");
    assert (alfki != null);
    assert (cell (customers, alfki, "CompanyName") == "Alfreds Futterkiste");
    assert (cell (customers, alfki, "Country") == "Germany");
    assert (find_row (customers, "City", "México D.F.") != null);
    assert (customers.primary_key.length == 1 && customers.primary_key[0] == "CustomerID");

    var orders = f.find_table ("Orders");
    var o = find_row (orders, "OrderID", "10330");
    assert (o != null);
    assert (cell (orders, o, "OrderDate") == "1994-11-16 00:00:00");
    assert (o.get (orders.index_of ("Freight")).as_double () == 12.75);
    assert (cell (orders, o, "CustomerID") == "LILAS");
    assert (orders.columns[orders.index_of ("OrderID")].autonumber);
    assert (!orders.columns[orders.index_of ("CustomerID")].autonumber);
    assert (orders.columns[orders.index_of ("OrderDate")].kind == MdbColumnType.DATETIME);
    assert (orders.columns[orders.index_of ("Freight")].kind == MdbColumnType.MONEY);

    var products = f.find_table ("Products");
    var chai = find_row (products, "ProductName", "Chai");
    assert (chai != null);
    assert (chai.get (products.index_of ("UnitPrice")).as_double () == 18.0);
    assert (products.columns[products.index_of ("Discontinued")].kind == MdbColumnType.BOOLEAN);

    var details = f.find_table ("Order Details");
    assert (details.primary_key.length == 2);
    double total = 0;
    foreach (var r in details.rows) total += r.get (details.index_of ("Quantity")).as_double ();
    assert (total > 50000);

    var employees = f.find_table ("Employees");
    var nancy = find_row (employees, "FirstName", "Nancy");
    assert (nancy != null);
    assert (cell (employees, nancy, "Notes").has_prefix ("Education includes a BA"));
    assert (cell (employees, nancy, "BirthDate") == "1948-12-08 00:00:00");
    assert (nancy.get (employees.index_of ("Photo")).kind == ValueKind.BLOB);
    assert (nancy.get (employees.index_of ("Photo")).blob_value.get_size () > 10000);

    var categories = f.find_table ("Categories");
    foreach (var r in categories.rows) assert (r.get (categories.index_of ("Picture")).kind == ValueKind.BLOB);

    var rel = find_rel (f, "Orders", "Customers");
    assert (rel != null);
    assert (rel.columns.length == 1 && rel.columns[0] == "CustomerID" && rel.ref_columns[0] == "CustomerID");
    assert (rel.enforce && rel.cascade_update && !rel.cascade_delete);
    var rel2 = find_rel (f, "Order Details", "Orders");
    assert (rel2 != null && rel2.cascade_delete);
    assert (find_rel (f, "Orders", "Shippers").ref_columns[0] == "ShipperID");
    bool invoices = false;
    foreach (string q in f.query_names) if (q == "Invoices") invoices = true;
    assert (invoices);
    print ("nwind.mdb: ok (%d tables, %.1f ms)\n", f.tables.size, ms);
}

void test_dates (string path) throws Error {
    var f = MdbFile.open (path);
    assert (f.version == 1);
    var t = f.find_table ("DateTest");
    assert (t != null && t.rows.size == 6);
    var r3 = find_row (t, "IDCol", "3");
    assert (cell (t, r3, "DateTimeCol") == "1898-01-01 00:00:00");
    assert (cell (t, r3, "TimeCol") == "1900-01-01 00:00:00");
    var r2 = find_row (t, "IDCol", "2");
    assert (cell (t, r2, "DateTimeCol") == "9999-01-01 00:00:00");
    assert (cell (t, r2, "LongTextCol") == "Year 9999");
    var r4 = find_row (t, "IDCol", "4");
    assert (cell (t, r4, "DateTimeCol") == "0632-01-01 00:00:00");
    var r6 = find_row (t, "IDCol", "6");
    assert (cell (t, r6, "LongTextCol").has_prefix ("New line"));
    assert (cell (t, r6, "LongTextCol").contains ("\n"));
    assert (t.columns[t.index_of ("LongTextCol")].kind == MdbColumnType.MEMO);
    assert (f.relationships.size == 0);
    print ("DateTestDatabase.mdb: ok\n");
}

void test_accdb (string path) throws Error {
    var f = MdbFile.open (path);
    assert (f.version == 2);
    assert (f.tables.size == 1);
    var t = f.find_table ("Asset Items");
    assert (t != null && t.rows.size == 65);
    assert (t.primary_key.length == 1 && t.primary_key[0] == "Asset No");
    var r = find_row (t, "Asset No", "30050");
    assert (r != null);
    assert (cell (t, r, "Make") == "GEO Rocket");
    assert (cell (t, r, "Acquired") == "1997-09-02 00:00:00");
    assert (r.get (t.index_of ("Cost")).as_double () == 1995.5);
    assert (f.query_names.length == 3);
    print ("ASampleDatabase.accdb: ok\n");
}

string? fixture (string name) {
    foreach (string env in new string[] { "MDB_FIXTURES", "DB_FIXTURES" }) {
        string? dir = Environment.get_variable (env);
        if (dir == null) continue;
        string p = Path.build_filename (dir, name);
        if (FileUtils.test (p, FileTest.EXISTS)) return p;
    }
    return null;
}


MdbQuery? find_query (MdbFile f, string name) {
    foreach (var q in f.queries) {
        if (q.name == name) return q;
    }
    return null;
}

void expect_sql (MdbFile f, string name, MdbQueryKind kind, string sql) {
    var q = find_query (f, name);
    assert (q != null);
    if (q.kind != kind || q.sql != sql) {
        stderr.printf ("query %s\n  got (%d):\n%s\n  want (%d):\n%s\n", name, (int) q.kind, q.sql, (int) kind, sql);
        assert_not_reached ();
    }
}

void test_queries (string path) throws Error {
    var f = MdbFile.open (path);
    assert (f.queries.size == 9);
    assert (f.query_names.length == 9);
    expect_sql (f, "SelectQuery", MdbQueryKind.SELECT,
        "SELECT DISTINCT Table1.*, Table2.col1, Table2.col2, Table3.col3\n" +
        "FROM (Table1 LEFT JOIN Table3 ON Table1.col1 = Table3.col1) INNER JOIN Table2 ON (Table3.col1 = Table2.col2) AND (Table3.col1 = Table2.col1)\n" +
        "WHERE (((Table2.col2)=\"foo\" Or (Table2.col2) In (\"buzz\",\"bazz\")))\n" +
        "ORDER BY Table2.col1;");
    expect_sql (f, "DeleteQuery", MdbQueryKind.DELETE,
        "DELETE Table1.col1, Table1.col2, Table1.col3\nFROM Table1\nWHERE (((Table1.col1)>\"blah\"));");
    expect_sql (f, "AppendQuery", MdbQueryKind.APPEND,
        "INSERT INTO Table3 (col2, col2, col3)\nSELECT [Table1].[col2], [Table2].[col2], [Table2].[col3]\n" +
        "FROM Table3, Table1 INNER JOIN Table2 ON [Table1].[col1]=[Table2].[col1];");
    expect_sql (f, "UpdateQuery", MdbQueryKind.UPDATE,
        "PARAMETERS [User Name] Text;\nUPDATE Table1\nSET Table1.col1 = \"foo\", Table1.col2 = [Table2].[col3], [Table2].[col1] = [User Name]\n" +
        "WHERE ((([Table2].[col1]) Is Not Null));");
    var upd = find_query (f, "UpdateQuery");
    assert (upd.parameter_names.length == 1 && upd.parameter_names[0] == "User Name" && upd.parameter_types[0] == "Text");
    assert (upd.parameters[0] == "[User Name] Text");
    expect_sql (f, "MakeTableQuery", MdbQueryKind.MAKE_TABLE,
        "SELECT Max(Table2.col1) AS MaxOfcol1, Table2.col2, Table3.col2 INTO Table4\n" +
        "FROM (Table2 INNER JOIN Table1 ON Table2.col1 = Table1.col2) RIGHT JOIN Table3 ON Table1.col2 = Table3.col3\n" +
        "GROUP BY Table2.col2, Table3.col2\n" +
        "HAVING (((Max(Table2.col1))=\"buzz\") AND ((Table2.col2)<>\"blah\"));");
    expect_sql (f, "CrosstabQuery", MdbQueryKind.CROSSTAB,
        "TRANSFORM Count([Table2].[col2]) AS CountOfcol2\n" +
        "SELECT Table2_1.col1, [Table2].[col3], Avg(Table2_1.col2) AS AvgOfcol2\n" +
        "FROM (Table1 INNER JOIN Table2 ON [Table1].[col1]=[Table2].[col1]) INNER JOIN Table2 AS Table2_1 ON [Table2].[col1]=Table2_1.col3\n" +
        "WHERE ((([Table1].[col1])>\"10\") And ((Table2_1.col1) Is Not Null) And ((Avg(Table2_1.col2))>\"10\"))\n" +
        "GROUP BY Table2_1.col1, [Table2].[col3]\n" +
        "ORDER BY [Table2].[col3]\n" +
        "PIVOT [Table1].[col1];");
    expect_sql (f, "UnionQuery", MdbQueryKind.UNION,
        "Select Table1.col1, Table1.col2\nwhere Table1.col1 = \"foo\"\nUNION\nSelect Table2.col1, Table2.col2\n" +
        "UNION ALL Select Table3.col1, Table3.col2\nwhere Table3.col3 > \"blah\";");
    expect_sql (f, "PassthroughQuery", MdbQueryKind.PASS_THROUGH, "ALTER TABLE Table4 DROP COLUMN col5;");
    assert (find_query (f, "PassthroughQuery").connection == "ODBC;");
    expect_sql (f, "DataDefinitionQuery", MdbQueryKind.DATA_DEFINITION, "CREATE TABLE Table5 (col1 CHAR, col2 CHAR);");
    print ("%s: queries ok\n", Path.get_basename (path));
}

void test_northwind_objects (string path) throws Error {
    var f = MdbFile.open (path);
    assert (!f.has_password);
    assert (f.form_names.length == 21 && f.report_names.length == 13 && f.macro_names.length == 7 && f.module_names.length == 3);
    bool orders = false;
    foreach (string n in f.form_names) if (n == "Orders") orders = true;
    assert (orders);
    assert (f.queries.size == f.query_names.length);
    foreach (var q in f.queries) assert (q.sql != "");
    var emp = find_query (f, "Employee Sales by Country");
    assert (emp.parameter_names.length == 2 && emp.parameter_names[0] == "Beginning Date" && emp.parameter_types[1] == "DateTime");
    assert (emp.sql.has_prefix ("PARAMETERS [Beginning Date] DateTime, [Ending Date] DateTime;\nSELECT DISTINCTROW Employees.Country"));
    var union = find_query (f, "Customers and Suppliers by City");
    assert (union.kind == MdbQueryKind.UNION && union.sql.contains ("\nUNION SELECT City, CompanyName, ContactName, \"Suppliers\"\n"));
    assert (find_query (f, "Product Sales for 1995").sql.contains ("Between #1/1/95# And #12/31/95#"));
    assert (find_query (f, "Current Product List").sql.contains ("FROM Products AS [Product List]"));
    print ("nwind.mdb: %d queries, forms %d, reports %d, macros %d, modules %d\n", f.queries.size, f.form_names.length, f.report_names.length, f.macro_names.length, f.module_names.length);
}

void test_password (string path) throws Error {
    uint8[] data;
    FileUtils.get_data (path, out data);
    uint8[] locked = MdbFile.with_password (data, "Sésamo 42");
    uint8[] copy1 = locked;
    try {
        MdbFile.from_data ((owned) copy1);
        assert_not_reached ();
    } catch (MdbError.PASSWORD e) {
    }
    uint8[] copy2 = locked;
    try {
        MdbFile.from_data ((owned) copy2, "wrong");
        assert_not_reached ();
    } catch (MdbError.PASSWORD e) {
    }
    uint8[] copy3 = locked;
    var f = MdbFile.from_data ((owned) copy3, "Sésamo 42");
    assert (f.has_password);
    assert (f.tables.size > 0);
    uint8[] copy4 = data;
    var plain = MdbFile.from_data ((owned) copy4);
    assert (!plain.has_password && plain.tables.size == f.tables.size);
    print ("%s: password ok (version %d)\n", Path.get_basename (path), f.version);
}

uint8[] le (uint32 v) {
    return { (uint8) (v & 0xff), (uint8) ((v >> 8) & 0xff), (uint8) ((v >> 16) & 0xff), (uint8) ((v >> 24) & 0xff) };
}

uint8[] encode_attachment (string ext, uint8[] content, bool compress) throws Error {
    var body = new ByteArray ();
    var type = new ByteArray ();
    foreach (uint8 b in (ext + "\0").data) {
        type.append ({ b, 0 });
    }
    type.append ({ 0, 0 });
    uint32 header_len = 12 + type.len;
    body.append (le (header_len));
    body.append (le (1));
    body.append (le (ext.length + 1));
    body.append (type.data);
    body.append (content);
    uint8[] payload = body.data;
    if (compress) {
        var conv = new ZlibCompressor (ZlibCompressorFormat.ZLIB, 3);
        var stream = new ConverterInputStream (new MemoryInputStream.from_data (payload), conv);
        var outb = new ByteArray ();
        uint8[] chunk = new uint8[4096];
        ssize_t n;
        while ((n = stream.read (chunk)) > 0) outb.append (chunk[0:n]);
        payload = outb.data;
    }
    var all = new ByteArray ();
    all.append (le (compress ? 1 : 0));
    all.append (le (header_len + content.length));
    all.append (payload);
    return all.data;
}

void test_attachment_codec () throws Error {
    uint8[] text = "Attachment body with some text that compresses well well well well".data;
    var raw = MdbCodec.attachment_content (encode_attachment ("jpg", text, false));
    assert (raw.get_size () == text.length && Memory.cmp (raw.get_data (), text, text.length) == 0);
    var packed = MdbCodec.attachment_content (encode_attachment ("txt", text, true));
    assert (packed.get_size () == text.length && Memory.cmp (packed.get_data (), text, text.length) == 0);
    try {
        MdbCodec.attachment_content ({ 7, 0, 0, 0, 1, 0, 0, 0, 0 });
        assert_not_reached ();
    } catch (MdbError.FORMAT e) {
    }
    print ("attachment codec: ok\n");
}

string mv_text (MdbFile f, MdbTable t, int row, int col) {
    string[] parts = {};
    foreach (var v in f.multi_values (t, row, col)) parts += v.to_string ();
    return string.joinv (",", parts);
}

void test_complex (string path) throws Error {
    var f = MdbFile.open (path);
    var t = f.find_table ("Table1");
    assert (t != null && t.rows.size == 4);
    int mv = t.index_of ("multi-value-data"), att = t.index_of ("attach-data"), id = t.index_of ("id");
    assert (t.columns[mv].kind == MdbColumnType.COMPLEX && t.columns[mv].complex_kind == MdbComplexKind.MULTI_VALUE);
    assert (t.columns[att].complex_kind == MdbComplexKind.ATTACHMENT);
    assert (f.complex_kind (t, att) == MdbComplexKind.ATTACHMENT);
    int vh = -1;
    for (int c = 0; c < t.columns.size; c++) {
        if (t.columns[c].name.has_prefix ("VersionHistory_")) vh = c;
    }
    assert (vh >= 0 && t.columns[vh].complex_kind == MdbComplexKind.VERSION_HISTORY);
    string[] want_mv = { "", "value1,value4", "value1,value2,value3,value4", "" };
    string[] want_att = { "", "test_data.txt,test_data2.txt", "", "test_data2.txt" };
    for (int r = 0; r < t.rows.size; r++) {
        int k = int.parse (t.rows[r].get (id).to_string ().substring (3)) - 1;
        assert (mv_text (f, t, r, mv) == want_mv[k]);
        string[] names = {};
        foreach (var a in f.attachments (t, r, att)) {
            names += a.name;
            assert (a.file_type == "txt");
            string body = a.name == "test_data.txt" ? "this is some test data for attachment." : "this is some more test data for attachment.";
            assert (a.data.get_size () == body.length);
            assert (Checksum.compute_for_bytes (ChecksumType.SHA256, a.data) == Checksum.compute_for_string (ChecksumType.SHA256, body));
        }
        assert (string.joinv (",", names) == want_att[k]);
        assert (f.attachments (t, r, mv).size == 0 && f.multi_values (t, r, att).size == 0);
    }
    print ("%s: complex columns ok\n", Path.get_basename (path));
}

void dump (string path) throws Error {
    var f = MdbFile.open (path);
    print ("== %s forms=%d reports=%d macros=%d modules=%d\n", path, f.form_names.length, f.report_names.length, f.macro_names.length, f.module_names.length);
    foreach (var q in f.queries) print ("-- %s kind=%d params=%s\n%s\n", q.name, (int) q.kind, string.joinv ("|", q.parameters), q.sql);
    foreach (var t in f.tables) {
        for (int c = 0; c < t.columns.size; c++) {
            if (Environment.get_variable ("MDB_COLS") != null) print ("col %s.%s kind=%d rows=%d\n", t.name, t.columns[c].name, (int) t.columns[c].kind, t.rows.size);
            if (t.columns[c].kind != MdbColumnType.COMPLEX) continue;
            print ("complex %s.%s kind=%d\n", t.name, t.columns[c].name, (int) t.columns[c].complex_kind);
            for (int r = 0; r < t.rows.size; r++) {
                foreach (var a in f.attachments (t, r, c)) print ("  row %d att %s %s %d [%s]\n", r, a.name, a.file_type, (int) a.data.get_size (), ((string) a.data.get_data ()).substring (0, int.min (80, (int) a.data.get_size ())));
                foreach (var v in f.multi_values (t, r, c)) print ("  row %d mv %s\n", r, v.to_string ());
            }
        }
    }
}

void test_office_encrypted (string path, string password, string table, string[] expected, string kind) throws Error {
    string name = Path.get_basename (path);
    try {
        MdbFile.open (path);
        assert_not_reached ();
    } catch (MdbError.PASSWORD e) {
    }
    try {
        MdbFile.open (path, "WrongPassword");
        assert_not_reached ();
    } catch (MdbError.PASSWORD e) {
        assert (e.message == "The password is not correct.");
    }
    var timer = new Timer ();
    var f = MdbFile.open (path, password);
    double secs = timer.elapsed ();
    assert (f.has_password);
    if (f.office_encryption != kind) error ("%s: encryption %s, expected %s", name, f.office_encryption, kind);
    var t = f.find_table (table);
    assert (t != null);
    int fi = t.index_of ("Field1");
    string[] got = {};
    foreach (var r in t.rows) got += r.get (fi).is_null ? "(null)" : r.get (fi).to_string ();
    if (string.joinv (",", got) != string.joinv (",", expected)) error ("%s: rows [%s]", name, string.joinv (",", got));
    print ("%s: %s, %d rows, %.2fs\n", name, f.office_encryption, t.rows.size, secs);
}

void main () {
    string? dp = Environment.get_variable ("MDB_DUMP");
    if (dp != null) {
        try {
            dump (dp);
        } catch (Error e) {
            print ("dump error %s\n", e.message);
        }
        return;
    }
    test_helpers ();
    test_errors ();
    try {
        test_attachment_codec ();
        foreach (string q in new string[] { "queryTestV1997.mdb", "queryTestV2003.mdb", "queryTestV2007.accdb" }) {
            string? qp = fixture (q);
            if (qp != null) test_queries (qp);
            else print ("%s: skipped\n", q);
        }
        foreach (string c in new string[] { "complexDataTestV2007.accdb", "complexDataTestV2010.accdb" }) {
            string? cp = fixture (c);
            if (cp != null) test_complex (cp);
            else print ("%s: skipped\n", c);
        }
        string? nwind = fixture ("nwind.mdb");
        if (nwind != null) {
            test_northwind (nwind);
            test_northwind_objects (nwind);
            test_password (nwind);
        }
        else print ("nwind.mdb: skipped, set MDB_FIXTURES to the fixtures directory\n");
        string? dates = fixture ("DateTestDatabase.mdb");
        if (dates != null) {
            test_dates (dates);
            test_password (dates);
        }
        else print ("DateTestDatabase.mdb: skipped\n");
        string? enc_dir = Environment.get_variable ("MDB_FIXTURES");
        string? e1 = enc_dir != null ? Path.build_filename (enc_dir, "encrypted", "db2007-oldenc.accdb") : null;
        if (e1 != null && FileUtils.test (e1, FileTest.EXISTS)) {
            string d = Path.get_dirname (e1);
            test_office_encrypted (e1, "Test123", "Table1", { "foo" }, "RC4 CryptoAPI");
            test_office_encrypted (Path.build_filename (d, "db2007-enc.accdb"), "Test123", "Table1", { "foo" }, "Agile AES");
            test_office_encrypted (Path.build_filename (d, "db2013-enc.accdb"), "1234", "Customers", { "Test", "Test2", "a", "(null)", "c", "d", "f" }, "Agile AES");
            test_office_encrypted (Path.build_filename (d, "db-nonstandard.accdb"), "password", "Table_One", { "test" }, "AES");
            foreach (string gen in new string[] { "standard-aes.accdb", "standard-aes-jackcess.accdb" }) {
                string gp = Path.build_filename (d, gen);
                if (!FileUtils.test (gp, FileTest.EXISTS)) continue;
                try {
                    MdbFile.open (gp, "wrong");
                    assert_not_reached ();
                } catch (MdbError.PASSWORD e) {
                }
                var g = MdbFile.open (gp, "Sésamo 42");
                var gt = g.find_table ("Asset Items");
                assert (g.office_encryption == "AES" && gt != null && gt.rows.size == 65);
                var gr = find_row (gt, "Asset No", "30050");
                assert (gr != null && cell (gt, gr, "Make") == "GEO Rocket");
                print ("%s: AES, 65 rows\n", gen);
            }
        } else {
            print ("encrypted accdb: skipped\n");
        }
        string? accdb = fixture ("ASampleDatabase.accdb");
        if (accdb != null) test_accdb (accdb);
        else print ("ASampleDatabase.accdb: skipped\n");
    } catch (Error e) {
        error ("mdb: %s", e.message);
    }
    print ("mdb tests passed\n");
}
