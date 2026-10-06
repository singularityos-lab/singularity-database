namespace Singularity.Apps.Database {

    [CCode (cname = "prctl", cheader_filename = "sys/prctl.h")]
    extern int sdb_prctl (int option, ulong arg2, ulong arg3, ulong arg4, ulong arg5);

    public class Engines {
        public static Engine create (ConnectionConfig config) {
            switch (config.kind) {
                case EngineKind.POSTGRESQL: return new PgEngine (config);
                case EngineKind.MYSQL: return new MysqlEngine (config);
                default: return new SqliteEngine (config);
            }
        }

        public static bool is_cancelled (Error e) {
            return e is IOError.CANCELLED || e is RemoteError.CANCELLED;
        }
    }

    public class ScriptStatement {
        public string text;
        public int start;
        public int end;

        public ScriptStatement (string text, int start, int end) {
            this.text = text;
            this.start = start;
            this.end = end;
        }
    }

    public class SqlScript {
        public static Gee.ArrayList<ScriptStatement> split (string sql, EngineKind kind) {
            var list = new Gee.ArrayList<ScriptStatement> ();
            int n = sql.length;
            int start = 0;
            int i = 0;
            int depth = 0;
            int case_depth = 0;
            while (i < n) {
                char c = sql[i];
                if (c == '-' && i + 1 < n && sql[i + 1] == '-') {
                    while (i < n && sql[i] != '\n') i++;
                    continue;
                }
                if (c == '#' && kind == EngineKind.MYSQL) {
                    while (i < n && sql[i] != '\n') i++;
                    continue;
                }
                if (c == '/' && i + 1 < n && sql[i + 1] == '*') {
                    int e = sql.index_of ("*/", i + 2);
                    i = e < 0 ? n : e + 2;
                    continue;
                }
                if (c == '\'' || c == '"' || (c == '`' && kind != EngineKind.POSTGRESQL)) {
                    bool backslash = kind == EngineKind.MYSQL && c != '`';
                    i++;
                    while (i < n) {
                        if (backslash && sql[i] == '\\') {
                            i += 2;
                            continue;
                        }
                        if (sql[i] == c) {
                            if (i + 1 < n && sql[i + 1] == c) {
                                i += 2;
                                continue;
                            }
                            break;
                        }
                        i++;
                    }
                    i++;
                    continue;
                }
                if (c == '$' && kind == EngineKind.POSTGRESQL) {
                    int j = i + 1;
                    while (j < n && (sql[j].isalnum () || sql[j] == '_')) j++;
                    if (j < n && sql[j] == '$' && (j == i + 1 || !sql[i + 1].isdigit ())) {
                        string tag = sql.substring (i, j - i + 1);
                        int e = sql.index_of (tag, j + 1);
                        i = e < 0 ? n : e + tag.length;
                        continue;
                    }
                }
                if (kind != EngineKind.POSTGRESQL && (c == 'B' || c == 'b' || c == 'E' || c == 'e') && word_at (sql, i)) {
                    string w = read_word (sql, i).up ();
                    if (w == "BEGIN" && in_trigger_or_routine (sql, start, i)) {
                        depth++;
                    } else if (w == "END" && depth > 0) {
                        string next = next_word (sql, i + w.length).up ();
                        if (next == "CASE" || next == "IF" || next == "WHILE" || next == "LOOP" || next == "REPEAT") {
                            if (next == "CASE" && case_depth > 0) case_depth--;
                            int j = i + w.length;
                            while (j < n && sql[j].isspace ()) j++;
                            i = j + next.length;
                            continue;
                        } else if (case_depth > 0) {
                            case_depth--;
                        } else {
                            depth--;
                        }
                    }
                    i += w.length;
                    continue;
                }
                if (kind != EngineKind.POSTGRESQL && depth > 0 && (c == 'C' || c == 'c') && word_at (sql, i)) {
                    string w = read_word (sql, i);
                    if (w.up () == "CASE") case_depth++;
                    i += w.length;
                    continue;
                }
                if (c == ';' && depth == 0) {
                    add (list, sql, start, i);
                    start = i + 1;
                }
                i++;
            }
            add (list, sql, start, n);
            return list;
        }

        private static bool word_at (string sql, int i) {
            return i == 0 || !(sql[i - 1].isalnum () || sql[i - 1] == '_');
        }

        private static string read_word (string sql, int i) {
            int j = i;
            while (j < sql.length && (sql[j].isalnum () || sql[j] == '_')) j++;
            return sql.substring (i, j - i);
        }

        private static string next_word (string sql, int i) {
            int j = i;
            while (j < sql.length && sql[j].isspace ()) j++;
            return read_word (sql, j);
        }

        private static bool in_trigger_or_routine (string sql, int start, int at) {
            string head = sql.substring (start, at - start).up ();
            return head.contains ("CREATE") && (head.contains ("TRIGGER") || head.contains ("PROCEDURE") || head.contains ("FUNCTION") || head.contains ("EVENT"));
        }

        private static void add (Gee.ArrayList<ScriptStatement> list, string sql, int start, int end) {
            if (end <= start) return;
            string raw = sql.substring (start, end - start);
            if (strip_comments (raw).strip () == "") return;
            int lead = 0;
            while (lead < raw.length && raw[lead].isspace ()) lead++;
            int trail = raw.length;
            while (trail > lead && raw[trail - 1].isspace ()) trail--;
            list.add (new ScriptStatement (raw.substring (lead, trail - lead), start + lead, start + trail));
        }

        public static string strip_comments (string sql) {
            var sb = new StringBuilder ();
            int i = 0;
            int n = sql.length;
            while (i < n) {
                if (sql[i] == '-' && i + 1 < n && sql[i + 1] == '-') {
                    while (i < n && sql[i] != '\n') i++;
                    continue;
                }
                if (sql[i] == '/' && i + 1 < n && sql[i + 1] == '*') {
                    int e = sql.index_of ("*/", i + 2);
                    i = e < 0 ? n : e + 2;
                    continue;
                }
                sb.append_c (sql[i]);
                i++;
            }
            return sb.str;
        }

        public static ScriptStatement? statement_at (string sql, int offset, EngineKind kind) {
            var list = split (sql, kind);
            ScriptStatement? best = null;
            foreach (var s in list) {
                if (offset >= s.start && offset <= s.end + 1) return s;
                if (s.end < offset) best = s;
            }
            if (best != null) return best;
            return list.size > 0 ? list[0] : null;
        }

        public static bool returns_rows (string sql) {
            string s = strip_comments (sql).strip ().up ();
            foreach (string k in new string[] { "SELECT", "WITH", "SHOW", "EXPLAIN", "DESCRIBE", "DESC ", "VALUES", "TABLE ", "PRAGMA" }) {
                if (s.has_prefix (k)) return true;
            }
            return false;
        }

        public static bool is_destructive (string sql) {
            string s = strip_comments (sql).strip ().up ();
            if (s.has_prefix ("DROP ") || s.has_prefix ("TRUNCATE ")) return true;
            if ((s.has_prefix ("DELETE ") || s.has_prefix ("UPDATE ")) && !s.contains (" WHERE ")) return true;
            return false;
        }
    }

    public class EditStatement {
        public string sql;
        public DbValue[] params;

        public EditStatement (string sql, owned DbValue[] params) {
            this.sql = sql;
            this.params = (owned) params;
        }

        public string preview (Engine e) {
            if (params.length == 0) return sql;
            var sb = new StringBuilder ();
            int p = 0;
            int i = 0;
            while (i < sql.length) {
                if (e.kind == EngineKind.POSTGRESQL && sql[i] == '$' && i + 1 < sql.length && sql[i + 1].isdigit ()) {
                    int j = i + 1;
                    while (j < sql.length && sql[j].isdigit ()) j++;
                    int idx = int.parse (sql.substring (i + 1, j - i - 1)) - 1;
                    sb.append (idx >= 0 && idx < params.length ? e.literal (params[idx]) : "NULL");
                    i = j;
                    continue;
                }
                if (e.kind != EngineKind.POSTGRESQL && sql[i] == '?') {
                    sb.append (p < params.length ? e.literal (params[p]) : "NULL");
                    p++;
                    i++;
                    continue;
                }
                sb.append_c (sql[i]);
                i++;
            }
            return sb.str;
        }
    }

    public class PendingChanges : Object {
        public string schema;
        public string table;
        public string[] columns;
        public string[] key_columns;
        private Gee.TreeMap<int, Gee.HashMap<int, DbValue>> edits = new Gee.TreeMap<int, Gee.HashMap<int, DbValue>> ();
        private Gee.TreeSet<int> deleted = new Gee.TreeSet<int> ();
        public Gee.ArrayList<Row> inserted = new Gee.ArrayList<Row> ();

        public signal void changed ();

        public PendingChanges (string schema, string table, string[] columns, string[] key_columns) {
            this.schema = schema;
            this.table = table;
            this.columns = columns;
            this.key_columns = key_columns;
        }

        public bool editable {
            get { return key_columns.length > 0; }
        }

        public int count () {
            int n = deleted.size + inserted.size;
            foreach (var e in edits.entries) {
                if (!deleted.contains (e.key)) n += e.value.size;
            }
            return n;
        }

        public bool is_empty () {
            return count () == 0;
        }

        public void set_value (int row, int col, DbValue original, DbValue v) {
            var m = edits[row];
            if (v.kind == original.kind && v.equals (original)) {
                if (m != null) {
                    m.unset (col);
                    if (m.size == 0) edits.unset (row);
                }
                changed ();
                return;
            }
            if (m == null) {
                m = new Gee.HashMap<int, DbValue> ();
                edits[row] = m;
            }
            m[col] = v;
            changed ();
        }

        public DbValue? edited (int row, int col) {
            var m = edits[row];
            if (m == null) return null;
            return m[col];
        }

        public bool row_edited (int row) {
            return edits.has_key (row);
        }

        public void toggle_delete (int row) {
            if (deleted.contains (row)) deleted.remove (row);
            else deleted.add (row);
            changed ();
        }

        public void mark_deleted (int row) {
            deleted.add (row);
            changed ();
        }

        public bool is_deleted (int row) {
            return deleted.contains (row);
        }

        public int add_insert () {
            var vals = new DbValue[columns.length];
            for (int i = 0; i < vals.length; i++) vals[i] = new DbValue.null ();
            inserted.add (new Row (-1, (owned) vals));
            changed ();
            return inserted.size - 1;
        }

        public void set_insert_value (int index, int col, DbValue v) {
            if (index < 0 || index >= inserted.size) return;
            inserted[index].values[col] = v;
            changed ();
        }

        public void remove_insert (int index) {
            if (index < 0 || index >= inserted.size) return;
            inserted.remove_at (index);
            changed ();
        }

        public void discard () {
            edits.clear ();
            deleted.clear ();
            inserted.clear ();
            changed ();
        }

        private int col_index (string name) {
            for (int i = 0; i < columns.length; i++) {
                if (columns[i] == name) return i;
            }
            return -1;
        }

        private string where_clause (Engine e, Row row, ref int p, Gee.ArrayList<DbValue> params) throws Error {
            string[] parts = {};
            foreach (string k in key_columns) {
                int ci = col_index (k);
                if (ci < 0) throw new RemoteError.UNSUPPORTED (_("The key column %s is not part of the loaded data.").printf (k));
                var v = row.get (ci);
                if (v.is_null) {
                    parts += "%s IS NULL".printf (e.quote_ident (k));
                } else {
                    parts += "%s = %s".printf (e.quote_ident (k), e.placeholder (++p));
                    params.add (v);
                }
            }
            return string.joinv (" AND ", parts);
        }

        public Gee.ArrayList<EditStatement> statements (Engine e, Gee.List<Row> rows) throws Error {
            if (!editable) throw new RemoteError.UNSUPPORTED (_("%s has no primary key, so rows cannot be changed safely.").printf (table));
            var list = new Gee.ArrayList<EditStatement> ();
            string target = e.qualified (schema, table);
            foreach (int r in deleted) {
                if (r < 0 || r >= rows.size) continue;
                int p = 0;
                var params = new Gee.ArrayList<DbValue> ();
                string w = where_clause (e, rows[r], ref p, params);
                list.add (new EditStatement ("DELETE FROM %s WHERE %s".printf (target, w), params.to_array ()));
            }
            foreach (var entry in edits.entries) {
                int r = entry.key;
                if (deleted.contains (r) || r < 0 || r >= rows.size) continue;
                int p = 0;
                var params = new Gee.ArrayList<DbValue> ();
                string[] sets = {};
                var cols = new Gee.ArrayList<int> ();
                cols.add_all (entry.value.keys);
                cols.sort ((a, b) => a - b);
                foreach (int c in cols) {
                    sets += "%s = %s".printf (e.quote_ident (columns[c]), e.placeholder (++p));
                    params.add (entry.value[c]);
                }
                string w = where_clause (e, rows[r], ref p, params);
                list.add (new EditStatement ("UPDATE %s SET %s WHERE %s".printf (target, string.joinv (", ", sets), w), params.to_array ()));
            }
            foreach (var ins in inserted) {
                unowned DbValue[] vals = ins.values;
                string[] names = {};
                string[] marks = {};
                DbValue[] params = {};
                int p = 0;
                for (int c = 0; c < vals.length; c++) {
                    if (vals[c].is_null) continue;
                    names += e.quote_ident (columns[c]);
                    marks += e.placeholder (++p);
                    params += vals[c];
                }
                string sql;
                if (names.length == 0) sql = e.kind == EngineKind.MYSQL ? "INSERT INTO %s () VALUES ()".printf (target) : "INSERT INTO %s DEFAULT VALUES".printf (target);
                else sql = "INSERT INTO %s (%s) VALUES (%s)".printf (target, string.joinv (", ", names), string.joinv (", ", marks));
                list.add (new EditStatement (sql, (owned) params));
            }
            return list;
        }

        public static string short_value (DbValue v) {
            if (v.is_null) return "NULL";
            if (v.kind == ValueKind.BLOB) return _("binary data");
            string t = v.to_string ().replace ("\n", " ");
            if (t.char_count () > 40) t = t.substring (0, t.index_of_nth_char (40)) + "...";
            if (v.kind == ValueKind.TEXT) return "'%s'".printf (t);
            return t;
        }

        private string describe_key (Row row) {
            string[] parts = {};
            foreach (string k in key_columns) {
                int ci = col_index (k);
                parts += "%s %s".printf (k, ci >= 0 ? short_value (row.get (ci)) : "?");
            }
            return string.joinv (", ", parts);
        }

        public Gee.ArrayList<int> touched_rows () {
            var list = new Gee.ArrayList<int> ();
            foreach (int r in deleted) list.add (r);
            foreach (int r in edits.keys) if (!deleted.contains (r)) list.add (r);
            return list;
        }

        public async void verify_unchanged (Engine e, Gee.List<Row> rows, Cancellable? cancellable = null) throws Error {
            string[] sel = {};
            foreach (string c in columns) sel += e.quote_ident (c);
            string lock_clause = e.kind == EngineKind.SQLITE ? "" : " FOR UPDATE";
            foreach (int r in touched_rows ()) {
                if (r < 0 || r >= rows.size) continue;
                var row = rows[r];
                int p = 0;
                var params = new Gee.ArrayList<DbValue> ();
                string w = where_clause (e, row, ref p, params);
                var res = yield e.execute ("SELECT %s FROM %s WHERE %s%s".printf (string.joinv (", ", sel), e.qualified (schema, table), w, lock_clause), params.to_array (), cancellable);
                if (res.rows.size == 0) {
                    throw new RemoteError.CONFLICT (_("The row with %s was deleted on the server after you loaded it. Nothing was saved. Reload the data and apply your changes again.").printf (describe_key (row)));
                }
                var now = res.rows[0];
                for (int c = 0; c < columns.length; c++) {
                    var before = row.get (c);
                    var current = now.get (c);
                    if (!before.equals (current)) {
                        throw new RemoteError.CONFLICT (_("Someone changed the row with %s on the server after you loaded it: %s is now %s, you loaded %s. Nothing was saved. Reload the data and apply your changes again.").printf (describe_key (row), columns[c], short_value (current), short_value (before)));
                    }
                }
            }
        }

        public async int apply (Engine e, Gee.List<Row> rows, Cancellable? cancellable = null) throws Error {
            var list = statements (e, rows);
            if (list.size == 0) return 0;
            yield e.begin_transaction (cancellable);
            try {
                yield verify_unchanged (e, rows, cancellable);
                foreach (var st in list) {
                    var r = yield e.execute (st.sql, st.params, cancellable);
                    if (r.affected == 0 && !st.sql.has_prefix ("INSERT")) throw new RemoteError.CONFLICT (_("A row changed or disappeared on the server before it could be saved. Reload the data and try again."));
                    if (r.affected > 1 && !st.sql.has_prefix ("INSERT")) throw new RemoteError.SERVER (_("The change would affect %lld rows instead of one, so it was not saved.").printf (r.affected));
                }
                yield e.commit (cancellable);
            } catch (Error err) {
                try {
                    yield e.rollback (null);
                } catch (Error ignored) {
                }
                throw err;
            }
            int n = list.size;
            discard ();
            return n;
        }
    }

    public enum ExportFormat {
        CSV,
        JSON,
        SQL;

        public string extension () {
            switch (this) {
                case JSON: return "json";
                case SQL: return "sql";
                default: return "csv";
            }
        }

        public string label () {
            switch (this) {
                case JSON: return "JSON";
                case SQL: return "SQL";
                default: return "CSV";
            }
        }
    }

    public class ResultWriter {
        private OutputStream stream;
        private ExportFormat format;
        private Engine? engine;
        private string target;
        private string[] columns;
        private int written;

        public ResultWriter (OutputStream stream, ExportFormat format, string[] columns, Engine? engine, string target) {
            this.stream = stream;
            this.format = format;
            this.columns = columns;
            this.engine = engine;
            this.target = target;
        }

        private void put (string s) throws Error {
            size_t w;
            stream.write_all (s.data, out w);
        }

        public void begin () throws Error {
            if (format == ExportFormat.CSV) {
                string[] q = {};
                foreach (string c in columns) q += Csv.quote (c, ',');
                put (string.joinv (",", q) + "\r\n");
            } else if (format == ExportFormat.JSON) {
                put ("[");
            }
        }

        public static string json_value (DbValue v) {
            switch (v.kind) {
                case ValueKind.NULL: return "null";
                case ValueKind.INTEGER: return v.int_value.to_string ();
                case ValueKind.REAL:
                    if (v.real_value.is_nan () || v.real_value.is_infinity () != 0) return "null";
                    return DbValue.format_real (v.real_value);
                case ValueKind.BLOB: return json_string (Base64.encode (v.blob_value.get_data ()));
                default: return json_string (v.text_value);
            }
        }

        public static string json_string (string s) {
            var sb = new StringBuilder ("\"");
            unichar c;
            int i = 0;
            while (s.get_next_char (ref i, out c)) {
                switch (c) {
                    case '"': sb.append ("\\\""); break;
                    case '\\': sb.append ("\\\\"); break;
                    case '\n': sb.append ("\\n"); break;
                    case '\r': sb.append ("\\r"); break;
                    case '\t': sb.append ("\\t"); break;
                    default:
                        if (c < 0x20) sb.append ("\\u%04x".printf ((uint) c));
                        else sb.append_unichar (c);
                        break;
                }
            }
            sb.append_c ('"');
            return sb.str;
        }

        public void write_row (Row row) throws Error {
            var sb = new StringBuilder ();
            switch (format) {
                case ExportFormat.CSV:
                    for (int i = 0; i < columns.length; i++) {
                        if (i > 0) sb.append_c (',');
                        var v = row.get (i);
                        if (!v.is_null) sb.append (Csv.quote (v.kind == ValueKind.BLOB ? Base64.encode (v.blob_value.get_data ()) : v.to_string (), ','));
                    }
                    sb.append ("\r\n");
                    break;
                case ExportFormat.JSON:
                    sb.append (written > 0 ? ",\n  {" : "\n  {");
                    for (int i = 0; i < columns.length; i++) {
                        if (i > 0) sb.append (", ");
                        sb.append (json_string (columns[i])).append (": ").append (json_value (row.get (i)));
                    }
                    sb.append ("}");
                    break;
                case ExportFormat.SQL:
                    string[] names = {};
                    string[] vals = {};
                    for (int i = 0; i < columns.length; i++) {
                        names += engine != null ? engine.quote_ident (columns[i]) : Sql.quote_ident (columns[i]);
                        vals += engine != null ? engine.literal (row.get (i)) : row.get (i).sql_literal ();
                    }
                    sb.append ("INSERT INTO %s (%s) VALUES (%s);\n".printf (target, string.joinv (", ", names), string.joinv (", ", vals)));
                    break;
            }
            put (sb.str);
            written++;
        }

        public void finish () throws Error {
            if (format == ExportFormat.JSON) put (written > 0 ? "\n]\n" : "]\n");
            stream.close ();
        }

        public int rows_written () {
            return written;
        }

        public static string[] names_of (Gee.List<ColumnMeta> cols) {
            string[] n = {};
            foreach (var c in cols) n += c.name;
            return n;
        }
    }

    public class RemoteTransfer {
        public delegate void Progress (int64 rows);

        public static async int64 export_query (Engine e, string sql, File dest, ExportFormat format, string target, Cancellable? cancellable, Progress? progress = null) throws Error {
            var cursor = yield e.open_cursor (sql, null, cancellable);
            var stream = dest.replace (null, false, FileCreateFlags.REPLACE_DESTINATION, cancellable);
            var w = new ResultWriter (stream, format, ResultWriter.names_of (cursor.columns), e, target);
            w.begin ();
            int64 total = 0;
            try {
                while (!cursor.done) {
                    var rows = yield cursor.fetch (2000, cancellable);
                    foreach (var r in rows) w.write_row (r);
                    total += rows.size;
                    if (progress != null) progress (total);
                    if (rows.size == 0) break;
                }
            } finally {
                try {
                    yield cursor.close_async ();
                } catch (Error ignored) {
                }
            }
            w.finish ();
            return total;
        }

        public static async int64 export_table (Engine e, string schema, string table, File dest, ExportFormat format, Cancellable? cancellable, Progress? progress = null) throws Error {
            string target = e.qualified (schema, table);
            if (format == ExportFormat.SQL) {
                var info = yield e.describe_table (schema, table, cancellable);
                var tmp = File.new_for_path (dest.get_path () + ".part");
                int64 n = yield export_query (e, "SELECT * FROM " + target, tmp, format, target, cancellable, progress);
                var stream = dest.replace (null, false, FileCreateFlags.REPLACE_DESTINATION, cancellable);
                size_t w;
                stream.write_all ((terminated (e.create_table_sql (info)) + "\n\n").data, out w);
                var input = tmp.read (cancellable);
                stream.splice (input, OutputStreamSpliceFlags.CLOSE_SOURCE | OutputStreamSpliceFlags.CLOSE_TARGET, cancellable);
                tmp.delete (null);
                return n;
            }
            return yield export_query (e, "SELECT * FROM " + target, dest, format, target, cancellable, progress);
        }

        public static async int64 dump_schema (Engine e, string schema, File dest, bool with_data, Cancellable? cancellable, Progress? progress = null) throws Error {
            var objects = yield e.list_objects (schema, cancellable);
            var stream = dest.replace (null, false, FileCreateFlags.REPLACE_DESTINATION, cancellable);
            size_t w;
            int64 total = 0;
            string ver = e.server_version;
            if (!ver.has_prefix (e.kind.label ())) ver = "%s %s".printf (e.kind.label (), ver);
            string header = "-- %s\n-- %s\n\n".printf (ver, schema);
            if (e.kind == EngineKind.SQLITE) header += "BEGIN TRANSACTION;\n\n";
            stream.write_all (header.data, out w);
            var infos = new Gee.ArrayList<TableInfo> ();
            foreach (var o in objects) {
                if (o.kind != ObjectKind.TABLE) continue;
                infos.add (yield e.describe_table (schema, o.name, cancellable));
            }
            foreach (var info in dependency_order (infos)) {
                stream.write_all ((terminated (e.create_table_sql (info)) + "\n\n").data, out w);
                if (!with_data) continue;
                string target = e.qualified (schema, info.name);
                var cursor = yield e.open_cursor ("SELECT * FROM " + target, null, cancellable);
                var names = ResultWriter.names_of (cursor.columns);
                var mem = new MemoryOutputStream.resizable ();
                var rw = new ResultWriter (mem, ExportFormat.SQL, names, e, target);
                while (!cursor.done) {
                    var rows = yield cursor.fetch (2000, cancellable);
                    if (rows.size == 0) break;
                    foreach (var r in rows) rw.write_row (r);
                    total += rows.size;
                    if (progress != null) progress (total);
                    mem.close ();
                    stream.write_all (mem.steal_as_bytes ().get_data (), out w);
                    mem = new MemoryOutputStream.resizable ();
                    rw = new ResultWriter (mem, ExportFormat.SQL, names, e, target);
                }
                stream.write_all ("\n".data, out w);
            }
            foreach (var o in objects) {
                if (o.kind != ObjectKind.VIEW && o.kind != ObjectKind.TRIGGER && o.kind != ObjectKind.FUNCTION && o.kind != ObjectKind.PROCEDURE) continue;
                string def = yield e.object_definition (o, cancellable);
                if (def.strip () == "") continue;
                string d = def.strip ();
                if (!d.has_suffix (";")) d += ";";
                stream.write_all ((d + "\n\n").data, out w);
            }
            if (e.kind == EngineKind.SQLITE) stream.write_all ("COMMIT;\n".data, out w);
            stream.close (cancellable);
            return total;
        }

        public static string terminated (string sql) {
            string s = sql.strip ();
            return s.has_suffix (";") ? s : s + ";";
        }

        public static Gee.ArrayList<TableInfo> dependency_order (Gee.List<TableInfo> tables) {
            var ordered = new Gee.ArrayList<TableInfo> ();
            var placed = new Gee.HashSet<string> ();
            var names = new Gee.HashSet<string> ();
            foreach (var t in tables) names.add (t.name);
            bool progress = true;
            while (ordered.size < tables.size && progress) {
                progress = false;
                foreach (var t in tables) {
                    if (placed.contains (t.name)) continue;
                    bool ready = true;
                    foreach (var fk in t.foreign_keys) {
                        if (fk.ref_table != t.name && names.contains (fk.ref_table) && !placed.contains (fk.ref_table)) ready = false;
                    }
                    if (!ready) continue;
                    ordered.add (t);
                    placed.add (t.name);
                    progress = true;
                }
            }
            foreach (var t in tables) {
                if (!placed.contains (t.name)) ordered.add (t);
            }
            return ordered;
        }

        public static async int64 import_rows (Engine e, string schema, string table, DataTable data, owned string[] target_columns, Cancellable? cancellable, Progress? progress = null) throws Error {
            string[] names = {};
            int[] src = {};
            for (int i = 0; i < target_columns.length && i < data.columns.length; i++) {
                if (target_columns[i] == "") continue;
                names += target_columns[i];
                src += i;
            }
            if (names.length == 0) throw new RemoteError.UNSUPPORTED (_("Choose at least one column to import."));
            bool[] use_default = new bool[names.length];
            try {
                var info = yield e.describe_table (schema, table, cancellable);
                for (int k = 0; k < names.length; k++) {
                    var c = info.find (names[k]);
                    use_default[k] = c != null && (c.auto_increment || (!c.nullable && c.default_expr != ""));
                }
            } catch (Error err) {
                if (Engines.is_cancelled (err)) throw err;
            }
            string target = e.qualified (schema, table);
            int64 n = 0;
            yield e.begin_transaction (cancellable);
            try {
                foreach (var row in data.rows) {
                    DbValue[] p = {};
                    string[] cols = {};
                    string[] marks = {};
                    for (int k = 0; k < src.length; k++) {
                        var v = row.get (src[k]);
                        bool empty = v.is_null || (v.kind == ValueKind.TEXT && v.text_value == "");
                        if (empty && use_default[k]) continue;
                        if (empty) v = new DbValue.null ();
                        cols += e.quote_ident (names[k]);
                        p += v;
                        marks += e.placeholder (p.length);
                    }
                    string sql;
                    if (cols.length == 0) sql = e.kind == EngineKind.MYSQL ? "INSERT INTO %s () VALUES ()".printf (target) : "INSERT INTO %s DEFAULT VALUES".printf (target);
                    else sql = "INSERT INTO %s (%s) VALUES (%s)".printf (target, string.joinv (", ", cols), string.joinv (", ", marks));
                    yield e.execute (sql, p, cancellable);
                    n++;
                    if (progress != null && n % 500 == 0) progress (n);
                }
                yield e.commit (cancellable);
            } catch (Error err) {
                try {
                    yield e.rollback (null);
                } catch (Error ignored) {
                }
                throw new RemoteError.SERVER (_("Row %lld could not be imported: %s").printf (n + 1, err.message));
            }
            if (progress != null) progress (n);
            return n;
        }

        public static async int64 run_script (Engine e, string sql, Cancellable? cancellable = null) throws Error {
            int64 n = 0;
            var list = SqlScript.split (sql, e.kind);
            bool wrap = e.kind == EngineKind.SQLITE && list.size > 1;
            foreach (var st in list) {
                string head = SqlScript.strip_comments (st.text).strip ().up ();
                if (head.has_prefix ("BEGIN") || head.has_prefix ("COMMIT") || head.has_prefix ("END") || head.has_prefix ("ROLLBACK") || head.has_prefix ("PRAGMA") || head.has_prefix ("VACUUM") || head.has_prefix ("SAVEPOINT")) wrap = false;
            }
            if (wrap) yield e.begin_transaction (cancellable);
            try {
                foreach (var st in list) {
                    yield e.execute (st.text, null, cancellable);
                    n++;
                }
                if (wrap) yield e.commit (cancellable);
            } catch (Error err) {
                if (wrap) {
                    try {
                        yield e.rollback (null);
                    } catch (Error ignored) {
                    }
                }
                throw err;
            }
            return n;
        }
    }

    public class ClientStore {
        public static string config_dir () {
            string? over = Environment.get_variable ("SDB_CONFIG_DIR");
            if (over != null && over != "") return over;
            return Path.build_filename (Environment.get_user_config_dir (), "singularity-database");
        }

        public static string path (string name) {
            return Path.build_filename (config_dir (), name);
        }

        public static Json.Node? load (string name) {
            try {
                var parser = new Json.Parser ();
                parser.load_from_file (path (name));
                return parser.get_root ()?.copy ();
            } catch (Error e) {
                return null;
            }
        }

        public static void save (string name, Json.Node root) throws Error {
            DirUtils.create_with_parents (config_dir (), 0700);
            var gen = new Json.Generator ();
            gen.pretty = true;
            gen.indent = 2;
            gen.set_root (root);
            string data = gen.to_data (null);
            FileUtils.set_contents (path (name), data);
            FileUtils.chmod (path (name), 0600);
        }
    }

    public class ConnectionStore : Object {
        public Gee.ArrayList<ConnectionConfig> items = new Gee.ArrayList<ConnectionConfig> ();

        public signal void changed ();

        private static ConnectionStore? instance;

        public static ConnectionStore get_default () {
            if (instance == null) {
                instance = new ConnectionStore ();
                instance.load ();
            }
            return instance;
        }

        public void load () {
            items.clear ();
            var root = ClientStore.load ("connections.json");
            if (root == null || root.get_node_type () != Json.NodeType.ARRAY) return;
            foreach (var node in root.get_array ().get_elements ()) {
                if (node.get_node_type () != Json.NodeType.OBJECT) continue;
                items.add (from_json (node.get_object ()));
            }
        }

        private static string s (Json.Object o, string k, string d = "") {
            if (!o.has_member (k)) return d;
            string? v = o.get_string_member_with_default (k, d);
            if (v == null) return d;
            return v;
        }

        private static int i (Json.Object o, string k, int d = 0) {
            return o.has_member (k) ? (int) o.get_int_member_with_default (k, d) : d;
        }

        private static bool b (Json.Object o, string k) {
            return o.has_member (k) && o.get_boolean_member_with_default (k, false);
        }

        public static ConnectionConfig from_json (Json.Object o) {
            var c = new ConnectionConfig ();
            c.id = s (o, "id");
            c.name = s (o, "name");
            c.kind = EngineKind.from_id (s (o, "kind", "postgresql"));
            c.host = s (o, "host", "127.0.0.1");
            c.port = i (o, "port");
            c.user = s (o, "user");
            c.database = s (o, "database");
            c.socket_path = s (o, "socket");
            c.file_path = s (o, "file");
            c.ssl_mode = SslMode.from_id (s (o, "sslmode", "prefer"));
            c.ssl_ca_file = s (o, "sslrootcert");
            c.ssh_enabled = b (o, "ssh");
            c.ssh_host = s (o, "ssh_host");
            c.ssh_port = i (o, "ssh_port", 22);
            c.ssh_user = s (o, "ssh_user");
            c.ssh_key_file = s (o, "ssh_key");
            c.ssh_use_password = b (o, "ssh_password");
            c.color = s (o, "color");
            c.read_only = b (o, "read_only");
            c.connect_timeout = i (o, "timeout", 10);
            if (c.id == "") c.id = Uuid.string_random ();
            return c;
        }

        public static Json.Node to_json (ConnectionConfig c) {
            var bld = new Json.Builder ();
            bld.begin_object ();
            bld.set_member_name ("id").add_string_value (c.id);
            bld.set_member_name ("name").add_string_value (c.name);
            bld.set_member_name ("kind").add_string_value (c.kind.id ());
            bld.set_member_name ("host").add_string_value (c.host);
            bld.set_member_name ("port").add_int_value (c.port);
            bld.set_member_name ("user").add_string_value (c.user);
            bld.set_member_name ("database").add_string_value (c.database);
            bld.set_member_name ("socket").add_string_value (c.socket_path);
            bld.set_member_name ("file").add_string_value (c.file_path);
            bld.set_member_name ("sslmode").add_string_value (c.ssl_mode.id ());
            bld.set_member_name ("sslrootcert").add_string_value (c.ssl_ca_file);
            bld.set_member_name ("ssh").add_boolean_value (c.ssh_enabled);
            bld.set_member_name ("ssh_host").add_string_value (c.ssh_host);
            bld.set_member_name ("ssh_port").add_int_value (c.ssh_port);
            bld.set_member_name ("ssh_user").add_string_value (c.ssh_user);
            bld.set_member_name ("ssh_key").add_string_value (c.ssh_key_file);
            bld.set_member_name ("ssh_password").add_boolean_value (c.ssh_use_password);
            bld.set_member_name ("color").add_string_value (c.color);
            bld.set_member_name ("read_only").add_boolean_value (c.read_only);
            bld.set_member_name ("timeout").add_int_value (c.connect_timeout);
            bld.end_object ();
            return bld.get_root ();
        }

        public void save () throws Error {
            var arr = new Json.Array ();
            foreach (var c in items) arr.add_element (to_json (c));
            var root = new Json.Node (Json.NodeType.ARRAY);
            root.set_array (arr);
            ClientStore.save ("connections.json", root);
            changed ();
        }

        public ConnectionConfig? find (string id) {
            foreach (var c in items) if (c.id == id) return c;
            return null;
        }

        public void put (ConnectionConfig c) throws Error {
            if (c.id == "") c.id = Uuid.string_random ();
            for (int k = 0; k < items.size; k++) {
                if (items[k].id == c.id) {
                    items[k] = c;
                    save ();
                    return;
                }
            }
            items.add (c);
            save ();
        }

        public void remove (string id) throws Error {
            for (int k = 0; k < items.size; k++) {
                if (items[k].id == id) {
                    items.remove_at (k);
                    break;
                }
            }
            save ();
        }
    }

    public class HistoryEntry {
        public string sql;
        public int64 time;
        public double elapsed_ms;
        public bool ok;
        public string database;

        public HistoryEntry (string sql, int64 time, double elapsed_ms, bool ok, string database) {
            this.sql = sql;
            this.time = time;
            this.elapsed_ms = elapsed_ms;
            this.ok = ok;
            this.database = database;
        }
    }

    public class QueryHistory : Object {
        public const int LIMIT = 500;
        public string connection_id;
        public Gee.ArrayList<HistoryEntry> entries = new Gee.ArrayList<HistoryEntry> ();

        public QueryHistory (string connection_id) {
            this.connection_id = connection_id;
            var root = ClientStore.load (file_name ());
            if (root == null || root.get_node_type () != Json.NodeType.ARRAY) return;
            foreach (var n in root.get_array ().get_elements ()) {
                var o = n.get_object ();
                if (o == null) continue;
                entries.add (new HistoryEntry (o.get_string_member_with_default ("sql", ""), o.get_int_member_with_default ("time", 0),
                    o.get_double_member_with_default ("ms", 0), o.get_boolean_member_with_default ("ok", true), o.get_string_member_with_default ("db", "")));
            }
        }

        private string file_name () {
            string safe = connection_id.replace ("/", "_").replace ("..", "_");
            return "history-%s.json".printf (safe);
        }

        public void add (string sql, double elapsed_ms, bool ok, string database) {
            string s = sql.strip ();
            if (s == "") return;
            if (entries.size > 0 && entries[0].sql == s) entries.remove_at (0);
            entries.insert (0, new HistoryEntry (s, get_real_time () / 1000000, elapsed_ms, ok, database));
            while (entries.size > LIMIT) entries.remove_at (entries.size - 1);
            save ();
        }

        public void clear () {
            entries.clear ();
            save ();
        }

        private void save () {
            var arr = new Json.Array ();
            foreach (var e in entries) {
                var o = new Json.Object ();
                o.set_string_member ("sql", e.sql);
                o.set_int_member ("time", e.time);
                o.set_double_member ("ms", e.elapsed_ms);
                o.set_boolean_member ("ok", e.ok);
                o.set_string_member ("db", e.database);
                arr.add_object_element (o);
            }
            var root = new Json.Node (Json.NodeType.ARRAY);
            root.set_array (arr);
            try {
                ClientStore.save (file_name (), root);
            } catch (Error e) {
                warning ("history: %s", e.message);
            }
        }
    }

    public class Snippet {
        public string name;
        public string sql;

        public Snippet (string name, string sql) {
            this.name = name;
            this.sql = sql;
        }
    }

    public class SnippetStore : Object {
        public Gee.ArrayList<Snippet> items = new Gee.ArrayList<Snippet> ();

        public signal void changed ();

        private static SnippetStore? instance;

        public static SnippetStore get_default () {
            if (instance == null) instance = new SnippetStore ();
            return instance;
        }

        public SnippetStore () {
            var root = ClientStore.load ("snippets.json");
            if (root == null || root.get_node_type () != Json.NodeType.ARRAY) return;
            foreach (var n in root.get_array ().get_elements ()) {
                var o = n.get_object ();
                if (o == null) continue;
                items.add (new Snippet (o.get_string_member_with_default ("name", ""), o.get_string_member_with_default ("sql", "")));
            }
        }

        public void put (string name, string sql) throws Error {
            foreach (var s in items) {
                if (s.name == name) {
                    s.sql = sql;
                    save ();
                    return;
                }
            }
            items.add (new Snippet (name, sql));
            items.sort ((a, b) => a.name.collate (b.name));
            save ();
        }

        public void remove (string name) throws Error {
            for (int i = 0; i < items.size; i++) {
                if (items[i].name == name) {
                    items.remove_at (i);
                    break;
                }
            }
            save ();
        }

        private void save () throws Error {
            var arr = new Json.Array ();
            foreach (var s in items) {
                var o = new Json.Object ();
                o.set_string_member ("name", s.name);
                o.set_string_member ("sql", s.sql);
                arr.add_object_element (o);
            }
            var root = new Json.Node (Json.NodeType.ARRAY);
            root.set_array (arr);
            ClientStore.save ("snippets.json", root);
            changed ();
        }
    }

    public class SshTunnel : Object {
        public const string ASKPASS_ENV = "SINGULARITY_DATABASE_ASKPASS";
        public int local_port { get; private set; }
        public string ssh_binary = "ssh";
        public string askpass_program = "";
        public string[] extra_options = {};
        private Subprocess? process;
        private string stderr_text = "";

        public static bool handle_askpass () {
            string? secret = Environment.get_variable (ASKPASS_ENV);
            if (secret == null) return false;
            print ("%s\n", secret);
            return true;
        }

        public static int free_port () throws Error {
            var sock = new Socket (SocketFamily.IPV4, SocketType.STREAM, SocketProtocol.TCP);
            sock.bind (new InetSocketAddress (new InetAddress.loopback (SocketFamily.IPV4), 0), true);
            var addr = (InetSocketAddress) sock.get_local_address ();
            int port = (int) addr.port;
            sock.close ();
            return port;
        }

        public string[] command (ConnectionConfig c, int port) {
            string target = c.socket_path != "" && c.kind != EngineKind.SQLITE ? "" : "%s:%d".printf (c.host == "" ? "127.0.0.1" : c.host, c.effective_port ());
            string remote_socket = c.socket_path;
            if (c.kind == EngineKind.POSTGRESQL && remote_socket != "" && !remote_socket.has_suffix (".s.PGSQL.%d".printf (c.effective_port ()))) remote_socket = Path.build_filename (remote_socket, ".s.PGSQL.%d".printf (c.effective_port ()));
            string[] argv = { ssh_binary, "-N", "-T",
                "-o", "ExitOnForwardFailure=yes",
                "-o", "ServerAliveInterval=30",
                "-o", "ConnectTimeout=%d".printf (c.connect_timeout > 0 ? c.connect_timeout : 10),
                "-o", "StrictHostKeyChecking=accept-new",
                "-o", c.ssh_use_password ? "BatchMode=no" : "BatchMode=yes",
                "-p", c.ssh_port.to_string () };
            if (c.ssh_use_password) {
                argv += "-o";
                argv += "PreferredAuthentications=password,keyboard-interactive";
                argv += "-o";
                argv += "PubkeyAuthentication=no";
                argv += "-o";
                argv += "NumberOfPasswordPrompts=1";
            }
            if (c.ssh_key_file != "") {
                argv += "-i";
                argv += c.ssh_key_file;
                argv += "-o";
                argv += "IdentitiesOnly=yes";
            }
            foreach (string o in extra_options) argv += o;
            argv += "-L";
            argv += target != "" ? "127.0.0.1:%d:%s".printf (port, target) : "127.0.0.1:%d:%s".printf (port, remote_socket);
            argv += (c.ssh_user != "" ? c.ssh_user + "@" : "") + c.ssh_host;
            return argv;
        }

        public async void start (ConnectionConfig c, string? password, Cancellable? cancellable = null) throws Error {
            if (c.ssh_host == "") throw new RemoteError.CONNECT (_("Enter the SSH server."));
            local_port = free_port ();
            var launcher = new SubprocessLauncher (SubprocessFlags.STDIN_PIPE | SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_PIPE);
            if (c.ssh_use_password) {
                string helper = askpass_program;
                if (helper == "") helper = FileUtils.read_link ("/proc/self/exe");
                launcher.setenv ("SSH_ASKPASS", helper, true);
                launcher.setenv ("SSH_ASKPASS_REQUIRE", "force", true);
                launcher.setenv (ASKPASS_ENV, password ?? "", true);
                if (Environment.get_variable ("DISPLAY") == null) launcher.setenv ("DISPLAY", ":0", true);
            } else {
                launcher.unsetenv ("SSH_ASKPASS");
                launcher.unsetenv (ASKPASS_ENV);
            }
            launcher.set_child_setup (() => {
                sdb_prctl (1, 15, 0, 0, 0);
            });
            process = launcher.spawnv (command (c, local_port));
            last_pid = process.get_identifier () ?? "";
            read_stderr.begin ();
            int64 deadline = get_monotonic_time () + (int64) (c.connect_timeout > 0 ? c.connect_timeout + 5 : 15) * 1000000;
            while (true) {
                if (cancellable != null && cancellable.is_cancelled ()) {
                    stop ();
                    throw new RemoteError.CANCELLED (_("Connecting was cancelled."));
                }
                if (process.get_identifier () == null) {
                    yield wait_stderr ();
                    throw new RemoteError.CONNECT (_("The SSH tunnel could not be opened: %s").printf (ssh_error ()));
                }
                if (yield port_open (local_port)) return;
                if (get_monotonic_time () > deadline) {
                    stop ();
                    throw new RemoteError.CONNECT (_("The SSH tunnel did not open in time: %s").printf (ssh_error ()));
                }
                yield sleep (100);
            }
        }

        private string ssh_error () {
            string t = stderr_text.strip ();
            string[] lines = {};
            foreach (string l in t.split ("\n")) {
                string s = l.strip ();
                if (s == "" || s.has_prefix ("Warning: Permanently added")) continue;
                lines += s;
            }
            if (lines.length == 0) return _("ssh exited without a message");
            return string.joinv (" ", lines);
        }

        private async void read_stderr () {
            if (process == null) return;
            var input = new DataInputStream (process.get_stderr_pipe ());
            try {
                string? line;
                while ((line = yield input.read_line_async ()) != null) stderr_text += line + "\n";
            } catch (Error e) {
            }
        }

        private async void wait_stderr () {
            for (int k = 0; k < 20; k++) {
                if (stderr_text != "") return;
                yield sleep (25);
            }
        }

        private static async void sleep (uint ms) {
            Timeout.add (ms, () => {
                sleep.callback ();
                return false;
            });
            yield;
        }

        private static async bool port_open (int port) {
            try {
                var client = new SocketClient ();
                client.timeout = 1;
                var conn = yield client.connect_async (new InetSocketAddress (new InetAddress.loopback (SocketFamily.IPV4), (uint16) port));
                yield conn.close_async ();
                return true;
            } catch (Error e) {
                return false;
            }
        }

        public bool running {
            get { return process != null && process.get_identifier () != null; }
        }

        public string last_pid { get; private set; default = ""; }

        public void stop () {
            if (process != null && process.get_identifier () != null) process.send_signal (15);
            process = null;
        }
    }

    public class ClientSession : Object {
        public ConnectionConfig config;
        public Engine? engine;
        public SshTunnel? tunnel;
        public QueryHistory history;
        public string ssh_binary = "";
        public string[] ssh_extra_options = {};

        public ClientSession (ConnectionConfig config) {
            this.config = config;
            history = new QueryHistory (config.id != "" ? config.id : "adhoc");
        }

        public async void connect (string? password, string? ssh_password, Cancellable? cancellable = null) throws Error {
            var effective = config.copy ();
            if (config.ssh_enabled && config.kind != EngineKind.SQLITE) {
                var t = new SshTunnel ();
                if (ssh_binary != "") t.ssh_binary = ssh_binary;
                t.extra_options = ssh_extra_options;
                try {
                    yield t.start (config, ssh_password, cancellable);
                } catch (Error e) {
                    t.stop ();
                    throw e;
                }
                tunnel = t;
                if (effective.tls_server_name == "") {
                    if (config.host == "127.0.0.1" || config.host == "") effective.tls_server_name = config.ssh_host;
                    else effective.tls_server_name = config.host;
                }
                effective.host = "127.0.0.1";
                effective.port = t.local_port;
                effective.socket_path = "";
            }
            engine = Engines.create (effective);
            try {
                yield engine.open (password, cancellable);
            } catch (Error e) {
                bool through_tunnel = tunnel != null;
                if (tunnel != null) tunnel.stop ();
                tunnel = null;
                engine = null;
                if (through_tunnel && e is IOError && !(e is IOError.CANCELLED)) throw new RemoteError.CONNECT (_("The database server could not be reached through the SSH tunnel: %s").printf (e.message));
                throw e;
            }
        }

        public async void disconnect () {
            if (engine != null) yield engine.close_async ();
            engine = null;
            if (tunnel != null) tunnel.stop ();
            tunnel = null;
        }

        public static async string test (ConnectionConfig config, string? password, string? ssh_password, Cancellable? cancellable = null) throws Error {
            var s = new ClientSession (config);
            var timer = new Timer ();
            yield s.connect (password, ssh_password, cancellable);
            string version = s.engine.server_version;
            string db = s.engine.current_database;
            bool tls = false;
            var pg = s.engine as PgEngine;
            if (pg != null) tls = pg.tls_active;
            var my = s.engine as MysqlEngine;
            if (my != null) tls = my.tls_active;
            yield s.disconnect ();
            string where = db != "" ? _("database %s").printf (db) : "";
            string secure = config.kind == EngineKind.SQLITE ? "" : (tls ? _("encrypted") : _("not encrypted"));
            string[] bits = { version };
            if (where != "") bits += where;
            if (secure != "") bits += secure;
            if (config.ssh_enabled) bits += _("through SSH");
            bits += _("%.0f ms").printf (timer.elapsed () * 1000);
            return string.joinv (", ", bits);
        }
    }
}
