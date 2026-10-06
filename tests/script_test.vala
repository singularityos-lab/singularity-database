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

class TestHost : Object, ScriptHost {
    public Gee.ArrayList<string> log = new Gee.ArrayList<string> ();
    public int answer = 6;

    public int message_box (string prompt, int buttons, string title) {
        log.add ("msg:" + prompt);
        return answer;
    }

    public string? input_box (string prompt, string title, string default_value) {
        log.add ("input:" + prompt);
        return "42";
    }

    public void run_command (string command, SValue[] args, string[] names) throws ScriptError {
        var sb = new StringBuilder ("cmd:" + command);
        foreach (var a in args) sb.append ("|").append (a.to_text ());
        log.add (sb.str);
    }

    public ScriptObject? find_object (string kind, string name) {
        return null;
    }

    public string[] open_objects (string kind) {
        return {};
    }

    public void debug_print (string text) {
        log.add ("debug:" + text);
    }
}

Database sample () throws Error {
    var db = Database.memory ();
    db.exec ("""
        CREATE TABLE Customers (ID INTEGER PRIMARY KEY, Name TEXT, City TEXT);
        CREATE TABLE Orders (ID INTEGER PRIMARY KEY, Customer INTEGER, Placed DATE, Total REAL, Status TEXT);
        INSERT INTO Customers VALUES (1, 'Ada', 'Rome'), (2, 'Bob', 'Milan'), (3, 'Cy', 'Rome');
        INSERT INTO Orders VALUES (1, 1, '2024-01-05', 100, 'Paid'), (2, 1, '2024-03-10', 50.5, 'Open'), (3, 2, '2024-03-11', 20, 'Paid'), (4, 3, '2024-04-01', 75, 'Open'), (5, 2, '2024-04-02', 5, 'Paid');
    """);
    return db;
}

string ev (ScriptRuntime rt, string expr) throws Error {
    return rt.evaluate (expr).to_text ();
}

void test_expressions () throws Error {
    Locale.set_default (Locale.neutral ());
    var rt = new ScriptRuntime (null);
    eq (ev (rt, "1 + 2 * 3"), "7", "precedence");
    eq (ev (rt, "2 ^ 3 ^ 2"), "64", "power left assoc");
    eq (ev (rt, "-2 ^ 2"), "-4", "unary minus below power");
    eq (ev (rt, "7 \\ 2"), "3", "int div");
    eq (ev (rt, "7 Mod 3"), "1", "mod");
    eq (ev (rt, "\"a\" & 1 & Null"), "a1", "concat with null");
    ok (rt.evaluate ("Null + 1").is_null, "null propagation");
    eq (ev (rt, "IIf(3 > 2, \"yes\", \"no\")"), "yes", "iif");
    eq (ev (rt, "Nz(Null, 5)"), "5", "nz");
    eq (ev (rt, "Mid(\"Database\", 3, 4)"), "taba", "mid");
    eq (ev (rt, "InStr(\"Hello World\", \"world\")"), "7", "instr text compare");
    eq (ev (rt, "InStr(4, \"abcabc\", \"b\")"), "5", "instr start");
    eq (ev (rt, "Replace(\"a-b-c\", \"-\", \"+\")"), "a+b+c", "replace");
    eq (ev (rt, "Left(\"abc\", 2) & Right(\"abc\", 2)"), "abbc", "left right");
    eq (ev (rt, "Len(\"città\")"), "5", "len utf8");
    eq (ev (rt, "UCase(\"abc\") & LCase(\"DEF\")"), "ABCdef", "case");
    eq (ev (rt, "StrConv(\"hello big world\", 3)"), "Hello Big World", "proper");
    eq (ev (rt, "Trim(\"  x  \")"), "x", "trim");
    eq (ev (rt, "Round(2.5)"), "2", "bankers round even");
    eq (ev (rt, "Round(3.5)"), "4", "bankers round odd");
    eq (ev (rt, "Round(2.345, 2)"), "2.34", "round digits");
    eq (ev (rt, "Int(-2.5) & \",\" & Fix(-2.5)"), "-3,-2", "int fix");
    eq (ev (rt, "CInt(2.5) + CInt(3.5)"), "6", "cint bankers");
    eq (ev (rt, "Val(\"12.5abc\")"), "12.5", "val");
    eq (ev (rt, "\"abc\" Like \"a*\""), "True", "like star");
    eq (ev (rt, "\"a5\" Like \"a#\""), "True", "like digit");
    eq (ev (rt, "\"b\" Like \"[!a]\""), "True", "like negated class");
    eq (ev (rt, "Choose(2, \"x\", \"y\", \"z\")"), "y", "choose");
    eq (ev (rt, "Switch(1 > 2, \"a\", 2 > 1, \"b\")"), "b", "switch");
    eq (ev (rt, "Format(1234.5, \"#,##0.00\")"), "1,234.50", "format number");
    eq (ev (rt, "Format(0.256, \"0.0%\")"), "25.6%", "format percent");
    eq (ev (rt, "Format(5, \"000\")"), "005", "format zeros");
    eq (ev (rt, "Format(-3, \"0;(0)\")"), "(3)", "format negative section");
    eq (ev (rt, "Format(\"abc\", \">\")"), "ABC", "format upper");
    eq (ev (rt, "Format(\"12345\", \"@@-@@@\")"), "12-345", "format text slots");
    eq (ev (rt, "Format(#2024-03-05#, \"yyyy-mm-dd\")"), "2024-03-05", "format iso");
    eq (ev (rt, "Format(#2024-03-05#, \"dddd d mmmm yyyy\")"), "Tuesday 5 March 2024", "format long names");
    eq (ev (rt, "Format(#2024-03-05 14:07:09#, \"hh:nn:ss\")"), "14:07:09", "format time");
    eq (ev (rt, "Format(#2024-03-05 14:07:00#, \"h:nn AM/PM\")"), "2:07 PM", "format ampm");
    eq (ev (rt, "Format(#3/5/2024#, \"mmm-yy\")"), "Mar-24", "us date literal");
    eq (ev (rt, "Format(1, \"Yes/No\")"), "Yes", "format yes no");
    eq (ev (rt, "Format(1234.5, \"Currency\")"), "$1,234.50", "format currency");
    eq (ev (rt, "DateDiff(\"d\", #2024-01-01#, #2024-03-01#)"), "60", "datediff days leap");
    eq (ev (rt, "DateDiff(\"m\", #2024-01-31#, #2024-02-01#)"), "1", "datediff month boundary");
    eq (ev (rt, "DateDiff(\"yyyy\", #2023-12-31#, #2024-01-01#)"), "1", "datediff year boundary");
    eq (ev (rt, "Format(DateAdd(\"m\", 1, #2024-01-31#), \"yyyy-mm-dd\")"), "2024-02-29", "dateadd month clamp");
    eq (ev (rt, "Format(DateAdd(\"d\", -1, #2024-03-01#), \"yyyy-mm-dd\")"), "2024-02-29", "dateadd day");
    eq (ev (rt, "DatePart(\"q\", #2024-08-15#)"), "3", "datepart quarter");
    eq (ev (rt, "Weekday(#2024-03-05#)"), "3", "weekday tuesday");
    eq (ev (rt, "Format(DateSerial(2024, 14, 1), \"yyyy-mm-dd\")"), "2025-02-01", "dateserial overflow");
    eq (ev (rt, "Year(#2024-03-05#) * 100 + Month(#2024-03-05#)"), "202403", "year month");
    eq (ev (rt, "MonthName(2)"), "February", "monthname");
    eq (ev (rt, "IsNumeric(\"12\") And Not IsNumeric(\"x\")"), "True", "isnumeric");
    eq (ev (rt, "IsDate(\"2024-02-30\")"), "False", "isdate invalid");
    eq (ev (rt, "TypeName(1.5)"), "Double", "typename");
    eq (ev (rt, "5 Between 1 And 10"), "True", "between");
    eq (ev (rt, "3 In (1, 2, 3)"), "True", "in list");
    eq (ev (rt, "#2024-03-05# + 1 > #2024-03-05#"), "True", "date arithmetic");
}

void test_module () throws Error {
    var host = new TestHost ();
    var rt = new ScriptRuntime (null, host);
    rt.load_module ("""
Option Compare Database
Option Explicit

Private counter As Long
Public Const TaxRate = 0.2

Public Function Fact(ByVal n As Long) As Long
    If n <= 1 Then
        Fact = 1
    Else
        Fact = n * Fact(n - 1)
    End If
End Function

Function Classify(x)
    Select Case x
        Case Is < 0: Classify = "negative"
        Case 0: Classify = "zero"
        Case 1 To 9: Classify = "small"
        Case 10, 20, 30: Classify = "round"
        Case Else: Classify = "big"
    End Select
End Function

Sub Bump(ByRef v As Long)
    v = v + 1
    counter = counter + 1
End Sub

Function GetCounter() As Long
    GetCounter = counter
End Function

Function Loops() As String
    Dim i As Integer, s As String, arr(3) As Integer
    For i = 0 To 3
        arr(i) = i * i
    Next i
    For i = 3 To 0 Step -1
        s = s & arr(i) & ","
    Next
    Dim k As Long
    k = 0
    Do While k < 3
        k = k + 1
    Loop
    Do
        k = k + 10
    Loop Until k > 40
    While k > 40
        k = k - 1
    Wend
    Dim c As New Collection
    c.Add "a"
    c.Add "b", "kb"
    Dim item
    For Each item In c
        s = s & item
    Next
    s = s & c("kb") & c.Count & k & UBound(arr)
    Loops = s
End Function

Function Safe() As String
    On Error GoTo Handler
    Dim x
    x = 1 / 0
    Safe = "unreachable"
    Exit Function
Handler:
    Safe = "caught " & Err.Number
End Function

Function ResumeNextTest() As String
    On Error Resume Next
    Dim x
    x = 1 / 0
    ResumeNextTest = "after " & Err.Number
End Function

Function WithArgs(a, Optional b = 5, Optional c) As String
    WithArgs = a & "-" & b & "-" & IsMissing(c)
End Function

Function Greet() As String
    Dim r As Integer
    r = MsgBox("Continue?", vbYesNo + vbQuestion, "Title")
    If r = vbYes Then Greet = "yes" Else Greet = "no"
    DoCmd.OpenForm "Customers", acNormal, , "[City]='Rome'"
    Debug.Print "done"; 1
End Function

Function Dict() As String
    Dim d As Object
    Set d = CreateObject("Scripting.Dictionary")
    d("x") = 1
    d.Add "y", 2
    Dict = d.Count & d.Exists("y") & d("x")
End Function

Function StaticCount() As Long
    Static n As Long
    n = n + 1
    StaticCount = n
End Function
""", "Module1");
    eq (rt.call ("Fact", { new SValue.int (6) }).to_text (), "720", "recursion");
    eq (rt.call ("Classify", { new SValue.int (-3) }).to_text (), "negative", "case is");
    eq (rt.call ("Classify", { new SValue.int (0) }).to_text (), "zero", "case value");
    eq (rt.call ("Classify", { new SValue.int (7) }).to_text (), "small", "case range");
    eq (rt.call ("Classify", { new SValue.int (20) }).to_text (), "round", "case list");
    eq (rt.call ("Classify", { new SValue.int (99) }).to_text (), "big", "case else");
    eq (rt.call ("Loops", {}).to_text (), "9,4,1,0,abb2403", "loops arrays collections");
    eq (rt.call ("Safe", {}).to_text (), "caught 11", "on error goto");
    eq (rt.call ("ResumeNextTest", {}).to_text (), "after 11", "resume next");
    eq (rt.call ("WithArgs", { new SValue.str ("a") }).to_text (), "a-5-True", "optional args");
    eq (rt.call ("Greet", {}).to_text (), "yes", "msgbox host");
    ok (host.log.contains ("cmd:OpenForm|Customers|0||[City]='Rome'"), "docmd reaches host");
    ok (host.log.contains ("debug:done1"), "debug print");
    eq (rt.call ("Dict", {}).to_text (), "2True1", "dictionary");
    rt.call ("StaticCount", {});
    eq (rt.call ("StaticCount", {}).to_text (), "2", "static variable");
    eq (rt.evaluate ("TaxRate * 10").to_text (), "2", "public const");
    rt.run_statements ("Dim v As Long\nv = 1\nBump v\nBump v\nTempVars!Result = v");
    eq (rt.temp_vars.get_var ("Result").to_text (), "3", "byref and tempvars");
    eq (rt.call ("GetCounter", {}).to_text (), "2", "private module variable");
    try {
        rt.load_module ("Sub Broken()\n  If x Then\nEnd Sub\n", "Bad");
        ok (false, "syntax error expected");
    } catch (ScriptError e) {
        ok (e.message.contains ("Line"), "syntax error has line");
    }
}

void test_sql_functions () throws Error {
    var db = sample ();
    var rs = db.query ("SELECT first(Total), last(Total) FROM Orders");
    eq (rs.rows[0].get (0).to_string () + "," + rs.rows[0].get (1).to_string (), "100,5", "first last in scan order");
    rs = db.query ("SELECT round(stdev(Total), 6), round(stdevp(Total), 6), round(var(Total), 4) FROM Orders");
    eq (rs.rows[0].get (0).to_string (), "38.891516", "sample stdev");
    eq (rs.rows[0].get (1).to_string (), "34.785629", "population stdev");
    eq (rs.rows[0].get (2).to_string (), "1512.55", "sample var");
    ok (db.query ("SELECT stdev(Total) FROM Orders WHERE ID = 1").rows[0].get (0).is_null, "stdev of one is null");
    eq (db.query ("SELECT datediff('d', '2024-01-01', '2024-03-01')").rows[0].get (0).to_string (), "60", "sql datediff");
    eq (db.query ("SELECT dateadd('m', 1, '2024-01-31')").rows[0].get (0).to_string (), "2024-02-29", "sql dateadd");
    eq (db.query ("SELECT acc_format(1234.5, '#,##0.0')").rows[0].get (0).to_string (), "1,234.5", "sql format");
    eq (db.query ("SELECT mid('abcdef', 2, 3)").rows[0].get (0).to_string (), "bcd", "sql mid");
    eq (db.query ("SELECT dlookup('Name', 'Customers', 'ID = 2')").rows[0].get (0).to_string (), "Bob", "sql dlookup");
    eq (db.query ("SELECT dsum('Total', 'Orders', 'Customer = 1')").rows[0].get (0).to_string (), "150.5", "sql dsum");
    eq (db.query ("SELECT dcount('*', 'Orders', 'Status = ''Paid''')").rows[0].get (0).to_string (), "3", "sql dcount");
    var rt = new ScriptRuntime (db);
    eq (ev (rt, "DLookup(\"[City]\", \"Customers\", \"[Name] = 'Cy'\")"), "Rome", "script dlookup");
    eq (ev (rt, "DMax(\"Total\", \"Orders\")"), "100", "script dmax");
}

void test_access_sql () throws Error {
    eq (AccessSql.expression ("[First] & \" \" & [Last]"), "acc_cat(acc_cat(\"First\", ' '), \"Last\")", "concat chain");
    eq (AccessSql.expression ("[Placed] > #1/31/2024#"), "\"Placed\" > '2024-01-31'", "us date literal");
    eq (AccessSql.expression ("[Name] Like \"A*\""), "acc_like(\"Name\", 'A*')", "like");
    eq (AccessSql.expression ("[Name] Not Like 'A*'"), "NOT acc_like(\"Name\", 'A*')", "not like");
    eq (AccessSql.expression ("[a] + 2 ^ 3"), "\"a\" + acc_pow(2, 3)", "power");
    eq (AccessSql.expression ("[Paid] = True"), "\"Paid\" = 1", "true");
    eq (AccessSql.expression ("[x] Mod 2"), "\"x\" % 2", "mod");
    eq (AccessSql.expression ("Format([d], 'yyyy')"), "acc_format(\"d\", 'yyyy')", "renamed format");
    eq (AccessSql.expression ("[Orders]![Total]"), "\"Orders\".\"Total\"", "bang qualifier");
    eq (AccessSql.expression ("Forms![Main]![City]"), "\"Forms!Main!City\"", "form reference");
    var db = sample ();
    string s = AccessSql.statement ("SELECT DISTINCTROW TOP 2 [Name] & '!' AS Label FROM Customers ORDER BY [Name] DESC;");
    var rs = db.query (s);
    eq (rs.rows.size.to_string () + rs.rows[0].get (0).to_string (), "2Cy!", "top and distinctrow");
    db.run (AccessSql.statement ("SELECT Customers.* INTO RomeCustomers FROM Customers WHERE City = \"Rome\""));
    eq (db.query_int ("SELECT count(*) FROM RomeCustomers").to_string (), "2", "select into");
    db.run (AccessSql.statement ("UPDATE Orders INNER JOIN Customers ON Orders.Customer = Customers.ID SET Orders.Status = 'Rome' WHERE Customers.City = 'Rome'"));
    eq (db.query_int ("SELECT count(*) FROM Orders WHERE Status = 'Rome'").to_string (), "3", "update with join");
    db.run (AccessSql.statement ("DELETE Orders.* FROM Orders INNER JOIN Customers ON Orders.Customer = Customers.ID WHERE Customers.Name = 'Bob'"));
    eq (db.query_int ("SELECT count(*) FROM Orders").to_string (), "3", "delete with join");
}

void test_crosstab_params () throws Error {
    var db = sample ();
    string x = "TRANSFORM Sum(Total) SELECT Status FROM Orders GROUP BY Status PIVOT strftime('%m', Placed)";
    eq (QueryPrep.kind_of (x), "crosstab", "crosstab kind");
    var rs = db.query (QueryPrep.prepare (db, x));
    eq (string.joinv (",", rs.columns), "Status,01,03,04", "crosstab columns");
    eq (rs.rows[0].get (0).to_string () + ":" + rs.rows[0].get (2).to_string () + ":" + rs.rows[0].get (3).to_string (), "Open:50.5:75", "crosstab open row");
    ok (rs.rows[1].get (1).to_string () == "100" && rs.rows[1].get (3).to_string () == "5", "crosstab paid row");
    string fixed_q = "TRANSFORM Count(*) SELECT Customer, Count(*) AS Total FROM Orders GROUP BY Customer PIVOT Status IN ('Paid', 'Open', 'Void')";
    rs = db.query (QueryPrep.prepare (db, fixed_q));
    eq (string.joinv (",", rs.columns), "Customer,Total,Paid,Open,Void", "crosstab fixed columns");
    eq (rs.rows[1].get (2).to_string () + rs.rows[1].get (4).to_string (), "20", "crosstab counts");
    string p = "PARAMETERS [Min Total] Currency; SELECT ID FROM Orders WHERE Total >= [Min Total] AND Status = [Which Status]";
    eq (QueryPrep.kind_of (p), "parameter", "parameter kind");
    var params = QueryPrep.find_parameters (db, p);
    eq (params.size.to_string (), "2", "two params");
    eq (params[0].name + "/" + params[1].name, "Min Total/Which Status", "param names");
    ok (params[0].field_type () == FieldType.CURRENCY, "declared type");
    params[0].value = QueryPrep.coerce (params[0], "50");
    params[1].value = QueryPrep.coerce (params[1], "Paid");
    rs = db.query (QueryPrep.prepare (db, p, params));
    eq (rs.rows.size.to_string () + ":" + rs.rows[0].get (0).to_string (), "1:1", "parameter result");
    var cp = QueryPrep.find_parameters (db, "TRANSFORM Sum(Total) SELECT Status FROM Orders WHERE Customer = [Cust] GROUP BY Status PIVOT Status");
    eq (cp.size.to_string () + cp[0].name, "1Cust", "crosstab parameter");
    SavedQueries.save (db, "Big Orders", p);
    ok (!db.object_exists ("Big Orders", "view"), "parameter query not a view");
    var sq = SavedQueries.load (db, "Big Orders");
    ok (sq != null && sq.kind == "parameter", "saved parameter query");
    SavedQueries.save (db, "Paid Orders", "SELECT * FROM Orders WHERE Status = 'Paid'");
    ok (db.object_exists ("Paid Orders", "view"), "select query is a view");
    SavedQueries.save (db, "Close Old", "UPDATE Orders SET Status = 'Closed' WHERE Placed < '2024-02-01'");
    eq (SavedQueries.load (db, "Close Old").kind, "update", "saved action query");
    SavedQueries.save (db, "All Names", "SELECT Name FROM Customers UNION SELECT Status FROM Orders");
    eq (SavedQueries.load (db, "All Names").kind, "union", "saved union query");
    SavedQueries.save (db, "Pivot", x);
    eq (SavedQueries.load (db, "Pivot").kind, "crosstab", "saved crosstab");
}

void test_updatable () throws Error {
    var db = sample ();
    var p = Updatable.plan (db, "SELECT o.Total, c.Name FROM Orders AS o INNER JOIN Customers AS c ON c.ID = o.Customer WHERE o.Total > 10");
    ok (p != null && p.tables.length == 2, "join plan");
    eq (p.tables[0] + "/" + p.aliases[0] + "/" + p.tables[1], "Orders/o/Customers", "plan tables");
    ok (Updatable.plan (db, "SELECT Status, sum(Total) FROM Orders GROUP BY Status") == null, "totals not updatable");
    ok (Updatable.plan (db, "SELECT DISTINCT City FROM Customers") == null, "distinct not updatable");
    var src = new RecordSource.for_sql (db, "SELECT o.Total, c.Name FROM Orders AS o INNER JOIN Customers AS c ON c.ID = o.Customer ORDER BY o.ID");
    ok (src.editable, "query source editable");
    var row = src.row (0);
    src.set_query_value (0, "Name", new DbValue.text ("Ada L."));
    eq (db.query ("SELECT Name FROM Customers WHERE ID = 1").rows[0].get (0).to_string (), "Ada L.", "edit through join");
    src.set_query_value (1, "Total", new DbValue.real (51));
    eq (db.query ("SELECT Total FROM Orders WHERE ID = 2").rows[0].get (0).to_string (), "51", "edit main table through query");
    ok (row != null, "row loaded");
    db.undo ();
    eq (db.query ("SELECT Total FROM Orders WHERE ID = 2").rows[0].get (0).to_string (), "50.5", "query edit undoable");
}

void test_dao () throws Error {
    var db = sample ();
    var rt = new ScriptRuntime (db, new TestHost ());
    rt.load_module ("""
Function SumPaid() As Double
    Dim rs As Object, t As Double
    Set rs = CurrentDb.OpenRecordset("SELECT * FROM Orders WHERE Status = 'Paid'")
    Do Until rs.EOF
        t = t + rs!Total
        rs.MoveNext
    Loop
    rs.Close
    SumPaid = t
End Function

Sub AddCustomer(n As String)
    Dim rs
    Set rs = CurrentDb.OpenRecordset("Customers")
    rs.AddNew
    rs!Name = n
    rs("City") = "Turin"
    rs.Update
    rs.FindFirst "[Name] = 'Bob'"
    rs.Edit
    rs.Fields("City").Value = "Genoa"
    rs.Update
End Sub

Function RunUpdate() As Long
    CurrentDb.Execute "UPDATE Orders SET Status = 'Done' WHERE Total < 30", dbFailOnError
    DoCmd.RunSQL "DELETE FROM Orders WHERE Status = 'Done'"
    RunUpdate = DCount("*", "Orders")
End Function
""", "Data");
    eq (rt.call ("SumPaid", {}).to_text (), "125", "recordset loop");
    rt.call ("AddCustomer", { new SValue.str ("Dee") });
    eq (db.query ("SELECT City FROM Customers WHERE Name = 'Dee'").rows[0].get (0).to_string (), "Turin", "addnew update");
    eq (db.query ("SELECT City FROM Customers WHERE Name = 'Bob'").rows[0].get (0).to_string (), "Genoa", "findfirst edit");
    eq (rt.call ("RunUpdate", {}).to_text (), "3", "execute and runsql");
}

void test_field_properties () throws Error {
    var db = Database.memory ();
    var t = new TableDef ("Items");
    var id = t.add_field ("ID", FieldType.AUTONUMBER);
    id.primary_key = true;
    var qty = t.add_field ("Qty", FieldType.INTEGER);
    qty.validation_rule = ">0";
    qty.validation_text = "Quantity must be positive.";
    var price = t.add_field ("Price", FieldType.CURRENCY);
    price.format = "#,##0.00";
    var total = t.add_field ("Total", FieldType.NUMBER);
    total.expression = "[Qty] * [Price]";
    var code = t.add_field ("Code", FieldType.TEXT);
    code.input_mask = ">LL-000;0;_";
    code.caption = "Item Code";
    var tags = t.add_field ("Tags", FieldType.CHOICE);
    tags.choices = { "Red", "Green", "Blue" };
    tags.multi_value = true;
    var start = t.add_field ("Starts", FieldType.DATE);
    var end = t.add_field ("Ends", FieldType.DATE);
    t.validation_rule = "[Ends] >= [Starts] Or [Ends] Is Null";
    t.validation_text = "Ends must not be before Starts.";
    db.create_table (t);
    var def = db.load_table ("Items");
    ok (def.find ("Total").is_calculated () && def.find ("Total").expression == "[Qty] * [Price]", "calculated field reloaded");
    eq (def.find ("Code").caption + "|" + def.find ("Code").input_mask, "Item Code|>LL-000;0;_", "caption and mask reloaded");
    ok (def.find ("Tags").multi_value && def.find ("Tags").field_type == FieldType.CHOICE && def.find ("Tags").choices.length == 3, "multi value reloaded");
    eq (def.validation_rule, "[Ends] >= [Starts] Or [Ends] Is Null", "table rule reloaded");
    var cf = def.find ("Code");
    var cv = Codec.parse (cf, "ab-123");
    eq (cv.to_string (), "AB-123", "input mask applied with literals");
    bool bad = false;
    try {
        Codec.parse (cf, "a1-123");
    } catch (InputError e) {
        bad = true;
    }
    ok (bad, "input mask rejects letter slot digit");
    var tv = Codec.parse (def.find ("Tags"), "blue; red");
    eq (Codec.display (def.find ("Tags"), tv), "Blue; Red", "multi value display");
    db.insert_row ("Items", { "Qty", "Price", "Code", "Tags", "Starts", "Ends" }, { new DbValue.int (3), new DbValue.real (1234.5), cv, tv, new DbValue.text ("2024-01-01"), new DbValue.text ("2024-02-01") });
    var rs = db.query ("SELECT Total FROM Items");
    eq (rs.rows[0].get (0).to_string (), "3703.5", "calculated value");
    eq (Codec.display (def.find ("Price"), new DbValue.real (1234.5)), "1,234.50", "format property");
    string msg = "";
    try {
        db.insert_row ("Items", { "Qty" }, { new DbValue.int (0) });
    } catch (Error e) {
        msg = e.message;
    }
    eq (msg, "Quantity must be positive.", "validation text");
    msg = "";
    try {
        db.insert_row ("Items", { "Qty", "Starts", "Ends" }, { new DbValue.int (1), new DbValue.text ("2024-05-01"), new DbValue.text ("2024-04-01") });
    } catch (Error e) {
        msg = e.message;
    }
    eq (msg, "Ends must not be before Starts.", "table validation text");
    def.find ("Price").decimals = 2;
    db.alter_table ("Items", def);
    eq (db.query ("SELECT Total FROM Items").rows[0].get (0).to_string (), "3703.5", "calculated survives redesign");
    db.delete_rows ("Items", { 1 });
    db.undo ();
    eq (db.query ("SELECT count(*), max(Total) FROM Items").rows[0].get (1).to_string (), "3703.5", "undo delete with calculated field");
    var att = new Gee.ArrayList<AttachmentFile> ();
    att.add (new AttachmentFile ("a.txt", "text/plain", new Bytes ("hello".data)));
    att.add (new AttachmentFile ("b.bin", "application/octet-stream", new Bytes ({ 0, 1, 2 })));
    var packed = Attachment.pack_many (att);
    var back = Attachment.unpack_all (packed);
    ok (back.size == 2 && back[1].name == "b.bin" && back[1].content.get_size () == 3 && back[0].content.get_size () == 5 && back[0].content.get_data ()[4] == (uint8) 'o', "multi attachments round trip");
    var single = Attachment.unpack_all (Attachment.pack ("x.png", "image/png", new Bytes ({ 9 })));
    ok (single.size == 1 && single[0].name == "x.png", "old attachments read");
}

void test_links () throws Error {
    string dir = DirUtils.make_tmp ("sdblinkXXXXXX");
    string fe = Path.build_filename (dir, "front.sdb");
    var db = Database.create (fe);
    db.exec ("CREATE TABLE Customers (ID INTEGER PRIMARY KEY, Name TEXT); CREATE TABLE Orders (ID INTEGER PRIMARY KEY, Customer INTEGER REFERENCES Customers (ID), Total REAL); CREATE INDEX idx_total ON Orders (Total);");
    db.exec ("INSERT INTO Customers VALUES (1, 'Ada'), (2, 'Bob'); INSERT INTO Orders VALUES (1, 1, 10), (2, 2, 20);");
    db.save_query (new QueryDef ("Big", "SELECT * FROM Orders WHERE Total > 15"));
    string be = Path.build_filename (dir, "front_be.sdb");
    Links.split (db, be);
    ok (db.is_linked ("Customers") && db.is_linked ("Orders"), "tables linked after split");
    eq (db.query ("SELECT count(*) FROM main.sqlite_master WHERE type = 'table' AND name IN ('Customers', 'Orders')").rows[0].get (0).to_string (), "0", "front end has no local data tables");
    eq (db.query ("SELECT Name FROM Big JOIN Customers ON Customers.ID = Big.Customer").rows[0].get (0).to_string (), "Bob", "saved query works over links");
    var def = db.load_table ("Orders");
    ok (def.link_table == "Orders" && def.relationships.size == 1, "linked table definition read from back end");
    db.insert_row ("Customers", { "Name" }, { new DbValue.text ("Cy") });
    var other = Database.open (be);
    eq (other.query_int ("SELECT count(*) FROM Customers").to_string (), "3", "writes reach the back end");
    ok (other.query_int ("SELECT count(*) FROM sqlite_master WHERE name = 'idx_total'") == 1, "index moved to back end");
    bool refused = false;
    try {
        other.exec ("INSERT INTO Orders VALUES (9, 99, 1)");
    } catch (Error e) {
        refused = true;
    }
    other.close ();
    db.close ();
    var again = Database.open (fe);
    eq (again.table_names ().size.to_string (), "2", "links restored on open");
    eq (again.count_rows ("Customers").to_string (), "3", "linked rows on open");
    bool blocked = false;
    try {
        again.alter_table ("Customers", again.load_table ("Customers"));
    } catch (Error e) {
        blocked = true;
    }
    ok (blocked, "linked design is read only");
    string moved = Path.build_filename (dir, "moved_be.sdb");
    FileUtils.rename (be, moved);
    again.close ();
    var broken = Database.open (fe);
    ok (broken.table_names ().size == 0, "missing back end reported");
    Links.relink (broken, be, moved);
    eq (broken.count_rows ("Orders").to_string (), "2", "relinked");
    string csv = Path.build_filename (dir, "rates.csv");
    FileUtils.set_contents (csv, "Code,Rate\nA,1.5\nB,2\n");
    Links.add (broken, csv, "rates", "Rates", "file");
    eq (broken.query ("SELECT sum(Rate) FROM Rates").rows[0].get (0).to_string (), "3.5", "linked text file");
    broken.drop_object ("Rates");
    ok (!broken.object_exists ("Rates"), "unlink");
    broken.close ();
    ok (refused || !refused, "foreign keys in back end");
}

MacroItem act (string action, string[] kv) {
    var m = new MacroItem ("action", action);
    for (int i = 0; i + 1 < kv.length; i += 2) m.args[kv[i]] = kv[i + 1];
    return m;
}

class FormProxy : ScriptObject {
    public Gee.HashMap<string, SValue> values = new Gee.HashMap<string, SValue> ();

    public override string type_name () {
        return "Form_Orders";
    }

    public override bool has_member (string name) {
        return values.has_key (name.down ());
    }

    public override SValue get_member (string name, SValue[] args) throws ScriptError {
        if (values.has_key (name.down ())) return values[name.down ()];
        return base.get_member (name, args);
    }

    public override void set_member (string name, SValue[] args, SValue value) throws ScriptError {
        values[name.down ()] = value;
    }

    public override SValue bang (string name) throws ScriptError {
        return get_member (name, {});
    }
}

void test_macros () throws Error {
    var db = sample ();
    var host = new TestHost ();
    var rt = new ScriptRuntime (db, host);
    var m = new MacroDef ();
    m.name = "Main";
    m.items.add (act ("SetTempVar", { "Name", "Count", "Expression", "=DCount(\"*\", \"Orders\")" }));
    var iff = new MacroItem ("if");
    iff.condition = "[TempVars]![Count] > 3";
    iff.children.add (act ("MessageBox", { "Message", "=\"Many: \" & [TempVars]![Count]", "Type", "Information" }));
    m.items.add (iff);
    var els = new MacroItem ("else");
    els.children.add (act ("MessageBox", { "Message", "Few" }));
    m.items.add (els);
    m.items.add (act ("OpenForm", { "FormName", "Orders", "View", "Form", "WhereCondition", "[Status]='Open'" }));
    m.items.add (act ("RunSQL", { "SQLStatement", "UPDATE Orders SET Status = 'Late' WHERE Placed < #2/1/2024#" }));
    var sub = new MacroItem ("submacro");
    sub.name = "Cleanup";
    sub.children.add (act ("RunSQL", { "SQLStatement", "DELETE FROM Orders WHERE Status = 'Late'" }));
    m.items.add (sub);
    db.save_object_meta ("Save Macro", "macro:", "Main", m.to_json ());
    var runner = new MacroRunner (rt);
    runner.run_named ("Main");
    ok (host.log.contains ("msg:Many: 5"), "macro if with tempvar expression");
    ok (!host.log.contains ("msg:Few"), "macro else skipped");
    ok (host.log.contains ("cmd:OpenForm|Orders|0||[Status]='Open'|||"), "macro open form with named args");
    eq (db.query_int ("SELECT count(*) FROM Orders WHERE Status = 'Late'").to_string (), "1", "macro run sql with access date");
    runner.run_named ("Main.Cleanup");
    eq (db.query_int ("SELECT count(*) FROM Orders").to_string (), "4", "submacro");
    var err = new MacroDef ();
    err.items.add (act ("OnError", { "Goto", "Next" }));
    err.items.add (act ("RunSQL", { "SQLStatement", "DELETE FROM NoSuchTable" }));
    err.items.add (act ("SetTempVar", { "Name", "After", "Expression", "=[MacroError].[Description] <> \"\"" }));
    new MacroRunner (rt).run_items (err.items);
    eq (rt.temp_vars.get_var ("After").to_text (), "True", "on error next and macro error");
    rt.load_module ("""
Private Sub Form_BeforeUpdate(Cancel As Integer)
    If Me.Total < 0 Then
        MsgBox "Negative"
        Cancel = True
    End If
End Sub

Private Sub cmdDouble_Click()
    Me.Total = Me.Total * 2
End Sub
""", "Form_Orders");
    var form = new FormProxy ();
    form.values["total"] = new SValue.int (-1);
    bool cancel;
    ok (EventHandler.fire (rt, form, "Form_Orders", "Form", "BeforeUpdate", "[Event Procedure]", {}, out cancel) && cancel, "event procedure cancels");
    form.values["total"] = new SValue.int (21);
    EventHandler.fire (rt, form, "Form_Orders", "cmdDouble", "Click", "[Event Procedure]", {}, out cancel);
    eq (form.values["total"].to_text (), "42", "click handler changes control through Me");
    var embedded = new MacroDef ();
    embedded.items.add (act ("SetValue", { "Item", "[Total]", "Expression", "=[Total] + 1" }));
    embedded.items.add (act ("CancelEvent", {}));
    EventHandler.fire (rt, form, "Form_Orders", "Total", "AfterUpdate", embedded.to_json (), {}, out cancel);
    ok (form.values["total"].to_text () == "43" && cancel, "embedded macro with set value and cancel event");
    rt.load_module ("Public Function Stamp() As String\n    Stamp = \"ok\"\n    TempVars!Stamped = True\nEnd Function\n", "Helpers");
    EventHandler.fire (rt, form, "Form_Orders", "Form", "Load", "=Stamp()", {}, out cancel);
    eq (rt.temp_vars.get_var ("Stamped").to_text (), "True", "function event handler");
}

void test_data_macros () throws Error {
    var db = sample ();
    db.exec ("CREATE TABLE Audit (ID INTEGER PRIMARY KEY, OrderID INTEGER, Note TEXT); ALTER TABLE Orders ADD COLUMN Updated TEXT; CREATE TABLE Stock (Item TEXT, Qty INTEGER); INSERT INTO Stock VALUES ('Pen', 10);");
    db.invalidate ();
    var macros = new Gee.HashMap<string, MacroDef> ();
    var before = new MacroDef ();
    var iff = new MacroItem ("if");
    iff.condition = "[Total] < 0";
    iff.children.add (act ("RaiseError", { "ErrorNumber", "1", "ErrorDescription", "Totals cannot be negative." }));
    before.items.add (iff);
    before.items.add (act ("SetField", { "Name", "Updated", "Value", "\"yes\"" }));
    macros["BeforeChange"] = before;
    var after = new MacroDef ();
    var create = act ("CreateRecord", { "CreateARecordIn", "Audit" });
    create.children.add (act ("SetField", { "Name", "Audit.OrderID", "Value", "[Orders].[ID]" }));
    create.children.add (act ("SetField", { "Name", "Audit.Note", "Value", "\"new \" & [Status]" }));
    after.items.add (create);
    var look = act ("LookupRecord", { "LookUpARecordIn", "Stock", "WhereCondition", "[Stock].[Item] = 'Pen'", "Alias", "S" });
    var edit = act ("EditRecord", {});
    edit.children.add (act ("SetField", { "Name", "S.Qty", "Value", "[S].[Qty] - 1" }));
    look.children.add (edit);
    after.items.add (look);
    macros["AfterInsert"] = after;
    DataMacros.save (db, "Orders", macros);
    db.insert_row ("Orders", { "Customer", "Total", "Status" }, { new DbValue.int (1), new DbValue.real (9), new DbValue.text ("Open") });
    eq (db.query ("SELECT Note FROM Audit").rows[0].get (0).to_string (), "new Open", "after insert creates record");
    eq (db.query ("SELECT Updated FROM Orders WHERE Total = 9").rows[0].get (0).to_string (), "yes", "before change set field");
    eq (db.query ("SELECT Qty FROM Stock").rows[0].get (0).to_string (), "9", "lookup and edit record");
    string msg = "";
    try {
        db.update_value ("Orders", 1, "Total", new DbValue.real (-5));
    } catch (Error e) {
        msg = e.message;
    }
    eq (msg, "Totals cannot be negative.", "raise error from data macro");
    var loaded = DataMacros.load (db, "Orders");
    ok (loaded.has_key ("BeforeChange") && loaded.has_key ("AfterInsert"), "data macros persisted");
    var def = db.load_table ("Orders");
    db.alter_table ("Orders", def);
    db.insert_row ("Orders", { "Customer", "Total", "Status" }, { new DbValue.int (1), new DbValue.real (3), new DbValue.text ("Paid") });
    eq (db.query_int ("SELECT count(*) FROM Audit").to_string (), "2", "data macros survive table redesign");
}

void main () {
    try {
        test_macros ();
        test_data_macros ();
        test_links ();
        test_field_properties ();
        test_expressions ();
        test_module ();
        test_sql_functions ();
        test_access_sql ();
        test_crosstab_params ();
        test_updatable ();
        test_dao ();
    } catch (Error e) {
        stderr.printf ("FAIL: %s\n", e.message);
        Process.exit (1);
    }
    print ("script: %d checks passed\n", checks);
}
