namespace Singularity.Apps.Database {

    public class MyWriter {
        public ByteArray buf = new ByteArray ();

        public void u8 (uint v) {
            uint8[] b = { (uint8) (v & 0xff) };
            buf.append (b);
        }

        public void u16 (uint v) {
            uint8[] b = { (uint8) (v & 0xff), (uint8) ((v >> 8) & 0xff) };
            buf.append (b);
        }

        public void u24 (uint v) {
            uint8[] b = { (uint8) (v & 0xff), (uint8) ((v >> 8) & 0xff), (uint8) ((v >> 16) & 0xff) };
            buf.append (b);
        }

        public void u32 (uint32 v) {
            uint8[] b = { (uint8) (v & 0xff), (uint8) ((v >> 8) & 0xff), (uint8) ((v >> 16) & 0xff), (uint8) ((v >> 24) & 0xff) };
            buf.append (b);
        }

        public void u64 (uint64 v) {
            u32 ((uint32) (v & 0xffffffff));
            u32 ((uint32) (v >> 32));
        }

        public void lenenc_int (uint64 v) {
            if (v < 251) {
                u8 ((uint) v);
            } else if (v < 0x10000) {
                u8 (0xfc);
                u16 ((uint) v);
            } else if (v < 0x1000000) {
                u8 (0xfd);
                u24 ((uint) v);
            } else {
                u8 (0xfe);
                u64 (v);
            }
        }

        public void bytes (uint8[] data) {
            buf.append (data);
        }

        public void lenenc_bytes (uint8[] data) {
            lenenc_int (data.length);
            buf.append (data);
        }

        public void null_str (string s) {
            buf.append (s.data);
            u8 (0);
        }

        public void zeros (int n) {
            for (int i = 0; i < n; i++) u8 (0);
        }

        public uint8[] take () {
            return buf.steal ();
        }
    }

    public class MyReader {
        public uint8[] data;
        public int pos;
        public bool last_null;

        public MyReader (uint8[] data) {
            this.data = data;
        }

        public int remaining () {
            return data.length - pos;
        }

        public bool at_end () {
            return pos >= data.length;
        }

        private void need (int n) throws RemoteError {
            if (pos + n > data.length) throw new RemoteError.PROTOCOL (_("The server sent a truncated packet."));
        }

        public uint8 u8 () throws RemoteError {
            need (1);
            return data[pos++];
        }

        public uint u16 () throws RemoteError {
            need (2);
            uint v = data[pos] | (data[pos + 1] << 8);
            pos += 2;
            return v;
        }

        public uint u24 () throws RemoteError {
            need (3);
            uint v = data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16);
            pos += 3;
            return v;
        }

        public uint32 u32 () throws RemoteError {
            need (4);
            uint32 v = (uint32) data[pos] | ((uint32) data[pos + 1] << 8) | ((uint32) data[pos + 2] << 16) | ((uint32) data[pos + 3] << 24);
            pos += 4;
            return v;
        }

        public uint64 u64 () throws RemoteError {
            uint64 lo = u32 ();
            uint64 hi = u32 ();
            return lo | (hi << 32);
        }

        public uint64 lenenc_int () throws RemoteError {
            last_null = false;
            uint8 first = u8 ();
            if (first < 0xfb) return first;
            if (first == 0xfb) {
                last_null = true;
                return 0;
            }
            if (first == 0xfc) return u16 ();
            if (first == 0xfd) return u24 ();
            if (first == 0xfe) return u64 ();
            throw new RemoteError.PROTOCOL (_("The server sent an invalid length."));
        }

        public uint8[] take (int n) throws RemoteError {
            need (n);
            uint8[] out_b = data[pos:pos + n];
            pos += n;
            return out_b;
        }

        public uint8[]? lenenc_bytes () throws RemoteError {
            uint64 n = lenenc_int ();
            if (last_null) return null;
            return take ((int) n);
        }

        public string lenenc_str () throws RemoteError {
            var b = lenenc_bytes ();
            return b == null ? "" : MyCodec.to_str (b);
        }

        public string null_str () throws RemoteError {
            int start = pos;
            while (pos < data.length && data[pos] != 0) pos++;
            string s = MyCodec.to_str (data[start:pos]);
            if (pos < data.length) pos++;
            return s;
        }

        public string rest_str () {
            string s = MyCodec.to_str (data[pos:data.length]);
            pos = data.length;
            return s;
        }

        public uint8[] rest () {
            uint8[] b = data[pos:data.length];
            pos = data.length;
            return b;
        }
    }

    public class MyCodec {
        public const uint32 LONG_PASSWORD = 1;
        public const uint32 FOUND_ROWS = 2;
        public const uint32 LONG_FLAG = 4;
        public const uint32 CONNECT_WITH_DB = 8;
        public const uint32 PROTOCOL_41 = 0x200;
        public const uint32 SSL = 0x800;
        public const uint32 TRANSACTIONS = 0x2000;
        public const uint32 SECURE_CONNECTION = 0x8000;
        public const uint32 MULTI_STATEMENTS = 0x10000;
        public const uint32 MULTI_RESULTS = 0x20000;
        public const uint32 PS_MULTI_RESULTS = 0x40000;
        public const uint32 PLUGIN_AUTH = 0x80000;
        public const uint32 PLUGIN_AUTH_LENENC = 0x200000;
        public const uint32 DEPRECATE_EOF = 0x1000000;

        public const uint STATUS_MORE_RESULTS = 0x0008;
        public const uint STATUS_NO_BACKSLASH_ESCAPES = 0x0200;

        public const int MAX_PAYLOAD = 0xffffff;

        public static string to_str (uint8[] b) {
            var sb = new StringBuilder.sized (b.length + 1);
            sb.append_len ((string) b, b.length);
            string s = sb.str;
            if (!s.validate ()) return s.make_valid ();
            return s;
        }

        public static uint8[] frame (uint8[] payload, ref uint8 seq) {
            var out_b = new ByteArray ();
            int pos = 0;
            while (true) {
                int len = int.min (MAX_PAYLOAD, payload.length - pos);
                uint8[] hdr = { (uint8) (len & 0xff), (uint8) ((len >> 8) & 0xff), (uint8) ((len >> 16) & 0xff), seq };
                seq++;
                out_b.append (hdr);
                if (len > 0) out_b.append (payload[pos:pos + len]);
                pos += len;
                if (len < MAX_PAYLOAD) break;
            }
            return out_b.steal ();
        }

        public static Gee.ArrayList<Bytes> deframe (uint8[] stream, out int consumed) throws RemoteError {
            var list = new Gee.ArrayList<Bytes> ();
            int pos = 0;
            consumed = 0;
            var cur = new ByteArray ();
            while (pos + 4 <= stream.length) {
                int len = stream[pos] | (stream[pos + 1] << 8) | (stream[pos + 2] << 16);
                if (pos + 4 + len > stream.length) break;
                cur.append (stream[pos + 4:pos + 4 + len]);
                pos += 4 + len;
                if (len < MAX_PAYLOAD) {
                    list.add (ByteArray.free_to_bytes (cur));
                    cur = new ByteArray ();
                    consumed = pos;
                }
            }
            return list;
        }

        public static uint8[] digest (ChecksumType type, uint8[] data) {
            var c = new Checksum (type);
            c.update (data, data.length);
            size_t len = type == ChecksumType.SHA1 ? 20 : 32;
            uint8[] out_b = new uint8[len];
            c.get_digest (out_b, ref len);
            return out_b;
        }

        private static uint8[] concat (uint8[] a, uint8[] b) {
            var ba = new ByteArray ();
            ba.append (a);
            ba.append (b);
            return ba.steal ();
        }

        public static uint8[] native_scramble (string password, uint8[] nonce) {
            if (password == "") return {};
            uint8[] s1 = digest (ChecksumType.SHA1, password.data);
            uint8[] s2 = digest (ChecksumType.SHA1, s1);
            uint8[] s3 = digest (ChecksumType.SHA1, concat (nonce, s2));
            uint8[] out_b = new uint8[20];
            for (int i = 0; i < 20; i++) out_b[i] = s1[i] ^ s3[i];
            return out_b;
        }

        public static uint8[] sha2_scramble (string password, uint8[] nonce) {
            if (password == "") return {};
            uint8[] d1 = digest (ChecksumType.SHA256, password.data);
            uint8[] d2 = digest (ChecksumType.SHA256, d1);
            uint8[] d3 = digest (ChecksumType.SHA256, concat (d2, nonce));
            uint8[] out_b = new uint8[32];
            for (int i = 0; i < 32; i++) out_b[i] = d1[i] ^ d3[i];
            return out_b;
        }

        public static uint8[] xor_password (string password, uint8[] nonce) {
            uint8[] pw = concat (password.data, { 0 });
            if (nonce.length == 0) return pw;
            for (int i = 0; i < pw.length; i++) pw[i] = pw[i] ^ nonce[i % nonce.length];
            return pw;
        }

        public static string type_name (uint8 code, uint flags, uint charset, uint32 length) {
            bool unsigned = (flags & 32) != 0;
            string u = unsigned ? " UNSIGNED" : "";
            bool bin = charset == 63;
            switch (code) {
                case 0:
                case 246: return "DECIMAL";
                case 1: return (length == 1 ? "TINYINT(1)" : "TINYINT") + u;
                case 2: return "SMALLINT" + u;
                case 3: return "INT" + u;
                case 4: return "FLOAT";
                case 5: return "DOUBLE";
                case 6: return "NULL";
                case 7: return "TIMESTAMP";
                case 8: return "BIGINT" + u;
                case 9: return "MEDIUMINT" + u;
                case 10: return "DATE";
                case 11: return "TIME";
                case 12: return "DATETIME";
                case 13: return "YEAR";
                case 15:
                case 253: return bin ? "VARBINARY" : "VARCHAR";
                case 16: return "BIT";
                case 245: return "JSON";
                case 247: return "ENUM";
                case 248: return "SET";
                case 249: return bin ? "TINYBLOB" : "TINYTEXT";
                case 250: return bin ? "MEDIUMBLOB" : "MEDIUMTEXT";
                case 251: return bin ? "LONGBLOB" : "LONGTEXT";
                case 252: return bin ? "BLOB" : "TEXT";
                case 254: return bin ? "BINARY" : "CHAR";
                case 255: return "GEOMETRY";
                default: return "UNKNOWN";
            }
        }

        public static bool is_binary (uint8 code, uint charset) {
            if (code == 255) return true;
            if (charset != 63) return false;
            return code == 249 || code == 250 || code == 251 || code == 252 || code == 253 || code == 254 || code == 15;
        }

        public static DbValue decimal_value (string s) {
            int digits = 0;
            bool leading = true;
            for (int i = 0; i < s.length; i++) {
                char c = s[i];
                if (!c.isdigit ()) continue;
                if (leading && c == '0') continue;
                leading = false;
                digits++;
            }
            double d = 0;
            if (digits <= 15 && double.try_parse (s, out d)) return new DbValue.real (d);
            return new DbValue.text (s);
        }

        public static DbValue integer_value (string s, bool unsigned) {
            int64 v;
            if (int64.try_parse (s, out v)) return new DbValue.int (v);
            return new DbValue.text (s);
        }

        public static DbValue decode_text (MyColumnDef c, uint8[]? raw) {
            if (raw == null) return new DbValue.null ();
            switch (c.type_code) {
                case 1:
                case 2:
                case 3:
                case 8:
                case 9:
                case 13:
                    return integer_value (to_str (raw), (c.flags & 32) != 0);
                case 4:
                case 5:
                    double d;
                    string fs = to_str (raw);
                    if (double.try_parse (fs, out d)) return new DbValue.real (d);
                    return new DbValue.text (fs);
                case 0:
                case 246:
                    return decimal_value (to_str (raw));
                case 16:
                    uint64 bits = 0;
                    foreach (uint8 b in raw) bits = (bits << 8) | b;
                    return new DbValue.int ((int64) bits);
                default:
                    if (is_binary (c.type_code, c.charset)) return new DbValue.blob (new Bytes (raw));
                    return new DbValue.text (to_str (raw));
            }
        }

        public static DbValue decode_binary (MyColumnDef c, MyReader r) throws RemoteError {
            bool unsigned = (c.flags & 32) != 0;
            switch (c.type_code) {
                case 1:
                    uint8 t = r.u8 ();
                    return new DbValue.int (unsigned ? (int64) t : (int64) (int8) t);
                case 2:
                case 13:
                    uint s = r.u16 ();
                    return new DbValue.int (unsigned || c.type_code == 13 ? (int64) s : (int64) (int16) s);
                case 3:
                case 9:
                    uint32 l = r.u32 ();
                    return new DbValue.int (unsigned ? (int64) l : (int64) (int32) l);
                case 8:
                    uint64 ll = r.u64 ();
                    if (unsigned && ll > int64.MAX) return new DbValue.text (ll.to_string ());
                    return new DbValue.int ((int64) ll);
                case 4:
                    uint32 fb = r.u32 ();
                    float f = 0;
                    Memory.copy (&f, &fb, 4);
                    return new DbValue.real ((double) f);
                case 5:
                    uint64 db = r.u64 ();
                    double d = 0;
                    Memory.copy (&d, &db, 8);
                    return new DbValue.real (d);
                case 7:
                case 10:
                case 12:
                    return new DbValue.text (binary_datetime (r, c.type_code == 10));
                case 11:
                    return new DbValue.text (binary_time (r));
                default:
                    var raw = r.lenenc_bytes ();
                    return decode_text (c, raw);
            }
        }

        public static string binary_datetime (MyReader r, bool date_only) throws RemoteError {
            uint8 len = r.u8 ();
            int y = 0, mo = 0, d = 0, h = 0, mi = 0, s = 0;
            uint32 micro = 0;
            if (len >= 4) {
                y = (int) r.u16 ();
                mo = r.u8 ();
                d = r.u8 ();
            }
            if (len >= 7) {
                h = r.u8 ();
                mi = r.u8 ();
                s = r.u8 ();
            }
            if (len >= 11) micro = r.u32 ();
            string date = "%04d-%02d-%02d".printf (y, mo, d);
            if (date_only) return date;
            string t = "%s %02d:%02d:%02d".printf (date, h, mi, s);
            if (micro > 0) t += ".%06u".printf (micro);
            return t;
        }

        public static string binary_time (MyReader r) throws RemoteError {
            uint8 len = r.u8 ();
            bool neg = false;
            uint32 days = 0;
            int h = 0, mi = 0, s = 0;
            uint32 micro = 0;
            if (len >= 8) {
                neg = r.u8 () != 0;
                days = r.u32 ();
                h = r.u8 ();
                mi = r.u8 ();
                s = r.u8 ();
            }
            if (len >= 12) micro = r.u32 ();
            string t = "%s%02u:%02d:%02d".printf (neg ? "-" : "", days * 24 + h, mi, s);
            if (micro > 0) t += ".%06u".printf (micro);
            return t;
        }

        public static string escape_string (string s, bool no_backslash) {
            var sb = new StringBuilder ("'");
            for (int i = 0; i < s.length; i++) {
                char c = s[i];
                if (c == '\'') {
                    sb.append ("''");
                } else if (no_backslash) {
                    sb.append_c (c);
                } else {
                    switch (c) {
                        case '\\': sb.append ("\\\\"); break;
                        case '\0': sb.append ("\\0"); break;
                        case '\n': sb.append ("\\n"); break;
                        case '\r': sb.append ("\\r"); break;
                        case '\x1a': sb.append ("\\Z"); break;
                        default: sb.append_c (c); break;
                    }
                }
            }
            sb.append_c ('\'');
            return sb.str;
        }
    }

    public class MyColumnDef {
        public string schema = "";
        public string table = "";
        public string org_table = "";
        public string name = "";
        public string org_name = "";
        public uint charset;
        public uint32 length;
        public uint8 type_code;
        public uint flags;
        public uint8 decimals;

        public static MyColumnDef parse (uint8[] payload) throws RemoteError {
            var r = new MyReader (payload);
            var c = new MyColumnDef ();
            r.lenenc_str ();
            c.schema = r.lenenc_str ();
            c.table = r.lenenc_str ();
            c.org_table = r.lenenc_str ();
            c.name = r.lenenc_str ();
            c.org_name = r.lenenc_str ();
            r.lenenc_int ();
            c.charset = r.u16 ();
            c.length = r.u32 ();
            c.type_code = r.u8 ();
            c.flags = r.u16 ();
            c.decimals = r.u8 ();
            return c;
        }

        public ColumnMeta to_meta () {
            var m = new ColumnMeta (name);
            m.type_name = MyCodec.type_name (type_code, flags, charset, length);
            m.type_oid = type_code;
            m.table = org_table != "" ? org_table : table;
            m.origin = org_name;
            return m;
        }
    }

    public class MyBigNum {
        public uint32[] w;

        public MyBigNum (int limbs) {
            w = new uint32[limbs];
        }

        public static MyBigNum from_bytes (uint8[] be, int limbs) {
            var n = new MyBigNum (limbs);
            int k = 0;
            for (int i = be.length - 1; i >= 0; i--, k++) {
                int limb = k / 4;
                if (limb >= limbs) break;
                n.w[limb] |= ((uint32) be[i]) << ((k % 4) * 8);
            }
            return n;
        }

        public uint8[] to_bytes (int len) {
            uint8[] out_b = new uint8[len];
            for (int k = 0; k < len; k++) {
                int limb = k / 4;
                uint8 v = limb < w.length ? (uint8) ((w[limb] >> ((k % 4) * 8)) & 0xff) : 0;
                out_b[len - 1 - k] = v;
            }
            return out_b;
        }

        public int cmp (MyBigNum o) {
            for (int i = w.length - 1; i >= 0; i--) {
                if (w[i] != o.w[i]) return w[i] > o.w[i] ? 1 : -1;
            }
            return 0;
        }

        public void sub (MyBigNum o) {
            int64 borrow = 0;
            for (int i = 0; i < w.length; i++) {
                int64 v = (int64) w[i] - (int64) o.w[i] - borrow;
                if (v < 0) {
                    v += 0x100000000;
                    borrow = 1;
                } else {
                    borrow = 0;
                }
                w[i] = (uint32) v;
            }
        }

        public void add (MyBigNum o) {
            uint64 carry = 0;
            for (int i = 0; i < w.length; i++) {
                uint64 v = (uint64) w[i] + (uint64) o.w[i] + carry;
                w[i] = (uint32) (v & 0xffffffff);
                carry = v >> 32;
            }
        }

        public void shl1 () {
            uint32 carry = 0;
            for (int i = 0; i < w.length; i++) {
                uint32 next = w[i] >> 31;
                w[i] = (w[i] << 1) | carry;
                carry = next;
            }
        }

        public bool bit (int i) {
            return ((w[i / 32] >> (i % 32)) & 1) != 0;
        }

        public int bitlen () {
            for (int i = w.length - 1; i >= 0; i--) {
                if (w[i] != 0) {
                    int b = 31;
                    while (((w[i] >> b) & 1) == 0) b--;
                    return i * 32 + b + 1;
                }
            }
            return 0;
        }

        public MyBigNum clone () {
            var n = new MyBigNum (w.length);
            n.w = w;
            return n;
        }

        public static MyBigNum mulmod (MyBigNum a, MyBigNum b, MyBigNum m) {
            var r = new MyBigNum (m.w.length);
            for (int i = b.bitlen () - 1; i >= 0; i--) {
                r.shl1 ();
                if (r.cmp (m) >= 0) r.sub (m);
                if (b.bit (i)) {
                    r.add (a);
                    if (r.cmp (m) >= 0) r.sub (m);
                }
            }
            return r;
        }

        public static MyBigNum modpow (MyBigNum b, MyBigNum e, MyBigNum m) {
            var result = new MyBigNum (m.w.length);
            result.w[0] = 1;
            var base_r = b.clone ();
            while (base_r.cmp (m) >= 0) base_r.sub (m);
            for (int i = e.bitlen () - 1; i >= 0; i--) {
                result = mulmod (result, result, m);
                if (e.bit (i)) result = mulmod (result, base_r, m);
            }
            return result;
        }
    }

    public class MyRsa {
        private static int der_len (uint8[] d, ref int pos) throws RemoteError {
            if (pos >= d.length) throw new RemoteError.PROTOCOL (_("The server public key is not valid."));
            int first = d[pos++];
            if (first < 0x80) return first;
            int n = first & 0x7f;
            if (n > 4 || pos + n > d.length) throw new RemoteError.PROTOCOL (_("The server public key is not valid."));
            int len = 0;
            for (int i = 0; i < n; i++) len = (len << 8) | d[pos++];
            return len;
        }

        private static uint8[] der_take (uint8[] d, ref int pos, uint8 tag) throws RemoteError {
            if (pos >= d.length || d[pos] != tag) throw new RemoteError.PROTOCOL (_("The server public key is not valid."));
            pos++;
            int len = der_len (d, ref pos);
            if (pos + len > d.length) throw new RemoteError.PROTOCOL (_("The server public key is not valid."));
            uint8[] out_b = d[pos:pos + len];
            pos += len;
            return out_b;
        }

        private static uint8[] strip_zeros (uint8[] v) {
            int i = 0;
            while (i < v.length - 1 && v[i] == 0) i++;
            return v[i:v.length];
        }

        public static void parse_public_key (string pem, out uint8[] modulus, out uint8[] exponent) throws RemoteError {
            var sb = new StringBuilder ();
            bool rsa_pkcs1 = pem.contains ("BEGIN RSA PUBLIC KEY");
            foreach (string line in pem.split ("\n")) {
                string l = line.strip ();
                if (l == "" || l.has_prefix ("-----")) continue;
                sb.append (l);
            }
            uint8[] der = Base64.decode (sb.str);
            int pos = 0;
            uint8[] rsa_seq;
            if (rsa_pkcs1) {
                rsa_seq = der_take (der, ref pos, 0x30);
            } else {
                uint8[] spki = der_take (der, ref pos, 0x30);
                int p = 0;
                der_take (spki, ref p, 0x30);
                uint8[] bitstr = der_take (spki, ref p, 0x03);
                if (bitstr.length < 2) throw new RemoteError.PROTOCOL (_("The server public key is not valid."));
                uint8[] inner = bitstr[1:bitstr.length];
                int q = 0;
                rsa_seq = der_take (inner, ref q, 0x30);
            }
            int r = 0;
            modulus = strip_zeros (der_take (rsa_seq, ref r, 0x02));
            exponent = strip_zeros (der_take (rsa_seq, ref r, 0x02));
        }

        private static uint8[] mgf1 (uint8[] seed, int len) {
            var out_b = new ByteArray ();
            uint32 counter = 0;
            while (out_b.len < len) {
                var ba = new ByteArray ();
                ba.append (seed);
                uint8[] c = { (uint8) (counter >> 24), (uint8) (counter >> 16), (uint8) (counter >> 8), (uint8) counter };
                ba.append (c);
                out_b.append (MyCodec.digest (ChecksumType.SHA1, ba.data));
                counter++;
            }
            uint8[] all = out_b.steal ();
            return all[0:len];
        }

        public static uint8[] random_bytes (int n) {
            uint8[] out_b = new uint8[n];
            var f = FileStream.open ("/dev/urandom", "rb");
            if (f != null && f.read (out_b) == n) return out_b;
            for (int i = 0; i < n; i++) out_b[i] = (uint8) Random.int_range (0, 256);
            return out_b;
        }

        public static uint8[] oaep_pad (uint8[] message, int k, uint8[] seed) throws RemoteError {
            int hlen = 20;
            if (message.length > k - 2 * hlen - 2) throw new RemoteError.AUTH (_("The password is too long for the server key."));
            uint8[] lhash = MyCodec.digest (ChecksumType.SHA1, {});
            int db_len = k - hlen - 1;
            uint8[] db = new uint8[db_len];
            for (int i = 0; i < hlen; i++) db[i] = lhash[i];
            db[db_len - message.length - 1] = 1;
            for (int i = 0; i < message.length; i++) db[db_len - message.length + i] = message[i];
            uint8[] db_mask = mgf1 (seed, db_len);
            for (int i = 0; i < db_len; i++) db[i] ^= db_mask[i];
            uint8[] seed_mask = mgf1 (db, hlen);
            uint8[] masked_seed = new uint8[hlen];
            for (int i = 0; i < hlen; i++) masked_seed[i] = seed[i] ^ seed_mask[i];
            uint8[] em = new uint8[k];
            em[0] = 0;
            for (int i = 0; i < hlen; i++) em[1 + i] = masked_seed[i];
            for (int i = 0; i < db_len; i++) em[1 + hlen + i] = db[i];
            return em;
        }

        public static uint8[] encrypt_oaep (string pem, uint8[] message) throws RemoteError {
            uint8[] n, e;
            parse_public_key (pem, out n, out e);
            int k = n.length;
            uint8[] em = oaep_pad (message, k, random_bytes (20));
            int limbs = (k + 3) / 4 + 1;
            var nm = MyBigNum.from_bytes (n, limbs);
            var em_n = MyBigNum.from_bytes (em, limbs);
            var en = MyBigNum.from_bytes (e, limbs);
            return MyBigNum.modpow (em_n, en, nm).to_bytes (k);
        }
    }

    public class MyWaiter {
        public SourceFunc callback;

        public MyWaiter (owned SourceFunc cb) {
            callback = (owned) cb;
        }
    }

    public class MysqlCursor : Cursor {
        internal MysqlEngine engine;
        internal Gee.ArrayList<MyColumnDef> defs;
        internal bool binary;
        internal uint32 stmt_id;
        internal bool has_stmt;
        private int64 index;

        internal MysqlCursor (MysqlEngine engine, Gee.ArrayList<MyColumnDef> defs, bool binary) {
            this.engine = engine;
            this.defs = defs;
            this.binary = binary;
            foreach (var d in defs) columns.add (d.to_meta ());
            done = defs.size == 0;
        }

        public override async Gee.ArrayList<Row> fetch (int max_rows, Cancellable? cancellable = null) throws Error {
            var rows = new Gee.ArrayList<Row> ();
            if (done) return rows;
            try {
                while (rows.size < max_rows) {
                    if (cancellable != null && cancellable.is_cancelled ()) break;
                    var row = yield engine.read_row (defs, binary, index);
                    if (row == null) {
                        yield finish ();
                        break;
                    }
                    rows.add (row);
                    index++;
                }
            } catch (Error e) {
                done = true;
                yield engine.finish_cursor (this, false);
                throw e;
            }
            return rows;
        }

        private async void finish () throws Error {
            done = true;
            yield engine.finish_cursor (this, true);
        }

        public override async void close_async () throws Error {
            if (done) return;
            done = true;
            yield engine.abandon_cursor (this);
        }
    }

    public class MysqlEngine : Engine {
        public string auth_path { get; private set; default = ""; }
        public uint32 thread_id { get; private set; }
        public bool tls_active { get; private set; }
        public bool is_mariadb { get; private set; }
        public uint32 server_caps { get; private set; }

        private SocketConnection? socket_conn;
        private IOStream? io;
        private InputStream? input;
        private OutputStream? output;
        private uint8[] rbuf = new uint8[65536];
        private int rpos;
        private int rlen;
        private uint8 seq;
        private uint32 caps;
        private string password = "";
        private uint status_flags;
        private bool busy;
        private Gee.ArrayQueue<MyWaiter> waiters = new Gee.ArrayQueue<MyWaiter> ();
        private bool via_socket;
        private int64 last_insert_id;
        private uint last_warnings;

        public MysqlEngine (ConnectionConfig config) {
            Object (config: config);
        }

        public static SocketAddress unix_address (string path) throws Error {
            uint8[] native = new uint8[110];
            native[0] = 1;
            if (path.length > 107) throw new RemoteError.CONNECT (_("The socket path is too long."));
            Memory.copy ((uint8*) native + 2, path.data, path.length);
            var addr = SocketAddress.from_native (native, 2 + path.length + 1);
            if (addr == null) throw new RemoteError.CONNECT (_("The socket path is not valid."));
            return addr;
        }

        private async void acquire () {
            while (busy) {
                waiters.offer (new MyWaiter (acquire.callback));
                yield;
            }
            busy = true;
        }

        private void release () {
            busy = false;
            var w = waiters.poll ();
            if (w != null) Idle.add ((owned) w.callback);
        }

        private async void fill (int need) throws Error {
            if (rpos > 0 && rpos == rlen) {
                rpos = 0;
                rlen = 0;
            }
            if (rlen - rpos >= need) return;
            if (rpos > 0) {
                int left = rlen - rpos;
                Memory.move (rbuf, (uint8*) rbuf + rpos, left);
                rpos = 0;
                rlen = left;
            }
            if (need > rbuf.length) rbuf.resize (need + 65536);
            while (rlen < need) {
                uint8[] tmp = new uint8[rbuf.length - rlen];
                ssize_t n = yield input.read_async (tmp, Priority.DEFAULT, null);
                if (n <= 0) {
                    connected = false;
                    throw new RemoteError.CONNECT (_("The server closed the connection."));
                }
                Memory.copy ((uint8*) rbuf + rlen, tmp, n);
                rlen += (int) n;
            }
        }

        internal async uint8[] read_packet () throws Error {
            var payload = new ByteArray ();
            while (true) {
                yield fill (4);
                int len = rbuf[rpos] | (rbuf[rpos + 1] << 8) | (rbuf[rpos + 2] << 16);
                seq = rbuf[rpos + 3] + 1;
                rpos += 4;
                if (len > 0) {
                    yield fill (len);
                    payload.append (rbuf[rpos:rpos + len]);
                    rpos += len;
                }
                if (len < MyCodec.MAX_PAYLOAD) break;
            }
            return payload.steal ();
        }

        private async void write_packet (uint8[] payload, Cancellable? cancellable = null) throws Error {
            uint8[] framed = MyCodec.frame (payload, ref seq);
            size_t written;
            yield output.write_all_async (framed, Priority.DEFAULT, cancellable, out written);
            yield output.flush_async (Priority.DEFAULT, cancellable);
        }

        private async void command (uint8 cmd, uint8[] body) throws Error {
            seq = 0;
            var w = new MyWriter ();
            w.u8 (cmd);
            w.bytes (body);
            yield write_packet (w.take ());
        }

        private RemoteError server_error (uint8[] p) {
            try {
                var r = new MyReader (p);
                r.u8 ();
                uint code = r.u16 ();
                string state = "";
                if (!r.at_end () && r.data[r.pos] == '#') {
                    r.u8 ();
                    state = MyCodec.to_str (r.take (5));
                }
                string msg = r.rest_str ();
                if (state != "") return new RemoteError.SERVER ("%s (%u, %s)".printf (msg, code, state));
                return new RemoteError.SERVER ("%s (%u)".printf (msg, code));
            } catch (Error e) {
                return new RemoteError.PROTOCOL (_("The server sent an invalid error packet."));
            }
        }

        public static uint server_error_code (Error e) {
            int open = e.message.last_index_of (" (");
            if (open < 0) return 0;
            string rest = e.message.substring (open + 2);
            uint v = 0;
            for (int i = 0; i < rest.length && rest[i].isdigit (); i++) v = v * 10 + (rest[i] - '0');
            return v;
        }

        private bool is_eof (uint8[] p) {
            if (p.length == 0 || p[0] != 0xfe) return false;
            if ((caps & MyCodec.DEPRECATE_EOF) != 0) return p.length < MyCodec.MAX_PAYLOAD;
            return p.length < 9;
        }

        private void parse_ok (uint8[] p, QueryResult? res) throws Error {
            var r = new MyReader (p);
            r.u8 ();
            uint64 affected = r.lenenc_int ();
            last_insert_id = (int64) r.lenenc_int ();
            status_flags = r.u16 ();
            last_warnings = r.u16 ();
            if (res != null) {
                if (res.affected < 0) res.affected = 0;
                res.affected += (int64) affected;
            }
        }

        private void parse_eof (uint8[] p) throws Error {
            if ((caps & MyCodec.DEPRECATE_EOF) != 0 && p.length >= 7) {
                parse_ok (p, null);
                return;
            }
            var r = new MyReader (p);
            r.u8 ();
            if (r.remaining () >= 4) {
                last_warnings = r.u16 ();
                status_flags = r.u16 ();
            }
        }

        public override async void open (string? pw, Cancellable? cancellable = null) throws Error {
            password = pw ?? "";
            var client = new SocketClient ();
            client.timeout = config.connect_timeout > 0 ? config.connect_timeout : 10;
            try {
                if (config.socket_path != "") {
                    socket_conn = yield client.connect_async (unix_address (config.socket_path), cancellable);
                    via_socket = true;
                } else {
                    socket_conn = yield client.connect_to_host_async (config.host, (uint16) config.effective_port (), cancellable);
                }
            } catch (Error e) {
                throw new RemoteError.CONNECT (_("Could not reach the server: %s").printf (e.message));
            }
            io = socket_conn;
            input = io.input_stream;
            output = io.output_stream;
            rpos = 0;
            rlen = 0;
            uint8[] hs = yield read_packet ();
            if (hs.length > 0 && hs[0] == 0xff) throw server_error (hs);
            var r = new MyReader (hs);
            uint8 proto = r.u8 ();
            if (proto != 10) throw new RemoteError.UNSUPPORTED (_("The server uses an unsupported protocol version."));
            server_version = r.null_str ();
            is_mariadb = server_version.contains ("MariaDB");
            thread_id = r.u32 ();
            var nonce = new ByteArray ();
            nonce.append (r.take (8));
            r.u8 ();
            uint32 scaps = r.u16 ();
            uint8 auth_len = 0;
            string plugin = "mysql_native_password";
            if (!r.at_end ()) {
                r.u8 ();
                r.u16 ();
                scaps |= ((uint32) r.u16 ()) << 16;
                auth_len = r.u8 ();
                r.take (10);
                if ((scaps & MyCodec.SECURE_CONNECTION) != 0) {
                    int n2 = int.max (13, (int) auth_len - 8);
                    uint8[] part2 = r.take (int.min (n2, r.remaining ()));
                    int keep = part2.length;
                    if (keep > 0 && part2[keep - 1] == 0) keep--;
                    nonce.append (part2[0:keep]);
                }
                if ((scaps & MyCodec.PLUGIN_AUTH) != 0 && !r.at_end ()) plugin = r.null_str ();
            }
            server_caps = scaps;
            uint8[] nonce_b = nonce.steal ();
            uint32 want = MyCodec.LONG_PASSWORD | MyCodec.FOUND_ROWS | MyCodec.LONG_FLAG | MyCodec.PROTOCOL_41 | MyCodec.TRANSACTIONS
                | MyCodec.SECURE_CONNECTION | MyCodec.MULTI_STATEMENTS | MyCodec.MULTI_RESULTS | MyCodec.PS_MULTI_RESULTS
                | MyCodec.PLUGIN_AUTH | MyCodec.PLUGIN_AUTH_LENENC | MyCodec.DEPRECATE_EOF;
            if (config.database != "") want |= MyCodec.CONNECT_WITH_DB;
            caps = want & scaps;
            if ((caps & MyCodec.PROTOCOL_41) == 0) throw new RemoteError.UNSUPPORTED (_("The server is too old."));
            bool use_tls = false;
            bool server_tls = (scaps & MyCodec.SSL) != 0;
            switch (config.ssl_mode) {
                case SslMode.DISABLE:
                    break;
                case SslMode.PREFER:
                    use_tls = server_tls && !via_socket;
                    break;
                default:
                    if (!server_tls) throw new RemoteError.TLS (_("The server does not support encrypted connections."));
                    use_tls = true;
                    break;
            }
            if (use_tls) {
                caps |= MyCodec.SSL;
                var w = new MyWriter ();
                w.u32 (caps);
                w.u32 (16777216);
                w.u8 (45);
                w.zeros (23);
                yield write_packet (w.take (), cancellable);
                yield start_tls (cancellable);
            }
            uint8[] auth = auth_response (plugin, nonce_b);
            var hw = new MyWriter ();
            hw.u32 (caps);
            hw.u32 (16777216);
            hw.u8 (45);
            hw.zeros (23);
            hw.null_str (config.user);
            if ((caps & MyCodec.PLUGIN_AUTH_LENENC) != 0) {
                hw.lenenc_bytes (auth);
            } else {
                hw.u8 (auth.length);
                hw.bytes (auth);
            }
            if ((caps & MyCodec.CONNECT_WITH_DB) != 0) hw.null_str (config.database);
            if ((caps & MyCodec.PLUGIN_AUTH) != 0) hw.null_str (plugin);
            yield write_packet (hw.take (), cancellable);
            yield auth_loop (plugin, nonce_b, cancellable);
            connected = true;
            current_database = config.database;
        }

        private async void start_tls (Cancellable? cancellable) throws Error {
            try {
                SocketConnectable identity = new NetworkAddress (config.tls_host (), (uint16) config.effective_port ());
                var tls = TlsClientConnection.new (socket_conn, identity);
                if (tls.get_class ().find_property ("session-resumption-enabled") != null) tls.set_property ("session-resumption-enabled", false);
                if (config.ssl_mode == SslMode.VERIFY_FULL) {
                    if (config.ssl_ca_file != "") tls.database = TlsFileDatabase.new (config.ssl_ca_file);
                    tls.accept_certificate.connect (() => false);
                } else {
                    tls.accept_certificate.connect (() => true);
                }
                yield tls.handshake_async (Priority.DEFAULT, cancellable);
                io = tls;
                input = tls.input_stream;
                output = tls.output_stream;
                tls_active = true;
            } catch (Error e) {
                throw new RemoteError.TLS (_("The encrypted connection failed: %s").printf (e.message));
            }
        }

        private bool secure () {
            return tls_active || via_socket;
        }

        private uint8[] auth_response (string plugin, uint8[] nonce) {
            switch (plugin) {
                case "caching_sha2_password": return MyCodec.sha2_scramble (password, nonce);
                case "mysql_clear_password": return MyCodec.xor_password (password, {});
                case "sha256_password":
                    if (secure ()) return MyCodec.xor_password (password, {});
                    uint8[] req = { 1 };
                    return password == "" ? new uint8[] { 0 } : req;
                default: return MyCodec.native_scramble (password, nonce);
            }
        }

        private async void auth_loop (string first_plugin, uint8[] first_nonce, Cancellable? cancellable) throws Error {
            string plugin = first_plugin;
            uint8[] nonce = first_nonce;
            auth_path = plugin == "caching_sha2_password" ? "fast" : (plugin == "mysql_native_password" ? "native" : plugin);
            for (int round = 0; round < 8; round++) {
                uint8[] p = yield read_packet ();
                if (p.length == 0) throw new RemoteError.PROTOCOL (_("The server sent an empty authentication reply."));
                switch (p[0]) {
                    case 0x00:
                        parse_ok (p, null);
                        return;
                    case 0xff:
                        var err = server_error (p);
                        throw new RemoteError.AUTH (_("Authentication failed: %s").printf (err.message));
                    case 0xfe:
                        var r = new MyReader (p);
                        r.u8 ();
                        plugin = r.null_str ();
                        uint8[] data = r.rest ();
                        int keep = data.length;
                        if (keep > 0 && data[keep - 1] == 0) keep--;
                        nonce = data[0:keep];
                        auth_path = plugin == "caching_sha2_password" ? "fast" : (plugin == "mysql_native_password" ? "native" : plugin);
                        yield write_packet (auth_response (plugin, nonce), cancellable);
                        break;
                    case 0x01:
                        uint8[] more = p[1:p.length];
                        if (plugin == "caching_sha2_password" && more.length == 1 && more[0] == 3) {
                            auth_path = "fast";
                            break;
                        }
                        if (plugin == "caching_sha2_password" && more.length == 1 && more[0] == 4) {
                            if (secure ()) {
                                auth_path = tls_active ? "full-tls" : "full-socket";
                                yield write_packet (MyCodec.xor_password (password, {}), cancellable);
                            } else {
                                auth_path = "full-rsa";
                                uint8[] req = { 2 };
                                yield write_packet (req, cancellable);
                            }
                            break;
                        }
                        string pem = MyCodec.to_str (more);
                        if (pem.contains ("BEGIN") && pem.contains ("KEY")) {
                            uint8[] enc = MyRsa.encrypt_oaep (pem, MyCodec.xor_password (password, nonce));
                            yield write_packet (enc, cancellable);
                            break;
                        }
                        throw new RemoteError.AUTH (_("The server asked for an unsupported authentication step."));
                    default:
                        throw new RemoteError.AUTH (_("The server sent an unexpected authentication reply."));
                }
            }
            throw new RemoteError.AUTH (_("Authentication did not finish."));
        }

        public override async void close_async () {
            if (socket_conn == null) return;
            try {
                if (connected && !busy) {
                    seq = 0;
                    uint8[] quit = { 0x01 };
                    yield write_packet (quit);
                }
            } catch (Error e) {
            }
            try {
                yield io.close_async ();
            } catch (Error e) {
            }
            connected = false;
            socket_conn = null;
        }

        public override void cancel_running () {
            if (!busy || thread_id == 0) return;
            kill_from_side.begin ((uint64) thread_id, true);
        }

        private async void kill_from_side (uint64 id, bool query_only) {
            var side = new MysqlEngine (config.copy ());
            side.config.database = "";
            try {
                yield side.open (password);
                yield side.execute ("KILL %s %llu".printf (query_only ? "QUERY" : "CONNECTION", id));
            } catch (Error e) {
            }
            yield side.close_async ();
        }

        private async Gee.ArrayList<MyColumnDef> read_defs (int count) throws Error {
            var defs = new Gee.ArrayList<MyColumnDef> ();
            for (int i = 0; i < count; i++) defs.add (MyColumnDef.parse (yield read_packet ()));
            if ((caps & MyCodec.DEPRECATE_EOF) == 0) {
                uint8[] eof = yield read_packet ();
                if (!is_eof (eof)) throw new RemoteError.PROTOCOL (_("The server sent an unexpected packet after the columns."));
            }
            return defs;
        }

        internal async Row? read_row (Gee.ArrayList<MyColumnDef> defs, bool binary, int64 index) throws Error {
            uint8[] p = yield read_packet ();
            if (p.length > 0 && p[0] == 0xff) throw server_error (p);
            if (is_eof (p)) {
                parse_eof (p);
                return null;
            }
            var r = new MyReader (p);
            DbValue[] vals = new DbValue[defs.size];
            if (binary) {
                r.u8 ();
                int nb = (defs.size + 7 + 2) / 8;
                uint8[] bitmap = r.take (nb);
                for (int i = 0; i < defs.size; i++) {
                    int bit = i + 2;
                    if ((bitmap[bit / 8] & (1 << (bit % 8))) != 0) vals[i] = new DbValue.null ();
                    else vals[i] = MyCodec.decode_binary (defs[i], r);
                }
            } else {
                for (int i = 0; i < defs.size; i++) vals[i] = MyCodec.decode_text (defs[i], r.lenenc_bytes ());
            }
            return new Row (index, (owned) vals);
        }

        private async Gee.ArrayList<MyColumnDef>? read_result_head (QueryResult res) throws Error {
            uint8[] p = yield read_packet ();
            if (p.length == 0) throw new RemoteError.PROTOCOL (_("The server sent an empty reply."));
            if (p[0] == 0xff) throw server_error (p);
            if (p[0] == 0x00) {
                parse_ok (p, res);
                return null;
            }
            if (p[0] == 0xfb) throw new RemoteError.UNSUPPORTED (_("Loading local files is not supported."));
            var r = new MyReader (p);
            int count = (int) r.lenenc_int ();
            return yield read_defs (count);
        }

        private async void drain_rows (Gee.ArrayList<MyColumnDef> defs, bool binary) throws Error {
            while (true) {
                uint8[] p = yield read_packet ();
                if (p.length > 0 && p[0] == 0xff) throw server_error (p);
                if (is_eof (p)) {
                    parse_eof (p);
                    return;
                }
            }
        }

        private async void drain_more_results (bool binary) throws Error {
            while ((status_flags & MyCodec.STATUS_MORE_RESULTS) != 0) {
                var tmp = new QueryResult ();
                var defs = yield read_result_head (tmp);
                if (defs != null) yield drain_rows (defs, binary);
            }
        }

        private async uint32 prepare (string sql, out int param_count, out Gee.ArrayList<MyColumnDef> cols) throws Error {
            yield command (0x16, sql.data);
            uint8[] p = yield read_packet ();
            if (p.length > 0 && p[0] == 0xff) throw server_error (p);
            var r = new MyReader (p);
            r.u8 ();
            uint32 id = r.u32 ();
            int ncols = (int) r.u16 ();
            param_count = (int) r.u16 ();
            if (param_count > 0) yield read_defs (param_count);
            cols = ncols > 0 ? yield read_defs (ncols) : new Gee.ArrayList<MyColumnDef> ();
            return id;
        }

        private async void stmt_execute (uint32 id, DbValue[] params) throws Error {
            var w = new MyWriter ();
            w.u32 (id);
            w.u8 (0);
            w.u32 (1);
            if (params.length > 0) {
                uint8[] bitmap = new uint8[(params.length + 7) / 8];
                for (int i = 0; i < params.length; i++) {
                    if (params[i].is_null) bitmap[i / 8] |= (uint8) (1 << (i % 8));
                }
                w.bytes (bitmap);
                w.u8 (1);
                foreach (var v in params) {
                    switch (v.kind) {
                        case ValueKind.NULL: w.u8 (6); break;
                        case ValueKind.INTEGER: w.u8 (8); break;
                        case ValueKind.REAL: w.u8 (5); break;
                        case ValueKind.BLOB: w.u8 (252); break;
                        default: w.u8 (253); break;
                    }
                    w.u8 (0);
                }
                foreach (var v in params) {
                    switch (v.kind) {
                        case ValueKind.NULL: break;
                        case ValueKind.INTEGER: w.u64 ((uint64) v.int_value); break;
                        case ValueKind.REAL:
                            double d = v.real_value;
                            uint64 bits = 0;
                            Memory.copy (&bits, &d, 8);
                            w.u64 (bits);
                            break;
                        case ValueKind.BLOB: w.lenenc_bytes (v.blob_value.get_data ()); break;
                        default: w.lenenc_bytes (v.text_value.data); break;
                    }
                }
            }
            yield command (0x17, w.take ());
        }

        private async void stmt_close (uint32 id) throws Error {
            var w = new MyWriter ();
            w.u32 (id);
            yield command (0x19, w.take ());
        }

        private async void fetch_warnings (QueryResult res) {
            if (last_warnings == 0) return;
            try {
                yield command (0x03, "SHOW WARNINGS".data);
                var tmp = new QueryResult ();
                var defs = yield read_result_head (tmp);
                if (defs == null) return;
                int64 i = 0;
                while (true) {
                    var row = yield read_row (defs, false, i++);
                    if (row == null) break;
                    res.notices.add ("%s %s: %s".printf (row.get (0).to_string (), row.get (1).to_string (), row.get (2).to_string ()));
                }
                yield drain_more_results (false);
            } catch (Error e) {
            }
        }

        private static string first_word (string sql) {
            foreach (var t in Sql.tokenize (sql)) {
                if (t.kind == TokenKind.COMMENT) continue;
                return t.text.up ();
            }
            return "";
        }

        public override async QueryResult execute (string sql, DbValue[]? params = null, Cancellable? cancellable = null, int max_rows = -1) throws Error {
            if (!connected) throw new RemoteError.CONNECT (_("Not connected."));
            yield acquire ();
            ulong handler = 0;
            if (cancellable != null) handler = cancellable.connect (() => cancel_running ());
            var timer = new Timer ();
            var result = new QueryResult ();
            result.command = first_word (sql);
            QueryResult? last_rows = null;
            try {
                bool binary = params != null && params.length > 0;
                uint32 stmt = 0;
                if (binary) {
                    int pc;
                    Gee.ArrayList<MyColumnDef> pcols;
                    stmt = yield prepare (sql, out pc, out pcols);
                    if (pc != params.length) {
                        yield stmt_close (stmt);
                        throw new RemoteError.SERVER (_("The statement expects %d parameters but %d were given.").printf (pc, params.length));
                    }
                    yield stmt_execute (stmt, params);
                } else {
                    yield command (0x03, sql.data);
                }
                bool more = true;
                Error? pending = null;
                while (more) {
                    var res = new QueryResult ();
                    res.command = result.command;
                    Gee.ArrayList<MyColumnDef>? defs = null;
                    try {
                        defs = yield read_result_head (res);
                    } catch (RemoteError.SERVER e) {
                        pending = e;
                        break;
                    }
                    if (defs != null) {
                        foreach (var d in defs) res.columns.add (d.to_meta ());
                        int64 i = 0;
                        while (true) {
                            Row? row = null;
                            try {
                                row = yield read_row (defs, binary, i);
                            } catch (RemoteError.SERVER e) {
                                pending = e;
                                break;
                            }
                            if (row == null) break;
                            if (max_rows < 0 || res.rows.size < max_rows) res.rows.add (row);
                            else res.truncated = true;
                            i++;
                        }
                        if (pending != null) break;
                        last_rows = res;
                    } else {
                        if (result.affected < 0) result.affected = 0;
                        result.affected += res.affected < 0 ? 0 : res.affected;
                    }
                    more = (status_flags & MyCodec.STATUS_MORE_RESULTS) != 0;
                }
                if (binary) yield stmt_close (stmt);
                if (pending != null) {
                    if (cancellable != null && cancellable.is_cancelled ()) throw new RemoteError.CANCELLED (_("The query was cancelled."));
                    throw pending;
                }
                if (last_rows != null) {
                    last_rows.affected = result.affected;
                    result = last_rows;
                }
                yield fetch_warnings (result);
            } finally {
                if (handler != 0) cancellable.disconnect (handler);
                release ();
            }
            result.elapsed_ms = timer.elapsed () * 1000;
            return result;
        }

        public override async Cursor open_cursor (string sql, DbValue[]? params = null, Cancellable? cancellable = null) throws Error {
            if (!connected) throw new RemoteError.CONNECT (_("Not connected."));
            yield acquire ();
            try {
                bool binary = params != null && params.length > 0;
                uint32 stmt = 0;
                if (binary) {
                    int pc;
                    Gee.ArrayList<MyColumnDef> pcols;
                    stmt = yield prepare (sql, out pc, out pcols);
                    yield stmt_execute (stmt, params);
                } else {
                    yield command (0x03, sql.data);
                }
                var tmp = new QueryResult ();
                var defs = yield read_result_head (tmp);
                var cursor = new MysqlCursor (this, defs ?? new Gee.ArrayList<MyColumnDef> (), binary);
                cursor.stmt_id = stmt;
                cursor.has_stmt = binary;
                if (defs == null) {
                    yield drain_more_results (binary);
                    if (binary) yield stmt_close (stmt);
                    release ();
                }
                return cursor;
            } catch (Error e) {
                release ();
                throw e;
            }
        }

        internal async void finish_cursor (MysqlCursor c, bool clean) throws Error {
            try {
                if (clean) yield drain_more_results (c.binary);
                if (c.has_stmt) yield stmt_close (c.stmt_id);
            } finally {
                release ();
            }
        }

        internal async void abandon_cursor (MysqlCursor c) throws Error {
            try {
                int drained = 0;
                bool killed = false;
                bool ended = false;
                while (!ended) {
                    uint8[] p = yield read_packet ();
                    if (p.length > 0 && p[0] == 0xff) {
                        ended = true;
                        status_flags = 0;
                        break;
                    }
                    if (is_eof (p)) {
                        parse_eof (p);
                        ended = true;
                        break;
                    }
                    drained++;
                    if (!killed && drained > 5000) {
                        killed = true;
                        yield kill_from_side ((uint64) thread_id, true);
                    }
                }
                yield drain_more_results (c.binary);
                if (c.has_stmt) yield stmt_close (c.stmt_id);
            } finally {
                release ();
            }
        }

        public override async void use_database (string database, Cancellable? cancellable = null) throws Error {
            yield acquire ();
            try {
                yield command (0x02, database.data);
                uint8[] p = yield read_packet ();
                if (p.length > 0 && p[0] == 0xff) throw server_error (p);
                parse_ok (p, null);
                current_database = database;
            } finally {
                release ();
            }
        }

        public override string quote_ident (string name) {
            return "`" + name.replace ("`", "``") + "`";
        }

        public override string placeholder (int index) {
            return "?";
        }

        public override string literal (DbValue v) {
            switch (v.kind) {
                case ValueKind.NULL: return "NULL";
                case ValueKind.INTEGER: return v.int_value.to_string ();
                case ValueKind.REAL: return v.sql_literal ();
                case ValueKind.BLOB: return v.sql_literal ();
                default: return MyCodec.escape_string (v.text_value, (status_flags & MyCodec.STATUS_NO_BACKSLASH_ESCAPES) != 0);
            }
        }

        public override string limit_clause (int limit, int64 offset) {
            return offset > 0 ? " LIMIT %d OFFSET %lld".printf (limit, offset) : " LIMIT %d".printf (limit);
        }

        public override string text_cast (string expr) {
            return "CAST(%s AS CHAR)".printf (expr);
        }

        public override string[] keywords () {
            return {
                "ACCESSIBLE", "ADD", "ALGORITHM", "ALL", "ALTER", "ANALYZE", "AND", "AS", "ASC", "AUTO_INCREMENT", "BEFORE", "BEGIN",
                "BETWEEN", "BINARY", "BY", "CALL", "CASCADE", "CASE", "CHANGE", "CHARACTER", "CHARSET", "CHECK", "COLLATE", "COLUMN",
                "COMMENT", "COMMIT", "CONSTRAINT", "CREATE", "CROSS", "DATABASE", "DATABASES", "DECLARE", "DEFAULT", "DEFINER",
                "DELETE", "DELIMITER", "DESC", "DESCRIBE", "DETERMINISTIC", "DISTINCT", "DIV", "DO", "DROP", "DUPLICATE", "EACH",
                "ELSE", "ELSEIF", "END", "ENGINE", "ESCAPE", "EVENT", "EXISTS", "EXPLAIN", "FALSE", "FOREIGN", "FROM", "FULL",
                "FULLTEXT", "FUNCTION", "GRANT", "GROUP", "HAVING", "IF", "IGNORE", "IN", "INDEX", "INNER", "INSERT", "INTERVAL",
                "INTO", "IS", "JOIN", "KEY", "KEYS", "KILL", "LEFT", "LIKE", "LIMIT", "LOCK", "MODIFY", "NATURAL", "NOT", "NULL",
                "OFFSET", "ON", "OR", "ORDER", "OUTER", "PARTITION", "PRIMARY", "PROCEDURE", "PROCESSLIST", "REFERENCES", "REGEXP",
                "RENAME", "REPLACE", "RETURN", "RETURNS", "REVOKE", "RIGHT", "ROLLBACK", "SCHEMA", "SELECT", "SEQUENCE", "SET",
                "SHOW", "SPATIAL", "START", "STATUS", "STRAIGHT_JOIN", "TABLE", "TABLES", "TEMPORARY", "THEN", "TO", "TRANSACTION",
                "TRIGGER", "TRUE", "TRUNCATE", "UNION", "UNIQUE", "UNLOCK", "UNSIGNED", "UPDATE", "USE", "USING", "VALUES", "VARIABLES",
                "VIEW", "WARNINGS", "WHEN", "WHERE", "WHILE", "WITH", "ZEROFILL"
            };
        }

        public override string[] type_names () {
            return {
                "TINYINT", "SMALLINT", "MEDIUMINT", "INT", "BIGINT", "DECIMAL(10,2)", "FLOAT", "DOUBLE", "BIT", "BOOLEAN",
                "CHAR(1)", "VARCHAR(255)", "TINYTEXT", "TEXT", "MEDIUMTEXT", "LONGTEXT", "BINARY(16)", "VARBINARY(255)",
                "TINYBLOB", "BLOB", "MEDIUMBLOB", "LONGBLOB", "DATE", "TIME", "DATETIME", "TIMESTAMP", "YEAR", "JSON",
                "ENUM('a','b')", "SET('a','b')", "GEOMETRY", "POINT", "UUID", "INET6"
            };
        }

        public override async Gee.ArrayList<string> list_databases (Cancellable? cancellable = null) throws Error {
            var res = yield execute ("SHOW DATABASES", null, cancellable);
            var list = new Gee.ArrayList<string> ();
            foreach (var r in res.rows) list.add (r.get (0).to_string ());
            return list;
        }

        public override async Gee.ArrayList<string> list_schemas (Cancellable? cancellable = null) throws Error {
            return yield list_databases (cancellable);
        }

        private static DbValue t (string s) {
            return new DbValue.text (s);
        }

        public override async Gee.ArrayList<CatalogObject> list_objects (string schema, Cancellable? cancellable = null) throws Error {
            var list = new Gee.ArrayList<CatalogObject> ();
            var tables = yield execute ("SELECT TABLE_NAME, TABLE_TYPE, TABLE_ROWS, TABLE_COMMENT, ENGINE FROM information_schema.TABLES WHERE TABLE_SCHEMA = ? ORDER BY TABLE_NAME", { t (schema) }, cancellable);
            foreach (var r in tables.rows) {
                string type = r.get (1).to_string ();
                ObjectKind kind = ObjectKind.TABLE;
                if (type == "VIEW" || type == "SYSTEM VIEW") kind = ObjectKind.VIEW;
                else if (type == "SEQUENCE") kind = ObjectKind.SEQUENCE;
                var o = new CatalogObject (kind, schema, r.get (0).to_string ());
                if (!r.get (2).is_null) o.row_estimate = r.get (2).as_int ();
                o.comment = r.get (3).to_string ();
                o.detail = r.get (4).to_string ();
                list.add (o);
            }
            var idx = yield execute ("SELECT TABLE_NAME, INDEX_NAME, MIN(NON_UNIQUE), MIN(INDEX_TYPE), GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX SEPARATOR ', ') FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = ? GROUP BY TABLE_NAME, INDEX_NAME ORDER BY TABLE_NAME, INDEX_NAME", { t (schema) }, cancellable);
            foreach (var r in idx.rows) {
                var o = new CatalogObject (ObjectKind.INDEX, schema, r.get (1).to_string ());
                o.parent = r.get (0).to_string ();
                o.detail = "%s%s (%s)".printf (r.get (2).as_int () == 0 ? "UNIQUE " : "", r.get (3).to_string (), r.get (4).to_string ());
                list.add (o);
            }
            var routines = yield execute ("SELECT ROUTINE_NAME, ROUTINE_TYPE, DTD_IDENTIFIER, ROUTINE_COMMENT FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = ? ORDER BY ROUTINE_NAME", { t (schema) }, cancellable);
            foreach (var r in routines.rows) {
                var o = new CatalogObject (r.get (1).to_string () == "PROCEDURE" ? ObjectKind.PROCEDURE : ObjectKind.FUNCTION, schema, r.get (0).to_string ());
                o.detail = r.get (2).to_string ();
                o.comment = r.get (3).to_string ();
                list.add (o);
            }
            var triggers = yield execute ("SELECT TRIGGER_NAME, EVENT_OBJECT_TABLE, ACTION_TIMING, EVENT_MANIPULATION FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA = ? ORDER BY TRIGGER_NAME", { t (schema) }, cancellable);
            foreach (var r in triggers.rows) {
                var o = new CatalogObject (ObjectKind.TRIGGER, schema, r.get (0).to_string ());
                o.parent = r.get (1).to_string ();
                o.detail = "%s %s".printf (r.get (2).to_string (), r.get (3).to_string ());
                list.add (o);
            }
            try {
                var events = yield execute ("SELECT EVENT_NAME, STATUS, EVENT_COMMENT FROM information_schema.EVENTS WHERE EVENT_SCHEMA = ? ORDER BY EVENT_NAME", { t (schema) }, cancellable);
                foreach (var r in events.rows) {
                    var o = new CatalogObject (ObjectKind.EVENT, schema, r.get (0).to_string ());
                    o.detail = r.get (1).to_string ();
                    o.comment = r.get (2).to_string ();
                    list.add (o);
                }
            } catch (RemoteError.SERVER e) {
            }
            return list;
        }

        private static bool looks_numeric (string s) {
            double d;
            return double.try_parse (s, out d);
        }

        private string normalize_default (DbValue v, string column_type, string extra) {
            if (v.is_null) return "";
            string s = v.to_string ();
            if (is_mariadb) {
                if (s == "NULL") return "";
                return s;
            }
            if (extra.contains ("DEFAULT_GENERATED")) {
                string u = s.up ();
                if (u.has_prefix ("CURRENT_TIMESTAMP") || u.has_prefix ("NOW(")) return s;
                return "(" + s + ")";
            }
            string ct = column_type.down ();
            bool numeric = ct.has_prefix ("int") || ct.has_prefix ("tinyint") || ct.has_prefix ("smallint") || ct.has_prefix ("mediumint")
                || ct.has_prefix ("bigint") || ct.has_prefix ("decimal") || ct.has_prefix ("float") || ct.has_prefix ("double") || ct.has_prefix ("bit");
            if (numeric && (looks_numeric (s) || s.has_prefix ("b'"))) return s;
            return MyCodec.escape_string (s, false);
        }

        public override async TableInfo describe_table (string schema, string table, Cancellable? cancellable = null) throws Error {
            var info = new TableInfo ();
            info.schema = schema;
            info.name = table;
            var tr = yield execute ("SELECT TABLE_COMMENT FROM information_schema.TABLES WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ?", { t (schema), t (table) }, cancellable);
            if (tr.rows.size == 0) throw new RemoteError.SERVER (_("The table \"%s\" does not exist.").printf (table));
            info.comment = tr.rows[0].get (0).to_string ();
            var cols = yield execute ("SELECT COLUMN_NAME, COLUMN_TYPE, IS_NULLABLE, COLUMN_DEFAULT, COLUMN_COMMENT, COLUMN_KEY, EXTRA, ORDINAL_POSITION FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ? ORDER BY ORDINAL_POSITION", { t (schema), t (table) }, cancellable);
            foreach (var r in cols.rows) {
                var c = new ColumnInfo ();
                c.name = r.get (0).to_string ();
                c.data_type = r.get (1).to_string ();
                c.nullable = r.get (2).to_string () == "YES";
                string extra = r.get (6).to_string ();
                c.default_expr = normalize_default (r.get (3), c.data_type, extra);
                c.comment = r.get (4).to_string ();
                c.primary_key = r.get (5).to_string () == "PRI";
                c.auto_increment = extra.down ().contains ("auto_increment");
                c.position = (int) r.get (7).as_int ();
                info.columns.add (c);
            }
            var pk = yield execute ("SELECT COLUMN_NAME FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ? AND INDEX_NAME = 'PRIMARY' ORDER BY SEQ_IN_INDEX", { t (schema), t (table) }, cancellable);
            foreach (var c in info.columns) c.primary_key = false;
            foreach (var r in pk.rows) {
                var c = info.find (r.get (0).to_string ());
                if (c != null) c.primary_key = true;
            }
            var idx = yield execute ("SELECT INDEX_NAME, COLUMN_NAME, NON_UNIQUE, INDEX_TYPE FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ? ORDER BY INDEX_NAME, SEQ_IN_INDEX", { t (schema), t (table) }, cancellable);
            IndexInfo? cur = null;
            foreach (var r in idx.rows) {
                string name = r.get (0).to_string ();
                if (cur == null || cur.name != name) {
                    cur = new IndexInfo ();
                    cur.name = name;
                    cur.primary = name == "PRIMARY";
                    cur.unique = r.get (2).as_int () == 0;
                    cur.method = r.get (3).to_string ();
                    info.indexes.add (cur);
                }
                string[] c = cur.columns;
                c += r.get (1).to_string ();
                cur.columns = c;
            }
            var fk = yield execute ("SELECT k.CONSTRAINT_NAME, k.COLUMN_NAME, k.REFERENCED_TABLE_SCHEMA, k.REFERENCED_TABLE_NAME, k.REFERENCED_COLUMN_NAME, rc.UPDATE_RULE, rc.DELETE_RULE FROM information_schema.KEY_COLUMN_USAGE k JOIN information_schema.REFERENTIAL_CONSTRAINTS rc ON rc.CONSTRAINT_SCHEMA = k.CONSTRAINT_SCHEMA AND rc.CONSTRAINT_NAME = k.CONSTRAINT_NAME AND rc.TABLE_NAME = k.TABLE_NAME WHERE k.TABLE_SCHEMA = ? AND k.TABLE_NAME = ? AND k.REFERENCED_TABLE_NAME IS NOT NULL ORDER BY k.CONSTRAINT_NAME, k.ORDINAL_POSITION", { t (schema), t (table) }, cancellable);
            ForeignKeyInfo? f = null;
            foreach (var r in fk.rows) {
                string name = r.get (0).to_string ();
                if (f == null || f.name != name) {
                    f = new ForeignKeyInfo ();
                    f.name = name;
                    f.ref_schema = r.get (2).to_string ();
                    f.ref_table = r.get (3).to_string ();
                    f.on_update = r.get (5).to_string ();
                    f.on_delete = r.get (6).to_string ();
                    info.foreign_keys.add (f);
                }
                string[] c = f.columns;
                c += r.get (1).to_string ();
                f.columns = c;
                string[] rcol = f.ref_columns;
                rcol += r.get (4).to_string ();
                f.ref_columns = rcol;
            }
            try {
                string same_table = is_mariadb ? " AND cc.TABLE_NAME = tc.TABLE_NAME" : "";
                var ck = yield execute ("SELECT cc.CHECK_CLAUSE FROM information_schema.TABLE_CONSTRAINTS tc JOIN information_schema.CHECK_CONSTRAINTS cc ON cc.CONSTRAINT_SCHEMA = tc.CONSTRAINT_SCHEMA AND cc.CONSTRAINT_NAME = tc.CONSTRAINT_NAME" + same_table + " WHERE tc.TABLE_SCHEMA = ? AND tc.TABLE_NAME = ? AND tc.CONSTRAINT_TYPE = 'CHECK' ORDER BY tc.CONSTRAINT_NAME", { t (schema), t (table) }, cancellable);
                string[] checks = {};
                foreach (var r in ck.rows) checks += r.get (0).to_string ();
                info.checks = checks;
            } catch (RemoteError.SERVER e) {
            }
            return info;
        }

        public override async string object_definition (CatalogObject obj, Cancellable? cancellable = null) throws Error {
            string q = qualified (obj.schema, obj.name);
            string sql;
            string col;
            switch (obj.kind) {
                case ObjectKind.TABLE: sql = "SHOW CREATE TABLE " + q; col = "Create Table"; break;
                case ObjectKind.VIEW: sql = "SHOW CREATE VIEW " + q; col = "Create View"; break;
                case ObjectKind.FUNCTION: sql = "SHOW CREATE FUNCTION " + q; col = "Create Function"; break;
                case ObjectKind.PROCEDURE: sql = "SHOW CREATE PROCEDURE " + q; col = "Create Procedure"; break;
                case ObjectKind.TRIGGER: sql = "SHOW CREATE TRIGGER " + q; col = "SQL Original Statement"; break;
                case ObjectKind.EVENT: sql = "SHOW CREATE EVENT " + q; col = "Create Event"; break;
                case ObjectKind.SEQUENCE: sql = "SHOW CREATE SEQUENCE " + q; col = "Create Table"; break;
                case ObjectKind.INDEX:
                    var info = yield describe_table (obj.schema, obj.parent, cancellable);
                    foreach (var i in info.indexes) {
                        if (i.name != obj.name) continue;
                        string[] cols = {};
                        foreach (string c in i.columns) cols += quote_ident (c);
                        if (i.primary) return "ALTER TABLE %s ADD PRIMARY KEY (%s);".printf (qualified (obj.schema, obj.parent), string.joinv (", ", cols));
                        string kind = i.unique ? "UNIQUE INDEX" : (i.method == "FULLTEXT" ? "FULLTEXT INDEX" : (i.method == "SPATIAL" ? "SPATIAL INDEX" : "INDEX"));
                        return "CREATE %s %s ON %s (%s);".printf (kind, quote_ident (i.name), qualified (obj.schema, obj.parent), string.joinv (", ", cols));
                    }
                    throw new RemoteError.SERVER (_("The index \"%s\" does not exist.").printf (obj.name));
                default:
                    throw new RemoteError.UNSUPPORTED (_("This object has no definition."));
            }
            var res = yield execute (sql, null, cancellable);
            if (res.rows.size == 0) return "";
            int i = res.index_of (col);
            if (i < 0) i = int.min (1, res.columns.size - 1);
            return res.rows[0].get (i).to_string () + ";";
        }

        public string column_definition (ColumnInfo c) {
            var sb = new StringBuilder ();
            sb.append (quote_ident (c.name));
            sb.append (" ");
            sb.append (c.data_type != "" ? c.data_type : "TEXT");
            sb.append (c.nullable && !c.primary_key ? " NULL" : " NOT NULL");
            if (c.default_expr != "") sb.append (" DEFAULT ").append (c.default_expr);
            if (c.auto_increment) sb.append (" AUTO_INCREMENT");
            if (c.comment != "") sb.append (" COMMENT ").append (MyCodec.escape_string (c.comment, false));
            return sb.str;
        }

        private string index_columns (string[] cols) {
            string[] q = {};
            foreach (string c in cols) q += quote_ident (c);
            return string.joinv (", ", q);
        }

        private static bool same_index (IndexInfo a, IndexInfo b) {
            if (a.unique != b.unique || a.columns.length != b.columns.length) return false;
            for (int i = 0; i < a.columns.length; i++) if (a.columns[i] != b.columns[i]) return false;
            return true;
        }

        private static bool same_fk (ForeignKeyInfo a, ForeignKeyInfo b) {
            if (a.ref_table != b.ref_table || a.ref_schema != b.ref_schema || a.on_update != b.on_update || a.on_delete != b.on_delete) return false;
            if (a.columns.length != b.columns.length || a.ref_columns.length != b.ref_columns.length) return false;
            for (int i = 0; i < a.columns.length; i++) if (a.columns[i] != b.columns[i]) return false;
            for (int i = 0; i < a.ref_columns.length; i++) if (a.ref_columns[i] != b.ref_columns[i]) return false;
            return true;
        }

        private string fk_clause (ForeignKeyInfo f) {
            string target = f.ref_schema != "" ? qualified (f.ref_schema, f.ref_table) : quote_ident (f.ref_table);
            var sb = new StringBuilder ();
            if (f.name != "") sb.append ("CONSTRAINT %s ".printf (quote_ident (f.name)));
            sb.append ("FOREIGN KEY (%s) REFERENCES %s (%s)".printf (index_columns (f.columns), target, index_columns (f.ref_columns)));
            if (f.on_update != "" && f.on_update.up () != "RESTRICT" && f.on_update.up () != "NO ACTION") sb.append (" ON UPDATE ").append (f.on_update.up ());
            if (f.on_delete != "" && f.on_delete.up () != "RESTRICT" && f.on_delete.up () != "NO ACTION") sb.append (" ON DELETE ").append (f.on_delete.up ());
            return sb.str;
        }

        private static bool same_pk (string[] a, string[] b) {
            if (a.length != b.length) return false;
            for (int i = 0; i < a.length; i++) if (a[i] != b[i]) return false;
            return true;
        }

        public override string[] alter_table_sql (TableInfo before, TableInfo after, Gee.List<ColumnChange> changes) {
            string target = qualified (before.schema, before.name);
            string[] statements = {};
            string[] fk_drops = {};
            foreach (var f in before.foreign_keys) {
                ForeignKeyInfo? match = null;
                foreach (var g in after.foreign_keys) if (g.name == f.name) match = g;
                if (match == null || !same_fk (f, match)) fk_drops += "DROP FOREIGN KEY %s".printf (quote_ident (f.name));
            }
            if (fk_drops.length > 0) statements += "ALTER TABLE %s %s".printf (target, string.joinv (", ", fk_drops));
            string[] clauses = {};
            foreach (var ch in changes) {
                if (ch.column == null && ch.old_name != null) {
                    clauses += "DROP COLUMN %s".printf (quote_ident (ch.old_name));
                } else if (ch.column != null && ch.old_name == null) {
                    string pos = "";
                    int idx = -1;
                    for (int i = 0; i < after.columns.size; i++) if (after.columns[i].name == ch.column.name) idx = i;
                    if (idx == 0) pos = " FIRST";
                    else if (idx > 0) pos = " AFTER %s".printf (quote_ident (after.columns[idx - 1].name));
                    clauses += "ADD COLUMN %s%s".printf (column_definition (ch.column), pos);
                } else if (ch.column != null) {
                    var old = before.find (ch.old_name);
                    bool renamed = ch.old_name != ch.column.name;
                    bool changed = old == null || !old.same_definition (ch.column) || old.auto_increment != ch.column.auto_increment;
                    if (renamed) clauses += "CHANGE COLUMN %s %s".printf (quote_ident (ch.old_name), column_definition (ch.column));
                    else if (changed) clauses += "MODIFY COLUMN %s".printf (column_definition (ch.column));
                }
            }
            string[] pk_before = before.primary_key ();
            string[] pk_after = after.primary_key ();
            if (!same_pk (pk_before, pk_after)) {
                if (pk_before.length > 0) clauses += "DROP PRIMARY KEY";
                if (pk_after.length > 0) clauses += "ADD PRIMARY KEY (%s)".printf (index_columns (pk_after));
            }
            foreach (var i in before.indexes) {
                if (i.primary) continue;
                IndexInfo? match = null;
                foreach (var j in after.indexes) if (j.name == i.name && !j.primary) match = j;
                if (match == null || !same_index (i, match)) clauses += "DROP INDEX %s".printf (quote_ident (i.name));
            }
            foreach (var j in after.indexes) {
                if (j.primary) continue;
                IndexInfo? match = null;
                foreach (var i in before.indexes) if (i.name == j.name && !i.primary) match = i;
                if (match == null || !same_index (match, j)) {
                    string kind = j.unique ? "UNIQUE INDEX" : (j.method == "FULLTEXT" ? "FULLTEXT INDEX" : "INDEX");
                    clauses += "ADD %s %s (%s)".printf (kind, quote_ident (j.name), index_columns (j.columns));
                }
            }
            foreach (var g in after.foreign_keys) {
                ForeignKeyInfo? match = null;
                foreach (var f in before.foreign_keys) if (f.name == g.name) match = f;
                if (match == null || !same_fk (match, g)) clauses += "ADD " + fk_clause (g);
            }
            if (before.comment != after.comment) clauses += "COMMENT = %s".printf (MyCodec.escape_string (after.comment, false));
            if (after.name != before.name && after.name != "") clauses += "RENAME TO %s".printf (qualified (after.schema != "" ? after.schema : before.schema, after.name));
            if (clauses.length > 0) statements += "ALTER TABLE %s %s".printf (target, string.joinv (", ", clauses));
            return statements;
        }

        public override string create_table_sql (TableInfo table) {
            string[] parts = {};
            foreach (var c in table.columns) parts += "    " + column_definition (c);
            string[] pk = table.primary_key ();
            if (pk.length > 0) parts += "    PRIMARY KEY (%s)".printf (index_columns (pk));
            foreach (var i in table.indexes) {
                if (i.primary) continue;
                parts += "    %s %s (%s)".printf (i.unique ? "UNIQUE KEY" : "KEY", quote_ident (i.name), index_columns (i.columns));
            }
            foreach (var f in table.foreign_keys) parts += "    " + fk_clause (f);
            foreach (string ck in table.checks) parts += "    CHECK (%s)".printf (ck);
            var sb = new StringBuilder ("CREATE TABLE %s (\n".printf (qualified (table.schema, table.name)));
            sb.append (string.joinv (",\n", parts));
            sb.append ("\n)");
            if (table.comment != "") sb.append (" COMMENT = ").append (MyCodec.escape_string (table.comment, false));
            return sb.str;
        }

        public override string explain_sql (string sql, bool analyze) {
            string s = sql.strip ();
            while (s.has_suffix (";")) s = s.substring (0, s.length - 1).strip ();
            if (!analyze) return "EXPLAIN " + s;
            return is_mariadb ? "ANALYZE " + s : "EXPLAIN ANALYZE " + s;
        }

        public override async QueryResult list_users (Cancellable? cancellable = null) throws Error {
            try {
                string yes = MyCodec.escape_string (_("Yes"), false);
                string no = MyCodec.escape_string (_("No"), false);
                if (is_mariadb) return yield execute ("SELECT User AS `User`, Host AS `Host`, IFNULL(JSON_VALUE(Priv, '$.plugin'), '') AS `Plugin`, IF(JSON_VALUE(Priv, '$.is_role') = 'true', %s, %s) AS `Role`, IF(JSON_VALUE(Priv, '$.account_locked') = 'true', %s, %s) AS `Locked`, IF(JSON_VALUE(Priv, '$.password_last_changed') = '0', %s, %s) AS `Password Expired` FROM mysql.global_priv ORDER BY User, Host".printf (yes, no, yes, no, yes, no), null, cancellable);
                return yield execute ("SELECT User AS `User`, Host AS `Host`, plugin AS `Plugin`, IF(account_locked = 'Y', %s, %s) AS `Locked`, IF(password_expired = 'Y', %s, %s) AS `Password Expired` FROM mysql.user ORDER BY User, Host".printf (yes, no, yes, no), null, cancellable);
            } catch (RemoteError.SERVER e) {
                return yield execute ("SELECT DISTINCT GRANTEE AS `User` FROM information_schema.USER_PRIVILEGES ORDER BY GRANTEE", null, cancellable);
            }
        }

        public static void split_account (string account, out string user, out string host) {
            string a = account.strip ();
            user = a;
            host = "%";
            int at = -1;
            bool q = false;
            char qc = 0;
            for (int i = 0; i < a.length; i++) {
                char c = a[i];
                if (q) {
                    if (c == qc) q = false;
                    continue;
                }
                if (c == '\'' || c == '"' || c == '`') {
                    q = true;
                    qc = c;
                } else if (c == '@') {
                    at = i;
                }
            }
            if (at >= 0) {
                user = a.substring (0, at);
                host = a.substring (at + 1);
            }
            user = unquote (user);
            host = unquote (host);
        }

        private static string unquote (string s) {
            if (s.length >= 2 && (s[0] == '\'' || s[0] == '"' || s[0] == '`') && s[s.length - 1] == s[0]) return s.substring (1, s.length - 2);
            return s;
        }

        public static void parse_grant (string stmt, out string privileges, out string object, out bool grant_option) {
            string s = stmt.strip ();
            privileges = "";
            object = "";
            grant_option = s.up ().has_suffix ("WITH GRANT OPTION") || s.up ().contains (" WITH GRANT OPTION");
            string u = s.up ();
            if (!u.has_prefix ("GRANT ")) {
                privileges = s;
                return;
            }
            int on = u.index_of (" ON ");
            int to = u.index_of (" TO ");
            if (on < 0 || to < 0 || to < on) {
                privileges = to > 0 ? s.substring (6, to - 6) : s.substring (6);
                return;
            }
            privileges = s.substring (6, on - 6).strip ();
            object = s.substring (on + 4, to - on - 4).strip ();
        }

        public override async QueryResult list_privileges (string user, Cancellable? cancellable = null) throws Error {
            string u, h;
            split_account (user, out u, out h);
            var raw = yield execute ("SHOW GRANTS FOR %s@%s".printf (MyCodec.escape_string (u, false), MyCodec.escape_string (h, false)), null, cancellable);
            var res = new QueryResult ();
            res.command = "SHOW";
            string[] names = { _("Privileges"), _("Object"), _("Grant Option"), _("Statement") };
            foreach (string n in names) res.columns.add (new ColumnMeta (n));
            int64 i = 0;
            foreach (var r in raw.rows) {
                string stmt = r.get (0).to_string ();
                string privs, obj;
                bool go;
                parse_grant (stmt, out privs, out obj, out go);
                DbValue[] vals = { t (privs), t (obj), t (go ? _("Yes") : _("No")), t (stmt) };
                res.rows.add (new Row (i++, (owned) vals));
            }
            return res;
        }

        public override async QueryResult list_activity (Cancellable? cancellable = null) throws Error {
            return yield execute ("SELECT ID AS `Id`, USER AS `User`, HOST AS `Host`, DB AS `Database`, COMMAND AS `Command`, TIME AS `Time`, STATE AS `State`, INFO AS `Query` FROM information_schema.PROCESSLIST ORDER BY ID", null, cancellable);
        }

        public override async void kill_activity (string id, bool whole_connection, Cancellable? cancellable = null) throws Error {
            uint64 n;
            if (!uint64.try_parse (id.strip (), out n)) throw new RemoteError.SERVER (_("\"%s\" is not a connection id.").printf (id));
            yield execute ("KILL %s %llu".printf (whole_connection ? "CONNECTION" : "QUERY", n), null, cancellable);
        }
    }
}
