namespace Singularity.Apps.Database {

    public class AccessFormat {
        private static string[] months () {
            return { _("January"), _("February"), _("March"), _("April"), _("May"), _("June"), _("July"), _("August"), _("September"), _("October"), _("November"), _("December") };
        }

        private static string[] days () {
            return { _("Sunday"), _("Monday"), _("Tuesday"), _("Wednesday"), _("Thursday"), _("Friday"), _("Saturday") };
        }

        public static string month_name (int m, bool abbrev) {
            if (m < 1 || m > 12) return "";
            string n = months ()[m - 1];
            return abbrev ? n.substring (0, n.index_of_nth_char (int.min (3, n.char_count ()))) : n;
        }

        public static string day_name (int wd, bool abbrev) {
            if (wd < 1 || wd > 7) return "";
            string n = days ()[wd - 1];
            return abbrev ? n.substring (0, n.index_of_nth_char (int.min (3, n.char_count ()))) : n;
        }

        public static int weekday (double serial, int first_day = 1) {
            int64 days = (int64) Math.floor (serial);
            int wd = (int) (((days - 1) % 7 + 7) % 7) + 1;
            return ((wd - first_day) % 7 + 7) % 7 + 1;
        }

        public static bool is_date_format (string fmt) {
            string f = fmt.down ();
            switch (f) {
                case "general date":
                case "long date":
                case "medium date":
                case "short date":
                case "long time":
                case "medium time":
                case "short time": return true;
            }
            bool quote = false;
            for (int i = 0; i < f.length; i++) {
                char c = f[i];
                if (c == '"') quote = !quote;
                if (quote) continue;
                if (c == '\\') {
                    i++;
                    continue;
                }
                if (c == 'd' || c == 'y' || c == 'h' || c == 'n' || c == 's' || c == 'w' || c == 'q' || c == 'm') {
                    if (c == 'm' && !f.contains ("d") && !f.contains ("y") && !f.contains ("h")) continue;
                    return true;
                }
            }
            return false;
        }

        public static string format (SValue value, string fmt) throws ScriptError {
            var v = value.resolved ();
            string f = fmt;
            string[] sections = split_sections (f);
            if (v.is_null) {
                if (sections.length >= 4) return render_literal (sections[3]);
                return "";
            }
            string low = f.strip ().down ();
            if (f.strip () == "") {
                if (v.kind == SKind.DATE) return Script.date_to_display (v.d);
                return v.to_text ();
            }
            switch (low) {
                case "general number":
                    return Script.format_double (v.to_double ());
                case "currency":
                    return Codec.format_currency (v.to_double (), 2);
                case "euro":
                    return "€" + Codec.format_number (v.to_double (), 2, true);
                case "fixed":
                    return Codec.format_number (v.to_double (), 2, false);
                case "standard":
                    return Codec.format_number (v.to_double (), 2, true);
                case "percent":
                    return Codec.format_number (v.to_double () * 100, 2, false) + "%";
                case "scientific":
                    return scientific (v.to_double (), 2);
                case "yes/no":
                    return truthy (v) ? _("Yes") : _("No");
                case "true/false":
                    return truthy (v) ? _("True") : _("False");
                case "on/off":
                    return truthy (v) ? _("On") : _("Off");
                case "general date":
                    return Script.date_to_display (v.to_date ());
                case "long date":
                    return date_pattern (v.to_date (), "dddd, mmmm d, yyyy");
                case "medium date":
                    return date_pattern (v.to_date (), "dd-mmm-yy");
                case "short date":
                    return date_pattern (v.to_date (), Locale.get ().day_first ? "dd/mm/yyyy" : "m/d/yyyy");
                case "long time":
                    return date_pattern (v.to_date (), "h:nn:ss AM/PM");
                case "medium time":
                    return date_pattern (v.to_date (), "hh:nn AM/PM");
                case "short time":
                    return date_pattern (v.to_date (), "hh:nn");
            }
            if (is_date_format (f) && (v.kind == SKind.DATE || v.kind == SKind.STRING || v.is_numeric ())) {
                double serial;
                try {
                    serial = v.to_date ();
                } catch (ScriptError e) {
                    return v.to_text ();
                }
                return date_pattern (serial, f);
            }
            if (is_text_format (f) || (v.kind == SKind.STRING && !v.looks_numeric ())) {
                return text_pattern (v.to_text (), sections[0]);
            }
            double x;
            try {
                x = v.to_double ();
            } catch (ScriptError e) {
                return text_pattern (v.to_text (), sections[0]);
            }
            string sec = sections[0];
            bool neg_section = false;
            if (x < 0 && sections.length >= 2 && sections[1] != "") {
                sec = sections[1];
                neg_section = true;
            } else if (x == 0 && sections.length >= 3 && sections[2] != "") {
                sec = sections[2];
            }
            string r = number_pattern (neg_section ? -x : x, sec);
            return r;
        }

        private static bool truthy (SValue v) {
            try {
                return v.to_bool ();
            } catch (ScriptError e) {
                return false;
            }
        }

        private static string scientific (double x, int decimals) {
            if (x == 0) return "0." + string.nfill (decimals, '0') + "E+00";
            int exp = (int) Math.floor (Math.log10 (Math.fabs (x)));
            double mant = x / Math.pow (10, exp);
            if (Math.fabs (Math.round (mant * Math.pow (10, decimals)) / Math.pow (10, decimals)) >= 10) {
                exp++;
                mant /= 10;
            }
            string m = "%.*f".printf (decimals, mant).replace (",", ".");
            if (Locale.get ().decimal_sep == ',') m = m.replace (".", ",");
            return "%sE%s%02d".printf (m, exp < 0 ? "-" : "+", exp.abs ());
        }

        private static string[] split_sections (string f) {
            string[] parts = {};
            var sb = new StringBuilder ();
            bool quote = false;
            for (int i = 0; i < f.length; i++) {
                char c = f[i];
                if (c == '"') quote = !quote;
                if (!quote && c == '\\' && i + 1 < f.length) {
                    sb.append_c (c);
                    sb.append_c (f[++i]);
                    continue;
                }
                if (!quote && c == ';') {
                    parts += sb.str;
                    sb.truncate ();
                    continue;
                }
                sb.append_c (c);
            }
            parts += sb.str;
            return parts;
        }

        private static string render_literal (string sec) {
            var sb = new StringBuilder ();
            bool quote = false;
            for (int i = 0; i < sec.length; i++) {
                char c = sec[i];
                if (c == '"') {
                    quote = !quote;
                    continue;
                }
                if (!quote && c == '\\' && i + 1 < sec.length) {
                    sb.append_c (sec[++i]);
                    continue;
                }
                sb.append_c (c);
            }
            return sb.str;
        }

        private static bool is_text_format (string f) {
            bool quote = false;
            for (int i = 0; i < f.length; i++) {
                char c = f[i];
                if (c == '"') quote = !quote;
                if (quote) continue;
                if (c == '\\') {
                    i++;
                    continue;
                }
                if (c == '@' || c == '&' || c == '<' || c == '>' || c == '!') return true;
                if (c == '0' || c == '#') return false;
            }
            return false;
        }

        public static string text_pattern (string text, string pattern) {
            int slots = 0;
            bool left_to_right = false;
            bool upper = false, lower = false;
            bool quote = false;
            for (int i = 0; i < pattern.length; i++) {
                char c = pattern[i];
                if (c == '"') {
                    quote = !quote;
                    continue;
                }
                if (quote) continue;
                if (c == '\\') {
                    i++;
                    continue;
                }
                if (c == '@' || c == '&') slots++;
                else if (c == '!') left_to_right = true;
                else if (c == '<') lower = true;
                else if (c == '>') upper = true;
            }
            string t = text;
            if (upper) t = text.up ();
            else if (lower) t = text.down ();
            if (slots == 0) return t;
            unichar[] chars = {};
            int ci = 0;
            unichar uc;
            while (t.get_next_char (ref ci, out uc)) chars += uc;
            int take_from = left_to_right ? 0 : int.max (0, chars.length - slots);
            string head = "";
            if (!left_to_right && chars.length > slots) {
                var hb = new StringBuilder ();
                for (int k = 0; k < chars.length - slots; k++) hb.append_unichar (chars[k]);
                head = hb.str;
            }
            var out_chars = new unichar?[slots];
            int avail = chars.length - (left_to_right ? 0 : take_from);
            if (left_to_right) {
                for (int k = 0; k < slots && k < chars.length; k++) out_chars[k] = chars[k];
            } else {
                int pad = slots - int.min (avail, slots);
                for (int k = 0; k < slots; k++) {
                    int src = take_from + k - pad;
                    if (k >= pad && src < chars.length) out_chars[k] = chars[src];
                }
            }
            var sb = new StringBuilder (head);
            int slot = 0;
            quote = false;
            for (int i = 0; i < pattern.length; i++) {
                char c = pattern[i];
                if (c == '"') {
                    quote = !quote;
                    continue;
                }
                if (quote) {
                    sb.append_c (c);
                    continue;
                }
                if (c == '\\' && i + 1 < pattern.length) {
                    sb.append_c (pattern[++i]);
                    continue;
                }
                if (c == '@' || c == '&') {
                    var ch = out_chars[slot++];
                    if (ch != null) sb.append_unichar (ch);
                    else if (c == '@') sb.append_c (' ');
                    continue;
                }
                if (c == '!' || c == '<' || c == '>') continue;
                sb.append_c (c);
            }
            if (left_to_right && chars.length > slots) {
                for (int k = slots; k < chars.length; k++) sb.append_unichar (chars[k]);
            }
            return sb.str;
        }

        public static string number_pattern (double x, string pattern) {
            string p = pattern;
            bool percent = false;
            bool quote = false;
            for (int i = 0; i < p.length; i++) {
                if (p[i] == '"') quote = !quote;
                else if (!quote && p[i] == '\\') i++;
                else if (!quote && p[i] == '%') percent = true;
            }
            double v = percent ? x * 100 : x;
            int int_zeros = 0, int_digits = 0, dec_zeros = 0, dec_hashes = 0;
            bool grouping = false, dot = false, sci = false;
            int sci_digits = 0;
            bool sci_plus = false;
            int first_ph = -1, last_ph = -1;
            quote = false;
            for (int i = 0; i < p.length; i++) {
                char c = p[i];
                if (c == '"') {
                    quote = !quote;
                    continue;
                }
                if (quote) continue;
                if (c == '\\') {
                    i++;
                    continue;
                }
                if (sci) {
                    if (c == '0' || c == '#') {
                        sci_digits++;
                        last_ph = i;
                    }
                    continue;
                }
                if (c == '0' || c == '#') {
                    if (first_ph < 0) first_ph = i;
                    last_ph = i;
                    if (dot) {
                        if (c == '0') dec_zeros = dec_zeros + dec_hashes + 1;
                        else dec_hashes++;
                    } else {
                        int_digits++;
                        if (c == '0') int_zeros++;
                    }
                } else if (c == '.' && !dot) {
                    dot = true;
                    if (first_ph < 0) first_ph = i;
                    last_ph = i;
                } else if (c == ',' && !dot && first_ph >= 0) {
                    grouping = true;
                } else if ((c == 'E' || c == 'e') && i + 1 < p.length && (p[i + 1] == '+' || p[i + 1] == '-')) {
                    sci = true;
                    sci_plus = p[i + 1] == '+';
                    i++;
                }
            }
            if (first_ph < 0) return render_literal (p);
            int decimals = dec_zeros + dec_hashes;
            string body;
            bool neg = v < 0;
            double av = Math.fabs (v);
            if (sci) {
                int exp = av == 0 ? 0 : (int) Math.floor (Math.log10 (av));
                double mant = av == 0 ? 0 : av / Math.pow (10, exp - (int_digits > 0 ? int_digits - 1 : 0));
                if (int_digits > 1) exp -= int_digits - 1;
                string ms = "%.*f".printf (decimals, mant).replace (",", ".");
                body = localize (ms, false, int_zeros) + "E" + (exp < 0 ? "-" : (sci_plus ? "+" : "")) + "%0*d".printf (int.max (1, sci_digits), exp.abs ());
            } else {
                string s = "%.*f".printf (decimals, av).replace (",", ".");
                int d = s.index_of (".");
                string ip = d >= 0 ? s.substring (0, d) : s;
                string fp = d >= 0 ? s.substring (d + 1) : "";
                while (fp.length > dec_zeros && fp.has_suffix ("0")) fp = fp.substring (0, fp.length - 1);
                if (ip == "0" && int_zeros == 0) ip = "";
                while (ip.length < int_zeros) ip = "0" + ip;
                if (grouping && ip != "") ip = Codec.group_digits (ip, Locale.get ().thousands_sep);
                body = ip;
                if (dot && (fp != "" || dec_zeros > 0 || decimals == 0)) {
                    if (fp != "" || dec_zeros > 0) body += Locale.get ().decimal_sep.to_string () + fp;
                    else if (decimals == 0 && dot && p.index_of (".") < last_ph) body += "";
                }
                if (dot && decimals == 0 && last_ph == p.index_of (".")) body += Locale.get ().decimal_sep.to_string ();
            }
            var sb = new StringBuilder ();
            bool placed = false;
            quote = false;
            for (int i = 0; i < p.length; i++) {
                char c = p[i];
                if (c == '"') {
                    quote = !quote;
                    continue;
                }
                if (quote) {
                    sb.append_c (c);
                    continue;
                }
                if (c == '\\' && i + 1 < p.length) {
                    sb.append_c (p[++i]);
                    continue;
                }
                if (i >= first_ph && i <= last_ph) {
                    if (!placed) {
                        if (neg) sb.append_c ('-');
                        sb.append (body);
                        placed = true;
                    }
                    continue;
                }
                if (sci && (c == 'E' || c == 'e' || c == '+' || c == '-') && i > first_ph && i <= last_ph + 1) continue;
                if (c == ',' && i > first_ph && i < last_ph) continue;
                if (c == '$') {
                    sb.append (Locale.get ().currency);
                    continue;
                }
                sb.append_c (c);
            }
            return sb.str;
        }

        private static string localize (string s, bool grouping, int min_int) {
            string r = s;
            if (Locale.get ().decimal_sep == ',') r = r.replace (".", ",");
            return r;
        }

        public static string date_pattern (double serial, string pattern) {
            int y, m, d, hh, mm, ss;
            Script.split_serial (serial, out y, out m, out d, out hh, out mm, out ss);
            string low = pattern.down ();
            bool ampm = low.contains ("am/pm") || low.contains ("a/p") || low.contains ("ampm");
            var sb = new StringBuilder ();
            int i = 0;
            int n = pattern.length;
            bool last_was_hour = false;
            while (i < n) {
                char c = pattern[i];
                char lc = c.tolower ();
                if (c == '"') {
                    int close = pattern.index_of_char ('"', i + 1);
                    if (close < 0) close = n;
                    sb.append (pattern.substring (i + 1, close - i - 1));
                    i = close + 1;
                    continue;
                }
                if (c == '\\' && i + 1 < n) {
                    sb.append_c (pattern[i + 1]);
                    i += 2;
                    continue;
                }
                int run = 1;
                while (i + run < n && pattern[i + run].tolower () == lc) run++;
                if (lc == 'a' && (low.substring (i).has_prefix ("am/pm") || low.substring (i).has_prefix ("a/p") || low.substring (i).has_prefix ("ampm"))) {
                    string rest = pattern.substring (i);
                    bool is_upper = rest[0] == 'A';
                    if (low.substring (i).has_prefix ("am/pm")) {
                        string t = hh < 12 ? "AM" : "PM";
                        sb.append (is_upper ? t : t.down ());
                        i += 5;
                    } else if (low.substring (i).has_prefix ("ampm")) {
                        sb.append (hh < 12 ? "AM" : "PM");
                        i += 4;
                    } else {
                        string t = hh < 12 ? "A" : "P";
                        sb.append (is_upper ? t : t.down ());
                        i += 3;
                    }
                    continue;
                }
                switch (lc) {
                    case 'y':
                        if (run >= 3) sb.append ("%04d".printf (y));
                        else if (run == 2) sb.append ("%02d".printf (y % 100));
                        else sb.append (((int) (serial - Script.make_serial (y, 1, 1)) + 1).to_string ());
                        break;
                    case 'm':
                        if (last_was_hour || (run <= 2 && next_is_seconds (low, i + run))) {
                            sb.append (run >= 2 ? "%02d".printf (mm) : mm.to_string ());
                        } else if (run >= 4) sb.append (month_name (m, false));
                        else if (run == 3) sb.append (month_name (m, true));
                        else if (run == 2) sb.append ("%02d".printf (m));
                        else sb.append (m.to_string ());
                        break;
                    case 'd':
                        if (run >= 6) sb.append (date_pattern (serial, "dddd, mmmm d, yyyy"));
                        else if (run == 5) sb.append (date_pattern (serial, Locale.get ().day_first ? "dd/mm/yyyy" : "m/d/yyyy"));
                        else if (run == 4) sb.append (day_name (weekday (serial), false));
                        else if (run == 3) sb.append (day_name (weekday (serial), true));
                        else if (run == 2) sb.append ("%02d".printf (d));
                        else sb.append (d.to_string ());
                        break;
                    case 'w':
                        if (run >= 2) sb.append (week_of_year (serial).to_string ());
                        else sb.append (weekday (serial).to_string ());
                        break;
                    case 'q':
                        sb.append (((m - 1) / 3 + 1).to_string ());
                        break;
                    case 'h':
                        int h12 = hh;
                        if (ampm) {
                            h12 = hh % 12;
                            if (h12 == 0) h12 = 12;
                        }
                        sb.append (run >= 2 ? "%02d".printf (h12) : h12.to_string ());
                        break;
                    case 'n':
                        sb.append (run >= 2 ? "%02d".printf (mm) : mm.to_string ());
                        break;
                    case 's':
                        sb.append (run >= 2 ? "%02d".printf (ss) : ss.to_string ());
                        break;
                    case 't':
                        if (run >= 5) {
                            sb.append (date_pattern (serial, "h:nn:ss AM/PM"));
                            break;
                        }
                        for (int k = 0; k < run; k++) sb.append_c (c);
                        break;
                    case 'c':
                        sb.append (Script.date_to_display (serial));
                        break;
                    default:
                        for (int k = 0; k < run; k++) sb.append_c (c);
                        break;
                }
                last_was_hour = lc == 'h' || (last_was_hour && (c == ':' || c == ' '));
                if (lc != 'h' && c != ':' && c != ' ') last_was_hour = false;
                i += run;
            }
            return sb.str;
        }

        private static bool next_is_seconds (string low, int from) {
            int i = from;
            while (i < low.length && (low[i] == ':' || low[i] == ' ' || low[i] == '.')) i++;
            return i < low.length && low[i] == 's';
        }

        public static int week_of_year (double serial, int first_day = 1) {
            int y, m, d, hh, mm, ss;
            Script.split_serial (serial, out y, out m, out d, out hh, out mm, out ss);
            double jan1 = Script.make_serial (y, 1, 1);
            int offset = weekday (jan1, first_day) - 1;
            return (int) ((Math.floor (serial) - jan1 + offset) / 7) + 1;
        }
    }
}
