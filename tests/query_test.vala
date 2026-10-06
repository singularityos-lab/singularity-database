using Singularity.Apps.Database;

int checks = 0;

void ok (bool cond, string what) {
    checks++;
    if (!cond) {
        stderr.printf ("FAIL: %s\n", what);
        Process.exit (1);
    }
}

void eq (string got, string want, string what) {
    checks++;
    if (got != want) {
        stderr.printf ("FAIL: %s\n  got:  %s\n  want: %s\n", what, got, want);
        Process.exit (1);
    }
}

Database sample () throws Error {
    var db = Database.memory ();
    db.exec ("""
        CREATE TABLE Customers (ID INTEGER PRIMARY KEY, Name TEXT, City TEXT, Joined DATE);
        CREATE TABLE Orders (ID INTEGER PRIMARY KEY, Customer INTEGER REFERENCES Customers(ID), Placed DATE, Total REAL, Status TEXT);
        CREATE TABLE Lines (ID INTEGER PRIMARY KEY, "Order" INTEGER REFERENCES Orders(ID), Item TEXT, Qty INTEGER, Price REAL);
        INSERT INTO Customers VALUES (1, 'Ada', 'Rome', '2023-01-10'), (2, 'Bob', 'Milan', '2024-02-01'), (3, 'Cy', 'Rome', '2024-07-15'), (4, 'Di', NULL, NULL);
        INSERT INTO Orders VALUES (1, 1, '2024-01-05', 100, 'Paid'), (2, 1, '2024-03-10', 50.5, 'Open'), (3, 2, '2024-03-11', 20, 'Paid'), (4, 3, '2024-04-01', 75, 'Open'), (5, NULL, '2024-04-02', 5, 'Paid');
        INSERT INTO Lines VALUES (1, 1, 'Pen', 10, 2), (2, 1, 'Ink', 2, 40), (3, 2, 'Pen', 5, 2), (4, 3, 'Paper', 4, 5), (5, 4, 'Pen%', 1, 75);
    """);
    return db;
}

void test_criteria () {
    string e = "\"x\"";
    eq (Criteria.to_sql (e, "5"), "\"x\" = 5", "number");
    eq (Criteria.to_sql (e, ">= 10"), "\"x\" >= 10", "ge");
    eq (Criteria.to_sql (e, "<>'a'"), "\"x\" <> 'a'", "ne quoted");
    eq (Criteria.to_sql (e, "!= 3"), "\"x\" <> 3", "bang equals");
    eq (Criteria.to_sql (e, "Rome"), "\"x\" = 'Rome'", "bare text");
    eq (Criteria.to_sql (e, "\"it's\""), "\"x\" = 'it''s'", "double quoted text");
    eq (Criteria.to_sql (e, "Is Null"), "\"x\" IS NULL", "is null");
    eq (Criteria.to_sql (e, "is not null"), "\"x\" IS NOT NULL", "is not null");
    eq (Criteria.to_sql (e, "= Null"), "\"x\" IS NULL", "equals null");
    eq (Criteria.to_sql (e, "Between 1 And 5"), "\"x\" BETWEEN 1 AND 5", "between");
    eq (Criteria.to_sql (e, "between #2024-01-01# and #2024-12-31#"), "\"x\" BETWEEN '2024-01-01' AND '2024-12-31'", "between dates");
    eq (Criteria.to_sql (e, "Like \"A*\""), "\"x\" LIKE 'A%'", "like star");
    eq (Criteria.to_sql (e, "Like 'B?b'"), "\"x\" LIKE 'B_b'", "like question");
    eq (Criteria.to_sql (e, "Like '*50%*'"), "\"x\" LIKE '%50\\%%' ESCAPE '\\'", "like escape");
    eq (Criteria.to_sql (e, "A*"), "\"x\" LIKE 'A%'", "implicit like");
    eq (Criteria.to_sql (e, "Not \"x\""), "NOT (\"x\" = 'x')", "not");
    eq (Criteria.to_sql (e, "In (1, 2, 3)"), "\"x\" IN (1, 2, 3)", "in numbers");
    eq (Criteria.to_sql (e, "In ('a', \"b\")"), "\"x\" IN ('a', 'b')", "in strings");
    eq (Criteria.to_sql (e, "1 Or 2"), "(\"x\" = 1) OR (\"x\" = 2)", "or");
    eq (Criteria.to_sql (e, ">1 And <9"), "(\"x\" > 1) AND (\"x\" < 9)", "and");
    eq (Criteria.to_sql (e, "'Oregon' or 'Ohio'"), "(\"x\" = 'Oregon') OR (\"x\" = 'Ohio')", "or with quoted");
    eq (Criteria.to_sql (e, "'a or b'"), "\"x\" = 'a or b'", "or inside quotes");
    eq (Criteria.to_sql (e, "> Date()"), "\"x\" > date('now','localtime')", "date function");
    eq (Criteria.to_sql (e, "#2024-02-03#"), "\"x\" = '2024-02-03'", "date literal");
    eq (Criteria.to_sql (e, "> [Other]"), "\"x\" > \"Other\"", "field reference");
    eq (Criteria.to_sql (e, "yes"), "\"x\" = 1", "yes");
    eq (Criteria.to_sql (e, "=[T].[F] * 2"), "\"x\" = \"T\".\"F\" * 2", "expression");
    eq (Criteria.literal ("3,5"), "3.5", "comma decimal");
    eq (QueryDesign.bracket_refs ("[Qty] * [Lines].[Price] + '[no]'"), "\"Qty\" * \"Lines\".\"Price\" + '[no]'", "bracket refs");
}

void test_select (Database db) throws Error {
    var d = new QueryDesign ();
    d.add_table ("Customers");
    d.add_column ("Customers", "Name");
    d.add_column ("Customers", "City");
    eq (d.to_sql (), "SELECT \"Customers\".\"Name\", \"Customers\".\"City\"\nFROM \"Customers\"", "simple select");
    var rs = db.query (d.to_sql ());
    ok (rs.rows.size == 4, "simple rows");
    d.columns[1].set_criterion (0, "Rome");
    d.columns[0].sort = SortOrder.DESCENDING;
    eq (d.to_sql (), "SELECT \"Customers\".\"Name\", \"Customers\".\"City\"\nFROM \"Customers\"\nWHERE \"Customers\".\"City\" = 'Rome'\nORDER BY \"Customers\".\"Name\" DESC", "criteria and sort");
    rs = db.query (d.to_sql ());
    ok (rs.rows.size == 2 && rs.rows[0].get (0).to_string () == "Cy", "criteria rows");
    d.columns[1].set_criterion (1, "Milan");
    rs = db.query (d.to_sql ());
    ok (rs.rows.size == 3, "or row");
    ok (d.to_sql ().contains ("WHERE (\"Customers\".\"City\" = 'Rome') OR (\"Customers\".\"City\" = 'Milan')"), "or rows sql");
    d.columns[1].show = false;
    rs = db.query (d.to_sql ());
    ok (rs.columns.length == 1, "hidden column");
    var e = d.add_column ("", "");
    e.expression = "upper([Name]) || '!'";
    e.alias = "Shout";
    rs = db.query (d.to_sql ());
    ok (rs.columns[1] == "Shout" && rs.rows[0].get (1).to_string () == "CY!", "expression column");
    var noalias = new QueryColumn.expr ("1 + 1", "");
    d.columns.add (noalias);
    ok (d.to_sql ().contains ("1 + 1 AS \"Expr4\""), "default expr alias");
    d.columns.remove (noalias);
    d.distinct = true;
    d.limit = 1;
    ok (d.to_sql ().has_prefix ("SELECT DISTINCT") && d.to_sql ().has_suffix ("LIMIT 1"), "distinct and limit");
    ok (db.query (d.to_sql ()).rows.size == 1, "limit rows");
    var star = new QueryDesign ();
    star.add_table ("Orders");
    ok (star.to_sql () == "SELECT *\nFROM \"Orders\"", "star when no columns");
    star.add_column ("Orders", "*");
    ok (star.to_sql () == "SELECT \"Orders\".*\nFROM \"Orders\"", "table star");
}

void test_joins (Database db) throws Error {
    var d = new QueryDesign ();
    d.add_table ("Customers");
    d.add_table ("Orders");
    d.auto_join (db);
    ok (d.joins.size == 1 && d.joins[0].left == "Customers" && d.joins[0].right == "Orders", "auto join");
    d.add_column ("Customers", "Name");
    d.add_column ("Orders", "Total");
    string sql = d.to_sql ();
    ok (sql.contains ("FROM \"Customers\"\nINNER JOIN \"Orders\" ON \"Customers\".\"ID\" = \"Orders\".\"Customer\""), "inner join sql: " + sql);
    ok (db.query (sql).rows.size == 4, "inner join rows");
    d.joins[0].kind = JoinKind.LEFT;
    ok (db.query (d.to_sql ()).rows.size == 5, "left join rows (Di has none)");
    d.joins[0].kind = JoinKind.RIGHT;
    ok (db.query (d.to_sql ()).rows.size == 5, "right join rows (order 5 has no customer)");
    d.joins[0].kind = JoinKind.FULL;
    ok (db.query (d.to_sql ()).rows.size == 6, "full join rows");
    var rev = new QueryDesign ();
    rev.add_table ("Orders");
    rev.add_table ("Customers");
    rev.joins.add (new QueryJoin ("Customers", "ID", "Orders", "Customer", JoinKind.LEFT));
    rev.add_column ("Customers", "Name");
    ok (rev.to_sql ().contains ("RIGHT JOIN \"Customers\""), "join direction flipped: " + rev.to_sql ());
    ok (db.query (rev.to_sql ()).rows.size == 5, "flipped join rows");
    var three = new QueryDesign ();
    three.add_table ("Customers");
    three.add_table ("Orders");
    three.add_table ("Lines");
    three.auto_join (db);
    ok (three.joins.size == 2, "chain join");
    three.add_column ("Customers", "Name");
    three.add_column ("Lines", "Item");
    three.columns[1].set_criterion (0, "Like 'Pen*'");
    var rs = db.query (three.to_sql ());
    ok (rs.rows.size == 3, "three table join rows %d".printf (rs.rows.size));
    var self_join = new QueryDesign ();
    var a = self_join.add_table ("Customers");
    var b = self_join.add_table ("Customers");
    ok (a.alias == "Customers" && b.alias == "Customers_1", "alias for second copy");
    self_join.joins.add (new QueryJoin (a.alias, "City", b.alias, "City"));
    self_join.add_column (a.alias, "Name");
    var other = self_join.add_column (b.alias, "Name");
    other.alias = "Neighbor";
    other.set_criterion (0, "<> [Customers].[Name]");
    rs = db.query (self_join.to_sql ());
    ok (rs.rows.size == 2 && self_join.to_sql ().contains ("\"Customers\" AS \"Customers_1\""), "self join");
    var cross = new QueryDesign ();
    cross.add_table ("Customers");
    cross.add_table ("Lines");
    ok (cross.to_sql ().contains ("CROSS JOIN \"Lines\"") && db.query (cross.to_sql ()).rows.size == 20, "cross join");
    var cyc = new QueryDesign ();
    cyc.add_table ("Customers");
    cyc.add_table ("Orders");
    cyc.joins.add (new QueryJoin ("Customers", "ID", "Orders", "Customer"));
    cyc.joins.add (new QueryJoin ("Orders", "ID", "Customers", "ID"));
    ok (cyc.to_sql ().contains ("ON \"Customers\".\"ID\" = \"Orders\".\"Customer\" AND \"Orders\".\"ID\" = \"Customers\".\"ID\""), "two conditions one join");
    db.query (cyc.to_sql ());
    cyc.remove_table ("Orders");
    ok (cyc.joins.size == 0 && cyc.tables.size == 1, "remove table drops joins");
}

void test_totals (Database db) throws Error {
    var d = new QueryDesign ();
    d.totals = true;
    d.add_table ("Customers");
    d.add_table ("Orders");
    d.auto_join (db);
    var name = d.add_column ("Customers", "City");
    name.total = Aggregate.GROUP_BY;
    name.sort = SortOrder.ASCENDING;
    var sum = d.add_column ("Orders", "Total");
    sum.total = Aggregate.SUM;
    var cnt = d.add_column ("Orders", "*");
    cnt.total = Aggregate.COUNT;
    var avg = d.add_column ("Orders", "Total");
    avg.total = Aggregate.AVG;
    avg.alias = "Average";
    string sql = d.to_sql ();
    ok (sql.contains ("SUM(\"Orders\".\"Total\") AS \"SumOfTotal\"") && sql.contains ("COUNT(*) AS \"CountOfRecords\"") && sql.contains ("GROUP BY \"Customers\".\"City\""), "totals sql: " + sql);
    var rs = db.query (sql);
    ok (rs.rows.size == 2, "groups");
    ok (rs.rows[0].get (0).to_string () == "Milan" && rs.rows[0].get (1).as_double () == 20, "milan sum");
    ok (rs.rows[1].get (1).as_double () == 225.5 && rs.rows[1].get (2).as_int () == 3, "rome sum and count");
    sum.set_criterion (0, "> 100");
    sql = d.to_sql ();
    ok (sql.contains ("HAVING SUM(\"Orders\".\"Total\") > 100"), "having");
    rs = db.query (sql);
    ok (rs.rows.size == 1 && rs.rows[0].get (0).to_string () == "Rome", "having rows");
    var w = d.add_column ("Orders", "Status");
    w.total = Aggregate.WHERE;
    w.set_criterion (0, "Paid");
    sql = d.to_sql ();
    ok (sql.contains ("WHERE \"Orders\".\"Status\" = 'Paid'") && !sql.contains ("\"Status\" AS"), "where total");
    rs = db.query (sql);
    ok (rs.rows.size == 0, "where then having leaves nothing");
    sum.set_criterion (0, "");
    rs = db.query (d.to_sql ());
    ok (rs.rows.size == 2 && rs.rows[1].get (1).as_double () == 100, "paid only per city");
    foreach (var agg in Aggregate.ALL) {
        if (!agg.is_aggregate ()) continue;
        var q = new QueryDesign ();
        q.totals = true;
        q.add_table ("Lines");
        var c = q.add_column ("Lines", "Qty");
        c.total = agg;
        var r = db.query (q.to_sql ());
        ok (r.rows.size == 1 && !r.rows[0].get (0).is_null, "aggregate " + agg.id ());
    }
    var sd = new QueryDesign ();
    sd.totals = true;
    sd.add_table ("Lines");
    var sc = sd.add_column ("Lines", "Qty");
    sc.total = Aggregate.STDEV;
    double v = db.query (sd.to_sql ()).rows[0].get (0).as_double ();
    ok (Math.fabs (v - Math.sqrt (((100 + 4 + 25 + 16 + 1) - 22 * 22 / 5.0) / 4.0)) < 1e-9, "sample stdev as in Access");
    sc.total = Aggregate.FIRST;
    var fl = sd.add_column ("Lines", "Qty");
    fl.total = Aggregate.LAST;
    var frs = db.query (sd.to_sql ());
    ok (frs.rows[0].get (0).as_int () == 10 && frs.rows[0].get (1).as_int () == 1, "first and last are record values, not min and max");
    var bad = new QueryDesign ();
    bad.totals = true;
    bad.add_table ("Lines");
    var hidden = bad.add_column ("Lines", "Qty");
    hidden.show = false;
    bool threw = false;
    try {
        bad.to_sql ();
    } catch (Error e) {
        threw = true;
    }
    ok (threw, "totals need a shown column");
    threw = false;
    try {
        new QueryDesign ().to_sql ();
    } catch (Error e) {
        threw = true;
    }
    ok (threw, "empty design rejected");
}

void test_action_queries (Database db) throws Error {
    var mk = new QueryDesign ();
    mk.query_type = QueryType.MAKE_TABLE;
    mk.target = "Rome Customers";
    mk.add_table ("Customers");
    mk.add_column ("Customers", "Name");
    mk.add_column ("Customers", "City").set_criterion (0, "Rome");
    string sql = mk.to_sql ();
    ok (sql.has_prefix ("CREATE TABLE \"Rome Customers\" AS\nSELECT"), "make table sql");
    db.run (sql);
    ok (db.count_rows ("Rome Customers") == 2, "make table rows");
    var ap = new QueryDesign ();
    ap.query_type = QueryType.APPEND;
    ap.target = "Rome Customers";
    ap.add_table ("Customers");
    var n = ap.add_column ("Customers", "Name");
    n.append_to = "Name";
    var c = ap.add_column ("Customers", "City");
    c.append_to = "City";
    c.set_criterion (0, "Milan");
    sql = ap.to_sql ();
    ok (sql.has_prefix ("INSERT INTO \"Rome Customers\" (\"Name\", \"City\")\nSELECT \"Customers\".\"Name\", \"Customers\".\"City\""), "append sql: " + sql);
    db.run (sql);
    ok (db.count_rows ("Rome Customers") == 3, "append rows");
    var up = new QueryDesign ();
    up.query_type = QueryType.UPDATE;
    up.add_table ("Orders");
    var tot = up.add_column ("Orders", "Total");
    tot.update_to = "=[Total] * 2";
    up.add_column ("Orders", "Status").set_criterion (0, "Open");
    sql = up.to_sql ();
    eq (sql, "UPDATE \"Orders\" SET \"Total\" = \"Total\" * 2\nWHERE \"Status\" = 'Open'", "update sql");
    db.run (sql);
    ok (db.query_int ("SELECT sum(Total) FROM Orders WHERE Status = 'Open'") == 251, "update applied");
    var lit = new QueryDesign ();
    lit.query_type = QueryType.UPDATE;
    lit.add_table ("Orders");
    lit.add_column ("Orders", "Status").update_to = "Archived";
    eq (lit.to_sql (), "UPDATE \"Orders\" SET \"Status\" = 'Archived'", "update literal");
    var cross = new QueryDesign ();
    cross.query_type = QueryType.DELETE;
    cross.add_table ("Orders");
    cross.add_table ("Customers");
    cross.auto_join (db);
    cross.add_column ("Customers", "City").set_criterion (0, "Milan");
    sql = cross.to_sql ();
    ok (sql.has_prefix ("DELETE FROM \"Orders\"\nWHERE EXISTS (SELECT 1 FROM \"Customers\" WHERE \"Customers\".\"ID\" = \"Orders\".\"Customer\""), "delete with related criteria: " + sql);
    int before = (int) db.count_rows ("Orders");
    db.exec ("PRAGMA foreign_keys = OFF");
    db.run (sql);
    db.exec ("PRAGMA foreign_keys = ON");
    ok (db.count_rows ("Orders") == before - 1, "delete applied");
    var need = new QueryDesign ();
    need.query_type = QueryType.UPDATE;
    need.add_table ("Orders");
    need.add_column ("Orders", "Total");
    bool threw = false;
    try {
        need.to_sql ();
    } catch (Error e) {
        threw = true;
    }
    ok (threw, "update needs values");
}

void test_json (Database db) throws Error {
    var d = new QueryDesign ();
    d.query_type = QueryType.SELECT;
    d.totals = true;
    d.distinct = true;
    d.limit = 7;
    var t = d.add_table ("Customers");
    t.x = 120;
    t.y = 40;
    d.add_table ("Orders");
    d.auto_join (db);
    d.joins[0].kind = JoinKind.LEFT;
    var c = d.add_column ("Customers", "City");
    c.set_criterion (0, "Rome");
    c.set_criterion (2, "Milan");
    c.sort = SortOrder.DESCENDING;
    var s = d.add_column ("Orders", "Total");
    s.total = Aggregate.MAX;
    s.alias = "Top";
    var back = QueryDesign.from_json (d.to_json ());
    ok (back != null, "parse json");
    eq (back.to_sql (), d.to_sql (), "json roundtrip sql");
    ok (back.tables[0].x == 120 && back.joins[0].kind == JoinKind.LEFT && back.columns[0].criteria.length == 3, "json details");
    ok (QueryDesign.from_json ("not json") == null, "bad json");
}

void test_saved_design (Database db) throws Error {
    var d = new QueryDesign ();
    d.add_table ("Orders");
    d.add_column ("Orders", "Status");
    var q = new QueryDef ("Statuses", d.to_sql ());
    q.design = d.to_json ();
    db.save_query (q);
    var back = db.load_query ("Statuses");
    var nd = QueryDesign.from_json (back.design);
    eq (nd.to_sql (), back.sql, "saved design matches view body");
    var rs = new RecordSource (db, "Statuses");
    ok (rs.count () == 4 && rs.def.fields.size == 1, "query as record source");
}

int main (string[] args) {
    Locale.set_default (Locale.neutral ());
    try {
        test_criteria ();
        var db = sample ();
        test_select (db);
        test_joins (db);
        test_totals (db);
        test_json (db);
        test_action_queries (db);
        test_saved_design (db);
    } catch (Error e) {
        stderr.printf ("FAIL: unexpected error: %s\n", e.message);
        return 1;
    }
    print ("query: %d checks passed\n", checks);
    return 0;
}
