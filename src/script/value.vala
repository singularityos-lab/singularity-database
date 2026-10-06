namespace Singularity.Apps.Database {

    public errordomain ScriptError {
        SYNTAX,
        RUNTIME,
        CANCELLED
    }

    public enum SKind {
        EMPTY,
        NULL,
        BOOL,
        INT,
        DOUBLE,
        STRING,
        DATE,
        OBJECT,
        ARRAY,
        NOTHING
    }

    public class SArray {
        public Gee.ArrayList<SValue> items = new Gee.ArrayList<SValue> ();
        public int lower;
        public int[] dims = {};

        public SArray (int lower, int upper) {
            this.lower = lower;
            for (int i = lower; i <= upper; i++) items.add (new SValue.empty ());
            dims = { upper - lower + 1 };
        }

        public SArray.from_list (Gee.List<SValue> list) {
            lower = 0;
            items.add_all (list);
            dims = { list.size };
        }

        public int upper {
            get { return lower + items.size - 1; }
        }

        public void resize (int upper, bool preserve) {
            int n = int.max (0, upper - lower + 1);
            if (!preserve) items.clear ();
            while (items.size > n) items.remove_at (items.size - 1);
            while (items.size < n) items.add (new SValue.empty ());
            dims = { n };
        }

        public SValue get_at (int index) throws ScriptError {
            int i = index - lower;
            if (i < 0 || i >= items.size) throw Script.fail (9, _("Subscript out of range"));
            return items[i];
        }

        public void set_at (int index, SValue v) throws ScriptError {
            int i = index - lower;
            if (i < 0 || i >= items.size) throw Script.fail (9, _("Subscript out of range"));
            items[i] = v;
        }
    }

    public abstract class ScriptObject : Object {
        public virtual string type_name () {
            return "Object";
        }

        public virtual bool has_member (string name) {
            return false;
        }

        public virtual SValue get_member (string name, SValue[] args) throws ScriptError {
            throw Script.fail (438, _("The object does not support \"%s\".").printf (name));
        }

        public virtual void set_member (string name, SValue[] args, SValue value) throws ScriptError {
            throw Script.fail (438, _("The object does not support \"%s\".").printf (name));
        }

        public virtual SValue call_method (string name, SValue[] args, string[] names) throws ScriptError {
            return get_member (name, args);
        }

        public virtual SValue get_default (SValue[] args) throws ScriptError {
            throw Script.fail (438, _("The object has no default value."));
        }

        public virtual void set_default (SValue[] args, SValue value) throws ScriptError {
            throw Script.fail (438, _("The object has no default value."));
        }

        public virtual SValue bang (string name) throws ScriptError {
            return get_default ({ new SValue.str (name) });
        }

        public virtual void set_bang (string name, SValue value) throws ScriptError {
            set_default ({ new SValue.str (name) }, value);
        }

        public virtual Gee.List<SValue>? items () {
            return null;
        }
    }

    public class SValue {
        public SKind kind;
        public bool b;
        public int64 i;
        public double d;
        public string s = "";
        public ScriptObject? obj;
        public SArray? arr;

        public SValue.empty () {
            kind = SKind.EMPTY;
        }

        public SValue.null () {
            kind = SKind.NULL;
        }

        public SValue.nothing () {
            kind = SKind.NOTHING;
        }

        public SValue.bool (bool v) {
            kind = SKind.BOOL;
            b = v;
        }

        public SValue.int (int64 v) {
            kind = SKind.INT;
            i = v;
        }

        public SValue.dbl (double v) {
            kind = SKind.DOUBLE;
            d = v;
        }

        public SValue.str (string v) {
            kind = SKind.STRING;
            s = v;
        }

        public SValue.date (double serial) {
            kind = SKind.DATE;
            d = serial;
        }

        public SValue.object (ScriptObject? o) {
            if (o == null) {
                kind = SKind.NOTHING;
            } else {
                kind = SKind.OBJECT;
                obj = o;
            }
        }

        public SValue.array (SArray a) {
            kind = SKind.ARRAY;
            arr = a;
        }

        public bool is_null {
            get { return kind == SKind.NULL; }
        }

        public bool is_empty {
            get { return kind == SKind.EMPTY; }
        }

        public bool is_numeric () {
            return kind == SKind.INT || kind == SKind.DOUBLE || kind == SKind.BOOL || kind == SKind.DATE;
        }

        public bool looks_numeric () {
            if (is_numeric () || kind == SKind.EMPTY) return true;
            if (kind != SKind.STRING) return false;
            double x;
            return Script.parse_number (s, out x);
        }

        public SValue copy () {
            var v = new SValue.empty ();
            v.kind = kind;
            v.b = b;
            v.i = i;
            v.d = d;
            v.s = s;
            v.obj = obj;
            v.arr = arr;
            return v;
        }

        public double to_double () throws ScriptError {
            switch (kind) {
                case SKind.EMPTY: return 0;
                case SKind.BOOL: return b ? -1 : 0;
                case SKind.INT: return (double) i;
                case SKind.DOUBLE:
                case SKind.DATE: return d;
                case SKind.STRING:
                    double x;
                    if (Script.parse_number (s, out x)) return x;
                    double serial;
                    if (Script.parse_date_text (s, out serial)) return serial;
                    throw Script.fail (13, _("Type mismatch: \"%s\" is not a number.").printf (s));
                case SKind.NULL: throw Script.fail (94, _("Invalid use of Null"));
                default: throw Script.fail (13, _("Type mismatch"));
            }
        }

        public int64 to_int () throws ScriptError {
            if (kind == SKind.INT) return i;
            double x = to_double ();
            return (int64) Script.bankers_round (x);
        }

        public bool to_bool () throws ScriptError {
            switch (kind) {
                case SKind.BOOL: return b;
                case SKind.EMPTY: return false;
                case SKind.NULL: return false;
                case SKind.STRING:
                    string t = s.strip ().down ();
                    if (t == "true" || t == "yes" || t == "on") return true;
                    if (t == "false" || t == "no" || t == "off" || t == "") return false;
                    return to_double () != 0;
                default: return to_double () != 0;
            }
        }

        public string to_str () throws ScriptError {
            switch (kind) {
                case SKind.EMPTY: return "";
                case SKind.NULL: throw Script.fail (94, _("Invalid use of Null"));
                case SKind.BOOL: return b ? "True" : "False";
                case SKind.INT: return i.to_string ();
                case SKind.DOUBLE: return Script.format_double (d);
                case SKind.STRING: return s;
                case SKind.DATE: return Script.date_to_display (d);
                case SKind.NOTHING: throw Script.fail (91, _("Object variable not set"));
                case SKind.OBJECT: return obj.get_default ({}).to_str ();
                default: throw Script.fail (13, _("Type mismatch"));
            }
        }

        public string to_text () {
            try {
                if (kind == SKind.NULL) return "";
                return to_str ();
            } catch (ScriptError e) {
                return "";
            }
        }

        public double to_date () throws ScriptError {
            switch (kind) {
                case SKind.DATE: return d;
                case SKind.STRING:
                    double serial;
                    if (Script.parse_date_text (s, out serial)) return serial;
                    double x;
                    if (Script.parse_number (s, out x)) return x;
                    throw Script.fail (13, _("Type mismatch: \"%s\" is not a date.").printf (s));
                default: return to_double ();
            }
        }

        public SValue resolved_or_self () {
            if (kind != SKind.OBJECT) return this;
            try {
                return obj.get_default ({});
            } catch (ScriptError e) {
                return this;
            }
        }

        public SValue resolved () throws ScriptError {
            if (kind == SKind.OBJECT) return obj.get_default ({});
            return this;
        }

        public static SValue from_db (DbValue v, FieldType? type = null) {
            switch (v.kind) {
                case ValueKind.NULL: return new SValue.null ();
                case ValueKind.INTEGER:
                    if (type != null && type == FieldType.BOOLEAN) return new SValue.bool (v.int_value != 0);
                    return new SValue.int (v.int_value);
                case ValueKind.REAL: return new SValue.dbl (v.real_value);
                case ValueKind.TEXT:
                    if (type != null && type.is_temporal ()) {
                        double serial;
                        if (Script.iso_to_serial (v.text_value, out serial)) return new SValue.date (serial);
                    }
                    return new SValue.str (v.text_value);
                case ValueKind.BLOB: return new SValue.str (v.to_string ());
            }
            return new SValue.null ();
        }

        public static SValue from_field (DbValue v, Field? f) {
            if (f == null) return from_db (v);
            return from_db (v, f.field_type);
        }

        public DbValue to_db () {
            switch (kind) {
                case SKind.EMPTY:
                case SKind.NULL:
                case SKind.NOTHING: return new DbValue.null ();
                case SKind.BOOL: return new DbValue.bool (b);
                case SKind.INT: return new DbValue.int (i);
                case SKind.DOUBLE: return new DbValue.real (d);
                case SKind.DATE: return new DbValue.text (Script.serial_to_iso (d));
                case SKind.STRING: return new DbValue.text (s);
                case SKind.OBJECT:
                    try {
                        return obj.get_default ({}).to_db ();
                    } catch (ScriptError e) {
                        return new DbValue.null ();
                    }
                default: return new DbValue.null ();
            }
        }

        public string debug () {
            switch (kind) {
                case SKind.EMPTY: return "Empty";
                case SKind.NULL: return "Null";
                case SKind.NOTHING: return "Nothing";
                case SKind.OBJECT: return obj.type_name ();
                case SKind.ARRAY: return "Array(%d)".printf (arr.items.size);
                case SKind.STRING: return s;
                default: return to_text ();
            }
        }
    }

    public class Script {
        public static int last_error_number;

        public static ScriptError fail (int number, string message) {
            last_error_number = number;
            return new ScriptError.RUNTIME (message);
        }

        public static double bankers_round (double x) {
            double f = Math.floor (x);
            double diff = x - f;
            if (diff > 0.5) return f + 1;
            if (diff < 0.5) return f;
            return ((int64) f) % 2 == 0 ? f : f + 1;
        }

        public static bool parse_number (string text, out double result) {
            result = 0;
            string t = text.strip ();
            if (t == "") return false;
            if (t.has_prefix ("&H") || t.has_prefix ("&h")) {
                int64 v;
                if (int64.try_parse (t.substring (2), out v, null, 16)) {
                    result = v;
                    return true;
                }
                return false;
            }
            bool digit = false;
            for (int k = 0; k < t.length; k++) {
                char c = t[k];
                if (c.isdigit ()) digit = true;
                else if (c != '.' && c != '-' && c != '+' && c != 'e' && c != 'E' && c != ',') return false;
            }
            if (!digit) return false;
            string n = t;
            var loc = Locale.get ();
            if (loc.decimal_sep == ',' && !t.contains (".")) n = t.replace (",", ".");
            else n = t.replace (",", "");
            return double.try_parse (n, out result);
        }

        public static string format_double (double v) {
            if (v.is_nan ()) return "NaN";
            if (v == Math.floor (v) && Math.fabs (v) < 1e15) return "%.0f".printf (v);
            string s = "%.15g".printf (v).replace (",", ".");
            if (Locale.get ().decimal_sep == ',') s = s.replace (".", ",");
            return s;
        }

        public static int64 days_from_civil (int64 y, int m, int d) {
            y -= m <= 2 ? 1 : 0;
            int64 era = (y >= 0 ? y : y - 399) / 400;
            int64 yoe = y - era * 400;
            int64 doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1;
            int64 doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
            return era * 146097 + doe - 719468;
        }

        public static void civil_from_days (int64 z, out int y, out int m, out int d) {
            z += 719468;
            int64 era = (z >= 0 ? z : z - 146096) / 146097;
            int64 doe = z - era * 146097;
            int64 yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
            int64 yy = yoe + era * 400;
            int64 doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
            int64 mp = (5 * doy + 2) / 153;
            d = (int) (doy - (153 * mp + 2) / 5 + 1);
            m = (int) (mp < 10 ? mp + 3 : mp - 9);
            y = (int) (yy + (m <= 2 ? 1 : 0));
        }

        public const int64 SERIAL_EPOCH = -25569;

        public static double make_serial (int y, int m, int d, int hh = 0, int mm = 0, int ss = 0) {
            int64 days = days_from_civil (y, m, d) - SERIAL_EPOCH;
            return days + (hh * 3600 + mm * 60 + ss) / 86400.0;
        }

        public static void split_serial (double serial, out int y, out int m, out int d, out int hh, out int mm, out int ss) {
            double day = Math.floor (serial);
            double frac = serial - day;
            int64 secs = (int64) Math.round (frac * 86400.0);
            if (secs >= 86400) {
                secs -= 86400;
                day += 1;
            }
            civil_from_days ((int64) day + SERIAL_EPOCH, out y, out m, out d);
            hh = (int) (secs / 3600);
            mm = (int) ((secs / 60) % 60);
            ss = (int) (secs % 60);
        }

        public static bool iso_to_serial (string iso, out double serial) {
            serial = 0;
            string t = iso.strip ();
            int y = 0, m = 0, d = 0, hh = 0, mi = 0, ss = 0;
            bool has_date = false;
            if (t.length >= 10 && t[4] == '-' && t[7] == '-') {
                if (!int.try_parse (t.substring (0, 4), out y, null, 10) || !int.try_parse (t.substring (5, 2), out m, null, 10) || !int.try_parse (t.substring (8, 2), out d, null, 10)) return false;
                if (m < 1 || m > 12 || d < 1 || d > ScriptFunctions.days_in_month (y, m)) return false;
                has_date = true;
                t = t.substring (10).strip ();
                if (t.has_prefix ("T")) t = t.substring (1);
            }
            if (t.length >= 5 && t[2] == ':') {
                if (!int.try_parse (t.substring (0, 2), out hh, null, 10) || !int.try_parse (t.substring (3, 2), out mi, null, 10)) return false;
                if (t.length >= 8 && t[5] == ':') int.try_parse (t.substring (6, 2), out ss, null, 10);
                t = "";
            }
            if (t != "") return false;
            if (!has_date) {
                serial = (hh * 3600 + mi * 60 + ss) / 86400.0;
                return true;
            }
            serial = make_serial (y, m, d, hh, mi, ss);
            return true;
        }

        public static string serial_to_iso (double serial) {
            int y, m, d, hh, mm, ss;
            split_serial (serial, out y, out m, out d, out hh, out mm, out ss);
            if (serial >= 0 && serial < 1 && serial != 0) return "%02d:%02d:%02d".printf (hh, mm, ss);
            if (hh == 0 && mm == 0 && ss == 0) return "%04d-%02d-%02d".printf (y, m, d);
            return "%04d-%02d-%02d %02d:%02d:%02d".printf (y, m, d, hh, mm, ss);
        }

        public static string date_to_display (double serial) {
            int y, m, d, hh, mm, ss;
            split_serial (serial, out y, out m, out d, out hh, out mm, out ss);
            bool time = hh != 0 || mm != 0 || ss != 0;
            bool only_time = serial >= 0 && serial < 1;
            string date = Locale.get ().day_first ? "%02d/%02d/%04d".printf (d, m, y) : "%d/%d/%04d".printf (m, d, y);
            if (only_time && time) return "%02d:%02d:%02d".printf (hh, mm, ss);
            if (!time) return date;
            return "%s %02d:%02d:%02d".printf (date, hh, mm, ss);
        }

        public static bool parse_date_text (string text, out double serial) {
            serial = 0;
            string t = text.strip ();
            if (t == "") return false;
            if (iso_to_serial (t, out serial)) return true;
            string iso;
            if (t.contains (":")) {
                if (Codec.parse_datetime (t, out iso)) return iso_to_serial (iso, out serial);
            }
            if (Codec.parse_date (t, out iso)) return iso_to_serial (iso, out serial);
            if (Codec.parse_time (t, out iso)) return iso_to_serial (iso, out serial);
            string[] months = { "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec" };
            string low = t.down ().replace (",", " ");
            string[] parts = {};
            foreach (string p in low.split (" ")) {
                if (p.strip () != "") parts += p.strip ();
            }
            if (parts.length == 3) {
                int mi = -1, day = -1, year = -1;
                foreach (string p in parts) {
                    for (int k = 0; k < 12; k++) {
                        if (p.has_prefix (months[k])) mi = k + 1;
                    }
                    int n;
                    if (int.try_parse (p, out n, null, 10)) {
                        if (n > 31) year = n;
                        else if (day < 0) day = n;
                        else year = n;
                    }
                }
                if (mi > 0 && day > 0 && year > 0) {
                    serial = make_serial (year < 100 ? (year < 30 ? 2000 + year : 1900 + year) : year, mi, day);
                    return true;
                }
            }
            return false;
        }

        public static SValue now () {
            var n = new DateTime.now_local ();
            return new SValue.date (make_serial (n.get_year (), n.get_month (), n.get_day_of_month (), n.get_hour (), n.get_minute (), n.get_second ()));
        }

        public static SValue today () {
            var n = new DateTime.now_local ();
            return new SValue.date (make_serial (n.get_year (), n.get_month (), n.get_day_of_month ()));
        }
    }
}
