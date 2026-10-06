namespace Singularity.Apps.Database {

    public class ScriptConstants {
        private static Gee.HashMap<string, SValue>? table;

        public static bool lookup (string key, out SValue value) {
            if (table == null) build ();
            value = table[key];
            return value != null;
        }

        private static void add (string name, int64 v) {
            table[name.down ()] = new SValue.int (v);
        }

        private static void build () {
            table = new Gee.HashMap<string, SValue> ();
            add ("vbOKOnly", 0);
            add ("vbOKCancel", 1);
            add ("vbAbortRetryIgnore", 2);
            add ("vbYesNoCancel", 3);
            add ("vbYesNo", 4);
            add ("vbRetryCancel", 5);
            add ("vbCritical", 16);
            add ("vbQuestion", 32);
            add ("vbExclamation", 48);
            add ("vbInformation", 64);
            add ("vbDefaultButton1", 0);
            add ("vbDefaultButton2", 256);
            add ("vbDefaultButton3", 512);
            add ("vbOK", 1);
            add ("vbCancel", 2);
            add ("vbAbort", 3);
            add ("vbRetry", 4);
            add ("vbIgnore", 5);
            add ("vbYes", 6);
            add ("vbNo", 7);
            add ("vbUpperCase", 1);
            add ("vbLowerCase", 2);
            add ("vbProperCase", 3);
            add ("vbBinaryCompare", 0);
            add ("vbTextCompare", 1);
            add ("vbDatabaseCompare", 2);
            add ("vbSunday", 1);
            add ("vbMonday", 2);
            add ("vbTuesday", 3);
            add ("vbWednesday", 4);
            add ("vbThursday", 5);
            add ("vbFriday", 6);
            add ("vbSaturday", 7);
            add ("vbUseSystemDayOfWeek", 0);
            add ("vbFirstJan1", 1);
            add ("vbGeneralDate", 0);
            add ("vbLongDate", 1);
            add ("vbShortDate", 2);
            add ("vbLongTime", 3);
            add ("vbShortTime", 4);
            add ("vbEmpty", 0);
            add ("vbNull", 1);
            add ("vbInteger", 2);
            add ("vbLong", 3);
            add ("vbSingle", 4);
            add ("vbDouble", 5);
            add ("vbCurrency", 6);
            add ("vbDate", 7);
            add ("vbString", 8);
            add ("vbObject", 9);
            add ("vbBoolean", 11);
            add ("vbVariant", 12);
            add ("vbArray", 8192);
            add ("vbObjectError", -2147221504);
            add ("vbBlack", 0);
            add ("vbWhite", 0xFFFFFF);
            add ("vbRed", 0x0000FF);
            add ("vbGreen", 0x00FF00);
            add ("vbBlue", 0xFF0000);
            add ("vbYellow", 0x00FFFF);
            add ("acTable", 0);
            add ("acQuery", 1);
            add ("acForm", 2);
            add ("acReport", 3);
            add ("acMacro", 4);
            add ("acModule", 5);
            add ("acDefault", -1);
            add ("acNormal", 0);
            add ("acDesign", 1);
            add ("acPreview", 2);
            add ("acFormDS", 3);
            add ("acFormPivotTable", 4);
            add ("acLayout", 6);
            add ("acViewNormal", 0);
            add ("acViewDesign", 1);
            add ("acViewPreview", 2);
            add ("acViewReport", 5);
            add ("acViewLayout", 6);
            add ("acPrevious", 0);
            add ("acNext", 1);
            add ("acFirst", 2);
            add ("acLast", 3);
            add ("acGoTo", 4);
            add ("acNewRec", 5);
            add ("acWindowNormal", 0);
            add ("acHidden", 1);
            add ("acIcon", 2);
            add ("acDialog", 3);
            add ("acFormPropertySettings", -1);
            add ("acFormAdd", 0);
            add ("acFormEdit", 1);
            add ("acFormReadOnly", 2);
            add ("acAdd", 0);
            add ("acEdit", 1);
            add ("acReadOnly", 2);
            add ("acSavePrompt", 0);
            add ("acSaveYes", 1);
            add ("acSaveNo", 2);
            add ("acExport", 1);
            add ("acImport", 0);
            add ("acLink", 2);
            add ("acSpreadsheetTypeExcel12Xml", 10);
            add ("acExportDelim", 2);
            add ("acImportDelim", 0);
            add ("acCmdSaveRecord", 97);
            add ("acCmdUndo", 292);
            add ("acCmdDeleteRecord", 223);
            add ("acCmdRecordsGoToNew", 28);
            add ("acCmdRefresh", 18);
            add ("acCmdRequery", 505);
            add ("acCmdClose", 58);
            add ("acCmdFind", 30);
            add ("acCmdPrint", 340);
            add ("acCmdFilterByForm", 145);
            add ("acCmdApplyFilterSort", 93);
            add ("acCmdRemoveFilterSort", 144);
            add ("acEntire", 0);
            add ("acAnywhere", 0);
            add ("acStart", 2);
            add ("acAll", 0);
            add ("acUp", 0);
            add ("acDown", 1);
            add ("acSearchAll", 2);
            add ("acCurrent", -1);
            add ("dbOpenTable", 1);
            add ("dbOpenDynaset", 2);
            add ("dbOpenSnapshot", 4);
            add ("dbOpenForwardOnly", 8);
            add ("dbSeeChanges", 512);
            add ("dbFailOnError", 128);
            add ("dbAppendOnly", 8);
            add ("dbReadOnly", 4);
            add ("dbBoolean", 1);
            add ("dbByte", 2);
            add ("dbInteger", 3);
            add ("dbLong", 4);
            add ("dbCurrency", 5);
            add ("dbSingle", 6);
            add ("dbDouble", 7);
            add ("dbDate", 8);
            add ("dbText", 10);
            add ("dbMemo", 12);
            add ("acOutputReport", 3);
            add ("acOutputForm", 2);
            add ("acOutputTable", 0);
            add ("acOutputQuery", 1);
            add ("acDataErrContinue", 0);
            add ("acDataErrDisplay", 1);
            add ("acDataErrAdded", 2);
            add ("acDeleteOK", 0);
            add ("acDeleteCancel", 1);
            add ("acDeleteUserCancel", 2);
            table["vbcrlf"] = new SValue.str ("\r\n");
            table["vbnewline"] = new SValue.str ("\n");
            table["vbcr"] = new SValue.str ("\r");
            table["vblf"] = new SValue.str ("\n");
            table["vbtab"] = new SValue.str ("\t");
            table["vbnullstring"] = new SValue.str ("");
            table["vbnullchar"] = new SValue.str ("");
            table["acformatpdf"] = new SValue.str ("PDF Format (*.pdf)");
            table["acformatxlsx"] = new SValue.str ("Excel Workbook (*.xlsx)");
            table["acformattxt"] = new SValue.str ("MS-DOS Text (*.txt)");
            table["acformathtml"] = new SValue.str ("HTML (*.html)");
            table["acformatrtf"] = new SValue.str ("Rich Text Format (*.rtf)");
        }
    }

    public class ScriptFunctions {
        private static SValue arg (SValue[] args, int i) {
            if (i >= args.length || args[i] is MissingValue) return new SValue.empty ();
            return args[i].resolved_or_self ();
        }

        private static bool has (SValue[] args, int i) {
            return i < args.length && !(args[i] is MissingValue);
        }

        private static void need (SValue[] args, int n, string name) throws ScriptError {
            int given = 0;
            for (int i = 0; i < args.length; i++) if (!(args[i] is MissingValue)) given = i + 1;
            if (given < n) throw Script.fail (450, _("%s needs at least %d arguments.").printf (name, n));
        }

        public static bool like (string text, string pattern) {
            var sb = new StringBuilder ("^");
            int i = 0;
            int n = pattern.length;
            while (i < n) {
                char c = pattern[i];
                if (c == '*') sb.append (".*");
                else if (c == '?') sb.append (".");
                else if (c == '#') sb.append ("[0-9]");
                else if (c == '[') {
                    int close = pattern.index_of_char (']', i + 1);
                    if (close < 0) {
                        sb.append ("\\[");
                    } else {
                        string inner = pattern.substring (i + 1, close - i - 1);
                        if (inner.has_prefix ("!")) inner = "^" + inner.substring (1);
                        sb.append ("[" + inner.replace ("\\", "\\\\") + "]");
                        i = close;
                    }
                } else {
                    unichar u = pattern.get_char (i);
                    int len = u.to_string ().length;
                    sb.append (Regex.escape_string (pattern.substring (i, len)));
                    i += len;
                    continue;
                }
                i++;
            }
            sb.append ("$");
            try {
                var re = new Regex (sb.str, RegexCompileFlags.CASELESS | RegexCompileFlags.DOTALL);
                return re.match (text);
            } catch (RegexError e) {
                return false;
            }
        }

        private static string sub_chars (string s, int start, int len) {
            int chars = s.char_count ();
            if (start >= chars || len <= 0) return "";
            int a = s.index_of_nth_char (start);
            int e = start + len >= chars ? s.length : s.index_of_nth_char (start + len);
            return s.substring (a, e - a);
        }

        private static SValue number_result (double v) {
            if (v == Math.floor (v) && Math.fabs (v) < 9e15) return new SValue.int ((int64) v);
            return new SValue.dbl (v);
        }

        private static string interval_unit (string s) {
            return s.strip ().down ();
        }

        public static double date_add (string interval, double n, double serial) throws ScriptError {
            int y, m, d, hh, mm, ss;
            Script.split_serial (serial, out y, out m, out d, out hh, out mm, out ss);
            double frac = serial - Math.floor (serial);
            switch (interval_unit (interval)) {
                case "yyyy":
                case "q":
                case "m":
                    int months = (int) n * (interval_unit (interval) == "yyyy" ? 12 : (interval_unit (interval) == "q" ? 3 : 1));
                    int total = y * 12 + (m - 1) + months;
                    int ny = total / 12;
                    int nm = total % 12 + 1;
                    int dim = days_in_month (ny, nm);
                    return Script.make_serial (ny, nm, int.min (d, dim)) + frac;
                case "y":
                case "d":
                case "w":
                    return serial + Math.trunc (n);
                case "ww":
                    return serial + Math.trunc (n) * 7;
                case "h":
                    return serial + Math.trunc (n) / 24.0;
                case "n":
                    return serial + Math.trunc (n) / 1440.0;
                case "s":
                    return serial + Math.trunc (n) / 86400.0;
            }
            throw Script.fail (5, _("\"%s\" is not a valid interval.").printf (interval));
        }

        public static int days_in_month (int y, int m) {
            int[] dm = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
            if (m == 2 && ((y % 4 == 0 && y % 100 != 0) || y % 400 == 0)) return 29;
            return dm[(m - 1).clamp (0, 11)];
        }

        public static int64 date_diff (string interval, double a, double b, int first_day = 1) throws ScriptError {
            int y1, m1, d1, h1, n1, s1, y2, m2, d2, h2, n2, s2;
            Script.split_serial (a, out y1, out m1, out d1, out h1, out n1, out s1);
            Script.split_serial (b, out y2, out m2, out d2, out h2, out n2, out s2);
            switch (interval_unit (interval)) {
                case "yyyy": return y2 - y1;
                case "q": return ((y2 * 4 + (m2 - 1) / 3) - (y1 * 4 + (m1 - 1) / 3));
                case "m": return (y2 * 12 + m2) - (y1 * 12 + m1);
                case "y":
                case "d": return (int64) (Math.floor (b) - Math.floor (a));
                case "w": return (int64) ((Math.floor (b) - Math.floor (a)) / 7);
                case "ww":
                    double wa = Math.floor (a) - (AccessFormat.weekday (a, first_day) - 1);
                    double wb = Math.floor (b) - (AccessFormat.weekday (b, first_day) - 1);
                    return (int64) ((wb - wa) / 7);
                case "h": return (int64) (Math.floor (b * 24 + 1e-9) - Math.floor (a * 24 + 1e-9));
                case "n": return (int64) (Math.floor (b * 1440 + 1e-7) - Math.floor (a * 1440 + 1e-7));
                case "s": return (int64) Math.round ((b - a) * 86400);
            }
            throw Script.fail (5, _("\"%s\" is not a valid interval.").printf (interval));
        }

        public static int64 date_part (string interval, double serial, int first_day = 1) throws ScriptError {
            int y, m, d, hh, mm, ss;
            Script.split_serial (serial, out y, out m, out d, out hh, out mm, out ss);
            switch (interval_unit (interval)) {
                case "yyyy": return y;
                case "q": return (m - 1) / 3 + 1;
                case "m": return m;
                case "y": return (int64) (Math.floor (serial) - Script.make_serial (y, 1, 1)) + 1;
                case "d": return d;
                case "w": return AccessFormat.weekday (serial, first_day);
                case "ww": return AccessFormat.week_of_year (serial, first_day);
                case "h": return hh;
                case "n": return mm;
                case "s": return ss;
            }
            throw Script.fail (5, _("\"%s\" is not a valid interval.").printf (interval));
        }

        public static double round_half_even (double x, int digits) {
            double f = Math.pow (10, digits);
            double v = x * f;
            double r = Script.bankers_round (Math.round (v * 1e6) / 1e6);
            return r / f;
        }

        public static bool call (ScriptRuntime rt, SFrame frame, string name0, Gee.List<SArg> raw, SValue[] args, out SValue result) throws ScriptError {
            result = new SValue.empty ();
            string name = name0.down ();
            if (name.has_suffix ("$")) name = name.substring (0, name.length - 1);
            switch (name) {
                case "len":
                    var v = arg (args, 0);
                    if (v.is_null) {
                        result = v;
                        return true;
                    }
                    result = new SValue.int (v.to_text ().char_count ());
                    return true;
                case "left":
                case "right":
                    need (args, 2, name0);
                    var s = arg (args, 0);
                    if (s.is_null) {
                        result = s;
                        return true;
                    }
                    string t = s.to_text ();
                    int n = (int) arg (args, 1).to_int ();
                    if (n < 0) throw Script.fail (5, _("Invalid procedure call or argument"));
                    int chars = t.char_count ();
                    if (name == "left") result = new SValue.str (sub_chars (t, 0, n));
                    else if (n >= chars) result = new SValue.str (t);
                    else result = new SValue.str (sub_chars (t, chars - n, n));
                    return true;
                case "mid":
                    need (args, 2, name0);
                    var s = arg (args, 0);
                    if (s.is_null) {
                        result = s;
                        return true;
                    }
                    int start = (int) arg (args, 1).to_int ();
                    if (start < 1) throw Script.fail (5, _("Invalid procedure call or argument"));
                    string t = s.to_text ();
                    int len = has (args, 2) ? (int) arg (args, 2).to_int () : t.char_count ();
                    result = new SValue.str (sub_chars (t, start - 1, len));
                    return true;
                case "instr":
                    need (args, 2, name0);
                    int start = 1;
                    int off = 0;
                    if (args.length >= 3 && has (args, 2) && arg (args, 0).is_numeric ()) {
                        start = (int) arg (args, 0).to_int ();
                        off = 1;
                    }
                    var hay = arg (args, off);
                    var needle = arg (args, off + 1);
                    if (hay.is_null || needle.is_null) {
                        result = new SValue.null ();
                        return true;
                    }
                    bool binary = has (args, off + 2) && arg (args, off + 2).to_int () == 0;
                    string h = hay.to_text (), nd = needle.to_text ();
                    if (!binary) {
                        h = h.casefold ();
                        nd = nd.casefold ();
                    }
                    if (start > h.char_count () + 1) {
                        result = new SValue.int (0);
                        return true;
                    }
                    if (nd == "") {
                        result = new SValue.int (start);
                        return true;
                    }
                    int from = h.index_of_nth_char (start - 1);
                    int at = h.index_of (nd, from);
                    result = new SValue.int (at < 0 ? 0 : h.substring (0, at).char_count () + 1);
                    return true;
                case "instrrev":
                    need (args, 2, name0);
                    var hay = arg (args, 0);
                    var needle = arg (args, 1);
                    if (hay.is_null || needle.is_null) {
                        result = new SValue.null ();
                        return true;
                    }
                    string h = hay.to_text ().casefold (), nd = needle.to_text ().casefold ();
                    int startp = has (args, 2) ? (int) arg (args, 2).to_int () : -1;
                    string scope = h;
                    if (startp > 0) scope = sub_chars (h, 0, startp);
                    int at = scope.last_index_of (nd);
                    result = new SValue.int (at < 0 ? 0 : scope.substring (0, at).char_count () + 1);
                    return true;
                case "replace":
                    need (args, 3, name0);
                    var s = arg (args, 0);
                    if (s.is_null) {
                        result = s;
                        return true;
                    }
                    string src = s.to_text ();
                    string find = arg (args, 1).to_text ();
                    string with = arg (args, 2).to_text ();
                    if (find == "") {
                        result = new SValue.str (src);
                        return true;
                    }
                    try {
                        var re = new Regex (Regex.escape_string (find), RegexCompileFlags.CASELESS);
                        result = new SValue.str (re.replace_literal (src, -1, 0, with));
                    } catch (RegexError e) {
                        result = new SValue.str (src.replace (find, with));
                    }
                    return true;
                case "trim":
                case "ltrim":
                case "rtrim":
                case "ucase":
                case "lcase":
                case "strreverse":
                    var s = arg (args, 0);
                    if (s.is_null) {
                        result = s;
                        return true;
                    }
                    string t = s.to_text ();
                    switch (name) {
                        case "trim": t = t.strip (); break;
                        case "ltrim": t = t.chug (); break;
                        case "rtrim": t = t.chomp (); break;
                        case "ucase": t = t.up (); break;
                        case "lcase": t = t.down (); break;
                        default: t = t.reverse (); break;
                    }
                    result = new SValue.str (t);
                    return true;
                case "strconv":
                    var s = arg (args, 0);
                    if (s.is_null) {
                        result = s;
                        return true;
                    }
                    int mode = (int) arg (args, 1).to_int ();
                    string t = s.to_text ();
                    if (mode == 1) t = t.up ();
                    else if (mode == 2) t = t.down ();
                    else if (mode == 3) t = proper (t);
                    result = new SValue.str (t);
                    return true;
                case "space":
                    result = new SValue.str (string.nfill ((int) arg (args, 0).to_int ().clamp (0, 1000000), ' '));
                    return true;
                case "string":
                    need (args, 2, name0);
                    var c = arg (args, 1);
                    string ch = c.is_numeric () ? ((unichar) c.to_int ()).to_string () : c.to_text ();
                    var sb = new StringBuilder ();
                    int count = (int) arg (args, 0).to_int ();
                    string first = ch == "" ? "" : ch.substring (0, ch.index_of_nth_char (1));
                    for (int k = 0; k < count; k++) sb.append (first);
                    result = new SValue.str (sb.str);
                    return true;
                case "strcomp":
                    need (args, 2, name0);
                    var a = arg (args, 0), b = arg (args, 1);
                    if (a.is_null || b.is_null) {
                        result = new SValue.null ();
                        return true;
                    }
                    bool bin = has (args, 2) && arg (args, 2).to_int () == 0;
                    int r = bin ? strcmp (a.to_text (), b.to_text ()) : a.to_text ().casefold ().collate (b.to_text ().casefold ());
                    result = new SValue.int (r < 0 ? -1 : (r > 0 ? 1 : 0));
                    return true;
                case "chr":
                case "chrw":
                    result = new SValue.str (((unichar) arg (args, 0).to_int ()).to_string ());
                    return true;
                case "asc":
                case "ascw":
                    string t = arg (args, 0).to_text ();
                    if (t == "") throw Script.fail (5, _("Invalid procedure call or argument"));
                    result = new SValue.int ((int64) t.get_char (0));
                    return true;
                case "split":
                    var s = arg (args, 0);
                    string delim = has (args, 1) ? arg (args, 1).to_text () : " ";
                    var list = new Gee.ArrayList<SValue> ();
                    string text = s.to_text ();
                    if (text != "") {
                        foreach (string part in text.split (delim)) list.add (new SValue.str (part));
                    }
                    result = new SValue.array (new SArray.from_list (list));
                    return true;
                case "join":
                    var a = arg (args, 0);
                    if (a.kind != SKind.ARRAY) throw Script.fail (13, _("Type mismatch"));
                    string delim = has (args, 1) ? arg (args, 1).to_text () : " ";
                    string[] parts = {};
                    foreach (var item in a.arr.items) parts += item.to_text ();
                    result = new SValue.str (string.joinv (delim, parts));
                    return true;
                case "format":
                    var v = arg (args, 0);
                    string fmt = has (args, 1) ? arg (args, 1).to_text () : "";
                    result = new SValue.str (AccessFormat.format (v, fmt));
                    return true;
                case "formatnumber":
                case "formatcurrency":
                case "formatpercent":
                    var v = arg (args, 0);
                    if (v.is_null) {
                        result = new SValue.str ("");
                        return true;
                    }
                    int dec = has (args, 1) && arg (args, 1).to_int () >= 0 ? (int) arg (args, 1).to_int () : 2;
                    double x = v.to_double ();
                    if (name == "formatcurrency") result = new SValue.str (Codec.format_currency (x, dec));
                    else if (name == "formatpercent") result = new SValue.str (Codec.format_number (x * 100, dec, true) + "%");
                    else result = new SValue.str (Codec.format_number (x, dec, true));
                    return true;
                case "formatdatetime":
                    var v = arg (args, 0);
                    int kind = has (args, 1) ? (int) arg (args, 1).to_int () : 0;
                    string[] names = { "General Date", "Long Date", "Short Date", "Long Time", "Short Time" };
                    result = new SValue.str (AccessFormat.format (v, names[kind.clamp (0, 4)]));
                    return true;
                case "val":
                    string t = arg (args, 0).to_text ().strip ().replace (" ", "");
                    int k = 0;
                    var sb = new StringBuilder ();
                    bool dot = false;
                    if (k < t.length && (t[k] == '-' || t[k] == '+')) sb.append_c (t[k++]);
                    while (k < t.length && (t[k].isdigit () || (t[k] == '.' && !dot))) {
                        if (t[k] == '.') dot = true;
                        sb.append_c (t[k++]);
                    }
                    double x = 0;
                    double.try_parse (sb.str == "" || sb.str == "-" || sb.str == "+" ? "0" : sb.str, out x);
                    result = number_result (x);
                    return true;
                case "str":
                    var v = arg (args, 0);
                    if (v.is_null) {
                        result = v;
                        return true;
                    }
                    double x = v.to_double ();
                    string s = Script.format_double (x).replace (",", ".");
                    result = new SValue.str (x >= 0 ? " " + s : s);
                    return true;
                case "cstr":
                    var v = arg (args, 0);
                    if (v.is_null) throw Script.fail (94, _("Invalid use of Null"));
                    result = new SValue.str (v.to_str ());
                    return true;
                case "hex":
                case "oct":
                    var v = arg (args, 0);
                    if (v.is_null) {
                        result = v;
                        return true;
                    }
                    int64 x = v.to_int ();
                    result = new SValue.str (name == "hex" ? "%llX".printf (x) : "%llo".printf (x));
                    return true;
                case "cint":
                case "clng":
                case "cbyte":
                case "clnglng":
                    var v = arg (args, 0);
                    if (v.is_null) throw Script.fail (94, _("Invalid use of Null"));
                    result = new SValue.int ((int64) Script.bankers_round (v.to_double ()));
                    return true;
                case "cdbl":
                case "csng":
                case "ccur":
                case "cdec":
                    var v = arg (args, 0);
                    if (v.is_null) throw Script.fail (94, _("Invalid use of Null"));
                    double x = v.to_double ();
                    if (name == "ccur") x = Math.round (x * 10000) / 10000;
                    result = new SValue.dbl (x);
                    return true;
                case "cbool":
                    var v = arg (args, 0);
                    if (v.is_null) throw Script.fail (94, _("Invalid use of Null"));
                    result = new SValue.bool (v.to_bool ());
                    return true;
                case "cdate":
                case "datevalue":
                case "timevalue":
                    var v = arg (args, 0);
                    if (v.is_null) {
                        if (name == "cdate") throw Script.fail (94, _("Invalid use of Null"));
                        result = v;
                        return true;
                    }
                    double serial = v.to_date ();
                    if (name == "datevalue") serial = Math.floor (serial);
                    else if (name == "timevalue") serial = serial - Math.floor (serial);
                    result = new SValue.date (serial);
                    return true;
                case "cvar":
                    result = arg (args, 0);
                    return true;
                case "int":
                case "fix":
                    var v = arg (args, 0);
                    if (v.is_null) {
                        result = v;
                        return true;
                    }
                    double x = v.to_double ();
                    result = number_result (name == "int" ? Math.floor (x) : Math.trunc (x));
                    return true;
                case "abs":
                case "sgn":
                case "sqr":
                case "exp":
                case "log":
                case "sin":
                case "cos":
                case "tan":
                case "atn":
                    var v = arg (args, 0);
                    if (v.is_null) {
                        result = v;
                        return true;
                    }
                    double x = v.to_double ();
                    switch (name) {
                        case "abs":
                            result = v.kind == SKind.INT ? new SValue.int (v.i.abs ()) : new SValue.dbl (Math.fabs (x));
                            return true;
                        case "sgn":
                            result = new SValue.int (x > 0 ? 1 : (x < 0 ? -1 : 0));
                            return true;
                        case "sqr":
                            if (x < 0) throw Script.fail (5, _("Invalid procedure call or argument"));
                            result = new SValue.dbl (Math.sqrt (x));
                            return true;
                        case "exp": result = new SValue.dbl (Math.exp (x)); return true;
                        case "log":
                            if (x <= 0) throw Script.fail (5, _("Invalid procedure call or argument"));
                            result = new SValue.dbl (Math.log (x));
                            return true;
                        case "sin": result = new SValue.dbl (Math.sin (x)); return true;
                        case "cos": result = new SValue.dbl (Math.cos (x)); return true;
                        case "tan": result = new SValue.dbl (Math.tan (x)); return true;
                        default: result = new SValue.dbl (Math.atan (x)); return true;
                    }
                case "round":
                    var v = arg (args, 0);
                    if (v.is_null) {
                        result = v;
                        return true;
                    }
                    int digits = has (args, 1) ? (int) arg (args, 1).to_int () : 0;
                    double r = round_half_even (v.to_double (), digits);
                    result = digits == 0 ? number_result (r) : new SValue.dbl (r);
                    return true;
                case "rnd":
                    result = new SValue.dbl (Random.next_double ());
                    return true;
                case "randomize":
                    Random.set_seed ((uint32) get_monotonic_time ());
                    return true;
                case "isnull":
                    result = new SValue.bool (arg (args, 0).is_null);
                    return true;
                case "isempty":
                    result = new SValue.bool (arg (args, 0).is_empty);
                    return true;
                case "isnumeric":
                    var v = arg (args, 0);
                    result = new SValue.bool (!v.is_null && !v.is_empty && v.kind != SKind.DATE && v.looks_numeric ());
                    return true;
                case "isdate":
                    var v = arg (args, 0);
                    double serial;
                    result = new SValue.bool (v.kind == SKind.DATE || (v.kind == SKind.STRING && Script.parse_date_text (v.s, out serial)));
                    return true;
                case "isarray":
                    result = new SValue.bool (args.length > 0 && args[0].kind == SKind.ARRAY);
                    return true;
                case "isobject":
                    result = new SValue.bool (args.length > 0 && (args[0].kind == SKind.OBJECT || args[0].kind == SKind.NOTHING));
                    return true;
                case "iserror":
                    result = new SValue.bool (false);
                    return true;
                case "ismissing":
                    bool missing = raw.size == 0;
                    if (raw.size > 0 && raw[0].value is SName) {
                        var key = ((SName) raw[0].value).name.down ();
                        var mv = frame.locals[key] as MissingVar;
                        missing = mv != null && mv.missing;
                    }
                    result = new SValue.bool (missing);
                    return true;
                case "vartype":
                    var v = args.length > 0 ? args[0] : new SValue.empty ();
                    int code = 0;
                    switch (v.kind) {
                        case SKind.NULL: code = 1; break;
                        case SKind.INT: code = 3; break;
                        case SKind.DOUBLE: code = 5; break;
                        case SKind.DATE: code = 7; break;
                        case SKind.STRING: code = 8; break;
                        case SKind.OBJECT:
                        case SKind.NOTHING: code = 9; break;
                        case SKind.BOOL: code = 11; break;
                        case SKind.ARRAY: code = 8204; break;
                        default: code = 0; break;
                    }
                    result = new SValue.int (code);
                    return true;
                case "typename":
                    var v = args.length > 0 ? args[0] : new SValue.empty ();
                    string tn;
                    switch (v.kind) {
                        case SKind.NULL: tn = "Null"; break;
                        case SKind.INT: tn = "Long"; break;
                        case SKind.DOUBLE: tn = "Double"; break;
                        case SKind.DATE: tn = "Date"; break;
                        case SKind.STRING: tn = "String"; break;
                        case SKind.OBJECT: tn = v.obj.type_name (); break;
                        case SKind.NOTHING: tn = "Nothing"; break;
                        case SKind.BOOL: tn = "Boolean"; break;
                        case SKind.ARRAY: tn = "Variant()"; break;
                        default: tn = "Empty"; break;
                    }
                    result = new SValue.str (tn);
                    return true;
                case "nz":
                    var v = arg (args, 0);
                    if (!v.is_null && !v.is_empty) {
                        result = v;
                        return true;
                    }
                    result = has (args, 1) ? arg (args, 1) : new SValue.int (0);
                    return true;
                case "iif":
                    need (args, 3, name0);
                    result = ScriptRuntime.truth (arg (args, 0)) ? arg (args, 1) : arg (args, 2);
                    return true;
                case "choose":
                    need (args, 2, name0);
                    var idx = arg (args, 0);
                    if (idx.is_null) {
                        result = idx;
                        return true;
                    }
                    int k = (int) idx.to_int ();
                    result = k >= 1 && k < args.length ? arg (args, k) : new SValue.null ();
                    return true;
                case "switch":
                    for (int k = 0; k + 1 < args.length; k += 2) {
                        if (ScriptRuntime.truth (arg (args, k))) {
                            result = arg (args, k + 1);
                            return true;
                        }
                    }
                    result = new SValue.null ();
                    return true;
                case "array":
                    var list = new Gee.ArrayList<SValue> ();
                    foreach (var a in args) list.add (a);
                    result = new SValue.array (new SArray.from_list (list));
                    return true;
                case "ubound":
                case "lbound":
                    var a = args.length > 0 ? args[0] : new SValue.empty ();
                    if (a.kind != SKind.ARRAY) throw Script.fail (13, _("Type mismatch"));
                    int dim = has (args, 1) ? (int) arg (args, 1).to_int () : 1;
                    if (name == "lbound") result = new SValue.int (a.arr.lower);
                    else if (dim <= 1 || a.arr.dims.length < dim) result = new SValue.int (a.arr.lower + (a.arr.dims.length > 0 ? a.arr.dims[0] : a.arr.items.size) - 1);
                    else result = new SValue.int (a.arr.lower + a.arr.dims[dim - 1] - 1);
                    return true;
                case "erase":
                    if (args.length > 0 && args[0].kind == SKind.ARRAY) {
                        foreach (var item in args[0].arr.items) item.kind = SKind.EMPTY;
                    }
                    return true;
                case "date":
                    result = Script.today ();
                    return true;
                case "now":
                    result = Script.now ();
                    return true;
                case "time":
                    var nw = Script.now ();
                    result = new SValue.date (nw.d - Math.floor (nw.d));
                    return true;
                case "timer":
                    var n = new DateTime.now_local ();
                    result = new SValue.dbl (n.get_hour () * 3600 + n.get_minute () * 60 + n.get_seconds ());
                    return true;
                case "year":
                case "month":
                case "day":
                case "hour":
                case "minute":
                case "second":
                    var v = arg (args, 0);
                    if (v.is_null) {
                        result = v;
                        return true;
                    }
                    int y, m, d, hh, mi, ss;
                    Script.split_serial (v.to_date (), out y, out m, out d, out hh, out mi, out ss);
                    switch (name) {
                        case "year": result = new SValue.int (y); break;
                        case "month": result = new SValue.int (m); break;
                        case "day": result = new SValue.int (d); break;
                        case "hour": result = new SValue.int (hh); break;
                        case "minute": result = new SValue.int (mi); break;
                        default: result = new SValue.int (ss); break;
                    }
                    return true;
                case "weekday":
                    var v = arg (args, 0);
                    if (v.is_null) {
                        result = v;
                        return true;
                    }
                    int fd = has (args, 1) ? (int) arg (args, 1).to_int () : 1;
                    result = new SValue.int (AccessFormat.weekday (v.to_date (), fd == 0 ? 1 : fd));
                    return true;
                case "weekdayname":
                    int wd = (int) arg (args, 0).to_int ();
                    bool abbrev = has (args, 1) && arg (args, 1).to_bool ();
                    int fd = has (args, 2) ? (int) arg (args, 2).to_int () : 1;
                    if (fd == 0) fd = 1;
                    result = new SValue.str (AccessFormat.day_name (((wd - 1 + fd - 1) % 7) + 1, abbrev));
                    return true;
                case "monthname":
                    result = new SValue.str (AccessFormat.month_name ((int) arg (args, 0).to_int (), has (args, 1) && arg (args, 1).to_bool ()));
                    return true;
                case "dateadd":
                    need (args, 3, name0);
                    var d = arg (args, 2);
                    if (d.is_null) {
                        result = d;
                        return true;
                    }
                    result = new SValue.date (date_add (arg (args, 0).to_text (), arg (args, 1).to_double (), d.to_date ()));
                    return true;
                case "datediff":
                    need (args, 3, name0);
                    var a = arg (args, 1), b = arg (args, 2);
                    if (a.is_null || b.is_null) {
                        result = new SValue.null ();
                        return true;
                    }
                    int fd = has (args, 3) ? (int) arg (args, 3).to_int () : 1;
                    result = new SValue.int (date_diff (arg (args, 0).to_text (), a.to_date (), b.to_date (), fd == 0 ? 1 : fd));
                    return true;
                case "datepart":
                    need (args, 2, name0);
                    var d = arg (args, 1);
                    if (d.is_null) {
                        result = d;
                        return true;
                    }
                    int fd = has (args, 2) ? (int) arg (args, 2).to_int () : 1;
                    result = new SValue.int (date_part (arg (args, 0).to_text (), d.to_date (), fd == 0 ? 1 : fd));
                    return true;
                case "dateserial":
                    need (args, 3, name0);
                    int y = (int) arg (args, 0).to_int ();
                    int m = (int) arg (args, 1).to_int ();
                    int d = (int) arg (args, 2).to_int ();
                    if (y >= 0 && y < 30) y += 2000;
                    else if (y >= 30 && y < 100) y += 1900;
                    int total = y * 12 + (m - 1);
                    int ny = (int) Math.floor (total / 12.0);
                    int nm = total - ny * 12 + 1;
                    result = new SValue.date (Script.make_serial (ny, nm, 1) + d - 1);
                    return true;
                case "timeserial":
                    need (args, 3, name0);
                    double secs = arg (args, 0).to_double () * 3600 + arg (args, 1).to_double () * 60 + arg (args, 2).to_double ();
                    result = new SValue.date (secs / 86400.0);
                    return true;
                case "rgb":
                    need (args, 3, name0);
                    result = new SValue.int ((arg (args, 0).to_int () & 255) | ((arg (args, 1).to_int () & 255) << 8) | ((arg (args, 2).to_int () & 255) << 16));
                    return true;
                case "qbcolor":
                    int64[] qb = { 0x000000, 0x800000, 0x008000, 0x808000, 0x000080, 0x800080, 0x008080, 0xC0C0C0, 0x808080, 0xFF0000, 0x00FF00, 0xFFFF00, 0x0000FF, 0xFF00FF, 0x00FFFF, 0xFFFFFF };
                    result = new SValue.int (qb[(int) arg (args, 0).to_int ().clamp (0, 15)]);
                    return true;
                case "environ":
                    string? e = Environment.get_variable (arg (args, 0).to_text ());
                    result = new SValue.str (e ?? "");
                    return true;
                case "msgbox":
                    string prompt = arg (args, 0).to_text ();
                    int buttons = has (args, 1) ? (int) arg (args, 1).to_int () : 0;
                    string title = has (args, 2) ? arg (args, 2).to_text () : _("Database");
                    int r = rt.host != null ? rt.host.message_box (prompt, buttons, title) : 1;
                    result = new SValue.int (r);
                    return true;
                case "inputbox":
                    string prompt = arg (args, 0).to_text ();
                    string title = has (args, 1) ? arg (args, 1).to_text () : _("Database");
                    string def = has (args, 2) ? arg (args, 2).to_text () : "";
                    string? r = rt.host != null ? rt.host.input_box (prompt, title, def) : def;
                    result = new SValue.str (r ?? "");
                    return true;
                case "beep":
                    if (rt.host != null) rt.host.run_command ("Beep", {}, {});
                    return true;
                case "eval":
                    result = rt.evaluate (arg (args, 0).to_text (), frame.context, frame.me);
                    return true;
                case "createobject":
                    result = rt.create_object (arg (args, 0).to_text ());
                    return true;
                case "dlookup":
                case "dcount":
                case "dsum":
                case "davg":
                case "dmin":
                case "dmax":
                case "dfirst":
                case "dlast":
                case "dstdev":
                case "dstdevp":
                case "dvar":
                case "dvarp":
                    need (args, 2, name0);
                    result = domain (rt, name, arg (args, 0).to_text (), arg (args, 1).to_text (), has (args, 2) ? arg (args, 2) : new SValue.empty ());
                    return true;
            }
            return false;
        }

        public static string proper (string t) {
            var sb = new StringBuilder ();
            bool start = true;
            int i = 0;
            unichar c;
            while (t.get_next_char (ref i, out c)) {
                if (c.isalnum ()) {
                    sb.append_unichar (start ? c.totitle () : c.tolower ());
                    start = false;
                } else {
                    sb.append_unichar (c);
                    start = true;
                }
            }
            return sb.str;
        }

        public static string domain_sql (string fn, string expr, string source, string crit) {
            string e = AccessSql.expression (expr);
            string agg;
            switch (fn) {
                case "dcount": agg = expr.strip () == "*" ? "count(*)" : "count(%s)".printf (e); break;
                case "dsum": agg = "sum(%s)".printf (e); break;
                case "davg": agg = "avg(%s)".printf (e); break;
                case "dmin": agg = "min(%s)".printf (e); break;
                case "dmax": agg = "max(%s)".printf (e); break;
                case "dfirst": agg = "first(%s)".printf (e); break;
                case "dlast": agg = "last(%s)".printf (e); break;
                case "dstdev": agg = "stdev(%s)".printf (e); break;
                case "dstdevp": agg = "stdevp(%s)".printf (e); break;
                case "dvar": agg = "var(%s)".printf (e); break;
                case "dvarp": agg = "varp(%s)".printf (e); break;
                default: agg = e; break;
            }
            string src = source.strip ();
            string from;
            if (src.down ().has_prefix ("select ")) from = "(%s)".printf (AccessSql.statement (src));
            else from = Sql.quote_ident (src.has_prefix ("[") && src.has_suffix ("]") ? src.substring (1, src.length - 2) : src);
            string sql = "SELECT %s FROM %s".printf (agg, from);
            if (crit.strip () != "") sql += " WHERE " + AccessSql.expression (crit.strip ());
            if (fn == "dlookup") sql += " LIMIT 1";
            return sql;
        }

        public static SValue domain (ScriptRuntime rt, string fn, string expr, string source, SValue criteria) throws ScriptError {
            if (rt.db == null) throw Script.fail (0, _("Domain functions need a database."));
            string sql = domain_sql (fn, expr, source, criteria.is_empty || criteria.is_null ? "" : criteria.to_text ());
            try {
                var rs = rt.db.query (sql);
                if (rs.rows.size == 0) return new SValue.null ();
                return SValue.from_db (rs.rows[0].get (0));
            } catch (Error err) {
                throw Script.fail (3075, _("%s could not be evaluated: %s").printf (fn, err.message));
            }
        }
    }
}
