namespace Singularity.Apps.Database {

    public enum ValueKind {
        NULL,
        INTEGER,
        REAL,
        TEXT,
        BLOB
    }

    public class DbValue {
        public ValueKind kind;
        public int64 int_value;
        public double real_value;
        public string? text_value;
        public Bytes? blob_value;

        public DbValue.null () {
            kind = ValueKind.NULL;
        }

        public DbValue.int (int64 v) {
            kind = ValueKind.INTEGER;
            int_value = v;
        }

        public DbValue.real (double v) {
            kind = ValueKind.REAL;
            real_value = v;
        }

        public DbValue.text (string v) {
            kind = ValueKind.TEXT;
            text_value = v;
        }

        public DbValue.blob (Bytes v) {
            kind = ValueKind.BLOB;
            blob_value = v;
        }

        public DbValue.bool (bool v) {
            kind = ValueKind.INTEGER;
            int_value = v ? 1 : 0;
        }

        public bool is_null {
            get { return kind == ValueKind.NULL; }
        }

        public bool is_number () {
            return kind == ValueKind.INTEGER || kind == ValueKind.REAL;
        }

        public double as_double () {
            switch (kind) {
                case ValueKind.INTEGER: return (double) int_value;
                case ValueKind.REAL: return real_value;
                case ValueKind.TEXT: return double.parse (text_value);
                default: return 0;
            }
        }

        public int64 as_int () {
            switch (kind) {
                case ValueKind.INTEGER: return int_value;
                case ValueKind.REAL: return (int64) real_value;
                case ValueKind.TEXT: return int64.parse (text_value);
                default: return 0;
            }
        }

        public bool as_bool () {
            switch (kind) {
                case ValueKind.INTEGER: return int_value != 0;
                case ValueKind.REAL: return real_value != 0;
                case ValueKind.TEXT:
                    string t = text_value.strip ().down ();
                    return t == "1" || t == "true" || t == "yes" || t == "y" || t == "-1" || t == "on" || t == "x";
                default: return false;
            }
        }

        public static string format_real (double v) {
            if (v == Math.floor (v) && Math.fabs (v) < 1e15) return "%.0f".printf (v);
            string s = "%.15g".printf (v);
            if (s.contains ("e")) return s;
            string r = "%.17g".printf (v);
            return double.parse (s) == v ? s : r;
        }

        public string to_string () {
            switch (kind) {
                case ValueKind.NULL: return "";
                case ValueKind.INTEGER: return int_value.to_string ();
                case ValueKind.REAL: return format_real (real_value);
                case ValueKind.TEXT: return text_value;
                case ValueKind.BLOB: return ngettext ("%d byte", "%d bytes", (ulong) blob_value.get_size ()).printf ((int) blob_value.get_size ());
            }
            return "";
        }

        public DbValue copy () {
            var v = new DbValue.null ();
            v.kind = kind;
            v.int_value = int_value;
            v.real_value = real_value;
            v.text_value = text_value;
            v.blob_value = blob_value;
            return v;
        }

        public bool equals (DbValue other) {
            if (kind == ValueKind.NULL || other.kind == ValueKind.NULL) return kind == other.kind;
            if (is_number () && other.is_number ()) return as_double () == other.as_double ();
            if (kind == ValueKind.BLOB || other.kind == ValueKind.BLOB) {
                return kind == other.kind && blob_value.compare (other.blob_value) == 0;
            }
            return to_string () == other.to_string ();
        }

        public int compare (DbValue other) {
            if (kind == ValueKind.NULL) return other.kind == ValueKind.NULL ? 0 : -1;
            if (other.kind == ValueKind.NULL) return 1;
            if (is_number () && other.is_number ()) {
                double a = as_double (), b = other.as_double ();
                return a < b ? -1 : (a > b ? 1 : 0);
            }
            if (is_number ()) return -1;
            if (other.is_number ()) return 1;
            return to_string ().collate (other.to_string ());
        }

        public string sql_literal () {
            switch (kind) {
                case ValueKind.NULL: return "NULL";
                case ValueKind.INTEGER: return int_value.to_string ();
                case ValueKind.REAL:
                    if (real_value.is_nan () || real_value.is_infinity () != 0) return "NULL";
                    string s = format_real (real_value);
                    if (!s.contains (".") && !s.contains ("e")) s += ".0";
                    return s;
                case ValueKind.TEXT: return Sql.quote_string (text_value);
                case ValueKind.BLOB:
                    var sb = new StringBuilder ("X'");
                    unowned uint8[] data = blob_value.get_data ();
                    foreach (uint8 b in data) sb.append ("%02X".printf (b));
                    sb.append ("'");
                    return sb.str;
            }
            return "NULL";
        }
    }

    public class Row {
        public int64 rowid;
        public DbValue[] values;
        public int64[]? keys;

        public Row (int64 rowid, owned DbValue[] values) {
            this.rowid = rowid;
            this.values = (owned) values;
        }

        public DbValue get (int i) {
            if (i < 0 || i >= values.length) return new DbValue.null ();
            return values[i];
        }
    }

    public class ResultSet {
        public string[] columns = {};
        public Gee.ArrayList<Row> rows = new Gee.ArrayList<Row> ();
        public int changes;

        public int index_of (string column) {
            for (int i = 0; i < columns.length; i++) {
                if (columns[i].casefold () == column.casefold ()) return i;
            }
            return -1;
        }
    }
}

namespace Singularity.Apps.Database {

    public class OrderedEntry<V> {
        public string key;
        public V value;

        public OrderedEntry (string key, V value) {
            this.key = key;
            this.value = value;
        }
    }

    public class OrderedMap<V> {
        private Gee.ArrayList<OrderedEntry<V>> list = new Gee.ArrayList<OrderedEntry<V>> ();
        private Gee.HashMap<string, OrderedEntry<V>> index = new Gee.HashMap<string, OrderedEntry<V>> ();

        public int size {
            get { return list.size; }
        }

        public Gee.List<OrderedEntry<V>> entries {
            get { return list; }
        }

        public new V? get (string key) {
            var e = index[key];
            return e != null ? e.value : null;
        }

        public new void set (string key, V value) {
            var e = index[key];
            if (e != null) {
                e.value = value;
                return;
            }
            e = new OrderedEntry<V> (key, value);
            list.add (e);
            index[key] = e;
        }

        public bool has_key (string key) {
            return index.has_key (key);
        }

        public void unset (string key) {
            var e = index[key];
            if (e == null) return;
            index.unset (key);
            list.remove (e);
        }

        public void clear () {
            list.clear ();
            index.clear ();
        }
    }
}
