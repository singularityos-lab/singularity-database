namespace Singularity.Apps.Database {

    public class PgWriter {
        private ByteArray buf = new ByteArray ();

        public void put_byte (uint8 b) {
            uint8[] x = { b };
            buf.append (x);
        }

        public void put_int16 (int v) {
            uint8[] x = { (uint8) ((v >> 8) & 0xff), (uint8) (v & 0xff) };
            buf.append (x);
        }

        public void put_int32 (int32 v) {
            uint32 u = (uint32) v;
            uint8[] x = { (uint8) (u >> 24), (uint8) ((u >> 16) & 0xff), (uint8) ((u >> 8) & 0xff), (uint8) (u & 0xff) };
            buf.append (x);
        }

        public void put_cstr (string s) {
            buf.append (s.data);
            put_byte (0);
        }

        public void put_bytes (uint8[] data) {
            buf.append (data);
        }

        public uint8[] raw () {
            return buf.data;
        }

        public uint8[] finish (char type) {
            var out_buf = new ByteArray ();
            if (type != 0) {
                uint8[] t = { (uint8) type };
                out_buf.append (t);
            }
            uint32 len = buf.len + 4;
            uint8[] l = { (uint8) (len >> 24), (uint8) ((len >> 16) & 0xff), (uint8) ((len >> 8) & 0xff), (uint8) (len & 0xff) };
            out_buf.append (l);
            out_buf.append (buf.data);
            return out_buf.steal ();
        }
    }

    public class PgMessage {
        public char type;
        public uint8[] data;
        public int pos;

        public PgMessage (char type, owned uint8[] data) {
            this.type = type;
            this.data = (owned) data;
        }

        public bool at_end () {
            return pos >= data.length;
        }

        public uint8 read_byte () {
            if (pos >= data.length) return 0;
            return data[pos++];
        }

        public int read_int16 () {
            if (pos + 2 > data.length) return 0;
            int v = (int) (int16) ((data[pos] << 8) | data[pos + 1]);
            pos += 2;
            return v;
        }

        public int32 read_int32 () {
            if (pos + 4 > data.length) return 0;
            uint32 v = ((uint32) data[pos] << 24) | ((uint32) data[pos + 1] << 16) | ((uint32) data[pos + 2] << 8) | (uint32) data[pos + 3];
            pos += 4;
            return (int32) v;
        }

        public string read_cstr () {
            int start = pos;
            while (pos < data.length && data[pos] != 0) pos++;
            var sb = new StringBuilder ();
            sb.append_len ((string) ((uint8*) data + start), pos - start);
            if (pos < data.length) pos++;
            return sb.str;
        }

        public uint8[] read_bytes (int n) {
            if (n < 0 || pos + n > data.length) n = int.max (0, data.length - pos);
            uint8[] r = data[pos:pos + n];
            pos += n;
            return r;
        }

        public string read_text (int n) {
            if (n < 0 || pos + n > data.length) n = int.max (0, data.length - pos);
            var sb = new StringBuilder ();
            sb.append_len ((string) ((uint8*) data + pos), n);
            pos += n;
            return sb.str;
        }
    }

    public class PgServerError {
        public string severity = "";
        public string code = "";
        public string message = "";
        public string detail = "";
        public string hint = "";
        public string position = "";

        public static PgServerError parse (PgMessage m) {
            var e = new PgServerError ();
            while (!m.at_end ()) {
                uint8 f = m.read_byte ();
                if (f == 0) break;
                string v = m.read_cstr ();
                switch ((char) f) {
                    case 'S': e.severity = v; break;
                    case 'V': e.severity = v; break;
                    case 'C': e.code = v; break;
                    case 'M': e.message = v; break;
                    case 'D': e.detail = v; break;
                    case 'H': e.hint = v; break;
                    case 'P': e.position = v; break;
                    default: break;
                }
            }
            return e;
        }

        public string describe () {
            var sb = new StringBuilder (message);
            if (detail != "") sb.append ("\n").append (detail);
            if (hint != "") sb.append ("\n").append (_("Hint: %s").printf (hint));
            if (position != "") sb.append ("\n").append (_("At character %s").printf (position));
            if (code != "") sb.append (" (SQLSTATE %s)".printf (code));
            return sb.str;
        }

        public Error to_error () {
            if (code == "57014") return new RemoteError.CANCELLED (describe ());
            if (code == "28P01" || code == "28000") return new RemoteError.AUTH (describe ());
            return new RemoteError.SERVER (describe ());
        }
    }

    public class PgScram {
        public static uint8[] hmac (uint8[] key, uint8[] data) {
            var h = new Hmac (ChecksumType.SHA256, key);
            h.update (data);
            uint8[] out_buf = new uint8[32];
            size_t len = 32;
            h.get_digest (out_buf, ref len);
            return out_buf;
        }

        public static uint8[] sha256 (uint8[] data) {
            var c = new Checksum (ChecksumType.SHA256);
            c.update (data, data.length);
            uint8[] out_buf = new uint8[32];
            size_t len = 32;
            c.get_digest (out_buf, ref len);
            return out_buf;
        }

        public static uint8[] pbkdf2 (uint8[] password, uint8[] salt, int iterations, int length = 32) {
            var result = new ByteArray ();
            uint32 block = 1;
            while (result.len < length) {
                var s = new ByteArray ();
                s.append (salt);
                uint8[] bi = { (uint8) (block >> 24), (uint8) ((block >> 16) & 0xff), (uint8) ((block >> 8) & 0xff), (uint8) (block & 0xff) };
                s.append (bi);
                uint8[] u = hmac (password, s.data);
                uint8[] t = u;
                for (int i = 1; i < iterations; i++) {
                    u = hmac (password, u);
                    for (int k = 0; k < t.length; k++) t[k] ^= u[k];
                }
                result.append (t);
                block++;
            }
            uint8[] r = result.data[0:length];
            return r;
        }

        public static string md5_password (string user, string password, uint8[] salt) {
            string inner = Checksum.compute_for_string (ChecksumType.MD5, password + user);
            var b = new ByteArray ();
            b.append (inner.data);
            b.append (salt);
            return "md5" + Checksum.compute_for_data (ChecksumType.MD5, b.data);
        }

        public static string random_nonce () {
            uint8[] raw = new uint8[18];
            var f = FileStream.open ("/dev/urandom", "rb");
            if (f != null) f.read (raw);
            else for (int i = 0; i < raw.length; i++) raw[i] = (uint8) Random.int_range (0, 256);
            return Base64.encode (raw);
        }

        public string client_nonce;
        public string client_first_bare;
        public string server_first = "";
        public string client_final_no_proof = "";
        private uint8[] salted_password = {};
        private string auth_message = "";

        public PgScram (string user, string? nonce = null) {
            client_nonce = nonce ?? random_nonce ();
            client_first_bare = "n=%s,r=%s".printf (user.replace ("=", "=3D").replace (",", "=2C"), client_nonce);
        }

        public string client_first () {
            return "n,," + client_first_bare;
        }

        public string client_final (string server_first_message, string password) throws Error {
            server_first = server_first_message;
            string nonce = "", salt = "";
            int iterations = 0;
            foreach (string part in server_first.split (",")) {
                if (part.has_prefix ("r=")) nonce = part.substring (2);
                else if (part.has_prefix ("s=")) salt = part.substring (2);
                else if (part.has_prefix ("i=")) iterations = int.parse (part.substring (2));
            }
            if (nonce == "" || salt == "" || iterations <= 0 || !nonce.has_prefix (client_nonce)) throw new RemoteError.AUTH (_("The server sent an invalid SCRAM challenge."));
            salted_password = pbkdf2 (password.data, Base64.decode (salt), iterations);
            client_final_no_proof = "c=biws,r=" + nonce;
            auth_message = client_first_bare + "," + server_first + "," + client_final_no_proof;
            uint8[] client_key = hmac (salted_password, "Client Key".data);
            uint8[] stored_key = sha256 (client_key);
            uint8[] signature = hmac (stored_key, auth_message.data);
            uint8[] proof = new uint8[client_key.length];
            for (int i = 0; i < proof.length; i++) proof[i] = client_key[i] ^ signature[i];
            return client_final_no_proof + ",p=" + Base64.encode (proof);
        }

        public bool verify_server (string server_final) {
            string v = "";
            foreach (string part in server_final.split (",")) {
                if (part.has_prefix ("v=")) v = part.substring (2);
            }
            uint8[] server_key = hmac (salted_password, "Server Key".data);
            uint8[] expected = hmac (server_key, auth_message.data);
            return v == Base64.encode (expected);
        }
    }

    public class PgTypes {
        public static string name_for (uint32 oid) {
            switch (oid) {
                case 16: return "bool";
                case 17: return "bytea";
                case 18: return "char";
                case 19: return "name";
                case 20: return "int8";
                case 21: return "int2";
                case 23: return "int4";
                case 24: return "regproc";
                case 25: return "text";
                case 26: return "oid";
                case 28: return "xid";
                case 114: return "json";
                case 142: return "xml";
                case 650: return "cidr";
                case 700: return "float4";
                case 701: return "float8";
                case 790: return "money";
                case 829: return "macaddr";
                case 869: return "inet";
                case 1000: return "bool[]";
                case 1005: return "int2[]";
                case 1007: return "int4[]";
                case 1009: return "text[]";
                case 1016: return "int8[]";
                case 1042: return "bpchar";
                case 1043: return "varchar";
                case 1082: return "date";
                case 1083: return "time";
                case 1114: return "timestamp";
                case 1184: return "timestamptz";
                case 1186: return "interval";
                case 1266: return "timetz";
                case 1560: return "bit";
                case 1562: return "varbit";
                case 1700: return "numeric";
                case 2205: return "regclass";
                case 2950: return "uuid";
                case 3614: return "tsvector";
                case 3802: return "jsonb";
                default: return "oid %u".printf (oid);
            }
        }

        private static string strip_zeros (string s) {
            if (!s.contains (".") || s.contains ("e") || s.contains ("E")) return s;
            string r = s;
            while (r.has_suffix ("0")) r = r.substring (0, r.length - 1);
            if (r.has_suffix (".")) r = r.substring (0, r.length - 1);
            if (r == "-0") r = "0";
            return r;
        }

        public static DbValue decode (uint32 oid, string text) {
            switch (oid) {
                case 20:
                case 21:
                case 23:
                case 26:
                case 28:
                    int64 i;
                    if (int64.try_parse (text, out i)) return new DbValue.int (i);
                    return new DbValue.text (text);
                case 700:
                case 701:
                    double d;
                    if (double.try_parse (text, out d) && d.is_finite ()) return new DbValue.real (d);
                    return new DbValue.text (text);
                case 1700:
                    double n;
                    if (!double.try_parse (text, out n) || !n.is_finite ()) return new DbValue.text (text);
                    if (DbValue.format_real (n) == strip_zeros (text)) return new DbValue.real (n);
                    return new DbValue.text (text);
                case 16:
                    return new DbValue.bool (text == "t" || text == "true");
                case 17:
                    if (text.has_prefix ("\\x")) {
                        int len = (text.length - 2) / 2;
                        uint8[] b = new uint8[len];
                        for (int k = 0; k < len; k++) {
                            b[k] = (uint8) ((text[2 + 2 * k].xdigit_value () << 4) | text[3 + 2 * k].xdigit_value ());
                        }
                        return new DbValue.blob (new Bytes.take ((owned) b));
                    }
                    return new DbValue.blob (new Bytes (text.data));
                default:
                    return new DbValue.text (text);
            }
        }

        public static string encode (DbValue v) {
            switch (v.kind) {
                case ValueKind.INTEGER: return v.int_value.to_string ();
                case ValueKind.REAL:
                    if (v.real_value.is_nan ()) return "NaN";
                    if (v.real_value.is_infinity () > 0) return "Infinity";
                    if (v.real_value.is_infinity () < 0) return "-Infinity";
                    return DbValue.format_real (v.real_value);
                case ValueKind.BLOB:
                    var sb = new StringBuilder ("\\x");
                    foreach (uint8 b in v.blob_value.get_data ()) sb.append ("%02x".printf (b));
                    return sb.str;
                default:
                    return v.text_value ?? "";
            }
        }
    }

    public class PgCursor : Cursor {
        private weak PgEngine engine;
        public bool open_on_server = true;
        public bool fetching;

        public PgCursor (PgEngine engine) {
            this.engine = engine;
        }

        public override async Gee.ArrayList<Row> fetch (int max_rows, Cancellable? cancellable = null) throws Error {
            var rows = new Gee.ArrayList<Row> ();
            if (done || !open_on_server) {
                done = true;
                return rows;
            }
            yield engine.cursor_fetch (this, rows, max_rows, cancellable);
            return rows;
        }

        public override async void close_async () throws Error {
            if (!open_on_server) {
                done = true;
                return;
            }
            yield engine.cursor_close (this);
        }

        public void mark_done () {
            done = true;
        }
    }

    private class PgWaiter {
        public SourceFunc callback;

        public PgWaiter (owned SourceFunc cb) {
            callback = (owned) cb;
        }
    }

    public class PgEngine : Engine {
        private IOStream? io;
        private SocketConnection? raw;
        private BufferedInputStream? input;
        private SocketConnectable? address;
        private string password = "";
        private int32 backend_pid;
        private int32 backend_key;
        public char transaction_status { get; private set; default = 'I'; }
        public string last_sqlstate { get; private set; default = ""; }
        public bool tls_active { get; private set; }
        private bool busy;
        private Gee.ArrayQueue<PgWaiter> waiters = new Gee.ArrayQueue<PgWaiter> ();
        private PgCursor? active_cursor;
        private Gee.ArrayList<string>? pending_notices;
        private int64 row_counter;

        public PgEngine (ConnectionConfig config) {
            Object (config: config);
        }

        private async void acquire () {
            if (busy && active_cursor != null && !active_cursor.fetching) {
                var c = active_cursor;
                try {
                    yield c.close_async ();
                } catch (Error e) {
                }
            }
            while (busy) {
                var w = new PgWaiter (acquire.callback);
                waiters.offer (w);
                yield;
            }
            busy = true;
        }

        private void release () {
            busy = false;
            var w = waiters.poll ();
            if (w != null) Idle.add ((owned) w.callback);
        }

        private async void send (uint8[] data) throws Error {
            if (io == null) throw new RemoteError.CONNECT (_("The connection is closed."));
            size_t written;
            yield io.output_stream.write_all_async (data, Priority.DEFAULT, null, out written);
        }

        private async uint8[] read_n (int n) throws Error {
            uint8[] b = new uint8[n];
            if (n == 0) return b;
            size_t got;
            yield input.read_all_async (b, Priority.DEFAULT, null, out got);
            if (got < n) {
                connected = false;
                throw new RemoteError.CONNECT (_("The server closed the connection."));
            }
            return b;
        }

        private async PgMessage read_message () throws Error {
            uint8[] head = yield read_n (5);
            uint32 len = ((uint32) head[1] << 24) | ((uint32) head[2] << 16) | ((uint32) head[3] << 8) | (uint32) head[4];
            if (len < 4 || len > 1024 * 1024 * 1024) throw new RemoteError.PROTOCOL (_("Invalid message from the server."));
            uint8[] body = yield read_n ((int) len - 4);
            var m = new PgMessage ((char) head[0], (owned) body);
            return m;
        }

        private bool handle_async_message (PgMessage m) {
            switch (m.type) {
                case 'N':
                    var e = PgServerError.parse (m);
                    string text = e.severity != "" ? "%s: %s".printf (e.severity, e.message) : e.message;
                    if (pending_notices != null) pending_notices.add (text);
                    notice (text);
                    return true;
                case 'S':
                    string k = m.read_cstr ();
                    string v = m.read_cstr ();
                    if (k == "server_version") server_version = v;
                    return true;
                case 'A':
                    return true;
                default:
                    return false;
            }
        }

        private async IOStream connect_stream (SocketConnectable addr, Cancellable? cancellable) throws Error {
            var client = new SocketClient ();
            client.timeout = (uint) int.max (1, config.connect_timeout);
            try {
                var conn = yield client.connect_async (addr, cancellable);
                conn.socket.timeout = 0;
                return conn;
            } catch (IOError.CANCELLED e) {
                throw new RemoteError.CANCELLED (_("Connecting was cancelled."));
            } catch (Error e) {
                throw new RemoteError.CONNECT (_("Could not connect to %s: %s").printf (config.summary (), e.message));
            }
        }

        private SocketConnectable make_address () {
            int port = config.effective_port ();
            if (config.socket_path != "") return new UnixSocketAddress (Path.build_filename (config.socket_path, ".s.PGSQL.%d".printf (port)));
            return new NetworkAddress (config.host, (uint16) port);
        }

        public Error login_error (Error e) {
            string where = config.summary ();
            if (e is RemoteError.CONNECT && e.message == _("The server closed the connection.")) {
                return new RemoteError.CONNECT (_("%s closed the connection while signing in. The server may be restarting, refusing this client in pg_hba.conf, or it is not a PostgreSQL server.").printf (where));
            }
            if (e is RemoteError || e is IOError.CANCELLED) return e;
            if (e is IOError.TIMED_OUT) return new RemoteError.CONNECT (_("%s did not answer while signing in. Check that the server is running and that the port is a PostgreSQL port.").printf (where));
            if (e is IOError.CONNECTION_CLOSED || e is IOError.BROKEN_PIPE || e is IOError.CONNECTION_REFUSED || e.message.contains ("reset by peer") || e.message.contains ("closed")) {
                return new RemoteError.CONNECT (_("%s closed the connection while signing in. The server may be restarting, refusing this client in pg_hba.conf, or it is not a PostgreSQL server.").printf (where));
            }
            if (e is TlsError) return new RemoteError.TLS (_("The secure connection to %s failed: %s").printf (where, e.message));
            return new RemoteError.CONNECT (_("Signing in to %s failed: %s").printf (where, e.message));
        }

        public override async void open (string? password, Cancellable? cancellable = null) throws Error {
            try {
                yield open_inner (password, cancellable);
            } catch (Error e) {
                throw login_error (e);
            }
        }

        private async void open_inner (string? password, Cancellable? cancellable) throws Error {
            this.password = password ?? "";
            address = make_address ();
            var stream = yield connect_stream (address, cancellable);
            raw = stream as SocketConnection;
            io = stream;
            tls_active = false;
            bool unix_socket = config.socket_path != "";
            if (!unix_socket && config.ssl_mode != SslMode.DISABLE) {
                var w = new PgWriter ();
                w.put_int32 (80877103);
                yield send (w.finish (0));
                uint8[] answer = new uint8[1];
                size_t got;
                yield io.input_stream.read_all_async (answer, Priority.DEFAULT, cancellable, out got);
                if (got < 1) throw new RemoteError.CONNECT (_("The server closed the connection."));
                if (answer[0] == 'S') {
                    yield start_tls (cancellable);
                } else if (config.ssl_mode == SslMode.REQUIRE || config.ssl_mode == SslMode.VERIFY_FULL) {
                    yield io.close_async ();
                    io = null;
                    throw new RemoteError.TLS (_("The server does not support encrypted connections."));
                }
            }
            input = new BufferedInputStream.sized (io.input_stream, 65536);
            input.close_base_stream = false;
            try {
                yield startup (cancellable);
            } catch (Error e) {
                try {
                    yield io.close_async ();
                } catch (Error x) {
                }
                io = null;
                connected = false;
                throw e;
            }
            connected = true;
        }

        private async void start_tls (Cancellable? cancellable) throws Error {
            var identity = new NetworkAddress (config.tls_host (), (uint16) config.effective_port ());
            TlsCertificate? ca = null;
            if (config.ssl_mode == SslMode.VERIFY_FULL && config.ssl_ca_file != "") {
                try {
                    ca = new TlsCertificate.from_file (config.ssl_ca_file);
                } catch (Error e) {
                    throw new RemoteError.TLS (_("The certificate authority file could not be read: %s").printf (e.message));
                }
            }
            var tls = TlsClientConnection.@new (io, identity);
            if (tls.get_class ().find_property ("session-resumption-enabled") != null) tls.set_property ("session-resumption-enabled", false);
            var mode = config.ssl_mode;
            tls.accept_certificate.connect ((peer, errors) => {
                if (mode != SslMode.VERIFY_FULL) return true;
                if (ca == null) return false;
                return peer.verify (identity, ca) == 0;
            });
            try {
                yield tls.handshake_async (Priority.DEFAULT, cancellable);
            } catch (Error e) {
                throw new RemoteError.TLS (_("The secure connection failed: %s").printf (e.message));
            }
            io = tls;
            tls_active = true;
        }

        private async void startup (Cancellable? cancellable) throws Error {
            string db = config.database != "" ? config.database : "postgres";
            var w = new PgWriter ();
            w.put_int32 (196608);
            w.put_cstr ("user");
            w.put_cstr (config.user);
            w.put_cstr ("database");
            w.put_cstr (db);
            w.put_cstr ("application_name");
            w.put_cstr ("Singularity Database");
            w.put_cstr ("client_encoding");
            w.put_cstr ("UTF8");
            w.put_cstr ("DateStyle");
            w.put_cstr ("ISO, YMD");
            w.put_byte (0);
            yield send (w.finish (0));
            PgScram? scram = null;
            while (true) {
                var m = yield read_message ();
                switch (m.type) {
                    case 'R':
                        int32 code = m.read_int32 ();
                        switch (code) {
                            case 0:
                                break;
                            case 3:
                                var p = new PgWriter ();
                                p.put_cstr (password);
                                yield send (p.finish ('p'));
                                break;
                            case 5:
                                uint8[] salt = m.read_bytes (4);
                                var p = new PgWriter ();
                                p.put_cstr (PgScram.md5_password (config.user, password, salt));
                                yield send (p.finish ('p'));
                                break;
                            case 10:
                                bool has = false;
                                while (!m.at_end ()) {
                                    string mech = m.read_cstr ();
                                    if (mech == "") break;
                                    if (mech == "SCRAM-SHA-256") has = true;
                                }
                                if (!has) throw new RemoteError.UNSUPPORTED (_("The server asked for an authentication method that is not supported."));
                                scram = new PgScram ("");
                                string first = scram.client_first ();
                                var p = new PgWriter ();
                                p.put_cstr ("SCRAM-SHA-256");
                                p.put_int32 (first.length);
                                p.put_bytes (first.data);
                                yield send (p.finish ('p'));
                                break;
                            case 11:
                                if (scram == null) throw new RemoteError.PROTOCOL (_("Unexpected authentication message."));
                                string server_first = m.read_text (-1);
                                string final_msg = scram.client_final (server_first, password);
                                var p = new PgWriter ();
                                p.put_bytes (final_msg.data);
                                yield send (p.finish ('p'));
                                break;
                            case 12:
                                if (scram == null || !scram.verify_server (m.read_text (-1))) throw new RemoteError.AUTH (_("The server could not prove it knows the password."));
                                break;
                            default:
                                throw new RemoteError.UNSUPPORTED (_("The server asked for an authentication method that is not supported (%d).").printf ((int) code));
                        }
                        break;
                    case 'K':
                        backend_pid = m.read_int32 ();
                        backend_key = m.read_int32 ();
                        break;
                    case 'E':
                        var err = PgServerError.parse (m);
                        last_sqlstate = err.code;
                        if (err.code.has_prefix ("28")) throw new RemoteError.AUTH (err.describe ());
                        throw new RemoteError.CONNECT (err.describe ());
                    case 'Z':
                        transaction_status = (char) m.read_byte ();
                        current_database = db;
                        return;
                    default:
                        handle_async_message (m);
                        break;
                }
            }
        }

        public override async void close_async () {
            if (io == null) return;
            try {
                var w = new PgWriter ();
                yield send (w.finish ('X'));
            } catch (Error e) {
            }
            try {
                yield io.close_async ();
            } catch (Error e) {
            }
            io = null;
            connected = false;
            active_cursor = null;
        }

        public override void cancel_running () {
            if (address == null || backend_pid == 0 || !busy) return;
            send_cancel.begin ();
        }

        private async void send_cancel () {
            try {
                var stream = yield connect_stream (address, null);
                var w = new PgWriter ();
                w.put_int32 (80877102);
                w.put_int32 (backend_pid);
                w.put_int32 (backend_key);
                size_t written;
                yield stream.output_stream.write_all_async (w.finish (0), Priority.DEFAULT, null, out written);
                yield stream.close_async ();
            } catch (Error e) {
                warning ("database: cancel failed: %s", e.message);
            }
        }

        private static ColumnMeta[] parse_row_description (PgMessage m) {
            int n = m.read_int16 ();
            ColumnMeta[] cols = new ColumnMeta[n];
            for (int i = 0; i < n; i++) {
                var c = new ColumnMeta (m.read_cstr ());
                m.read_int32 ();
                m.read_int16 ();
                c.type_oid = (uint32) m.read_int32 ();
                m.read_int16 ();
                m.read_int32 ();
                m.read_int16 ();
                c.type_name = PgTypes.name_for (c.type_oid);
                cols[i] = c;
            }
            return cols;
        }

        private Row parse_row (PgMessage m, Gee.List<ColumnMeta> cols) {
            int n = m.read_int16 ();
            DbValue[] vals = new DbValue[n];
            for (int i = 0; i < n; i++) {
                int32 len = m.read_int32 ();
                if (len < 0) {
                    vals[i] = new DbValue.null ();
                    continue;
                }
                string t = m.read_text (len);
                vals[i] = PgTypes.decode (i < cols.size ? cols[i].type_oid : 25, t);
            }
            return new Row (row_counter++, (owned) vals);
        }

        public static void apply_tag (QueryResult r, string tag) {
            r.command = tag;
            string[] parts = tag.split (" ");
            if (parts.length >= 2) {
                int64 n;
                if (int64.try_parse (parts[parts.length - 1], out n)) {
                    string verb = parts[0];
                    if (verb == "INSERT" || verb == "UPDATE" || verb == "DELETE" || verb == "SELECT" || verb == "MOVE" || verb == "FETCH" || verb == "COPY" || verb == "MERGE") r.affected = n;
                }
                string[] words = {};
                foreach (string w in parts) {
                    int64 x;
                    if (!int64.try_parse (w, out x)) words += w;
                }
                r.command = string.joinv (" ", words);
            }
        }

        private void check_cancelled (Cancellable? cancellable) throws Error {
            if (cancellable != null && cancellable.is_cancelled ()) throw new RemoteError.CANCELLED (_("The query was cancelled."));
        }

        public override async QueryResult execute (string sql, DbValue[]? params = null, Cancellable? cancellable = null, int max_rows = -1) throws Error {
            check_cancelled (cancellable);
            if (!connected) throw new RemoteError.CONNECT (_("The connection is closed."));
            yield acquire ();
            ulong handler = 0;
            if (cancellable != null) handler = cancellable.connect (() => cancel_running ());
            var timer = new Timer ();
            try {
                bool multi = params == null && Sql.split_statements (sql).size > 1;
                QueryResult r;
                if (multi || (params == null && max_rows < 0)) r = yield simple_query (sql, max_rows);
                else r = yield extended_query (sql, params, max_rows);
                r.elapsed_ms = timer.elapsed () * 1000;
                return r;
            } finally {
                if (handler != 0) cancellable.disconnect (handler);
                release ();
            }
        }

        private async QueryResult simple_query (string sql, int max_rows) throws Error {
            var w = new PgWriter ();
            w.put_cstr (sql);
            yield send (w.finish ('Q'));
            QueryResult? last = null;
            QueryResult? current = null;
            var notices = new Gee.ArrayList<string> ();
            pending_notices = notices;
            PgServerError? error = null;
            row_counter = 0;
            while (true) {
                var m = yield read_message ();
                switch (m.type) {
                    case 'T':
                        current = new QueryResult ();
                        foreach (var c in parse_row_description (m)) current.columns.add (c);
                        row_counter = 0;
                        break;
                    case 'D':
                        if (current == null) break;
                        if (max_rows >= 0 && current.rows.size >= max_rows) {
                            current.truncated = true;
                            break;
                        }
                        current.rows.add (parse_row (m, current.columns));
                        break;
                    case 'C':
                        if (current == null) current = new QueryResult ();
                        apply_tag (current, m.read_cstr ());
                        if (last == null || current.has_rows () || !last.has_rows ()) last = current;
                        current = null;
                        break;
                    case 'I':
                        if (last == null) last = new QueryResult ();
                        current = null;
                        break;
                    case 'G':
                        var f = new PgWriter ();
                        f.put_cstr (_("COPY from the client is not supported."));
                        yield send (f.finish ('f'));
                        break;
                    case 'H':
                    case 'd':
                    case 'c':
                        break;
                    case 'E':
                        error = PgServerError.parse (m);
                        break;
                    case 'Z':
                        transaction_status = (char) m.read_byte ();
                        pending_notices = null;
                        if (error != null) {
                            last_sqlstate = error.code;
                            throw error.to_error ();
                        }
                        last_sqlstate = "";
                        var r = last ?? new QueryResult ();
                        r.notices.add_all (notices);
                        return r;
                    default:
                        handle_async_message (m);
                        break;
                }
            }
        }

        private void write_parse_bind (PgWriter all, string sql, DbValue[]? params) {
            var p = new PgWriter ();
            p.put_cstr ("");
            p.put_cstr (sql);
            p.put_int16 (0);
            all.put_bytes (p.finish ('P'));
            var b = new PgWriter ();
            b.put_cstr ("");
            b.put_cstr ("");
            b.put_int16 (0);
            int n = params != null ? params.length : 0;
            b.put_int16 (n);
            for (int i = 0; i < n; i++) {
                var v = params[i];
                if (v == null || v.is_null) {
                    b.put_int32 (-1);
                    continue;
                }
                uint8[] data = PgTypes.encode (v).data;
                b.put_int32 (data.length);
                b.put_bytes (data);
            }
            b.put_int16 (1);
            b.put_int16 (0);
            all.put_bytes (b.finish ('B'));
            var d = new PgWriter ();
            d.put_byte ('P');
            d.put_cstr ("");
            all.put_bytes (d.finish ('D'));
        }

        private static uint8[] execute_message (int max_rows) {
            var e = new PgWriter ();
            e.put_cstr ("");
            e.put_int32 (max_rows);
            return e.finish ('E');
        }

        private async QueryResult extended_query (string sql, DbValue[]? params, int max_rows) throws Error {
            var all = new PgWriter ();
            write_parse_bind (all, sql, params);
            int limit = max_rows < 0 ? 0 : max_rows + 1;
            all.put_bytes (execute_message (limit));
            all.put_bytes (new PgWriter ().finish ('S'));
            yield send (all.raw ());
            var r = new QueryResult ();
            var notices = new Gee.ArrayList<string> ();
            pending_notices = notices;
            PgServerError? error = null;
            row_counter = 0;
            while (true) {
                var m = yield read_message ();
                switch (m.type) {
                    case '1':
                    case '2':
                    case 'n':
                        break;
                    case 'T':
                        foreach (var c in parse_row_description (m)) r.columns.add (c);
                        break;
                    case 'D':
                        if (max_rows >= 0 && r.rows.size >= max_rows) {
                            r.truncated = true;
                            break;
                        }
                        r.rows.add (parse_row (m, r.columns));
                        break;
                    case 'C':
                        apply_tag (r, m.read_cstr ());
                        break;
                    case 's':
                    case 'I':
                        break;
                    case 'E':
                        error = PgServerError.parse (m);
                        break;
                    case 'Z':
                        transaction_status = (char) m.read_byte ();
                        pending_notices = null;
                        if (error != null) {
                            last_sqlstate = error.code;
                            throw error.to_error ();
                        }
                        last_sqlstate = "";
                        r.notices.add_all (notices);
                        return r;
                    default:
                        handle_async_message (m);
                        break;
                }
            }
        }

        public override async Cursor open_cursor (string sql, DbValue[]? params = null, Cancellable? cancellable = null) throws Error {
            check_cancelled (cancellable);
            if (!connected) throw new RemoteError.CONNECT (_("The connection is closed."));
            yield acquire ();
            var cursor = new PgCursor (this);
            try {
                var all = new PgWriter ();
                write_parse_bind (all, sql, params);
                all.put_bytes (new PgWriter ().finish ('H'));
                yield send (all.raw ());
                row_counter = 0;
                while (true) {
                    var m = yield read_message ();
                    if (m.type == '1' || m.type == '2') continue;
                    if (m.type == 'T') {
                        foreach (var c in parse_row_description (m)) cursor.columns.add (c);
                        break;
                    }
                    if (m.type == 'n') break;
                    if (m.type == 'E') {
                        var err = PgServerError.parse (m);
                        last_sqlstate = err.code;
                        yield sync_and_drain ();
                        throw err.to_error ();
                    }
                    handle_async_message (m);
                }
            } catch (Error e) {
                cursor.open_on_server = false;
                cursor.mark_done ();
                release ();
                throw e;
            }
            active_cursor = cursor;
            return cursor;
        }

        private async void sync_and_drain () throws Error {
            yield send (new PgWriter ().finish ('S'));
            while (true) {
                var m = yield read_message ();
                if (m.type == 'Z') {
                    transaction_status = (char) m.read_byte ();
                    return;
                }
                handle_async_message (m);
            }
        }

        private void finish_cursor (PgCursor cursor) {
            cursor.open_on_server = false;
            cursor.mark_done ();
            if (active_cursor == cursor) active_cursor = null;
            release ();
        }

        internal async void cursor_fetch (PgCursor cursor, Gee.ArrayList<Row> rows, int max_rows, Cancellable? cancellable) throws Error {
            ulong handler = 0;
            if (cancellable != null) handler = cancellable.connect (() => cancel_running ());
            cursor.fetching = true;
            try {
                var all = new PgWriter ();
                all.put_bytes (execute_message (int.max (1, max_rows)));
                all.put_bytes (new PgWriter ().finish ('H'));
                yield send (all.raw ());
                while (true) {
                    var m = yield read_message ();
                    switch (m.type) {
                        case 'D':
                            rows.add (parse_row (m, cursor.columns));
                            break;
                        case 's':
                            return;
                        case 'C':
                        case 'I':
                            yield sync_and_drain ();
                            finish_cursor (cursor);
                            return;
                        case 'E':
                            var err = PgServerError.parse (m);
                            last_sqlstate = err.code;
                            yield sync_and_drain ();
                            finish_cursor (cursor);
                            throw err.to_error ();
                        default:
                            handle_async_message (m);
                            break;
                    }
                }
            } finally {
                cursor.fetching = false;
                if (handler != 0) cancellable.disconnect (handler);
            }
        }

        internal async void cursor_close (PgCursor cursor) throws Error {
            if (!cursor.open_on_server) return;
            try {
                var all = new PgWriter ();
                var c = new PgWriter ();
                c.put_byte ('P');
                c.put_cstr ("");
                all.put_bytes (c.finish ('C'));
                all.put_bytes (new PgWriter ().finish ('S'));
                yield send (all.raw ());
                while (true) {
                    var m = yield read_message ();
                    if (m.type == 'Z') {
                        transaction_status = (char) m.read_byte ();
                        break;
                    }
                    handle_async_message (m);
                }
            } finally {
                finish_cursor (cursor);
            }
        }

        public override async void use_database (string database, Cancellable? cancellable = null) throws Error {
            if (database == current_database && connected) return;
            yield close_async ();
            string old = config.database;
            config.database = database;
            try {
                yield open (password, cancellable);
            } catch (Error e) {
                config.database = old;
                throw e;
            }
        }

        private const string[] RESERVED = {
            "all", "analyse", "analyze", "and", "any", "array", "as", "asc", "asymmetric", "authorization", "binary", "both", "case", "cast",
            "check", "collate", "collation", "column", "concurrently", "constraint", "create", "cross", "current_catalog", "current_date",
            "current_role", "current_schema", "current_time", "current_timestamp", "current_user", "default", "deferrable", "desc",
            "distinct", "do", "else", "end", "except", "false", "fetch", "for", "foreign", "freeze", "from", "full", "grant", "group",
            "having", "ilike", "in", "initially", "inner", "intersect", "into", "is", "isnull", "join", "lateral", "leading", "left",
            "like", "limit", "localtime", "localtimestamp", "natural", "not", "notnull", "null", "offset", "on", "only", "or", "order",
            "outer", "overlaps", "placing", "primary", "references", "returning", "right", "select", "session_user", "similar", "some",
            "symmetric", "system_user", "table", "tablesample", "then", "to", "trailing", "true", "union", "unique", "user", "using",
            "variadic", "verbose", "when", "where", "window", "with"
        };

        public override string quote_ident (string name) {
            bool plain = name.length > 0 && (name[0].islower () || name[0] == '_');
            for (int i = 0; plain && i < name.length; i++) {
                char c = name[i];
                if (!(c.islower () || c.isdigit () || c == '_' || c == '$')) plain = false;
            }
            if (plain) {
                foreach (string r in RESERVED) {
                    if (r == name) plain = false;
                }
            }
            if (plain) return name;
            return "\"" + name.replace ("\"", "\"\"") + "\"";
        }

        public override string placeholder (int index) {
            return "$%d".printf (index);
        }

        public override string literal (DbValue v) {
            switch (v.kind) {
                case ValueKind.NULL: return "NULL";
                case ValueKind.BLOB: return "'%s'::bytea".printf (PgTypes.encode (v));
                case ValueKind.REAL:
                    if (!v.real_value.is_finite ()) return "'%s'::float8".printf (PgTypes.encode (v));
                    return v.sql_literal ();
                case ValueKind.TEXT:
                    string t = v.text_value;
                    if (t.contains ("\\")) return "E'" + t.replace ("\\", "\\\\").replace ("'", "''") + "'";
                    return "'" + t.replace ("'", "''") + "'";
                default:
                    return v.sql_literal ();
            }
        }

        public override string text_cast (string expr) {
            return "CAST(%s AS TEXT)".printf (expr);
        }

        public override string explain_sql (string sql, bool analyze) {
            return analyze ? "EXPLAIN (ANALYZE, BUFFERS) " + sql : "EXPLAIN " + sql;
        }

        public override string[] keywords () {
            return {
                "SELECT", "FROM", "WHERE", "GROUP BY", "HAVING", "ORDER BY", "LIMIT", "OFFSET", "INSERT INTO", "VALUES", "UPDATE", "SET",
                "DELETE FROM", "RETURNING", "WITH", "RECURSIVE", "JOIN", "LEFT JOIN", "RIGHT JOIN", "FULL JOIN", "CROSS JOIN", "LATERAL",
                "ON", "USING", "UNION", "INTERSECT", "EXCEPT", "DISTINCT", "DISTINCT ON", "CREATE TABLE", "CREATE INDEX", "CREATE VIEW",
                "CREATE MATERIALIZED VIEW", "CREATE SCHEMA", "CREATE SEQUENCE", "CREATE FUNCTION", "CREATE TRIGGER", "ALTER TABLE",
                "DROP TABLE", "TRUNCATE", "BEGIN", "COMMIT", "ROLLBACK", "SAVEPOINT", "EXPLAIN", "ANALYZE", "VACUUM", "GRANT", "REVOKE",
                "ILIKE", "SIMILAR TO", "IS DISTINCT FROM", "ON CONFLICT", "DO NOTHING", "DO UPDATE", "WINDOW", "OVER", "PARTITION BY",
                "FILTER", "COALESCE", "NULLIF", "GREATEST", "LEAST", "now()", "current_date", "generate_series", "string_agg", "array_agg",
                "jsonb_build_object", "to_char", "date_trunc", "extract", "count", "sum", "avg", "min", "max"
            };
        }

        public override string[] type_names () {
            return {
                "smallint", "integer", "bigint", "serial", "bigserial", "numeric", "numeric(12,2)", "real", "double precision", "money",
                "text", "varchar(255)", "char(1)", "boolean", "date", "time", "timestamp", "timestamptz", "interval", "uuid", "json",
                "jsonb", "bytea", "inet", "cidr", "macaddr", "xml", "tsvector", "integer[]", "text[]"
            };
        }

        public override async Gee.ArrayList<string> list_databases (Cancellable? cancellable = null) throws Error {
            var list = new Gee.ArrayList<string> ();
            var r = yield execute ("SELECT datname FROM pg_database WHERE NOT datistemplate AND datallowconn ORDER BY datname", null, cancellable);
            foreach (var row in r.rows) list.add (row.get (0).to_string ());
            return list;
        }

        public override async Gee.ArrayList<string> list_schemas (Cancellable? cancellable = null) throws Error {
            var list = new Gee.ArrayList<string> ();
            var r = yield execute ("SELECT nspname FROM pg_namespace WHERE nspname NOT LIKE 'pg\\_toast%' AND nspname NOT LIKE 'pg\\_temp%' ORDER BY nspname IN ('pg_catalog', 'information_schema'), nspname", null, cancellable);
            foreach (var row in r.rows) list.add (row.get (0).to_string ());
            return list;
        }

        public override async Gee.ArrayList<CatalogObject> list_objects (string schema, Cancellable? cancellable = null) throws Error {
            var list = new Gee.ArrayList<CatalogObject> ();
            DbValue[] p = { new DbValue.text (schema) };
            var rels = yield execute (
                "SELECT c.relname, c.relkind::text, COALESCE(obj_description(c.oid, 'pg_class'), ''), c.reltuples::bigint " +
                "FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = $1 AND c.relkind IN ('r', 'p', 'v', 'm', 'S', 'f') ORDER BY c.relname", p, cancellable);
            foreach (var row in rels.rows) {
                string k = row.get (1).to_string ();
                ObjectKind kind = ObjectKind.TABLE;
                if (k == "v") kind = ObjectKind.VIEW;
                else if (k == "m") kind = ObjectKind.MATERIALIZED_VIEW;
                else if (k == "S") kind = ObjectKind.SEQUENCE;
                var o = new CatalogObject (kind, schema, row.get (0).to_string ());
                o.comment = row.get (2).to_string ();
                if (kind == ObjectKind.TABLE || kind == ObjectKind.MATERIALIZED_VIEW) {
                    int64 est = row.get (3).as_int ();
                    o.row_estimate = est < 0 ? -1 : est;
                }
                if (k == "p") o.detail = _("Partitioned");
                if (k == "f") o.detail = _("Foreign");
                list.add (o);
            }
            var idx = yield execute (
                "SELECT i.relname, t.relname, x.indisunique, x.indisprimary, am.amname FROM pg_index x JOIN pg_class i ON i.oid = x.indexrelid " +
                "JOIN pg_class t ON t.oid = x.indrelid JOIN pg_namespace n ON n.oid = i.relnamespace JOIN pg_am am ON am.oid = i.relam " +
                "WHERE n.nspname = $1 ORDER BY t.relname, i.relname", p, cancellable);
            foreach (var row in idx.rows) {
                var o = new CatalogObject (ObjectKind.INDEX, schema, row.get (0).to_string ());
                o.parent = row.get (1).to_string ();
                string[] parts = {};
                if (row.get (3).as_bool ()) parts += _("primary key");
                else if (row.get (2).as_bool ()) parts += _("unique");
                parts += row.get (4).to_string ();
                o.detail = string.joinv (", ", parts);
                list.add (o);
            }
            var fn = yield execute (
                "SELECT p.proname, p.prokind::text, pg_get_function_identity_arguments(p.oid), COALESCE(obj_description(p.oid, 'pg_proc'), '') " +
                "FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = $1 AND p.prokind IN ('f', 'p') ORDER BY p.proname", p, cancellable);
            foreach (var row in fn.rows) {
                var o = new CatalogObject (row.get (1).to_string () == "p" ? ObjectKind.PROCEDURE : ObjectKind.FUNCTION, schema, row.get (0).to_string ());
                o.detail = row.get (2).to_string ();
                o.comment = row.get (3).to_string ();
                list.add (o);
            }
            var tg = yield execute (
                "SELECT t.tgname, c.relname FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace " +
                "WHERE n.nspname = $1 AND NOT t.tgisinternal ORDER BY c.relname, t.tgname", p, cancellable);
            foreach (var row in tg.rows) {
                var o = new CatalogObject (ObjectKind.TRIGGER, schema, row.get (0).to_string ());
                o.parent = row.get (1).to_string ();
                list.add (o);
            }
            return list;
        }

        private async int64 relation_oid (string schema, string name, Cancellable? cancellable) throws Error {
            var r = yield execute ("SELECT c.oid FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = $1 AND c.relname = $2",
                { new DbValue.text (schema), new DbValue.text (name) }, cancellable);
            if (r.rows.size == 0) throw new RemoteError.SERVER (_("\"%s.%s\" does not exist.").printf (schema, name));
            return r.rows[0].get (0).as_int ();
        }

        private static string action_word (string code) {
            switch (code) {
                case "r": return "RESTRICT";
                case "c": return "CASCADE";
                case "n": return "SET NULL";
                case "d": return "SET DEFAULT";
                default: return "NO ACTION";
            }
        }

        public override async TableInfo describe_table (string schema, string table, Cancellable? cancellable = null) throws Error {
            int64 oid = yield relation_oid (schema, table, cancellable);
            DbValue[] p = { new DbValue.int (oid) };
            var t = new TableInfo ();
            t.schema = schema;
            t.name = table;
            var cm = yield execute ("SELECT COALESCE(obj_description($1::oid, 'pg_class'), '')", p, cancellable);
            if (cm.rows.size > 0) t.comment = cm.rows[0].get (0).to_string ();
            var cols = yield execute (
                "SELECT a.attname, format_type(a.atttypid, a.atttypmod), NOT a.attnotnull, COALESCE(pg_get_expr(d.adbin, d.adrelid), ''), " +
                "COALESCE(col_description(a.attrelid, a.attnum), ''), a.attidentity::text, a.attnum, " +
                "EXISTS (SELECT 1 FROM pg_index i WHERE i.indrelid = a.attrelid AND i.indisprimary AND a.attnum = ANY (i.indkey)) " +
                "FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum " +
                "WHERE a.attrelid = $1::oid AND a.attnum > 0 AND NOT a.attisdropped ORDER BY a.attnum", p, cancellable);
            foreach (var row in cols.rows) {
                var c = new ColumnInfo ();
                c.name = row.get (0).to_string ();
                c.data_type = row.get (1).to_string ();
                c.nullable = row.get (2).as_bool ();
                c.default_expr = row.get (3).to_string ();
                c.comment = row.get (4).to_string ();
                string ident = row.get (5).to_string ();
                c.auto_increment = ident == "a" || ident == "d" || c.default_expr.has_prefix ("nextval(");
                c.position = (int) row.get (6).as_int ();
                c.primary_key = row.get (7).as_bool ();
                t.columns.add (c);
            }
            var idx = yield execute (
                "SELECT ic.relname, x.indisunique, x.indisprimary, am.amname, " +
                "(SELECT string_agg(pg_get_indexdef(x.indexrelid, k, true), chr(31) ORDER BY k) FROM generate_series(1, x.indnkeyatts) k) " +
                "FROM pg_index x JOIN pg_class ic ON ic.oid = x.indexrelid JOIN pg_am am ON am.oid = ic.relam WHERE x.indrelid = $1::oid ORDER BY ic.relname", p, cancellable);
            foreach (var row in idx.rows) {
                var i = new IndexInfo ();
                i.name = row.get (0).to_string ();
                i.unique = row.get (1).as_bool ();
                i.primary = row.get (2).as_bool ();
                i.method = row.get (3).to_string ();
                i.columns = row.get (4).to_string ().split ("\x1f");
                t.indexes.add (i);
            }
            var fks = yield execute (
                "SELECT con.conname, " +
                "(SELECT string_agg(a.attname, chr(31) ORDER BY k.ord) FROM unnest(con.conkey) WITH ORDINALITY k(attnum, ord) JOIN pg_attribute a ON a.attrelid = con.conrelid AND a.attnum = k.attnum), " +
                "rn.nspname, rc.relname, " +
                "(SELECT string_agg(a.attname, chr(31) ORDER BY k.ord) FROM unnest(con.confkey) WITH ORDINALITY k(attnum, ord) JOIN pg_attribute a ON a.attrelid = con.confrelid AND a.attnum = k.attnum), " +
                "con.confupdtype::text, con.confdeltype::text FROM pg_constraint con JOIN pg_class rc ON rc.oid = con.confrelid " +
                "JOIN pg_namespace rn ON rn.oid = rc.relnamespace WHERE con.conrelid = $1::oid AND con.contype = 'f' ORDER BY con.conname", p, cancellable);
            foreach (var row in fks.rows) {
                var f = new ForeignKeyInfo ();
                f.name = row.get (0).to_string ();
                f.columns = row.get (1).to_string ().split ("\x1f");
                f.ref_schema = row.get (2).to_string ();
                f.ref_table = row.get (3).to_string ();
                f.ref_columns = row.get (4).to_string ().split ("\x1f");
                f.on_update = action_word (row.get (5).to_string ());
                f.on_delete = action_word (row.get (6).to_string ());
                t.foreign_keys.add (f);
            }
            var ck = yield execute ("SELECT pg_get_constraintdef(oid, true) FROM pg_constraint WHERE conrelid = $1::oid AND contype = 'c' ORDER BY conname", p, cancellable);
            string[] checks = {};
            foreach (var row in ck.rows) checks += row.get (0).to_string ();
            t.checks = checks;
            return t;
        }

        public override async string object_definition (CatalogObject obj, Cancellable? cancellable = null) throws Error {
            DbValue[] p = { new DbValue.text (obj.schema), new DbValue.text (obj.name) };
            string q = qualified (obj.schema, obj.name);
            QueryResult r;
            switch (obj.kind) {
                case ObjectKind.VIEW:
                case ObjectKind.MATERIALIZED_VIEW:
                    int64 oid = yield relation_oid (obj.schema, obj.name, cancellable);
                    r = yield execute ("SELECT pg_get_viewdef($1::oid, true)", { new DbValue.int (oid) }, cancellable);
                    string head = obj.kind == ObjectKind.VIEW ? "CREATE OR REPLACE VIEW %s AS\n".printf (q) : "CREATE MATERIALIZED VIEW %s AS\n".printf (q);
                    return head + r.rows[0].get (0).to_string ();
                case ObjectKind.FUNCTION:
                case ObjectKind.PROCEDURE:
                    r = yield execute ("SELECT pg_get_functiondef(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = $1 AND p.proname = $2 AND pg_get_function_identity_arguments(p.oid) = $3",
                        { p[0], p[1], new DbValue.text (obj.detail) }, cancellable);
                    if (r.rows.size == 0) r = yield execute ("SELECT pg_get_functiondef(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = $1 AND p.proname = $2 LIMIT 1", p, cancellable);
                    return r.rows.size > 0 ? r.rows[0].get (0).to_string () : "";
                case ObjectKind.INDEX:
                    r = yield execute ("SELECT pg_get_indexdef(c.oid) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = $1 AND c.relname = $2", p, cancellable);
                    return r.rows.size > 0 ? r.rows[0].get (0).to_string () + ";" : "";
                case ObjectKind.TRIGGER:
                    r = yield execute ("SELECT pg_get_triggerdef(t.oid, true) FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = $1 AND t.tgname = $2 AND c.relname = $3",
                        { p[0], p[1], new DbValue.text (obj.parent) }, cancellable);
                    return r.rows.size > 0 ? r.rows[0].get (0).to_string () + ";" : "";
                case ObjectKind.SEQUENCE:
                    r = yield execute ("SELECT data_type::text, start_value, min_value, max_value, increment_by, cycle, cache_size FROM pg_sequences WHERE schemaname = $1 AND sequencename = $2", p, cancellable);
                    if (r.rows.size == 0) return "";
                    var s = r.rows[0];
                    return "CREATE SEQUENCE %s AS %s INCREMENT BY %s MINVALUE %s MAXVALUE %s START WITH %s CACHE %s%s;".printf (q, s.get (0).to_string (), s.get (4).to_string (),
                        s.get (2).to_string (), s.get (3).to_string (), s.get (1).to_string (), s.get (6).to_string (), s.get (5).as_bool () ? " CYCLE" : " NO CYCLE");
                case ObjectKind.SCHEMA:
                    return "CREATE SCHEMA %s;".printf (quote_ident (obj.name));
                case ObjectKind.DATABASE:
                    return "CREATE DATABASE %s;".printf (quote_ident (obj.name));
                default:
                    var t = yield describe_table (obj.schema, obj.name, cancellable);
                    var sb = new StringBuilder (create_table_sql (t));
                    foreach (var i in t.indexes) {
                        if (i.primary) continue;
                        sb.append ("\n").append (create_index_sql (t, i)).append (";");
                    }
                    return sb.str;
            }
        }

        private string column_ref (TableInfo t, string col) {
            foreach (var c in t.columns) {
                if (c.name == col) return quote_ident (col);
            }
            return col;
        }

        private string column_list (TableInfo t, string[] cols) {
            string[] q = {};
            foreach (string c in cols) q += column_ref (t, c);
            return string.joinv (", ", q);
        }

        private string plain_list (string[] cols) {
            string[] q = {};
            foreach (string c in cols) q += quote_ident (c);
            return string.joinv (", ", q);
        }

        private string create_index_sql (TableInfo t, IndexInfo i) {
            string method = i.method != "" && i.method != "btree" ? " USING " + i.method : "";
            return "CREATE %sINDEX %s ON %s%s (%s)".printf (i.unique ? "UNIQUE " : "", quote_ident (i.name), qualified (t.schema, t.name), method, column_list (t, i.columns));
        }

        private string fk_sql (ForeignKeyInfo f) {
            var sb = new StringBuilder ();
            if (f.name != "") sb.append ("CONSTRAINT %s ".printf (quote_ident (f.name)));
            sb.append ("FOREIGN KEY (%s) REFERENCES %s (%s)".printf (plain_list (f.columns), qualified (f.ref_schema, f.ref_table), plain_list (f.ref_columns)));
            if (f.on_update != "" && f.on_update != "NO ACTION") sb.append (" ON UPDATE ").append (f.on_update);
            if (f.on_delete != "" && f.on_delete != "NO ACTION") sb.append (" ON DELETE ").append (f.on_delete);
            return sb.str;
        }

        private string column_def (ColumnInfo c) {
            var sb = new StringBuilder ();
            string type = c.data_type;
            string def = c.default_expr;
            if (c.auto_increment && def.has_prefix ("nextval(")) {
                string serial = "";
                if (type == "integer") serial = "serial";
                else if (type == "bigint") serial = "bigserial";
                else if (type == "smallint") serial = "smallserial";
                if (serial != "") {
                    type = serial;
                    def = "";
                }
            }
            sb.append (quote_ident (c.name)).append (" ").append (type);
            if (c.auto_increment && c.default_expr == "") sb.append (" GENERATED BY DEFAULT AS IDENTITY");
            if (!c.nullable) sb.append (" NOT NULL");
            if (def != "") sb.append (" DEFAULT ").append (def);
            return sb.str;
        }

        public override string create_table_sql (TableInfo table) {
            string[] parts = {};
            foreach (var c in table.columns) parts += "    " + column_def (c);
            string[] pk = table.primary_key ();
            if (pk.length > 0) parts += "    PRIMARY KEY (%s)".printf (plain_list (pk));
            foreach (var f in table.foreign_keys) parts += "    " + fk_sql (f);
            foreach (string ch in table.checks) parts += "    " + (ch.up ().has_prefix ("CHECK") ? ch : "CHECK (%s)".printf (ch));
            var sb = new StringBuilder ("CREATE TABLE %s (\n%s\n);".printf (qualified (table.schema, table.name), string.joinv (",\n", parts)));
            string q = qualified (table.schema, table.name);
            if (table.comment != "") sb.append ("\nCOMMENT ON TABLE %s IS %s;".printf (q, literal (new DbValue.text (table.comment))));
            foreach (var c in table.columns) {
                if (c.comment != "") sb.append ("\nCOMMENT ON COLUMN %s.%s IS %s;".printf (q, quote_ident (c.name), literal (new DbValue.text (c.comment))));
            }
            return sb.str;
        }

        private static string[] rename_list (string[] cols, Gee.Map<string, string> renames) {
            string[] out_cols = {};
            foreach (string c in cols) out_cols += renames.has_key (c) ? renames[c] : c;
            return out_cols;
        }

        private static bool same_list (string[] a, string[] b) {
            if (a.length != b.length) return false;
            for (int i = 0; i < a.length; i++) {
                if (a[i] != b[i]) return false;
            }
            return true;
        }

        public override string[] alter_table_sql (TableInfo before, TableInfo after, Gee.List<ColumnChange> changes) {
            string[] out_sql = {};
            string old_q = qualified (before.schema, before.name);
            string q = old_q;
            if (after.name != before.name && after.name != "") {
                out_sql += "ALTER TABLE %s RENAME TO %s".printf (old_q, quote_ident (after.name));
                q = qualified (before.schema, after.name);
            }
            var renames = new Gee.HashMap<string, string> ();
            var dropped = new Gee.HashSet<string> ();
            foreach (var ch in changes) {
                if (ch.old_name != null && ch.column != null && ch.old_name != ch.column.name) renames[ch.old_name] = ch.column.name;
                if (ch.old_name != null && ch.column == null) dropped.add (ch.old_name);
            }
            var before_fk = new Gee.HashMap<string, ForeignKeyInfo> ();
            foreach (var f in before.foreign_keys) before_fk[f.name] = f;
            var after_fk = new Gee.HashMap<string, ForeignKeyInfo> ();
            foreach (var f in after.foreign_keys) after_fk[f.name] = f;
            var fk_add = new Gee.ArrayList<ForeignKeyInfo> ();
            foreach (var f in before.foreign_keys) {
                var a = after_fk[f.name];
                bool same = a != null && same_list (rename_list (f.columns, renames), a.columns) && a.ref_table == f.ref_table && a.ref_schema == f.ref_schema
                    && same_list (f.ref_columns, a.ref_columns) && a.on_update == f.on_update && a.on_delete == f.on_delete;
                if (!same) {
                    out_sql += "ALTER TABLE %s DROP CONSTRAINT %s".printf (q, quote_ident (f.name));
                    if (a != null) fk_add.add (a);
                }
            }
            foreach (var f in after.foreign_keys) {
                if (f.name == "" || !before_fk.has_key (f.name)) fk_add.add (f);
            }
            var before_idx = new Gee.HashMap<string, IndexInfo> ();
            foreach (var i in before.indexes) if (!i.primary) before_idx[i.name] = i;
            var after_idx = new Gee.HashMap<string, IndexInfo> ();
            foreach (var i in after.indexes) if (!i.primary) after_idx[i.name] = i;
            var idx_add = new Gee.ArrayList<IndexInfo> ();
            foreach (var i in before_idx.values) {
                var a = after_idx[i.name];
                bool same = a != null && a.unique == i.unique && same_list (rename_list (i.columns, renames), a.columns) && (a.method == "" || a.method == i.method);
                if (!same) {
                    out_sql += "DROP INDEX %s".printf (qualified (before.schema, i.name));
                    if (a != null) idx_add.add (a);
                }
            }
            foreach (var i in after_idx.values) {
                if (!before_idx.has_key (i.name)) idx_add.add (i);
            }
            string[] pk_before = rename_list (before.primary_key (), renames);
            string[] pk_after = after.primary_key ();
            bool pk_changed = !same_list (pk_before, pk_after);
            if (pk_changed && before.primary_key ().length > 0) {
                string pk_name = before.name + "_pkey";
                foreach (var i in before.indexes) if (i.primary) pk_name = i.name;
                out_sql += "ALTER TABLE %s DROP CONSTRAINT %s".printf (q, quote_ident (pk_name));
            }
            foreach (var ch in changes) {
                if (ch.old_name != null && ch.column == null) out_sql += "ALTER TABLE %s DROP COLUMN %s".printf (q, quote_ident (ch.old_name));
            }
            foreach (var ch in changes) {
                if (ch.old_name != null && ch.column != null && ch.old_name != ch.column.name) {
                    out_sql += "ALTER TABLE %s RENAME COLUMN %s TO %s".printf (q, quote_ident (ch.old_name), quote_ident (ch.column.name));
                }
            }
            foreach (var ch in changes) {
                if (ch.old_name == null || ch.column == null) continue;
                var old = before.find (ch.old_name);
                if (old == null) continue;
                var c = ch.column;
                string cq = quote_ident (c.name);
                if (old.data_type != c.data_type) out_sql += "ALTER TABLE %s ALTER COLUMN %s TYPE %s USING %s::%s".printf (q, cq, c.data_type, cq, c.data_type);
                if (old.nullable != c.nullable) out_sql += "ALTER TABLE %s ALTER COLUMN %s %s".printf (q, cq, c.nullable ? "DROP NOT NULL" : "SET NOT NULL");
                bool old_identity = old.auto_increment && !old.default_expr.has_prefix ("nextval(");
                bool new_identity = c.auto_increment && (c.default_expr == "" || !c.default_expr.has_prefix ("nextval("));
                if (old_identity && !c.auto_increment) out_sql += "ALTER TABLE %s ALTER COLUMN %s DROP IDENTITY IF EXISTS".printf (q, cq);
                if (old.default_expr != c.default_expr && !(new_identity && c.default_expr == "")) {
                    if (c.default_expr == "") out_sql += "ALTER TABLE %s ALTER COLUMN %s DROP DEFAULT".printf (q, cq);
                    else out_sql += "ALTER TABLE %s ALTER COLUMN %s SET DEFAULT %s".printf (q, cq, c.default_expr);
                }
                if (!old.auto_increment && new_identity && c.default_expr == "") out_sql += "ALTER TABLE %s ALTER COLUMN %s ADD GENERATED BY DEFAULT AS IDENTITY".printf (q, cq);
                if (old.comment != c.comment) {
                    out_sql += "COMMENT ON COLUMN %s.%s IS %s".printf (q, cq, c.comment == "" ? "NULL" : literal (new DbValue.text (c.comment)));
                }
            }
            foreach (var ch in changes) {
                if (ch.old_name != null || ch.column == null) continue;
                out_sql += "ALTER TABLE %s ADD COLUMN %s".printf (q, column_def (ch.column));
                if (ch.column.comment != "") out_sql += "COMMENT ON COLUMN %s.%s IS %s".printf (q, quote_ident (ch.column.name), literal (new DbValue.text (ch.column.comment)));
            }
            if (pk_changed && pk_after.length > 0) out_sql += "ALTER TABLE %s ADD PRIMARY KEY (%s)".printf (q, plain_list (pk_after));
            var t_after = after.copy ();
            t_after.schema = before.schema;
            foreach (var i in idx_add) out_sql += create_index_sql (t_after, i);
            foreach (var f in fk_add) out_sql += "ALTER TABLE %s ADD %s".printf (q, fk_sql (f));
            foreach (string ch in after.checks) {
                bool exists = false;
                foreach (string b in before.checks) if (b == ch) exists = true;
                if (!exists) out_sql += "ALTER TABLE %s ADD %s".printf (q, ch.up ().has_prefix ("CHECK") ? ch : "CHECK (%s)".printf (ch));
            }
            if (after.comment != before.comment) out_sql += "COMMENT ON TABLE %s IS %s".printf (q, after.comment == "" ? "NULL" : literal (new DbValue.text (after.comment)));
            return out_sql;
        }

        private string alias (string label) {
            return quote_ident (label);
        }

        public override async QueryResult list_users (Cancellable? cancellable = null) throws Error {
            string sql = ("SELECT r.rolname AS %s, r.rolsuper AS %s, r.rolcreaterole AS %s, r.rolcreatedb AS %s, r.rolcanlogin AS %s, " +
                "r.rolconnlimit AS %s, r.rolvaliduntil::text AS %s, " +
                "COALESCE((SELECT string_agg(b.rolname, ', ' ORDER BY b.rolname) FROM pg_auth_members m JOIN pg_roles b ON b.oid = m.roleid WHERE m.member = r.oid), '') AS %s " +
                "FROM pg_roles r WHERE r.rolname NOT LIKE 'pg\\_%%' ORDER BY r.rolname").printf (
                alias (_("Role")), alias (_("Superuser")), alias (_("Create Roles")), alias (_("Create Databases")), alias (_("Login")),
                alias (_("Connection Limit")), alias (_("Valid Until")), alias (_("Member Of")));
            return yield execute (sql, null, cancellable);
        }

        public override async QueryResult list_privileges (string user, Cancellable? cancellable = null) throws Error {
            string sql = ("SELECT %s, %s, %s FROM (" +
                "SELECT 1 AS o, 'Database' AS lvl, datname::text AS obj, concat_ws(', ', CASE WHEN has_database_privilege($1::name, datname, 'CONNECT') THEN 'CONNECT' END, " +
                "CASE WHEN has_database_privilege($1::name, datname, 'CREATE') THEN 'CREATE' END, CASE WHEN has_database_privilege($1::name, datname, 'TEMPORARY') THEN 'TEMPORARY' END) AS privs " +
                "FROM pg_database WHERE datallowconn AND NOT datistemplate " +
                "UNION ALL SELECT 2, 'Schema', nspname::text, concat_ws(', ', CASE WHEN has_schema_privilege($1::name, nspname, 'USAGE') THEN 'USAGE' END, " +
                "CASE WHEN has_schema_privilege($1::name, nspname, 'CREATE') THEN 'CREATE' END) " +
                "FROM pg_namespace WHERE nspname NOT LIKE 'pg\\_%%' AND nspname <> 'information_schema' " +
                "UNION ALL SELECT 3, 'Table', table_schema || '.' || table_name, string_agg(privilege_type, ', ' ORDER BY privilege_type) " +
                "FROM information_schema.role_table_grants WHERE grantee = $1::text GROUP BY table_schema, table_name" +
                ") p WHERE privs <> '' ORDER BY o, obj").printf ("lvl AS " + alias (_("Level")), "obj AS " + alias (_("Object")), "privs AS " + alias (_("Privileges")));
            return yield execute (sql, { new DbValue.text (user) }, cancellable);
        }

        public override async QueryResult list_activity (Cancellable? cancellable = null) throws Error {
            string sql = ("SELECT pid AS %s, usename AS %s, datname AS %s, COALESCE(client_addr::text, 'local') AS %s, application_name AS %s, " +
                "state AS %s, query_start::text AS %s, COALESCE(wait_event_type || ': ' || wait_event, '') AS %s, query AS %s " +
                "FROM pg_stat_activity WHERE backend_type = 'client backend' ORDER BY query_start NULLS LAST").printf (
                alias (_("PID")), alias (_("User")), alias (_("Database")), alias (_("Client")), alias (_("Application")),
                alias (_("State")), alias (_("Started")), alias (_("Waiting For")), alias (_("Query")));
            return yield execute (sql, null, cancellable);
        }

        public override async void kill_activity (string id, bool whole_connection, Cancellable? cancellable = null) throws Error {
            int64 pid;
            if (!int64.try_parse (id, out pid)) throw new RemoteError.SERVER (_("\"%s\" is not a process number.").printf (id));
            var r = yield execute (whole_connection ? "SELECT pg_terminate_backend($1::int)" : "SELECT pg_cancel_backend($1::int)", { new DbValue.int (pid) }, cancellable);
            if (r.rows.size == 0 || !r.rows[0].get (0).as_bool ()) throw new RemoteError.SERVER (_("The process %s could not be stopped.").printf (id));
        }
    }
}
