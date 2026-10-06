namespace Singularity.Apps.Database {

    public class LinkDef {
        public string name = "";
        public string path = "";
        public string table = "";
        public string kind = "database";
        public string schema = "";
        public string remote_schema = "";
        public bool available;
        public string error = "";

        public LinkDef (string name, string path, string table, string kind = "database") {
            this.name = name;
            this.path = path;
            this.table = table;
            this.kind = kind;
        }

        public string stored_name () {
            return schema == "temp" ? name : table;
        }
    }

    public class ServerSnapshot {
        public string[] columns = {};
        public string[] types = {};
        public string[] key = {};
        public string[] serial = {};
        public Gee.ArrayList<Row> rows = new Gee.ArrayList<Row> ();
        public string error = "";
    }

    public class LinkChange {
        public string link = "";
        public string op = "";
        public Json.Object? key;
        public Json.Object? values;
    }

    public class Links {
        public const string META_KEY = "links";

        public static Gee.ArrayList<LinkDef> list (Database db) {
            var result = new Gee.ArrayList<LinkDef> ();
            var o = Meta.parse_object ("{\"l\":%s}".printf (db.get_meta (META_KEY) ?? "[]"));
            if (o == null || !o.has_member ("l")) return result;
            o.get_array_member ("l").foreach_element ((a, i, n) => {
                var x = n.get_object ();
                var l = new LinkDef (x.get_string_member_with_default ("name", ""), x.get_string_member_with_default ("path", ""), x.get_string_member_with_default ("table", ""), x.get_string_member_with_default ("kind", "database"));
                l.remote_schema = x.get_string_member_with_default ("remote_schema", "");
                if (l.name != "") result.add (l);
            });
            return result;
        }

        private static string to_json (Gee.List<LinkDef> links) {
            var b = new Json.Builder ();
            b.begin_array ();
            foreach (var l in links) {
                b.begin_object ();
                b.set_member_name ("name").add_string_value (l.name);
                b.set_member_name ("path").add_string_value (l.path);
                b.set_member_name ("table").add_string_value (l.table);
                b.set_member_name ("kind").add_string_value (l.kind);
                if (l.remote_schema != "") b.set_member_name ("remote_schema").add_string_value (l.remote_schema);
                b.end_object ();
            }
            b.end_array ();
            return Json.to_string (b.get_root (), false);
        }

        public static string resolve (Database db, string path) {
            if (Path.is_absolute (path) || db.path == ":memory:") return path;
            return Path.build_filename (Path.get_dirname (db.path), path);
        }

        public static string relative (Database db, string path) {
            if (db.path == ":memory:") return path;
            string dir = Path.get_dirname (db.path);
            if (path.has_prefix (dir + "/")) return path.substring (dir.length + 1);
            return path;
        }

        public static void attach_all (Database db) {
            db.linked.clear ();
            var schemas = new Gee.HashMap<string, string> ();
            int counter = 0;
            try {
                var rs = db.query ("PRAGMA database_list");
                foreach (var r in rs.rows) {
                    string n = r.get (1).to_string ();
                    if (n.has_prefix ("sdblink")) db.exec ("DETACH DATABASE %s".printf (Sql.quote_ident (n)));
                }
            } catch (Error e) {
            }
            foreach (var l in list (db)) {
                if (l.kind == "server") {
                    var snap = db.server_data[l.name.casefold ()];
                    if (snap == null) {
                        l.error = _("Connecting to the server");
                    } else if (snap.error != "") {
                        l.error = snap.error;
                    } else {
                        try {
                            load_server_link (db, l, snap);
                            l.available = true;
                            l.schema = "temp";
                        } catch (Error e) {
                            l.error = e.message;
                        }
                    }
                    db.linked[l.name.casefold ()] = l;
                    continue;
                }
                string full = resolve (db, l.path);
                if (l.kind != "database") {
                    try {
                        load_file_link (db, l, full);
                        l.available = true;
                        l.schema = "temp";
                    } catch (Error e) {
                        l.error = e.message;
                    }
                    db.linked[l.name.casefold ()] = l;
                    continue;
                }
                if (!schemas.has_key (full)) {
                    string schema = "sdblink%d".printf (++counter);
                    try {
                        if (!FileUtils.test (full, FileTest.EXISTS)) throw new FileError.NOENT (_("The file \"%s\" was not found.").printf (full));
                        db.run ("ATTACH DATABASE ? AS %s".printf (Sql.quote_ident (schema)), { new DbValue.text (full) });
                        schemas[full] = schema;
                    } catch (Error e) {
                        l.error = e.message;
                        db.linked[l.name.casefold ()] = l;
                        continue;
                    }
                }
                l.schema = schemas[full];
                try {
                    l.available = db.query_int ("SELECT count(*) FROM %s.sqlite_master WHERE type = 'table' AND name = ? COLLATE NOCASE".printf (Sql.quote_ident (l.schema)), { new DbValue.text (l.table) }) > 0;
                    if (!l.available) l.error = _("The table \"%s\" is not in the linked file.").printf (l.table);
                } catch (Error e) {
                    l.error = e.message;
                }
                db.linked[l.name.casefold ()] = l;
            }
            shadow_views (db);
        }

        public static void unshadow (Database db) {
            try {
                var rs = db.query ("SELECT name FROM temp.sqlite_master WHERE type = 'view'");
                foreach (var r in rs.rows) db.exec ("DROP VIEW temp.%s".printf (Sql.quote_ident (r.get (0).to_string ())));
            } catch (Error e) {
            }
        }

        public static void shadow_views (Database db) {
            unshadow (db);
            if (db.linked.size == 0) return;
            try {
                var rs = db.query ("SELECT name, sql FROM main.sqlite_master WHERE type = 'view'");
                foreach (var r in rs.rows) {
                    string name = r.get (0).to_string ();
                    string sql = r.get (1).to_string ();
                    var toks = Sql.tokenize (sql);
                    int words = 0;
                    int as_end = -1;
                    foreach (var t in toks) {
                        if (t.kind == TokenKind.COMMENT) continue;
                        words++;
                        if (t.kind == TokenKind.KEYWORD && t.text.up () == "AS" && words >= 3) {
                            as_end = t.end;
                            break;
                        }
                    }
                    if (as_end < 0) continue;
                    try {
                        db.exec ("CREATE TEMP VIEW %s AS %s".printf (Sql.quote_ident (name), sql.substring (as_end)));
                    } catch (Error e) {
                    }
                }
            } catch (Error e) {
            }
        }

        private static void load_file_link (Database db, LinkDef l, string full) throws Error {
            DataTable dt;
            string ext = full.down ();
            if (ext.has_suffix (".xlsx")) {
                var sheets = Xlsx.load (full);
                dt = sheets[0];
                foreach (var s in sheets) {
                    if (s.name.casefold () == l.table.casefold ()) dt = s;
                }
            } else {
                dt = Csv.load (full);
            }
            var def = Transfer.table_for (db, dt, l.name, false);
            db.exec ("DROP TABLE IF EXISTS temp.%s".printf (Sql.quote_ident (l.name)));
            string create = def.create_sql ().replace ("CREATE TABLE ", "CREATE TEMP TABLE ");
            db.exec (create);
            string[] cols = {};
            string[] ph = {};
            foreach (var f in def.fields) {
                cols += Sql.quote_ident (f.name);
                ph += "?";
            }
            var stmt = db.prepare ("INSERT INTO temp.%s (%s) VALUES (%s)".printf (Sql.quote_ident (l.name), string.joinv (", ", cols), string.joinv (", ", ph)));
            foreach (var r in dt.rows) {
                stmt.reset ();
                stmt.clear_bindings ();
                for (int i = 0; i < def.fields.size; i++) {
                    var v = r.get (i);
                    try {
                        if (!v.is_null && v.kind == ValueKind.TEXT && !def.fields[i].field_type.is_text ()) v = Codec.parse (def.fields[i], v.text_value);
                    } catch (Error e) {
                    }
                    Database.bind (stmt, i + 1, v);
                }
                stmt.step ();
            }
        }

        public static FieldType server_field_type (string declared) {
            string d = declared.strip ().down ();
            if (d.has_prefix ("timestamp") || d.has_prefix ("datetime")) return FieldType.DATETIME;
            if (d.has_prefix ("time")) return FieldType.TIME;
            if (d == "date") return FieldType.DATE;
            if (d == "boolean" || d == "bool" || d == "tinyint(1)" || d == "bit" || d == "bit(1)") return FieldType.BOOLEAN;
            if (d == "bytea" || d.contains ("blob") || d.contains ("binary")) return FieldType.ATTACHMENT;
            if (d == "money") return FieldType.CURRENCY;
            if (d.has_prefix ("json") || (d != "text" && d.has_suffix ("text"))) return FieldType.LONG_TEXT;
            if (d.contains ("char") || d == "text" || d == "uuid" || d.has_prefix ("enum") || d.has_prefix ("set(") || d.has_prefix ("inet")) return FieldType.TEXT;
            if (d.contains ("int") || d.has_suffix ("serial")) return FieldType.INTEGER;
            if (d.has_prefix ("numeric") || d.has_prefix ("decimal") || d.contains ("double") || d.contains ("real") || d.contains ("float")) return FieldType.NUMBER;
            return FieldType.from_declared (declared);
        }

        private static DbValue server_value (Field f, DbValue v) {
            if (v.is_null) return v;
            if (f.field_type == FieldType.BOOLEAN && v.kind == ValueKind.TEXT) {
                string t = v.text_value.down ();
                return new DbValue.bool (t == "t" || t == "true" || t == "1" || t == "y" || t == "yes");
            }
            if (v.kind == ValueKind.TEXT && !f.field_type.is_text () && f.field_type != FieldType.ATTACHMENT) {
                string t = v.text_value;
                if (f.field_type == FieldType.DATETIME && t.length > 19) t = t.substring (0, 19);
                try {
                    return Codec.parse (f, t.replace ("T", " "));
                } catch (Error e) {
                }
            }
            return v;
        }

        private static void load_server_link (Database db, LinkDef l, ServerSnapshot snap) throws Error {
            var def = new TableDef (l.name);
            var keys = new Gee.HashSet<string> ();
            foreach (string k in snap.key) keys.add (k);
            for (int i = 0; i < snap.columns.length; i++) {
                var f = new Field (snap.columns[i], server_field_type (snap.types[i]));
                f.primary_key = keys.contains (snap.columns[i]);
                def.fields.add (f);
            }
            db.exec ("DROP TABLE IF EXISTS temp.%s".printf (Sql.quote_ident (l.name)));
            db.exec (def.create_sql ().replace ("CREATE TABLE ", "CREATE TEMP TABLE "));
            string[] cols = {};
            string[] ph = {};
            foreach (var f in def.fields) {
                cols += Sql.quote_ident (f.name);
                ph += "?";
            }
            var stmt = db.prepare ("INSERT INTO temp.%s (%s) VALUES (%s)".printf (Sql.quote_ident (l.name), string.joinv (", ", cols), string.joinv (", ", ph)));
            foreach (var r in snap.rows) {
                stmt.reset ();
                stmt.clear_bindings ();
                for (int i = 0; i < def.fields.size; i++) Database.bind (stmt, i + 1, server_value (def.fields[i], r.get (i)));
                stmt.step ();
            }
            if (snap.key.length == 0) return;
            db.register_link_hook ();
            string[] key_new = {};
            string[] key_old = {};
            string[] all_new = {};
            foreach (var f in def.fields) {
                if (f.field_type == FieldType.ATTACHMENT) continue;
                string lit = Sql.quote_string (f.name);
                all_new += "%s, new.%s".printf (lit, Sql.quote_ident (f.name));
                if (keys.contains (f.name)) {
                    key_new += "%s, new.%s".printf (lit, Sql.quote_ident (f.name));
                    key_old += "%s, old.%s".printf (lit, Sql.quote_ident (f.name));
                }
            }
            string n = Sql.quote_string (l.name);
            string t = Sql.quote_ident (l.name);
            db.exec ("CREATE TEMP TRIGGER %s AFTER INSERT ON %s BEGIN SELECT sdb_link_change (%s, 'insert', json_object (%s), json_object (%s)); END".printf (Sql.quote_ident ("sdbsrv_i_" + l.name), t, n, string.joinv (", ", key_new), string.joinv (", ", all_new)));
            db.exec ("CREATE TEMP TRIGGER %s AFTER UPDATE ON %s BEGIN SELECT sdb_link_change (%s, 'update', json_object (%s), json_object (%s)); END".printf (Sql.quote_ident ("sdbsrv_u_" + l.name), t, n, string.joinv (", ", key_old), string.joinv (", ", all_new)));
            db.exec ("CREATE TEMP TRIGGER %s AFTER DELETE ON %s BEGIN SELECT sdb_link_change (%s, 'delete', json_object (%s), NULL); END".printf (Sql.quote_ident ("sdbsrv_d_" + l.name), t, n, string.joinv (", ", key_old)));
        }

        public static void add_server (Database db, string connection, string remote_schema, string table, string local_name, ServerSnapshot snap) throws Error {
            if (db.object_exists (local_name) || db.get_meta ("action:" + local_name) != null) throw new SchemaError.INVALID (_("An object named \"%s\" already exists.").printf (local_name));
            db.server_data[local_name.casefold ()] = snap;
            var links = list (db);
            var nl = new LinkDef (local_name, connection, table, "server");
            nl.remote_schema = remote_schema;
            links.add (nl);
            save (db, links);
            var l = db.linked[local_name.casefold ()];
            if (l == null || !l.available) {
                links.remove_at (links.size - 1);
                save (db, links);
                throw new SchemaError.INVALID (l != null && l.error != "" ? l.error : _("The table could not be linked."));
            }
        }

        public static void save (Database db, Gee.List<LinkDef> links) throws Error {
            db.save_object_meta (_("Change Linked Tables"), "", META_KEY, links.size > 0 ? to_json (links) : null);
            attach_all (db);
            db.invalidate ();
            db.schema_changed ();
        }

        public static void add (Database db, string path, string table, string? local_name = null, string kind = "database") throws Error {
            string name = local_name ?? table;
            if (db.object_exists (name) || db.get_meta ("action:" + name) != null) throw new SchemaError.INVALID (_("An object named \"%s\" already exists.").printf (name));
            if (kind == "database" && name.casefold () != table.casefold ()) throw new SchemaError.INVALID (_("A linked table keeps the name it has in its database."));
            var links = list (db);
            links.add (new LinkDef (name, relative (db, path), table, kind));
            save (db, links);
            var l = db.linked[name.casefold ()];
            if (l == null || !l.available) {
                links.remove_at (links.size - 1);
                save (db, links);
                throw new SchemaError.INVALID (l != null && l.error != "" ? l.error : _("The table could not be linked."));
            }
        }

        public static void remove (Database db, string name) throws Error {
            var links = list (db);
            var keep = new Gee.ArrayList<LinkDef> ();
            foreach (var l in links) {
                if (l.name.casefold () != name.casefold ()) keep.add (l);
            }
            db.linked.unset (name.casefold ());
            save (db, keep);
        }

        public static void relink (Database db, string old_path, string new_path) throws Error {
            var links = list (db);
            foreach (var l in links) {
                if (resolve (db, l.path) == resolve (db, old_path) || l.path == old_path) l.path = relative (db, new_path);
            }
            save (db, links);
        }

        public static Gee.ArrayList<string> tables_in (string path) throws Error {
            var other = Database.open (path);
            var names = other.table_names ();
            other.close ();
            return names;
        }

        public static string split (Database db, string backend_path) throws Error {
            if (db.path == ":memory:") throw new SchemaError.INVALID (_("Save the database before splitting it."));
            if (FileUtils.test (backend_path, FileTest.EXISTS)) FileUtils.remove (backend_path);
            var tables = new Gee.ArrayList<string> ();
            foreach (string t in db.table_names ()) {
                if (!db.is_linked (t)) tables.add (t);
            }
            if (tables.size == 0) throw new SchemaError.INVALID (_("There are no local tables to move."));
            var be = Database.create (backend_path);
            try {
                be.exec ("PRAGMA foreign_keys = OFF");
                foreach (string t in tables) {
                    var sql = db.query ("SELECT sql FROM main.sqlite_master WHERE type = 'table' AND name = ?", { new DbValue.text (t) });
                    be.exec (sql.rows[0].get (0).to_string ());
                    string? meta = db.get_meta ("table:" + t);
                    if (meta != null) be.set_meta ("table:" + t, meta);
                    string? views = db.get_meta ("views:" + t);
                    if (views != null) be.set_meta ("views:" + t, views);
                }
                be.close ();
                db.run ("ATTACH DATABASE ? AS sdbsplit", { new DbValue.text (backend_path) });
                try {
                    db.exec ("PRAGMA foreign_keys = OFF");
                    db.begin ();
                    foreach (string t in tables) {
                        string[] cols = db.stored_columns (t);
                        string[] q = {};
                        foreach (string c in cols) q += Sql.quote_ident (c);
                        string list_sql = string.joinv (", ", q);
                        db.exec ("INSERT INTO sdbsplit.%s (rowid, %s) SELECT rowid, %s FROM main.%s".printf (Sql.quote_ident (t), list_sql, list_sql, Sql.quote_ident (t)));
                        var extra = db.query ("SELECT sql FROM main.sqlite_master WHERE type IN ('index', 'trigger') AND tbl_name = ? AND sql IS NOT NULL", { new DbValue.text (t) });
                        foreach (var r in extra.rows) {
                            string s = r.get (0).to_string ();
                            string target = s.replace ("CREATE INDEX ", "CREATE INDEX sdbsplit.").replace ("CREATE UNIQUE INDEX ", "CREATE UNIQUE INDEX sdbsplit.").replace ("CREATE TRIGGER ", "CREATE TRIGGER sdbsplit.");
                            if (target != s) db.exec (target);
                        }
                    }
                    foreach (string t in tables) {
                        db.exec ("DROP TABLE main.%s".printf (Sql.quote_ident (t)));
                        db.set_meta ("table:" + t, null);
                        db.set_meta ("views:" + t, null);
                    }
                    var links = list (db);
                    foreach (string t in tables) links.add (new LinkDef (t, relative (db, backend_path), t));
                    db.set_meta (META_KEY, to_json (links));
                    db.commit ();
                } catch (Error e) {
                    db.rollback ();
                    throw e;
                } finally {
                    try {
                        db.exec ("PRAGMA foreign_keys = ON");
                        db.exec ("DETACH DATABASE sdbsplit");
                    } catch (Error e) {
                    }
                }
            } catch (Error e) {
                FileUtils.remove (backend_path);
                throw e;
            }
            db.clear_history ();
            attach_all (db);
            db.invalidate ();
            db.schema_changed ();
            return backend_path;
        }
    }
}
