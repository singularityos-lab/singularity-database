namespace Singularity.Apps.Database {

    public errordomain CryptError {
        PASSWORD_REQUIRED
    }

    public class Crypt {
        public const string VFS = "sdbcrypt";
        public const int RESERVE = 32;

        [CCode (cname = "sdb_crypt_register")]
        private static extern int c_register ();

        [CCode (cname = "sdb_crypt_set_key")]
        private static extern int c_set_key (string path, string password);

        [CCode (cname = "sdb_crypt_clear_key")]
        private static extern void c_clear_key (string path);

        [CCode (cname = "sdb_crypt_is_encrypted")]
        private static extern int c_is_encrypted (string path);

        [CCode (cname = "sdb_crypt_set_reserve")]
        private static extern int c_set_reserve (Sqlite.Database db, int n);

        public static void register () throws Error {
            if (c_register () != Sqlite.OK) throw new SchemaError.SQL (_("Encryption is not available."));
        }

        public static bool is_encrypted (string path) {
            return c_is_encrypted (path) != 0;
        }

        public static void set_key (string path, string password) throws Error {
            if (c_set_key (path, password) != Sqlite.OK) throw new SchemaError.SQL (_("Encryption is not available."));
        }

        public static void clear_key (string path) {
            c_clear_key (path);
        }

        public static void set_reserve (Sqlite.Database db, int n) throws Error {
            if (c_set_reserve (db, n) != Sqlite.OK) throw new SchemaError.SQL (db.errmsg ());
        }

        public static string temp_path (string path, string tag) {
            return Path.build_filename (Path.get_dirname (path), ".%s.%s-%08x".printf (Path.get_basename (path), tag, Random.next_int ()));
        }
    }
}
