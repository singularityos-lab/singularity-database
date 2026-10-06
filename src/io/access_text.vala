namespace Singularity.Apps.Database {

    public errordomain AccessTextError {
        FORMAT
    }

    public class AccessTextNode {
        public string kind = "";
        public string name = "";
        public OrderedMap<string> props = new OrderedMap<string> ();
        public Gee.ArrayList<AccessTextNode> children = new Gee.ArrayList<AccessTextNode> ();
        public weak AccessTextNode? parent;

        public const string[] SECTION_KINDS = {
            "FormHeader", "FormFooter", "PageHeader", "PageFooter", "Section", "BreakHeader", "BreakFooter", "ReportHeader", "ReportFooter"
        };

        public AccessTextNode (string kind) {
            this.kind = kind;
        }

        public string? get (string key) {
            foreach (var e in props.entries) {
                if (e.key.casefold () == key.casefold ()) return e.value;
            }
            return null;
        }

        public string text (string key, string fallback = "") {
            return get (key) ?? fallback;
        }

        public int get_int (string key, int fallback = 0) {
            string? v = get (key);
            if (v == null) return fallback;
            int64 n;
            if (int64.try_parse (v.strip (), out n)) return (int) n;
            return fallback;
        }

        public bool get_bool (string key, bool fallback = false) {
            string? v = get (key);
            if (v == null) return fallback;
            string s = v.strip ();
            if (s == "NotDefault") return true;
            if (s == "Default") return false;
            int64 n;
            if (int64.try_parse (s, out n)) return n != 0;
            return s.down () == "true" || s.down () == "yes";
        }

        public bool is_section () {
            return kind in SECTION_KINDS;
        }

        public bool is_group () {
            return kind == "";
        }

        public string section_kind () {
            switch (kind) {
                case "Section": return "Detail";
                case "BreakHeader": return "GroupHeader";
                case "BreakFooter": return "GroupFooter";
                default: return kind;
            }
        }

        public Gee.ArrayList<AccessTextNode> sections () {
            var list = new Gee.ArrayList<AccessTextNode> ();
            collect_sections (this, list);
            return list;
        }

        private static void collect_sections (AccessTextNode n, Gee.ArrayList<AccessTextNode> list) {
            foreach (var c in n.children) {
                if (c.is_section ()) list.add (c);
                else if (c.is_group ()) collect_sections (c, list);
            }
        }

        public Gee.ArrayList<AccessTextNode> controls () {
            var list = new Gee.ArrayList<AccessTextNode> ();
            collect_controls (this, list);
            return list;
        }

        private static void collect_controls (AccessTextNode n, Gee.ArrayList<AccessTextNode> list) {
            foreach (var c in n.children) {
                if (!c.is_group () && !c.is_section () && c.name != "") list.add (c);
                collect_controls (c, list);
            }
        }

        public Gee.ArrayList<AccessTextNode> defaults () {
            var list = new Gee.ArrayList<AccessTextNode> ();
            foreach (var c in children) {
                if (!c.is_group ()) continue;
                foreach (var d in c.children) {
                    if (!d.is_group () && !d.is_section () && d.name == "") list.add (d);
                }
            }
            return list;
        }

        public AccessTextNode? find (string control_name) {
            foreach (var c in controls ()) {
                if (c.name.casefold () == control_name.casefold ()) return c;
            }
            return null;
        }

        public AccessTextNode? container () {
            var p = parent;
            while (p != null && p.is_group ()) p = p.parent;
            return p;
        }

        public Gee.ArrayList<string> events () {
            var list = new Gee.ArrayList<string> ();
            foreach (var e in props.entries) {
                if ((e.key.has_prefix ("On") || e.key.has_prefix ("Before") || e.key.has_prefix ("After")) && e.value.strip () != "") list.add (e.key);
            }
            return list;
        }
    }

    public class AccessTextObject {
        public string kind = "unknown";
        public string name = "";
        public int version;
        public AccessTextNode root = new AccessTextNode ("");
        public OrderedMap<string> header = new OrderedMap<string> ();
        public string code = "";
    }

    public class AccessMacroStep {
        public string kind = "action";
        public string name = "";
        public string condition = "";
        public string comment = "";
        public OrderedMap<string> arguments = new OrderedMap<string> ();
        public string[] values = {};
        public Gee.ArrayList<AccessMacroStep> children = new Gee.ArrayList<AccessMacroStep> ();

        public AccessMacroStep (string kind, string name = "") {
            this.kind = kind;
            this.name = name;
        }

        public string argument (string key, string fallback = "") {
            foreach (var e in arguments.entries) {
                if (e.key.casefold () == key.casefold ()) return e.value;
            }
            return fallback;
        }
    }

    public class AccessText {
        public const int TWIPS_PER_INCH = 1440;

        public static double twips_to_points (int twips) {
            return twips / 20.0;
        }

        public static int twips_to_pixels (int twips, double dpi = 96) {
            return (int) Math.round (twips * dpi / TWIPS_PER_INCH);
        }

        public static string decode (uint8[] data) {
            if (data.length >= 2 && data[0] == 0xFF && data[1] == 0xFE) {
                var sb = new StringBuilder ();
                int i = 2;
                while (i + 1 < data.length) {
                    uint unit = data[i] | (data[i + 1] << 8);
                    i += 2;
                    if (unit >= 0xD800 && unit <= 0xDBFF && i + 1 < data.length) {
                        uint low = data[i] | (data[i + 1] << 8);
                        if (low >= 0xDC00 && low <= 0xDFFF) {
                            i += 2;
                            sb.append_unichar ((unichar) (0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00)));
                            continue;
                        }
                    }
                    if (unit == 0) continue;
                    if (unit >= 0xD800 && unit <= 0xDFFF) unit = 0xFFFD;
                    sb.append_unichar ((unichar) unit);
                }
                return sb.str;
            }
            int start = data.length >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF ? 3 : 0;
            var raw = new StringBuilder ();
            raw.append_len ((string) ((uint8*) data + start), data.length - start);
            if (raw.str.validate ()) return raw.str;
            return MdbCodec.cp1252 (data, start, data.length - start);
        }

        private static string[] split_lines (string text) {
            string t = text;
            if (t.has_prefix ("\uFEFF")) t = t.substring (3);
            return t.replace ("\r\n", "\n").replace ("\r", "\n").split ("\n");
        }

        private static bool read_quoted (string s, int start, StringBuilder sb, out int end) {
            int i = start + 1;
            end = s.length;
            while (i < s.length) {
                char c = s[i];
                if (c == '\\' && i + 1 < s.length) {
                    char n = s[i + 1];
                    if (n >= '0' && n <= '7') {
                        int v = 0;
                        int k = 1;
                        while (k <= 3 && i + k < s.length && s[i + k] >= '0' && s[i + k] <= '7') {
                            v = v * 8 + (s[i + k] - '0');
                            k++;
                        }
                        sb.append_unichar ((unichar) v);
                        i += k;
                        continue;
                    }
                    sb.append_c (n);
                    i += 2;
                    continue;
                }
                if (c == '"') {
                    end = i + 1;
                    return true;
                }
                sb.append_c (c);
                i++;
            }
            return false;
        }

        public static string unquote (string value) {
            string v = value.strip ();
            if (!v.has_prefix ("\"")) return v;
            var sb = new StringBuilder ();
            int end;
            read_quoted (v, 0, sb, out end);
            return sb.str;
        }

        private static string prop_key (string raw) {
            string k = raw.strip ();
            int q = k.index_of_char ('"');
            if (q > 0 && k.has_suffix ("\"")) return k.substring (q + 1, k.length - q - 2);
            return k;
        }

        public static AccessTextObject parse_object (string text) throws Error {
            var obj = new AccessTextObject ();
            string[] lines = split_lines (text);
            int first = 0;
            while (first < lines.length && lines[first].strip () == "") first++;
            if (first >= lines.length) throw new AccessTextError.FORMAT (_("The exported Access object is empty."));
            string head = lines[first].strip ();
            if (head.has_prefix ("VERSION ") && head.contains ("CLASS")) {
                obj.kind = "class";
                int i = first + 1;
                if (i < lines.length && lines[i].strip () == "BEGIN") {
                    while (i < lines.length && lines[i].strip () != "END") i++;
                    i++;
                }
                read_module (obj, lines, i);
                return obj;
            }
            if (head.has_prefix ("Attribute VB_")) {
                obj.kind = "module";
                read_module (obj, lines, first);
                return obj;
            }
            var root = new AccessTextNode ("");
            var stack = new Gee.ArrayList<AccessTextNode> ();
            stack.add (root);
            int n = lines.length;
            int li = first;
            while (li < n) {
                string raw = lines[li];
                string l = raw.strip ();
                li++;
                if (l == "") continue;
                var cur = stack[stack.size - 1];
                if (l == "CodeBehindForm") {
                    var code = new StringBuilder ();
                    for (int k = li; k < n; k++) {
                        if (lines[k].has_prefix ("Attribute VB_")) continue;
                        code.append (lines[k]).append_c ('\n');
                    }
                    obj.code = code.str.strip ();
                    break;
                }
                if (l == "End") {
                    if (stack.size > 1) stack.remove_at (stack.size - 1);
                    continue;
                }
                if (l == "Begin" || (l.has_prefix ("Begin ") && !l.contains ("="))) {
                    var node = new AccessTextNode (l == "Begin" ? "" : l.substring (6).strip ());
                    node.parent = cur;
                    cur.children.add (node);
                    stack.add (node);
                    continue;
                }
                int eq = l.index_of_char ('=');
                if (eq <= 0) continue;
                string key = prop_key (l.substring (0, eq));
                string rest = l.substring (eq + 1).strip ();
                string value;
                if (rest == "Begin") {
                    var blob = new StringBuilder ();
                    while (li < n && lines[li].strip () != "End") {
                        string b = lines[li].strip ();
                        li++;
                        if (b.has_prefix ("\"")) blob.append (unquote (b));
                        else blob.append (b.has_prefix ("0x") ? b.substring (2).replace (",", "").replace (" ", "") : b.replace (",", "").replace (" ", ""));
                    }
                    li++;
                    value = blob.str;
                } else if (rest.has_prefix ("\"")) {
                    var sb = new StringBuilder ();
                    int end;
                    read_quoted (rest, 0, sb, out end);
                    while (li < n && lines[li].strip ().has_prefix ("\"")) {
                        read_quoted (lines[li].strip (), 0, sb, out end);
                        li++;
                    }
                    value = sb.str;
                } else {
                    value = rest;
                }
                if (cur.props.has_key (key)) {
                    int k = 2;
                    while (cur.props.has_key ("%s#%d".printf (key, k))) k++;
                    cur.props["%s#%d".printf (key, k)] = value;
                } else {
                    cur.props[key] = value;
                }
                if (key == "Name" && cur != root) cur.name = value;
            }
            foreach (var e in root.props.entries) obj.header[e.key] = e.value;
            obj.version = root.get_int ("Version", 0);
            AccessTextNode? top = null;
            foreach (var c in root.children) {
                if (c.kind == "Form" || c.kind == "Report") top = c;
            }
            if (top != null) {
                obj.kind = top.kind.down ();
                obj.root = top;
                obj.name = top.name;
            } else if (root.get ("Operation") != null || root.get ("SQL") != null) {
                obj.kind = "query";
                obj.root = root;
            } else {
                bool actions = false;
                foreach (var c in root.children) {
                    if (c.get ("Action") != null || c.get ("Comment") != null || c.get ("MacroName") != null) actions = true;
                }
                obj.kind = actions ? "macro" : "unknown";
                obj.root = root;
            }
            return obj;
        }

        private static void read_module (AccessTextObject obj, string[] lines, int start) {
            var code = new StringBuilder ();
            for (int i = start; i < lines.length; i++) {
                string l = lines[i];
                if (l.has_prefix ("Attribute VB_")) {
                    string s = l.substring ("Attribute ".length);
                    int eq = s.index_of_char ('=');
                    if (eq > 0) {
                        string key = s.substring (0, eq).strip ();
                        string value = unquote (s.substring (eq + 1));
                        obj.header[key] = value;
                        if (key == "VB_Name") obj.name = value;
                    }
                    continue;
                }
                code.append (l).append_c ('\n');
            }
            obj.code = code.str.strip ();
        }

        private static string[] legacy_argument_names (string action) {
            switch (action.down ()) {
                case "openform": return { "FormName", "View", "FilterName", "WhereCondition", "DataMode", "WindowMode", "OpenArgs" };
                case "openreport": return { "ReportName", "View", "FilterName", "WhereCondition", "WindowMode", "OpenArgs" };
                case "openquery": return { "QueryName", "View", "DataMode" };
                case "opentable": return { "TableName", "View", "DataMode" };
                case "runcode": return { "FunctionName" };
                case "runsql": return { "SQLStatement", "UseTransaction" };
                case "msgbox": return { "Message", "Beep", "Type", "Title" };
                case "setvalue": return { "Item", "Expression" };
                case "close": return { "ObjectType", "ObjectName", "Save" };
                case "gotorecord": return { "ObjectType", "ObjectName", "Record", "Offset" };
                case "gotocontrol": return { "ControlName" };
                case "runmacro": return { "MacroName", "RepeatCount", "RepeatExpression" };
                case "setwarnings": return { "WarningsOn" };
                case "requery": return { "ControlName" };
                case "applyfilter": return { "FilterName", "WhereCondition", "ControlName" };
                case "findrecord": return { "FindWhat", "Match", "MatchCase", "Search", "SearchAsFormatted", "OnlyCurrentField", "FindFirst" };
                case "settempvar": return { "Name", "Expression" };
                case "removetempvar": return { "Name" };
                case "quit": return { "Options" };
                case "echo": return { "EchoOn", "StatusBarText" };
                case "hourglass": return { "HourglassOn" };
                case "outputto": return { "ObjectType", "ObjectName", "OutputFormat", "OutputFile", "AutoStart", "TemplateFile", "Encoding", "OutputQuality" };
                case "transferspreadsheet": return { "TransferType", "SpreadsheetType", "TableName", "FileName", "HasFieldNames", "Range" };
                case "transfertext": return { "TransferType", "SpecificationName", "TableName", "FileName", "HasFieldNames", "HTMLTableName", "CodePage" };
                case "selectobject": return { "ObjectType", "ObjectName", "InDatabaseWindow" };
                case "printout": return { "PrintRange", "PageFrom", "PageTo", "PrintQuality", "Copies", "CollateCopies" };
                case "sendkeys": return { "Keystrokes", "Wait" };
                case "stopmacro":
                case "stopallmacros":
                case "beep":
                case "maximize":
                case "minimize":
                case "restore":
                    return {};
                default: return {};
            }
        }

        public static Gee.ArrayList<AccessMacroStep> parse_macro (string text) throws Error {
            string t = text.strip ();
            if (t.has_prefix ("\uFEFF")) t = t.substring (3);
            if (t.has_prefix ("<")) return parse_macro_xml (t);
            var obj = parse_object (text);
            var axl = new StringBuilder ();
            foreach (var c in obj.root.children) {
                foreach (var e in c.props.entries) {
                    if (e.key.has_prefix ("Comment") && e.value.has_prefix ("_AXL:")) axl.append (e.value.substring (5));
                }
            }
            if (axl.len > 0) {
                try {
                    return parse_macro_xml (axl.str);
                } catch (Error e) {
                }
            }
            var steps = new Gee.ArrayList<AccessMacroStep> ();
            AccessMacroStep? sub = null;
            AccessMacroStep? last_if = null;
            foreach (var c in obj.root.children) {
                string? macro_name = c.get ("MacroName");
                if (macro_name != null && macro_name.strip () != "") {
                    sub = new AccessMacroStep ("submacro", macro_name);
                    steps.add (sub);
                    last_if = null;
                }
                var target = sub != null ? sub.children : steps;
                string? action = c.get ("Action");
                string? comment = c.get ("Comment");
                if (action == null) {
                    if (comment != null && !comment.has_prefix ("_AXL:")) {
                        var cm = new AccessMacroStep ("comment");
                        cm.comment = comment;
                        target.add (cm);
                    }
                    continue;
                }
                var step = new AccessMacroStep ("action", action);
                if (comment != null && !comment.has_prefix ("_AXL:")) step.comment = comment;
                string[] values = {};
                foreach (var e in c.props.entries) {
                    if (e.key == "Argument" || e.key.has_prefix ("Argument#")) values += e.value;
                }
                step.values = values;
                string[] names = legacy_argument_names (action);
                for (int i = 0; i < values.length; i++) step.arguments[i < names.length ? names[i] : "Argument%d".printf (i + 1)] = values[i];
                string? cond = c.get ("Condition");
                if (cond != null && cond.strip () == "...") {
                    if (last_if != null) {
                        last_if.children.add (step);
                        continue;
                    }
                } else if (cond != null && cond.strip () != "") {
                    last_if = new AccessMacroStep ("if");
                    last_if.condition = cond.strip ();
                    last_if.children.add (step);
                    target.add (last_if);
                    continue;
                }
                last_if = null;
                target.add (step);
            }
            return steps;
        }

        private static string strip_declaration (string xml) {
            string s = xml.strip ();
            if (s.has_prefix ("<?xml")) {
                int end = s.index_of ("?>");
                if (end > 0) s = s.substring (end + 2).strip ();
            }
            return s;
        }

        public static Gee.ArrayList<AccessMacroStep> parse_macro_xml (string xml) throws Error {
            string body = strip_declaration (xml);
            Xml.Doc* doc = Xml.Parser.read_memory (body, body.length, null, null, Xml.ParserOption.NONET | Xml.ParserOption.NOBLANKS);
            if (doc == null) throw new AccessTextError.FORMAT (_("The macro XML could not be read."));
            var steps = new Gee.ArrayList<AccessMacroStep> ();
            Xml.Node* root = doc->get_root_element ();
            if (root != null) {
                for (Xml.Node* c = root->children; c != null; c = c->next) {
                    if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                    if (c->name == "Statements") read_statements (c, steps);
                    else if (c->name == "Sub" || c->name == "Submacro") {
                        var sub = new AccessMacroStep ("submacro", c->get_prop ("Name") ?? "");
                        read_statements (c, sub.children);
                        steps.add (sub);
                    } else if (c->name == "DataMacros" || c->name == "DataMacro") {
                        var dm = new AccessMacroStep ("datamacro", c->get_prop ("Event") ?? c->get_prop ("Name") ?? "");
                        read_statements (c, dm.children);
                        steps.add (dm);
                    }
                }
            }
            delete doc;
            return steps;
        }

        private static Xml.Node* element (Xml.Node* n, string name) {
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type == Xml.ElementType.ELEMENT_NODE && c->name == name) return c;
            }
            return null;
        }

        private static void read_statements (Xml.Node* parent, Gee.ArrayList<AccessMacroStep> out_list) {
            Xml.Node* container = parent->name == "Statements" ? parent : element (parent, "Statements");
            if (container == null) container = parent;
            for (Xml.Node* c = container->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                switch (c->name) {
                    case "Action":
                        var step = new AccessMacroStep ("action", c->get_prop ("Name") ?? "");
                        string[] values = {};
                        for (Xml.Node* a = c->children; a != null; a = a->next) {
                            if (a->type != Xml.ElementType.ELEMENT_NODE || a->name != "Argument") continue;
                            string v = a->get_content () ?? "";
                            step.arguments[a->get_prop ("Name") ?? "Argument%d".printf (values.length + 1)] = v;
                            values += v;
                        }
                        step.values = values;
                        out_list.add (step);
                        break;
                    case "Comment":
                        var cm = new AccessMacroStep ("comment");
                        cm.comment = c->get_content () ?? "";
                        out_list.add (cm);
                        break;
                    case "ConditionalBlock":
                        for (Xml.Node* b = c->children; b != null; b = b->next) {
                            if (b->type != Xml.ElementType.ELEMENT_NODE) continue;
                            if (b->name != "If" && b->name != "ElseIf" && b->name != "Else") continue;
                            var br = new AccessMacroStep (b->name.down ());
                            Xml.Node* cond = element (b, "Condition");
                            if (cond != null) br.condition = cond->get_content () ?? "";
                            read_statements (b, br.children);
                            out_list.add (br);
                        }
                        break;
                    case "Group":
                        var g = new AccessMacroStep ("group", c->get_prop ("Name") ?? "");
                        read_statements (c, g.children);
                        out_list.add (g);
                        break;
                    case "Sub":
                    case "Submacro":
                        var sub = new AccessMacroStep ("submacro", c->get_prop ("Name") ?? "");
                        read_statements (c, sub.children);
                        out_list.add (sub);
                        break;
                    case "OnError":
                        var oe = new AccessMacroStep ("action", "OnError");
                        for (Xml.Node* a = c->children; a != null; a = a->next) {
                            if (a->type == Xml.ElementType.ELEMENT_NODE) oe.arguments[a->name] = a->get_content () ?? "";
                        }
                        out_list.add (oe);
                        break;
                    default:
                        break;
                }
            }
        }
    }
}
