namespace Singularity.Apps.Database {

    public errordomain SchemaError {
        INVALID,
        CONSTRAINT,
        SQL,
        NOT_FOUND
    }

    public enum FieldType {
        AUTONUMBER,
        TEXT,
        LONG_TEXT,
        INTEGER,
        NUMBER,
        CURRENCY,
        PERCENT,
        DATE,
        DATETIME,
        TIME,
        BOOLEAN,
        CHOICE,
        EMAIL,
        URL,
        PHONE,
        ATTACHMENT,
        LOOKUP;

        public const FieldType[] ALL = {
            FieldType.AUTONUMBER, FieldType.TEXT, FieldType.LONG_TEXT, FieldType.INTEGER, FieldType.NUMBER,
            FieldType.CURRENCY, FieldType.PERCENT, FieldType.DATE, FieldType.DATETIME, FieldType.TIME,
            FieldType.BOOLEAN, FieldType.CHOICE, FieldType.EMAIL, FieldType.URL, FieldType.PHONE,
            FieldType.ATTACHMENT, FieldType.LOOKUP
        };

        public string id () {
            switch (this) {
                case AUTONUMBER: return "autonumber";
                case TEXT: return "text";
                case LONG_TEXT: return "long-text";
                case INTEGER: return "integer";
                case NUMBER: return "number";
                case CURRENCY: return "currency";
                case PERCENT: return "percent";
                case DATE: return "date";
                case DATETIME: return "datetime";
                case TIME: return "time";
                case BOOLEAN: return "boolean";
                case CHOICE: return "choice";
                case EMAIL: return "email";
                case URL: return "url";
                case PHONE: return "phone";
                case ATTACHMENT: return "attachment";
                case LOOKUP: return "lookup";
            }
            return "text";
        }

        public static FieldType from_id (string id) {
            foreach (var t in ALL) {
                if (t.id () == id) return t;
            }
            return FieldType.TEXT;
        }

        public string label () {
            switch (this) {
                case AUTONUMBER: return _("AutoNumber");
                case TEXT: return _("Short Text");
                case LONG_TEXT: return _("Long Text");
                case INTEGER: return _("Whole Number");
                case NUMBER: return _("Decimal Number");
                case CURRENCY: return _("Currency");
                case PERCENT: return _("Percent");
                case DATE: return _("Date");
                case DATETIME: return _("Date and Time");
                case TIME: return _("Time");
                case BOOLEAN: return _("Yes/No");
                case CHOICE: return _("Choice List");
                case EMAIL: return _("Email");
                case URL: return _("Hyperlink");
                case PHONE: return _("Phone Number");
                case ATTACHMENT: return _("Attachment");
                case LOOKUP: return _("Lookup");
            }
            return "";
        }

        public string icon_name () {
            switch (this) {
                case AUTONUMBER: return "db-key-symbolic";
                case TEXT: return "db-type-text-symbolic";
                case LONG_TEXT: return "db-type-longtext-symbolic";
                case INTEGER:
                case NUMBER: return "db-type-number-symbolic";
                case CURRENCY: return "db-type-currency-symbolic";
                case PERCENT: return "db-type-percent-symbolic";
                case DATE:
                case DATETIME:
                case TIME: return "db-type-date-symbolic";
                case BOOLEAN: return "db-type-boolean-symbolic";
                case CHOICE: return "db-type-choice-symbolic";
                case EMAIL: return "db-type-email-symbolic";
                case URL: return "db-type-link-symbolic";
                case PHONE: return "db-type-phone-symbolic";
                case ATTACHMENT: return "db-type-attachment-symbolic";
                case LOOKUP: return "db-relationship-symbolic";
            }
            return "db-type-text-symbolic";
        }

        public string declared_type () {
            switch (this) {
                case AUTONUMBER:
                case INTEGER: return "INTEGER";
                case TEXT:
                case CHOICE: return "TEXT";
                case LONG_TEXT: return "LONG TEXT";
                case NUMBER: return "REAL";
                case CURRENCY: return "CURRENCY";
                case PERCENT: return "PERCENT";
                case DATE: return "DATE";
                case DATETIME: return "DATETIME";
                case TIME: return "TIME";
                case BOOLEAN: return "BOOLEAN";
                case EMAIL: return "EMAIL TEXT";
                case URL: return "URL TEXT";
                case PHONE: return "PHONE TEXT";
                case ATTACHMENT: return "BLOB";
                case LOOKUP: return "INTEGER";
            }
            return "TEXT";
        }

        public static FieldType from_declared (string declared) {
            string d = declared.strip ().up ();
            int paren = d.index_of ("(");
            if (paren > 0) d = d.substring (0, paren).strip ();
            switch (d) {
                case "": return FieldType.TEXT;
                case "LONG TEXT":
                case "LONGTEXT":
                case "MEMO":
                case "CLOB":
                case "MEDIUMTEXT": return FieldType.LONG_TEXT;
                case "CURRENCY":
                case "MONEY":
                case "SMALLMONEY": return FieldType.CURRENCY;
                case "PERCENT": return FieldType.PERCENT;
                case "DATE": return FieldType.DATE;
                case "DATETIME":
                case "TIMESTAMP": return FieldType.DATETIME;
                case "TIME": return FieldType.TIME;
                case "BOOLEAN":
                case "BOOL":
                case "BIT":
                case "YESNO": return FieldType.BOOLEAN;
                case "EMAIL TEXT":
                case "EMAIL": return FieldType.EMAIL;
                case "URL TEXT":
                case "URL":
                case "HYPERLINK": return FieldType.URL;
                case "PHONE TEXT":
                case "PHONE": return FieldType.PHONE;
                case "DECIMAL":
                case "NUMERIC": return FieldType.NUMBER;
                default: break;
            }
            if (d.contains ("INT")) return FieldType.INTEGER;
            if (d.contains ("CHAR") || d.contains ("TEXT") || d.contains ("CLOB")) return FieldType.TEXT;
            if (d.contains ("BLOB") || d.contains ("BINARY") || d.contains ("IMAGE")) return FieldType.ATTACHMENT;
            if (d.contains ("REAL") || d.contains ("FLOA") || d.contains ("DOUB")) return FieldType.NUMBER;
            return FieldType.NUMBER;
        }

        public bool is_numeric () {
            return this == INTEGER || this == NUMBER || this == CURRENCY || this == PERCENT || this == AUTONUMBER;
        }

        public bool is_temporal () {
            return this == DATE || this == DATETIME || this == TIME;
        }

        public bool is_text () {
            return this == TEXT || this == LONG_TEXT || this == CHOICE || this == EMAIL || this == URL || this == PHONE;
        }
    }

    public enum RefAction {
        NO_ACTION,
        RESTRICT,
        CASCADE,
        SET_NULL,
        SET_DEFAULT;

        public string sql () {
            switch (this) {
                case RESTRICT: return "RESTRICT";
                case CASCADE: return "CASCADE";
                case SET_NULL: return "SET NULL";
                case SET_DEFAULT: return "SET DEFAULT";
                default: return "NO ACTION";
            }
        }

        public static RefAction parse (string s) {
            switch (s.up ().strip ()) {
                case "RESTRICT": return RESTRICT;
                case "CASCADE": return CASCADE;
                case "SET NULL": return SET_NULL;
                case "SET DEFAULT": return SET_DEFAULT;
                default: return NO_ACTION;
            }
        }
    }

    public class Field {
        public string name = "";
        public FieldType field_type = FieldType.TEXT;
        public bool required;
        public bool unique;
        public bool primary_key;
        public string default_value = "";
        public string description = "";
        public int max_length;
        public int decimals = -1;
        public string[] choices = {};
        public string validation = "";
        public string lookup_table = "";
        public string lookup_field = "";
        public string lookup_display = "";
        public bool indexed;
        public string expression = "";
        public bool multi_value;
        public string format = "";
        public string input_mask = "";
        public string caption = "";
        public string validation_rule = "";
        public string validation_text = "";
        public bool rich_text;
        public string table_name = "";

        public bool is_calculated () {
            return expression.strip () != "";
        }

        public string label () {
            return caption != "" ? caption : name;
        }

        public string validation_sql () {
            string r = validation_rule.strip ();
            if (r == "") return validation.strip ();
            return AccessRule.to_sql (Sql.quote_ident (name), r);
        }

        public Field (string name, FieldType type) {
            this.name = name;
            this.field_type = type;
        }

        public Field copy () {
            var f = new Field (name, field_type);
            f.required = required;
            f.unique = unique;
            f.primary_key = primary_key;
            f.default_value = default_value;
            f.description = description;
            f.max_length = max_length;
            f.decimals = decimals;
            f.choices = choices;
            f.validation = validation;
            f.lookup_table = lookup_table;
            f.lookup_field = lookup_field;
            f.lookup_display = lookup_display;
            f.indexed = indexed;
            f.expression = expression;
            f.multi_value = multi_value;
            f.format = format;
            f.input_mask = input_mask;
            f.caption = caption;
            f.validation_rule = validation_rule;
            f.validation_text = validation_text;
            f.rich_text = rich_text;
            f.table_name = table_name;
            return f;
        }

        public string default_sql () {
            string d = default_value.strip ();
            if (d == "") return "";
            string u = d.up ();
            if (u == "NOW()" || u == "NOW" || u == "CURRENT_TIMESTAMP") {
                return field_type == FieldType.DATE ? "(date('now','localtime'))" : (field_type == FieldType.TIME ? "(time('now','localtime'))" : "(datetime('now','localtime'))");
            }
            if (u == "DATE()" || u == "TODAY" || u == "TODAY()" || u == "CURRENT_DATE") return "(date('now','localtime'))";
            if (u == "TIME()" || u == "CURRENT_TIME") return "(time('now','localtime'))";
            if (u == "NULL") return "NULL";
            if (field_type == FieldType.BOOLEAN) {
                var v = new DbValue.text (d);
                return v.as_bool () ? "1" : "0";
            }
            if (d.has_prefix ("(") && d.has_suffix (")")) return d;
            if (field_type.is_numeric ()) {
                double x;
                if (double.try_parse (d, out x)) return d;
            }
            if (d.length >= 2 && d[0] == '\'' && d[d.length - 1] == '\'') return d;
            if (d.length >= 2 && d[0] == '"' && d[d.length - 1] == '"') d = d.substring (1, d.length - 2);
            return Sql.quote_string (d);
        }

        public string declared () {
            if (multi_value && (field_type == FieldType.CHOICE || field_type == FieldType.LOOKUP)) return "MULTIVALUE TEXT";
            return field_type.declared_type ();
        }

        public string column_sql (bool single_pk, string table = "") {
            var sb = new StringBuilder (Sql.quote_ident (name));
            sb.append (" ");
            sb.append (declared ());
            if (is_calculated ()) {
                sb.append (" GENERATED ALWAYS AS (%s) VIRTUAL".printf (AccessSql.expression (expression)));
                return sb.str;
            }
            if (field_type == FieldType.AUTONUMBER && single_pk) {
                sb.append (" PRIMARY KEY AUTOINCREMENT");
            } else if (primary_key && single_pk) {
                sb.append (" PRIMARY KEY");
            }
            if (required && !(primary_key && field_type == FieldType.AUTONUMBER)) sb.append (" NOT NULL");
            if (unique && !primary_key) sb.append (" UNIQUE");
            string def = default_sql ();
            if (def != "") sb.append (" DEFAULT ").append (def);
            string q = Sql.quote_ident (name);
            string[] checks = {};
            if (field_type == FieldType.BOOLEAN) checks += "%s IN (0, 1)".printf (q);
            if (field_type == FieldType.CHOICE && choices.length > 0 && !multi_value) {
                string[] quoted = {};
                foreach (string c in choices) quoted += Sql.quote_string (c);
                checks += "%s IN (%s)".printf (q, string.joinv (", ", quoted));
            }
            if (max_length > 0 && field_type.is_text ()) checks += "length(%s) <= %d".printf (q, max_length);
            if (checks.length > 0) {
                sb.append (" CHECK (");
                for (int i = 0; i < checks.length; i++) {
                    if (i > 0) sb.append (" AND ");
                    sb.append (checks.length > 1 ? "(" + checks[i] + ")" : checks[i]);
                }
                sb.append (")");
            }
            string vr = validation_sql ();
            if (vr != "") sb.append (" CONSTRAINT %s CHECK (%s)".printf (Sql.quote_ident ("vr:" + table + "." + name), vr));
            return sb.str;
        }
    }

    public class IndexDef {
        public string name = "";
        public string[] columns = {};
        public bool unique;

        public IndexDef (string name, string[] columns, bool unique) {
            this.name = name;
            this.columns = columns;
            this.unique = unique;
        }

        public IndexDef copy () {
            return new IndexDef (name, columns, unique);
        }

        public string create_sql (string table) {
            string[] cols = {};
            foreach (string c in columns) cols += Sql.quote_ident (c);
            return "CREATE %sINDEX %s ON %s (%s)".printf (unique ? "UNIQUE " : "", Sql.quote_ident (name), Sql.quote_ident (table), string.joinv (", ", cols));
        }
    }

    public class Relationship {
        public string name = "";
        public string table = "";
        public string[] columns = {};
        public string ref_table = "";
        public string[] ref_columns = {};
        public bool enforce = true;
        public RefAction on_update = RefAction.NO_ACTION;
        public RefAction on_delete = RefAction.NO_ACTION;

        public Relationship (string table, string column, string ref_table, string ref_column) {
            this.table = table;
            this.columns = { column };
            this.ref_table = ref_table;
            this.ref_columns = { ref_column };
        }

        public Relationship copy () {
            var r = new Relationship (table, "", ref_table, "");
            r.name = name;
            r.columns = columns;
            r.ref_columns = ref_columns;
            r.enforce = enforce;
            r.on_update = on_update;
            r.on_delete = on_delete;
            return r;
        }

        public string key () {
            return "%s(%s)>%s(%s)".printf (table.casefold (), string.joinv (",", columns).casefold (), ref_table.casefold (), string.joinv (",", ref_columns).casefold ());
        }

        public string constraint_sql () {
            string[] a = {}, b = {};
            foreach (string c in columns) a += Sql.quote_ident (c);
            foreach (string c in ref_columns) b += Sql.quote_ident (c);
            var sb = new StringBuilder ();
            if (name != "") sb.append ("CONSTRAINT %s ".printf (Sql.quote_ident (name)));
            sb.append ("FOREIGN KEY (%s) REFERENCES %s (%s)".printf (string.joinv (", ", a), Sql.quote_ident (ref_table), string.joinv (", ", b)));
            if (on_update != RefAction.NO_ACTION) sb.append (" ON UPDATE ").append (on_update.sql ());
            if (on_delete != RefAction.NO_ACTION) sb.append (" ON DELETE ").append (on_delete.sql ());
            return sb.str;
        }
    }

    public class TableDef {
        public string name = "";
        public string description = "";
        public Gee.ArrayList<Field> fields = new Gee.ArrayList<Field> ();
        public Gee.ArrayList<IndexDef> indexes = new Gee.ArrayList<IndexDef> ();
        public Gee.ArrayList<Relationship> relationships = new Gee.ArrayList<Relationship> ();
        public bool without_rowid;
        public string validation_rule = "";
        public string validation_text = "";
        public string link_path = "";
        public string link_table = "";

        public TableDef (string name) {
            this.name = name;
        }

        public TableDef copy () {
            var t = new TableDef (name);
            t.description = description;
            t.without_rowid = without_rowid;
            t.validation_rule = validation_rule;
            t.validation_text = validation_text;
            t.link_path = link_path;
            t.link_table = link_table;
            foreach (var f in fields) t.fields.add (f.copy ());
            foreach (var i in indexes) t.indexes.add (i.copy ());
            foreach (var r in relationships) t.relationships.add (r.copy ());
            return t;
        }

        public Field? find (string field) {
            foreach (var f in fields) {
                if (f.name.casefold () == field.casefold ()) return f;
            }
            return null;
        }

        public int index_of (string field) {
            for (int i = 0; i < fields.size; i++) {
                if (fields[i].name.casefold () == field.casefold ()) return i;
            }
            return -1;
        }

        public Gee.ArrayList<Field> primary_key () {
            var list = new Gee.ArrayList<Field> ();
            foreach (var f in fields) {
                if (f.primary_key) list.add (f);
            }
            return list;
        }

        public Field add_field (string name, FieldType type) {
            var f = new Field (name, type);
            fields.add (f);
            return f;
        }

        public string unique_field_name (string base_name) {
            if (find (base_name) == null) return base_name;
            for (int i = 2; ; i++) {
                string n = "%s %d".printf (base_name, i);
                if (find (n) == null) return n;
            }
        }

        public void validate () throws SchemaError {
            if (name.strip () == "") throw new SchemaError.INVALID (_("The table needs a name."));
            if (name.has_prefix ("sqlite_") || name.has_prefix ("_sdb_")) throw new SchemaError.INVALID (_("Table names cannot start with \"%s\".").printf (name.has_prefix ("sqlite_") ? "sqlite_" : "_sdb_"));
            if (fields.size == 0) throw new SchemaError.INVALID (_("The table needs at least one field."));
            var seen = new Gee.HashSet<string> ();
            int autos = 0;
            foreach (var f in fields) {
                if (f.name.strip () == "") throw new SchemaError.INVALID (_("Every field needs a name."));
                if (!seen.add (f.name.casefold ())) throw new SchemaError.INVALID (_("There are two fields named \"%s\".").printf (f.name));
                if (f.field_type == FieldType.AUTONUMBER) autos++;
                if (f.field_type == FieldType.CHOICE && f.choices.length == 0) throw new SchemaError.INVALID (_("The choice field \"%s\" needs at least one choice.").printf (f.name));
                if (f.is_calculated () && f.primary_key) throw new SchemaError.INVALID (_("The calculated field \"%s\" cannot be a primary key.").printf (f.name));
                if (f.field_type == FieldType.LOOKUP && (f.lookup_table == "" || f.lookup_field == "")) throw new SchemaError.INVALID (_("The lookup field \"%s\" needs a table and a field to look up.").printf (f.name));
            }
            if (autos > 1) throw new SchemaError.INVALID (_("A table can have only one AutoNumber field."));
            var pk = primary_key ();
            if (autos == 1) {
                foreach (var f in fields) {
                    if (f.field_type == FieldType.AUTONUMBER && (!f.primary_key || pk.size > 1)) throw new SchemaError.INVALID (_("The AutoNumber field must be the only primary key."));
                }
            }
            foreach (var idx in indexes) {
                foreach (string c in idx.columns) {
                    if (find (c) == null) throw new SchemaError.INVALID (_("The index \"%s\" uses a field that does not exist.").printf (idx.name));
                }
            }
            foreach (var r in relationships) {
                foreach (string c in r.columns) {
                    if (find (c) == null) throw new SchemaError.INVALID (_("A relationship uses the missing field \"%s\".").printf (c));
                }
            }
        }

        public Gee.ArrayList<Relationship> effective_relationships () {
            var list = new Gee.ArrayList<Relationship> ();
            var keys = new Gee.HashSet<string> ();
            foreach (var r in relationships) {
                list.add (r);
                keys.add (r.key ());
            }
            foreach (var f in fields) {
                if (f.field_type != FieldType.LOOKUP || f.lookup_table == "" || f.lookup_field == "" || f.multi_value) continue;
                var r = new Relationship (name, f.name, f.lookup_table, f.lookup_field);
                if (keys.add (r.key ())) list.add (r);
            }
            return list;
        }

        public string create_sql (string? as_name = null) {
            var pk = primary_key ();
            bool single = pk.size == 1;
            var sb = new StringBuilder ();
            sb.append ("CREATE TABLE %s (\n".printf (Sql.quote_ident (as_name ?? name)));
            string[] parts = {};
            foreach (var f in fields) parts += "    " + f.column_sql (single, as_name ?? name);
            if (pk.size > 1) {
                string[] cols = {};
                foreach (var f in pk) cols += Sql.quote_ident (f.name);
                parts += "    PRIMARY KEY (%s)".printf (string.joinv (", ", cols));
            }
            foreach (var r in effective_relationships ()) {
                if (r.enforce) parts += "    " + r.constraint_sql ();
            }
            if (validation_rule.strip () != "") parts += "    CONSTRAINT %s CHECK (%s)".printf (Sql.quote_ident ("tvr:" + (as_name ?? name)), AccessRule.table_sql (validation_rule));
            sb.append (string.joinv (",\n", parts));
            sb.append ("\n)");
            if (without_rowid && pk.size > 0) sb.append (" WITHOUT ROWID");
            return sb.str;
        }

        public string[] index_sql () {
            string[] list = {};
            foreach (var i in indexes) list += i.create_sql (name);
            foreach (var f in fields) {
                if (!f.indexed || f.primary_key || f.unique || f.is_calculated ()) continue;
                bool covered = false;
                foreach (var i in indexes) {
                    if (i.columns.length > 0 && i.columns[0].casefold () == f.name.casefold ()) covered = true;
                }
                if (!covered) list += new IndexDef ("idx_%s_%s".printf (name, f.name), { f.name }, false).create_sql (name);
            }
            return list;
        }
    }

    public class QueryDef {
        public string name = "";
        public string sql = "";
        public string design = "";
        public string description = "";

        public QueryDef (string name, string sql) {
            this.name = name;
            this.sql = sql;
        }
    }
}

namespace Singularity.Apps.Database {

    public class AccessRule {
        public static bool is_short_form (string rule) {
            string r = rule.strip ();
            string low = r.down ();
            string[] starts = { "<", ">", "=", "between ", "like ", "in ", "in(", "is ", "not ", "<>" };
            foreach (string st in starts) {
                if (low.has_prefix (st)) return true;
            }
            if (low == "is null" || low == "is not null") return true;
            if (r.has_prefix ("[")) return false;
            double d;
            if (double.try_parse (r, out d)) return true;
            if (r.has_prefix ("\"") || r.has_prefix ("'") || r.has_prefix ("#")) return true;
            return false;
        }

        public static string to_sql (string column_sql, string rule) {
            string r = rule.strip ();
            if (is_short_form (r)) return stable (Criteria.to_sql (column_sql, r));
            return stable (AccessSql.expression (r));
        }

        public static string table_sql (string rule) {
            return stable (AccessSql.expression (rule.strip ()));
        }

        private static string stable (string sql) {
            return sql.replace ("datetime('now','localtime')", "acc_check_now()").replace ("date('now','localtime')", "acc_check_today()").replace ("acc_date()", "acc_check_today()").replace ("acc_now()", "acc_check_now()");
        }
    }
}
