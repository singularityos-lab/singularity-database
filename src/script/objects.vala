namespace Singularity.Apps.Database {

    public class ErrObject : ScriptObject {
        public int64 number;
        public string description = "";
        public string source = "";

        public override string type_name () {
            return "ErrObject";
        }

        public void set_from (Error e) {
            number = Script.last_error_number != 0 ? Script.last_error_number : ((e is ScriptError.SYNTAX) ? 2434 : 5);
            description = e.message;
            Script.last_error_number = 0;
        }

        public void clear () {
            number = 0;
            description = "";
            source = "";
        }

        public override bool has_member (string name) {
            switch (name.down ()) {
                case "number":
                case "description":
                case "source":
                case "raise":
                case "clear": return true;
            }
            return false;
        }

        public override SValue get_default (SValue[] args) throws ScriptError {
            return new SValue.int (number);
        }

        public override SValue get_member (string name, SValue[] args) throws ScriptError {
            switch (name.down ()) {
                case "number": return new SValue.int (number);
                case "description": return new SValue.str (description);
                case "source": return new SValue.str (source);
                case "clear":
                    clear ();
                    return new SValue.empty ();
            }
            return base.get_member (name, args);
        }

        public override void set_member (string name, SValue[] args, SValue value) throws ScriptError {
            switch (name.down ()) {
                case "number": number = value.to_int (); return;
                case "description": description = value.to_text (); return;
                case "source": source = value.to_text (); return;
            }
            base.set_member (name, args, value);
        }

        public override SValue call_method (string name, SValue[] args, string[] names) throws ScriptError {
            if (name.down () == "raise") {
                int64 n = args.length > 0 ? args[0].to_int () : 5;
                string src = args.length > 1 && !(args[1] is MissingValue) ? args[1].to_text () : "";
                string desc = args.length > 2 && !(args[2] is MissingValue) ? args[2].to_text () : _("Application-defined or object-defined error");
                source = src;
                throw Script.fail ((int) n, desc);
            }
            if (name.down () == "clear") {
                clear ();
                return new SValue.empty ();
            }
            return get_member (name, args);
        }
    }

    public class TempVarsObject : ScriptObject {
        public OrderedMap<SValue> vars = new OrderedMap<SValue> ();
        public Gee.HashMap<string, string> display = new Gee.HashMap<string, string> ();

        public override string type_name () {
            return "TempVars";
        }

        public SValue get_var (string name) {
            var v = vars[name.down ()];
            return v ?? new SValue.null ();
        }

        public void set_var (string name, SValue value) {
            vars[name.down ()] = value;
            display[name.down ()] = name;
        }

        public override SValue get_default (SValue[] args) throws ScriptError {
            if (args.length == 0) throw Script.fail (450, _("TempVars needs a name."));
            if (args[0].kind == SKind.INT) {
                int k = 0;
                foreach (var e in vars.entries) {
                    if (k++ == args[0].i) return e.value;
                }
                throw Script.fail (9, _("Subscript out of range"));
            }
            return get_var (args[0].to_text ());
        }

        public override void set_default (SValue[] args, SValue value) throws ScriptError {
            if (args.length == 0) throw Script.fail (450, _("TempVars needs a name."));
            set_var (args[0].to_text (), value);
        }

        public override SValue bang (string name) throws ScriptError {
            return get_var (name);
        }

        public override void set_bang (string name, SValue value) throws ScriptError {
            set_var (name, value);
        }

        public override SValue get_member (string name, SValue[] args) throws ScriptError {
            switch (name.down ()) {
                case "count": return new SValue.int (vars.size);
                case "item": return get_default (args);
            }
            return base.get_member (name, args);
        }

        public override SValue call_method (string name, SValue[] args, string[] names) throws ScriptError {
            switch (name.down ()) {
                case "add":
                    if (args.length < 2) throw Script.fail (450, _("TempVars.Add needs a name and a value."));
                    set_var (args[0].to_text (), args[1].resolved ());
                    return new SValue.empty ();
                case "remove":
                    if (args.length > 0) {
                        vars.unset (args[0].to_text ().down ());
                        display.unset (args[0].to_text ().down ());
                    }
                    return new SValue.empty ();
                case "removeall":
                    vars.clear ();
                    display.clear ();
                    return new SValue.empty ();
            }
            return get_member (name, args);
        }
    }

    public class CollectionObject : ScriptObject {
        public Gee.ArrayList<SValue> list = new Gee.ArrayList<SValue> ();
        public Gee.ArrayList<string?> keys = new Gee.ArrayList<string?> ();

        public override string type_name () {
            return "Collection";
        }

        private int index_of (SValue key) throws ScriptError {
            if (key.kind == SKind.STRING) {
                for (int i = 0; i < keys.size; i++) {
                    if (keys[i] != null && keys[i].casefold () == key.s.casefold ()) return i;
                }
                throw Script.fail (5, _("The key \"%s\" is not in the collection.").printf (key.s));
            }
            int k = (int) key.to_int () - 1;
            if (k < 0 || k >= list.size) throw Script.fail (9, _("Subscript out of range"));
            return k;
        }

        public override SValue get_default (SValue[] args) throws ScriptError {
            if (args.length == 0) throw Script.fail (450, _("Collection needs an index."));
            return list[index_of (args[0])];
        }

        public override SValue get_member (string name, SValue[] args) throws ScriptError {
            switch (name.down ()) {
                case "count": return new SValue.int (list.size);
                case "item": return get_default (args);
            }
            return base.get_member (name, args);
        }

        public override SValue call_method (string name, SValue[] args, string[] names) throws ScriptError {
            switch (name.down ()) {
                case "add":
                    if (args.length == 0) throw Script.fail (450, _("Collection.Add needs an item."));
                    string? key = args.length > 1 && !(args[1] is MissingValue) ? args[1].to_text () : null;
                    if (key != null) {
                        foreach (var k in keys) {
                            if (k != null && k.casefold () == key.casefold ()) throw Script.fail (457, _("The key is already used."));
                        }
                    }
                    int at = list.size;
                    if (args.length > 2 && !(args[2] is MissingValue)) at = index_of (args[2]);
                    else if (args.length > 3 && !(args[3] is MissingValue)) at = index_of (args[3]) + 1;
                    list.insert (at, args[0]);
                    keys.insert (at, key);
                    return new SValue.empty ();
                case "remove":
                    int k = index_of (args[0]);
                    list.remove_at (k);
                    keys.remove_at (k);
                    return new SValue.empty ();
            }
            return get_member (name, args);
        }

        public override Gee.List<SValue>? items () {
            return list;
        }
    }

    public class DictionaryObject : ScriptObject {
        public Gee.ArrayList<string> keys = new Gee.ArrayList<string> ();
        public Gee.ArrayList<SValue> values = new Gee.ArrayList<SValue> ();
        public Gee.ArrayList<SValue> key_values = new Gee.ArrayList<SValue> ();
        public bool text_compare;

        public override string type_name () {
            return "Dictionary";
        }

        private int find (SValue key) {
            string k = key.to_text ();
            for (int i = 0; i < keys.size; i++) {
                if (text_compare ? keys[i].casefold () == k.casefold () : keys[i] == k) return i;
            }
            return -1;
        }

        public override SValue get_default (SValue[] args) throws ScriptError {
            if (args.length == 0) throw Script.fail (450, _("Dictionary needs a key."));
            int i = find (args[0]);
            if (i < 0) {
                keys.add (args[0].to_text ());
                key_values.add (args[0]);
                values.add (new SValue.empty ());
                return values[values.size - 1];
            }
            return values[i];
        }

        public override void set_default (SValue[] args, SValue value) throws ScriptError {
            if (args.length == 0) throw Script.fail (450, _("Dictionary needs a key."));
            int i = find (args[0]);
            if (i < 0) {
                keys.add (args[0].to_text ());
                key_values.add (args[0]);
                values.add (value);
            } else {
                values[i] = value;
            }
        }

        public override SValue get_member (string name, SValue[] args) throws ScriptError {
            switch (name.down ()) {
                case "count": return new SValue.int (keys.size);
                case "item": return get_default (args);
                case "keys": return new SValue.array (new SArray.from_list (key_values));
                case "items": return new SValue.array (new SArray.from_list (values));
                case "comparemode": return new SValue.int (text_compare ? 1 : 0);
            }
            return base.get_member (name, args);
        }

        public override void set_member (string name, SValue[] args, SValue value) throws ScriptError {
            if (name.down () == "item") {
                set_default (args, value);
                return;
            }
            if (name.down () == "comparemode") {
                text_compare = value.to_int () == 1;
                return;
            }
            base.set_member (name, args, value);
        }

        public override SValue call_method (string name, SValue[] args, string[] names) throws ScriptError {
            switch (name.down ()) {
                case "add":
                    if (args.length < 2) throw Script.fail (450, _("Dictionary.Add needs a key and an item."));
                    if (find (args[0]) >= 0) throw Script.fail (457, _("The key is already used."));
                    keys.add (args[0].to_text ());
                    key_values.add (args[0]);
                    values.add (args[1]);
                    return new SValue.empty ();
                case "exists":
                    return new SValue.bool (args.length > 0 && find (args[0]) >= 0);
                case "remove":
                    int i = args.length > 0 ? find (args[0]) : -1;
                    if (i < 0) throw Script.fail (32811, _("The key is not in the dictionary."));
                    keys.remove_at (i);
                    key_values.remove_at (i);
                    values.remove_at (i);
                    return new SValue.empty ();
                case "removeall":
                    keys.clear ();
                    key_values.clear ();
                    values.clear ();
                    return new SValue.empty ();
            }
            return get_member (name, args);
        }

        public override Gee.List<SValue>? items () {
            return key_values;
        }
    }

    public class DebugObject : ScriptObject {
        private weak ScriptRuntime rt;

        public DebugObject (ScriptRuntime rt) {
            this.rt = rt;
        }

        public override string type_name () {
            return "Debug";
        }

        public override SValue call_method (string name, SValue[] args, string[] names) throws ScriptError {
            switch (name.down ()) {
                case "print":
                    string text = args.length > 0 ? args[0].to_text () : "";
                    rt.output.append (text).append ("\n");
                    if (rt.host != null) rt.host.debug_print (text);
                    return new SValue.empty ();
                case "assert":
                    if (args.length > 0 && !ScriptRuntime.truth (args[0])) throw Script.fail (0, _("Debug.Assert failed."));
                    return new SValue.empty ();
            }
            return base.call_method (name, args, names);
        }
    }

    public class OpenObjects : ScriptObject {
        private weak ScriptRuntime rt;
        private string kind;

        public OpenObjects (ScriptRuntime rt, string kind) {
            this.rt = rt;
            this.kind = kind;
        }

        public override string type_name () {
            return kind == "form" ? "Forms" : "Reports";
        }

        private SValue find (string name) throws ScriptError {
            var o = rt.host != null ? rt.host.find_object (kind, name) : null;
            if (o == null) throw Script.fail (2450, kind == "form" ? _("The form \"%s\" is not open.").printf (name) : _("The report \"%s\" is not open.").printf (name));
            return new SValue.object (o);
        }

        public override SValue get_default (SValue[] args) throws ScriptError {
            if (args.length == 0) return new SValue.object (this);
            if (args[0].kind == SKind.INT || args[0].kind == SKind.DOUBLE) {
                string[] open = rt.host != null ? rt.host.open_objects (kind) : new string[0];
                int k = (int) args[0].to_int ();
                if (k < 0 || k >= open.length) throw Script.fail (2456, _("The number refers to an object that is not open."));
                return find (open[k]);
            }
            return find (args[0].to_text ());
        }

        public override SValue bang (string name) throws ScriptError {
            return find (name);
        }

        public override bool has_member (string name) {
            return name.down () == "count";
        }

        public override SValue get_member (string name, SValue[] args) throws ScriptError {
            if (name.down () == "count") return new SValue.int (rt.host != null ? rt.host.open_objects (kind).length : 0);
            if (name.down () == "item") return get_default (args);
            return find (name);
        }

        public override Gee.List<SValue>? items () {
            var list = new Gee.ArrayList<SValue> ();
            if (rt.host == null) return list;
            foreach (string n in rt.host.open_objects (kind)) {
                var o = rt.host.find_object (kind, n);
                if (o != null) list.add (new SValue.object (o));
            }
            return list;
        }
    }

    public class ApplicationObject : ScriptObject {
        private weak ScriptRuntime rt;

        public ApplicationObject (ScriptRuntime rt) {
            this.rt = rt;
        }

        public override string type_name () {
            return "Application";
        }

        public override SValue get_member (string name, SValue[] args) throws ScriptError {
            SValue b;
            switch (name.down ()) {
                case "name": return new SValue.str (_("Database"));
                case "version": return new SValue.str ("16.0");
                case "currentuser": return new SValue.str (Environment.get_user_name ());
                case "path":
                    return new SValue.str (rt.db != null && rt.db.path != ":memory:" ? Path.get_dirname (rt.db.path) : "");
                case "fullname":
                    return new SValue.str (rt.db != null ? rt.db.path : "");
                case "currentproject":
                case "screen":
                case "application":
                    return new SValue.object (this);
                case "activeform":
                    var f = rt.host != null ? rt.host.find_object ("active-form", "") : null;
                    if (f == null) throw Script.fail (2475, _("There is no active form."));
                    return new SValue.object (f);
                case "activecontrol":
                    var c = rt.host != null ? rt.host.find_object ("active-control", "") : null;
                    if (c == null) throw Script.fail (2474, _("There is no active control."));
                    return new SValue.object (c);
                case "activereport":
                    var r = rt.host != null ? rt.host.find_object ("active-report", "") : null;
                    if (r == null) throw Script.fail (2476, _("There is no active report."));
                    return new SValue.object (r);
            }
            if (rt.builtin_object (name.down (), out b)) {
                if (args.length > 0 && b.kind == SKind.OBJECT) return b.obj.get_default (args);
                return b;
            }
            return base.get_member (name, args);
        }

        public override SValue call_method (string name, SValue[] args, string[] names) throws ScriptError {
            switch (name.down ()) {
                case "run":
                    if (args.length == 0) throw Script.fail (450, _("Run needs a procedure name."));
                    SValue[] rest = {};
                    for (int i = 1; i < args.length; i++) rest += args[i];
                    return rt.call (args[0].to_text (), rest);
                case "quit":
                case "echo":
                case "setoption":
                case "refreshdatabasewindow":
                    if (rt.host != null) rt.host.run_command (name, args, names);
                    return new SValue.empty ();
                case "eval":
                    return rt.evaluate (args.length > 0 ? args[0].to_text () : "");
                case "dlookup":
                case "dcount":
                case "dsum":
                    return ScriptFunctions.domain (rt, name.down (), args[0].to_text (), args[1].to_text (), args.length > 2 ? args[2] : new SValue.empty ());
            }
            return get_member (name, args);
        }
    }

    public class DoCmdObject : ScriptObject {
        private weak ScriptRuntime rt;

        public DoCmdObject (ScriptRuntime rt) {
            this.rt = rt;
        }

        public override string type_name () {
            return "DoCmd";
        }

        public override SValue get_member (string name, SValue[] args) throws ScriptError {
            return call_method (name, args, new string[args.length]);
        }

        public override SValue call_method (string name, SValue[] args, string[] names) throws ScriptError {
            string n = name.down ();
            switch (n) {
                case "runsql":
                    if (args.length == 0) throw Script.fail (450, _("RunSQL needs a statement."));
                    if (rt.db == null) throw Script.fail (0, _("RunSQL needs a database."));
                    try {
                        AccessRun.execute (rt.db, args[0].to_text ());
                    } catch (Error e) {
                        throw Script.fail (3129, e.message);
                    }
                    if (rt.host != null) rt.host.run_command ("DataChanged", {}, {});
                    return new SValue.empty ();
                case "setwarnings":
                    rt.warnings = args.length > 0 && ScriptRuntime.truth (args[0]);
                    return new SValue.empty ();
                case "cancelevent":
                    rt.event_cancelled = true;
                    return new SValue.empty ();
                case "hourglass":
                case "echo":
                    return new SValue.empty ();
                case "runcode":
                    if (args.length == 0) throw Script.fail (450, _("RunCode needs a function."));
                    string fn = args[0].to_text ().strip ();
                    if (fn.has_prefix ("=")) fn = fn.substring (1);
                    if (!fn.contains ("(")) fn += "()";
                    return rt.evaluate (fn);
                case "runmacro":
                    if (args.length == 0) throw Script.fail (450, _("RunMacro needs a macro name."));
                    int repeat = args.length > 1 && !(args[1] is MissingValue) ? (int) args[1].to_int () : 1;
                    string? cond = args.length > 2 && !(args[2] is MissingValue) ? args[2].to_text () : null;
                    for (int i = 0; i < int.max (1, repeat); i++) {
                        if (cond != null && !ScriptRuntime.truth (rt.evaluate (cond))) break;
                        if (rt.macro_runner == null) throw Script.fail (2485, _("Macros cannot run here."));
                        rt.macro_runner (args[0].to_text ());
                    }
                    return new SValue.empty ();
            }
            if (rt.host == null) throw Script.fail (2046, _("The command \"%s\" is not available now.").printf (name));
            SValue[] resolved = {};
            foreach (var a in args) resolved += (a is MissingValue) ? a : a.resolved_or_self ();
            rt.host.run_command (name, resolved, names);
            return new SValue.empty ();
        }
    }
}
