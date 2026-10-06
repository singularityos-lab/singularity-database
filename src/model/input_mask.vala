namespace Singularity.Apps.Database {

    public class MaskSlot {
        public char code;
        public string literal = "";
        public int case_mode;

        public bool is_literal () {
            return literal != "";
        }

        public bool required () {
            return code == '0' || code == 'L' || code == 'A' || code == '&';
        }

        public bool accepts (unichar c) {
            switch (code) {
                case '0':
                case '9': return c.isdigit ();
                case '#': return c.isdigit () || c == ' ' || c == '+' || c == '-';
                case 'L':
                case '?': return c.isalpha ();
                case 'A':
                case 'a': return c.isalnum ();
                case '&':
                case 'C': return true;
                default: return false;
            }
        }
    }

    public class InputMask {
        public Gee.ArrayList<MaskSlot> slots = new Gee.ArrayList<MaskSlot> ();
        public bool store_literals;
        public string placeholder = "_";
        public bool password;
        public string source = "";

        public static InputMask? parse (string text) {
            string t = text.strip ();
            if (t == "") return null;
            var m = new InputMask ();
            m.source = t;
            if (t.down () == "password") {
                m.password = true;
                return m;
            }
            string[] parts = split (t);
            string mask = parts[0];
            if (parts.length > 1) m.store_literals = parts[1].strip () == "0";
            if (parts.length > 2 && parts[2] != "") m.placeholder = parts[2].substring (0, 1);
            int case_mode = 0;
            int i = 0;
            while (i < mask.length) {
                char c = mask[i];
                if (c == '\\' && i + 1 < mask.length) {
                    var s = new MaskSlot ();
                    s.literal = mask.substring (i + 1, 1);
                    m.slots.add (s);
                    i += 2;
                    continue;
                }
                if (c == '"') {
                    int close = mask.index_of_char ('"', i + 1);
                    if (close < 0) close = mask.length;
                    string lit = mask.substring (i + 1, close - i - 1);
                    int k = 0;
                    unichar u;
                    while (lit.get_next_char (ref k, out u)) {
                        var s = new MaskSlot ();
                        s.literal = u.to_string ();
                        m.slots.add (s);
                    }
                    i = close + 1;
                    continue;
                }
                if (c == '<') {
                    case_mode = case_mode == 1 ? 0 : 1;
                    if (i + 1 < mask.length && mask[i + 1] == '>') {
                        case_mode = 0;
                        i++;
                    }
                    i++;
                    continue;
                }
                if (c == '>') {
                    case_mode = 2;
                    i++;
                    continue;
                }
                if (c == '!') {
                    i++;
                    continue;
                }
                var s = new MaskSlot ();
                if ("09#L?Aa&C".index_of_char (c) >= 0) {
                    s.code = c;
                    s.case_mode = case_mode;
                } else {
                    s.literal = c.to_string ();
                }
                m.slots.add (s);
                i++;
            }
            return m;
        }

        private static string[] split (string t) {
            string[] parts = {};
            var sb = new StringBuilder ();
            bool quote = false;
            for (int i = 0; i < t.length; i++) {
                char c = t[i];
                if (c == '"') quote = !quote;
                if (c == '\\' && i + 1 < t.length) {
                    sb.append_c (c);
                    sb.append_c (t[++i]);
                    continue;
                }
                if (c == ';' && !quote) {
                    parts += sb.str;
                    sb.truncate ();
                    continue;
                }
                sb.append_c (c);
            }
            parts += sb.str;
            return parts;
        }

        public string template () {
            var sb = new StringBuilder ();
            foreach (var s in slots) sb.append (s.is_literal () ? s.literal : placeholder);
            return sb.str;
        }

        public string apply (string input) throws InputError {
            if (password) return input;
            var chars = new Gee.ArrayList<unichar> ();
            int k = 0;
            unichar u;
            while (input.get_next_char (ref k, out u)) chars.add (u);
            var stored = new StringBuilder ();
            int ci = 0;
            foreach (var s in slots) {
                if (s.is_literal ()) {
                    if (ci < chars.size && chars[ci].to_string () == s.literal) ci++;
                    if (store_literals) stored.append (s.literal);
                    continue;
                }
                while (ci < chars.size && placeholder != "" && chars[ci].to_string () == placeholder && !s.accepts (chars[ci])) ci++;
                if (ci < chars.size && s.accepts (chars[ci])) {
                    unichar c = chars[ci++];
                    if (s.case_mode == 1) c = c.tolower ();
                    else if (s.case_mode == 2) c = c.toupper ();
                    stored.append_unichar (c);
                    continue;
                }
                if (s.required ()) throw new InputError.INVALID (_("The value does not match the input mask %s.").printf (source));
            }
            while (ci < chars.size && (chars[ci] == ' ' || chars[ci].to_string () == placeholder)) ci++;
            if (ci < chars.size) throw new InputError.INVALID (_("The value does not match the input mask %s.").printf (source));
            return stored.str;
        }

        public string display (string stored) {
            if (password) return string.nfill (stored.char_count (), '*');
            if (store_literals) return stored;
            var chars = new Gee.ArrayList<unichar> ();
            int k = 0;
            unichar u;
            while (stored.get_next_char (ref k, out u)) chars.add (u);
            var sb = new StringBuilder ();
            int ci = 0;
            foreach (var s in slots) {
                if (s.is_literal ()) {
                    sb.append (s.literal);
                    continue;
                }
                if (ci < chars.size) sb.append_unichar (chars[ci++]);
                else if (s.required ()) sb.append (placeholder);
            }
            while (ci < chars.size) sb.append_unichar (chars[ci++]);
            return sb.str;
        }
    }
}
