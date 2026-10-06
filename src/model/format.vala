namespace Singularity.Apps.Database {

    public errordomain InputError {
        INVALID
    }

    public class Locale {
        public char decimal_sep = '.';
        public char thousands_sep = ',';
        public bool day_first = false;
        public string currency = "$";
        public bool currency_after = false;

        private static Locale? instance;

        public static Locale get () {
            if (instance == null) instance = detect ();
            return instance;
        }

        public static void set_default (Locale l) {
            instance = l;
        }

        public static Locale neutral () {
            var l = new Locale ();
            l.day_first = false;
            return l;
        }

        private static Locale detect () {
            var l = new Locale ();
            string lang = Intl.setlocale (LocaleCategory.NUMERIC, null) ?? "C";
            string sample = "%.1f".printf (1.5);
            if (sample.contains (",")) {
                l.decimal_sep = ',';
                l.thousands_sep = '.';
                l.currency = "€";
                l.currency_after = true;
            }
            string tl = Intl.setlocale (LocaleCategory.TIME, null) ?? lang;
            if (!(tl.has_prefix ("en_US") || tl == "C" || tl == "POSIX" || tl.has_prefix ("C."))) l.day_first = true;
            if (tl.has_prefix ("en_GB") || tl.has_prefix ("en_IE")) l.currency = "£";
            if (tl.has_prefix ("en_GB")) {
                l.currency_after = false;
            }
            return l;
        }

        public string date_pattern () {
            return day_first ? "%d/%m/%Y" : "%m/%d/%Y";
        }
    }

    public class Codec {
        public static bool decimal_int (string s, out int value) {
            value = 0;
            string t = s.strip ();
            if (t == "" || t.length > 9) return false;
            int v = 0;
            for (int i = 0; i < t.length; i++) {
                if (!t[i].isdigit ()) return false;
                v = v * 10 + (t[i] - '0');
            }
            value = v;
            return true;
        }

        public static string group_digits (string integer_part, char sep) {
            bool neg = integer_part.has_prefix ("-");
            string digits = neg ? integer_part.substring (1) : integer_part;
            var sb = new StringBuilder ();
            int n = digits.length;
            for (int i = 0; i < n; i++) {
                if (i > 0 && (n - i) % 3 == 0) sb.append_c (sep);
                sb.append_c (digits[i]);
            }
            return (neg ? "-" : "") + sb.str;
        }

        public static string format_number (double v, int decimals, bool grouping) {
            var loc = Locale.get ();
            string s;
            if (decimals < 0) {
                s = "%.12g".printf (v).replace (",", ".");
                if (s.contains ("e") && Math.fabs (v) >= 1e-4 && Math.fabs (v) < 1e15) s = DbValue.format_real (v);
                if (s.contains ("e")) return s;
            } else {
                s = "%.*f".printf (decimals, v);
                s = s.replace (",", ".");
            }
            int dot = s.index_of (".");
            string ip = dot >= 0 ? s.substring (0, dot) : s;
            string fp = dot >= 0 ? s.substring (dot + 1) : "";
            if (grouping) ip = group_digits (ip, loc.thousands_sep);
            return fp != "" ? "%s%c%s".printf (ip, loc.decimal_sep, fp) : ip;
        }

        public static string format_currency (double v, int decimals) {
            var loc = Locale.get ();
            int d = decimals < 0 ? 2 : decimals;
            string n = format_number (Math.fabs (v), d, true);
            string sign = v < 0 ? "-" : "";
            return loc.currency_after ? "%s%s %s".printf (sign, n, loc.currency) : "%s%s%s".printf (sign, loc.currency, n);
        }

        public static bool parse_number (string input, out double result) {
            result = 0;
            var loc = Locale.get ();
            string s = input.strip ().replace (" ", "").replace (" ", "").replace (" ", "");
            foreach (string sym in new string[] { loc.currency, "$", "€", "£", "¥", "%" }) s = s.replace (sym, "");
            if (s == "") return false;
            bool neg = false;
            if (s.has_prefix ("(") && s.has_suffix (")")) {
                neg = true;
                s = s.substring (1, s.length - 2);
            }
            int last_dot = s.last_index_of (".");
            int last_comma = s.last_index_of (",");
            if (last_dot >= 0 && last_comma >= 0) {
                if (last_comma > last_dot) s = s.replace (".", "").replace (",", ".");
                else s = s.replace (",", "");
            } else if (last_comma >= 0) {
                int commas = s.split (",").length - 1;
                string after = s.substring (last_comma + 1);
                if (loc.decimal_sep == ',' || (commas == 1 && after.length != 3)) s = s.replace (",", ".");
                else s = s.replace (",", "");
            } else if (last_dot >= 0 && loc.decimal_sep == ',') {
                int dots = s.split (".").length - 1;
                string after = s.substring (last_dot + 1);
                if (dots > 1 || after.length == 3) s = s.replace (".", "");
            }
            double v;
            if (!double.try_parse (s, out v)) return false;
            result = neg ? -v : v;
            return true;
        }

        private static bool valid_ymd (int y, int m, int d) {
            if (m < 1 || m > 12 || d < 1 || y < 1 || y > 9999) return false;
            return d <= ((DateMonth) m).get_days_in_month ((DateYear) y);
        }

        public static bool parse_date (string input, out string iso) {
            iso = "";
            string s = input.strip ();
            if (s == "") return false;
            string low = s.down ();
            var now = new DateTime.now_local ();
            if (low == "today" || low == "date()" || low == "now") {
                iso = now.format ("%Y-%m-%d");
                return true;
            }
            if (low == "tomorrow") {
                iso = now.add_days (1).format ("%Y-%m-%d");
                return true;
            }
            if (low == "yesterday") {
                iso = now.add_days (-1).format ("%Y-%m-%d");
                return true;
            }
            string d = s;
            int sp = d.index_of_char (' ');
            int tpos = d.index_of_char ('T');
            if (tpos == 10) d = d.substring (0, 10);
            else if (sp > 0) d = d.substring (0, sp);
            string[] parts;
            if (d.contains ("-")) parts = d.split ("-");
            else if (d.contains ("/")) parts = d.split ("/");
            else if (d.contains (".")) parts = d.split (".");
            else return false;
            if (parts.length != 3) return false;
            foreach (string p in parts) {
                int tmp;
                if (!decimal_int (p, out tmp)) return false;
            }
            int a = int.parse (parts[0]), b = int.parse (parts[1]), c = int.parse (parts[2]);
            int y, m, dd;
            if (parts[0].length == 4) {
                y = a;
                m = b;
                dd = c;
            } else {
                y = c;
                if (parts[2].length <= 2) y += y < 50 ? 2000 : 1900;
                if (Locale.get ().day_first) {
                    dd = a;
                    m = b;
                } else {
                    m = a;
                    dd = b;
                }
                if (m > 12 && dd <= 12) {
                    int t = m;
                    m = dd;
                    dd = t;
                }
            }
            if (!valid_ymd (y, m, dd)) return false;
            iso = "%04d-%02d-%02d".printf (y, m, dd);
            return true;
        }

        public static bool parse_time (string input, out string iso) {
            iso = "";
            string s = input.strip ().down ();
            bool pm = false, am = false;
            if (s.has_suffix ("pm")) {
                pm = true;
                s = s.substring (0, s.length - 2).strip ();
            } else if (s.has_suffix ("am")) {
                am = true;
                s = s.substring (0, s.length - 2).strip ();
            }
            string[] parts = s.split (":");
            if (parts.length < 2 || parts.length > 3) return false;
            int h = 0, m = 0, sec = 0;
            if (!decimal_int (parts[0], out h) || !decimal_int (parts[1], out m)) return false;
            if (parts.length == 3) {
                double fs;
                if (!double.try_parse (parts[2], out fs)) return false;
                sec = (int) fs;
            }
            if (pm && h < 12) h += 12;
            if (am && h == 12) h = 0;
            if (h < 0 || h > 23 || m < 0 || m > 59 || sec < 0 || sec > 59) return false;
            iso = "%02d:%02d:%02d".printf (h, m, sec);
            return true;
        }

        public static bool parse_datetime (string input, out string iso) {
            iso = "";
            string s = input.strip ().replace ("T", " ");
            if (s.has_suffix ("Z")) s = s.substring (0, s.length - 1);
            if (s.down () == "now") {
                iso = new DateTime.now_local ().format ("%Y-%m-%d %H:%M:%S");
                return true;
            }
            int sp = s.index_of_char (' ');
            string date_part = sp > 0 ? s.substring (0, sp) : s;
            string time_part = sp > 0 ? s.substring (sp + 1) : "";
            string di, ti = "00:00:00";
            if (!parse_date (date_part, out di)) return false;
            if (time_part.strip () != "") {
                int dot = time_part.index_of_char ('.');
                string tp = dot > 0 && !time_part.contains ("m") ? time_part.substring (0, dot) : time_part;
                int plus = tp.index_of_char ('+');
                if (plus > 0) tp = tp.substring (0, plus);
                if (!parse_time (tp, out ti)) return false;
            }
            iso = di + " " + ti;
            return true;
        }

        public static DbValue parse (Field f, string input) throws InputError {
            if (f.is_calculated ()) throw new InputError.INVALID (_("\"%s\" is calculated and cannot be edited.").printf (f.label ()));
            if (f.multi_value) return MultiValue.parse (f, input);
            if (f.input_mask != "" && input.strip () != "") {
                var mask = InputMask.parse (f.input_mask);
                if (mask != null && !mask.password) {
                    string stored = mask.apply (input);
                    if (f.field_type.is_text ()) return new DbValue.text (stored);
                    input = stored;
                }
            }
            string s = input;
            if (f.field_type != FieldType.LONG_TEXT && f.field_type != FieldType.TEXT) s = input.strip ();
            if (s == "") {
                if (f.field_type.is_text ()) return f.required ? new DbValue.text ("") : new DbValue.null ();
                return new DbValue.null ();
            }
            double num;
            string iso;
            switch (f.field_type) {
                case FieldType.AUTONUMBER:
                case FieldType.INTEGER:
                case FieldType.LOOKUP:
                    if (!parse_number (s, out num) || num != Math.floor (num)) throw new InputError.INVALID (_("\"%s\" is not a whole number.").printf (s));
                    return new DbValue.int ((int64) num);
                case FieldType.NUMBER:
                case FieldType.CURRENCY:
                    if (!parse_number (s, out num)) throw new InputError.INVALID (_("\"%s\" is not a number.").printf (s));
                    return new DbValue.real (num);
                case FieldType.PERCENT:
                    if (!parse_number (s, out num)) throw new InputError.INVALID (_("\"%s\" is not a percentage.").printf (s));
                    return new DbValue.real (s.contains ("%") || Math.fabs (num) > 1 ? num / 100.0 : num);
                case FieldType.DATE:
                    if (!parse_date (s, out iso)) throw new InputError.INVALID (_("\"%s\" is not a date.").printf (s));
                    return new DbValue.text (iso);
                case FieldType.DATETIME:
                    if (!parse_datetime (s, out iso)) throw new InputError.INVALID (_("\"%s\" is not a date and time.").printf (s));
                    return new DbValue.text (iso);
                case FieldType.TIME:
                    if (!parse_time (s, out iso)) throw new InputError.INVALID (_("\"%s\" is not a time.").printf (s));
                    return new DbValue.text (iso);
                case FieldType.BOOLEAN:
                    return new DbValue.bool (new DbValue.text (s).as_bool ());
                case FieldType.CHOICE:
                    foreach (string c in f.choices) {
                        if (c.casefold () == s.casefold ()) return new DbValue.text (c);
                    }
                    throw new InputError.INVALID (_("\"%s\" is not one of the choices.").printf (s));
                case FieldType.EMAIL:
                    if (!s.contains ("@") || s.contains (" ")) throw new InputError.INVALID (_("\"%s\" is not an email address.").printf (s));
                    return new DbValue.text (s);
                case FieldType.ATTACHMENT:
                    throw new InputError.INVALID (_("Attachments are added from a file."));
                default:
                    if (f.max_length > 0 && s.char_count () > f.max_length) throw new InputError.INVALID (_("The text is longer than %d characters.").printf (f.max_length));
                    return new DbValue.text (s);
            }
        }

        public static string display (Field? f, DbValue v) {
            if (v.is_null) return "";
            if (f == null) return v.to_string ();
            if (f.multi_value) return string.joinv ("; ", MultiValue.items (v));
            if (f.rich_text && v.kind == ValueKind.TEXT) return RichText.to_plain (v.text_value);
            if (f.format != "" && f.field_type != FieldType.ATTACHMENT) {
                try {
                    return AccessFormat.format (SValue.from_db (v, f.field_type), f.format);
                } catch (ScriptError e) {
                }
            }
            if (f.input_mask != "" && v.kind == ValueKind.TEXT) {
                var mask = InputMask.parse (f.input_mask);
                if (mask != null) return mask.display (v.text_value);
            }
            switch (f.field_type) {
                case FieldType.CURRENCY:
                    if (v.is_number () || v.kind == ValueKind.TEXT) return format_currency (v.as_double (), f.decimals);
                    break;
                case FieldType.NUMBER:
                    if (v.is_number ()) return format_number (v.as_double (), f.decimals, true);
                    break;
                case FieldType.INTEGER:
                    if (v.is_number ()) return format_number (v.as_double (), 0, true);
                    break;
                case FieldType.PERCENT:
                    if (v.is_number ()) return format_number (v.as_double () * 100, f.decimals < 0 ? 0 : f.decimals, true) + "%";
                    break;
                case FieldType.DATE:
                    return display_date (v.to_string ());
                case FieldType.DATETIME:
                    string s = v.to_string ();
                    if (s.length >= 16) return display_date (s.substring (0, 10)) + " " + s.substring (11, 5);
                    return display_date (s);
                case FieldType.TIME:
                    string t = v.to_string ();
                    return t.length >= 5 ? t.substring (0, 5) : t;
                case FieldType.BOOLEAN:
                    return v.as_bool () ? _("Yes") : _("No");
                case FieldType.ATTACHMENT:
                    if (v.kind == ValueKind.BLOB) return Attachment.describe (v.blob_value);
                    break;
                default:
                    break;
            }
            return v.to_string ();
        }

        public static string display_date (string iso) {
            if (iso.length < 10) return iso;
            int y = int.parse (iso.substring (0, 4)), m = int.parse (iso.substring (5, 2)), d = int.parse (iso.substring (8, 2));
            if (!valid_ymd (y, m, d)) return iso;
            return Locale.get ().day_first ? "%02d/%02d/%04d".printf (d, m, y) : "%02d/%02d/%04d".printf (m, d, y);
        }

        public static string edit_text (Field? f, DbValue v) {
            if (v.is_null) return "";
            if (f == null) return v.to_string ();
            if (f.multi_value) return string.joinv ("; ", MultiValue.items (v));
            if (f.input_mask != "" && v.kind == ValueKind.TEXT) {
                var mask = InputMask.parse (f.input_mask);
                if (mask != null && !mask.password) return mask.display (v.text_value);
            }
            switch (f.field_type) {
                case FieldType.NUMBER:
                case FieldType.CURRENCY:
                    return format_number (v.as_double (), -1, false);
                case FieldType.PERCENT:
                    return format_number (v.as_double () * 100, -1, false) + "%";
                case FieldType.DATE:
                case FieldType.DATETIME:
                    return display (f, v);
                case FieldType.TIME:
                    return v.to_string ();
                case FieldType.BOOLEAN:
                    return v.as_bool () ? _("Yes") : _("No");
                default:
                    return v.to_string ();
            }
        }

        public static FieldType infer (Gee.List<string> samples) {
            int n = 0, ints = 0, nums = 0, dates = 0, datetimes = 0, bools = 0, emails = 0, urls = 0, currencies = 0, percents = 0, longs = 0;
            var distinct = new Gee.HashSet<string> ();
            foreach (string raw in samples) {
                string s = raw.strip ();
                if (s == "") continue;
                n++;
                distinct.add (s);
                double d;
                string iso;
                if (s.length > 255 || s.contains ("\n")) longs++;
                string low = s.down ();
                if (low == "true" || low == "false" || low == "yes" || low == "no") bools++;
                if (parse_number (s, out d)) {
                    nums++;
                    if (d == Math.floor (d) && !s.contains (".") && !s.contains (",") && s.length < 16) ints++;
                    if (s.contains ("$") || s.contains ("€") || s.contains ("£")) currencies++;
                    if (s.has_suffix ("%")) percents++;
                } else if (s.length >= 8 && parse_date (s, out iso)) {
                    if (s.contains (":")) datetimes++;
                    else dates++;
                } else if (s.contains ("@") && !s.contains (" ")) {
                    emails++;
                } else if (low.has_prefix ("http://") || low.has_prefix ("https://")) {
                    urls++;
                }
            }
            if (n == 0) return FieldType.TEXT;
            if (bools == n) return FieldType.BOOLEAN;
            if (currencies == n) return FieldType.CURRENCY;
            if (percents == n) return FieldType.PERCENT;
            if (ints == n) return FieldType.INTEGER;
            if (nums == n) return FieldType.NUMBER;
            if (dates == n) return FieldType.DATE;
            if (dates + datetimes == n) return FieldType.DATETIME;
            if (emails == n) return FieldType.EMAIL;
            if (urls == n) return FieldType.URL;
            if (longs > 0) return FieldType.LONG_TEXT;
            return FieldType.TEXT;
        }
    }

    public class Attachment {
        public static Bytes pack (string filename, string mime, Bytes content) {
            var b = new ByteArray ();
            b.append ("SDBA1\n".data);
            b.append ((filename.replace ("\n", " ") + "\n").data);
            b.append ((mime.replace ("\n", " ") + "\n").data);
            b.append (content.get_data ());
            return ByteArray.free_to_bytes (b);
        }

        public static bool unpack (Bytes data, out string filename, out string mime, out Bytes content) {
            filename = "";
            mime = "application/octet-stream";
            content = data;
            unowned uint8[] d = data.get_data ();
            if (d.length >= 6 && Memory.cmp (d, "SDBA2\n".data, 6) == 0) {
                var all = unpack_all (data);
                if (all.size == 0) return false;
                filename = all[0].name;
                mime = all[0].mime;
                content = all[0].content;
                return true;
            }
            if (d.length < 8 || Memory.cmp (d, "SDBA1\n".data, 6) != 0) return false;
            int p = 6;
            int nl1 = -1, nl2 = -1;
            for (int i = p; i < d.length; i++) {
                if (d[i] == '\n') {
                    if (nl1 < 0) nl1 = i;
                    else {
                        nl2 = i;
                        break;
                    }
                }
            }
            if (nl1 < 0 || nl2 < 0) return false;
            var sb = new StringBuilder ();
            sb.append_len ((string) ((uint8*) d + p), nl1 - p);
            filename = sb.str;
            sb.truncate ();
            sb.append_len ((string) ((uint8*) d + nl1 + 1), nl2 - nl1 - 1);
            mime = sb.str;
            content = new Bytes.from_bytes (data, nl2 + 1, d.length - nl2 - 1);
            return true;
        }

        public static Bytes pack_many (Gee.List<AttachmentFile> files) {
            if (files.size == 1) return pack (files[0].name, files[0].mime, files[0].content);
            var b = new ByteArray ();
            b.append ("SDBA2\n".data);
            b.append ("%d\n".printf (files.size).data);
            foreach (var f in files) {
                b.append ((f.name.replace ("\n", " ") + "\n").data);
                b.append ((f.mime.replace ("\n", " ") + "\n").data);
                b.append ("%zu\n".printf (f.content.get_size ()).data);
                b.append (f.content.get_data ());
            }
            return ByteArray.free_to_bytes (b);
        }

        public static Gee.ArrayList<AttachmentFile> unpack_all (Bytes? data) {
            var list = new Gee.ArrayList<AttachmentFile> ();
            if (data == null || data.get_size () == 0) return list;
            unowned uint8[] d = data.get_data ();
            if (d.length >= 6 && Memory.cmp (d, "SDBA2\n".data, 6) == 0) {
                int p = 6;
                string? count_s = read_line (d, ref p);
                int count = count_s != null ? int.parse (count_s) : 0;
                for (int i = 0; i < count; i++) {
                    string? name = read_line (d, ref p);
                    string? mime = read_line (d, ref p);
                    string? size_s = read_line (d, ref p);
                    if (name == null || mime == null || size_s == null) break;
                    int64 size = int64.parse (size_s);
                    if (size < 0 || p + size > d.length) break;
                    list.add (new AttachmentFile (name, mime, new Bytes.from_bytes (data, p, (size_t) size)));
                    p += (int) size;
                }
                return list;
            }
            string n, m;
            Bytes c;
            if (unpack (data, out n, out m, out c)) list.add (new AttachmentFile (n, m, c));
            else list.add (new AttachmentFile (_("File"), "application/octet-stream", data));
            return list;
        }

        private static string? read_line (uint8[] d, ref int p) {
            int start = p;
            while (p < d.length && d[p] != '\n') p++;
            if (p >= d.length) return null;
            var sb = new StringBuilder ();
            sb.append_len ((string) ((uint8*) d + start), p - start);
            p++;
            return sb.str;
        }

        public static string describe (Bytes data) {
            unowned uint8[] raw = data.get_data ();
            if (raw.length >= 6 && Memory.cmp (raw, "SDBA2\n".data, 6) == 0) {
                var all = unpack_all (data);
                if (all.size == 1) return "%s (%s)".printf (all[0].name, format_size (all[0].content.get_size ()));
                string[] names = {};
                foreach (var f in all) names += f.name;
                return ngettext ("%d file: %s", "%d files: %s", all.size).printf (all.size, string.joinv (", ", names));
            }
            string name, mime;
            Bytes content;
            if (unpack (data, out name, out mime, out content)) return "%s (%s)".printf (name, format_size (content.get_size ()));
            return format_size (data.get_size ());
        }
    }
}

namespace Singularity.Apps.Database {

    public class AttachmentFile {
        public string name;
        public string mime;
        public Bytes content;

        public AttachmentFile (string name, string mime, Bytes content) {
            this.name = name;
            this.mime = mime;
            this.content = content;
        }
    }

    public class MultiValue {
        public static string[] items (DbValue v) {
            string[] list = {};
            if (v.is_null) return list;
            string t = v.to_string ().strip ();
            if (t.has_prefix ("[")) {
                try {
                    var p = new Json.Parser ();
                    p.load_from_data (t);
                    var arr = p.get_root ().get_array ();
                    for (uint i = 0; i < arr.get_length (); i++) {
                        var n = arr.get_element (i);
                        if (n.get_value_type () == typeof (string)) list += n.get_string ();
                        else if (n.get_value_type () == typeof (int64)) list += n.get_int ().to_string ();
                        else if (n.get_value_type () == typeof (double)) list += DbValue.format_real (n.get_double ());
                        else list += n.get_string () ?? "";
                    }
                    return list;
                } catch (Error e) {
                }
            }
            if (t != "") list += t;
            return list;
        }

        public static string encode (string[] values) {
            var b = new Json.Builder ();
            b.begin_array ();
            foreach (string s in values) b.add_string_value (s);
            b.end_array ();
            return Json.to_string (b.get_root (), false);
        }

        public static DbValue parse (Field f, string input) throws InputError {
            string[] parts = {};
            foreach (string raw in input.split (";")) {
                string p = raw.strip ();
                if (p == "") continue;
                if (f.field_type == FieldType.CHOICE && f.choices.length > 0) {
                    string? hit = null;
                    foreach (string c in f.choices) {
                        if (c.casefold () == p.casefold ()) hit = c;
                    }
                    if (hit == null) throw new InputError.INVALID (_("\"%s\" is not one of the choices.").printf (p));
                    p = hit;
                }
                bool dup = false;
                foreach (string e in parts) {
                    if (e == p) dup = true;
                }
                if (!dup) parts += p;
            }
            if (parts.length == 0) return new DbValue.null ();
            return new DbValue.text (encode (parts));
        }

        public static DbValue from_list (string[] values) {
            if (values.length == 0) return new DbValue.null ();
            return new DbValue.text (encode (values));
        }
    }

    public class RichText {
        public static string to_plain (string html) {
            if (!html.contains ("<")) return html;
            string t = html.replace ("<br>", "\n").replace ("<br/>", "\n").replace ("<br />", "\n").replace ("</div>", "\n").replace ("</p>", "\n");
            try {
                var re = new Regex ("<[^>]*>");
                t = re.replace (t, -1, 0, "");
            } catch (RegexError e) {
            }
            t = t.replace ("&nbsp;", " ").replace ("&lt;", "<").replace ("&gt;", ">").replace ("&quot;", "\"").replace ("&#39;", "'").replace ("&amp;", "&");
            return t.strip ();
        }

        public static string to_markup (string html) {
            if (!html.contains ("<")) return Markup.escape_text (html);
            string t = html;
            string[,] map = {
                { "<strong>", "<b>" }, { "</strong>", "</b>" }, { "<em>", "<i>" }, { "</em>", "</i>" },
                { "<br>", "\n" }, { "<br/>", "\n" }, { "<br />", "\n" }, { "<div>", "" }, { "</div>", "\n" },
                { "<p>", "" }, { "</p>", "\n" }
            };
            for (int i = 0; i < map.length[0]; i++) t = t.replace (map[i, 0], map[i, 1]);
            try {
                var fontre = new Regex ("<font color=[\"']?(#[0-9A-Fa-f]{6})[\"']?>");
                t = fontre.replace (t, -1, 0, "<span foreground=\"\\1\">");
                t = t.replace ("</font>", "</span>");
                var other = new Regex ("<(?!/?(b|i|u|s|span)[ >])[^>]*>");
                t = other.replace (t, -1, 0, "");
            } catch (RegexError e) {
            }
            t = t.replace ("&nbsp;", " ");
            string checked;
            try {
                Pango.parse_markup (t, -1, 0, null, out checked, null);
                return t.strip ();
            } catch (Error e) {
                return Markup.escape_text (to_plain (html));
            }
        }
    }
}
