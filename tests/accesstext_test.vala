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

const string FORM = """Version =20
VersionRequired =20
Begin Form
    RecordSelectors = NotDefault
    DefaultView =0
    Width =7200
    Caption ="Customer Orders"
    RecordSource ="SELECT Customers.* FROM Customers "
        "WHERE Customers.Active = True;"
    OnLoad ="[Event Procedure]"
    BeforeUpdate ="=CheckRecord()"
    RecSrcDt = Begin
        0xef22ea99ebc8e540
    End
    Begin
        Begin Label
            FontSize =11
        End
        Begin TextBox
            SpecialEffect =2
        End
        Begin FormHeader
            Height =720
            Name ="FormHeader"
            Begin
                Begin Label
                    Left =360
                    Top =120
                    Width =3000
                    Height =420
                    Name ="lblTitle"
                    Caption ="Orders for \"VIP\" clients\015\012and partners"
                End
            End
        End
        Begin Section
            Height =4320
            Name ="Detail"
            Begin
                Begin TextBox
                    Left =1800
                    Top =240
                    Width =2880
                    Height =315
                    Name ="CompanyName"
                    ControlSource ="CompanyName"
                    AfterUpdate ="[Event Procedure]"
                    Begin
                        Begin Label
                            Left =240
                            Top =240
                            Width =1440
                            Height =315
                            Name ="CompanyName_Label"
                            Caption ="Company"
                        End
                    End
                End
                Begin TextBox
                    Left =1800
                    Top =720
                    Width =1440
                    Height =315
                    Name ="txtTotal"
                    ControlSource ="=[Quantity]*[UnitPrice]"
                    Format ="Currency"
                End
                Begin CommandButton
                    Left =5040
                    Top =240
                    Width =1440
                    Height =420
                    Name ="cmdSave"
                    Caption ="Save"
                    OnClick ="[Event Procedure]"
                End
                Begin Tab
                    Left =240
                    Top =1440
                    Width =6480
                    Height =2520
                    Name ="tabMain"
                    Begin
                        Begin Page
                            Name ="pgNotes"
                            Caption ="Notes"
                            Begin
                                Begin TextBox
                                    Left =480
                                    Top =1920
                                    Width =5760
                                    Height =1440
                                    Name ="Notes"
                                    ControlSource ="Notes"
                                End
                            End
                        End
                        Begin Page
                            Name ="pgOrders"
                            Caption ="Orders"
                            Begin
                                Begin Subform
                                    Left =480
                                    Top =1920
                                    Width =5760
                                    Height =1440
                                    Name ="subOrders"
                                    SourceObject ="Form.Order Lines"
                                    LinkChildFields ="CustomerID"
                                    LinkMasterFields ="CustomerID"
                                End
                            End
                        End
                    End
                End
            End
        End
        Begin FormFooter
            Height =360
            Name ="FormFooter"
        End
    End
End
CodeBehindForm
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = True
Option Compare Database
Option Explicit

Private Sub cmdSave_Click()
    If Me.Dirty Then Me.Dirty = False
End Sub
""";

const string REPORT = """Version =20
VersionRequired =20
Begin Report
    Width =9360
    RecordSource ="Orders"
    Caption ="Sales"
    Begin
        Begin BreakLevel
            ControlSource ="OrderDate"
            GroupOn =3
        End
        Begin PageHeader
            Height =480
            Name ="PageHeaderSection"
        End
        Begin BreakHeader
            KeepTogether =1
            Height =480
            Name ="GroupHeader0"
            Begin
                Begin TextBox
                    Left =120
                    Top =60
                    Width =2400
                    Height =300
                    Name ="txtMonth"
                    ControlSource ="=Format([OrderDate],\"mmmm yyyy\")"
                End
            End
        End
        Begin Section
            Height =360
            Name ="Detail"
            Begin
                Begin TextBox
                    RunningSum =2
                    Left =120
                    Top =30
                    Width =1440
                    Height =300
                    Name ="txtRunning"
                    ControlSource ="Freight"
                End
            End
        End
        Begin BreakFooter
            Height =360
            Name ="GroupFooter1"
        End
        Begin PageFooter
            Height =360
            Name ="PageFooterSection"
            Begin
                Begin TextBox
                    Left =6000
                    Top =30
                    Width =3000
                    Height =300
                    Name ="txtPage"
                    ControlSource ="=\"Page \" & [Page] & \" of \" & [Pages]"
                End
            End
        End
    End
End
""";

const string LEGACY_MACRO = """Version =196611
ColumnsShown =10
Begin
    MacroName ="OpenCustomers"
End
Begin
    Condition ="[Forms]![Main]![chkAll]=True"
    Action ="OpenForm"
    Argument ="Customers"
    Argument ="0"
    Argument =""
    Argument ="[Active]=True"
    Argument ="-1"
    Argument ="0"
End
Begin
    Condition ="..."
    Action ="MsgBox"
    Argument ="All customers shown"
    Argument ="-1"
    Argument ="0"
    Argument ="Info"
End
Begin
    Action ="RunSQL"
    Argument ="UPDATE Customers SET Seen = True;"
    Argument ="-1"
End
Begin
    Comment ="Refresh the list"
End
""";

const string XML_MACRO = """<?xml version="1.0" encoding="UTF-16" standalone="no"?>
<UserInterfaceMacro For="cmdGo" Event="OnClick" xmlns="http://schemas.microsoft.com/office/accessservices/2009/11/application">
<Statements>
<Comment>Validate before opening</Comment>
<ConditionalBlock>
<If><Condition>IsNull([Forms]![Main]![txtCity])</Condition><Statements>
<Action Name="MessageBox"><Argument Name="Message">Enter a city first</Argument><Argument Name="Type">Warning?</Argument></Action>
<Action Name="StopMacro"/>
</Statements></If>
<Else><Statements>
<Action Name="OpenReport"><Argument Name="ReportName">Customers by City</Argument><Argument Name="View">Print Preview</Argument><Argument Name="WhereCondition">[City]=[Forms]![Main]![txtCity]</Argument></Action>
</Statements></Else>
</ConditionalBlock>
<Action Name="SetTempVar"><Argument Name="Name">LastCity</Argument><Argument Name="Expression">[Forms]![Main]![txtCity]</Argument></Action>
</Statements>
<Sub Name="Cleanup"><Statements><Action Name="CloseWindow"/></Statements></Sub>
</UserInterfaceMacro>
""";

const string MODULE = """Attribute VB_Name = "basOrders"
Option Compare Database
Option Explicit

Public Function OrderTotal(ByVal id As Long) As Currency
    OrderTotal = Nz(DSum("[Quantity]*[UnitPrice]", "Order Details", "OrderID=" & id), 0)
End Function
""";

const string CLASS_MODULE = "VERSION 1.0 CLASS\r\nBEGIN\r\n  MultiUse = -1  'True\r\nEND\r\nAttribute VB_Name = \"clsPerson\"\r\nAttribute VB_GlobalNameSpace = False\r\nAttribute VB_Exposed = False\r\nOption Explicit\r\n\r\nPublic FirstName As String\r\n";

const string QUERY = """Operation =1
Option =0
Where ="(((Customers.City)=\"Rome\"))"
Begin InputTables
    Name ="Customers"
End
Begin OutputColumns
    Expression ="Customers.CompanyName"
End
dbMemo "SQL" ="SELECT Customers.CompanyName\015\012FROM Customers\015\012WHERE (((Customers.City)=\"Rome\"));\015\012"
""";

void test_form () throws Error {
    var obj = AccessText.parse_object (FORM);
    eq (obj.kind, "form", "form kind");
    ok (obj.version == 20, "form version");
    eq (obj.root.text ("Caption"), "Customer Orders", "form caption");
    eq (obj.root.text ("RecordSource"), "SELECT Customers.* FROM Customers WHERE Customers.Active = True;", "continued record source");
    eq (obj.root.text ("RecSrcDt"), "ef22ea99ebc8e540", "hex blob property");
    ok (obj.root.get_bool ("RecordSelectors"), "NotDefault is true");
    eq (obj.root.text ("OnLoad"), "[Event Procedure]", "form event");
    ok (obj.root.events ().contains ("BeforeUpdate") && obj.root.events ().contains ("OnLoad"), "form events listed");
    var sections = obj.root.sections ();
    ok (sections.size == 3, "three sections");
    eq (sections[0].section_kind (), "FormHeader", "header section");
    eq (sections[1].section_kind (), "Detail", "detail section");
    ok (sections[1].get_int ("Height") == 4320, "detail height");
    ok (obj.root.defaults ().size == 2, "default control styles");
    var title = obj.root.find ("lblTitle");
    ok (title != null && title.kind == "Label", "title label");
    eq (title.text ("Caption"), "Orders for \"VIP\" clients\r\nand partners", "escaped caption");
    var company = obj.root.find ("CompanyName");
    ok (company.kind == "TextBox" && company.text ("ControlSource") == "CompanyName", "bound text box");
    ok (company.get_int ("Left") == 1800 && company.get_int ("Top") == 240 && company.get_int ("Width") == 2880, "twips geometry");
    ok (AccessText.twips_to_pixels (company.get_int ("Width")) == 192, "twips to pixels");
    ok (AccessText.twips_to_points (1440) == 72, "twips to points");
    var attached = obj.root.find ("CompanyName_Label");
    ok (attached != null && attached.container () == company, "attached label belongs to its text box");
    eq (obj.root.find ("txtTotal").text ("ControlSource"), "=[Quantity]*[UnitPrice]", "calculated control");
    eq (obj.root.find ("cmdSave").text ("OnClick"), "[Event Procedure]", "button event");
    var notes = obj.root.find ("Notes");
    ok (notes.container ().kind == "Page" && notes.container ().name == "pgNotes", "control on tab page");
    ok (notes.container ().container ().name == "tabMain", "page inside tab control");
    var sub = obj.root.find ("subOrders");
    ok (sub.kind == "Subform" && sub.text ("SourceObject") == "Form.Order Lines" && sub.text ("LinkMasterFields") == "CustomerID", "subform control");
    int names = 0;
    foreach (var c in sections[1].controls ()) names++;
    ok (names == 9, "detail control count %d".printf (names));
    ok (obj.code.has_prefix ("Option Compare Database"), "code behind form");
    ok (obj.code.contains ("Private Sub cmdSave_Click()") && !obj.code.contains ("Attribute VB_"), "code without attributes");
    print ("form: ok\n");
}

void test_report () throws Error {
    var obj = AccessText.parse_object (REPORT);
    eq (obj.kind, "report", "report kind");
    eq (obj.root.text ("RecordSource"), "Orders", "report source");
    var sections = obj.root.sections ();
    ok (sections.size == 5, "report sections");
    eq (sections[1].section_kind (), "GroupHeader", "group header");
    eq (sections[3].section_kind (), "GroupFooter", "group footer");
    AccessTextNode? level = null;
    foreach (var c in obj.root.children[0].children) {
        if (c.kind == "BreakLevel") level = c;
    }
    ok (level != null && level.text ("ControlSource") == "OrderDate" && level.get_int ("GroupOn") == 3, "grouping level");
    eq (obj.root.find ("txtMonth").text ("ControlSource"), "=Format([OrderDate],\"mmmm yyyy\")", "quoted escapes in expression");
    ok (obj.root.find ("txtRunning").get_int ("RunningSum") == 2, "running sum");
    eq (obj.root.find ("txtPage").text ("ControlSource"), "=\"Page \" & [Page] & \" of \" & [Pages]", "page expression");
    print ("report: ok\n");
}

void test_macros () throws Error {
    var steps = AccessText.parse_macro (LEGACY_MACRO);
    ok (steps.size == 1 && steps[0].kind == "submacro" && steps[0].name == "OpenCustomers", "legacy submacro");
    var body = steps[0].children;
    ok (body.size == 3, "legacy body size %d".printf (body.size));
    eq (body[0].kind, "if", "legacy condition");
    eq (body[0].condition, "[Forms]![Main]![chkAll]=True", "legacy condition text");
    ok (body[0].children.size == 2, "continuation joins the condition");
    eq (body[0].children[0].name, "OpenForm", "legacy action");
    eq (body[0].children[0].argument ("FormName"), "Customers", "named legacy argument");
    eq (body[0].children[0].argument ("WhereCondition"), "[Active]=True", "legacy where");
    eq (body[0].children[1].argument ("Title"), "Info", "msgbox title");
    eq (body[1].argument ("SQLStatement"), "UPDATE Customers SET Seen = True;", "runsql");
    ok (body[2].kind == "comment" && body[2].comment == "Refresh the list", "legacy comment");

    var xs = AccessText.parse_macro (XML_MACRO);
    ok (xs.size == 5, "xml steps %d".printf (xs.size));
    ok (xs[0].kind == "comment" && xs[0].comment == "Validate before opening", "xml comment");
    eq (xs[1].kind, "if", "xml if");
    eq (xs[1].condition, "IsNull([Forms]![Main]![txtCity])", "xml condition");
    ok (xs[1].children.size == 2 && xs[1].children[0].argument ("Message") == "Enter a city first", "xml if body");
    eq (xs[1].children[1].name, "StopMacro", "empty action");
    ok (xs[2].kind == "else" && xs[2].children[0].argument ("ReportName") == "Customers by City", "xml else");
    eq (xs[3].argument ("Name"), "LastCity", "settempvar");
    ok (xs[4].kind == "submacro" && xs[4].name == "Cleanup" && xs[4].children[0].name == "CloseWindow", "xml submacro");
    print ("macros: ok\n");
}

void test_modules () throws Error {
    var m = AccessText.parse_object (MODULE);
    eq (m.kind, "module", "module kind");
    eq (m.name, "basOrders", "module name");
    ok (m.code.has_prefix ("Option Compare Database") && m.code.contains ("Public Function OrderTotal"), "module code");
    var c = AccessText.parse_object (CLASS_MODULE);
    eq (c.kind, "class", "class kind");
    eq (c.name, "clsPerson", "class name");
    eq (c.code, "Option Explicit\n\nPublic FirstName As String", "class code");
    var q = AccessText.parse_object (QUERY);
    eq (q.kind, "query", "query kind");
    eq (q.root.text ("SQL"), "SELECT Customers.CompanyName\r\nFROM Customers\r\nWHERE (((Customers.City)=\"Rome\"));\r\n", "query sql");
    eq (q.root.children[0].text ("Name"), "Customers", "query input table");
    print ("modules: ok\n");
}

void test_decode () {
    uint8[] utf16 = { 0xFF, 0xFE, 'V', 0, 'e', 0, 0xE8, 0, 0x3D, 0xD8, 0x00, 0xDE };
    eq (AccessText.decode (utf16), "Veè😀", "utf-16 decode");
    uint8[] utf8 = { 0xEF, 0xBB, 0xBF, 'O', 'k', 0xC3, 0xA0 };
    eq (AccessText.decode (utf8), "Okà", "utf-8 bom");
    uint8[] cp = { 'C', 'a', 'f', 0xE9 };
    eq (AccessText.decode (cp), "Café", "windows-1252 fallback");
    var sb = new StringBuilder ();
    sb.append_c ((char) 0xFF);
    sb.append_c ((char) 0xFE);
    foreach (char ch in "Attribute VB_Name = \"M\"\r\nSub X()\r\nEnd Sub\r\n".to_utf8 ()) {
        sb.append_c (ch);
        sb.append_c (0);
    }
    uint8[] mod = sb.data;
    try {
        var obj = AccessText.parse_object (AccessText.decode (mod));
        ok (obj.kind == "module" && obj.name == "M" && obj.code == "Sub X()\nEnd Sub", "utf-16 module");
    } catch (Error e) {
        ok (false, e.message);
    }
    print ("decode: ok\n");
}

string? fixture_dir () {
    foreach (string env in new string[] { "ACCESS_TEXT_FIXTURES", "MDB_FIXTURES" }) {
        string? dir = Environment.get_variable (env);
        if (dir == null) continue;
        foreach (string p in new string[] { dir, Path.build_filename (dir, "savetext") }) {
            if (FileUtils.test (Path.build_filename (p, "frmTestMenu.form"), FileTest.EXISTS)) return p;
        }
    }
    return null;
}

string load (string dir, string name) throws Error {
    uint8[] data;
    FileUtils.get_data (Path.build_filename (dir, name), out data);
    return AccessText.decode (data);
}

void test_fixtures (string dir) throws Error {
    var menu = AccessText.parse_object (load (dir, "frmTestMenu.form"));
    eq (menu.kind, "form", "fixture form kind");
    var btn = menu.root.find ("cmdShowMenu");
    ok (btn != null && btn.kind == "CommandButton", "fixture button");
    eq (btn.text ("Caption"), " Show Menu...", "fixture caption");
    eq (btn.text ("OnClick"), "[Event Procedure]", "fixture event");
    ok (btn.get_int ("Left") == 720 && btn.get_int ("Top") == 1620, "fixture geometry");
    ok (btn.text ("ImageData").length > 100, "fixture image blob");
    eq (menu.root.find ("Label1").text ("Caption"), "Click this button to show \r\nthe custom Popup Menu.", "fixture escaped newline");
    int sections = menu.root.sections ().size;
    var form1 = AccessText.parse_object (load (dir, "Form1.form"));
    eq (form1.root.text ("RecordSource"), "SELECT tblAttachment.ImageObject FROM tblAttachment; ", "fixture record source");
    var report = AccessText.parse_object (load (dir, "rptDefaultPrinter.report"));
    eq (report.kind, "report", "fixture report");
    eq (report.root.find ("Label0").text ("Caption"), "This report does not have any saved print settings.", "fixture report label");
    var macro = AccessText.parse_macro (load (dir, "AutoExec.macro"));
    ok (macro.size == 2, "fixture macro steps");
    eq (macro[0].name, "OpenForm", "fixture macro action");
    eq (macro[0].argument ("FormName"), "frmMain", "fixture macro argument from xml");
    eq (macro[1].argument ("FunctionName"), "RunTests()", "fixture runcode");
    var module = AccessText.parse_object (load (dir, "Module1.bas"));
    eq (module.name, "Module1", "fixture module name");
    ok (module.code.contains ("Option Explicit"), "fixture module code");
    var cls = AccessText.parse_object (load (dir, "frmTestMenu.cls"));
    ok (cls.kind == "class" || cls.kind == "module", "fixture code behind file");
    print ("savetext fixtures: ok (%d sections in frmTestMenu)\n", sections);
}

void test_import_objects () throws Error {
    string? dir = Environment.get_variable ("ACCESS_TEXT_FIXTURES");
    var db = Database.memory ();
    db.exec ("CREATE TABLE Orders (ID INTEGER PRIMARY KEY, OrderDate DATE, Total REAL)");
    string tmp = DirUtils.make_tmp ("sdbatxXXXXXX");
    string rp = Path.build_filename (tmp, "rptSales.report");
    FileUtils.set_contents (rp, REPORT);
    var rr = AccessObjectImport.import_file (db, rp);
    var rd = ReportDef.from_json (rr.table, db.get_meta ("report:" + rr.table));
    ok (rd != null && rd.designed && rd.groups.size == 1 && rd.groups[0].interval == "quarter", "report imported with grouping");
    ok (rd.find_control ("txtPage") != null && rd.find_control ("txtRunning").running_sum == "all", "report controls imported");
    db.exec ("INSERT INTO Orders VALUES (1, '2024-01-10', 10), (2, '2024-05-02', 20)");
    var pages = new ReportRenderer ().layout (rd, ReportEngine.open_source (db, rd));
    ok (pages.size >= 1, "imported report renders");
    if (dir != null && FileUtils.test (Path.build_filename (dir, "Form1.form"), FileTest.EXISTS)) {
        foreach (string f in new string[] { "Form1.form", "frmTestMenu.form", "frmTestMenu.cls", "rptDefaultPrinter.report", "AutoExec.macro", "Module1.bas" }) {
            var r = AccessObjectImport.import_file (db, Path.build_filename (dir, f));
            ok (r.table != "", "imported " + f);
        }
        var menu = FormDef.from_json ("frmTestMenu", db.get_meta ("form:frmTestMenu"));
        ok (menu != null && menu.controls.size > 0 && menu.code.strip () != "", "form with controls and code behind");
        var auto = MacroDef.from_json ("AutoExec", db.get_meta ("macro:AutoExec"));
        ok (auto != null && auto.items.size > 0, "macro imported");
        ok (db.get_meta ("module:Module1") != null, "module imported");
        print ("savetext import: ok\n");
    } else {
        print ("savetext import: fixtures skipped\n");
    }
}

void main () {
    try {
        test_import_objects ();
    } catch (Error e) {
        stderr.printf ("FAIL: %s\n", e.message);
        Process.exit (1);
    }
    try {
        test_decode ();
        test_form ();
        test_report ();
        test_macros ();
        test_modules ();
        string? dir = fixture_dir ();
        if (dir != null) test_fixtures (dir);
        else print ("savetext fixtures: skipped, set ACCESS_TEXT_FIXTURES\n");
    } catch (Error e) {
        stderr.printf ("FAIL: %s\n", e.message);
        Process.exit (1);
    }
    print ("accesstext: %d checks passed\n", checks);
}
