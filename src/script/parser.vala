namespace Singularity.Apps.Database {

    public class ScriptParser {
        private Gee.ArrayList<SToken> toks;
        private int pos;

        private ScriptParser (Gee.ArrayList<SToken> toks) {
            this.toks = toks;
            pos = 0;
        }

        public static SModule parse_module (string source, string name = "") throws ScriptError {
            var p = new ScriptParser (ScriptLexer.tokenize (source));
            var m = p.module ();
            m.name = name;
            return m;
        }

        public static SExpr parse_expression (string source) throws ScriptError {
            var p = new ScriptParser (ScriptLexer.tokenize (source));
            p.skip_eol ();
            var e = p.expr ();
            p.skip_eol ();
            if (p.peek ().kind != STok.EOF) throw p.error (_("Unexpected \"%s\" after the expression.").printf (p.peek ().text));
            return e;
        }

        public static Gee.ArrayList<SStmt> parse_statements (string source) throws ScriptError {
            var p = new ScriptParser (ScriptLexer.tokenize (source));
            var list = p.block ({});
            if (p.peek ().kind != STok.EOF) throw p.error (_("Unexpected \"%s\".").printf (p.peek ().text));
            return list;
        }

        private SToken peek (int ahead = 0) {
            int i = int.min (pos + ahead, toks.size - 1);
            return toks[i];
        }

        private SToken next () {
            var t = toks[pos];
            if (pos < toks.size - 1) pos++;
            return t;
        }

        private bool at (string word, int ahead = 0) {
            return peek (ahead).is (word);
        }

        private bool accept (string word) {
            if (at (word)) {
                next ();
                return true;
            }
            return false;
        }

        private ScriptError error (string msg) {
            return new ScriptError.SYNTAX (_("Line %d: %s").printf (peek ().line, msg));
        }

        private void expect (string word) throws ScriptError {
            if (!accept (word)) throw error (_("Expected \"%s\" but found \"%s\".").printf (word, peek ().kind == STok.EOL ? _("end of line") : peek ().text));
        }

        private string ident () throws ScriptError {
            var t = peek ();
            if (t.kind != STok.IDENT) throw error (_("Expected a name but found \"%s\".").printf (t.text));
            next ();
            return t.text;
        }

        private bool at_eol () {
            var k = peek ().kind;
            return k == STok.EOL || k == STok.EOF;
        }

        private void skip_eol () {
            while (peek ().kind == STok.EOL) next ();
        }

        private void end_statement () throws ScriptError {
            if (peek ().kind == STok.EOF) return;
            if (peek ().kind != STok.EOL) throw error (_("Unexpected \"%s\".").printf (peek ().text));
            skip_eol ();
        }

        private SModule module () throws ScriptError {
            var m = new SModule ();
            skip_eol ();
            while (peek ().kind != STok.EOF) {
                if (at ("Option") || at ("Attribute") || at ("VERSION") || at ("DefInt") || at ("DefLng") || at ("DefStr") || at ("DefDbl") || at ("DefBool") || at ("DefVar") || at ("DefObj") || at ("DefDate") || at ("DefCur")) {
                    while (!at_eol ()) next ();
                    skip_eol ();
                    continue;
                }
                if (at ("BEGIN")) {
                    while (!(at ("END") && peek (1).kind == STok.EOL) && peek ().kind != STok.EOF) next ();
                    if (peek ().kind != STok.EOF) next ();
                    skip_eol ();
                    continue;
                }
                bool is_public = true;
                int save = pos;
                if (accept ("Private")) is_public = false;
                else if (accept ("Public") || accept ("Friend") || accept ("Global")) is_public = true;
                accept ("Static");
                if (at ("Sub") || at ("Function") || at ("Property")) {
                    var proc = procedure ();
                    proc.is_public = is_public;
                    proc.module = m;
                    m.procedures.add (proc);
                    skip_eol ();
                    continue;
                }
                if (at ("Declare") || at ("Type") || at ("Enum") || at ("Event") || at ("Implements")) {
                    string closing = at ("Type") ? "Type" : (at ("Enum") ? "Enum" : "");
                    if (closing != "") {
                        if (closing == "Enum") {
                            m.declarations.add (enum_block ());
                            skip_eol ();
                            continue;
                        }
                        while (!(at ("End") && peek (1).is (closing)) && peek ().kind != STok.EOF) next ();
                        next ();
                        next ();
                    }
                    while (!at_eol ()) next ();
                    skip_eol ();
                    continue;
                }
                pos = save;
                if (at ("Dim") || at ("Private") || at ("Public") || at ("Global") || at ("Const") || at ("Static")) {
                    var d = dim_statement ();
                    if (!is_public) {
                        foreach (var v in ((SDim) d).vars) m.private_names.add (v.name.down ());
                    }
                    m.declarations.add (d);
                    end_statement ();
                    continue;
                }
                throw error (_("Only declarations and procedures can be written outside a Sub or Function."));
            }
            return m;
        }

        private SStmt enum_block () throws ScriptError {
            expect ("Enum");
            ident ();
            skip_eol ();
            var d = new SDim ();
            d.is_const = true;
            int64 counter = 0;
            while (!(at ("End") && peek (1).is ("Enum")) && peek ().kind != STok.EOF) {
                var v = new SDimVar ();
                v.name = ident ();
                SExpr value;
                if (accept ("=")) value = expr ();
                else value = new SLiteral (new SValue.int (counter));
                var lit = value as SLiteral;
                if (lit != null) {
                    try {
                        counter = lit.value.to_int () + 1;
                    } catch (ScriptError e) {
                    }
                } else {
                    counter++;
                }
                d.vars.add (v);
                d.values.add (value);
                skip_eol ();
            }
            expect ("End");
            expect ("Enum");
            return d;
        }

        private SProcedure procedure () throws ScriptError {
            var p = new SProcedure ();
            p.line = peek ().line;
            string closing;
            if (accept ("Sub")) {
                p.kind = "sub";
                closing = "Sub";
            } else if (accept ("Function")) {
                p.kind = "function";
                closing = "Function";
            } else {
                expect ("Property");
                closing = "Property";
                if (accept ("Get")) p.kind = "get";
                else if (accept ("Let")) p.kind = "let";
                else {
                    expect ("Set");
                    p.kind = "set";
                }
            }
            p.name = ident ();
            if (accept ("(")) {
                if (!at (")")) {
                    do {
                        var prm = new SParam ();
                        while (true) {
                            if (accept ("Optional")) prm.optional = true;
                            else if (accept ("ByVal")) prm.by_val = true;
                            else if (accept ("ByRef")) prm.by_val = false;
                            else if (accept ("ParamArray")) prm.param_array = true;
                            else break;
                        }
                        prm.name = ident ();
                        if (accept ("(")) {
                            expect (")");
                            prm.is_array = true;
                        }
                        if (accept ("As")) type_name ();
                        if (accept ("=")) prm.default_value = expr ();
                        p.params.add (prm);
                    } while (accept (","));
                }
                expect (")");
            }
            if (accept ("As")) type_name ();
            end_statement ();
            p.body = block ({ "End " + closing });
            expect ("End");
            expect (closing);
            if (!at_eol ()) throw error (_("Unexpected \"%s\".").printf (peek ().text));
            return p;
        }

        private string type_name () throws ScriptError {
            accept ("New");
            string n = ident ();
            while (accept (".")) n += "." + ident ();
            if (accept ("*")) expr_primary ();
            return n;
        }

        private bool at_terminator (string[] terms) {
            if (peek ().kind == STok.EOF) return true;
            foreach (string t in terms) {
                string[] words = t.split (" ");
                bool all = true;
                for (int k = 0; k < words.length; k++) {
                    if (!at (words[k], k)) {
                        all = false;
                        break;
                    }
                }
                if (all) return true;
            }
            return false;
        }

        private Gee.ArrayList<SStmt> block (string[] terms) throws ScriptError {
            var list = new Gee.ArrayList<SStmt> ();
            skip_eol ();
            while (!at_terminator (terms)) {
                if (at ("End") && (at ("Sub", 1) || at ("Function", 1) || at ("Property", 1) || at ("If", 1) || at ("Select", 1) || at ("With", 1))) {
                    throw error (_("\"End %s\" does not match an open block.").printf (peek (1).text));
                }
                var s = statement ();
                if (s != null) list.add (s);
                if (s is SLabel) {
                    skip_eol ();
                    continue;
                }
                end_statement ();
            }
            return list;
        }

        private SStmt? statement () throws ScriptError {
            int line = peek ().line;
            SStmt? s = statement_inner ();
            if (s != null) s.line = line;
            return s;
        }

        private SStmt? statement_inner () throws ScriptError {
            var t = peek ();
            if (t.kind == STok.IDENT && !t.bracketed && peek (1).kind == STok.EOL && peek (1).text == ":" && !is_keyword (t.text)) {
                next ();
                next ();
                var l = new SLabel ();
                l.name = t.text;
                return l;
            }
            if (t.kind == STok.NUMBER && peek (1).kind != STok.EOL) {
                next ();
            }
            if (at ("Dim") || at ("ReDim") || at ("Const") || at ("Static") || ((at ("Private") || at ("Public")) && !at ("Sub", 1) && !at ("Function", 1))) return dim_statement ();
            if (at ("If")) return if_statement ();
            if (at ("Select")) return select_statement ();
            if (at ("For")) return for_statement ();
            if (at ("Do")) return do_statement ();
            if (at ("While")) return while_statement ();
            if (at ("With")) return with_statement ();
            if (accept ("Exit")) {
                var e = new SExit ();
                e.what = ident ().down ();
                return e;
            }
            if (at ("On") && (at ("Error", 1) || at ("Local", 1))) {
                next ();
                accept ("Local");
                expect ("Error");
                var o = new SOnError ();
                if (accept ("Resume")) {
                    expect ("Next");
                    o.mode = "resume-next";
                } else {
                    expect ("GoTo");
                    var lt = next ();
                    if (lt.kind == STok.NUMBER && lt.text == "0") o.mode = "none";
                    else if (lt.kind == STok.OP && lt.text == "-") {
                        next ();
                        o.mode = "none";
                    } else {
                        o.mode = "goto";
                        o.label = lt.text;
                    }
                }
                return o;
            }
            if (accept ("Resume")) {
                var r = new SResume ();
                if (accept ("Next")) r.mode = "next";
                else if (at_eol () || at ("Else")) r.mode = "retry";
                else {
                    var lt = next ();
                    r.mode = lt.text == "0" ? "retry" : "label";
                    r.label = lt.text;
                }
                return r;
            }
            if (accept ("GoTo")) {
                var g = new SGoTo ();
                g.label = next ().text;
                return g;
            }
            if (at ("End") && at_eol_ahead (1)) {
                next ();
                var e = new SExit ();
                e.what = "end";
                return e;
            }
            if (accept ("Stop")) {
                var e = new SExit ();
                e.what = "stop";
                return e;
            }
            if (accept ("Call")) {
                var target = postfix ();
                var st = new SExprStmt ();
                st.expr = (target is SCall) ? target : new SCall (target);
                return st;
            }
            bool is_set = false;
            if (accept ("Set")) is_set = true;
            else accept ("Let");
            if (at ("Debug") && at (".", 1) && at ("Print", 2)) {
                next ();
                next ();
                next ();
                var call = new SCall (new SMember (new SName ("Debug"), "Print", false));
                call.parens = false;
                var parts = new Gee.ArrayList<SExpr> ();
                while (!at_eol () && !at ("Else")) {
                    if (accept (";") || accept (",")) continue;
                    parts.add (expr ());
                }
                SExpr? joined = null;
                foreach (var part in parts) joined = joined == null ? part : new SBinary ("&", joined, part);
                call.args.add (new SArg (joined ?? new SLiteral (new SValue.str (""))));
                var st = new SExprStmt ();
                st.expr = call;
                return st;
            }
            var target = postfix ();
            if (accept ("=")) {
                var a = new SAssign ();
                a.target = target;
                a.value = expr ();
                a.is_set = is_set;
                return a;
            }
            if (is_set) throw error (_("Expected \"=\" after Set."));
            var st = new SExprStmt ();
            if (at_eol () || at ("Else")) {
                if (target is SCall) {
                    st.expr = target;
                } else {
                    var c = new SCall (target);
                    c.parens = false;
                    st.expr = c;
                }
                return st;
            }
            SCall call;
            var pc = target as SCall;
            if (pc != null && pc.parens && pc.args.size == 1 && pc.args[0].name == null && (at (",") || !at_eol ())) {
                call = new SCall (pc.target);
                call.parens = false;
                var first = pc.args[0].value != null ? continue_expr (new SParen (pc.args[0].value)) : null;
                call.args.add (new SArg (first));
                if (accept (",")) parse_args_into (call, false);
            } else {
                call = new SCall (target);
                call.parens = false;
                parse_args_into (call, false);
            }
            st.expr = call;
            return st;
        }

        private SExpr continue_expr (SExpr left) throws ScriptError {
            pending_left = left;
            return expr ();
        }

        private SExpr? pending_left;

        private bool at_eol_ahead (int k) {
            var kk = peek (k).kind;
            return kk == STok.EOL || kk == STok.EOF;
        }

        private static bool is_keyword (string w) {
            string[] kws = { "Else", "End", "Loop", "Next", "Wend", "Case", "Then", "Do", "Resume", "Exit" };
            foreach (string k in kws) {
                if (k.ascii_casecmp (w) == 0) return true;
            }
            return false;
        }

        private SStmt dim_statement () throws ScriptError {
            var d = new SDim ();
            if (accept ("ReDim")) {
                d.redim = true;
                if (accept ("Preserve")) d.preserve = true;
            } else if (accept ("Const")) {
                d.is_const = true;
            } else {
                if (accept ("Static")) d.is_static = true;
                else if (!accept ("Dim")) {
                    if (!accept ("Private") && !accept ("Public")) accept ("Global");
                }
                if (accept ("Const")) d.is_const = true;
                accept ("WithEvents");
            }
            do {
                var v = new SDimVar ();
                v.name = ident ();
                if (accept ("(")) {
                    v.is_array = true;
                    if (!at (")")) {
                        do {
                            var a = expr ();
                            if (accept ("To")) {
                                v.lower.add (a);
                                v.bounds.add (expr ());
                            } else {
                                v.lower.add (new SLiteral (new SValue.int (0)));
                                v.bounds.add (a);
                            }
                        } while (accept (","));
                    }
                    expect (")");
                }
                if (accept ("As")) {
                    if (accept ("New")) v.is_new = true;
                    v.type_name = type_name ();
                }
                SExpr? value = null;
                if (accept ("=")) value = expr ();
                d.vars.add (v);
                d.values.add (value);
            } while (accept (","));
            return d;
        }

        private SStmt if_statement () throws ScriptError {
            expect ("If");
            var s = new SIf ();
            var br = new SIfBranch ();
            br.condition = expr ();
            expect ("Then");
            s.branches.add (br);
            if (!at_eol () || (peek ().kind == STok.EOL && peek ().text == ":")) {
                if (peek ().kind == STok.EOL && peek ().text == ":") next ();
                br.body = inline_block ();
                if (accept ("Else")) {
                    var eb = new SIfBranch ();
                    eb.body = inline_block ();
                    s.branches.add (eb);
                }
                accept_end_if_inline ();
                return s;
            }
            br.body = block ({ "ElseIf", "Else", "End If" });
            while (true) {
                if (accept ("ElseIf")) {
                    var b = new SIfBranch ();
                    b.condition = expr ();
                    expect ("Then");
                    b.body = block ({ "ElseIf", "Else", "End If" });
                    s.branches.add (b);
                    continue;
                }
                if (accept ("Else")) {
                    if (at ("If")) {
                        next ();
                        var b = new SIfBranch ();
                        b.condition = expr ();
                        expect ("Then");
                        b.body = block ({ "ElseIf", "Else", "End If" });
                        s.branches.add (b);
                        continue;
                    }
                    var b = new SIfBranch ();
                    b.body = block ({ "End If" });
                    s.branches.add (b);
                }
                break;
            }
            expect ("End");
            expect ("If");
            return s;
        }

        private void accept_end_if_inline () {
            if (at ("End") && at ("If", 1)) {
                next ();
                next ();
            }
        }

        private Gee.ArrayList<SStmt> inline_block () throws ScriptError {
            var list = new Gee.ArrayList<SStmt> ();
            while (!(peek ().kind == STok.EOL && peek ().text == "\n") && peek ().kind != STok.EOF && !at ("Else")) {
                if (peek ().kind == STok.EOL) {
                    next ();
                    continue;
                }
                var s = statement ();
                if (s != null) list.add (s);
            }
            return list;
        }

        private SStmt select_statement () throws ScriptError {
            expect ("Select");
            expect ("Case");
            var s = new SSelect ();
            s.subject = expr ();
            end_statement ();
            while (accept ("Case")) {
                var c = new SCase ();
                if (accept ("Else")) {
                    c.is_else = true;
                } else {
                    do {
                        var t = new SCaseTest ();
                        if (accept ("Is")) {
                            t.kind = "is";
                            t.op = next ().text;
                            t.a = expr ();
                        } else {
                            t.a = expr ();
                            if (accept ("To")) {
                                t.kind = "range";
                                t.b = expr ();
                            }
                        }
                        c.tests.add (t);
                    } while (accept (","));
                }
                c.body = block ({ "Case", "End Select" });
                s.cases.add (c);
            }
            expect ("End");
            expect ("Select");
            return s;
        }

        private SStmt for_statement () throws ScriptError {
            expect ("For");
            if (accept ("Each")) {
                var fe = new SForEach ();
                fe.variable = new SName (ident ());
                expect ("In");
                fe.collection = expr ();
                end_statement ();
                fe.body = block ({ "Next" });
                expect ("Next");
                if (!at_eol ()) ident ();
                return fe;
            }
            var f = new SFor ();
            f.variable = new SName (ident ());
            expect ("=");
            f.from = expr ();
            expect ("To");
            f.to = expr ();
            if (accept ("Step")) f.step = expr ();
            end_statement ();
            f.body = block ({ "Next" });
            expect ("Next");
            if (!at_eol () && peek ().kind == STok.IDENT) {
                ident ();
                while (accept (",")) ident ();
            }
            return f;
        }

        private SStmt do_statement () throws ScriptError {
            expect ("Do");
            var d = new SDo ();
            if (accept ("While")) d.pre = expr ();
            else if (accept ("Until")) {
                d.pre = expr ();
                d.pre_until = true;
            }
            end_statement ();
            d.body = block ({ "Loop" });
            expect ("Loop");
            if (accept ("While")) d.post = expr ();
            else if (accept ("Until")) {
                d.post = expr ();
                d.post_until = true;
            }
            return d;
        }

        private SStmt while_statement () throws ScriptError {
            expect ("While");
            var d = new SDo ();
            d.pre = expr ();
            end_statement ();
            d.body = block ({ "Wend" });
            expect ("Wend");
            return d;
        }

        private SStmt with_statement () throws ScriptError {
            expect ("With");
            var w = new SWith ();
            w.target = expr ();
            end_statement ();
            w.body = block ({ "End With" });
            expect ("End");
            expect ("With");
            return w;
        }

        public SExpr expr () throws ScriptError {
            return expr_imp ();
        }

        private SExpr expr_imp () throws ScriptError {
            var l = expr_eqv ();
            while (at ("Imp")) {
                next ();
                l = new SBinary ("imp", l, expr_eqv ());
            }
            return l;
        }

        private SExpr expr_eqv () throws ScriptError {
            var l = expr_xor ();
            while (at ("Eqv")) {
                next ();
                l = new SBinary ("eqv", l, expr_xor ());
            }
            return l;
        }

        private SExpr expr_xor () throws ScriptError {
            var l = expr_or ();
            while (at ("Xor")) {
                next ();
                l = new SBinary ("xor", l, expr_or ());
            }
            return l;
        }

        private SExpr expr_or () throws ScriptError {
            var l = expr_and ();
            while (at ("Or") || at ("OrElse")) {
                next ();
                l = new SBinary ("or", l, expr_and ());
            }
            return l;
        }

        private SExpr expr_and () throws ScriptError {
            var l = expr_not ();
            while (at ("And") || at ("AndAlso")) {
                next ();
                l = new SBinary ("and", l, expr_not ());
            }
            return l;
        }

        private SExpr expr_not () throws ScriptError {
            if (pending_left == null && accept ("Not")) return new SUnary ("not", expr_not ());
            return expr_compare ();
        }

        private SExpr expr_compare () throws ScriptError {
            var l = expr_concat ();
            while (true) {
                var t = peek ();
                if (t.kind == STok.OP && (t.text == "=" || t.text == "<>" || t.text == "<" || t.text == ">" || t.text == "<=" || t.text == ">=")) {
                    next ();
                    l = new SBinary (t.text, l, expr_concat ());
                } else if (at ("Like")) {
                    next ();
                    l = new SBinary ("like", l, expr_concat ());
                } else if (at ("Is")) {
                    next ();
                    if (accept ("Not")) {
                        var r = expr_concat ();
                        l = new SUnary ("not", new SBinary ("is", l, r));
                    } else {
                        l = new SBinary ("is", l, expr_concat ());
                    }
                } else if (at ("Between")) {
                    next ();
                    var lo = expr_concat ();
                    expect ("And");
                    var hi = expr_concat ();
                    l = new SBinary ("and", new SBinary (">=", l, lo), new SBinary ("<=", l, hi));
                } else if (at ("In") && at ("(", 1)) {
                    next ();
                    next ();
                    SExpr? any = null;
                    do {
                        var cmp = new SBinary ("=", l, expr ());
                        any = any == null ? cmp : new SBinary ("or", any, cmp);
                    } while (accept (","));
                    expect (")");
                    l = any ?? new SLiteral (new SValue.bool (false));
                } else {
                    break;
                }
            }
            return l;
        }

        private SExpr expr_concat () throws ScriptError {
            var l = expr_add ();
            while (peek ().kind == STok.OP && peek ().text == "&") {
                next ();
                l = new SBinary ("&", l, expr_add ());
            }
            return l;
        }

        private SExpr expr_add () throws ScriptError {
            var l = expr_mod ();
            while (peek ().kind == STok.OP && (peek ().text == "+" || peek ().text == "-")) {
                string op = next ().text;
                l = new SBinary (op, l, expr_mod ());
            }
            return l;
        }

        private SExpr expr_mod () throws ScriptError {
            var l = expr_intdiv ();
            while (at ("Mod")) {
                next ();
                l = new SBinary ("mod", l, expr_intdiv ());
            }
            return l;
        }

        private SExpr expr_intdiv () throws ScriptError {
            var l = expr_mul ();
            while (peek ().kind == STok.OP && peek ().text == "\\") {
                next ();
                l = new SBinary ("\\", l, expr_mul ());
            }
            return l;
        }

        private SExpr expr_mul () throws ScriptError {
            var l = expr_unary ();
            while (peek ().kind == STok.OP && (peek ().text == "*" || peek ().text == "/")) {
                string op = next ().text;
                l = new SBinary (op, l, expr_unary ());
            }
            return l;
        }

        private SExpr expr_unary () throws ScriptError {
            if (pending_left == null && peek ().kind == STok.OP && (peek ().text == "-" || peek ().text == "+")) {
                string op = next ().text;
                var operand = expr_unary ();
                return op == "-" ? new SUnary ("neg", operand) : operand;
            }
            return expr_pow ();
        }

        private SExpr expr_pow () throws ScriptError {
            var l = postfix ();
            while (peek ().kind == STok.OP && peek ().text == "^") {
                next ();
                SExpr r;
                if (peek ().kind == STok.OP && peek ().text == "-") {
                    next ();
                    r = new SUnary ("neg", postfix ());
                } else {
                    r = postfix ();
                }
                l = new SBinary ("^", l, r);
            }
            return l;
        }

        private SExpr postfix () throws ScriptError {
            SExpr e;
            if (pending_left != null) {
                e = pending_left;
                pending_left = null;
            } else {
                e = expr_primary ();
            }
            while (true) {
                var t = peek ();
                if (t.kind == STok.OP && t.text == "." && peek (1).kind == STok.IDENT) {
                    next ();
                    var name = next ();
                    e = new SMember (e, name.text, false);
                    continue;
                }
                if (t.kind == STok.OP && t.text == "!" && peek (1).kind == STok.IDENT) {
                    next ();
                    var name = next ();
                    e = new SMember (e, name.text, true);
                    continue;
                }
                if (t.kind == STok.OP && t.text == "(") {
                    next ();
                    var call = new SCall (e);
                    if (peek ().kind == STok.OP && peek ().text == "*" && peek (1).kind == STok.OP && peek (1).text == ")") {
                        next ();
                        call.args.add (new SArg (new SName ("*")));
                    } else if (!at (")")) parse_args_into (call, true);
                    expect (")");
                    e = call;
                    continue;
                }
                break;
            }
            return e;
        }

        private void parse_args_into (SCall call, bool in_parens) throws ScriptError {
            while (true) {
                if (at (",")) {
                    call.args.add (new SArg (null));
                    next ();
                    if (in_parens && at (")")) {
                        call.args.add (new SArg (null));
                        return;
                    }
                    if (!in_parens && at_eol ()) return;
                    continue;
                }
                if (in_parens && at (")")) return;
                if (!in_parens && (at_eol () || at ("Else"))) return;
                string? name = null;
                if (peek ().kind == STok.IDENT && peek (1).kind == STok.OP && peek (1).text == ":=") {
                    name = next ().text;
                    next ();
                }
                if (accept ("ByVal")) {
                }
                call.args.add (new SArg (expr (), name));
                if (!accept (",")) return;
                if ((in_parens && at (")")) || (!in_parens && at_eol ())) {
                    call.args.add (new SArg (null));
                    return;
                }
            }
        }

        private SExpr expr_primary () throws ScriptError {
            var t = peek ();
            int line = t.line;
            SExpr e;
            switch (t.kind) {
                case STok.NUMBER:
                    next ();
                    e = new SLiteral (t.integer ? new SValue.int ((int64) t.number) : new SValue.dbl (t.number));
                    break;
                case STok.STRING:
                    next ();
                    e = new SLiteral (new SValue.str (t.text));
                    break;
                case STok.DATE:
                    next ();
                    double serial;
                    if (!Script.parse_date_text (t.text, out serial)) {
                        string iso;
                        if (Codec.parse_date (t.text, out iso)) Script.iso_to_serial (iso, out serial);
                        else throw error (_("\"%s\" is not a date.").printf (t.text));
                    }
                    e = new SLiteral (new SValue.date (serial));
                    break;
                case STok.OP:
                    if (t.text == "(") {
                        next ();
                        var inner = expr ();
                        expect (")");
                        e = new SParen (inner);
                    } else if (t.text == "." || t.text == "!") {
                        next ();
                        bool bang = t.text == "!";
                        string name = ident ();
                        e = new SMember (null, name, bang);
                    } else {
                        throw error (_("Unexpected \"%s\".").printf (t.text));
                    }
                    break;
                case STok.IDENT:
                    if (!t.bracketed) {
                        if (t.is ("True")) {
                            next ();
                            e = new SLiteral (new SValue.bool (true));
                            break;
                        }
                        if (t.is ("False")) {
                            next ();
                            e = new SLiteral (new SValue.bool (false));
                            break;
                        }
                        if (t.is ("Null")) {
                            next ();
                            e = new SLiteral (new SValue.null ());
                            break;
                        }
                        if (t.is ("Nothing")) {
                            next ();
                            e = new SLiteral (new SValue.nothing ());
                            break;
                        }
                        if (t.is ("Empty")) {
                            next ();
                            e = new SLiteral (new SValue.empty ());
                            break;
                        }
                        if (t.is ("New")) {
                            next ();
                            e = new SNew (type_name ());
                            break;
                        }
                        if (t.is ("TypeOf")) {
                            next ();
                            var operand = postfix ();
                            expect ("Is");
                            e = new STypeOf (operand, type_name ());
                            break;
                        }
                        if (t.is ("AddressOf")) {
                            next ();
                            e = new SLiteral (new SValue.str (ident ()));
                            break;
                        }
                    }
                    next ();
                    e = new SName (t.text);
                    break;
                default:
                    throw error (at_eol () ? _("An expression is missing.") : _("Unexpected \"%s\".").printf (t.text));
            }
            e.line = line;
            return e;
        }
    }
}
