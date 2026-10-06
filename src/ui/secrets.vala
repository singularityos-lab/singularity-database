namespace Singularity.Apps.Database {

    public class ConnectionSecrets {
        private static Secret.Schema schema () {
            return new Secret.Schema ("dev.sinty.database.Connection", Secret.SchemaFlags.NONE,
                "connection", Secret.SchemaAttributeType.STRING,
                "purpose", Secret.SchemaAttributeType.STRING);
        }

        public static string unavailable_message (Error e) {
            if (e is DBusError.SERVICE_UNKNOWN || e is DBusError.NAME_HAS_NO_OWNER || e is DBusError.SPAWN_EXEC_FAILED || e is DBusError.SPAWN_SERVICE_NOT_FOUND) {
                return _("The system keyring is not running, so the password was not saved.");
            }
            return _("The password could not be saved in the keyring: %s").printf (e.message);
        }

        public static async string? lookup (string id, string purpose) {
            if (id == "") return null;
            try {
                return yield Secret.password_lookup (schema (), null, "connection", id, "purpose", purpose);
            } catch (Error e) {
                return null;
            }
        }

        public static async void store (ConnectionConfig c, string purpose, string? password) throws Error {
            if (password == null || password == "") {
                yield clear (c.id, purpose);
                return;
            }
            string label = purpose == "ssh" ? _("Database SSH: %s").printf (c.name) : _("Database: %s").printf (c.name);
            yield Secret.password_store (schema (), Secret.COLLECTION_DEFAULT, label, password, null, "connection", c.id, "purpose", purpose);
        }

        public static async void clear (string id, string purpose) {
            try {
                yield Secret.password_clear (schema (), null, "connection", id, "purpose", purpose);
            } catch (Error e) {
            }
        }
    }
}
