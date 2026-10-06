namespace Singularity.Apps.Database {

    public class OfficeCrypt {
        [CCode (cname = "sdb_office_aes_decrypt")]
        private static extern int c_aes (uint8* key, int key_len, uint8* iv, uint8* data, int len);

        private const int STRUCTURE_OFFSET = 0x299;
        private const uint8[] VERIFIER_INPUT_BLOCK = { 0xfe, 0xa7, 0xd2, 0x76, 0x3b, 0x4b, 0x9e, 0x79 };
        private const uint8[] VERIFIER_VALUE_BLOCK = { 0xd7, 0xaa, 0x0f, 0x6d, 0x30, 0x61, 0x34, 0x4e };
        private const uint8[] KEY_VALUE_BLOCK = { 0x14, 0x6e, 0x0b, 0xe7, 0xab, 0xac, 0xd0, 0xd6 };

        public enum Kind {
            RC4_CRYPTOAPI,
            STANDARD_AES,
            AGILE;

            public string label () {
                switch (this) {
                    case RC4_CRYPTOAPI: return "RC4 CryptoAPI";
                    case STANDARD_AES: return "AES";
                    default: return "Agile AES";
                }
            }
        }

        public Kind kind;
        private uint8[] encoding_key;
        private uint8[] base_hash;
        private int key_bytes;
        private uint8[] key_value;
        private uint8[] data_salt;
        private ChecksumType data_hash = ChecksumType.SHA1;
        private int block_size = 16;

        public static bool is_encrypted (uint8[] data, uint8[] header_plain) {
            if (data.length < 4096 || data[0x14] < 2) return false;
            int at = 0x3E - 0x18;
            if (header_plain.length < at + 4) return false;
            for (int i = 0; i < 4; i++) {
                if (header_plain[at + i] != 0) return true;
            }
            return false;
        }

        private static uint32 u32 (uint8[] b, int at) {
            return (uint32) b[at] | ((uint32) b[at + 1] << 8) | ((uint32) b[at + 2] << 16) | ((uint32) b[at + 3] << 24);
        }

        private static uint16 u16 (uint8[] b, int at) {
            return (uint16) (b[at] | (b[at + 1] << 8));
        }

        public static uint8[] password_bytes (string password) {
            var out_b = new ByteArray ();
            int i = 0;
            int n = 0;
            unichar ch;
            while (password.get_next_char (ref i, out ch) && n < 255) {
                if (ch > 0xFFFF) {
                    uint32 v = ch - 0x10000;
                    uint16 hi = (uint16) (0xD800 + (v >> 10));
                    uint16 lo = (uint16) (0xDC00 + (v & 0x3FF));
                    out_b.append ({ (uint8) (hi & 0xff), (uint8) (hi >> 8), (uint8) (lo & 0xff), (uint8) (lo >> 8) });
                } else {
                    out_b.append ({ (uint8) (ch & 0xff), (uint8) ((ch >> 8) & 0xff) });
                }
                n++;
            }
            return out_b.data;
        }

        public static uint8[] hash (ChecksumType t, uint8[] a, uint8[]? b = null) {
            var c = new Checksum (t);
            c.update (a, a.length);
            if (b != null) c.update (b, b.length);
            size_t len = 64;
            uint8[] buf = new uint8[64];
            c.get_digest (buf, ref len);
            return buf[0:len];
        }

        private static uint8[] fix (uint8[] b, int len, uint8 pad) {
            uint8[] r = new uint8[len];
            for (int i = 0; i < len; i++) r[i] = i < b.length ? b[i] : pad;
            return r;
        }

        private static uint8[] le32 (uint32 v) {
            return { (uint8) (v & 0xff), (uint8) ((v >> 8) & 0xff), (uint8) ((v >> 16) & 0xff), (uint8) ((v >> 24) & 0xff) };
        }

        private static uint8[] iterate (ChecksumType t, uint8[] base_h, int iterations) {
            uint8[] h = base_h;
            for (int i = 0; i < iterations; i++) h = hash (t, le32 ((uint32) i), h);
            return h;
        }

        private static uint8[] aes (uint8[] key, uint8[]? iv, uint8[] input) throws MdbError {
            uint8[] out_b = input;
            int len = out_b.length - out_b.length % 16;
            if (len == 0) return out_b;
            uint8[]? chain = iv != null ? fix (iv, 16, 0x36) : null;
            if (c_aes ((uint8*) key, key.length, chain != null ? (uint8*) chain : null, (uint8*) out_b, len) != 0) throw new MdbError.UNSUPPORTED (_("This Access database uses an encryption key size that is not supported."));
            return out_b;
        }

        private static ChecksumType checksum_for (string name) throws MdbError {
            switch (name.up ().replace ("-", "")) {
                case "SHA1": return ChecksumType.SHA1;
                case "SHA256": return ChecksumType.SHA256;
                case "SHA384": return ChecksumType.SHA384;
                case "SHA512": return ChecksumType.SHA512;
                case "MD5": return ChecksumType.MD5;
                default: throw new MdbError.UNSUPPORTED (_("This Access database uses the hash algorithm %s, which is not supported.").printf (name));
            }
        }

        private static string attr (string element, string name) {
            try {
                MatchInfo mi;
                if (new Regex ("[\\s:]" + name + "=\"([^\"]*)\"").match (element, 0, out mi)) return mi.fetch (1);
            } catch (RegexError e) {
            }
            return "";
        }

        private static string element (string xml, string tag) {
            try {
                MatchInfo mi;
                if (new Regex ("<(?:\\w+:)?" + tag + "\\s[^>]*>").match (xml, 0, out mi)) return mi.fetch (0);
            } catch (RegexError e) {
            }
            return "";
        }

        private uint8[] block_key (int page) {
            uint8[] b = le32 ((uint32) page);
            for (int i = 0; i < 4; i++) b[i] ^= encoding_key[i];
            return b;
        }

        private uint8[] standard_key (uint8[] block) {
            if (kind == Kind.RC4_CRYPTOAPI) {
                uint8[] k = fix (hash (ChecksumType.SHA1, base_hash, block), key_bytes, 0);
                if (key_bytes == 5) k = fix (k, 16, 0);
                return k;
            }
            uint8[] final_h = hash (ChecksumType.SHA1, base_hash, block);
            uint8[] x1 = new uint8[64];
            uint8[] x2 = new uint8[64];
            for (int i = 0; i < 64; i++) {
                x1[i] = 0x36;
                x2[i] = 0x5C;
            }
            for (int i = 0; i < final_h.length; i++) {
                x1[i] ^= final_h[i];
                x2[i] ^= final_h[i];
            }
            var both = new ByteArray ();
            both.append (hash (ChecksumType.SHA1, x1));
            both.append (hash (ChecksumType.SHA1, x2));
            return fix (both.data, key_bytes, 0);
        }

        public static OfficeCrypt open (uint8[] data, uint8[] header_plain, string? password) throws MdbError {
            var oc = new OfficeCrypt ();
            int at = 0x3E - 0x18;
            oc.encoding_key = header_plain[at:at + 4];
            int info_len = u16 (data, STRUCTURE_OFFSET);
            int start = STRUCTURE_OFFSET + 2;
            if (info_len < 8 || start + info_len > 4096) throw new MdbError.FORMAT (_("The encryption information of this Access database is damaged."));
            uint8[] info = data[start:start + info_len];
            int major = u16 (info, 0);
            int minor = u16 (info, 2);
            if (password == null) throw new MdbError.PASSWORD (_("This Access database is protected with a password."));
            uint8[] pwd = password_bytes (password);
            bool ok;
            if (major == 4 && minor == 4) {
                ok = oc.setup_agile (info, pwd);
            } else if ((major == 2 || major == 3 || major == 4) && minor == 2) {
                ok = oc.setup_standard (info, pwd);
            } else {
                throw new MdbError.UNSUPPORTED (_("This Access database uses encryption version %d.%d, which is not supported.").printf (major, minor));
            }
            if (!ok) throw new MdbError.PASSWORD (_("The password is not correct."));
            return oc;
        }

        private bool setup_standard (uint8[] info, uint8[] pwd) throws MdbError {
            uint32 flags = u32 (info, 4);
            if ((flags & 0x04) == 0) throw new MdbError.UNSUPPORTED (_("This Access database uses an encryption method that is not supported."));
            int header_len = (int) u32 (info, 8);
            int h = 12;
            if (h + header_len + 4 > info.length) throw new MdbError.FORMAT (_("The encryption information of this Access database is damaged."));
            uint32 alg = u32 (info, h + 8);
            uint32 key_size = u32 (info, h + 16);
            bool is_aes = (flags & 0x20) != 0 || alg == 0x660E || alg == 0x660F || alg == 0x6610;
            kind = is_aes ? Kind.STANDARD_AES : Kind.RC4_CRYPTOAPI;
            if (key_size == 0) {
                if (is_aes) {
                    key_size = alg == 0x6610 ? 256 : (alg == 0x660F ? 192 : 128);
                } else {
                    key_size = 40;
                }
            }
            key_bytes = (int) key_size / 8;
            int v = h + header_len;
            int salt_size = (int) u32 (info, v);
            if (salt_size != 16 || v + 4 + 32 + 4 > info.length) throw new MdbError.FORMAT (_("The encryption information of this Access database is damaged."));
            uint8[] salt = info[v + 4:v + 20];
            uint8[] enc_verifier = info[v + 20:v + 36];
            int hash_size = (int) u32 (info, v + 36);
            int enc_hash_len = is_aes ? 32 : 20;
            if (hash_size < 16 || hash_size > enc_hash_len || v + 40 + enc_hash_len > info.length) throw new MdbError.FORMAT (_("The encryption information of this Access database is damaged."));
            uint8[] enc_hash = info[v + 40:v + 40 + enc_hash_len];
            base_hash = hash (ChecksumType.SHA1, salt, pwd);
            if (is_aes && (flags & 0x20) != 0) base_hash = iterate (ChecksumType.SHA1, base_hash, 50000);
            if (check_standard (le32 (0), is_aes, enc_verifier, enc_hash, hash_size)) return true;
            return is_aes && check_standard (le32 (49999), is_aes, enc_verifier, enc_hash, hash_size);
        }

        private bool check_standard (uint8[] block, bool is_aes, uint8[] enc_verifier, uint8[] enc_hash, int hash_size) throws MdbError {
            uint8[] k0 = standard_key (block);
            uint8[] verifier;
            uint8[] verifier_hash;
            if (is_aes) {
                verifier = aes (k0, null, enc_verifier);
                verifier_hash = aes (k0, null, enc_hash);
            } else {
                var both = new ByteArray ();
                both.append (enc_verifier);
                both.append (enc_hash);
                uint8[] plain = MdbCodec.rc4 (k0, both.data);
                verifier = plain[0:16];
                verifier_hash = plain[16:plain.length];
            }
            uint8[] test = fix (hash (ChecksumType.SHA1, verifier), hash_size, 0);
            return Memory.cmp (fix (verifier_hash, hash_size, 0), test, hash_size) == 0;
        }

        private bool setup_agile (uint8[] info, uint8[] pwd) throws MdbError {
            if (info.length < 8 || u32 (info, 4) != 0x40) throw new MdbError.FORMAT (_("The encryption information of this Access database is damaged."));
            var sb = new StringBuilder ();
            sb.append_len ((string) ((uint8*) info + 8), info.length - 8);
            string xml = sb.str.make_valid ();
            string kd = element (xml, "keyData");
            string ke = element (xml, "encryptedKey");
            if (kd == "" || ke == "") throw new MdbError.FORMAT (_("The encryption information of this Access database is damaged."));
            if (attr (kd, "cipherAlgorithm").up () != "AES" || attr (ke, "cipherAlgorithm").up () != "AES") throw new MdbError.UNSUPPORTED (_("This Access database uses the cipher %s, which is not supported.").printf (attr (kd, "cipherAlgorithm")));
            if (attr (kd, "cipherChaining") != "ChainingModeCBC" || attr (ke, "cipherChaining") != "ChainingModeCBC") throw new MdbError.UNSUPPORTED (_("This Access database uses a cipher mode that is not supported."));
            data_hash = checksum_for (attr (kd, "hashAlgorithm"));
            data_salt = Base64.decode (attr (kd, "saltValue"));
            block_size = int.parse (attr (kd, "blockSize"));
            if (block_size != 16) block_size = 16;
            var pwd_hash = checksum_for (attr (ke, "hashAlgorithm"));
            uint8[] salt = Base64.decode (attr (ke, "saltValue"));
            int spin = int.parse (attr (ke, "spinCount"));
            int kbytes = int.parse (attr (ke, "keyBits")) / 8;
            int data_kbytes = int.parse (attr (kd, "keyBits")) / 8;
            if (spin < 0 || spin > 10000000 || kbytes <= 0 || data_kbytes <= 0) throw new MdbError.FORMAT (_("The encryption information of this Access database is damaged."));
            uint8[] iter_h = iterate (pwd_hash, hash (pwd_hash, salt, pwd), spin);
            uint8[] k_in = fix (hash (pwd_hash, iter_h, VERIFIER_INPUT_BLOCK), kbytes, 0x36);
            uint8[] k_val = fix (hash (pwd_hash, iter_h, VERIFIER_VALUE_BLOCK), kbytes, 0x36);
            uint8[] k_key = fix (hash (pwd_hash, iter_h, KEY_VALUE_BLOCK), kbytes, 0x36);
            uint8[] verifier = aes (k_in, salt, Base64.decode (attr (ke, "encryptedVerifierHashInput")));
            uint8[] verifier_hash = aes (k_val, salt, Base64.decode (attr (ke, "encryptedVerifierHashValue")));
            uint8[] test = hash (pwd_hash, verifier);
            if (test.length % 16 != 0) test = fix (test, (test.length + 15) / 16 * 16, 0);
            if (verifier_hash.length != test.length || Memory.cmp (verifier_hash, test, test.length) != 0) return false;
            uint8[] kv = aes (k_key, salt, Base64.decode (attr (ke, "encryptedKeyValue")));
            if (kv.length < data_kbytes) throw new MdbError.FORMAT (_("The encryption information of this Access database is damaged."));
            key_value = kv[0:data_kbytes];
            kind = Kind.AGILE;
            return true;
        }

        public void decrypt_page (uint8[] data, int offset, int size, int page) throws MdbError {
            uint8[] block = block_key (page);
            uint8[] chunk = data[offset:offset + size];
            uint8[] plain;
            switch (kind) {
                case Kind.RC4_CRYPTOAPI:
                    plain = MdbCodec.rc4 (standard_key (block), chunk);
                    break;
                case Kind.STANDARD_AES:
                    plain = aes (standard_key (block), null, chunk);
                    break;
                default:
                    plain = aes (key_value, fix (hash (data_hash, data_salt, block), block_size, 0x36), chunk);
                    break;
            }
            Memory.copy ((uint8*) data + offset, plain, size);
        }
    }
}
