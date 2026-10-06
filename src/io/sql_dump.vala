namespace Singularity.Apps.Database {

    public enum SqlDialect {
        SQLITE,
        POSTGRESQL,
        MYSQL;

        public string label () {
            switch (this) {
                case POSTGRESQL: return "PostgreSQL";
                case MYSQL: return "MySQL / MariaDB";
                default: return "SQLite";
            }
        }
    }

    public class SqlDump {
        public static string dump (Database db, SqlDialect dialect = SqlDialect.SQLITE) throws Error {
            if (dialect != SqlDialect.SQLITE) return portable (db, dialect);
            var sb = new StringBuilder ();
            sb.append ("PRAGMA foreign_keys=OFF;\nBEGIN TRANSACTION;\n");
            var objects = db.query ("SELECT type, name, sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY CASE type WHEN 'table' THEN 0 WHEN 'index' THEN 1 WHEN 'view' THEN 2 ELSE 3 END, rowid");
            foreach (var r in objects.rows) {
                string type = r.get (0).to_string ();
                string name = r.get (1).to_string ();
                string sql = r.get (2).to_string ();
                if (type != "table") continue;
                if (name == META_TABLE) {
                    sb.append ("CREATE TABLE IF NOT EXISTS %s (key TEXT PRIMARY KEY, value TEXT);\n".printf (META_TABLE));
                    var meta = db.query ("SELECT key, value FROM %s ORDER BY key".printf (META_TABLE));
                    foreach (var m in meta.rows) sb.append ("INSERT OR REPLACE INTO %s VALUES(%s,%s);\n".printf (META_TABLE, m.get (0).sql_literal (), m.get (1).sql_literal ()));
                    continue;
                }
                sb.append (sql).append (";\n");
                append_rows (db, sb, name, Sql.quote_ident (name), null);
            }
            var seq = db.query ("SELECT count(*) FROM sqlite_master WHERE name = 'sqlite_sequence'");
            if (seq.rows[0].get (0).as_int () > 0) {
                var rs = db.query ("SELECT name, seq FROM sqlite_sequence");
                if (rs.rows.size > 0) sb.append ("DELETE FROM sqlite_sequence;\n");
                foreach (var r in rs.rows) sb.append ("INSERT INTO sqlite_sequence VALUES(%s,%s);\n".printf (r.get (0).sql_literal (), r.get (1).sql_literal ()));
            }
            foreach (var r in objects.rows) {
                if (r.get (0).to_string () == "table") continue;
                sb.append (r.get (2).to_string ()).append (";\n");
            }
            sb.append ("COMMIT;\n");
            return sb.str;
        }

        private static void append_rows (Database db, StringBuilder sb, string table, string target, SqlDialect? dialect) throws Error {
            var stmt = db.prepare ("SELECT * FROM %s".printf (Sql.quote_ident (table)));
            int n = stmt.column_count ();
            string[] cols = {};
            for (int i = 0; i < n; i++) cols += quote_for (stmt.column_name (i), dialect);
            string head = dialect == null ? "INSERT INTO %s VALUES(".printf (target) : "INSERT INTO %s (%s) VALUES (".printf (target, string.joinv (", ", cols));
            while (stmt.step () == Sqlite.ROW) {
                sb.append (head);
                for (int i = 0; i < n; i++) {
                    if (i > 0) sb.append (",");
                    var v = Database.column (stmt, i);
                    sb.append (literal_for (v, dialect));
                }
                sb.append (");\n");
            }
        }

        private static string quote_for (string name, SqlDialect? dialect) {
            if (dialect == SqlDialect.MYSQL) return "`" + name.replace ("`", "``") + "`";
            return Sql.quote_ident (name);
        }

        private static string literal_for (DbValue v, SqlDialect? dialect) {
            if (dialect == null || v.kind != ValueKind.BLOB) {
                if (dialect == SqlDialect.MYSQL && v.kind == ValueKind.TEXT) return "'" + v.text_value.replace ("\\", "\\\\").replace ("'", "''") + "'";
                return v.sql_literal ();
            }
            var sb = new StringBuilder ();
            unowned uint8[] data = v.blob_value.get_data ();
            foreach (uint8 b in data) sb.append ("%02x".printf (b));
            if (dialect == SqlDialect.POSTGRESQL) return "'\\x%s'::bytea".printf (sb.str);
            return "X'%s'".printf (sb.str);
        }

        private static string type_for (Field f, SqlDialect d) {
            bool pg = d == SqlDialect.POSTGRESQL;
            switch (f.field_type) {
                case FieldType.AUTONUMBER: return pg ? "BIGSERIAL" : "BIGINT AUTO_INCREMENT";
                case FieldType.INTEGER:
                case FieldType.LOOKUP: return "BIGINT";
                case FieldType.NUMBER: return pg ? "DOUBLE PRECISION" : "DOUBLE";
                case FieldType.CURRENCY: return "DECIMAL(19,4)";
                case FieldType.PERCENT: return pg ? "DOUBLE PRECISION" : "DOUBLE";
                case FieldType.DATE: return "DATE";
                case FieldType.DATETIME: return pg ? "TIMESTAMP" : "DATETIME";
                case FieldType.TIME: return "TIME";
                case FieldType.BOOLEAN: return pg ? "BOOLEAN" : "TINYINT(1)";
                case FieldType.LONG_TEXT: return pg ? "TEXT" : "LONGTEXT";
                case FieldType.ATTACHMENT: return pg ? "BYTEA" : "LONGBLOB";
                default:
                    if (f.max_length > 0) return "VARCHAR(%d)".printf (f.max_length);
                    return pg ? "TEXT" : "VARCHAR(255)";
            }
        }

        private static string portable (Database db, SqlDialect d) throws Error {
            var sb = new StringBuilder ();
            if (d == SqlDialect.MYSQL) sb.append ("SET FOREIGN_KEY_CHECKS=0;\n");
            sb.append ("BEGIN;\n");
            var defs = new Gee.ArrayList<TableDef> ();
            foreach (string t in db.table_names ()) defs.add (db.load_table (t));
            foreach (var def in defs) {
                sb.append ("CREATE TABLE %s (\n".printf (quote_for (def.name, d)));
                string[] parts = {};
                var pk = def.primary_key ();
                foreach (var f in def.fields) {
                    var p = new StringBuilder ("    %s %s".printf (quote_for (f.name, d), type_for (f, d)));
                    if (f.required || f.primary_key) p.append (" NOT NULL");
                    if (f.unique && !f.primary_key) p.append (" UNIQUE");
                    string dv = f.default_sql ();
                    if (dv != "" && !dv.has_prefix ("(")) {
                        if (f.field_type == FieldType.BOOLEAN && d == SqlDialect.POSTGRESQL) dv = dv == "1" ? "TRUE" : "FALSE";
                        p.append (" DEFAULT ").append (dv);
                    }
                    if (f.field_type == FieldType.CHOICE && f.choices.length > 0) {
                        string[] q = {};
                        foreach (string c in f.choices) q += Sql.quote_string (c);
                        p.append (" CHECK (%s IN (%s))".printf (quote_for (f.name, d), string.joinv (", ", q)));
                    }
                    parts += p.str;
                }
                if (pk.size > 0) {
                    string[] cols = {};
                    foreach (var f in pk) cols += quote_for (f.name, d);
                    parts += "    PRIMARY KEY (%s)".printf (string.joinv (", ", cols));
                }
                sb.append (string.joinv (",\n", parts));
                sb.append ("\n);\n");
            }
            foreach (var def in defs) {
                var pk = def.primary_key ();
                bool pg_bool_fix = d == SqlDialect.POSTGRESQL;
                if (pg_bool_fix) {
                    bool has_bool = false;
                    foreach (var f in def.fields) {
                        if (f.field_type == FieldType.BOOLEAN) has_bool = true;
                    }
                    if (has_bool) {
                        append_rows_bool (db, sb, def);
                        continue;
                    }
                }
                append_rows (db, sb, def.name, quote_for (def.name, d), d);
                if (d == SqlDialect.POSTGRESQL && pk.size == 1 && pk[0].field_type == FieldType.AUTONUMBER) {
                    sb.append ("SELECT setval(pg_get_serial_sequence('%s', '%s'), COALESCE(MAX(%s), 1)) FROM %s;\n".printf (
                        def.name.replace ("'", "''"), pk[0].name.replace ("'", "''"), quote_for (pk[0].name, d), quote_for (def.name, d)));
                }
            }
            foreach (var def in defs) {
                foreach (var r in def.effective_relationships ()) {
                    if (!r.enforce) continue;
                    string[] a = {}, b = {};
                    foreach (string c in r.columns) a += quote_for (c, d);
                    foreach (string c in r.ref_columns) b += quote_for (c, d);
                    sb.append ("ALTER TABLE %s ADD FOREIGN KEY (%s) REFERENCES %s (%s)%s%s;\n".printf (quote_for (def.name, d), string.joinv (", ", a), quote_for (r.ref_table, d), string.joinv (", ", b),
                        r.on_update != RefAction.NO_ACTION ? " ON UPDATE " + r.on_update.sql () : "", r.on_delete != RefAction.NO_ACTION ? " ON DELETE " + r.on_delete.sql () : ""));
                }
                foreach (var i in def.indexes) {
                    string[] cols = {};
                    foreach (string c in i.columns) cols += quote_for (c, d);
                    sb.append ("CREATE %sINDEX %s ON %s (%s);\n".printf (i.unique ? "UNIQUE " : "", quote_for (i.name, d), quote_for (def.name, d), string.joinv (", ", cols)));
                }
            }
            sb.append ("COMMIT;\n");
            if (d == SqlDialect.MYSQL) sb.append ("SET FOREIGN_KEY_CHECKS=1;\n");
            return sb.str;
        }

        private static void append_rows_bool (Database db, StringBuilder sb, TableDef def) throws Error {
            var stmt = db.prepare ("SELECT * FROM %s".printf (Sql.quote_ident (def.name)));
            int n = stmt.column_count ();
            string[] cols = {};
            for (int i = 0; i < n; i++) cols += Sql.quote_ident (stmt.column_name (i));
            while (stmt.step () == Sqlite.ROW) {
                sb.append ("INSERT INTO %s (%s) VALUES (".printf (Sql.quote_ident (def.name), string.joinv (", ", cols)));
                for (int i = 0; i < n; i++) {
                    if (i > 0) sb.append (",");
                    var v = Database.column (stmt, i);
                    var f = def.find (stmt.column_name (i));
                    if (f != null && f.field_type == FieldType.BOOLEAN && !v.is_null) sb.append (v.as_bool () ? "TRUE" : "FALSE");
                    else sb.append (literal_for (v, SqlDialect.POSTGRESQL));
                }
                sb.append (");\n");
            }
        }

        public static void import_script (Database db, string script) throws Error {
            ResultSet? last;
            db.execute_script (script, out last);
        }
    }
}
