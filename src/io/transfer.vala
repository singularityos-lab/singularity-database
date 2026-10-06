namespace Singularity.Apps.Database {

    public enum ImportMode {
        NEW_TABLE,
        APPEND,
        REPLACE
    }

    public class ImportResult {
        public string table = "";
        public int imported;
        public int failed;
        public Gee.ArrayList<string> notes = new Gee.ArrayList<string> ();
    }

    public class Transfer {
        public static string[] import_extensions () {
            return { "csv", "tsv", "txt", "xlsx", "json", "ndjson", "xml", "sql", "mdb", "accdb", "form", "report", "macro", "bas", "cls", "sqlite", "sqlite3", "db", "sdb" };
        }

        public static FieldType infer_column (DataTable dt, int c) {
            FieldType? fixed_type = c < dt.types.length ? dt.types[c] : null;
            if (fixed_type != null) return fixed_type;
            int ints = 0, reals = 0, texts = 0, blobs = 0, total = 0;
            var samples = new Gee.ArrayList<string> ();
            int limit = int.min (dt.rows.size, 2000);
            for (int r = 0; r < limit; r++) {
                var v = dt.rows[r].get (c);
                if (v.is_null) continue;
                total++;
                switch (v.kind) {
                    case ValueKind.INTEGER: ints++; break;
                    case ValueKind.REAL: reals++; break;
                    case ValueKind.BLOB: blobs++; break;
                    default:
                        texts++;
                        samples.add (v.text_value);
                        break;
                }
            }
            if (total == 0) return FieldType.TEXT;
            if (blobs == total) return FieldType.ATTACHMENT;
            if (ints == total) return FieldType.INTEGER;
            if (ints + reals == total) return FieldType.NUMBER;
            if (texts == total) {
                var t = Codec.infer (samples);
                if (t == FieldType.TEXT) {
                    foreach (string s in samples) {
                        if (s.char_count () > 255 || s.contains ("\n")) return FieldType.LONG_TEXT;
                    }
                }
                return t;
            }
            var mixed = new Gee.ArrayList<string> ();
            for (int r = 0; r < limit; r++) {
                var v = dt.rows[r].get (c);
                if (!v.is_null) mixed.add (v.to_string ());
            }
            var t = Codec.infer (mixed);
            return t == FieldType.INTEGER || t == FieldType.NUMBER ? t : FieldType.TEXT;
        }

        public static TableDef table_for (Database db, DataTable dt, string name, bool add_id, FieldType[]? overrides = null) {
            var def = new TableDef (name);
            bool has_id = false;
            foreach (string c in dt.columns) {
                if (c.casefold () == "id") has_id = true;
            }
            if (add_id && !has_id) {
                var id = def.add_field ("ID", FieldType.AUTONUMBER);
                id.primary_key = true;
            }
            for (int c = 0; c < dt.columns.length; c++) {
                var t = overrides != null && c < overrides.length ? overrides[c] : infer_column (dt, c);
                string fname = def.unique_field_name (dt.columns[c].strip () == "" ? _("Field %d").printf (c + 1) : dt.columns[c].strip ());
                var f = def.add_field (fname, t);
                if (t == FieldType.CURRENCY) f.decimals = 2;
            }
            if (add_id && has_id) {
                var idf = def.find ("ID");
                if (idf != null && idf.field_type == FieldType.INTEGER) {
                    var seen = new Gee.HashSet<int64?> ((v) => (uint) v, (a, b) => a == b);
                    bool unique = true;
                    int ci = -1;
                    for (int c = 0; c < dt.columns.length; c++) {
                        if (dt.columns[c].casefold () == "id") ci = c;
                    }
                    foreach (var r in dt.rows) {
                        var v = r.get (ci);
                        if (v.is_null || !seen.add (v.as_int ())) {
                            unique = false;
                            break;
                        }
                    }
                    if (unique) {
                        idf.primary_key = true;
                        idf.field_type = FieldType.AUTONUMBER;
                    }
                }
            }
            return def;
        }

        private static DbValue convert (Field f, DbValue v, ref int failed) {
            if (v.is_null) return v;
            switch (f.field_type) {
                case FieldType.TEXT:
                case FieldType.LONG_TEXT:
                case FieldType.EMAIL:
                case FieldType.URL:
                case FieldType.PHONE:
                    if (v.kind == ValueKind.BLOB) return v;
                    return new DbValue.text (v.to_string ());
                case FieldType.CHOICE:
                    return new DbValue.text (v.to_string ());
                case FieldType.ATTACHMENT:
                    return v;
                case FieldType.BOOLEAN:
                    return new DbValue.bool (v.as_bool ());
                default:
                    if (v.is_number () && f.field_type.is_numeric ()) {
                        if (f.field_type == FieldType.INTEGER || f.field_type == FieldType.AUTONUMBER) return new DbValue.int (v.as_int ());
                        return new DbValue.real (v.as_double ());
                    }
                    if (v.is_number () && f.field_type.is_temporal ()) {
                        string iso = Xlsx.serial_to_iso (v.as_double (), f.field_type == FieldType.DATETIME);
                        return new DbValue.text (iso);
                    }
                    try {
                        var p = Codec.parse (f, v.to_string ());
                        return p;
                    } catch (Error e) {
                        failed++;
                        return new DbValue.null ();
                    }
            }
        }

        public static ImportResult import_table (Database db, DataTable dt, string target, ImportMode mode, bool add_id = true, FieldType[]? overrides = null) throws Error {
            var result = new ImportResult ();
            result.table = target;
            TableDef def;
            bool exists = db.object_exists (target, "table");
            if (mode == ImportMode.NEW_TABLE || !exists) {
                string name = exists ? db.unique_object_name (target) : target;
                def = table_for (db, dt, name, add_id, overrides);
                def.validate ();
                result.table = name;
                db.design_change (_("Import Table"), { name }, () => {
                    db.exec (def.create_sql ());
                    foreach (string s in def.index_sql ()) db.exec (s);
                    db.write_table_meta (def);
                    fill (db, def, dt, result);
                });
            } else {
                def = db.load_table (target);
                db.design_change (mode == ImportMode.REPLACE ? _("Replace Records") : _("Append Records"), { def.name }, () => {
                    if (mode == ImportMode.REPLACE) db.exec ("DELETE FROM %s".printf (Sql.quote_ident (def.name)));
                    fill (db, def, dt, result);
                });
            }
            db.data_changed (result.table);
            return result;
        }

        private static void fill (Database db, TableDef def, DataTable dt, ImportResult result) throws Error {
            var map = new Gee.ArrayList<int> ();
            var targets = new Gee.ArrayList<Field> ();
            for (int c = 0; c < dt.columns.length; c++) {
                var f = def.find (dt.columns[c].strip ());
                if (f == null || f.is_calculated ()) continue;
                if (f.field_type == FieldType.AUTONUMBER && dt.columns[c].casefold () != f.name.casefold ()) continue;
                map.add (c);
                targets.add (f);
            }
            if (targets.size == 0) throw new SchemaError.INVALID (_("None of the columns match the fields of \"%s\".").printf (def.name));
            string[] q = {};
            string[] ph = {};
            foreach (var f in targets) {
                q += Sql.quote_ident (f.name);
                ph += "?";
            }
            var stmt = db.prepare ("INSERT INTO %s (%s) VALUES (%s)".printf (Sql.quote_ident (def.name), string.joinv (", ", q), string.joinv (", ", ph)));
            int failed = 0;
            int row_errors = 0;
            string first_error = "";
            foreach (var r in dt.rows) {
                stmt.reset ();
                stmt.clear_bindings ();
                for (int k = 0; k < targets.size; k++) Database.bind (stmt, k + 1, convert (targets[k], r.get (map[k]), ref failed));
                int rc = stmt.step ();
                if (rc != Sqlite.DONE) {
                    row_errors++;
                    if (first_error == "") first_error = Database.friendly_constraint (db.handle ().errmsg ());
                    continue;
                }
                result.imported++;
            }
            result.failed = failed + row_errors;
            if (failed > 0) result.notes.add (ngettext ("%d value could not be converted and was left empty.", "%d values could not be converted and were left empty.", failed).printf (failed));
            if (row_errors > 0) result.notes.add (ngettext ("%d record was skipped: %s", "%d records were skipped: %s", row_errors).printf (row_errors, first_error));
        }

        public static DataTable from_source (RecordSource rs, bool formatted = false, bool visible_only = false) throws Error {
            var dt = new DataTable (rs.def.name);
            var fields = new Gee.ArrayList<Field> ();
            foreach (var f in rs.def.fields) {
                if (visible_only && rs.state.hidden.contains (f.name)) continue;
                fields.add (f);
            }
            string[] cols = {};
            FieldType?[] types = {};
            foreach (var f in fields) {
                cols += f.name;
                types += formatted ? FieldType.TEXT : f.field_type;
            }
            dt.columns = cols;
            dt.types = types;
            int64 n = rs.count ();
            for (int64 i = 0; i < n; i++) {
                var row = rs.row (i);
                if (row == null) break;
                DbValue[] vals = new DbValue[fields.size];
                for (int k = 0; k < fields.size; k++) {
                    var v = row.get (rs.def.index_of (fields[k].name));
                    vals[k] = formatted && !v.is_null && v.kind != ValueKind.BLOB ? new DbValue.text (rs.display (fields[k], v)) : v;
                }
                dt.add_row ((owned) vals);
            }
            return dt;
        }

        public static Gee.ArrayList<DataTable> all_tables (Database db) throws Error {
            var list = new Gee.ArrayList<DataTable> ();
            foreach (string t in db.table_names ()) list.add (from_source (new RecordSource (db, t)));
            return list;
        }

        private static FieldType mdb_type (MdbColumn c, MdbTable t) {
            switch (c.kind) {
                case MdbColumnType.BOOLEAN: return FieldType.BOOLEAN;
                case MdbColumnType.BYTE:
                case MdbColumnType.INTEGER:
                case MdbColumnType.LONG: return FieldType.INTEGER;
                case MdbColumnType.MONEY: return FieldType.CURRENCY;
                case MdbColumnType.FLOAT:
                case MdbColumnType.DOUBLE:
                case MdbColumnType.NUMERIC: return FieldType.NUMBER;
                case MdbColumnType.DATETIME:
                    int idx = t.columns.index_of (c);
                    foreach (var r in t.rows) {
                        var v = r.get (idx);
                        if (!v.is_null && !v.to_string ().has_suffix ("00:00:00")) return FieldType.DATETIME;
                    }
                    return FieldType.DATE;
                case MdbColumnType.MEMO: return FieldType.LONG_TEXT;
                case MdbColumnType.OLE:
                case MdbColumnType.BINARY: return FieldType.ATTACHMENT;
                default: return FieldType.TEXT;
            }
        }

        private static bool mdb_skip (MdbColumn c) {
            if (c.kind == MdbColumnType.UNKNOWN) return true;
            return c.kind == MdbColumnType.COMPLEX && c.complex_kind != MdbComplexKind.ATTACHMENT && c.complex_kind != MdbComplexKind.MULTI_VALUE;
        }

        private static string attachment_mime (string name, string file_type) {
            bool uncertain;
            string ct = ContentType.guess (name != "" ? name : "file." + file_type, null, out uncertain);
            string? mime = ContentType.get_mime_type (ct);
            return mime ?? "application/octet-stream";
        }

        public static Gee.ArrayList<ImportResult> import_mdb (Database db, string path, string? password = null) throws Error {
            var mdb = MdbFile.open (path, password);
            var results = new Gee.ArrayList<ImportResult> ();
            var defs = new Gee.ArrayList<TableDef> ();
            var names = new Gee.HashMap<string, string> ();
            foreach (var t in mdb.tables) {
                string name = db.object_exists (t.name) ? db.unique_object_name (t.name) : t.name;
                names[t.name.casefold ()] = name;
                var def = new TableDef (name);
                for (int ci = 0; ci < t.columns.size; ci++) {
                    var c = t.columns[ci];
                    if (mdb_skip (c)) continue;
                    if (c.kind == MdbColumnType.COMPLEX) {
                        if (c.complex_kind == MdbComplexKind.ATTACHMENT) {
                            def.add_field (def.unique_field_name (c.name), FieldType.ATTACHMENT);
                        } else {
                            var mf = def.add_field (def.unique_field_name (c.name), FieldType.CHOICE);
                            mf.multi_value = true;
                            var seen = new Gee.TreeSet<string> ();
                            for (int r = 0; r < t.rows.size; r++) {
                                foreach (var v in mdb.multi_values (t, r, ci)) {
                                    if (!v.is_null) seen.add (v.to_string ());
                                }
                            }
                            string[] ch = {};
                            foreach (string x in seen) ch += x;
                            if (ch.length == 0) ch += "";
                            mf.choices = ch;
                        }
                        continue;
                    }
                    var f = def.add_field (def.unique_field_name (c.name), mdb_type (c, t));
                    if (c.kind == MdbColumnType.TEXT && c.size > 0) f.max_length = c.size;
                    if (c.kind == MdbColumnType.MONEY) f.decimals = 2;
                    f.required = !c.nullable;
                    foreach (string pk in t.primary_key) {
                        if (pk.casefold () == c.name.casefold ()) f.primary_key = true;
                    }
                    if (c.autonumber && f.primary_key && t.primary_key.length == 1 && f.field_type == FieldType.INTEGER) f.field_type = FieldType.AUTONUMBER;
                }
                defs.add (def);
            }
            foreach (var rel in mdb.relationships) {
                string? child = names[rel.table.casefold ()];
                string? parent = names[rel.ref_table.casefold ()];
                if (child == null || parent == null) continue;
                TableDef? cdef = null, pdef = null;
                foreach (var d in defs) {
                    if (d.name == child) cdef = d;
                    if (d.name == parent) pdef = d;
                }
                if (cdef == null || pdef == null) continue;
                bool pk_match = rel.ref_columns.length == pdef.primary_key ().size;
                foreach (string rc in rel.ref_columns) {
                    var pf = pdef.find (rc);
                    if (pf == null || !pf.primary_key) pk_match = false;
                }
                if (!pk_match || !rel.enforce) continue;
                var r = new Relationship (cdef.name, rel.columns[0], pdef.name, rel.ref_columns[0]);
                r.columns = rel.columns;
                r.ref_columns = rel.ref_columns;
                r.on_update = rel.cascade_update ? RefAction.CASCADE : RefAction.NO_ACTION;
                r.on_delete = rel.cascade_delete ? RefAction.CASCADE : RefAction.NO_ACTION;
                bool ok = true;
                foreach (string c in r.columns) {
                    if (cdef.find (c) == null) ok = false;
                }
                if (ok) cdef.relationships.add (r);
            }
            string[] all = {};
            foreach (var d in defs) all += d.name;
            db.design_change (_("Import Access Database"), all, () => {
                for (int i = 0; i < defs.size; i++) {
                    var def = defs[i];
                    var t = mdb.tables[i];
                    foreach (var f in def.fields) {
                        if (f.multi_value && f.choices.length == 1 && f.choices[0] == "") f.choices = {};
                    }
                    db.exec (def.create_sql ());
                    foreach (string s in def.index_sql ()) db.exec (s);
                    db.write_table_meta (def);
                    var dt = new DataTable (t.name);
                    string[] cols = {};
                    var keep = new Gee.ArrayList<int> ();
                    for (int k = 0; k < t.columns.size; k++) {
                        if (mdb_skip (t.columns[k])) continue;
                        keep.add (k);
                        cols += def.fields[cols.length].name;
                    }
                    dt.columns = cols;
                    for (int ri = 0; ri < t.rows.size; ri++) {
                        var row = t.rows[ri];
                        DbValue[] vals = new DbValue[keep.size];
                        for (int k = 0; k < keep.size; k++) {
                            var c = t.columns[keep[k]];
                            if (c.kind == MdbColumnType.COMPLEX && c.complex_kind == MdbComplexKind.ATTACHMENT) {
                                var files = new Gee.ArrayList<AttachmentFile> ();
                                foreach (var at in mdb.attachments (t, ri, keep[k])) files.add (new AttachmentFile (at.name, attachment_mime (at.name, at.file_type), at.data));
                                vals[k] = files.size > 0 ? new DbValue.blob (Attachment.pack_many (files)) : new DbValue.null ();
                            } else if (c.kind == MdbColumnType.COMPLEX) {
                                string[] items = {};
                                foreach (var v in mdb.multi_values (t, ri, keep[k])) {
                                    if (!v.is_null) items += v.to_string ();
                                }
                                vals[k] = MultiValue.from_list (items);
                            } else {
                                vals[k] = row.get (keep[k]);
                            }
                        }
                        dt.add_row ((owned) vals);
                    }
                    var result = new ImportResult ();
                    result.table = def.name;
                    fill (db, def, dt, result);
                    int skipped = 0;
                    foreach (var c in t.columns) {
                        if (c.kind == MdbColumnType.COMPLEX && mdb_skip (c)) skipped++;
                    }
                    if (skipped > 0) result.notes.add (ngettext ("%d version history field was not imported.", "%d version history fields were not imported.", skipped).printf (skipped));
                    results.add (result);
                }
            });
            var note_target = results.size > 0 ? results[0] : new ImportResult ();
            if (results.size == 0) results.add (note_target);
            import_mdb_queries (db, mdb, names, note_target);
            string[] objs = {};
            if (mdb.form_names.length > 0) objs += ngettext ("%d form", "%d forms", mdb.form_names.length).printf (mdb.form_names.length);
            if (mdb.report_names.length > 0) objs += ngettext ("%d report", "%d reports", mdb.report_names.length).printf (mdb.report_names.length);
            if (mdb.macro_names.length > 0) objs += ngettext ("%d macro", "%d macros", mdb.macro_names.length).printf (mdb.macro_names.length);
            if (mdb.module_names.length > 0) objs += ngettext ("%d module", "%d modules", mdb.module_names.length).printf (mdb.module_names.length);
            if (objs.length > 0) note_target.notes.add (_("The file also contains %s. Access stores their design in a private binary format; export them from Access with SaveAsText and import the text files to bring them over.").printf (string.joinv (", ", objs)));
            return results;
        }

        public static string translate_access_query (string sql, Gee.Map<string, string>? renames = null) {
            string s = AccessSql.statement (sql);
            if (renames != null) {
                foreach (var e in renames.entries) {
                    if (e.key != e.value.casefold ()) s = s.replace (Sql.quote_ident (e.key), Sql.quote_ident (e.value));
                }
            }
            return s;
        }

        private static void import_mdb_queries (Database db, MdbFile mdb, Gee.Map<string, string> names, ImportResult result) {
            var pending = new Gee.ArrayList<MdbQuery> ();
            foreach (var q in mdb.queries) {
                if (q.name.has_prefix ("~")) continue;
                pending.add (q);
            }
            int imported = 0;
            string[] failed = {};
            for (int pass = 0; pass < 4 && pending.size > 0; pass++) {
                var next = new Gee.ArrayList<MdbQuery> ();
                foreach (var q in pending) {
                    if (q.sql.strip () == "") {
                        failed += q.name;
                        continue;
                    }
                    string name = db.object_exists (q.name) || db.get_meta ("action:" + q.name) != null ? db.unique_object_name (q.name) : q.name;
                    try {
                        string sql = q.kind == MdbQueryKind.PASS_THROUGH ? q.sql : translate_access_query (q.sql);
                        bool last = pass == 3;
                        if (q.kind == MdbQueryKind.SELECT || q.kind == MdbQueryKind.UNION) {
                            if (!QueryPrep.can_be_view (db, sql) && !last) {
                                var probe = QueryPrep.find_parameters (db, sql);
                                bool missing_query = false;
                                foreach (var p in probe) {
                                    foreach (var other in pending) {
                                        if (other != q && sql.contains (Sql.quote_ident (other.name))) missing_query = true;
                                    }
                                }
                                try {
                                    db.prepare (sql);
                                } catch (Error e) {
                                    if (e.message.contains ("no such table")) missing_query = true;
                                }
                                if (missing_query) {
                                    next.add (q);
                                    continue;
                                }
                            }
                        }
                        SavedQueries.save (db, name, sql, "", q.kind == MdbQueryKind.PASS_THROUGH ? (q.connection != "" ? q.connection : "odbc") : "");
                        imported++;
                    } catch (Error e) {
                        if (pass < 3) next.add (q);
                        else failed += q.name;
                    }
                }
                pending = next;
            }
            foreach (var q in pending) failed += q.name;
            if (imported > 0) result.notes.add (ngettext ("%d query was converted.", "%d queries were converted.", imported).printf (imported));
            if (failed.length > 0) result.notes.add (_("These queries could not be converted: %s.").printf (string.joinv (", ", failed)));
        }

        public static Gee.ArrayList<ImportResult> import_sqlite (Database db, string path) throws Error {
            var src = Database.open (path);
            var results = new Gee.ArrayList<ImportResult> ();
            foreach (string t in src.table_names ()) {
                var dt = from_source (new RecordSource (src, t));
                var sdef = src.load_table (t);
                string name = db.object_exists (t) ? db.unique_object_name (t) : t;
                sdef.name = name;
                sdef.relationships.clear ();
                foreach (var f in sdef.fields) {
                    if (f.field_type == FieldType.LOOKUP) {
                        f.field_type = FieldType.INTEGER;
                        f.lookup_table = "";
                        f.lookup_field = "";
                    }
                }
                var result = new ImportResult ();
                result.table = name;
                db.design_change (_("Import Table"), { name }, () => {
                    db.exec (sdef.create_sql ());
                    db.write_table_meta (sdef);
                    fill (db, sdef, dt, result);
                });
                results.add (result);
            }
            src.close ();
            return results;
        }
    }
}
