# Writing `YamlValue`s as YAML text, in block style, with the comments and
# layout a `YamlDocument` keeps.

import "schema";
import "value";

## Writes `documents` as one YAML stream, each document started by `---`.
##
## @param documents the documents, each written as `YamlValue.to_string()`
##   writes it
## @returns the YAML text; empty for no documents
## @example
##     import yaml;
##
##     var text = yaml.write_all([yaml.YamlValue.Integer(1), yaml.YamlValue.String("two")]);
##     assert(text == "--- 1\n--- two\n", "two documents");
##     assert(yaml.parse_all(text).value().count == 2, "read back");
export write_all(documents: Array<YamlValue>): String {
    var out = StringBuilder();
    for (var document in documents) {
        var written = document.to_string();
        var block = (document is Mapping || document is Sequence) && written != "{}\n" && written != "[]\n";
        out.append(block || written.starts_with("|") ? "---\n" : "--- ");
        out.append(written);
    }
    return out.to_string();
}

# How a value was written, when not in the writer's default way.
const FLOW = 1;
const SINGLE_QUOTED = 2;
const DOUBLE_QUOTED = 3;

# A `|` or `>` scalar as it was written: its value, its header (`|-`,
# `>2`), the indentation indicator in it (0 for none), and its lines with
# the indentation taken off (blank lines empty).
struct _YamlBlock {
    var value: String;
    var header: String;
    var explicit: ulong;
    var lines: Array<String>;
}

# The comments and layout of a document, filed by the path of the value
# they belong to (`$.server.port`, as `_yaml_path_key` writes it): the
# comment and blank lines before it (`before`), the comment at the end of
# its line (`trailing`), and the lines closing a collection (`end`, with
# `$` for those after the whole document); how a scalar or collection was
# written when not in the default way (`styles`, `blocks`, and `plain`, the
# text of a plain scalar that is not a string, such as `0x1f` or `~`); and
# the indentation of nested mappings and of sequences under a key.
struct _YamlNotes {
    HashMap<String, Array<String>> before;
    HashMap<String, String> trailing;
    HashMap<String, Array<String>> end;
    HashMap<String, int> styles;
    HashMap<String, String> plain;
    HashMap<String, _YamlBlock> blocks;
    ulong indent;
    bool indent_seen;
    bool indent_sequences;
    bool sequences_seen;
    bool explicit_start;

    construct() {
        before = HashMap<String, Array<String>>();
        trailing = HashMap<String, String>();
        end = HashMap<String, Array<String>>();
        styles = HashMap<String, int>();
        plain = HashMap<String, String>();
        blocks = HashMap<String, _YamlBlock>();
        indent = 2;
        indent_sequences = true;
    }

    # Files `lines` under `path` in `kind`, after those already there.
    add(kind: HashMap<String, Array<String>>, path: String, lines: Array<String>) {
        if (lines.is_empty) {
            return;
        }
        var filed = kind.try_get(path);
        if (filed.is_empty()) {
            kind[path] = lines;
            return;
        }
        for (var line in lines) {
            filed.value().append(line);
        }
    }
}

# Writes `root` as a YAML document, with the comments and layout in
# `notes`.
_yaml_write(root: YamlValue, notes: _YamlNotes): String {
    var writer = _YamlWriter(notes);
    writer.document(root);
    return writer.out.to_string();
}

# Writes YAML text into `out`.
# shortcut: recursive, so a value nested some ten thousand deep overflows the stack; parse bounds what it reads to 256.
struct _YamlWriter {
    StringBuilder out;
    _YamlNotes notes;

    construct(notes: _YamlNotes) {
        out = StringBuilder();
        this.notes = notes;
    }

    document(root: YamlValue) {
        _lines(notes.before.try_get("$"), 0);
        if (notes.explicit_start) {
            out.append("---");
        }
        if (_is_block(root, "$")) {
            _trailing("$");
            if (notes.explicit_start || notes.trailing.contains("$")) {
                out.append("\n");
            }
            _block(root, "$", 0, "");
        } else {
            _scalar_after(root, "$", -1, notes.explicit_start);
            _lines(notes.end.try_get("$"), 0);
        }
    }

    # Writes the entries of the collection `value`, at column `indent`. The
    # first line starts with `lead` instead of the indentation when `lead`
    # is not empty.
    _block(value: YamlValue, path: String, indent: ulong, lead: String) {
        var first = true;
        if (value is Mapping(members)) {
            for (var (key, member) in members) {
                var key_path = _yaml_path_key(path, key);
                _lines(notes.before.try_get(key_path), indent);
                out.append(first && !lead.is_empty ? lead : " ".repeat(indent));
                out.append(_key(key));
                out.append(":");
                var child = indent + notes.indent;
                if (member is Sequence && !notes.indent_sequences) {
                    child = indent;
                }
                _after(member, key_path, indent, child);
                first = false;
            }
        } else if (value is Sequence(items)) {
            for (var index in 0..items.count) {
                var item = items[index];
                var item_path = $"{path}[{index}]";
                _lines(notes.before.try_get(item_path), indent);
                out.append(first && !lead.is_empty ? lead : " ".repeat(indent));
                out.append("-");
                first = false;
                if (_is_block(item, item_path)
                    && !notes.trailing.contains(item_path)
                    && !_has_lead_lines(item, item_path)) {
                    _block(item, item_path, indent + 2, " ");
                    continue;
                }
                _after(item, item_path, indent, indent + 2);
            }
        }
        _lines(notes.end.try_get(path), indent);
    }

    # Whether the first entry of the collection `value` has lines before
    # it, which cannot go on the line of a `-`.
    _has_lead_lines(value: YamlValue, path: String): bool {
        if (value is Mapping(members)) {
            for (var (key, member) in members) {
                return notes.before.contains(_yaml_path_key(path, key));
            }
        }
        return notes.before.contains($"{path}[0]");
    }

    # Writes what follows a key's `:` or a `-` for `value`, through the end
    # of its line, and a block collection's entries at column `child`.
    # `indent` is the column of the key or `-`.
    _after(value: YamlValue, path: String, indent: ulong, child: ulong) {
        if (_is_block(value, path)) {
            _trailing(path);
            out.append("\n");
            _block(value, path, child, "");
            return;
        }
        _scalar_after(value, path, indent as long, true);
    }

    # Writes a scalar or flow collection after a key, a `-` or `---`
    # (`space` puts a space first), through the end of its line, or a block
    # scalar's header and lines. `parent` is the column of the collection
    # holding it, -1 at the top.
    _scalar_after(value: YamlValue, path: String, parent: long, space: bool) {
        ulong base = parent < 0 ? 0 : parent as ulong;
        var string = value.as_string();
        if (string.is_value() && _is_literal(string.value(), path)) {
            var text = string.value();
            if (space) {
                out.append(" ");
            }
            var kept = notes.blocks.try_get(path);
            if (kept.is_value() && kept.value().value == text) {
                var block = kept.value();
                var at = block.explicit > 0 ? base + block.explicit : base + notes.indent;
                out.append(block.header);
                _trailing(path);
                out.append("\n");
                for (var line in block.lines) {
                    if (!line.is_empty) {
                        out.append(" ".repeat(at));
                        out.append(line);
                    }
                    out.append("\n");
                }
                return;
            }
            _literal(text, path, base + notes.indent, notes.indent);
            return;
        }
        var written = _inline(value, path, false);
        if (space && !written.is_empty) {
            out.append(" ");
        }
        out.append(written);
        _trailing(path);
        out.append("\n");
    }

    # Writes `text` as a `|` block scalar whose lines are at column `at`,
    # `relative` past its parent's column.
    _literal(text: String, path: String, at: ulong, relative: ulong) {
        var body = text;
        ulong trailing = 0;
        while (body.ends_with("\n")) {
            body = body.substr_bytes(0, body.size - 1);
            trailing = trailing + 1;
        }
        out.append("|");
        var lines = body.split("\n");
        for (var line in lines) {
            if (!line.is_empty) {
                if (line.byte_at(0) == ' ') {
                    out.append(to_string(relative));
                }
                break;
            }
        }
        if (trailing == 0) {
            out.append("-");
        } else if (trailing > 1) {
            out.append("+");
        }
        _trailing(path);
        out.append("\n");
        for (var line in lines) {
            if (!line.is_empty) {
                out.append(" ".repeat(at));
                out.append(line);
            }
            out.append("\n");
        }
        for (var index in 1..trailing) {
            out.append("\n");
        }
    }

    # Whether `text` is written as a block scalar: it has a line break, was
    # not quoted, and holds no character a block scalar cannot.
    _is_literal(text: String, path: String): bool {
        var kept = notes.blocks.try_get(path);
        if (kept.is_value() && kept.value().value == text) {
            return true;
        }
        var style = notes.styles.try_get(path);
        if (!text.contains("\n") || text.replace("\n", "").is_empty || (style.is_value() && style.value() != FLOW)) {
            return false;
        }
        for (var b in text.bytes()) {
            if ((b < 32 && b != '\n' && b != '\t') || b == 127) {
                return false;
            }
        }
        # A line of only spaces, or with spaces before a tab, could change
        # how the block's indentation is read; quote such text.
        for (var line in text.split("\n")) {
            if (!line.is_empty && line.trim().is_empty) {
                return false;
            }
        }
        return true;
    }

    # Whether `value` is written as a block collection: a mapping or
    # sequence with entries, not written in flow style.
    _is_block(value: YamlValue, path: String): bool {
        var style = notes.styles.try_get(path);
        if (style.is_value() && style.value() == FLOW) {
            return false;
        }
        match (value) {
            Mapping(members) => { return !members.is_empty; }
            Sequence(items) => { return !items.is_empty; }
            else => {}
        }
        return false;
    }

    # `value` on one line: a scalar, or a collection in flow style. `flow`
    # says it is inside a flow collection.
    _inline(value: YamlValue, path: String, flow: bool): String {
        var kept = notes.plain.try_get(path);
        if (kept.is_value() && _same(_yaml_resolve(kept.value()), value)) {
            return kept.value();
        }
        match (value) {
            Null => { return "null"; }
            Bool(flag) => { return flag ? "true" : "false"; }
            Integer(n) => { return to_string(n); }
            Float(n) => { return _yaml_float(n); }
            String(text) => { return _string(text, path, flow); }
            Sequence(items) => {
                var out = StringBuilder();
                out.append("[");
                for (var index in 0..items.count) {
                    if (index > 0) {
                        out.append(", ");
                    }
                    out.append(_inline(items[index], $"{path}[{index}]", true));
                }
                out.append("]");
                return out.to_string();
            }
            Mapping(members) => {
                var out = StringBuilder();
                out.append("{");
                var first = true;
                for (var (key, member) in members) {
                    if (!first) {
                        out.append(", ");
                    }
                    first = false;
                    out.append(_plain_safe(key, true, true) ? key : _yaml_double_quoted(key));
                    out.append(": ");
                    out.append(_inline(member, _yaml_path_key(path, key), true));
                }
                out.append("}");
                return out.to_string();
            }
        }
        return "";
    }

    # A string on one line: plain when it reads back as itself, else in the
    # quotes it was written in, or double quotes.
    _string(text: String, path: String, flow: bool): String {
        var style = notes.styles.try_get(path);
        var single = style.is_value() && style.value() == SINGLE_QUOTED;
        var double = style.is_value() && style.value() == DOUBLE_QUOTED;
        if (single && _single_safe(text)) {
            return "'" + text.replace("'", "''") + "'";
        }
        if (!single && !double && _plain_safe(text, flow, false)) {
            return text;
        }
        return _yaml_double_quoted(text);
    }

    # A key, plain when it can be.
    _key(key: String): String {
        if (_plain_safe(key, false, true)) {
            return key;
        }
        return _yaml_double_quoted(key);
    }

    # Writes `lines` (comment lines, or empty for blank lines) at column
    # `indent`.
    _lines(lines: Array<String>?, indent: ulong) {
        if (lines.is_empty()) {
            return;
        }
        for (var line in lines.value()) {
            if (!line.is_empty) {
                out.append(" ".repeat(indent));
                out.append(line);
            }
            out.append("\n");
        }
    }

    # Writes the comment at the end of the line of the value at `path`.
    _trailing(path: String) {
        var comment = notes.trailing.try_get(path);
        if (comment.is_value()) {
            out.append(" ");
            out.append(comment.value());
        }
    }
}

# Whether `text` can be written as a plain scalar and read back as the same
# string (`key` for a mapping key, which is a string however it reads;
# `flow` inside a flow collection).
_plain_safe(text: String, flow: bool, key: bool): bool {
    if (text.is_empty || (!key && (!(_yaml_resolve(text) is String) || _yaml_is_old_boolean(text)))) {
        return false;
    }
    if (text.starts_with("---") || text.starts_with("...")) {
        return false;
    }
    var size = text.size;
    var first = text.byte_at(0);
    var second = size > 1 ? text.byte_at(1) : ' ' as byte;
    if ((first == '-' || first == '?' || first == ':') && (second == ' ' || second == '\t')) {
        return false;
    }
    if (first == ',' || first == '[' || first == ']' || first == '{' || first == '}' || first == '#') {
        return false;
    }
    if (first == '&' || first == '*' || first == '!' || first == '|' || first == '>') {
        return false;
    }
    if (first == '\'' || first == '"' || first == '%' || first == '@' || first == '`') {
        return false;
    }
    var last = text.byte_at(size - 1);
    if (first == ' ' || first == '\t' || last == ' ' || last == '\t' || last == ':') {
        return false;
    }
    for (var index in 0..size) {
        var b = text.byte_at(index);
        if (b < 32 || b == 127) {
            return false;
        }
        var next = index + 1 < size ? text.byte_at(index + 1) : ' ' as byte;
        if (b == ':' && (next == ' ' || next == '\t')) {
            return false;
        }
        if (b == '#' && index > 0 && (text.byte_at(index - 1) == ' ' || text.byte_at(index - 1) == '\t')) {
            return false;
        }
        var indicator = b == ',' || b == '[' || b == ']' || b == '{' || b == '}';
        if (flow
            && (indicator || (b == ':' && (next == ',' || next == '[' || next == ']' || next == '{' || next == '}')))) {
            return false;
        }
    }
    return true;
}

# Whether YAML 1.1 reads `text` as a boolean, as `yes` and `off`: quoted,
# so that older readers see a string too.
_yaml_is_old_boolean(text: String): bool {
    var lower = text.lower();
    return lower == "y" || lower == "n" || lower == "yes" || lower == "no" || lower == "on" || lower == "off";
}

# Whether `text` can be written between single quotes, which hold no
# escapes.
_single_safe(text: String): bool {
    for (var b in text.bytes()) {
        if (b < 32 || b == 127) {
            return false;
        }
    }
    return true;
}

# A float as YAML spells it: `.inf`, `-.inf`, `.nan`, or a number with a
# `.` or an exponent, so it reads back as a float.
_yaml_float(number: double): String {
    if (number != number) {
        return ".nan";
    }
    if (number - number != 0.0) {
        return number > 0.0 ? ".inf" : "-.inf";
    }
    var spelled = to_string(number);
    if (_yaml_resolve(spelled) is Float) {
        return spelled;
    }
    return spelled + ".0";
}

# Whether two scalars are the same value; NaN is the same as NaN.
_same(a: YamlValue, b: YamlValue): bool {
    match (a) {
        Null => { return b is Null; }
        Bool(x) => { return b.as_bool().is_value() && b.as_bool().value() == x; }
        Integer(x) => { return b.as_int().is_value() && b.as_int().value() == x; }
        Float(x) => {
            if (!(b is Float)) {
                return false;
            }
            var y = b.as_float().value();
            return x == y || (x != x && y != y);
        }
        else => {}
    }
    return false;
}
