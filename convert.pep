## Struct conversion: `encode` and `decode` turn Pepper values into YAML
## text and back, through reflection, with no per-type code to write.
##
## They convert as `json`'s `to_json` and `from_json` do, through a
## `json.JsonValue`, so the rules and the `serialize` attributes
## (`[Name]`, `[Ignore]`, `[Required]`, `[Tag]`, `[Untagged]`) are the
## same in both formats: a property's key is its name as written,
## `Optional<T>` is the value or `null`, and a `Result` is a compile error.

import json;
import "parse";
import "value";
import "write";

## Converts `value` to a `YamlValue`, as `json.to_json` converts it to
## JSON: a struct's public properties become a mapping's members in
## declaration order, an `Array` a sequence, an enum case that carries no
## values its name.
##
## @typeParam T the type of the value
## @param value the value to convert
## @returns the value as YAML
## @example
##     import yaml;
##
##     struct Point {
##         var x: int;
##         var y: int;
##     }
##
##     main(): int {
##         var p = Point();
##         p.x = 1;
##         p.y = 2;
##         assert(yaml.to_yaml(p)["y"].as_int().value() == 2, "a member");
##         return 0;
##     }
export to_yaml<T>(value: T): YamlValue {
    return _yaml_of_json(json.to_json(value));
}

## Writes `value` as a YAML document, converting it as `to_yaml` does.
##
## @typeParam T the type of the value
## @param value the value to write
## @returns the YAML text, ending with a line break
## @example
##     import serialize;
##     import yaml;
##
##     struct ServerConfig {
##         var host: String;
##         var max_connections: int;
##         [Name("tls")]
##         var use_tls: bool;
##         var tags: Array<String>;
##     }
##
##     main(): int {
##         var config = ServerConfig();
##         config.host = "localhost";
##         config.max_connections = 16;
##         config.tags = ["web"];
##         var text = yaml.encode(config);
##         assert(text == "host: localhost\nmax_connections: 16\ntls: false\ntags:\n  - web\n", "a document");
##         return 0;
##     }
export encode<T>(value: T): String {
    return to_yaml(value).to_string();
}

## Converts a `YamlValue` to a `T`, the reverse of `to_yaml`, as
## `json.from_json` converts JSON.
##
## A struct is made with its constructor that takes no arguments, then each
## property found in the mapping is read in. A missing key leaves its
## property at its default, unless the property is marked `[Required]`,
## which makes it an error. A key that names no property is skipped, or
## with `unknown_keys = json.UnknownKeys.Reject` is an error.
##
## An error names where in the document it is, as a path from the root `$`
## in its `value_path` and at the start of its message, and has no line or
## column, since there is no text: `$.server.port: expected a number, found
## a string`.
##
## @typeParam T the type to convert to
## @param value the YAML value
## @param unknown_keys what to do with a key that names no property
## @returns the converted value, or the first error
export from_yaml<T>(value: YamlValue, unknown_keys: json.UnknownKeys = json.UnknownKeys.Ignore): Result<T, YamlError> {
    var converted = json.from_json<T>(_yaml_to_json(value), unknown_keys);
    if (converted.is_err()) {
        return Result<T, YamlError>.err(_yaml_error_of_json(converted.error()));
    }
    return Result<T, YamlError>.ok(converted.value());
}

## Parses a YAML document and converts it to a `T`: `parse`, then
## `from_yaml`.
##
## @typeParam T the type to convert to
## @param text the YAML text
## @param unknown_keys what to do with a key that names no property
## @param path the name of the text (a file name, say), which the error's
##   `to_string()` puts first
## @returns the value, or the first error: a syntax error, or a conversion
##   error with its path in the document; either has its line and column
## @example
##     import serialize;
##     import yaml;
##
##     struct ServerConfig {
##         var host: String;
##         [Required]
##         var port: int;
##         var tags: Array<String>;
##         var timeout: int?;
##     }
##
##     main(): int {
##         var config = yaml.decode<ServerConfig>("host: a\nport: 80\ntags: [x]\n");
##         assert(config.value().port == 80, "a number");
##         assert(config.value().tags[0] == "x", "a sequence");
##         assert(config.value().timeout.is_empty(), "a missing optional");
##
##         var bad = yaml.decode<ServerConfig>("port: eighty\n", path = "server.yaml");
##         assert(bad.error().to_string() == "server.yaml:1:7: error: $.port: expected a number, found a string", "where");
##         return 0;
##     }
export decode<T>(
    text: String, unknown_keys: json.UnknownKeys = json.UnknownKeys.Ignore, path: String = ""
): Result<T, YamlError> {
    var offsets = HashMap<String, ulong>();
    var parsed = _yaml_parse_noted(
        text, path, 256, 1000000, Optional<_YamlNotes>.Empty, Optional<HashMap<String, ulong>>.Value(offsets)
    );
    if (parsed.is_err()) {
        return Result<T, YamlError>.err(parsed.error());
    }
    var result = from_yaml<T>(parsed.value(), unknown_keys);
    if (result.is_err()) {
        var error = result.error();
        error.path = path;
        var offset = offsets.try_get(error.value_path);
        if (offset.is_value()) {
            _yaml_place(error, text, offset.value());
        }
        return Result<T, YamlError>.err(error);
    }
    return result;
}

# The JSON value of `value`, whose mappings have string keys as JSON's do.
_yaml_to_json(value: YamlValue): json.JsonValue {
    match (value) {
        Null => { return json.JsonValue.Null; }
        Bool(flag) => { return json.JsonValue.Bool(flag); }
        Integer(n) => { return json.JsonValue.Integer(n); }
        Float(n) => { return json.JsonValue.Number(n); }
        String(text) => { return json.JsonValue.String(text); }
        Sequence(items) => {
            var out = Array<json.JsonValue>(items.count);
            for (var item in items) {
                out.append(_yaml_to_json(item));
            }
            return json.JsonValue.Array(out);
        }
        Mapping(members) => {
            var out = json.JsonValue.object();
            for (var (key, member) in members) {
                out[key] = _yaml_to_json(member);
            }
            return out;
        }
    }
    return json.JsonValue.Null;
}

# The YAML value of `value`.
_yaml_of_json(value: json.JsonValue): YamlValue {
    match (value) {
        Null => { return YamlValue.Null; }
        Bool(flag) => { return YamlValue.Bool(flag); }
        Integer(n) => { return YamlValue.Integer(n); }
        Number(n) => { return YamlValue.Float(n); }
        String(text) => { return YamlValue.String(text); }
        Array(items) => {
            var out = Array<YamlValue>(items.count);
            for (var item in items) {
                out.append(_yaml_of_json(item));
            }
            return YamlValue.Sequence(out);
        }
        Object(members) => {
            var out = YamlValue.mapping();
            for (var (key, member) in members) {
                out[key] = _yaml_of_json(member);
            }
            return out;
        }
    }
    return YamlValue.Null;
}

# A `YamlError` for an error of `json.from_json`, naming kinds of values as
# YAML does: a mapping, not an object; a sequence, not an array.
_yaml_error_of_json(error: json.JsonError): YamlError {
    var prefix = error.value_path.is_empty ? "" : error.value_path + ": ";
    var message = error.message;
    if (message.starts_with(prefix)) {
        var rest = message.substr_bytes(prefix.size, message.size - prefix.size);
        message = prefix + rest.replace("an object", "a mapping").replace("an array", "a sequence");
    }
    var out = YamlError(message, line = 0, column = 0);
    out.value_path = error.value_path;
    return out;
}
