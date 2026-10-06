namespace Singularity.Apps.Database {

    public abstract class SExpr {
        public int line;
    }

    public class SLiteral : SExpr {
        public SValue value;

        public SLiteral (SValue v) {
            value = v;
        }
    }

    public class SName : SExpr {
        public string name;

        public SName (string name) {
            this.name = name;
        }
    }

    public class SMember : SExpr {
        public SExpr? target;
        public string name;
        public bool bang;

        public SMember (SExpr? target, string name, bool bang) {
            this.target = target;
            this.name = name;
            this.bang = bang;
        }
    }

    public class SArg {
        public SExpr? value;
        public string? name;

        public SArg (SExpr? value, string? name = null) {
            this.value = value;
            this.name = name;
        }
    }

    public class SCall : SExpr {
        public SExpr target;
        public Gee.ArrayList<SArg> args = new Gee.ArrayList<SArg> ();
        public bool parens = true;

        public SCall (SExpr target) {
            this.target = target;
        }
    }

    public class SBinary : SExpr {
        public string op;
        public SExpr left;
        public SExpr right;

        public SBinary (string op, SExpr left, SExpr right) {
            this.op = op;
            this.left = left;
            this.right = right;
        }
    }

    public class SUnary : SExpr {
        public string op;
        public SExpr operand;

        public SUnary (string op, SExpr operand) {
            this.op = op;
            this.operand = operand;
        }
    }

    public class SNew : SExpr {
        public string class_name;

        public SNew (string class_name) {
            this.class_name = class_name;
        }
    }

    public class STypeOf : SExpr {
        public SExpr operand;
        public string type_name;

        public STypeOf (SExpr operand, string type_name) {
            this.operand = operand;
            this.type_name = type_name;
        }
    }

    public class SParen : SExpr {
        public SExpr inner;

        public SParen (SExpr inner) {
            this.inner = inner;
        }
    }

    public abstract class SStmt {
        public int line;
    }

    public class SAssign : SStmt {
        public SExpr target;
        public SExpr value;
        public bool is_set;
    }

    public class SExprStmt : SStmt {
        public SExpr expr;
    }

    public class SIfBranch {
        public SExpr? condition;
        public Gee.ArrayList<SStmt> body = new Gee.ArrayList<SStmt> ();
    }

    public class SIf : SStmt {
        public Gee.ArrayList<SIfBranch> branches = new Gee.ArrayList<SIfBranch> ();
    }

    public class SCaseTest {
        public string kind = "value";
        public string op = "=";
        public SExpr a;
        public SExpr? b;
    }

    public class SCase {
        public Gee.ArrayList<SCaseTest> tests = new Gee.ArrayList<SCaseTest> ();
        public bool is_else;
        public Gee.ArrayList<SStmt> body = new Gee.ArrayList<SStmt> ();
    }

    public class SSelect : SStmt {
        public SExpr subject;
        public Gee.ArrayList<SCase> cases = new Gee.ArrayList<SCase> ();
    }

    public class SFor : SStmt {
        public SExpr variable;
        public SExpr from;
        public SExpr to;
        public SExpr? step;
        public Gee.ArrayList<SStmt> body = new Gee.ArrayList<SStmt> ();
    }

    public class SForEach : SStmt {
        public SExpr variable;
        public SExpr collection;
        public Gee.ArrayList<SStmt> body = new Gee.ArrayList<SStmt> ();
    }

    public class SDo : SStmt {
        public SExpr? pre;
        public bool pre_until;
        public SExpr? post;
        public bool post_until;
        public Gee.ArrayList<SStmt> body = new Gee.ArrayList<SStmt> ();
    }

    public class SExit : SStmt {
        public string what;
    }

    public class SDimVar {
        public string name;
        public Gee.ArrayList<SExpr> bounds = new Gee.ArrayList<SExpr> ();
        public Gee.ArrayList<SExpr> lower = new Gee.ArrayList<SExpr> ();
        public bool is_array;
        public bool is_new;
        public string type_name = "";
    }

    public class SDim : SStmt {
        public Gee.ArrayList<SDimVar> vars = new Gee.ArrayList<SDimVar> ();
        public bool redim;
        public bool preserve;
        public bool is_const;
        public bool is_static;
        public Gee.ArrayList<SExpr?> values = new Gee.ArrayList<SExpr?> ();
    }

    public class SWith : SStmt {
        public SExpr target;
        public Gee.ArrayList<SStmt> body = new Gee.ArrayList<SStmt> ();
    }

    public class SOnError : SStmt {
        public string mode;
        public string label = "";
    }

    public class SResume : SStmt {
        public string mode;
        public string label = "";
    }

    public class SGoTo : SStmt {
        public string label;
    }

    public class SLabel : SStmt {
        public string name;
    }

    public class SParam {
        public string name;
        public bool by_val;
        public bool optional;
        public bool param_array;
        public SExpr? default_value;
        public bool is_array;
    }

    public class SProcedure {
        public string name;
        public string kind = "sub";
        public bool is_public = true;
        public Gee.ArrayList<SParam> params = new Gee.ArrayList<SParam> ();
        public Gee.ArrayList<SStmt> body = new Gee.ArrayList<SStmt> ();
        public weak SModule module;
        public int line;
    }

    public class SModule {
        public string name = "";
        public Gee.ArrayList<SProcedure> procedures = new Gee.ArrayList<SProcedure> ();
        public Gee.ArrayList<SStmt> declarations = new Gee.ArrayList<SStmt> ();
        public Gee.HashSet<string> private_names = new Gee.HashSet<string> ();

        public SProcedure? find (string name, string? kind = null) {
            foreach (var p in procedures) {
                if (p.name.ascii_casecmp (name) == 0 && (kind == null || p.kind == kind || (kind == "get" && (p.kind == "function" || p.kind == "get")))) return p;
            }
            return null;
        }
    }
}
