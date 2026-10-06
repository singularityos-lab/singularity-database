namespace Singularity.Apps.Database {

    public class SVar {
        public SValue value;
        public bool is_const;

        public SVar (SValue v) {
            value = v;
        }
    }

    public interface ScriptHost : Object {
        public abstract int message_box (string prompt, int buttons, string title);
        public abstract string? input_box (string prompt, string title, string default_value);
        public abstract void run_command (string command, SValue[] args, string[] names) throws ScriptError;
        public abstract ScriptObject? find_object (string kind, string name);
        public abstract string[] open_objects (string kind);
        public abstract void debug_print (string text);
    }

    public interface AggregateProvider : Object {
        public abstract bool aggregate (string function, SExpr? argument, ScriptRuntime rt, SFrame frame, out SValue result) throws ScriptError;
    }

    public delegate void MacroHook (string name) throws ScriptError;

    public enum SSignal {
        NONE,
        EXIT_SUB,
        EXIT_FOR,
        EXIT_DO,
        GOTO,
        END
    }

    public class SFrame {
        public SModule? module;
        public SProcedure? proc;
        public Gee.HashMap<string, SVar> locals = new Gee.HashMap<string, SVar> ();
        public ScriptObject? me;
        public ScriptObject? context;
        public AggregateProvider? aggregates;
        public Gee.ArrayList<SValue> with_stack = new Gee.ArrayList<SValue> ();
        public string on_error = "none";
        public string error_label = "";
        public bool in_handler;
        public int resume_index = -1;
        public string goto_label = "";
        public bool strict;
    }

    public class ScriptRuntime : Object {
        public Database? db;
        public ScriptHost? host;
        public Gee.ArrayList<SModule> modules = new Gee.ArrayList<SModule> ();
        public Gee.HashMap<string, SVar> globals = new Gee.HashMap<string, SVar> ();
        public Gee.HashMap<SModule, Gee.HashMap<string, SVar>> module_vars = new Gee.HashMap<SModule, Gee.HashMap<string, SVar>> ();
        public ErrObject err = new ErrObject ();
        public TempVarsObject temp_vars = new TempVarsObject ();
        public bool warnings = true;
        public int64 steps;
        public int64 max_steps = 20000000;
        public int depth;
        public StringBuilder output = new StringBuilder ();
        public Gee.HashMap<string, SVar> statics = new Gee.HashMap<string, SVar> ();
        public bool event_cancelled;
        public MacroHook? macro_runner;

        public ScriptRuntime (Database? db, ScriptHost? host = null) {
            this.db = db;
            this.host = host;
        }

        public SModule load_module (string source, string name) throws ScriptError {
            var m = ScriptParser.parse_module (source, name);
            add_module (m);
            return m;
        }

        public void add_module (SModule m) throws ScriptError {
            for (int i = 0; i < modules.size; i++) {
                if (modules[i].name != "" && modules[i].name.ascii_casecmp (m.name) == 0) {
                    module_vars.unset (modules[i]);
                    modules.remove_at (i);
                    break;
                }
            }
            modules.add (m);
            var vars = new Gee.HashMap<string, SVar> ();
            module_vars[m] = vars;
            var frame = new SFrame ();
            frame.module = m;
            foreach (var d in m.declarations) {
                var dim = (SDim) d;
                for (int i = 0; i < dim.vars.size; i++) {
                    var v = dim.vars[i];
                    var value = dim.values[i] != null ? eval (dim.values[i], frame) : initial (v, frame);
                    var sv = new SVar (value);
                    sv.is_const = dim.is_const;
                    string key = v.name.down ();
                    if (m.private_names.contains (key) && !dim.is_const) vars[key] = sv;
                    else if (m.private_names.contains (key)) vars[key] = sv;
                    else globals[key] = sv;
                }
            }
        }

        public void remove_module (string name) {
            for (int i = 0; i < modules.size; i++) {
                if (modules[i].name.ascii_casecmp (name) == 0) {
                    module_vars.unset (modules[i]);
                    modules.remove_at (i);
                    return;
                }
            }
        }

        public SModule? find_module (string name) {
            foreach (var m in modules) {
                if (m.name.ascii_casecmp (name) == 0) return m;
            }
            return null;
        }

        public SProcedure? find_procedure (string name, SModule? prefer = null) {
            if (prefer != null) {
                var p = prefer.find (name);
                if (p != null) return p;
            }
            int dot = name.index_of (".");
            if (dot > 0) {
                var m = find_module (name.substring (0, dot));
                if (m != null) return m.find (name.substring (dot + 1));
            }
            foreach (var m in modules) {
                if (m.name.has_prefix ("Form_") || m.name.has_prefix ("Report_")) continue;
                var p = m.find (name);
                if (p != null && p.is_public) return p;
            }
            return null;
        }

        public SValue call (string name, SValue[] args, ScriptObject? me = null, SModule? prefer = null) throws ScriptError {
            var p = find_procedure (name, prefer);
            if (p == null) throw Script.fail (35, _("The procedure \"%s\" does not exist.").printf (name));
            var vars = new SVar[args.length];
            for (int i = 0; i < args.length; i++) vars[i] = new SVar (args[i]);
            steps = 0;
            return invoke (p, vars, new string[args.length], me);
        }

        public SValue call_with_refs (SProcedure p, SVar[] args, ScriptObject? me) throws ScriptError {
            return invoke (p, args, new string[args.length], me);
        }

        public SValue evaluate (string expression, ScriptObject? context = null, ScriptObject? me = null, AggregateProvider? aggregates = null) throws ScriptError {
            var e = ScriptParser.parse_expression (expression);
            return eval_with (e, context, me, aggregates);
        }

        public SValue eval_with (SExpr e, ScriptObject? context, ScriptObject? me = null, AggregateProvider? aggregates = null) throws ScriptError {
            var f = new SFrame ();
            f.context = context;
            f.me = me;
            f.aggregates = aggregates;
            f.strict = true;
            if (me != null) f.module = module_for (me);
            steps = 0;
            return eval (e, f);
        }

        public void assign_expression (SExpr target, SValue value, ScriptObject? context) throws ScriptError {
            var f = new SFrame ();
            f.context = context;
            f.me = context;
            assign (target, value, f, value.kind == SKind.OBJECT);
        }

        public void run_statements (string source, ScriptObject? me = null) throws ScriptError {
            var body = ScriptParser.parse_statements (source);
            var f = new SFrame ();
            f.me = me;
            if (me != null) f.module = module_for (me);
            steps = 0;
            run_body (body, f);
        }

        public SModule? module_for (ScriptObject me) {
            string n = me.type_name ();
            return find_module (n);
        }

        private SValue initial (SDimVar v, SFrame f) throws ScriptError {
            if (v.is_array) {
                if (v.bounds.size == 0) return new SValue.array (new SArray (0, -1));
                int lo = (int) eval (v.lower[0], f).to_int ();
                int hi = (int) eval (v.bounds[0], f).to_int ();
                var arr = new SArray (lo, hi);
                if (v.bounds.size > 1) {
                    int total = hi - lo + 1;
                    int[] dims = { total };
                    for (int k = 1; k < v.bounds.size; k++) {
                        int lk = (int) eval (v.lower[k], f).to_int ();
                        int hk = (int) eval (v.bounds[k], f).to_int ();
                        dims += hk - lk + 1;
                        total *= hk - lk + 1;
                    }
                    arr.items.clear ();
                    for (int k = 0; k < total; k++) arr.items.add (new SValue.empty ());
                    arr.dims = dims;
                }
                return new SValue.array (arr);
            }
            if (v.is_new) return create_object (v.type_name);
            string t = v.type_name.down ();
            switch (t) {
                case "integer":
                case "long":
                case "byte":
                case "longlong":
                case "longptr": return new SValue.int (0);
                case "double":
                case "single":
                case "currency":
                case "decimal": return new SValue.dbl (0);
                case "string": return new SValue.str ("");
                case "boolean": return new SValue.bool (false);
                case "date": return new SValue.date (0);
                case "variant":
                case "": return new SValue.empty ();
                default: return new SValue.nothing ();
            }
        }

        public SValue create_object (string type_name) throws ScriptError {
            string t = type_name.down ();
            if (t.has_suffix ("collection")) return new SValue.object (new CollectionObject ());
            if (t.has_suffix ("dictionary")) return new SValue.object (new DictionaryObject ());
            throw Script.fail (429, _("The object type \"%s\" is not available.").printf (type_name));
        }

        private void tick () throws ScriptError {
            steps++;
            if (steps > max_steps) throw Script.fail (28, _("The code ran for too long and was stopped."));
        }

        private SValue invoke (SProcedure p, SVar[] args, string[] names, ScriptObject? me) throws ScriptError {
            depth++;
            if (depth > 200) {
                depth--;
                throw Script.fail (28, _("Out of stack space"));
            }
            try {
                var f = new SFrame ();
                f.module = p.module;
                f.proc = p;
                f.me = me;
                var positional = new Gee.ArrayList<SVar?> ();
                var named = new Gee.HashMap<string, SVar> ();
                for (int i = 0; i < args.length; i++) {
                    if (i < names.length && names[i] != null && names[i] != "") named[names[i].down ()] = args[i];
                    else positional.add (args[i]);
                }
                for (int i = 0; i < p.params.size; i++) {
                    var prm = p.params[i];
                    string key = prm.name.down ();
                    if (prm.param_array) {
                        var list = new Gee.ArrayList<SValue> ();
                        for (int k = i; k < positional.size; k++) {
                            if (positional[k] != null) list.add (positional[k].value);
                        }
                        f.locals[key] = new SVar (new SValue.array (new SArray.from_list (list)));
                        break;
                    }
                    SVar? given = named.has_key (key) ? named[key] : (i < positional.size ? positional[i] : null);
                    if (given == null || (given.value.kind == SKind.EMPTY && given is MissingVar)) {
                        if (!prm.optional) throw Script.fail (449, _("Argument \"%s\" of %s is not optional.").printf (prm.name, p.name));
                        var mv = new MissingVar (prm.default_value != null ? eval (prm.default_value, f) : new SValue.empty ());
                        mv.missing = prm.default_value == null;
                        f.locals[key] = mv;
                        continue;
                    }
                    f.locals[key] = prm.by_val ? new SVar (given.value.copy ()) : given;
                }
                if (p.kind == "function" || p.kind == "get") f.locals[p.name.down ()] = new SVar (new SValue.empty ());
                run_body (p.body, f);
                if (p.kind == "function" || p.kind == "get") return f.locals[p.name.down ()].value;
                return new SValue.empty ();
            } finally {
                depth--;
            }
        }

        public void run_body (Gee.ArrayList<SStmt> body, SFrame f) throws ScriptError {
            var labels = new Gee.HashMap<string, int> ();
            for (int i = 0; i < body.size; i++) {
                var l = body[i] as SLabel;
                if (l != null) labels[l.name.down ()] = i;
            }
            int i = 0;
            while (i < body.size) {
                SSignal sig;
                try {
                    sig = exec (body[i], f);
                } catch (ScriptError e) {
                    if (e is ScriptError.CANCELLED) throw e;
                    if (f.on_error == "goto" && !f.in_handler && labels.has_key (f.error_label.down ())) {
                        err.set_from (e);
                        f.resume_index = i;
                        f.in_handler = true;
                        i = labels[f.error_label.down ()];
                        continue;
                    }
                    throw e;
                }
                if (sig == SSignal.GOTO) {
                    string target = f.goto_label.down ();
                    if (target.has_prefix ("\x01")) {
                        int idx = int.parse (target.substring (1));
                        f.in_handler = false;
                        i = idx;
                        continue;
                    }
                    if (!labels.has_key (target)) throw Script.fail (0, _("The label \"%s\" does not exist.").printf (f.goto_label));
                    if (f.in_handler && f.goto_label != "") f.in_handler = false;
                    i = labels[target];
                    continue;
                }
                if (sig == SSignal.EXIT_SUB) return;
                if (sig == SSignal.END) throw new ScriptError.CANCELLED ("end");
                i++;
            }
        }

        private SSignal exec_block (Gee.ArrayList<SStmt> body, SFrame f) throws ScriptError {
            foreach (var s in body) {
                SSignal sig;
                try {
                    sig = exec (s, f);
                } catch (ScriptError e) {
                    if (e is ScriptError.CANCELLED) throw e;
                    if (f.on_error == "resume-next") {
                        err.set_from (e);
                        continue;
                    }
                    throw e;
                }
                if (sig != SSignal.NONE) return sig;
            }
            return SSignal.NONE;
        }

        private SSignal exec (SStmt s, SFrame f) throws ScriptError {
            tick ();
            if (f.on_error == "resume-next" && !(s is SIf || s is SFor || s is SForEach || s is SDo || s is SSelect || s is SWith)) {
                try {
                    return exec_inner (s, f);
                } catch (ScriptError e) {
                    if (e is ScriptError.CANCELLED) throw e;
                    err.set_from (e);
                    return SSignal.NONE;
                }
            }
            return exec_inner (s, f);
        }

        private SSignal exec_inner (SStmt s, SFrame f) throws ScriptError {
            if (s is SAssign) {
                var a = (SAssign) s;
                var v = eval (a.value, f);
                if (!a.is_set && v.kind == SKind.OBJECT) v = v.obj.get_default ({});
                assign (a.target, v, f, a.is_set);
                return SSignal.NONE;
            }
            if (s is SExprStmt) {
                var e = ((SExprStmt) s).expr;
                var call = e as SCall;
                if (call != null) eval_call (call, f, true);
                else eval (e, f);
                return SSignal.NONE;
            }
            if (s is SIf) {
                foreach (var br in ((SIf) s).branches) {
                    if (br.condition == null || truth (eval (br.condition, f))) return exec_block (br.body, f);
                }
                return SSignal.NONE;
            }
            if (s is SSelect) return exec_select ((SSelect) s, f);
            if (s is SFor) return exec_for ((SFor) s, f);
            if (s is SForEach) return exec_foreach ((SForEach) s, f);
            if (s is SDo) return exec_do ((SDo) s, f);
            if (s is SExit) {
                switch (((SExit) s).what) {
                    case "sub":
                    case "function":
                    case "property": return SSignal.EXIT_SUB;
                    case "for": return SSignal.EXIT_FOR;
                    case "do": return SSignal.EXIT_DO;
                    default: return SSignal.END;
                }
            }
            if (s is SDim) {
                exec_dim ((SDim) s, f);
                return SSignal.NONE;
            }
            if (s is SWith) {
                var w = (SWith) s;
                f.with_stack.add (eval (w.target, f));
                try {
                    return exec_block (w.body, f);
                } finally {
                    f.with_stack.remove_at (f.with_stack.size - 1);
                }
            }
            if (s is SOnError) {
                var o = (SOnError) s;
                f.on_error = o.mode;
                f.error_label = o.label;
                if (o.mode == "none") err.clear ();
                return SSignal.NONE;
            }
            if (s is SResume) {
                var r = (SResume) s;
                err.clear ();
                if (r.mode == "next") {
                    f.goto_label = "\x01%d".printf (f.resume_index + 1);
                } else if (r.mode == "retry") {
                    f.goto_label = "\x01%d".printf (f.resume_index);
                } else {
                    f.goto_label = r.label;
                    f.in_handler = false;
                }
                return SSignal.GOTO;
            }
            if (s is SGoTo) {
                f.goto_label = ((SGoTo) s).label;
                return SSignal.GOTO;
            }
            if (s is SLabel) return SSignal.NONE;
            return SSignal.NONE;
        }

        private void exec_dim (SDim d, SFrame f) throws ScriptError {
            for (int i = 0; i < d.vars.size; i++) {
                var v = d.vars[i];
                string key = v.name.down ();
                if (d.redim) {
                    SVar? existing = lookup_var (key, f);
                    int hi = (int) eval (v.bounds[v.bounds.size - 1], f).to_int ();
                    int lo = (int) eval (v.lower[v.lower.size - 1], f).to_int ();
                    if (existing != null && existing.value.kind == SKind.ARRAY && d.preserve) {
                        existing.value.arr.resize (hi, true);
                    } else if (v.bounds.size > 1) {
                        var fresh = initial (v, f);
                        if (existing != null) existing.value = fresh;
                        else f.locals[key] = new SVar (fresh);
                    } else {
                        var arr = new SArray (lo, hi);
                        if (existing != null) existing.value = new SValue.array (arr);
                        else f.locals[key] = new SVar (new SValue.array (arr));
                    }
                    continue;
                }
                if (d.is_static && f.proc != null) {
                    string sk = "%s.%s.%s".printf (f.module != null ? f.module.name : "", f.proc.name, key);
                    if (!statics.has_key (sk)) statics[sk] = new SVar (d.values[i] != null ? eval (d.values[i], f) : initial (v, f));
                    f.locals[key] = statics[sk];
                    continue;
                }
                var value = d.values[i] != null ? eval (d.values[i], f) : initial (v, f);
                var sv = new SVar (value);
                sv.is_const = d.is_const;
                f.locals[key] = sv;
            }
        }

        private SSignal exec_select (SSelect s, SFrame f) throws ScriptError {
            var subject = eval (s.subject, f).resolved ();
            foreach (var c in s.cases) {
                bool hit = c.is_else;
                foreach (var t in c.tests) {
                    if (hit) break;
                    if (t.kind == "range") {
                        hit = compare (subject, eval (t.a, f)) >= 0 && compare (subject, eval (t.b, f)) <= 0;
                    } else if (t.kind == "is") {
                        hit = truth (binary (t.op, subject, eval (t.a, f)));
                    } else {
                        var r = binary ("=", subject, eval (t.a, f));
                        hit = r.kind == SKind.BOOL && r.b;
                    }
                }
                if (hit) return exec_block (c.body, f);
            }
            return SSignal.NONE;
        }

        private SSignal exec_for (SFor s, SFrame f) throws ScriptError {
            var from = eval (s.from, f);
            var to = eval (s.to, f);
            var step = s.step != null ? eval (s.step, f) : new SValue.int (1);
            bool ints = from.kind == SKind.INT && to.kind == SKind.INT && step.kind == SKind.INT;
            double st = step.to_double ();
            double end = to.to_double ();
            assign (s.variable, from, f, false);
            while (true) {
                tick ();
                double cur = eval (s.variable, f).to_double ();
                if (st >= 0 ? cur > end : cur < end) break;
                var sig = exec_block (s.body, f);
                if (sig == SSignal.EXIT_FOR) break;
                if (sig != SSignal.NONE) return sig;
                double nv = eval (s.variable, f).to_double () + st;
                assign (s.variable, ints ? new SValue.int ((int64) nv) : new SValue.dbl (nv), f, false);
            }
            return SSignal.NONE;
        }

        private SSignal exec_foreach (SForEach s, SFrame f) throws ScriptError {
            var coll = eval (s.collection, f);
            Gee.List<SValue>? items = null;
            if (coll.kind == SKind.ARRAY) items = coll.arr.items;
            else if (coll.kind == SKind.OBJECT) items = coll.obj.items ();
            if (items == null) throw Script.fail (451, _("The value cannot be used in For Each."));
            var snapshot = new Gee.ArrayList<SValue> ();
            snapshot.add_all (items);
            foreach (var item in snapshot) {
                assign (s.variable, item, f, true);
                var sig = exec_block (s.body, f);
                if (sig == SSignal.EXIT_FOR) break;
                if (sig != SSignal.NONE) return sig;
            }
            return SSignal.NONE;
        }

        private SSignal exec_do (SDo s, SFrame f) throws ScriptError {
            while (true) {
                tick ();
                if (s.pre != null) {
                    bool c = truth (eval (s.pre, f));
                    if (s.pre_until ? c : !c) break;
                }
                var sig = exec_block (s.body, f);
                if (sig == SSignal.EXIT_DO) break;
                if (sig != SSignal.NONE) return sig;
                if (s.post != null) {
                    bool c = truth (eval (s.post, f));
                    if (s.post_until ? c : !c) break;
                }
            }
            return SSignal.NONE;
        }

        public static bool truth (SValue v) throws ScriptError {
            var r = v.resolved ();
            if (r.kind == SKind.NULL) return false;
            return r.to_bool ();
        }

        private SVar? lookup_var (string key, SFrame f) {
            if (f.locals.has_key (key)) return f.locals[key];
            if (f.module != null && module_vars.has_key (f.module)) {
                var mv = module_vars[f.module];
                if (mv.has_key (key)) return mv[key];
            }
            if (globals.has_key (key)) return globals[key];
            return null;
        }

        private void assign (SExpr target, SValue value, SFrame f, bool is_set) throws ScriptError {
            if (target is SName) {
                string name = ((SName) target).name;
                string key = name.down ();
                var v = lookup_var (key, f);
                if (v != null) {
                    if (v.is_const) throw Script.fail (0, _("\"%s\" is a constant and cannot be changed.").printf (name));
                    v.value = value;
                    return;
                }
                if (f.me != null && f.me.has_member (name)) {
                    var cur = f.me.get_member (name, {});
                    if (!is_set && cur.kind == SKind.OBJECT) cur.obj.set_default ({}, value);
                    else f.me.set_member (name, {}, value);
                    return;
                }
                if (f.context != null && f.context.has_member (name)) {
                    f.context.set_member (name, {}, value);
                    return;
                }
                if (name.ascii_casecmp ("TempVars") == 0) throw Script.fail (0, _("TempVars cannot be replaced."));
                f.locals[key] = new SVar (value);
                return;
            }
            if (target is SMember) {
                var m = (SMember) target;
                var obj = m.target != null ? eval (m.target, f) : with_object (f);
                if (obj.kind != SKind.OBJECT) throw Script.fail (424, _("Object required"));
                if (m.bang) {
                    obj.obj.set_bang (m.name, value);
                    return;
                }
                if (!is_set) {
                    SValue cur;
                    bool obj_member = false;
                    try {
                        cur = obj.obj.get_member (m.name, {});
                        obj_member = cur.kind == SKind.OBJECT;
                    } catch (ScriptError e) {
                        cur = new SValue.empty ();
                    }
                    if (obj_member) {
                        cur.obj.set_default ({}, value);
                        return;
                    }
                }
                obj.obj.set_member (m.name, {}, value);
                return;
            }
            if (target is SCall) {
                var c = (SCall) target;
                SValue[] args = eval_args (c, f);
                if (c.target is SName) {
                    string key = ((SName) c.target).name.down ();
                    var v = lookup_var (key, f);
                    if (v != null && v.value.kind == SKind.ARRAY) {
                        v.value.arr.set_at (array_index (v.value.arr, args), value);
                        return;
                    }
                    if (v != null && v.value.kind == SKind.OBJECT) {
                        v.value.obj.set_default (args, value);
                        return;
                    }
                }
                if (c.target is SMember) {
                    var m = (SMember) c.target;
                    var obj = m.target != null ? eval (m.target, f) : with_object (f);
                    if (obj.kind != SKind.OBJECT) throw Script.fail (424, _("Object required"));
                    obj.obj.set_member (m.name, args, value);
                    return;
                }
                var t = eval (c.target, f);
                if (t.kind == SKind.OBJECT) {
                    t.obj.set_default (args, value);
                    return;
                }
                if (t.kind == SKind.ARRAY) {
                    t.arr.set_at (array_index (t.arr, args), value);
                    return;
                }
            }
            throw Script.fail (0, _("This expression cannot be assigned."));
        }

        private int array_index (SArray arr, SValue[] args) throws ScriptError {
            if (args.length == 1) return (int) args[0].to_int ();
            int idx = 0;
            int mult = 1;
            for (int k = args.length - 1; k >= 0; k--) {
                int d = k < arr.dims.length ? arr.dims[k] : 1;
                int a = (int) args[k].to_int () - arr.lower;
                if (a < 0 || a >= d) throw Script.fail (9, _("Subscript out of range"));
                idx += a * mult;
                mult *= d;
            }
            return idx + arr.lower;
        }

        private SValue with_object (SFrame f) throws ScriptError {
            if (f.with_stack.size == 0) throw Script.fail (0, _("A member starting with \".\" needs a With block."));
            return f.with_stack[f.with_stack.size - 1];
        }

        public SValue eval (SExpr e, SFrame f) throws ScriptError {
            if (e is SLiteral) return ((SLiteral) e).value;
            if (e is SParen) {
                var v = eval (((SParen) e).inner, f);
                return v.kind == SKind.OBJECT ? v.obj.get_default ({}) : v;
            }
            if (e is SName) return eval_name (((SName) e).name, f);
            if (e is SBinary) {
                var b = (SBinary) e;
                if (b.op == "and" || b.op == "or") {
                    var l = eval (b.left, f).resolved ();
                    var r = eval (b.right, f).resolved ();
                    return logic (b.op, l, r);
                }
                return binary (b.op, eval (b.left, f).resolved (), eval (b.right, f).resolved ());
            }
            if (e is SUnary) {
                var u = (SUnary) e;
                var v = eval (u.operand, f).resolved ();
                if (u.op == "neg") {
                    if (v.is_null) return v;
                    if (v.kind == SKind.INT) return new SValue.int (-v.i);
                    if (v.kind == SKind.BOOL) return new SValue.int (v.b ? 1 : 0);
                    return new SValue.dbl (-v.to_double ());
                }
                if (v.is_null) return v;
                if (v.kind == SKind.INT) return new SValue.int (~v.i);
                return new SValue.bool (!v.to_bool ());
            }
            if (e is SMember) {
                var m = (SMember) e;
                var obj = m.target != null ? eval (m.target, f) : with_object (f);
                if (obj.kind == SKind.NOTHING) throw Script.fail (91, _("Object variable not set"));
                if (obj.kind != SKind.OBJECT) throw Script.fail (424, _("Object required"));
                if (m.bang) return obj.obj.bang (m.name);
                return obj.obj.get_member (m.name, {});
            }
            if (e is SCall) return eval_call ((SCall) e, f, false);
            if (e is SNew) return create_object (((SNew) e).class_name);
            if (e is STypeOf) {
                var t = (STypeOf) e;
                var v = eval (t.operand, f);
                return new SValue.bool (v.kind == SKind.OBJECT && v.obj.type_name ().ascii_casecmp (t.type_name) == 0);
            }
            throw Script.fail (0, _("Unknown expression."));
        }

        private SValue eval_name (string name, SFrame f) throws ScriptError {
            string key = name.down ();
            var v = lookup_var (key, f);
            if (v != null) return v.value;
            SValue c;
            if (ScriptConstants.lookup (key, out c)) return c;
            if (key == "me") {
                if (f.me == null) throw Script.fail (0, _("\"Me\" can be used only in form and report code."));
                return new SValue.object (f.me);
            }
            if (f.me != null && f.me.has_member (name)) return f.me.get_member (name, {});
            if (f.context != null && f.context.has_member (name)) return f.context.get_member (name, {});
            SValue b;
            if (builtin_object (key, out b)) return b;
            var p = find_procedure (name, f.module);
            if (p != null) return invoke (p, {}, {}, f.me);
            if (f.aggregates != null) {
                SValue r;
                if (f.aggregates.aggregate (name, null, this, f, out r)) return r;
            }
            SValue fr;
            if (ScriptFunctions.call (this, f, name, new Gee.ArrayList<SArg> (), {}, out fr)) return fr;
            if (f.strict) throw Script.fail (2465, _("The name \"%s\" is not known.").printf (name));
            return new SValue.empty ();
        }

        public bool builtin_object (string key, out SValue result) {
            result = new SValue.empty ();
            switch (key) {
                case "docmd":
                    result = new SValue.object (new DoCmdObject (this));
                    return true;
                case "currentdb":
                case "codedb":
                    if (db == null) return false;
                    result = new SValue.object (new DaoDatabase (this));
                    return true;
                case "forms":
                    result = new SValue.object (new OpenObjects (this, "form"));
                    return true;
                case "reports":
                    result = new SValue.object (new OpenObjects (this, "report"));
                    return true;
                case "err":
                    result = new SValue.object (err);
                    return true;
                case "debug":
                    result = new SValue.object (new DebugObject (this));
                    return true;
                case "tempvars":
                    result = new SValue.object (temp_vars);
                    return true;
                case "application":
                case "screen":
                case "currentproject":
                    result = new SValue.object (new ApplicationObject (this));
                    return true;
                default:
                    return false;
            }
        }

        private SValue[] eval_args (SCall c, SFrame f) throws ScriptError {
            SValue[] args = new SValue[c.args.size];
            for (int i = 0; i < c.args.size; i++) {
                var a = c.args[i];
                args[i] = a.value != null ? eval (a.value, f) : new MissingValue ();
            }
            return args;
        }

        private string[] arg_names (SCall c) {
            string[] names = new string[c.args.size];
            for (int i = 0; i < c.args.size; i++) names[i] = c.args[i].name ?? "";
            return names;
        }

        private SValue eval_call (SCall c, SFrame f, bool statement) throws ScriptError {
            if (c.target is SName) {
                string name = ((SName) c.target).name;
                string key = name.down ();
                var v = lookup_var (key, f);
                if (v != null && f.proc != null && c.args.size > 0 && key == f.proc.name.down () && v.value.kind != SKind.ARRAY) v = null;
                if (v != null) {
                    var args = eval_args (c, f);
                    if (v.value.kind == SKind.ARRAY) return v.value.arr.get_at (array_index (v.value.arr, args));
                    if (v.value.kind == SKind.OBJECT) return v.value.obj.get_default (args);
                    if (args.length == 0) return v.value;
                    throw Script.fail (13, _("\"%s\" is not an array or a function.").printf (name));
                }
                if (f.me != null && f.me.has_member (name)) {
                    var args = eval_args (c, f);
                    var m = f.me.get_member (name, {});
                    if (args.length == 0) return m;
                    if (m.kind == SKind.OBJECT) return m.obj.get_default (args);
                }
                if (f.aggregates != null && c.args.size <= 1) {
                    SValue r;
                    if (f.aggregates.aggregate (name, c.args.size == 1 ? c.args[0].value : null, this, f, out r)) return r;
                }
                var p = find_procedure (name, f.module);
                if (p != null) {
                    SVar[] refs = new SVar[c.args.size];
                    for (int i = 0; i < c.args.size; i++) {
                        var a = c.args[i];
                        if (a.value == null) {
                            refs[i] = new MissingVar (new SValue.empty ());
                            continue;
                        }
                        if (a.value is SName) {
                            var existing = lookup_var (((SName) a.value).name.down (), f);
                            if (existing != null) {
                                refs[i] = existing;
                                continue;
                            }
                        }
                        refs[i] = new SVar (eval (a.value, f));
                    }
                    return invoke (p, refs, arg_names (c), f.me);
                }
                SValue b;
                if (builtin_object (key, out b)) {
                    var args = eval_args (c, f);
                    if (args.length == 0) return b;
                    return b.obj.get_default (args);
                }
                if (f.context != null && f.context.has_member (name)) {
                    var m = f.context.get_member (name, {});
                    var args = eval_args (c, f);
                    if (args.length == 0) return m;
                    if (m.kind == SKind.OBJECT) return m.obj.get_default (args);
                }
                SValue result;
                if (ScriptFunctions.call (this, f, name, c.args, eval_args (c, f), out result)) return result;
                throw Script.fail (35, _("The function \"%s\" does not exist.").printf (name));
            }
            if (c.target is SMember) {
                var m = (SMember) c.target;
                var obj = m.target != null ? eval (m.target, f) : with_object (f);
                if (obj.kind == SKind.NOTHING) throw Script.fail (91, _("Object variable not set"));
                if (obj.kind != SKind.OBJECT) throw Script.fail (424, _("Object required"));
                var args = eval_args (c, f);
                if (m.bang) {
                    var bv = obj.obj.bang (m.name);
                    if (bv.kind == SKind.OBJECT) return bv.obj.get_default (args);
                    return bv;
                }
                return obj.obj.call_method (m.name, args, arg_names (c));
            }
            var t = eval (c.target, f);
            var args = eval_args (c, f);
            if (t.kind == SKind.OBJECT) return t.obj.get_default (args);
            if (t.kind == SKind.ARRAY) return t.arr.get_at (array_index (t.arr, args));
            throw Script.fail (13, _("Type mismatch"));
        }

        public SValue logic (string op, SValue l, SValue r) throws ScriptError {
            if (l.kind == SKind.INT && r.kind == SKind.INT) return new SValue.int (op == "and" ? l.i & r.i : l.i | r.i);
            if (op == "and") {
                if (l.is_null || r.is_null) {
                    if ((!l.is_null && !l.to_bool ()) || (!r.is_null && !r.to_bool ())) return new SValue.bool (false);
                    return new SValue.null ();
                }
                return new SValue.bool (l.to_bool () && r.to_bool ());
            }
            if (l.is_null || r.is_null) {
                if ((!l.is_null && l.to_bool ()) || (!r.is_null && r.to_bool ())) return new SValue.bool (true);
                return new SValue.null ();
            }
            return new SValue.bool (l.to_bool () || r.to_bool ());
        }

        public static int compare (SValue a0, SValue b0) throws ScriptError {
            var a = a0.resolved ();
            var b = b0.resolved ();
            if (a.kind == SKind.STRING && b.kind == SKind.STRING) return a.s.casefold ().collate (b.s.casefold ());
            if (a.kind == SKind.EMPTY && b.kind == SKind.STRING) return "".collate (b.s.casefold ());
            if (b.kind == SKind.EMPTY && a.kind == SKind.STRING) return a.s.casefold ().collate ("");
            if (a.kind == SKind.STRING && !a.looks_numeric () && b.kind != SKind.DATE) return a.s.casefold ().collate (b.to_str ().casefold ());
            if (b.kind == SKind.STRING && !b.looks_numeric () && a.kind != SKind.DATE) return a.to_str ().casefold ().collate (b.s.casefold ());
            double x = a.kind == SKind.DATE || b.kind == SKind.DATE ? a.to_date () : a.to_double ();
            double y = a.kind == SKind.DATE || b.kind == SKind.DATE ? b.to_date () : b.to_double ();
            return x < y ? -1 : (x > y ? 1 : 0);
        }

        public SValue binary (string op, SValue l, SValue r) throws ScriptError {
            switch (op) {
                case "&":
                    if (l.is_null && r.is_null) return new SValue.null ();
                    return new SValue.str (l.to_text () + r.to_text ());
                case "=":
                case "<>":
                case "<":
                case ">":
                case "<=":
                case ">=":
                    if (l.is_null || r.is_null) return new SValue.null ();
                    int c = compare (l, r);
                    switch (op) {
                        case "=": return new SValue.bool (c == 0);
                        case "<>": return new SValue.bool (c != 0);
                        case "<": return new SValue.bool (c < 0);
                        case ">": return new SValue.bool (c > 0);
                        case "<=": return new SValue.bool (c <= 0);
                        default: return new SValue.bool (c >= 0);
                    }
                case "like":
                    if (l.is_null || r.is_null) return new SValue.null ();
                    return new SValue.bool (ScriptFunctions.like (l.to_str (), r.to_str ()));
                case "is":
                    if (l.kind == SKind.NOTHING || r.kind == SKind.NOTHING) return new SValue.bool (l.kind == r.kind);
                    return new SValue.bool (l.kind == SKind.OBJECT && r.kind == SKind.OBJECT && l.obj == r.obj);
                case "xor":
                    if (l.is_null || r.is_null) return new SValue.null ();
                    if (l.kind == SKind.INT && r.kind == SKind.INT) return new SValue.int (l.i ^ r.i);
                    return new SValue.bool (l.to_bool () != r.to_bool ());
                case "eqv":
                    if (l.is_null || r.is_null) return new SValue.null ();
                    return new SValue.bool (l.to_bool () == r.to_bool ());
                case "imp":
                    if (l.is_null || r.is_null) return new SValue.null ();
                    return new SValue.bool (!l.to_bool () || r.to_bool ());
            }
            if (l.is_null || r.is_null) return new SValue.null ();
            if (op == "+" && l.kind == SKind.STRING && r.kind == SKind.STRING) return new SValue.str (l.s + r.s);
            if (op == "+" && ((l.kind == SKind.STRING && !l.looks_numeric () && r.kind != SKind.DATE) || (r.kind == SKind.STRING && !r.looks_numeric () && l.kind != SKind.DATE))) {
                if (l.kind == SKind.STRING && r.kind == SKind.STRING) return new SValue.str (l.s + r.s);
                throw Script.fail (13, _("Type mismatch"));
            }
            bool date_l = l.kind == SKind.DATE, date_r = r.kind == SKind.DATE;
            switch (op) {
                case "+":
                    if (date_l || date_r) return new SValue.date (l.to_double () + r.to_double ());
                    if (l.kind == SKind.INT && r.kind == SKind.INT) return int_or_double ((double) l.i + (double) r.i, l.i + r.i);
                    return new SValue.dbl (l.to_double () + r.to_double ());
                case "-":
                    if (date_l && !date_r) return new SValue.date (l.to_double () - r.to_double ());
                    if (l.kind == SKind.INT && r.kind == SKind.INT) return int_or_double ((double) l.i - (double) r.i, l.i - r.i);
                    return new SValue.dbl (l.to_double () - r.to_double ());
                case "*":
                    if (l.kind == SKind.INT && r.kind == SKind.INT) return int_or_double ((double) l.i * (double) r.i, l.i * r.i);
                    return new SValue.dbl (l.to_double () * r.to_double ());
                case "/":
                    double den = r.to_double ();
                    if (den == 0) throw Script.fail (11, _("Division by zero"));
                    return new SValue.dbl (l.to_double () / den);
                case "\\":
                    int64 dd = (int64) Script.bankers_round (r.to_double ());
                    if (dd == 0) throw Script.fail (11, _("Division by zero"));
                    return new SValue.int ((int64) Script.bankers_round (l.to_double ()) / dd);
                case "mod":
                    int64 md = (int64) Script.bankers_round (r.to_double ());
                    if (md == 0) throw Script.fail (11, _("Division by zero"));
                    return new SValue.int ((int64) Script.bankers_round (l.to_double ()) % md);
                case "^":
                    return new SValue.dbl (Math.pow (l.to_double (), r.to_double ()));
            }
            throw Script.fail (0, _("Unknown operator \"%s\".").printf (op));
        }

        private static SValue int_or_double (double exact, int64 wrapped) {
            if (Math.fabs (exact) < 9.0e18) return new SValue.int (wrapped);
            return new SValue.dbl (exact);
        }
    }

    public class MissingValue : SValue {
        public MissingValue () {
            base.empty ();
        }
    }

    public class MissingVar : SVar {
        public bool missing = true;

        public MissingVar (SValue v) {
            base (v);
        }
    }
}
