namespace Singularity.Apps.Database {

    public errordomain RemoteError {
        CONNECT,
        AUTH,
        TLS,
        PROTOCOL,
        SERVER,
        CANCELLED,
        UNSUPPORTED,
        CONFLICT
    }

    public enum EngineKind {
        SQLITE,
        POSTGRESQL,
        MYSQL;

        public string id () {
            switch (this) {
                case POSTGRESQL: return "postgresql";
                case MYSQL: return "mysql";
                default: return "sqlite";
            }
        }

        public static EngineKind from_id (string s) {
            switch (s) {
                case "postgresql": return POSTGRESQL;
                case "mysql": return MYSQL;
                default: return SQLITE;
            }
        }

        public string label () {
            switch (this) {
                case POSTGRESQL: return "PostgreSQL";
                case MYSQL: return "MySQL / MariaDB";
                default: return "SQLite";
            }
        }

        public int default_port () {
            switch (this) {
                case POSTGRESQL: return 5432;
                case MYSQL: return 3306;
                default: return 0;
            }
        }
    }

    public enum SslMode {
        DISABLE,
        PREFER,
        REQUIRE,
        VERIFY_FULL;

        public string id () {
            switch (this) {
                case DISABLE: return "disable";
                case REQUIRE: return "require";
                case VERIFY_FULL: return "verify-full";
                default: return "prefer";
            }
        }

        public static SslMode from_id (string s) {
            switch (s) {
                case "disable": return DISABLE;
                case "require": return REQUIRE;
                case "verify-full": return VERIFY_FULL;
                default: return PREFER;
            }
        }

        public string label () {
            switch (this) {
                case DISABLE: return _("Disabled");
                case REQUIRE: return _("Required");
                case VERIFY_FULL: return _("Required and Verified");
                default: return _("When Available");
            }
        }
    }

    public class ConnectionConfig : Object {
        public string id = "";
        public string name = "";
        public EngineKind kind = EngineKind.POSTGRESQL;
        public string host = "127.0.0.1";
        public int port;
        public string user = "";
        public string database = "";
        public string socket_path = "";
        public string file_path = "";
        public SslMode ssl_mode = SslMode.PREFER;
        public string ssl_ca_file = "";
        public bool ssh_enabled;
        public string ssh_host = "";
        public int ssh_port = 22;
        public string ssh_user = "";
        public string ssh_key_file = "";
        public bool ssh_use_password;
        public string color = "";
        public bool read_only;
        public int connect_timeout = 10;
        public string tls_server_name = "";

        public ConnectionConfig copy () {
            var c = new ConnectionConfig ();
            c.id = id;
            c.name = name;
            c.kind = kind;
            c.host = host;
            c.port = port;
            c.user = user;
            c.database = database;
            c.socket_path = socket_path;
            c.file_path = file_path;
            c.ssl_mode = ssl_mode;
            c.ssl_ca_file = ssl_ca_file;
            c.ssh_enabled = ssh_enabled;
            c.ssh_host = ssh_host;
            c.ssh_port = ssh_port;
            c.ssh_user = ssh_user;
            c.ssh_key_file = ssh_key_file;
            c.ssh_use_password = ssh_use_password;
            c.color = color;
            c.read_only = read_only;
            c.connect_timeout = connect_timeout;
            c.tls_server_name = tls_server_name;
            return c;
        }

        public string tls_host () {
            if (tls_server_name != "") return tls_server_name;
            return host != "" ? host : "localhost";
        }

        public int effective_port () {
            return port > 0 ? port : kind.default_port ();
        }

        public string summary () {
            if (kind == EngineKind.SQLITE) return file_path;
            string where = socket_path != "" ? socket_path : "%s:%d".printf (host, effective_port ());
            string who = user != "" ? user + "@" : "";
            string db = database != "" ? "/" + database : "";
            return who + where + db;
        }
    }

    public class ColumnMeta {
        public string name;
        public string type_name = "";
        public uint32 type_oid;
        public string table = "";
        public string origin = "";

        public ColumnMeta (string name) {
            this.name = name;
        }
    }

    public class QueryResult {
        public Gee.ArrayList<ColumnMeta> columns = new Gee.ArrayList<ColumnMeta> ();
        public Gee.ArrayList<Row> rows = new Gee.ArrayList<Row> ();
        public int64 affected = -1;
        public string command = "";
        public bool truncated;
        public double elapsed_ms;
        public Gee.ArrayList<string> notices = new Gee.ArrayList<string> ();

        public bool has_rows () {
            return columns.size > 0;
        }

        public int index_of (string column) {
            for (int i = 0; i < columns.size; i++) {
                if (columns[i].name.casefold () == column.casefold ()) return i;
            }
            return -1;
        }

        public string text (int row, string column) {
            int i = index_of (column);
            if (i < 0 || row >= rows.size) return "";
            return rows[row].get (i).to_string ();
        }
    }

    public abstract class Cursor : Object {
        public Gee.ArrayList<ColumnMeta> columns = new Gee.ArrayList<ColumnMeta> ();
        public bool done { get; protected set; }

        public abstract async Gee.ArrayList<Row> fetch (int max_rows, Cancellable? cancellable = null) throws Error;

        public abstract async void close_async () throws Error;
    }

    public enum ObjectKind {
        DATABASE,
        SCHEMA,
        TABLE,
        VIEW,
        MATERIALIZED_VIEW,
        INDEX,
        FUNCTION,
        PROCEDURE,
        TRIGGER,
        SEQUENCE,
        EVENT;

        public string label () {
            switch (this) {
                case DATABASE: return _("Database");
                case SCHEMA: return _("Schema");
                case TABLE: return _("Table");
                case VIEW: return _("View");
                case MATERIALIZED_VIEW: return _("Materialized View");
                case INDEX: return _("Index");
                case FUNCTION: return _("Function");
                case PROCEDURE: return _("Procedure");
                case TRIGGER: return _("Trigger");
                case SEQUENCE: return _("Sequence");
                default: return _("Event");
            }
        }

        public string plural () {
            switch (this) {
                case DATABASE: return _("Databases");
                case SCHEMA: return _("Schemas");
                case TABLE: return _("Tables");
                case VIEW: return _("Views");
                case MATERIALIZED_VIEW: return _("Materialized Views");
                case INDEX: return _("Indexes");
                case FUNCTION: return _("Functions");
                case PROCEDURE: return _("Procedures");
                case TRIGGER: return _("Triggers");
                case SEQUENCE: return _("Sequences");
                default: return _("Events");
            }
        }
    }

    public class CatalogObject {
        public ObjectKind kind;
        public string schema = "";
        public string name = "";
        public string parent = "";
        public string comment = "";
        public string detail = "";
        public int64 row_estimate = -1;

        public CatalogObject (ObjectKind kind, string schema, string name) {
            this.kind = kind;
            this.schema = schema;
            this.name = name;
        }
    }

    public class ColumnInfo {
        public string name = "";
        public string data_type = "";
        public bool nullable = true;
        public string default_expr = "";
        public string comment = "";
        public bool primary_key;
        public bool auto_increment;
        public int position;

        public ColumnInfo copy () {
            var c = new ColumnInfo ();
            c.name = name;
            c.data_type = data_type;
            c.nullable = nullable;
            c.default_expr = default_expr;
            c.comment = comment;
            c.primary_key = primary_key;
            c.auto_increment = auto_increment;
            c.position = position;
            return c;
        }

        public bool same_definition (ColumnInfo o) {
            return data_type == o.data_type && nullable == o.nullable && default_expr == o.default_expr && comment == o.comment;
        }
    }

    public class IndexInfo {
        public string name = "";
        public string[] columns = {};
        public bool unique;
        public bool primary;
        public string method = "";

        public IndexInfo copy () {
            var i = new IndexInfo ();
            i.name = name;
            i.columns = columns;
            i.unique = unique;
            i.primary = primary;
            i.method = method;
            return i;
        }
    }

    public class ForeignKeyInfo {
        public string name = "";
        public string[] columns = {};
        public string ref_schema = "";
        public string ref_table = "";
        public string[] ref_columns = {};
        public string on_update = "";
        public string on_delete = "";

        public ForeignKeyInfo copy () {
            var f = new ForeignKeyInfo ();
            f.name = name;
            f.columns = columns;
            f.ref_schema = ref_schema;
            f.ref_table = ref_table;
            f.ref_columns = ref_columns;
            f.on_update = on_update;
            f.on_delete = on_delete;
            return f;
        }
    }

    public class TableInfo {
        public string schema = "";
        public string name = "";
        public string comment = "";
        public Gee.ArrayList<ColumnInfo> columns = new Gee.ArrayList<ColumnInfo> ();
        public Gee.ArrayList<IndexInfo> indexes = new Gee.ArrayList<IndexInfo> ();
        public Gee.ArrayList<ForeignKeyInfo> foreign_keys = new Gee.ArrayList<ForeignKeyInfo> ();
        public string[] checks = {};

        public TableInfo copy () {
            var t = new TableInfo ();
            t.schema = schema;
            t.name = name;
            t.comment = comment;
            foreach (var c in columns) t.columns.add (c.copy ());
            foreach (var i in indexes) t.indexes.add (i.copy ());
            foreach (var f in foreign_keys) t.foreign_keys.add (f.copy ());
            t.checks = checks;
            return t;
        }

        public string[] primary_key () {
            string[] pk = {};
            foreach (var c in columns) {
                if (c.primary_key) pk += c.name;
            }
            return pk;
        }

        public ColumnInfo? find (string column) {
            foreach (var c in columns) {
                if (c.name == column) return c;
            }
            return null;
        }
    }

    public class ColumnChange {
        public string? old_name;
        public ColumnInfo? column;

        public ColumnChange (string? old_name, ColumnInfo? column) {
            this.old_name = old_name;
            this.column = column;
        }
    }

    public abstract class Engine : Object {
        public ConnectionConfig config { get; construct; }
        public string server_version { get; protected set; default = ""; }
        public string current_database { get; protected set; default = ""; }
        public bool connected { get; protected set; }

        public signal void notice (string message);

        public EngineKind kind {
            get { return config.kind; }
        }

        public abstract async void open (string? password, Cancellable? cancellable = null) throws Error;

        public abstract async void close_async ();

        public abstract void cancel_running ();

        public abstract async QueryResult execute (string sql, DbValue[]? params = null, Cancellable? cancellable = null, int max_rows = -1) throws Error;

        public abstract async Cursor open_cursor (string sql, DbValue[]? params = null, Cancellable? cancellable = null) throws Error;

        public abstract async void use_database (string database, Cancellable? cancellable = null) throws Error;

        public abstract string quote_ident (string name);

        public abstract string placeholder (int index);

        public virtual string qualified (string schema, string name) {
            if (schema == "") return quote_ident (name);
            return quote_ident (schema) + "." + quote_ident (name);
        }

        public virtual string literal (DbValue v) {
            return v.sql_literal ();
        }

        public abstract string[] keywords ();

        public abstract string[] type_names ();

        public abstract async Gee.ArrayList<string> list_databases (Cancellable? cancellable = null) throws Error;

        public abstract async Gee.ArrayList<string> list_schemas (Cancellable? cancellable = null) throws Error;

        public abstract async Gee.ArrayList<CatalogObject> list_objects (string schema, Cancellable? cancellable = null) throws Error;

        public abstract async TableInfo describe_table (string schema, string table, Cancellable? cancellable = null) throws Error;

        public abstract async string object_definition (CatalogObject obj, Cancellable? cancellable = null) throws Error;

        public abstract string[] alter_table_sql (TableInfo before, TableInfo after, Gee.List<ColumnChange> changes);

        public abstract string create_table_sql (TableInfo table);

        public abstract string explain_sql (string sql, bool analyze);

        public abstract async QueryResult list_users (Cancellable? cancellable = null) throws Error;

        public abstract async QueryResult list_privileges (string user, Cancellable? cancellable = null) throws Error;

        public abstract async QueryResult list_activity (Cancellable? cancellable = null) throws Error;

        public abstract async void kill_activity (string id, bool whole_connection, Cancellable? cancellable = null) throws Error;

        public virtual string limit_clause (int limit, int64 offset) {
            return offset > 0 ? " LIMIT %d OFFSET %lld".printf (limit, offset) : " LIMIT %d".printf (limit);
        }

        public virtual string text_cast (string expr) {
            return "CAST(%s AS CHAR)".printf (expr);
        }

        public virtual async void begin_transaction (Cancellable? cancellable = null) throws Error {
            yield execute ("BEGIN", null, cancellable);
        }

        public virtual async void commit (Cancellable? cancellable = null) throws Error {
            yield execute ("COMMIT", null, cancellable);
        }

        public virtual async void rollback (Cancellable? cancellable = null) throws Error {
            yield execute ("ROLLBACK", null, cancellable);
        }
    }
}
