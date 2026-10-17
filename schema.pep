# The YAML 1.2 core schema: what a plain scalar means (`null`, `true`,
# `0x1f`, `.inf`, or a string), shared by the parser and the writer, and
# how a value's path in a document is written.

import "value";

# What the plain scalar `text` means under the core schema.
export _yaml_resolve(text: String): YamlValue {
    if (text.is_empty || text == "~" || text == "null" || text == "Null" || text == "NULL") {
        return YamlValue.Null;
    }
    if (text == "true" || text == "True" || text == "TRUE") {
        return YamlValue.Bool(true);
    }
    if (text == "false" || text == "False" || text == "FALSE") {
        return YamlValue.Bool(false);
    }
    var number = _yaml_number(text);
    if (number.is_value()) {
        return number.value();
    }
    return YamlValue.String(text);
}

# The integer or float `text` spells under the core schema, or none.
export _yaml_number(text: String): YamlValue? {
    var size = text.size;
    if (size > 2 && text.byte_at(0) == '0' && (text.byte_at(1) == 'o' || text.byte_at(1) == 'x')) {
        var base = text.byte_at(1) == 'o' ? 8 : 16;
        var digits = text.substr_bytes(2, size - 2);
        for (var b in digits.bytes()) {
            if (_yaml_digit(b) < 0 || _yaml_digit(b) >= base) {
                return Optional<YamlValue>.Empty;
            }
        }
        var parsed = long.parse(digits, base);
        if (parsed.is_empty()) {
            # shortcut: past 2^63 - 1 is a string, as no long holds it; read it as a float if someone needs it.
            return Optional<YamlValue>.Empty;
        }
        return Optional<YamlValue>.Value(YamlValue.Integer(parsed.value()));
    }
    ulong start = 0;
    var negative = false;
    if (size > 0 && (text.byte_at(0) == '-' || text.byte_at(0) == '+')) {
        negative = text.byte_at(0) == '-';
        start = 1;
    }
    var rest = text.substr_bytes(start, size - start);
    if (rest == ".inf" || rest == ".Inf" || rest == ".INF") {
        return Optional<YamlValue>.Value(YamlValue.Float(negative ? -1.0 / 0.0 : 1.0 / 0.0));
    }
    if (start == 0 && (rest == ".nan" || rest == ".NaN" || rest == ".NAN")) {
        return Optional<YamlValue>.Value(YamlValue.Float(0.0 / 0.0));
    }
    # [0-9]* ( . [0-9]* )? ( [eE] [-+]? [0-9]+ )?, with a digit before the
    # exponent.
    var index = start;
    var whole = 0;
    while (index < size && _yaml_is_decimal(text.byte_at(index))) {
        index = index + 1;
        whole = whole + 1;
    }
    if (index == size) {
        if (whole == 0) {
            return Optional<YamlValue>.Empty;
        }
        var parsed = long.parse(text);
        if (parsed.is_value()) {
            return Optional<YamlValue>.Value(YamlValue.Integer(parsed.value()));
        }
        # An integer past a long reads as the float nearest it.
        return Optional<YamlValue>.Value(YamlValue.Float(double.parse(text).value()));
    }
    var fraction = 0;
    if (text.byte_at(index) == '.') {
        index = index + 1;
        while (index < size && _yaml_is_decimal(text.byte_at(index))) {
            index = index + 1;
            fraction = fraction + 1;
        }
    }
    if (whole + fraction == 0) {
        return Optional<YamlValue>.Empty;
    }
    if (index < size && (text.byte_at(index) == 'e' || text.byte_at(index) == 'E')) {
        index = index + 1;
        if (index < size && (text.byte_at(index) == '-' || text.byte_at(index) == '+')) {
            index = index + 1;
        }
        var exponent = 0;
        while (index < size && _yaml_is_decimal(text.byte_at(index))) {
            index = index + 1;
            exponent = exponent + 1;
        }
        if (exponent == 0) {
            return Optional<YamlValue>.Empty;
        }
    }
    if (index < size) {
        return Optional<YamlValue>.Empty;
    }
    var parsed = double.parse(text);
    if (parsed.is_empty()) {
        return Optional<YamlValue>.Empty;
    }
    return Optional<YamlValue>.Value(YamlValue.Float(parsed.value()));
}

# The value of hexadecimal digit `b`, or -1.
export _yaml_digit(b: byte): int {
    if (b >= '0' && b <= '9') {
        return (b - '0') as int;
    }
    if (b >= 'a' && b <= 'f') {
        return (b - 'a') as int + 10;
    }
    if (b >= 'A' && b <= 'F') {
        return (b - 'A') as int + 10;
    }
    return -1;
}

# `path.key`, or `path["key"]` when the key is not an identifier: how a
# value's path in a document is written, as `json` writes it.
export _yaml_path_key(path: String, key: String): String {
    var plain = !key.is_empty;
    for (var b in key.bytes()) {
        var letter = (b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z') || b == '_';
        if (!letter && !(b >= '0' && b <= '9')) {
            plain = false;
        }
    }
    if (plain) {
        return $"{path}.{key}";
    }
    return $"{path}[{_yaml_double_quoted(key)}]";
}

# `text` as a double-quoted YAML scalar, with escapes for `"`, `\` and
# control characters.
export _yaml_double_quoted(text: String): String {
    var out = StringBuilder();
    out.append("\"");
    var start: ulong = 0;
    var index: ulong = 0;
    var size = text.size;
    while (index < size) {
        var b = text.byte_at(index);
        var escape = "";
        if (b == '"') {
            escape = "\\\"";
        } else if (b == '\\') {
            escape = "\\\\";
        } else if (b == '\n') {
            escape = "\\n";
        } else if (b == '\t') {
            escape = "\\t";
        } else if (b == '\r') {
            escape = "\\r";
        } else if (b == 0) {
            escape = "\\0";
        } else if (b < 32 || b == 127) {
            escape = $"\\x{b as int:02x}";
        }
        if (escape.is_empty) {
            index = index + 1;
            continue;
        }
        out.append(text.substr_bytes(start, index - start));
        out.append(escape);
        index = index + 1;
        start = index;
    }
    out.append(text.substr_bytes(start, size - start));
    out.append("\"");
    return out.to_string();
}

# Whether `b` is a decimal digit.
export _yaml_is_decimal(b: byte): bool {
    return b >= '0' && b <= '9';
}
