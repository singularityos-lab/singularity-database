namespace Singularity.Apps.Database {

    public errordomain MdbError {
        FORMAT,
        UNSUPPORTED,
        PASSWORD
    }

    public enum MdbColumnType {
        BOOLEAN,
        BYTE,
        INTEGER,
        LONG,
        MONEY,
        FLOAT,
        DOUBLE,
        DATETIME,
        BINARY,
        TEXT,
        OLE,
        MEMO,
        GUID,
        NUMERIC,
        COMPLEX,
        UNKNOWN;

        public static MdbColumnType from_code (int code) {
            switch (code) {
                case 0x01: return BOOLEAN;
                case 0x02: return BYTE;
                case 0x03: return INTEGER;
                case 0x04: return LONG;
                case 0x05: return MONEY;
                case 0x06: return FLOAT;
                case 0x07: return DOUBLE;
                case 0x08: return DATETIME;
                case 0x09: return BINARY;
                case 0x0A: return TEXT;
                case 0x0B: return OLE;
                case 0x0C: return MEMO;
                case 0x0F: return GUID;
                case 0x10: return NUMERIC;
                case 0x11: return COMPLEX;
                case 0x12: return COMPLEX;
                case 0x13: return LONG;
                default: return UNKNOWN;
            }
        }
    }

    public enum MdbComplexKind {
        NONE,
        ATTACHMENT,
        MULTI_VALUE,
        VERSION_HISTORY,
        UNKNOWN
    }

    public enum MdbQueryKind {
        SELECT,
        MAKE_TABLE,
        APPEND,
        UPDATE,
        DELETE,
        CROSSTAB,
        DATA_DEFINITION,
        PASS_THROUGH,
        UNION,
        UNKNOWN;

        public static MdbQueryKind from_flag (int flag) {
            switch (flag & 0xF0) {
                case 0: return SELECT;
                case 80: return MAKE_TABLE;
                case 64: return APPEND;
                case 48: return UPDATE;
                case 32: return DELETE;
                case 16: return CROSSTAB;
                case 96: return DATA_DEFINITION;
                case 112: return PASS_THROUGH;
                case 128: return UNION;
                default: return UNKNOWN;
            }
        }

        public static MdbQueryKind from_type (int type) {
            switch (type) {
                case 1: return SELECT;
                case 2: return MAKE_TABLE;
                case 3: return APPEND;
                case 4: return UPDATE;
                case 5: return DELETE;
                case 6: return CROSSTAB;
                case 7: return DATA_DEFINITION;
                case 8: return PASS_THROUGH;
                case 9: return UNION;
                default: return UNKNOWN;
            }
        }
    }

    public class MdbQuery {
        public string name = "";
        public MdbQueryKind kind = MdbQueryKind.UNKNOWN;
        public string sql = "";
        public string[] parameters = {};
        public string[] parameter_names = {};
        public string[] parameter_types = {};
        public string connection = "";
        public bool hidden;
    }

    public class MdbAttachment {
        public string name = "";
        public string file_type = "";
        public Bytes data;
        public string url = "";
        public string timestamp = "";
        public int flags;

        public MdbAttachment () {
            data = new Bytes (new uint8[0]);
        }
    }

    public class MdbColumn {
        public string name = "";
        public MdbColumnType kind = MdbColumnType.UNKNOWN;
        public int size;
        public bool autonumber;
        public bool nullable = true;
        public int precision;
        public int scale;
        public MdbComplexKind complex_kind = MdbComplexKind.NONE;
        internal int complex_id;
        internal int code;
        internal int number;
        internal int var_index;
        internal int fixed_offset;
        internal bool is_fixed;
        internal bool compressed;
        internal bool hidden;
    }

    public class MdbTable {
        public string name = "";
        public Gee.ArrayList<MdbColumn> columns = new Gee.ArrayList<MdbColumn> ();
        public Gee.ArrayList<Row> rows = new Gee.ArrayList<Row> ();
        public string[] primary_key = {};
        internal Gee.HashMap<int, MdbComplexData> complex = new Gee.HashMap<int, MdbComplexData> ();

        public int index_of (string column) {
            for (int i = 0; i < columns.size; i++) {
                if (columns[i].name.casefold () == column.casefold ()) return i;
            }
            return -1;
        }
    }

    public class MdbRelationship {
        public string name = "";
        public string table = "";
        public string[] columns = {};
        public string ref_table = "";
        public string[] ref_columns = {};
        public bool enforce = true;
        public bool cascade_update;
        public bool cascade_delete;
    }

    internal class MdbQueryRow {
        public int attribute = -1;
        public string? expression;
        public int flag;
        public bool has_flag;
        public int extra;
        public string? name1;
        public string? name2;
    }

    internal abstract class MdbTableSource {
        public abstract void write (StringBuilder sb, bool top);
        public abstract bool contains (string table);
        public abstract bool same_join (int type, string? on);

        public string text () {
            var sb = new StringBuilder ();
            write (sb, true);
            return sb.str;
        }
    }

    internal class MdbSimpleSource : MdbTableSource {
        private string table;
        private string expr;

        public MdbSimpleSource (string table, string expr) {
            this.table = table;
            this.expr = expr;
        }

        public override void write (StringBuilder sb, bool top) {
            sb.append (expr);
        }

        public override bool contains (string t) {
            return table.casefold () == t.casefold ();
        }

        public override bool same_join (int type, string? on) {
            return false;
        }
    }

    internal class MdbJoinSource : MdbTableSource {
        private MdbTableSource from;
        private MdbTableSource to;
        private int type;
        private Gee.ArrayList<string> on = new Gee.ArrayList<string> ();

        public MdbJoinSource (MdbTableSource from, MdbTableSource to, int type, string? on) {
            this.from = from;
            this.to = to;
            this.type = type;
            this.on.add (on ?? "");
        }

        public override void write (StringBuilder sb, bool top) {
            string kind;
            switch (type) {
                case 1: kind = " INNER JOIN "; break;
                case 2: kind = " LEFT JOIN "; break;
                case 3: kind = " RIGHT JOIN "; break;
                default: kind = " INNER JOIN "; break;
            }
            if (!top) sb.append ("(");
            from.write (sb, false);
            sb.append (kind);
            to.write (sb, false);
            sb.append (" ON ");
            if (on.size > 1) sb.append ("(");
            sb.append (string.joinv (") AND (", on.to_array ()));
            if (on.size > 1) sb.append (")");
            if (!top) sb.append (")");
        }

        public override bool contains (string t) {
            return from.contains (t) || to.contains (t);
        }

        public override bool same_join (int t, string? o) {
            if (type != t) return false;
            on.insert (0, o ?? "");
            return true;
        }
    }

    internal class MdbQueryBuilder {
        private Gee.ArrayList<MdbQueryRow> rows;
        public string[] parameter_names = {};
        public string[] parameter_types = {};
        private string[] parameter_texts = {};

        public MdbQueryBuilder (Gee.ArrayList<MdbQueryRow> rows) {
            this.rows = rows;
        }

        private Gee.ArrayList<MdbQueryRow> by_attr (int a) {
            var list = new Gee.ArrayList<MdbQueryRow> ();
            foreach (var r in rows) {
                if (r.attribute == a) list.add (r);
            }
            return list;
        }

        private MdbQueryRow unique (Gee.ArrayList<MdbQueryRow> list) throws MdbError {
            if (list.size == 1) return list[0];
            if (list.size == 0) return new MdbQueryRow ();
            throw new MdbError.FORMAT ("unexpected number of query rows");
        }

        public MdbQueryRow type_row () {
            foreach (var r in rows) {
                if (r.attribute == 1) return r;
            }
            return new MdbQueryRow ();
        }

        private MdbQueryRow flag_row () throws MdbError {
            return unique (by_attr (3));
        }

        private bool has (int mask) throws MdbError {
            return ((flag_row ().flag & 0xFFFF) & mask) != 0;
        }

        private static bool has_flag (MdbQueryRow r, int mask) {
            return ((r.flag & 0xFFFF) & mask) != 0;
        }

        public MdbQueryKind resolve_kind (int object_flag) {
            int f = object_flag & 0xF0;
            if (f == 0) {
                var t = type_row ();
                if (t.has_flag) {
                    var k = MdbQueryKind.from_type (t.flag);
                    if (k != MdbQueryKind.UNKNOWN) return k;
                }
                return MdbQueryKind.SELECT;
            }
            return MdbQueryKind.from_flag (f);
        }

        private static bool needs_quote (string s) {
            for (int i = 0; i < s.length; i++) {
                char c = s[i];
                if (!(c.isalnum () || c == '_') || (uint8) c >= 0x80) return true;
            }
            return false;
        }

        private static string quoted (string expr) {
            if (expr.length >= 2 && expr[0] == '[' && expr[expr.length - 1] == ']') return expr;
            return "[" + expr + "]";
        }

        public static string optional_quote (string expr, bool identifier) {
            string[] parts = identifier ? expr.split (".") : new string[] { expr };
            var sb = new StringBuilder ();
            for (int i = 0; i < parts.length; i++) {
                sb.append (needs_quote (parts[i]) ? quoted (parts[i]) : parts[i]);
                if (i < parts.length - 1) sb.append_c ('.');
            }
            return sb.str;
        }

        private static string alias (string? a) {
            if (a == null) return "";
            return " AS " + optional_quote (a, false);
        }

        private static string param_type (int flag) {
            switch (flag) {
                case 0: return "Value";
                case 1: return "Bit";
                case 10: return "Text";
                case 2: return "Byte";
                case 3: return "Short";
                case 4: return "Long";
                case 5: return "Currency";
                case 6: return "IEEESingle";
                case 7: return "IEEEDouble";
                case 8: return "DateTime";
                case 9: return "Binary";
                case 11: return "LongBinary";
                case 15: return "Guid";
                default: return "Value";
            }
        }

        public string[] parameters () {
            return parameter_texts;
        }

        private void collect_parameters () {
            string[] names = {}, types = {}, texts = {};
            foreach (var r in by_attr (2)) {
                string n = r.name1 ?? "";
                string t = param_type (r.flag);
                if (r.flag == 10 && r.extra > 0) t += " ( %d )".printf (r.extra);
                names += n;
                types += t;
                texts += optional_quote (n, false) + " " + t;
            }
            parameter_names = names;
            parameter_types = types;
            parameter_texts = texts;
        }

        private string[] from_tables () throws MdbError {
            var sources = new Gee.ArrayList<MdbTableSource> ();
            foreach (var t in by_attr (5)) {
                var sb = new StringBuilder ();
                if (t.expression != null) sb.append (quoted (t.expression)).append_c ('.');
                if (t.name1 != null) sb.append (optional_quote (t.name1, true));
                sb.append (alias (t.name2));
                sources.add (new MdbSimpleSource (t.name2 ?? t.name1 ?? "", sb.str));
            }
            foreach (var j in by_attr (7)) {
                string from_t = j.name1 ?? "";
                string to_t = j.name2 ?? "";
                MdbTableSource? from_s = null, to_s = null;
                for (int i = 0; i < sources.size && (from_s == null || to_s == null); i++) {
                    var ts = sources[i];
                    if (from_s == null && ts.contains (from_t)) {
                        from_s = ts;
                        if (to_s == null && ts.contains (to_t)) {
                            to_s = ts;
                            break;
                        }
                        sources.remove_at (i);
                        i--;
                    } else if (to_s == null && ts.contains (to_t)) {
                        to_s = ts;
                        sources.remove_at (i);
                        i--;
                    }
                }
                if (from_s == null) from_s = new MdbSimpleSource (from_t, optional_quote (from_t, true));
                if (to_s == null) to_s = new MdbSimpleSource (to_t, optional_quote (to_t, true));
                if (from_s == to_s) {
                    if (from_s.same_join (j.flag, j.expression)) continue;
                    throw new MdbError.FORMAT ("inconsistent join types");
                }
                sources.add (new MdbJoinSource (from_s, to_s, j.flag, j.expression));
            }
            string[] list = {};
            foreach (var s in sources) list += s.text ();
            return list;
        }

        private string remote (string? path, string? type) {
            if (path == null && type == null) return "";
            var sb = new StringBuilder (" IN '");
            if (path != null) sb.append (path);
            sb.append_c ('\'');
            if (type != null) sb.append (" [").append (type).append ("]");
            return sb.str;
        }

        private string select_type () throws MdbError {
            if (has (0x02)) return "DISTINCT";
            if (has (0x08)) return "DISTINCTROW";
            if (has (0x10)) {
                string s = "TOP " + (flag_row ().name1 ?? "");
                if (has (0x20)) s += " PERCENT";
                return s;
            }
            return "";
        }

        private void select_string (StringBuilder sb, bool prefix, MdbQueryKind kind) throws MdbError {
            if (prefix) {
                sb.append ("SELECT ");
                string st = select_type ();
                if (st != "") sb.append (st).append_c (' ');
            }
            string[] cols = {};
            foreach (var c in by_attr (6)) {
                if (kind == MdbQueryKind.CROSSTAB && !has_flag (c, 0x02)) continue;
                if (kind == MdbQueryKind.APPEND && has_flag (c, 0x8000)) continue;
                cols += (c.expression ?? "") + alias (c.name1);
            }
            if (has (0x01)) cols += "*";
            sb.append (string.joinv (", ", cols));
            if (kind == MdbQueryKind.MAKE_TABLE) {
                var t = type_row ();
                sb.append (" INTO ").append (optional_quote (t.name1 ?? "", true));
                sb.append (remote (t.name2, t.expression));
            }
            string[] from = from_tables ();
            if (from.length > 0) {
                sb.append ("\nFROM ").append (string.joinv (", ", from));
                var rdb = unique (by_attr (4));
                sb.append (remote (rdb.name1, rdb.expression));
            }
            string? where_e = unique (by_attr (8)).expression;
            if (where_e != null) sb.append ("\nWHERE ").append (where_e);
            string[] groups = {};
            foreach (var g in by_attr (9)) {
                if (kind == MdbQueryKind.CROSSTAB && !has_flag (g, 0x02)) continue;
                groups += g.expression ?? "";
            }
            if (groups.length > 0) sb.append ("\nGROUP BY ").append (string.joinv (", ", groups));
            string? having = unique (by_attr (10)).expression;
            if (having != null) sb.append ("\nHAVING ").append (having);
            append_order (sb);
        }

        private void append_order (StringBuilder sb) {
            string[] orders = {};
            foreach (var o in by_attr (11)) {
                string s = o.expression ?? "";
                if ((o.name1 ?? "").up () == "D") s += " DESC";
                orders += s;
            }
            if (orders.length > 0) sb.append ("\nORDER BY ").append (string.joinv (", ", orders));
        }

        private static string clean_union (string s) {
            string t = s.strip ();
            try {
                return new Regex ("[\r\n]+").replace (t, -1, 0, "\n");
            } catch (RegexError e) {
                return t;
            }
        }

        public string to_sql (MdbQueryKind kind) throws MdbError {
            collect_parameters ();
            var sb = new StringBuilder ();
            bool standard = kind != MdbQueryKind.PASS_THROUGH && kind != MdbQueryKind.DATA_DEFINITION;
            if (kind == MdbQueryKind.UNKNOWN) throw new MdbError.UNSUPPORTED ("unknown query type");
            var t = type_row ();
            if (t.has_flag && MdbQueryKind.from_type (t.flag) != kind) throw new MdbError.FORMAT ("unexpected query type");
            if (standard && parameter_texts.length > 0) sb.append ("PARAMETERS ").append (string.joinv (", ", parameter_texts)).append (";\n");
            switch (kind) {
                case MdbQueryKind.SELECT:
                case MdbQueryKind.MAKE_TABLE:
                    select_string (sb, true, kind);
                    break;
                case MdbQueryKind.DELETE:
                    sb.append ("DELETE ");
                    select_string (sb, false, kind);
                    break;
                case MdbQueryKind.CROSSTAB:
                    MdbQueryRow? transform = null;
                    MdbQueryRow? pivot = null;
                    foreach (var c in by_attr (6)) {
                        if (has_flag (c, 0x01)) {
                            if (pivot != null) throw new MdbError.FORMAT ("two pivot columns");
                            pivot = c;
                        } else if (!has_flag (c, 0x02)) {
                            if (transform != null) throw new MdbError.FORMAT ("two transform columns");
                            transform = c;
                        }
                    }
                    if (transform != null && transform.expression != null) sb.append ("TRANSFORM ").append (transform.expression).append (alias (transform.name1)).append ("\n");
                    select_string (sb, true, kind);
                    sb.append ("\nPIVOT ").append (pivot != null ? (pivot.expression ?? "") : "");
                    break;
                case MdbQueryKind.APPEND:
                    sb.append ("INSERT INTO ").append (optional_quote (t.name1 ?? "", true));
                    string[] targets = {};
                    string[] values = {};
                    foreach (var c in by_attr (6)) {
                        if (c.name2 != null) targets += optional_quote (c.name2, true);
                        if (has_flag (c, 0x8000)) values += c.expression ?? "";
                    }
                    if (targets.length > 0) sb.append (" (").append (string.joinv (", ", targets)).append (")");
                    sb.append (remote (t.name2, t.expression));
                    sb.append ("\n");
                    if (values.length > 0) sb.append ("VALUES (").append (string.joinv (", ", values)).append (")");
                    else select_string (sb, true, kind);
                    break;
                case MdbQueryKind.UPDATE:
                    sb.append ("UPDATE ").append (string.joinv (", ", from_tables ()));
                    var rdb = unique (by_attr (4));
                    sb.append (remote (rdb.name1, rdb.expression));
                    string[] sets = {};
                    foreach (var c in by_attr (6)) sets += optional_quote (c.name2 ?? "", true) + " = " + (c.expression ?? "");
                    sb.append ("\nSET ").append (string.joinv (", ", sets));
                    string? w = unique (by_attr (8)).expression;
                    if (w != null) sb.append ("\nWHERE ").append (w);
                    break;
                case MdbQueryKind.UNION:
                    string? part1 = null, part2 = null;
                    foreach (var r in by_attr (5)) {
                        if (r.name2 == "X7YZ_____1") part1 = r.expression;
                        else if (r.name2 == "X7YZ_____2") part2 = r.expression;
                    }
                    if (part1 == null || part2 == null) throw new MdbError.FORMAT ("union parts missing");
                    sb.append (clean_union (part1)).append ("\nUNION ");
                    if (!has (0x02)) sb.append ("ALL ");
                    sb.append (clean_union (part2));
                    append_order (sb);
                    break;
                case MdbQueryKind.PASS_THROUGH:
                case MdbQueryKind.DATA_DEFINITION:
                    if (t.expression != null) sb.append (t.expression);
                    break;
                default:
                    throw new MdbError.UNSUPPORTED ("unknown query type");
            }
            if (standard) {
                if (has (0x04)) sb.append ("\nWITH OWNERACCESS OPTION");
                sb.append_c (';');
            }
            return sb.str;
        }
    }

    internal class MdbComplexData {
        public MdbComplexKind kind = MdbComplexKind.UNKNOWN;
        public MdbTable flat = new MdbTable ();
        public int[] value_columns = {};
        public Gee.HashMap<string, Gee.ArrayList<Row>> by_key = new Gee.HashMap<string, Gee.ArrayList<Row>> ();
    }

    public class MdbCodec {
        public static uint8[] rc4 (uint8[] key, uint8[] input) {
            uint8[] s = new uint8[256];
            for (int i = 0; i < 256; i++) s[i] = (uint8) i;
            int j = 0;
            for (int i = 0; i < 256; i++) {
                j = (j + s[i] + key[i % key.length]) & 0xff;
                uint8 t = s[i];
                s[i] = s[j];
                s[j] = t;
            }
            uint8[] output = new uint8[input.length];
            int a = 0, b = 0;
            for (int k = 0; k < input.length; k++) {
                a = (a + 1) & 0xff;
                b = (b + s[a]) & 0xff;
                uint8 t = s[a];
                s[a] = s[b];
                s[b] = t;
                output[k] = input[k] ^ s[(s[a] + s[b]) & 0xff];
            }
            return output;
        }

        public static string ucs2 (uint8[] data, int start, int len) {
            var sb = new StringBuilder ();
            int end = start + len;
            int i = start;
            while (i + 1 < end) {
                uint unit = data[i] | (data[i + 1] << 8);
                i += 2;
                if (unit >= 0xD800 && unit <= 0xDBFF && i + 1 < end) {
                    uint low = data[i] | (data[i + 1] << 8);
                    if (low >= 0xDC00 && low <= 0xDFFF) {
                        i += 2;
                        sb.append_unichar ((unichar) (0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00)));
                        continue;
                    }
                }
                if (unit == 0) continue;
                if (unit >= 0xD800 && unit <= 0xDFFF) unit = 0xFFFD;
                sb.append_unichar ((unichar) unit);
            }
            return sb.str;
        }

        public static string jet4_text (uint8[] data, int start, int len) {
            if (len >= 2 && data[start] == 0xFF && data[start + 1] == 0xFE) {
                var sb = new StringBuilder ();
                bool compressed = true;
                int i = start + 2;
                int end = start + len;
                while (i < end) {
                    if (data[i] == 0) {
                        compressed = !compressed;
                        i++;
                        continue;
                    }
                    if (compressed) {
                        sb.append_unichar ((unichar) data[i]);
                        i++;
                    } else {
                        if (i + 1 >= end) break;
                        uint unit = data[i] | (data[i + 1] << 8);
                        if (unit != 0 && !(unit >= 0xD800 && unit <= 0xDFFF)) sb.append_unichar ((unichar) unit);
                        i += 2;
                    }
                }
                return sb.str;
            }
            return ucs2 (data, start, len);
        }

        private const uint16[] CP1252_HIGH = {
            0x20AC, 0xFFFD, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0xFFFD, 0x017D, 0xFFFD,
            0xFFFD, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0xFFFD, 0x017E, 0x0178
        };

        public static string cp1252 (uint8[] data, int start, int len) {
            var sb = new StringBuilder ();
            for (int i = start; i < start + len; i++) {
                uint8 c = data[i];
                if (c == 0) continue;
                if (c >= 0x80 && c < 0xA0) sb.append_unichar ((unichar) CP1252_HIGH[c - 0x80]);
                else sb.append_unichar ((unichar) c);
            }
            return sb.str;
        }

        public static string ole_date (double v) {
            double days = v >= 0 ? Math.floor (v) : Math.ceil (v);
            double frac = Math.fabs (v - days);
            int64 secs = (int64) Math.round (frac * 86400.0);
            if (secs >= 86400) {
                secs -= 86400;
                days += v >= 0 ? 1 : -1;
            }
            var base_date = new DateTime.utc (1899, 12, 30, 0, 0, 0);
            if (days.is_nan () || Math.fabs (days) > 3000000) return "";
            var day = base_date.add_days ((int) days);
            if (day == null) return "";
            var d = day.add_seconds ((double) secs);
            if (d == null) return "";
            return "%04d-%02d-%02d %02d:%02d:%02d".printf (d.get_year (), d.get_month (), d.get_day_of_month (), d.get_hour (), d.get_minute (), d.get_second ());
        }

        private static uint32 le32 (uint8[] b, int p) {
            return (uint32) b[p] | ((uint32) b[p + 1] << 8) | ((uint32) b[p + 2] << 16) | ((uint32) b[p + 3] << 24);
        }

        public static Bytes attachment_content (uint8[] encoded) throws Error {
            if (encoded.length < 8) throw new MdbError.FORMAT (_("An attachment is damaged."));
            uint32 type_flag = le32 (encoded, 0);
            int data_len = (int) le32 (encoded, 4);
            uint8[] content;
            if (type_flag == 0) {
                content = encoded[8:encoded.length];
            } else if (type_flag == 1) {
                var conv = new ZlibDecompressor (ZlibCompressorFormat.ZLIB);
                var stream = new ConverterInputStream (new MemoryInputStream.from_data (encoded[8:encoded.length]), conv);
                var buf = new ByteArray.sized (int.max (64, data_len));
                uint8[] chunk = new uint8[65536];
                ssize_t n;
                while ((n = stream.read (chunk)) > 0) buf.append (chunk[0:n]);
                content = buf.steal ();
            } else {
                throw new MdbError.FORMAT (_("An attachment uses an unknown storage format."));
            }
            if (content.length < 4) throw new MdbError.FORMAT (_("An attachment is damaged."));
            int header_len = (int) le32 (content, 0);
            if (header_len < 4 || header_len > content.length) throw new MdbError.FORMAT (_("An attachment is damaged."));
            int end = data_len > header_len && data_len <= content.length ? data_len : content.length;
            return new Bytes (content[header_len:end]);
        }

        public static double money (int64 raw) {
            return raw / 10000.0;
        }

        public static string guid (uint8[] b, int p) {
            return "{%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X}".printf (
                b[p + 3], b[p + 2], b[p + 1], b[p], b[p + 5], b[p + 4], b[p + 7], b[p + 6],
                b[p + 8], b[p + 9], b[p + 10], b[p + 11], b[p + 12], b[p + 13], b[p + 14], b[p + 15]);
        }

        public static double numeric (uint8[] b, int p, int scale) {
            double v = 0;
            for (int w = 0; w < 4; w++) {
                int q = p + 1 + w * 4;
                uint32 part = (uint32) b[q] | ((uint32) b[q + 1] << 8) | ((uint32) b[q + 2] << 16) | ((uint32) b[q + 3] << 24);
                v = v * 4294967296.0 + part;
            }
            v = v / Math.pow (10, scale);
            return (b[p] & 0x80) != 0 ? -v : v;
        }
    }

    public class MdbFile {
        public int version;
        public Gee.ArrayList<MdbTable> tables = new Gee.ArrayList<MdbTable> ();
        public Gee.ArrayList<MdbRelationship> relationships = new Gee.ArrayList<MdbRelationship> ();
        public string[] query_names = {};
        public Gee.ArrayList<MdbQuery> queries = new Gee.ArrayList<MdbQuery> ();
        public string[] form_names = {};
        public string[] report_names = {};
        public string[] macro_names = {};
        public string[] module_names = {};
        public bool has_password { get; private set; }
        public string office_encryption { get; private set; default = ""; }

        private uint8[] data;
        private int page_size;
        private bool jet3;
        private int page_count;
        private uint8[] header_plain;
        private Gee.HashMap<string, int> system_pages = new Gee.HashMap<string, int> ();
        private Gee.HashMap<int, string> object_names = new Gee.HashMap<int, string> ();

        private class TableDefinition {
            public int page;
            public int num_rows;
            public int num_var_cols;
            public int num_cols;
            public uint32 used_pages;
            public Gee.ArrayList<MdbColumn> columns = new Gee.ArrayList<MdbColumn> ();
            public string[] primary_key = {};
        }

        private class IndexColumns {
            public int[] numbers = {};
        }

        private class ColumnPair {
            public string column;
            public string ref_column;
        }

        private MdbFile () {
        }

        public static MdbFile open (string path, string? password = null) throws Error {
            uint8[] bytes;
            FileUtils.get_data (path, out bytes);
            var f = new MdbFile ();
            f.load ((owned) bytes, password);
            return f;
        }

        public static MdbFile from_data (owned uint8[] bytes, string? password = null) throws Error {
            var f = new MdbFile ();
            f.load ((owned) bytes, password);
            return f;
        }

        public static bool is_accdb_encrypted (uint8[] bytes) {
            if (bytes.length < 3 * 4096 || bytes[0x14] < 2) return false;
            return bytes[2 * 4096] != 0x02;
        }

        private void load (owned uint8[] bytes, string? password) throws Error {
            data = (owned) bytes;
            if (data.length < 2048 || data[0] != 0) throw new MdbError.FORMAT (_("This is not an Access database."));
            var sig = new StringBuilder ();
            sig.append_len ((string) ((uint8*) data + 4), 15);
            if (sig.str != "Standard Jet DB" && sig.str != "Standard ACE DB") throw new MdbError.FORMAT (_("This is not an Access database."));
            version = data[0x14];
            jet3 = version == 0;
            page_size = jet3 ? 2048 : 4096;
            page_count = data.length / page_size;
            if (page_count < 3) throw new MdbError.FORMAT (_("The Access database is truncated."));
            int hlen = jet3 ? 126 : 128;
            uint8[] header = MdbCodec.rc4 ({ 0xC7, 0xDA, 0x39, 0x6B }, data[0x18:0x18 + hlen]);
            uint32 db_key = (uint32) header[0x3E - 0x18] | ((uint32) header[0x3F - 0x18] << 8) | ((uint32) header[0x40 - 0x18] << 16) | ((uint32) header[0x41 - 0x18] << 24);
            header_plain = header;
            if (db_key != 0 && version <= 1) decode_pages (db_key);
            if (OfficeCrypt.is_encrypted (data, header_plain)) {
                var oc = OfficeCrypt.open (data, header_plain, password);
                for (int p = 1; p < page_count; p++) oc.decrypt_page (data, p * page_size, page_size, p);
                office_encryption = oc.kind.label ();
                has_password = true;
                if (data[2 * page_size] != 0x02) throw new MdbError.PASSWORD (_("The password is not correct."));
                read_catalog ();
                return;
            }
            if (data[2 * page_size] != 0x02) {
                throw new MdbError.UNSUPPORTED (_("This Access database uses an encryption method that is not supported."));
            }
            string stored = stored_password ();
            has_password = stored != "";
            if (has_password && (password == null || password != stored)) {
                throw new MdbError.PASSWORD (password == null ? _("This Access database is protected with a password.") : _("The password is not correct."));
            }
            read_catalog ();
        }

        private void decode_pages (uint32 db_key) {
            for (int p = 1; p < page_count; p++) {
                uint32 k = db_key ^ (uint32) p;
                uint8[] key = { (uint8) (k & 0xff), (uint8) ((k >> 8) & 0xff), (uint8) ((k >> 16) & 0xff), (uint8) ((k >> 24) & 0xff) };
                int start = p * page_size;
                uint8[] plain = MdbCodec.rc4 (key, data[start:start + page_size]);
                Memory.copy ((uint8*) data + start, plain, page_size);
            }
        }

        private string stored_password () {
            int at = 0x42 - 0x18;
            int len = jet3 ? 20 : 40;
            if (header_plain.length < at + len) return "";
            uint8[] pwd = header_plain[at:at + len];
            if (!jet3 && header_plain.length >= 0x72 - 0x18 + 8) {
                double date = f64 (header_plain, 0x72 - 0x18);
                int32 m = (int32) date;
                uint8[] mask = { (uint8) (m & 0xff), (uint8) ((m >> 8) & 0xff), (uint8) ((m >> 16) & 0xff), (uint8) ((m >> 24) & 0xff) };
                for (int i = 0; i < pwd.length; i++) pwd[i] ^= mask[i % 4];
            }
            bool any = false;
            foreach (uint8 b in pwd) {
                if (b != 0) any = true;
            }
            if (!any) return "";
            return jet3 ? MdbCodec.cp1252 (pwd, 0, pwd.length) : MdbCodec.ucs2 (pwd, 0, pwd.length);
        }

        public static uint8[] with_password (uint8[] file, string password) {
            uint8[] result = file;
            bool j3 = result[0x14] == 0;
            int hlen = j3 ? 126 : 128;
            uint8[] key = { 0xC7, 0xDA, 0x39, 0x6B };
            uint8[] header = MdbCodec.rc4 (key, result[0x18:0x18 + hlen]);
            int at = 0x42 - 0x18;
            int len = j3 ? 20 : 40;
            uint8[] pwd = new uint8[len];
            if (j3) {
                int i = 0;
                int k = 0;
                unichar ch;
                while (password.get_next_char (ref i, out ch) && k < len) pwd[k++] = (uint8) (ch < 256 ? ch : '?');
            } else {
                int i = 0;
                unichar ch;
                int k = 0;
                while (password.get_next_char (ref i, out ch) && k + 1 < len) {
                    pwd[k++] = (uint8) (ch & 0xff);
                    pwd[k++] = (uint8) ((ch >> 8) & 0xff);
                }
                int64 bits = 0;
                int dp = 0x72 - 0x18;
                for (int b = 7; b >= 0; b--) bits = (bits << 8) | header[dp + b];
                double date = 0;
                Memory.copy (&date, &bits, 8);
                int32 m = (int32) date;
                uint8[] mask = { (uint8) (m & 0xff), (uint8) ((m >> 8) & 0xff), (uint8) ((m >> 16) & 0xff), (uint8) ((m >> 24) & 0xff) };
                for (int j = 0; j < len; j++) pwd[j] ^= mask[j % 4];
            }
            for (int j = 0; j < len; j++) header[at + j] = pwd[j];
            uint8[] enc = MdbCodec.rc4 (key, header);
            for (int j = 0; j < hlen; j++) result[0x18 + j] = enc[j];
            return result;
        }

        private int u16 (uint8[] b, int p) {
            return b[p] | (b[p + 1] << 8);
        }

        private uint32 u32 (uint8[] b, int p) {
            return (uint32) b[p] | ((uint32) b[p + 1] << 8) | ((uint32) b[p + 2] << 16) | ((uint32) b[p + 3] << 24);
        }

        private int64 i64 (uint8[] b, int p) {
            uint64 lo = u32 (b, p);
            uint64 hi = u32 (b, p + 4);
            return (int64) (lo | (hi << 32));
        }

        private double f64 (uint8[] b, int p) {
            int64 bits = i64 (b, p);
            double v = 0;
            Memory.copy (&v, &bits, 8);
            return v;
        }

        private float f32 (uint8[] b, int p) {
            uint32 bits = u32 (b, p);
            float v = 0;
            Memory.copy (&v, &bits, 4);
            return v;
        }

        private string name_text (uint8[] b, int p, int len) {
            return jet3 ? MdbCodec.cp1252 (b, p, len) : MdbCodec.jet4_text (b, p, len);
        }

        private uint8[]? page (int n) {
            if (n <= 0 || n >= page_count) return null;
            int s = n * page_size;
            return data[s:s + page_size];
        }

        private bool row_bounds (uint8[] pg, int row, out int start, out int end, out bool deleted, out bool lookup) {
            start = end = 0;
            deleted = lookup = false;
            int count_off = jet3 ? 8 : 12;
            int count = u16 (pg, count_off);
            if (row < 0 || row >= count) return false;
            int table = count_off + 2;
            int raw = u16 (pg, table + row * 2);
            deleted = (raw & 0x8000) != 0;
            lookup = (raw & 0x4000) != 0;
            start = raw & 0x1FFF;
            end = row == 0 ? page_size : (u16 (pg, table + (row - 1) * 2) & 0x1FFF);
            if (start >= page_size || end > page_size || start > end) return false;
            return true;
        }

        private uint8[]? row_data (uint32 pointer) {
            int pg_no = (int) (pointer >> 8);
            int row = (int) (pointer & 0xff);
            var pg = page (pg_no);
            if (pg == null) return null;
            int s, e;
            bool del, look;
            if (!row_bounds (pg, row, out s, out e, out del, out look)) return null;
            return pg[s:e];
        }

        private bool follow (uint8[] pg, int at, out uint8[] target, out int start, out int end) {
            target = pg;
            start = end = 0;
            uint8[] cur = pg;
            int pos = at;
            for (int hop = 0; hop < 8; hop++) {
                uint32 pointer = u32 (cur, pos);
                var next = page ((int) (pointer >> 8));
                if (next == null || next[0] != 0x01) return false;
                int s, e;
                bool del, look;
                if (!row_bounds (next, (int) (pointer & 0xff), out s, out e, out del, out look)) return false;
                if (look && e - s >= 4) {
                    cur = next;
                    pos = s;
                    continue;
                }
                target = next;
                start = s;
                end = e;
                return true;
            }
            return false;
        }

        private uint8[] tdef_bytes (int start_page) throws Error {
            var buf = new ByteArray ();
            int p = start_page;
            int guard = 0;
            while (p > 0 && guard++ < 1000) {
                var pg = page (p);
                if (pg == null || pg[0] != 0x02) {
                    if (buf.len == 0) throw new MdbError.FORMAT (_("A table definition is damaged."));
                    break;
                }
                if (buf.len == 0) buf.append (pg);
                else buf.append (pg[8:page_size]);
                p = (int) u32 (pg, 4);
            }
            return buf.steal ();
        }

        private TableDefinition read_tdef (int tpage) throws Error {
            uint8[] t = tdef_bytes (tpage);
            var def = new TableDefinition ();
            def.page = tpage;
            int pos;
            int num_idx, num_real_idx;
            if (jet3) {
                def.num_rows = (int) u32 (t, 12);
                def.num_var_cols = u16 (t, 23);
                def.num_cols = u16 (t, 25);
                num_idx = (int) u32 (t, 27);
                num_real_idx = (int) u32 (t, 31);
                def.used_pages = u32 (t, 35);
                pos = 43 + num_real_idx * 8;
            } else {
                def.num_rows = (int) u32 (t, 16);
                def.num_var_cols = u16 (t, 43);
                def.num_cols = u16 (t, 45);
                num_idx = (int) u32 (t, 47);
                num_real_idx = (int) u32 (t, 51);
                def.used_pages = u32 (t, 55);
                pos = 63 + num_real_idx * 12;
            }
            if (def.num_cols > 4096 || num_idx > 1000 || num_real_idx > 1000) throw new MdbError.FORMAT (_("A table definition is damaged."));
            int entry = jet3 ? 18 : 25;
            var cols = new Gee.ArrayList<MdbColumn> ();
            for (int i = 0; i < def.num_cols; i++) {
                int e = pos + i * entry;
                if (e + entry > t.length) throw new MdbError.FORMAT (_("A table definition is damaged."));
                var c = new MdbColumn ();
                c.code = t[e];
                c.kind = MdbColumnType.from_code (c.code);
                int flags;
                if (jet3) {
                    c.number = u16 (t, e + 1);
                    c.var_index = u16 (t, e + 3);
                    c.precision = t[e + 9];
                    c.scale = t[e + 10];
                    flags = t[e + 13];
                    c.fixed_offset = u16 (t, e + 14);
                    c.size = u16 (t, e + 16);
                } else {
                    c.number = u16 (t, e + 5);
                    c.var_index = u16 (t, e + 7);
                    c.precision = t[e + 11];
                    c.scale = t[e + 12];
                    flags = t[e + 15];
                    c.compressed = (t[e + 16] & 0x01) != 0;
                    c.fixed_offset = u16 (t, e + 21);
                    c.size = u16 (t, e + 23);
                    if (c.code == 0x12) c.complex_id = (int) u32 (t, e + 11);
                }
                c.is_fixed = (flags & 0x01) != 0;
                c.hidden = (flags & 0x10) != 0;
                c.nullable = (flags & 0x02) != 0;
                c.autonumber = ((flags & 0x04) != 0 && c.kind == MdbColumnType.LONG) || ((flags & 0x40) != 0 && c.kind == MdbColumnType.GUID);
                if (c.kind == MdbColumnType.COMPLEX) c.autonumber = false;
                cols.add (c);
            }
            pos += def.num_cols * entry;
            foreach (var c in cols) {
                int len;
                if (jet3) {
                    len = t[pos];
                    pos += 1;
                } else {
                    len = u16 (t, pos);
                    pos += 2;
                }
                if (pos + len > t.length) throw new MdbError.FORMAT (_("A table definition is damaged."));
                c.name = name_text (t, pos, len);
                pos += len;
            }
            var real_cols = new Gee.ArrayList<IndexColumns> ();
            int real_entry = jet3 ? 39 : 52;
            for (int i = 0; i < num_real_idx; i++) {
                int e = pos + i * real_entry + (jet3 ? 0 : 4);
                var ic = new IndexColumns ();
                for (int k = 0; k < 10; k++) {
                    if (e + k * 3 + 2 > t.length) break;
                    int n = u16 (t, e + k * 3);
                    if (n != 0xFFFF) ic.numbers += n;
                }
                real_cols.add (ic);
            }
            pos += num_real_idx * real_entry;
            int logical_entry = jet3 ? 20 : 28;
            for (int i = 0; i < num_idx; i++) {
                int e = pos + i * logical_entry + (jet3 ? 0 : 4);
                if (e + logical_entry - (jet3 ? 0 : 4) > t.length) break;
                int real_index = (int) u32 (t, e + 4);
                int type = t[e + 19];
                if (type == 1 && real_index >= 0 && real_index < real_cols.size && def.primary_key.length == 0) {
                    string[] pk = {};
                    foreach (int n in real_cols[real_index].numbers) {
                        foreach (var c in cols) {
                            if (c.number == n) pk += c.name;
                        }
                    }
                    def.primary_key = pk;
                }
            }
            cols.sort ((a, b) => a.number - b.number);
            def.columns = cols;
            return def;
        }

        private Gee.ArrayList<int> table_pages (TableDefinition def) {
            var list = new Gee.ArrayList<int> ();
            var map = row_data (def.used_pages);
            if (map != null && map.length > 1) {
                if (map[0] == 0 && map.length >= 5) {
                    int first = (int) u32 (map, 1);
                    for (int i = 5; i < map.length; i++) {
                        for (int bit = 0; bit < 8; bit++) {
                            if ((map[i] & (1 << bit)) != 0) list.add (first + (i - 5) * 8 + bit);
                        }
                    }
                } else if (map[0] == 1) {
                    int per_page = (page_size - 4) * 8;
                    for (int i = 1; i + 4 <= map.length; i += 4) {
                        int mp = (int) u32 (map, i);
                        if (mp == 0) continue;
                        var mpg = page (mp);
                        if (mpg == null || mpg[0] != 0x05) continue;
                        int base_page = ((i - 1) / 4) * per_page;
                        for (int k = 4; k < page_size; k++) {
                            if (mpg[k] == 0) continue;
                            for (int bit = 0; bit < 8; bit++) {
                                if ((mpg[k] & (1 << bit)) != 0) list.add (base_page + (k - 4) * 8 + bit);
                            }
                        }
                    }
                }
            }
            var valid = new Gee.ArrayList<int> ();
            foreach (int p in list) {
                var pg = page (p);
                if (pg != null && pg[0] == 0x01 && u32 (pg, 4) == def.page) valid.add (p);
            }
            if (valid.size > 0 || def.num_rows == 0) return valid;
            for (int p = 3; p < page_count; p++) {
                int s = p * page_size;
                if (data[s] == 0x01 && u32 (data, s + 4) == def.page) valid.add (p);
            }
            return valid;
        }

        private Gee.ArrayList<Row> read_rows (TableDefinition def) {
            var rows = new Gee.ArrayList<Row> ();
            foreach (int p in table_pages (def)) {
                var pg = page (p);
                int count = u16 (pg, jet3 ? 8 : 12);
                for (int r = 0; r < count; r++) {
                    int s, e;
                    bool del, look;
                    if (!row_bounds (pg, r, out s, out e, out del, out look)) continue;
                    if (del) continue;
                    uint8[] rpg = pg;
                    if (look) {
                        if (!follow (pg, s, out rpg, out s, out e)) continue;
                    }
                    if (e - s < 1) continue;
                    var values = crack (def, rpg, s, e);
                    if (values != null) rows.add (new Row (rows.size, (owned) values));
                }
            }
            return rows;
        }

        private DbValue[]? crack (TableDefinition def, uint8[] pg, int start, int end) {
            int num_cols = jet3 ? pg[start] : u16 (pg, start);
            int mask_size = (num_cols + 7) / 8;
            if (end - start < mask_size + 1) return null;
            int mask_at = end - mask_size;
            int fixed_base = start + (jet3 ? 1 : 2);
            int[] var_start = {};
            int[] var_end = {};
            int var_len = 0;
            if (def.num_var_cols > 0) {
                if (jet3) {
                    var_len = pg[mask_at - 1];
                    int row_len = end - start;
                    int jumps = (row_len - 1) / 256;
                    int ptr = mask_at - jumps - 1;
                    if ((ptr - start - var_len) / 256 < jumps) jumps--;
                    if (jumps < 0) jumps = 0;
                    int[] jump = new int[jumps];
                    for (int k = 0; k < jumps; k++) jump[k] = pg[mask_at - 2 - k];
                    int table_end = mask_at - 1 - jumps;
                    int[] offs = new int[var_len + 1];
                    for (int j = 0; j <= var_len; j++) {
                        int at = table_end - 1 - j;
                        if (at < start) return null;
                        int o = pg[at];
                        foreach (int jv in jump) {
                            if (jv <= j) o += 256;
                        }
                        offs[j] = o;
                    }
                    for (int j = 0; j < var_len; j++) {
                        var_start += start + offs[j];
                        var_end += start + offs[j + 1];
                    }
                } else {
                    var_len = u16 (pg, mask_at - 2);
                    int[] offs = new int[var_len + 1];
                    for (int j = 0; j <= var_len; j++) {
                        int at = mask_at - 4 - 2 * j;
                        if (at < start) return null;
                        offs[j] = u16 (pg, at);
                    }
                    for (int j = 0; j < var_len; j++) {
                        var_start += start + offs[j];
                        var_end += start + offs[j + 1];
                    }
                }
            }
            DbValue[] values = new DbValue[def.columns.size];
            for (int i = 0; i < def.columns.size; i++) {
                var c = def.columns[i];
                bool present = c.number < num_cols && (pg[mask_at + c.number / 8] & (1 << (c.number % 8))) != 0;
                if (c.kind == MdbColumnType.BOOLEAN) {
                    values[i] = new DbValue.bool (present);
                    continue;
                }
                if (!present) {
                    values[i] = new DbValue.null ();
                    continue;
                }
                if (c.is_fixed) {
                    int p = fixed_base + c.fixed_offset;
                    int size = fixed_size (c);
                    if (p + size > mask_at) {
                        values[i] = new DbValue.null ();
                        continue;
                    }
                    values[i] = decode (c, pg, p, size);
                } else {
                    if (c.var_index >= var_len) {
                        values[i] = new DbValue.null ();
                        continue;
                    }
                    int s = var_start[c.var_index], e = var_end[c.var_index];
                    if (s < start || e > mask_at || e < s) {
                        values[i] = new DbValue.null ();
                        continue;
                    }
                    values[i] = decode (c, pg, s, e - s);
                }
            }
            return values;
        }

        private int fixed_size (MdbColumn c) {
            switch (c.kind) {
                case MdbColumnType.BYTE: return 1;
                case MdbColumnType.INTEGER: return 2;
                case MdbColumnType.LONG: return c.code == 0x13 ? 8 : 4;
                case MdbColumnType.COMPLEX: return 4;
                case MdbColumnType.FLOAT: return 4;
                case MdbColumnType.MONEY:
                case MdbColumnType.DOUBLE:
                case MdbColumnType.DATETIME: return 8;
                case MdbColumnType.GUID: return 16;
                case MdbColumnType.NUMERIC: return 17;
                default: return c.size;
            }
        }

        private DbValue decode (MdbColumn c, uint8[] b, int p, int len) {
            switch (c.kind) {
                case MdbColumnType.BYTE: return new DbValue.int (b[p]);
                case MdbColumnType.INTEGER: return new DbValue.int ((int16) u16 (b, p));
                case MdbColumnType.LONG:
                    if (c.code == 0x13 && len >= 8) return new DbValue.int (i64 (b, p));
                    return new DbValue.int ((int32) u32 (b, p));
                case MdbColumnType.COMPLEX: return new DbValue.int ((int32) u32 (b, p));
                case MdbColumnType.MONEY: return new DbValue.real (MdbCodec.money (i64 (b, p)));
                case MdbColumnType.FLOAT: return new DbValue.real ((double) f32 (b, p));
                case MdbColumnType.DOUBLE: return new DbValue.real (f64 (b, p));
                case MdbColumnType.DATETIME:
                    string iso = MdbCodec.ole_date (f64 (b, p));
                    return iso == "" ? new DbValue.null () : new DbValue.text (iso);
                case MdbColumnType.GUID:
                    if (len < 16) return new DbValue.null ();
                    return new DbValue.text (MdbCodec.guid (b, p));
                case MdbColumnType.NUMERIC:
                    if (len < 17) return new DbValue.null ();
                    return new DbValue.real (MdbCodec.numeric (b, p, c.scale));
                case MdbColumnType.TEXT:
                    return new DbValue.text (name_text (b, p, len));
                case MdbColumnType.MEMO:
                    var mem = long_value (b, p, len);
                    if (mem == null) return new DbValue.null ();
                    return new DbValue.text (name_text (mem, 0, mem.length));
                case MdbColumnType.OLE:
                    var ole = long_value (b, p, len);
                    if (ole == null) return new DbValue.null ();
                    return new DbValue.blob (new Bytes (ole));
                default:
                    return new DbValue.blob (new Bytes (b[p:p + len]));
            }
        }

        private uint8[]? long_value (uint8[] b, int p, int len) {
            if (len < 12) return null;
            uint32 head = u32 (b, p);
            int total = (int) (head & 0x3FFFFFFF);
            uint32 kind = head & 0xC0000000;
            if (total == 0) return new uint8[0];
            if (kind == 0x80000000) {
                int n = int.min (total, len - 12);
                return b[p + 12:p + 12 + n];
            }
            uint32 pointer = u32 (b, p + 4);
            if (kind == 0x40000000) {
                var r = row_data (pointer);
                if (r == null) return null;
                return r.length > total ? r[0:total] : r;
            }
            var buf = new ByteArray ();
            int guard = 0;
            while (pointer != 0 && buf.len < total && guard++ < 1000000) {
                var r = row_data (pointer);
                if (r == null || r.length < 4) break;
                pointer = u32 (r, 0);
                buf.append (r[4:r.length]);
            }
            var result = buf.steal ();
            if (result.length > total) result.length = total;
            return result;
        }

        private void read_catalog () throws Error {
            var cat = read_tdef (2);
            var rows = read_rows (cat);
            int id_i = -1, name_i = -1, type_i = -1, flags_i = -1;
            for (int i = 0; i < cat.columns.size; i++) {
                switch (cat.columns[i].name) {
                    case "Id": id_i = i; break;
                    case "Name": name_i = i; break;
                    case "Type": type_i = i; break;
                    case "Flags": flags_i = i; break;
                }
            }
            if (id_i < 0 || name_i < 0 || type_i < 0) throw new MdbError.FORMAT (_("The Access catalog could not be read."));
            int rel_page = -1;
            var user = new Gee.ArrayList<int> ();
            var names = new Gee.ArrayList<string> ();
            string[] queries = {};
            var query_ids = new Gee.ArrayList<int> ();
            var query_flags = new Gee.ArrayList<int> ();
            var query_list = new Gee.ArrayList<string> ();
            string[] forms = {}, reports = {}, macros = {}, modules = {};
            foreach (var r in rows) {
                int raw_type = (int) r.get (type_i).as_int ();
                int type = raw_type & 0x7FFF;
                string name = r.get (name_i).to_string ();
                int64 flags = flags_i >= 0 ? r.get (flags_i).as_int () : 0;
                int tpage = (int) (r.get (id_i).as_int () & 0x00FFFFFF);
                if (raw_type == -32768) {
                    if (!name.has_prefix ("~")) forms += name;
                    continue;
                }
                if (raw_type == -32764) {
                    if (!name.has_prefix ("~")) reports += name;
                    continue;
                }
                if (raw_type == -32766) {
                    if (!name.has_prefix ("~")) macros += name;
                    continue;
                }
                if (raw_type == -32761) {
                    if (!name.has_prefix ("~")) modules += name;
                    continue;
                }
                if (type == 1) {
                    object_names[tpage] = name;
                    if (!system_pages.has_key (name.casefold ())) system_pages[name.casefold ()] = tpage;
                    if (name == "MSysRelationships") rel_page = tpage;
                    bool system = (flags & 0x80000002) != 0 || name.has_prefix ("MSys") || name.has_prefix ("USys") || name.has_prefix ("~");
                    if (!system) {
                        user.add (tpage);
                        names.add (name);
                    }
                } else if (type == 5 && !name.has_prefix ("~")) {
                    queries += name;
                    query_list.add (name);
                    query_ids.add ((int) r.get (id_i).as_int ());
                    query_flags.add ((int) flags);
                }
            }
            form_names = forms;
            report_names = reports;
            macro_names = macros;
            module_names = modules;
            query_names = queries;
            for (int i = 0; i < user.size; i++) {
                var pg = page (user[i]);
                if (pg == null || pg[0] != 0x02) continue;
                var def = read_tdef (user[i]);
                var t = new MdbTable ();
                t.name = names[i];
                foreach (var c in def.columns) {
                    if (c.hidden && (c.name.has_prefix ("s_") || c.name.has_prefix ("Gen_"))) continue;
                    t.columns.add (c);
                }
                var raw = read_rows (def);
                if (t.columns.size == def.columns.size) {
                    t.rows = raw;
                } else {
                    int[] keep = {};
                    for (int k = 0; k < def.columns.size; k++) {
                        if (t.columns.contains (def.columns[k])) keep += k;
                    }
                    foreach (var r in raw) {
                        DbValue[] v = new DbValue[keep.length];
                        for (int k = 0; k < keep.length; k++) v[k] = r.values[keep[k]];
                        t.rows.add (new Row (r.rowid, (owned) v));
                    }
                }
                t.primary_key = def.primary_key;
                tables.add (t);
                foreach (var c in t.columns) {
                    if (c.kind == MdbColumnType.COMPLEX) load_complex (t, c, user[i]);
                }
            }
            if (rel_page > 0) read_relationships (rel_page);
            read_queries (query_list, query_ids, query_flags);
        }

        private void read_relationships (int tpage) {
            try {
                var def = read_tdef (tpage);
                var rows = read_rows (def);
                int grbit = -1, icol = -1, col = -1, obj = -1, rcol = -1, robj = -1, rname = -1;
                for (int i = 0; i < def.columns.size; i++) {
                    switch (def.columns[i].name) {
                        case "grbit": grbit = i; break;
                        case "icolumn": icol = i; break;
                        case "szColumn": col = i; break;
                        case "szObject": obj = i; break;
                        case "szReferencedColumn": rcol = i; break;
                        case "szReferencedObject": robj = i; break;
                        case "szRelationship": rname = i; break;
                    }
                }
                if (col < 0 || obj < 0 || rcol < 0 || robj < 0 || rname < 0) return;
                var by_name = new Gee.HashMap<string, MdbRelationship> ();
                var order = new Gee.HashMap<string, Gee.TreeMap<int, ColumnPair>> ();
                foreach (var r in rows) {
                    string n = r.get (rname).to_string ();
                    var rel = by_name[n];
                    if (rel == null) {
                        rel = new MdbRelationship ();
                        rel.name = n;
                        rel.table = r.get (obj).to_string ();
                        rel.ref_table = r.get (robj).to_string ();
                        int64 g = grbit >= 0 ? r.get (grbit).as_int () : 0;
                        rel.enforce = (g & 0x02) == 0;
                        rel.cascade_update = (g & 0x100) != 0;
                        rel.cascade_delete = (g & 0x1000) != 0;
                        by_name[n] = rel;
                        order[n] = new Gee.TreeMap<int, ColumnPair> ();
                        relationships.add (rel);
                    }
                    int k = icol >= 0 ? (int) r.get (icol).as_int () : order[n].size;
                    var pair = new ColumnPair ();
                    pair.column = r.get (col).to_string ();
                    pair.ref_column = r.get (rcol).to_string ();
                    order[n][k] = pair;
                }
                var user_rels = new Gee.ArrayList<MdbRelationship> ();
                foreach (var rel in relationships) {
                    if (find_table (rel.table) != null && find_table (rel.ref_table) != null) user_rels.add (rel);
                }
                relationships = user_rels;
                foreach (var rel in relationships) {
                    string[] a = {}, b = {};
                    foreach (var pair in order[rel.name].values) {
                        a += pair.column;
                        b += pair.ref_column;
                    }
                    rel.columns = a;
                    rel.ref_columns = b;
                }
            } catch (Error e) {
            }
        }

        private void read_queries (Gee.ArrayList<string> names, Gee.ArrayList<int> ids, Gee.ArrayList<int> flags) {
            if (names.size == 0) return;
            var qt = read_system_named ("MSysQueries");
            var by_id = new Gee.HashMap<string, Gee.ArrayList<MdbQueryRow>> ();
            if (qt != null) {
                int a_i = qt.index_of ("Attribute"), e_i = qt.index_of ("Expression"), f_i = qt.index_of ("Flag"), x_i = qt.index_of ("LvExtra");
                int n1_i = qt.index_of ("Name1"), n2_i = qt.index_of ("Name2"), o_i = qt.index_of ("ObjectId");
                foreach (var r in qt.rows) {
                    var q = new MdbQueryRow ();
                    q.attribute = a_i >= 0 ? (int) r.get (a_i).as_int () : -1;
                    q.expression = text_or_null (r, e_i);
                    q.flag = f_i >= 0 && !r.get (f_i).is_null ? (int) r.get (f_i).as_int () : 0;
                    q.has_flag = f_i >= 0 && !r.get (f_i).is_null;
                    if (x_i >= 0) {
                        var xv = r.get (x_i);
                        if (xv.is_number ()) q.extra = (int) xv.as_int ();
                        else if (xv.kind == ValueKind.BLOB && xv.blob_value.get_size () >= 4) q.extra = (int) le32 (xv.blob_value.get_data (), 0);
                    }
                    q.name1 = text_or_null (r, n1_i);
                    q.name2 = text_or_null (r, n2_i);
                    string key = o_i >= 0 ? r.get (o_i).as_int ().to_string () : "";
                    var list = by_id[key];
                    if (list == null) {
                        list = new Gee.ArrayList<MdbQueryRow> ();
                        by_id[key] = list;
                    }
                    list.add (q);
                }
            }
            for (int i = 0; i < names.size; i++) {
                var q = new MdbQuery ();
                q.name = names[i];
                var rows = by_id[ids[i].to_string ()] ?? new Gee.ArrayList<MdbQueryRow> ();
                var builder = new MdbQueryBuilder (rows);
                q.kind = builder.resolve_kind (flags[i]);
                try {
                    q.sql = builder.to_sql (q.kind);
                    q.parameters = builder.parameters ();
                    q.parameter_names = builder.parameter_names;
                    q.parameter_types = builder.parameter_types;
                    if (q.kind == MdbQueryKind.PASS_THROUGH) q.connection = builder.type_row ().name1 ?? "";
                } catch (Error e) {
                    q.sql = "";
                }
                q.hidden = (flags[i] & 0x08) != 0;
                queries.add (q);
            }
        }

        private static uint32 le32 (uint8[] b, int p) {
            return (uint32) b[p] | ((uint32) b[p + 1] << 8) | ((uint32) b[p + 2] << 16) | ((uint32) b[p + 3] << 24);
        }

        private static string? text_or_null (Row r, int i) {
            if (i < 0) return null;
            var v = r.get (i);
            if (v.is_null) return null;
            return v.to_string ();
        }

        private MdbTable? read_system_table (int tpage) {
            try {
                var pg = page (tpage);
                if (pg == null || pg[0] != 0x02) return null;
                var def = read_tdef (tpage);
                var t = new MdbTable ();
                t.name = object_names.has_key (tpage) ? object_names[tpage] : "";
                t.columns = def.columns;
                t.rows = read_rows (def);
                t.primary_key = def.primary_key;
                return t;
            } catch (Error e) {
                return null;
            }
        }

        private MdbTable? read_system_named (string name) {
            if (!system_pages.has_key (name.casefold ())) return null;
            return read_system_table (system_pages[name.casefold ()]);
        }

        private MdbTable? complex_columns_cache;
        private bool complex_columns_read;

        private void load_complex (MdbTable t, MdbColumn c, int tdef_page) {
            int col_index = t.columns.index_of (c);
            if (col_index < 0) return;
            c.complex_kind = MdbComplexKind.UNKNOWN;
            if (!complex_columns_read) {
                complex_columns_cache = read_system_named ("MSysComplexColumns");
                complex_columns_read = true;
            }
            var cc = complex_columns_cache;
            if (cc == null) return;
            int id_i = cc.index_of ("ComplexID"), flat_i = cc.index_of ("FlatTableID"), type_i = cc.index_of ("ComplexTypeObjectID"), name_i = cc.index_of ("ColumnName"), table_i = cc.index_of ("ConceptualTableID");
            if (id_i < 0 || flat_i < 0 || type_i < 0) return;
            Row? info = null;
            foreach (var r in cc.rows) {
                if (r.get (id_i).as_int () == c.complex_id) {
                    info = r;
                    break;
                }
            }
            if (info == null) {
                foreach (var r in cc.rows) {
                    bool same_table = table_i < 0 || (int) (r.get (table_i).as_int () & 0x00FFFFFF) == tdef_page;
                    if (same_table && name_i >= 0 && r.get (name_i).to_string ().casefold () == c.name.casefold ()) {
                        info = r;
                        break;
                    }
                }
            }
            if (info == null) return;
            var type_table = read_system_table ((int) (info.get (type_i).as_int () & 0x00FFFFFF));
            var flat = read_system_table ((int) (info.get (flat_i).as_int () & 0x00FFFFFF));
            if (type_table == null || flat == null) return;
            var data = new MdbComplexData ();
            data.flat = flat;
            int[] values = {};
            int pk = -1, fk = -1;
            for (int k = 0; k < flat.columns.size; k++) {
                var fc = flat.columns[k];
                if (type_table.index_of (fc.name) >= 0) {
                    values += k;
                } else if (fc.kind == MdbColumnType.COMPLEX) {
                    fk = k;
                } else if (fc.autonumber) {
                    pk = k;
                }
            }
            if (fk < 0) {
                for (int k = 0; k < flat.columns.size; k++) {
                    var fc = flat.columns[k];
                    if (k in values || k == pk) continue;
                    if (fc.kind == MdbColumnType.LONG && !fc.autonumber) fk = k;
                }
            }
            if (fk < 0) return;
            data.value_columns = values;
            string tname = type_table.name;
            if (tname.casefold () == "msyscomplextype_attachment".casefold ()) data.kind = MdbComplexKind.ATTACHMENT;
            else if (tname.down ().has_prefix ("msyscomplextypevh_")) data.kind = MdbComplexKind.VERSION_HISTORY;
            else if (type_table.columns.size == 1 && multi_value_type (type_table.columns[0].kind)) data.kind = MdbComplexKind.MULTI_VALUE;
            else if (attachment_shape (type_table)) data.kind = MdbComplexKind.ATTACHMENT;
            else data.kind = MdbComplexKind.UNKNOWN;
            foreach (var r in flat.rows) {
                string key = r.get (fk).as_int ().to_string ();
                var list = data.by_key[key];
                if (list == null) {
                    list = new Gee.ArrayList<Row> ();
                    data.by_key[key] = list;
                }
                list.add (r);
            }
            if (pk >= 0) {
                int p = pk;
                foreach (var list in data.by_key.values) list.sort ((a, b) => a.get (p).compare (b.get (p)));
            }
            c.complex_kind = data.kind;
            t.complex[col_index] = data;
        }

        private static bool multi_value_type (MdbColumnType k) {
            return k == MdbColumnType.BYTE || k == MdbColumnType.INTEGER || k == MdbColumnType.LONG || k == MdbColumnType.FLOAT
                || k == MdbColumnType.DOUBLE || k == MdbColumnType.GUID || k == MdbColumnType.NUMERIC || k == MdbColumnType.TEXT;
        }

        private static bool attachment_shape (MdbTable t) {
            int memo = 0, text = 0, date = 0, ole = 0, lng = 0;
            foreach (var c in t.columns) {
                switch (c.kind) {
                    case MdbColumnType.MEMO: memo++; break;
                    case MdbColumnType.TEXT: text++; break;
                    case MdbColumnType.DATETIME: date++; break;
                    case MdbColumnType.OLE: ole++; break;
                    case MdbColumnType.LONG: lng++; break;
                    default: break;
                }
            }
            return t.columns.size >= 6 && memo >= 1 && text >= 2 && date >= 1 && ole >= 1 && lng >= 1;
        }

        private Gee.ArrayList<Row> complex_rows (MdbTable t, int row, int column, out MdbComplexData? data) {
            data = t.complex[column];
            var empty = new Gee.ArrayList<Row> ();
            if (data == null || row < 0 || row >= t.rows.size) return empty;
            var v = t.rows[row].get (column);
            if (v.is_null) return empty;
            return data.by_key[v.as_int ().to_string ()] ?? empty;
        }

        public Gee.ArrayList<DbValue> multi_values (MdbTable t, int row, int column) {
            var list = new Gee.ArrayList<DbValue> ();
            MdbComplexData? data;
            var rows = complex_rows (t, row, column, out data);
            if (data == null || data.kind != MdbComplexKind.MULTI_VALUE || data.value_columns.length == 0) return list;
            foreach (var r in rows) list.add (r.get (data.value_columns[0]));
            return list;
        }

        public Gee.ArrayList<MdbAttachment> attachments (MdbTable t, int row, int column) {
            var list = new Gee.ArrayList<MdbAttachment> ();
            MdbComplexData? data;
            var rows = complex_rows (t, row, column, out data);
            if (data == null || data.kind != MdbComplexKind.ATTACHMENT) return list;
            int name_c = -1, type_c = -1, data_c = -1, url_c = -1, time_c = -1, flags_c = -1;
            foreach (int k in data.value_columns) {
                var c = data.flat.columns[k];
                switch (c.kind) {
                    case MdbColumnType.TEXT:
                        if (c.name.casefold () == "filename") name_c = k;
                        else if (c.name.casefold () == "filetype") type_c = k;
                        else if (name_c < 0) name_c = k;
                        else if (type_c < 0) type_c = k;
                        break;
                    case MdbColumnType.LONG: flags_c = k; break;
                    case MdbColumnType.DATETIME: time_c = k; break;
                    case MdbColumnType.OLE: data_c = k; break;
                    case MdbColumnType.MEMO: url_c = k; break;
                    default: break;
                }
            }
            foreach (var r in rows) {
                var a = new MdbAttachment ();
                if (name_c >= 0) a.name = r.get (name_c).to_string ();
                if (type_c >= 0) a.file_type = r.get (type_c).to_string ();
                if (url_c >= 0) a.url = r.get (url_c).to_string ();
                if (time_c >= 0) a.timestamp = r.get (time_c).to_string ();
                if (flags_c >= 0) a.flags = (int) r.get (flags_c).as_int ();
                if (data_c >= 0) {
                    var raw = r.get (data_c);
                    if (raw.kind == ValueKind.BLOB) {
                        try {
                            a.data = MdbCodec.attachment_content (raw.blob_value.get_data ());
                        } catch (Error e) {
                            a.data = raw.blob_value;
                        }
                    }
                }
                list.add (a);
            }
            return list;
        }

        public MdbComplexKind complex_kind (MdbTable t, int column) {
            var data = t.complex[column];
            return data != null ? data.kind : MdbComplexKind.NONE;
        }

        public MdbTable? find_table (string name) {
            foreach (var t in tables) {
                if (t.name.casefold () == name.casefold ()) return t;
            }
            return null;
        }
    }
}
