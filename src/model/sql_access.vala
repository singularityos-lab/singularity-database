namespace Singularity.Apps.Database {

    public class SqlFnEntry {
        public string name;
        public string script_name;

        public SqlFnEntry (string name, string script_name) {
            this.name = name;
            this.script_name = script_name;
        }
    }

    public class SqlAggState {
        public string kind;
        public SValue? first;
        public SValue? last;
        public bool seen;
        public int64 n;
        public double mean;
        public double m2;

        public SqlAggState (string kind) {
            this.kind = kind;
        }
    }

    public class AccessSqlFunctions {
        private static Gee.ArrayList<SqlFnEntry>? entries;
        private static Gee.HashMap<int64?, SqlAggState>? states;
        private static int64 next_state = 1;
        private static ScriptRuntime? scratch;

        private const string[] SCALARS = {
            "mid", "val", "str", "cstr", "cint", "clng", "cdbl", "csng", "ccur", "cdec", "cbool", "cdate", "cbyte",
            "int", "fix", "sgn", "sqr", "strconv", "strcomp", "space", "strreverse", "chr", "chrw", "asc", "ascw", "instrrev",
            "dateadd", "datediff", "datepart", "dateserial", "datevalue", "timeserial", "timevalue", "weekday", "weekdayname",
            "monthname", "minute", "second", "isnull", "isnumeric", "isdate", "choose", "switch", "formatnumber",
            "formatcurrency", "formatpercent", "formatdatetime", "hex", "oct", "exp", "log", "atn"
        };

        private static SValue from_sqlite (Sqlite.Value v) {
            switch (v.to_type ()) {
                case Sqlite.INTEGER: return new SValue.int (v.to_int64 ());
                case Sqlite.FLOAT: return new SValue.dbl (v.to_double ());
                case Sqlite.TEXT: return new SValue.str (v.to_text () ?? "");
                case Sqlite.NULL: return new SValue.null ();
                default: return new SValue.str (v.to_text () ?? "");
            }
        }

        private static void result (Sqlite.Context ctx, SValue r) {
            switch (r.kind) {
                case SKind.INT: ctx.result_int64 (r.i); break;
                case SKind.DOUBLE: ctx.result_double (r.d); break;
                case SKind.BOOL: ctx.result_int (r.b ? 1 : 0); break;
                case SKind.DATE: ctx.result_text (Script.serial_to_iso (r.d)); break;
                case SKind.STRING: ctx.result_text (r.s); break;
                default: ctx.result_null (); break;
            }
        }

        private static ScriptRuntime runtime () {
            if (scratch == null) scratch = new ScriptRuntime (null);
            return scratch;
        }

        private static void call_script (Sqlite.Context ctx, Sqlite.Value[] args, string name) {
            SValue[] vals = new SValue[args.length];
            for (int i = 0; i < args.length; i++) vals[i] = from_sqlite (args[i]);
            try {
                SValue r;
                if (!ScriptFunctions.call (runtime (), new SFrame (), name, new Gee.ArrayList<SArg> (), vals, out r)) {
                    ctx.result_error ("%s is not available".printf (name), Sqlite.ERROR);
                    return;
                }
                result (ctx, r);
            } catch (ScriptError e) {
                if (Script.last_error_number == 94) {
                    Script.last_error_number = 0;
                    ctx.result_null ();
                    return;
                }
                Script.last_error_number = 0;
                ctx.result_error (e.message, Sqlite.ERROR);
            }
        }

        private static void scalar (Sqlite.Context ctx, Sqlite.Value[] args) {
            unowned SqlFnEntry e = ctx.user_data<SqlFnEntry> ();
            call_script (ctx, args, e.script_name);
        }

        private static SqlAggState state (Sqlite.Context ctx, string kind) {
            int64* slot = (int64*) ctx.aggregate ((int) sizeof (int64));
            if (*slot == 0) {
                *slot = next_state++;
                states[*slot] = new SqlAggState (kind);
            }
            return states[*slot];
        }

        private static SqlAggState? take_state (Sqlite.Context ctx) {
            int64* slot = (int64*) ctx.aggregate ((int) sizeof (int64));
            if (slot == null || *slot == 0) return null;
            var st = states[*slot];
            states.unset (*slot);
            return st;
        }

        private static void agg_step (Sqlite.Context ctx, Sqlite.Value[] args) {
            unowned SqlFnEntry e = ctx.user_data<SqlFnEntry> ();
            var st = state (ctx, e.script_name);
            if (args.length == 0) return;
            var v = from_sqlite (args[0]);
            if (st.kind == "first" || st.kind == "last") {
                if (!st.seen) st.first = v;
                st.last = v;
                st.seen = true;
                return;
            }
            if (v.is_null) return;
            double x;
            try {
                x = v.to_double ();
            } catch (ScriptError err) {
                return;
            }
            st.n++;
            double delta = x - st.mean;
            st.mean += delta / st.n;
            st.m2 += delta * (x - st.mean);
        }

        private static void agg_final (Sqlite.Context ctx) {
            unowned SqlFnEntry e = ctx.user_data<SqlFnEntry> ();
            var st = take_state (ctx);
            if (st == null) {
                ctx.result_null ();
                return;
            }
            switch (e.script_name) {
                case "first":
                    result (ctx, st.first ?? new SValue.null ());
                    return;
                case "last":
                    result (ctx, st.last ?? new SValue.null ());
                    return;
                case "stdev":
                    if (st.n < 2) ctx.result_null ();
                    else ctx.result_double (Math.sqrt (st.m2 / (st.n - 1)));
                    return;
                case "stdevp":
                    if (st.n < 1) ctx.result_null ();
                    else ctx.result_double (Math.sqrt (st.m2 / st.n));
                    return;
                case "var":
                    if (st.n < 2) ctx.result_null ();
                    else ctx.result_double (st.m2 / (st.n - 1));
                    return;
                default:
                    if (st.n < 1) ctx.result_null ();
                    else ctx.result_double (st.m2 / st.n);
                    return;
            }
        }

        private static void domain_fn (Sqlite.Context ctx, Sqlite.Value[] args) {
            unowned SqlFnEntry e = ctx.user_data<SqlFnEntry> ();
            if (args.length < 2) {
                ctx.result_error ("%s needs an expression and a domain".printf (e.name), Sqlite.ERROR);
                return;
            }
            string sql = ScriptFunctions.domain_sql (e.script_name, args[0].to_text () ?? "", args[1].to_text () ?? "", args.length > 2 && args[2].to_type () != Sqlite.NULL ? (args[2].to_text () ?? "") : "");
            unowned Sqlite.Database handle = ctx.db_handle ();
            Sqlite.Statement stmt;
            if (handle.prepare_v2 (sql, -1, out stmt) != Sqlite.OK) {
                ctx.result_error (handle.errmsg (), Sqlite.ERROR);
                return;
            }
            if (stmt.step () == Sqlite.ROW) {
                switch (stmt.column_type (0)) {
                    case Sqlite.INTEGER: ctx.result_int64 (stmt.column_int64 (0)); break;
                    case Sqlite.FLOAT: ctx.result_double (stmt.column_double (0)); break;
                    case Sqlite.TEXT: ctx.result_text (stmt.column_text (0)); break;
                    default: ctx.result_null (); break;
                }
            } else {
                ctx.result_null ();
            }
        }

        private static SqlFnEntry entry (string name, string script_name) {
            var e = new SqlFnEntry (name, script_name);
            entries.add (e);
            return e;
        }

        public static void register (Sqlite.Database db) {
            if (entries == null) entries = new Gee.ArrayList<SqlFnEntry> ();
            if (states == null) states = new Gee.HashMap<int64?, SqlAggState> ((k) => (uint) k, (a, b) => a == b);
            int det = Sqlite.UTF8 | 0x800;
            int vol = Sqlite.UTF8;
            foreach (string n in SCALARS) db.create_function (n, -1, det, entry (n, n), scalar, null, null);
            string[,] renamed = {
                { "acc_format", "format" }, { "acc_instr", "instr" }, { "acc_replace", "replace" }, { "acc_round", "round" },
                { "acc_nz", "nz" }, { "acc_iif", "iif" }, { "acc_left", "left" }, { "acc_right", "right" }, { "acc_len", "len" },
                { "acc_trim", "trim" }, { "acc_ucase", "ucase" }, { "acc_lcase", "lcase" }, { "acc_year", "year" },
                { "acc_month", "month" }, { "acc_day", "day" }, { "acc_hour", "hour" }
            };
            for (int i = 0; i < renamed.length[0]; i++) db.create_function (renamed[i, 0], -1, det, entry (renamed[i, 0], renamed[i, 1]), scalar, null, null);
            db.create_function ("acc_check_today", 0, det, entry ("acc_check_today", "date"), scalar, null, null);
            db.create_function ("acc_check_now", 0, det, entry ("acc_check_now", "now"), scalar, null, null);
            db.create_function ("acc_date", 0, vol, entry ("acc_date", "date"), scalar, null, null);
            db.create_function ("acc_now", 0, vol, entry ("acc_now", "now"), scalar, null, null);
            db.create_function ("acc_time", 0, vol, entry ("acc_time", "time"), scalar, null, null);
            db.create_function ("acc_cat", 2, det, entry ("acc_cat", "&"), (ctx, args) => {
                bool n0 = args[0].to_type () == Sqlite.NULL, n1 = args[1].to_type () == Sqlite.NULL;
                if (n0 && n1) {
                    ctx.result_null ();
                    return;
                }
                ctx.result_text (text_of (args[0]) + text_of (args[1]));
            }, null, null);
            db.create_function ("acc_like", 2, det, entry ("acc_like", "like"), (ctx, args) => {
                if (args[0].to_type () == Sqlite.NULL || args[1].to_type () == Sqlite.NULL) {
                    ctx.result_null ();
                    return;
                }
                ctx.result_int (ScriptFunctions.like (text_of (args[0]), text_of (args[1])) ? 1 : 0);
            }, null, null);
            db.create_function ("acc_pow", 2, det, entry ("acc_pow", "^"), (ctx, args) => {
                if (args[0].to_type () == Sqlite.NULL || args[1].to_type () == Sqlite.NULL) {
                    ctx.result_null ();
                    return;
                }
                ctx.result_double (Math.pow (args[0].to_double (), args[1].to_double ()));
            }, null, null);
            db.create_function ("acc_intdiv", 2, det, entry ("acc_intdiv", "\\"), (ctx, args) => {
                if (args[0].to_type () == Sqlite.NULL || args[1].to_type () == Sqlite.NULL) {
                    ctx.result_null ();
                    return;
                }
                int64 b = (int64) Script.bankers_round (args[1].to_double ());
                if (b == 0) {
                    ctx.result_error ("Division by zero", Sqlite.ERROR);
                    return;
                }
                ctx.result_int64 ((int64) Script.bankers_round (args[0].to_double ()) / b);
            }, null, null);
            foreach (string a in new string[] { "first", "last", "stdev", "stdevp", "var", "varp" }) {
                db.create_function (a, 1, Sqlite.UTF8, entry (a, a), null, agg_step, agg_final);
            }
            foreach (string d in new string[] { "dlookup", "dcount", "dsum", "davg", "dmin", "dmax", "dfirst", "dlast", "dstdev", "dstdevp", "dvar", "dvarp" }) {
                db.create_function (d, -1, vol, entry (d, d), domain_fn, null, null);
            }
        }

        private static string text_of (Sqlite.Value v) {
            if (v.to_type () == Sqlite.NULL) return "";
            if (v.to_type () == Sqlite.FLOAT) {
                double d = v.to_double ();
                if (d == Math.floor (d) && Math.fabs (d) < 1e15) return "%.0f".printf (d);
                return "%.15g".printf (d).replace (",", ".");
            }
            return v.to_text () ?? "";
        }
    }
}
