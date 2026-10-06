namespace Singularity.Apps.Database {

    public class MacroItem {
        public string kind = "action";
        public string action = "";
        public string condition = "";
        public string comment = "";
        public string name = "";
        public OrderedMap<string> args = new OrderedMap<string> ();
        public Gee.ArrayList<MacroItem> children = new Gee.ArrayList<MacroItem> ();

        public MacroItem (string kind, string action = "") {
            this.kind = kind;
            this.action = action;
        }

        public string arg (string name) {
            foreach (var e in args.entries) {
                if (e.key.casefold () == name.casefold ()) return e.value;
            }
            return "";
        }

        public void list (StringBuilder sb, int depth) {
            string pad = string.nfill (depth * 4, ' ');
            string line;
            switch (kind) {
                case "comment":
                    line = "' " + comment;
                    break;
                case "submacro":
                    line = _("Submacro: %s").printf (name);
                    break;
                case "group":
                    line = _("Group: %s").printf (name);
                    break;
                case "if":
                    line = _("If %s Then").printf (condition);
                    break;
                case "elseif":
                    line = _("Else If %s Then").printf (condition);
                    break;
                case "else":
                    line = _("Else");
                    break;
                default:
                    string[] parts = {};
                    foreach (var e in args.entries) {
                        if (e.value != null && e.value != "") parts += "%s: %s".printf (e.key, e.value);
                    }
                    line = parts.length > 0 ? "%s  (%s)".printf (action, string.joinv (", ", parts)) : action;
                    if (condition != "") line = _("If %s Then").printf (condition) + " " + line;
                    break;
            }
            sb.append (pad).append (line).append_c ('\n');
            if (kind != "comment" && comment != "") sb.append (pad).append ("    ' ").append (comment).append_c ('\n');
            foreach (var c in children) c.list (sb, depth + 1);
            if (kind == "submacro") sb.append (pad).append (_("End Submacro")).append_c ('\n');
            if (kind == "group") sb.append (pad).append (_("End Group")).append_c ('\n');
        }

        public MacroItem copy () {
            var m = new MacroItem (kind, action);
            m.condition = condition;
            m.comment = comment;
            m.name = name;
            foreach (var e in args.entries) m.args[e.key] = e.value;
            foreach (var c in children) m.children.add (c.copy ());
            return m;
        }

        public void build (Json.Builder b) {
            b.begin_object ();
            b.set_member_name ("kind").add_string_value (kind);
            if (action != "") b.set_member_name ("action").add_string_value (action);
            if (condition != "") b.set_member_name ("condition").add_string_value (condition);
            if (comment != "") b.set_member_name ("comment").add_string_value (comment);
            if (name != "") b.set_member_name ("name").add_string_value (name);
            if (args.size > 0) {
                b.set_member_name ("args").begin_array ();
                foreach (var e in args.entries) {
                    b.begin_array ();
                    b.add_string_value (e.key);
                    b.add_string_value (e.value);
                    b.end_array ();
                }
                b.end_array ();
            }
            if (children.size > 0) {
                b.set_member_name ("children").begin_array ();
                foreach (var c in children) c.build (b);
                b.end_array ();
            }
            b.end_object ();
        }

        public static MacroItem read (Json.Object o) {
            var m = new MacroItem (o.get_string_member_with_default ("kind", "action"), o.get_string_member_with_default ("action", ""));
            m.condition = o.get_string_member_with_default ("condition", "");
            m.comment = o.get_string_member_with_default ("comment", "");
            m.name = o.get_string_member_with_default ("name", "");
            if (o.has_member ("args")) {
                o.get_array_member ("args").foreach_element ((a, i, n) => {
                    var pair = n.get_array ();
                    if (pair.get_length () >= 2) m.args[pair.get_string_element (0)] = pair.get_string_element (1);
                });
            }
            if (o.has_member ("children")) {
                o.get_array_member ("children").foreach_element ((a, i, n) => m.children.add (MacroItem.read (n.get_object ())));
            }
            return m;
        }
    }

    public class MacroDef {
        public string name = "";
        public string description = "";
        public Gee.ArrayList<MacroItem> items = new Gee.ArrayList<MacroItem> ();

        public string listing () {
            var sb = new StringBuilder ();
            if (description != "") sb.append (description).append ("\n\n");
            foreach (var it in items) it.list (sb, 0);
            return sb.str;
        }

        public string to_json () {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("description").add_string_value (description);
            b.set_member_name ("items").begin_array ();
            foreach (var i in items) i.build (b);
            b.end_array ();
            b.end_object ();
            return Json.to_string (b.get_root (), false);
        }

        public static MacroDef? from_json (string name, string? json) {
            var o = Meta.parse_object (json);
            if (o == null) return null;
            var m = new MacroDef ();
            m.name = name;
            m.description = o.get_string_member_with_default ("description", "");
            if (o.has_member ("items")) {
                o.get_array_member ("items").foreach_element ((a, i, n) => m.items.add (MacroItem.read (n.get_object ())));
            }
            return m;
        }

        public MacroItem? submacro (string sub) {
            foreach (var i in items) {
                if (i.kind == "submacro" && i.name.casefold () == sub.casefold ()) return i;
            }
            return null;
        }
    }

    public class MacroAction {
        public string name;
        public string label;
        public string[] args;
        public string category;
        public bool data;

        public MacroAction (string name, string label, string category, string[] args, bool data = false) {
            this.name = name;
            this.label = label;
            this.category = category;
            this.args = args;
            this.data = data;
        }
    }

    public class MacroCatalog {
        private static Gee.ArrayList<MacroAction>? actions;

        public static Gee.ArrayList<MacroAction> all () {
            if (actions != null) return actions;
            actions = new Gee.ArrayList<MacroAction> ();
            string win = _("Windows and Objects");
            string data = _("Records and Data");
            string flow = _("Macro Commands");
            string ui = _("User Interface");
            string io = _("Data Import and Export");
            actions.add (new MacroAction ("OpenForm", _("Open Form"), win, { "FormName", "View", "FilterName", "WhereCondition", "DataMode", "WindowMode", "OpenArgs" }));
            actions.add (new MacroAction ("OpenReport", _("Open Report"), win, { "ReportName", "View", "FilterName", "WhereCondition", "WindowMode", "OpenArgs" }));
            actions.add (new MacroAction ("OpenTable", _("Open Table"), win, { "TableName", "View", "DataMode" }));
            actions.add (new MacroAction ("OpenQuery", _("Open Query"), win, { "QueryName", "View", "DataMode" }));
            actions.add (new MacroAction ("CloseWindow", _("Close Window"), win, { "ObjectType", "ObjectName", "Save" }));
            actions.add (new MacroAction ("SelectObject", _("Select Object"), win, { "ObjectType", "ObjectName", "InDatabaseWindow" }));
            actions.add (new MacroAction ("BrowseTo", _("Browse To"), win, { "ObjectType", "ObjectName", "PathToSubformControl", "WhereCondition", "Page", "DataMode" }));
            actions.add (new MacroAction ("GoToRecord", _("Go to Record"), data, { "ObjectType", "ObjectName", "Record", "Offset" }));
            actions.add (new MacroAction ("GoToControl", _("Go to Control"), data, { "ControlName" }));
            actions.add (new MacroAction ("FindRecord", _("Find Record"), data, { "FindWhat", "Match", "MatchCase", "Search", "SearchAsFormatted", "OnlyCurrentField", "FindFirst" }));
            actions.add (new MacroAction ("ApplyFilter", _("Apply Filter"), data, { "FilterName", "WhereCondition", "ControlName" }));
            actions.add (new MacroAction ("ShowAllRecords", _("Show All Records"), data, {}));
            actions.add (new MacroAction ("Requery", _("Requery"), data, { "ControlName" }));
            actions.add (new MacroAction ("RefreshRecord", _("Refresh Record"), data, {}));
            actions.add (new MacroAction ("SaveRecord", _("Save Record"), data, {}));
            actions.add (new MacroAction ("DeleteRecord", _("Delete Record"), data, {}));
            actions.add (new MacroAction ("UndoRecord", _("Undo Record"), data, {}));
            actions.add (new MacroAction ("SetValue", _("Set Value"), data, { "Item", "Expression" }));
            actions.add (new MacroAction ("SetProperty", _("Set Property"), ui, { "ControlName", "Property", "Value" }));
            actions.add (new MacroAction ("MessageBox", _("Message Box"), ui, { "Message", "Beep", "Type", "Title" }));
            actions.add (new MacroAction ("Beep", _("Beep"), ui, {}));
            actions.add (new MacroAction ("RunSQL", _("Run SQL"), data, { "SQLStatement", "UseTransaction" }));
            actions.add (new MacroAction ("OpenQueryAction", _("Run Action Query"), data, { "QueryName" }));
            actions.add (new MacroAction ("RunCode", _("Run Code"), flow, { "FunctionName" }));
            actions.add (new MacroAction ("RunMacro", _("Run Macro"), flow, { "MacroName", "RepeatCount", "RepeatExpression" }));
            actions.add (new MacroAction ("StopMacro", _("Stop Macro"), flow, {}));
            actions.add (new MacroAction ("StopAllMacros", _("Stop All Macros"), flow, {}));
            actions.add (new MacroAction ("CancelEvent", _("Cancel Event"), flow, {}));
            actions.add (new MacroAction ("OnError", _("On Error"), flow, { "Goto", "MacroName" }));
            actions.add (new MacroAction ("ClearMacroError", _("Clear Macro Error"), flow, {}));
            actions.add (new MacroAction ("SetTempVar", _("Set Temporary Variable"), flow, { "Name", "Expression" }));
            actions.add (new MacroAction ("RemoveTempVar", _("Remove Temporary Variable"), flow, { "Name" }));
            actions.add (new MacroAction ("RemoveAllTempVars", _("Remove All Temporary Variables"), flow, {}));
            actions.add (new MacroAction ("SetLocalVar", _("Set Local Variable"), flow, { "Name", "Expression" }));
            actions.add (new MacroAction ("SetWarnings", _("Set Warnings"), flow, { "WarningsOn" }));
            actions.add (new MacroAction ("ExportWithFormatting", _("Export With Formatting"), io, { "ObjectType", "ObjectName", "OutputFormat", "OutputFile", "AutoStart" }));
            actions.add (new MacroAction ("EMailDatabaseObject", _("Email Database Object"), io, { "ObjectType", "ObjectName", "OutputFormat", "To", "Subject", "MessageText" }));
            actions.add (new MacroAction ("PrintObject", _("Print Object"), io, {}));
            actions.add (new MacroAction ("QuitAccess", _("Close Database"), win, { "Options" }));
            actions.add (new MacroAction ("SetField", _("Set Field"), data, { "Name", "Value" }, true));
            actions.add (new MacroAction ("RaiseError", _("Raise Error"), flow, { "ErrorNumber", "ErrorDescription" }, true));
            actions.add (new MacroAction ("CreateRecord", _("Create Record"), data, { "CreateARecordIn", "Alias" }, true));
            actions.add (new MacroAction ("EditRecord", _("Edit Record"), data, { "Alias" }, true));
            actions.add (new MacroAction ("DeleteRecord", _("Delete Record"), data, { "Alias" }, true));
            actions.add (new MacroAction ("LookupRecord", _("Look Up Record"), data, { "LookUpARecordIn", "WhereCondition", "Alias" }, true));
            actions.add (new MacroAction ("ForEachRecord", _("For Each Record"), data, { "ForEachRecordIn", "WhereCondition", "Alias" }, true));
            return actions;
        }

        public static MacroAction? find (string name) {
            foreach (var a in all ()) {
                if (a.name.casefold () == name.casefold ()) return a;
            }
            return null;
        }
    }

    public class MacroStop : Object {
    }

    public class MacroRunner {
        private ScriptRuntime rt;
        private Database db;
        public Gee.HashMap<string, SValue> locals = new Gee.HashMap<string, SValue> ();
        private bool stopped;
        private string on_error = "fail";
        private string error_macro = "";
        public string last_error = "";
        public ScriptObject? context;
        public int depth;

        public MacroRunner (ScriptRuntime rt) {
            this.rt = rt;
            this.db = rt.db;
        }

        public static MacroDef? load (Database db, string name) {
            return MacroDef.from_json (name, db.get_meta ("macro:" + name));
        }

        public void run_named (string full) throws ScriptError {
            string name = full;
            string sub = "";
            int dot = full.index_of (".");
            if (dot > 0 && load (db, full) == null) {
                name = full.substring (0, dot);
                sub = full.substring (dot + 1);
            }
            var m = load (db, name);
            if (m == null) throw Script.fail (2485, _("The macro \"%s\" does not exist.").printf (name));
            if (sub != "") {
                var s = m.submacro (sub);
                if (s == null) throw Script.fail (2485, _("The macro \"%s\" does not exist.").printf (full));
                run_items (s.children);
            } else {
                run_items (m.items);
            }
        }

        public void run_items (Gee.List<MacroItem> items) throws ScriptError {
            depth++;
            if (depth > 20) {
                depth--;
                throw Script.fail (2485, _("Macros call each other too deeply."));
            }
            try {
                stopped = false;
                exec_list (items);
            } finally {
                depth--;
            }
        }

        private SValue eval (string expr) throws ScriptError {
            string e = expr.strip ();
            if (e.has_prefix ("=")) e = e.substring (1);
            if (e == "") return new SValue.empty ();
            return rt.evaluate (e, new MacroScope (this, context));
        }

        private bool test (string condition) throws ScriptError {
            if (condition.strip () == "") return true;
            return ScriptRuntime.truth (eval (condition));
        }

        private void exec_list (Gee.List<MacroItem> items) throws ScriptError {
            int i = 0;
            while (i < items.size && !stopped) {
                var it = items[i];
                switch (it.kind) {
                    case "comment":
                    case "submacro":
                        i++;
                        continue;
                    case "group":
                        exec_list (it.children);
                        i++;
                        continue;
                    case "if":
                        int j = i;
                        bool done = false;
                        while (j < items.size) {
                            var b = items[j];
                            if (j > i && b.kind != "elseif" && b.kind != "else") break;
                            if (!done && (b.kind == "else" || test (b.condition))) {
                                exec_list (b.children);
                                done = true;
                            }
                            j++;
                        }
                        i = j;
                        continue;
                    case "elseif":
                    case "else":
                        i++;
                        continue;
                }
                if (it.condition != "" && !test (it.condition)) {
                    i++;
                    continue;
                }
                try {
                    exec_action (it);
                } catch (ScriptError e) {
                    if (e is ScriptError.CANCELLED) throw e;
                    last_error = e.message;
                    rt.err.set_from (e);
                    if (on_error == "next") {
                        i++;
                        continue;
                    }
                    if (on_error == "macro" && error_macro != "") {
                        on_error = "fail";
                        run_named (error_macro);
                        return;
                    }
                    throw e;
                }
                i++;
            }
        }

        private SValue[] positional (MacroItem it, MacroAction? spec) throws ScriptError {
            SValue[] values = {};
            if (spec == null) {
                foreach (var e in it.args.entries) values += arg_value (e.key, e.value);
                return values;
            }
            foreach (string a in spec.args) {
                string raw = it.arg (a);
                values += raw == "" ? new MissingValue () : arg_value (a, raw);
            }
            return values;
        }

        private SValue arg_value (string name, string raw) throws ScriptError {
            string r = raw.strip ();
            if (r.has_prefix ("=")) return eval (r);
            switch (name.down ()) {
                case "view":
                    switch (r.down ()) {
                        case "design": return new SValue.int (1);
                        case "print preview":
                        case "preview": return new SValue.int (2);
                        case "datasheet": return new SValue.int (3);
                        case "report": return new SValue.int (5);
                        case "layout": return new SValue.int (6);
                        default: return new SValue.int (0);
                    }
                case "datamode":
                    switch (r.down ()) {
                        case "add": return new SValue.int (0);
                        case "read only": return new SValue.int (2);
                        default: return new SValue.int (1);
                    }
                case "windowmode":
                    switch (r.down ()) {
                        case "hidden": return new SValue.int (1);
                        case "dialog": return new SValue.int (3);
                        default: return new SValue.int (0);
                    }
                case "objecttype":
                    switch (r.down ()) {
                        case "table": return new SValue.int (0);
                        case "query": return new SValue.int (1);
                        case "form": return new SValue.int (2);
                        case "report": return new SValue.int (3);
                        case "macro": return new SValue.int (4);
                        case "module": return new SValue.int (5);
                        default: return new SValue.int (-1);
                    }
                case "record":
                    switch (r.down ()) {
                        case "previous": return new SValue.int (0);
                        case "first": return new SValue.int (2);
                        case "last": return new SValue.int (3);
                        case "go to":
                        case "goto": return new SValue.int (4);
                        case "new": return new SValue.int (5);
                        default: return new SValue.int (1);
                    }
            }
            return new SValue.str (r);
        }

        private void exec_action (MacroItem it) throws ScriptError {
            var spec = MacroCatalog.find (it.action);
            string a = it.action.down ();
            switch (a) {
                case "stopmacro":
                case "stopallmacros":
                    stopped = true;
                    return;
                case "cancelevent":
                    rt.event_cancelled = true;
                    return;
                case "onerror":
                    string g = it.arg ("Goto").down ();
                    on_error = g == "next" ? "next" : (g == "macro name" || g == "macro" ? "macro" : "fail");
                    error_macro = it.arg ("MacroName");
                    return;
                case "clearmacroerror":
                    last_error = "";
                    rt.err.clear ();
                    return;
                case "settempvar":
                    rt.temp_vars.set_var (it.arg ("Name"), eval (it.arg ("Expression")));
                    return;
                case "removetempvar":
                    rt.temp_vars.vars.unset (it.arg ("Name").down ());
                    return;
                case "removealltempvars":
                    rt.temp_vars.vars.clear ();
                    return;
                case "setlocalvar":
                    locals[it.arg ("Name").down ()] = eval (it.arg ("Expression"));
                    return;
                case "setwarnings":
                    rt.warnings = it.arg ("WarningsOn").down () != "no";
                    return;
                case "messagebox":
                    int type = 0;
                    switch (it.arg ("Type").down ()) {
                        case "critical": type = 16; break;
                        case "warning?": type = 32; break;
                        case "warning!": type = 48; break;
                        case "information": type = 64; break;
                    }
                    string msg = it.arg ("Message");
                    string text = msg;
                    if (msg.has_prefix ("=")) text = eval (msg).to_text ();
                    if (rt.host != null) rt.host.message_box (text, type, it.arg ("Title") != "" ? it.arg ("Title") : _("Database"));
                    return;
                case "runsql":
                    try {
                        AccessRun.execute (db, it.arg ("SQLStatement"));
                    } catch (Error e) {
                        throw Script.fail (3129, e.message);
                    }
                    if (rt.host != null) rt.host.run_command ("DataChanged", {}, {});
                    return;
                case "runcode":
                    string fn = it.arg ("FunctionName").strip ();
                    if (fn.has_prefix ("=")) fn = fn.substring (1);
                    if (!fn.contains ("(")) fn += "()";
                    rt.evaluate (fn, new MacroScope (this, context));
                    return;
                case "runmacro":
                    int repeat = it.arg ("RepeatCount") != "" ? int.parse (it.arg ("RepeatCount")) : 1;
                    string rexpr = it.arg ("RepeatExpression");
                    int n = 0;
                    while (true) {
                        if (it.arg ("RepeatCount") != "" && n >= repeat) break;
                        if (rexpr != "" && !test (rexpr)) break;
                        if (it.arg ("RepeatCount") == "" && rexpr == "" && n >= 1) break;
                        var inner = new MacroRunner (rt);
                        inner.context = context;
                        inner.depth = depth;
                        inner.run_named (it.arg ("MacroName"));
                        n++;
                        if (n > 100000) break;
                    }
                    return;
                case "setvalue":
                    var target = ScriptParser.parse_expression (it.arg ("Item"));
                    var value = eval (it.arg ("Expression"));
                    rt.assign_expression (target, value, new MacroScope (this, context));
                    return;
                case "beep":
                    if (rt.host != null) rt.host.run_command ("Beep", {}, {});
                    return;
            }
            if (spec != null && spec.data) throw Script.fail (2950, _("\"%s\" can be used only in data macros.").printf (it.action));
            if (rt.host == null) throw Script.fail (2950, _("The action \"%s\" is not available here.").printf (it.action));
            string[] names = {};
            if (spec != null) names = spec.args;
            var vals = positional (it, spec);
            rt.host.run_command (spec != null ? spec.name : it.action, vals, new string[vals.length]);
        }

        public SValue? local (string name) {
            return locals[name.down ()];
        }
    }

    public class MacroScope : ScriptObject {
        private MacroRunner runner;
        private ScriptObject? inner;

        public MacroScope (MacroRunner runner, ScriptObject? inner) {
            this.runner = runner;
            this.inner = inner;
        }

        public override string type_name () {
            return inner != null ? inner.type_name () : "Macro";
        }

        public override bool has_member (string name) {
            if (runner.local (name) != null) return true;
            if (name.ascii_casecmp ("MacroError") == 0) return true;
            return inner != null && inner.has_member (name);
        }

        public override SValue get_member (string name, SValue[] args) throws ScriptError {
            var l = runner.local (name);
            if (l != null) return l;
            if (name.ascii_casecmp ("MacroError") == 0) return new SValue.object (new MacroErrorObject (runner));
            if (inner != null) return inner.get_member (name, args);
            return base.get_member (name, args);
        }

        public override void set_member (string name, SValue[] args, SValue value) throws ScriptError {
            if (inner != null) {
                inner.set_member (name, args, value);
                return;
            }
            base.set_member (name, args, value);
        }
    }

    public class MacroErrorObject : ScriptObject {
        private MacroRunner runner;

        public MacroErrorObject (MacroRunner runner) {
            this.runner = runner;
        }

        public override SValue get_member (string name, SValue[] args) throws ScriptError {
            switch (name.down ()) {
                case "description": return new SValue.str (runner.last_error);
                case "number": return new SValue.int (runner.last_error != "" ? 1 : 0);
            }
            return base.get_member (name, args);
        }

        public override SValue get_default (SValue[] args) throws ScriptError {
            return new SValue.int (runner.last_error != "" ? 1 : 0);
        }
    }

    public class DataMacros {
        public const string[] EVENTS = { "BeforeChange", "BeforeDelete", "AfterInsert", "AfterUpdate", "AfterDelete" };

        public static string event_label (string e) {
            switch (e) {
                case "BeforeChange": return _("Before Change");
                case "BeforeDelete": return _("Before Delete");
                case "AfterInsert": return _("After Insert");
                case "AfterUpdate": return _("After Update");
                default: return _("After Delete");
            }
        }

        public static Gee.HashMap<string, MacroDef> load (Database db, string table) {
            var map = new Gee.HashMap<string, MacroDef> ();
            var o = Meta.parse_object (db.get_meta ("datamacro:" + table));
            if (o == null) return map;
            foreach (string e in EVENTS) {
                if (!o.has_member (e)) continue;
                var m = MacroDef.from_json (e, Json.to_string (o.get_member (e), false));
                if (m != null && m.items.size > 0) map[e] = m;
            }
            return map;
        }

        public static string to_json (Gee.Map<string, MacroDef> macros) {
            var b = new Json.Builder ();
            b.begin_object ();
            foreach (var e in macros.entries) {
                if (e.value.items.size == 0) continue;
                b.set_member_name (e.key);
                var p = new Json.Parser ();
                try {
                    p.load_from_data (e.value.to_json ());
                    b.add_value (p.get_root ().copy ());
                } catch (Error err) {
                    b.add_null_value ();
                }
            }
            b.end_object ();
            return Json.to_string (b.get_root (), false);
        }

        public static string trigger_name (string table, string ev) {
            return "sdb_dm_%s_%s".printf (table, ev);
        }

        public static void save (Database db, string table, Gee.Map<string, MacroDef> macros) throws Error {
            var def = db.load_table (table);
            string[] statements = {};
            foreach (var e in macros.entries) {
                if (e.value.items.size == 0) continue;
                foreach (string s in compile (def, e.key, e.value)) statements += s;
            }
            string json = to_json (macros);
            db.design_change (_("Change Data Macros"), { table }, () => {
                var old = db.query ("SELECT name FROM sqlite_master WHERE type = 'trigger' AND tbl_name = ? COLLATE NOCASE AND name LIKE 'sdb_dm_%'", { new DbValue.text (table) });
                foreach (var r in old.rows) db.exec ("DROP TRIGGER %s".printf (Sql.quote_ident (r.get (0).to_string ())));
                foreach (string s in statements) db.exec (s);
                db.set_meta ("datamacro:" + table, macros.size > 0 ? json : null);
            }, { "datamacro:", "table:", "views:", "layout-table:" });
        }

        private class Ctx {
            public string table;
            public string row_ref;
            public string old_ref = "OLD";
            public string alias = "";
            public string alias_table = "";
            public string alias_where = "";
            public string[] conditions = {};
        }

        public static string[] compile (TableDef def, string ev, MacroDef m) throws Error {
            var ctx = new Ctx ();
            ctx.table = def.name;
            ctx.row_ref = ev == "AfterDelete" || ev == "BeforeDelete" ? "OLD" : "NEW";
            var body_list = new Gee.ArrayList<string> ();
            compile_list (m.items, ctx, ev, body_list);
            if (body_list.size == 0) return {};
            string[] body = body_list.to_array ();
            string t = Sql.quote_ident (def.name);
            string[] out = {};
            switch (ev) {
                case "BeforeChange":
                    out += "CREATE TRIGGER %s BEFORE INSERT ON %s FOR EACH ROW BEGIN %s END".printf (Sql.quote_ident (trigger_name (def.name, "BeforeInsert")), t, string.joinv (" ", only_checks (body)));
                    out += "CREATE TRIGGER %s BEFORE UPDATE ON %s FOR EACH ROW BEGIN %s END".printf (Sql.quote_ident (trigger_name (def.name, "BeforeUpdate")), t, string.joinv (" ", only_checks (body)));
                    string[] sets = only_sets (body);
                    if (sets.length > 0) {
                        out += "CREATE TRIGGER %s AFTER INSERT ON %s FOR EACH ROW BEGIN %s END".printf (Sql.quote_ident (trigger_name (def.name, "SetInsert")), t, string.joinv (" ", sets));
                        out += "CREATE TRIGGER %s AFTER UPDATE ON %s FOR EACH ROW BEGIN %s END".printf (Sql.quote_ident (trigger_name (def.name, "SetUpdate")), t, string.joinv (" ", sets));
                    }
                    for (int i = 0; i < out.length; i++) {
                        if (out[i].contains ("BEGIN  END")) out[i] = "";
                    }
                    break;
                case "BeforeDelete":
                    out += "CREATE TRIGGER %s BEFORE DELETE ON %s FOR EACH ROW BEGIN %s END".printf (Sql.quote_ident (trigger_name (def.name, ev)), t, string.joinv (" ", body));
                    break;
                case "AfterInsert":
                    out += "CREATE TRIGGER %s AFTER INSERT ON %s FOR EACH ROW BEGIN %s END".printf (Sql.quote_ident (trigger_name (def.name, ev)), t, string.joinv (" ", body));
                    break;
                case "AfterUpdate":
                    out += "CREATE TRIGGER %s AFTER UPDATE ON %s FOR EACH ROW BEGIN %s END".printf (Sql.quote_ident (trigger_name (def.name, ev)), t, string.joinv (" ", body));
                    break;
                default:
                    out += "CREATE TRIGGER %s AFTER DELETE ON %s FOR EACH ROW BEGIN %s END".printf (Sql.quote_ident (trigger_name (def.name, ev)), t, string.joinv (" ", body));
                    break;
            }
            string[] clean = {};
            foreach (string s in out) {
                if (s != "") clean += s;
            }
            return clean;
        }

        private static string[] only_checks (string[] body) {
            string[] r = {};
            foreach (string s in body) {
                if (!s.has_prefix ("\x01")) r += s;
            }
            return r;
        }

        private static string[] only_sets (string[] body) {
            string[] r = {};
            foreach (string s in body) {
                if (s.has_prefix ("\x01")) r += s.substring (1);
            }
            return r;
        }

        private static string where_of (Ctx ctx) {
            if (ctx.conditions.length == 0) return "1";
            string[] w = {};
            foreach (string c in ctx.conditions) w += "(" + c + ")";
            return string.joinv (" AND ", w);
        }

        private static string translate (string expr, Ctx ctx) {
            string e = expr.strip ();
            if (e.has_prefix ("=")) e = e.substring (1);
            var toks = AccessSql.tokenize (e);
            var list = new Gee.ArrayList<AToken> ();
            for (int i = 0; i < toks.size; i++) {
                var t = toks[i];
                int nx = i + 1;
                while (nx < toks.size && toks[nx].kind == ATok.SPACE) nx++;
                bool call = nx < toks.size && toks[nx].op ("(");
                bool name_tok = t.kind == ATok.IDENT || (t.kind == ATok.WORD && !call && !is_word (t.text));
                if (name_tok) {
                    bool qualified = i + 2 < toks.size && (toks[i + 1].op (".") || toks[i + 1].op ("!")) && (toks[i + 2].kind == ATok.IDENT || toks[i + 2].kind == ATok.WORD);
                    bool after_dot = i > 0 && (toks[i - 1].op (".") || toks[i - 1].op ("!"));
                    string? text = null;
                    if (qualified) {
                        string q = t.text;
                        string col = toks[i + 2].text;
                        if (q.casefold () == "old") text = "OLD.%s".printf (Sql.quote_ident (col));
                        else if (ctx.alias != "" && q.casefold () == ctx.alias.casefold ()) text = Sql.quote_ident (ctx.alias_table) + "." + Sql.quote_ident (col);
                        else if (q.casefold () == ctx.table.casefold ()) text = "%s.%s".printf (ctx.row_ref, Sql.quote_ident (col));
                        else text = Sql.quote_ident (q) + "." + Sql.quote_ident (col);
                        i += 2;
                    } else if (!after_dot) {
                        if (ctx.alias_table != "") text = Sql.quote_ident (ctx.alias_table) + "." + Sql.quote_ident (t.text);
                        else text = "%s.%s".printf (ctx.row_ref, Sql.quote_ident (t.text));
                    }
                    if (text != null) {
                        list.add (new AToken (ATok.WORD, text));
                        continue;
                    }
                }
                list.add (t);
            }
            return AccessSql.expression_from_tokens (list);
        }

        private static bool is_word (string w) {
            string[] words = { "AND", "OR", "NOT", "IS", "NULL", "LIKE", "BETWEEN", "IN", "TRUE", "FALSE", "MOD", "XOR" };
            foreach (string x in words) {
                if (x.ascii_casecmp (w) == 0) return true;
            }
            return false;
        }

        private static void compile_list (Gee.List<MacroItem> items, Ctx ctx, string ev, Gee.ArrayList<string> body) throws Error {
            int i = 0;
            while (i < items.size) {
                var it = items[i];
                if (it.kind == "comment") {
                    i++;
                    continue;
                }
                if (it.kind == "group") {
                    compile_list (it.children, ctx, ev, body);
                    i++;
                    continue;
                }
                if (it.kind == "if") {
                    string[] negations = {};
                    int j = i;
                    while (j < items.size) {
                        var b = items[j];
                        if (j > i && b.kind != "elseif" && b.kind != "else") break;
                        string[] saved = ctx.conditions;
                        string[] conds = saved;
                        foreach (string n in negations) conds += n;
                        string c = "";
                        if (b.kind != "else") {
                            c = translate (b.condition, ctx);
                            conds += c;
                        }
                        ctx.conditions = conds;
                        compile_list (b.children, ctx, ev, body);
                        ctx.conditions = saved;
                        if (c != "") negations += "NOT (%s)".printf (c);
                        j++;
                    }
                    i = j;
                    continue;
                }
                if (it.kind != "action") {
                    i++;
                    continue;
                }
                compile_action (it, ctx, ev, body);
                i++;
            }
        }

        private static void compile_action (MacroItem it, Ctx ctx, string ev, Gee.ArrayList<string> body) throws Error {
            string a = it.action.down ();
            switch (a) {
                case "raiseerror":
                    string msg = it.arg ("ErrorDescription");
                    if (msg == "") msg = _("The change was refused by a data macro.");
                    body.add ("SELECT RAISE(ABORT, %s) WHERE %s;".printf (Sql.quote_string (msg), where_of (ctx)));
                    return;
                case "setfield":
                    string field = it.arg ("Name");
                    int dot = field.last_index_of (".");
                    if (dot > 0) field = field.substring (dot + 1);
                    field = Sql.unquote_ident (field.strip ());
                    if (field.has_prefix ("[") && field.has_suffix ("]")) field = field.substring (1, field.length - 2);
                    string value = translate (it.arg ("Value"), ctx);
                    if (ctx.alias_table != "") {
                        body.add ("UPDATE %s SET %s = %s WHERE (%s) AND %s;".printf (Sql.quote_ident (ctx.alias_table), Sql.quote_ident (field), value, ctx.alias_where, where_of (ctx)));
                        return;
                    }
                    if (ev != "BeforeChange") throw new SchemaError.INVALID (_("Set Field changes the current record only in Before Change."));
                    body.add ("\x01UPDATE %s SET %s = %s WHERE rowid = NEW.rowid AND %s;".printf (Sql.quote_ident (ctx.table), Sql.quote_ident (field), value, where_of (ctx)));
                    return;
                case "createrecord":
                    string target = strip_brackets (it.arg ("CreateARecordIn"));
                    string[] cols = {};
                    string[] vals = {};
                    foreach (var c in it.children) {
                        if (c.kind != "action" || c.action.down () != "setfield") continue;
                        string f = strip_brackets (c.arg ("Name"));
                        int d = f.last_index_of (".");
                        if (d > 0) f = strip_brackets (f.substring (d + 1));
                        cols += Sql.quote_ident (f);
                        vals += translate (c.arg ("Value"), ctx);
                    }
                    if (cols.length == 0) body.add ("INSERT INTO %s DEFAULT VALUES;".printf (Sql.quote_ident (target)));
                    else body.add ("INSERT INTO %s (%s) SELECT %s WHERE %s;".printf (Sql.quote_ident (target), string.joinv (", ", cols), string.joinv (", ", vals), where_of (ctx)));
                    return;
                case "lookuprecord":
                case "foreachrecord":
                    string src = strip_brackets (it.arg (a == "lookuprecord" ? "LookUpARecordIn" : "ForEachRecordIn"));
                    var inner = new Ctx ();
                    inner.table = ctx.table;
                    inner.row_ref = ctx.row_ref;
                    inner.alias = it.arg ("Alias") != "" ? it.arg ("Alias") : src;
                    inner.alias_table = src;
                    inner.conditions = ctx.conditions;
                    string where = it.arg ("WhereCondition").strip () != "" ? translate (it.arg ("WhereCondition"), inner) : "1";
                    inner.alias_where = where;
                    foreach (var c in it.children) {
                        if (c.kind == "action" && (c.action.down () == "editrecord")) {
                            foreach (var s in c.children) compile_action (s, inner, ev, body);
                            continue;
                        }
                        if (c.kind == "action" && c.action.down () == "deleterecord") {
                            body.add ("DELETE FROM %s WHERE (%s) AND %s;".printf (Sql.quote_ident (src), where, where_of (ctx)));
                            continue;
                        }
                        var one = new Gee.ArrayList<MacroItem> ();
                        one.add (c);
                        compile_list (one, inner, ev, body);
                    }
                    return;
                case "editrecord":
                    foreach (var s in it.children) compile_action (s, ctx, ev, body);
                    return;
                case "deleterecord":
                    if (ctx.alias_table != "") {
                        body.add ("DELETE FROM %s WHERE (%s) AND %s;".printf (Sql.quote_ident (ctx.alias_table), ctx.alias_where, where_of (ctx)));
                        return;
                    }
                    body.add ("DELETE FROM %s WHERE rowid = %s.rowid AND %s;".printf (Sql.quote_ident (ctx.table), ctx.row_ref, where_of (ctx)));
                    return;
                case "setlocalvar":
                case "stopmacro":
                    return;
            }
            throw new SchemaError.INVALID (_("The action \"%s\" cannot be used in a data macro.").printf (it.action));
        }

        private static string strip_brackets (string s) {
            string t = s.strip ();
            if (t.has_prefix ("[") && t.has_suffix ("]")) return t.substring (1, t.length - 2);
            return t;
        }
    }

    public class EventHandler {
        public static bool is_procedure (string handler) {
            return handler.strip ().down () == "[event procedure]";
        }

        public static bool fire (ScriptRuntime rt, ScriptObject owner, string module_name, string object_name, string event_name, string handler, SValue[] extra, out bool cancel) throws ScriptError {
            cancel = false;
            string h = handler.strip ();
            if (h == "") return false;
            rt.event_cancelled = false;
            if (is_procedure (h)) {
                var m = rt.find_module (module_name);
                if (m == null) return false;
                string proc_name = "%s_%s".printf (object_name, event_name);
                var p = m.find (proc_name);
                if (p == null) return false;
                SVar[] args = {};
                SVar? cancel_var = null;
                foreach (var prm in p.params) {
                    string pn = prm.name.down ();
                    if (pn == "cancel") {
                        cancel_var = new SVar (new SValue.int (0));
                        args += cancel_var;
                    } else if (args.length - (cancel_var != null ? 1 : 0) < extra.length) {
                        args += new SVar (extra[args.length - (cancel_var != null ? 1 : 0)]);
                    } else {
                        args += new SVar (new SValue.int (0));
                    }
                }
                rt.steps = 0;
                rt.call_with_refs (p, args, owner);
                if (cancel_var != null && ScriptRuntime.truth (cancel_var.value)) cancel = true;
                if (rt.event_cancelled) cancel = true;
                return true;
            }
            if (h.has_prefix ("=")) {
                rt.evaluate (h.substring (1), owner, owner);
                cancel = rt.event_cancelled;
                return true;
            }
            if (h.has_prefix ("{")) {
                var m = MacroDef.from_json ("", h);
                if (m == null) return false;
                var runner = new MacroRunner (rt);
                runner.context = owner;
                runner.run_items (m.items);
                cancel = rt.event_cancelled;
                return true;
            }
            var runner = new MacroRunner (rt);
            runner.context = owner;
            runner.run_named (h);
            cancel = rt.event_cancelled;
            return true;
        }
    }
}
