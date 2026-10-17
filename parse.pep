## `parse` and `parse_all`: reading YAML text into `YamlValue`s;
## `YamlError`, what they report when the text is not YAML; and
## `decode_text`, for text in UTF-16.

import text;
import "schema";
import "value";
import "write";

## What `parse` reports when the text is not YAML, and what `decode`
## reports when a value does not fit its property: what is wrong, and the
## line and column where it is.
##
## `to_string()` renders it like a compiler error:
## `config.yaml:4:12: error: undefined alias 'base'`.
export struct YamlError {
    ## What is wrong, worded like a compiler error (`expected ':' after the
    ## key`).
    var message: String;
    ## The path given to `parse`, which names the text in `to_string()`;
    ## empty when none was given.
    var path: String;
    ## The line of the error, from 1; 0 for an error with no text to point
    ## into, such as one from `from_yaml`.
    var line: ulong;
    ## The column of the error, from 1, counting bytes as clang does; 0
    ## when `line` is.
    var column: ulong;
    ## The byte offset of the error in the text, from 0.
    var offset: ulong;
    ## Where in the document the value an error is about is, as a path from
    ## the root `$` (`$.server.port`, `$.hosts[0]`); empty for an error in
    ## the text's syntax. `decode` and `from_yaml` set it, and start
    ## `message` with it.
    var value_path: String;

    ## Creates an error.
    ##
    ## @param message what is wrong
    ## @param path the name of the text, or empty
    ## @param line the line of the error, from 1
    ## @param column the column of the error, from 1
    ## @param offset the byte offset of the error, from 0
    construct(message: String = "", path: String = "", line: ulong = 1, column: ulong = 1, offset: ulong = 0) {
        this.message = message;
        this.path = path;
        this.line = line;
        this.column = column;
        this.offset = offset;
        value_path = "";
    }

    ## Returns the error as a compiler prints one:
    ## `path:line:column: error: message`, without the `path:` when there
    ## is no path and without `line:column:` when `line` is 0.
    ##
    ## @returns the rendered error
    to_string(): String {
        if (line == 0) {
            if (path.is_empty) {
                return $"error: {message}";
            }
            return $"{path}: error: {message}";
        }
        if (path.is_empty) {
            return $"{line}:{column}: error: {message}";
        }
        return $"{path}:{line}:{column}: error: {message}";
    }
}

## Parses YAML 1.2 text holding one document into a `YamlValue`.
##
## Plain scalars are read with the core schema: `null`, `~` and nothing are
## `Null`; `true` and `false` (also `True`, `TRUE`, ...) are booleans;
## `42`, `0x2a` and `0o52` are integers; `1.5`, `1e3`, `.inf` and `.nan`
## are floats; anything else, `yes`, `no`, `on` and `off` included, is a
## string. Quoted and block scalars (`|`, `>`) are strings.
##
## Only the core schema's tags are read: `!!str`, `!!int`, `!!float`,
## `!!bool`, `!!null`, `!!seq` and `!!map` (and `!`, which makes a plain
## scalar a string). Any other tag is an error, so no text can ask for a
## type of its own to be made.
##
## Anchors and aliases (`&base`, `*base`) are read, and an alias is the
## value its anchor names, shared rather than copied. So that a small
## text cannot stand for a huge value (the "billion laughs" attack), the
## nodes all aliases stand for, counted as if each were copied, may not
## pass `max_alias_nodes`.
##
## The text must be valid UTF-8; a byte-order mark at the start is skipped
## (use `decode_text` for UTF-16). A mapping's keys must be scalars and
## must differ. YAML 1.1's merge key (`<<: *base`) is an ordinary key.
##
## @param text the YAML text
## @param path the name of the text (a file name, say), which the error's
##   `to_string()` puts first
## @param max_depth how deeply collections may nest
## @param max_alias_nodes how many nodes the aliases may stand for in all
## @returns the document's value (`Null` for text with no document), or an
##   error naming the first problem and its line and column; text holding
##   more than one document is an error (use `parse_all`)
## @example
##     import yaml;
##
##     var parsed = yaml.parse("server:\n  port: 8080\n  debug: no\n");
##     assert(parsed.value()["server"]["port"].as_int().value() == 8080, "an integer");
##     assert(parsed.value()["server"]["debug"].as_string().value() == "no", "not a boolean");
##     var bad = yaml.parse("a: *missing", path = "config.yaml");
##     assert(bad.error().to_string() == "config.yaml:1:4: error: undefined alias 'missing'", "where");
export parse(
    text: String, path: String = "", max_depth: ulong = 256, max_alias_nodes: ulong = 1000000
): Result<YamlValue, YamlError> {
    var parser = _YamlParser(text, path, max_depth, max_alias_nodes);
    var documents = parser.run();
    if (documents.is_err()) {
        return Result<YamlValue, YamlError>.err(documents.error());
    }
    return parser.single(documents.value());
}

## Parses YAML 1.2 text holding any number of documents, each started by
## `---` or ended by `...`, into one `YamlValue` each.
##
## Each document is read as `parse` reads one; anchors and `%TAG`
## directives hold only in their own document.
##
## @param text the YAML text
## @param path the name of the text (a file name, say), which the error's
##   `to_string()` puts first
## @param max_depth how deeply collections may nest
## @param max_alias_nodes how many nodes the aliases of each document may
##   stand for in all
## @returns the documents in order (none for empty text), or an error
##   naming the first problem and its line and column
## @example
##     import yaml;
##
##     var documents = yaml.parse_all("---\nname: a\n---\nname: b\n").value();
##     assert(documents.count == 2, "two documents");
##     assert(documents[1]["name"].as_string().value() == "b", "the second");
export parse_all(
    text: String, path: String = "", max_depth: ulong = 256, max_alias_nodes: ulong = 1000000
): Result<Array<YamlValue>, YamlError> {
    var parser = _YamlParser(text, path, max_depth, max_alias_nodes);
    return parser.run();
}

## Decodes the bytes of a YAML file into text for `parse`, in whichever
## encoding YAML allows they are: UTF-8, or UTF-16 in either byte order,
## told apart by a byte-order mark or, without one, by where the zero bytes
## of the first character are. A byte-order mark is dropped.
##
## @param bytes the file's contents
## @param path the name of the text, which the error's `to_string()` puts
##   first
## @returns the text, or an error when the bytes are not valid in their
##   encoding or are UTF-32, which this package does not read
## @example
##     import text;
##     import yaml;
##
##     var bytes = text.Utf16.encode("\u{feff}a: 1\n");
##     var decoded = yaml.decode_text(bytes).value();
##     assert(yaml.parse(decoded).value()["a"].as_int().value() == 1, "UTF-16");
export decode_text(bytes: u8[], path: String = ""): Result<String, YamlError> {
    var count = bytes.count;
    var b0 = count > 0 ? bytes[0] : 1 as u8;
    var b1 = count > 1 ? bytes[1] : 1 as u8;
    var b2 = count > 2 ? bytes[2] : 1 as u8;
    var b3 = count > 3 ? bytes[3] : 1 as u8;
    if ((b0 == 0 && b1 == 0) || (count > 3 && b2 == 0 && b3 == 0 && (b1 == 0 || (b0 == 255 && b1 == 254)))) {
        return Result<String, YamlError>.err(YamlError("UTF-32 text is not supported; convert it to UTF-8", path));
    }
    ulong skip = 0;
    var utf16 = false;
    var big_endian = false;
    if (b0 == 254 && b1 == 255) {
        utf16 = true;
        big_endian = true;
        skip = 2;
    } else if (b0 == 255 && b1 == 254) {
        utf16 = true;
        skip = 2;
    } else if (count > 1 && b0 == 0) {
        utf16 = true;
        big_endian = true;
    } else if (count > 1 && b1 == 0) {
        utf16 = true;
    } else if (b0 == 239 && b1 == 187 && b2 == 191) {
        skip = 3;
    }
    var body = Array<u8>(count - skip);
    for (var index in skip..count) {
        body.append(bytes[index]);
    }
    if (utf16) {
        var decoded = text.Utf16.decode(body, big_endian = big_endian);
        if (decoded.is_empty()) {
            return Result<String, YamlError>.err(YamlError("invalid UTF-16", path));
        }
        return Result<String, YamlError>.ok(decoded.value());
    }
    var decoded = text.Utf8.decode(body);
    if (decoded.is_empty()) {
        return Result<String, YamlError>.err(YamlError("invalid UTF-8", path));
    }
    return Result<String, YamlError>.ok(decoded.value());
}

# Parses `text` like `parse_all`, filing its comments and layout in `notes`
# and, when `offsets` is given, the offset of each value by its path.
export _yaml_parse_noted(
    text: String,
    path: String,
    max_depth: ulong,
    max_alias_nodes: ulong,
    notes: _YamlNotes?,
    offsets: HashMap<String, ulong>?
): Result<YamlValue, YamlError> {
    var parser = _YamlParser(text, path, max_depth, max_alias_nodes);
    parser._notes = notes;
    parser._offsets = offsets;
    var documents = parser.run();
    if (documents.is_err()) {
        return Result<YamlValue, YamlError>.err(documents.error());
    }
    return parser.single(documents.value());
}

# Sets `error`'s offset, and the line and column of that offset in `text`.
export _yaml_place(error: YamlError, text: String, offset: ulong) {
    ulong line = 1;
    ulong line_start = 0;
    ulong index = 0;
    while (index < offset && index < text.size) {
        if (text.byte_at(index) == '\n') {
            line = line + 1;
            line_start = index + 1;
        }
        index = index + 1;
    }
    error.line = line;
    error.column = offset - line_start + 1;
    error.offset = offset;
}

# The prefix of the core schema's tags, which `!!` stands for.
const CORE_TAG = "tag:yaml.org,2002:";

# What came before a block node on its line: nothing (`LINE`); a `- `,
# `? ` or explicit `: `, after which a block collection may start on the
# same line (`COMPACT`); or an implicit key's `:`, after which it may not
# (`KEYED`), or a `---` (`DOCUMENT`).
const LINE = 0;
const COMPACT = 1;
const KEYED = 2;
# After `---`, where no block collection may start either.
const DOCUMENT = 3;

# A comment line, or a blank line (empty `text`), waiting for the value it
# belongs to, and the column it starts at.
struct _YamlLine {
    var text: String;
    var column: ulong;
}

# Reads YAML text. Each method that can fail returns false after recording
# the first error in `_error`; one that reads a node leaves it in `_value`.
struct _YamlParser {
    String _text;
    ulong _size;
    ulong _position;
    String _path;
    ulong _max_depth;
    ulong _depth;
    ulong _max_alias_nodes;
    ulong _expanded;
    # The nodes read so far, aliases counted as the nodes they stand for.
    ulong _nodes;
    YamlError _error;
    YamlValue _value;
    # Whether `_value` ended on the line the position is still on, so a
    # comment or a line break must follow.
    bool _inline;
    # Whether `_value` was quoted or a flow collection, after which a flow
    # mapping's `:` needs no space.
    bool _json_like;
    # The text of the last scalar read.
    String _scalar;
    # How many flow collections the position is inside, and the column of
    # the block collection holding the outermost (-1 at the top), past
    # which its lines must be indented.
    ulong _flow;
    long _flow_indent;
    # The same for a quoted scalar in a block collection.
    long _scalar_indent;
    HashMap<String, YamlValue> _anchors;
    HashMap<String, ulong> _anchor_sizes;
    HashMap<String, String> _handles;
    # The properties `_properties` read, and where the tag is.
    String _anchor;
    String _tag;
    ulong _tag_at;
    # With `parse_document`: comments and layout, and the comment lines not
    # yet given to a value.
    _YamlNotes? _notes;
    Array<_YamlLine> _pending;
    # With `decode`: the offset of each value by its path.
    HashMap<String, ulong>? _offsets;
    bool _first_document;

    construct(text: String, path: String, max_depth: ulong, max_alias_nodes: ulong) {
        _text = text;
        _size = text.size;
        _path = path;
        _max_depth = max_depth;
        _max_alias_nodes = max_alias_nodes;
        _error = YamlError();
        _value = YamlValue.Null;
        _scalar = "";
        _anchors = HashMap<String, YamlValue>();
        _anchor_sizes = HashMap<String, ulong>();
        _handles = HashMap<String, String>();
        _anchor = "";
        _tag = "";
        _notes = Optional<_YamlNotes>.Empty;
        _pending = Array<_YamlLine>();
        _offsets = Optional<HashMap<String, ulong>>.Empty;
        _first_document = true;
        _flow_indent = -1;
        _scalar_indent = -1;
    }

    run(): Result<Array<YamlValue>, YamlError> {
        var documents = Array<YamlValue>();
        if (_size >= 3 && _text.byte_at(0) == 239 && _text.byte_at(1) == 187 && _text.byte_at(2) == 191) {
            _position = 3;
        }
        var invalid = text.Utf8.find_invalid(_text);
        if (invalid.is_value()) {
            _fail_at("invalid UTF-8", invalid.value());
            return Result<Array<YamlValue>, YamlError>.err(_error);
        }
        if (!_stream(documents)) {
            return Result<Array<YamlValue>, YamlError>.err(_error);
        }
        return Result<Array<YamlValue>, YamlError>.ok(documents);
    }

    # The one document of `documents`, `Null` for none, or an error for
    # more than one.
    single(documents: Array<YamlValue>): Result<YamlValue, YamlError> {
        if (documents.count > 1) {
            _fail_at("expected one document, found several; use 'parse_all' to read them", _second_document);
            return Result<YamlValue, YamlError>.err(_error);
        }
        if (documents.is_empty) {
            return Result<YamlValue, YamlError>.ok(YamlValue.Null);
        }
        return Result<YamlValue, YamlError>.ok(documents[0]);
    }

    ulong _second_document;

    # ── Documents ──────────────────────────────────────────────────────────

    _stream(documents: Array<YamlValue>): bool {
        while (true) {
            if (!_skip_to_content()) {
                return false;
            }
            if (_position >= _size) {
                break;
            }
            if (documents.count == 1) {
                _second_document = _position;
            }
            _anchors = HashMap<String, YamlValue>();
            _anchor_sizes = HashMap<String, ulong>();
            _handles = HashMap<String, String>();
            _expanded = 0;
            var directives = false;
            var version_seen = false;
            while (_peek() == '%' && _column(_position) == 0) {
                if (!_directive(version_seen)) {
                    return false;
                }
                version_seen = version_seen || _scalar == "YAML";
                directives = true;
                if (!_skip_to_content()) {
                    return false;
                }
            }
            var explicit = false;
            if (_at_marker("---")) {
                _position = _position + 3;
                explicit = true;
                if (_first_document && _notes.is_value()) {
                    _notes.value().explicit_start = true;
                }
            } else if (directives) {
                _fail("expected '---' after the directives");
                return false;
            } else if (_at_marker("...")) {
                _position = _position + 3;
                if (!_end_of_marker_line()) {
                    return false;
                }
                continue;
            }
            _file_before("$");
            _note_offset("$");
            _depth = 0;
            var read = explicit ? _block_node(-1, DOCUMENT, "$") : _content(-1, LINE, false, "$", "", "", 0);
            if (!read) {
                return false;
            }
            documents.append(_value);
            if (!_end_line("$") || !_skip_to_content()) {
                return false;
            }
            _first_document = false;
            if (_position >= _size) {
                break;
            }
            if (_at_marker("...")) {
                _position = _position + 3;
                if (!_end_of_marker_line()) {
                    return false;
                }
                continue;
            }
            if (!_at_marker("---")) {
                _fail("expected the end of the document");
                return false;
            }
        }
        if (_notes.is_value()) {
            _notes.value().add(_notes.value().end, "$", _take_pending());
        }
        return true;
    }

    # After a `...`: nothing but a comment until the line break.
    _end_of_marker_line(): bool {
        _skip_space();
        if (_peek() == '#') {
            _skip_comment();
        }
        if (!_at_line_end()) {
            _fail("expected a line break after '...'");
            return false;
        }
        return true;
    }

    # Reads a `%YAML` or `%TAG` directive line; others are skipped, as the
    # specification asks. Leaves the directive's name in `_scalar`.
    _directive(version_seen: bool): bool {
        var start = _position;
        _position = _position + 1;
        var name = _token();
        _scalar = name;
        _skip_space();
        if (name == "YAML") {
            if (version_seen) {
                _fail_at("duplicate '%YAML' directive", start);
                return false;
            }
            var version_at = _position;
            var version = _token();
            var digits = version.size > 2;
            for (var b in version.bytes()) {
                digits = digits && (_yaml_is_decimal(b) || b == '.');
            }
            if (!digits) {
                return _fail_at($"expected a version such as '1.2', found '{version}'", version_at);
            }
            if (!version.starts_with("1.")) {
                _fail_at($"unsupported YAML version '{version}'; this package reads YAML 1.2", version_at);
                return false;
            }
        } else if (name == "TAG") {
            var handle_at = _position;
            var handle = _token();
            if (!handle.starts_with("!") || !handle.ends_with("!")) {
                _fail_at($"expected a tag handle such as '!' or '!e!', found '{handle}'", handle_at);
                return false;
            }
            _skip_space();
            var prefix = _token();
            if (prefix.is_empty) {
                _fail("expected a tag prefix after the handle");
                return false;
            }
            _handles[handle] = prefix;
        } else {
            while (!_at_line_end()) {
                _position = _position + 1;
            }
        }
        _skip_space();
        if (_peek() == '#') {
            _skip_comment();
        }
        if (!_at_line_end()) {
            _fail("expected a line break after the directive");
            return false;
        }
        return true;
    }

    # ── Block nodes ────────────────────────────────────────────────────────

    # Reads a node of a block collection whose entries are at column
    # `indent` (-1 at the top), after what `mode` says came before it on
    # its line.
    _block_node(indent: long, mode: int, path: String): bool {
        _skip_space();
        if (_at_line_end() || _peek() == '#') {
            if (!_take_trailing(path)) {
                return false;
            }
            return _next_line_node(indent, mode == KEYED, path, "", "", 0);
        }
        return _content(indent, mode, mode == KEYED, path, "", "", 0);
    }

    # Reads a node that starts on a later line, or is empty when the next
    # line is not indented past `indent` (a sequence at `indent` itself
    # still belongs to a mapping's key, `under_key`). `anchor` and `tag` are
    # properties already read.
    _next_line_node(indent: long, under_key: bool, path: String, anchor: String, tag: String, tag_at: ulong): bool {
        if (!_skip_to_content()) {
            return false;
        }
        var column = _column(_position) as long;
        var ended = _position >= _size || _at_marker("---") || _at_marker("...");
        var sequence_here = under_key && column == indent && _at_indicator('-');
        if (ended || (column <= indent && !sequence_here)) {
            _note_offset(path);
            return _empty(anchor, tag, tag_at);
        }
        return _content(indent, LINE, under_key, path, anchor, tag, tag_at);
    }

    # Reads a node starting at the position, on a line `mode` describes.
    _content(indent: long, mode: int, under_key: bool, path: String, anchor: String, tag: String, tag_at: ulong): bool {
        var start = _position;
        _note_offset(path);
        if (_peek() == '&' || _peek() == '!') {
            if (!_properties()) {
                return false;
            }
            _skip_space();
            if (mode != KEYED && mode != DOCUMENT && _implicit_key_ahead()) {
                # Properties before a key are the key's.
                _position = start;
                return _block_mapping(_column(start), indent, under_key, path, anchor, tag);
            }
            if (!anchor.is_empty && !_anchor.is_empty) {
                _fail_at("a node can have only one anchor", start);
                return false;
            }
            if (!tag.is_empty && !_tag.is_empty) {
                _fail_at("a node can have only one tag", start);
                return false;
            }
            var merged_anchor = anchor.is_empty ? _anchor : anchor;
            var merged_tag = tag.is_empty ? _tag : tag;
            var merged_at = tag.is_empty ? _tag_at : tag_at;
            if (_at_line_end() || _peek() == '#') {
                if (!_take_trailing(path)) {
                    return false;
                }
                return _next_line_node(indent, under_key, path, merged_anchor, merged_tag, merged_at);
            }
            if (_at_indicator('-') || _at_indicator('?')) {
                return _fail(
                    "a block collection cannot start on the line of its properties; start it on the next line"
                );
            }
            return _content(indent, mode, under_key, path, merged_anchor, merged_tag, merged_at);
        }
        var b = _peek();
        var column = _column(_position);
        if ((b == '-' || b == '?') && _at_indicator(b)) {
            if (mode == KEYED || mode == DOCUMENT) {
                return _fail(
                    mode == KEYED ?
                        "a block collection cannot start on the line of its key; start it on the next line" :
                        "a block collection cannot start on the '---' line; start it on the next line"
                );
            }
            if (mode == COMPACT && _tab_before(_position)) {
                return _fail("a tab cannot indent YAML; use spaces");
            }
            if (b == '-') {
                return _block_sequence(column, indent, under_key, path, anchor, tag, tag_at);
            }
            return _block_mapping(column, indent, under_key, path, anchor, tag);
        }
        if (_implicit_key_ahead()) {
            if (mode == KEYED || mode == DOCUMENT) {
                return _fail(
                    mode == KEYED ?
                        "a mapping cannot start on the line of its key; start it on the next line" :
                        "a block mapping cannot start on the '---' line; start it on the next line"
                );
            }
            if (mode == COMPACT && _tab_before(_position)) {
                return _fail("a tab cannot indent YAML; use spaces");
            }
            return _block_mapping(column, indent, under_key, path, anchor, tag);
        }
        if (b == '|' || b == '>') {
            return _block_scalar(indent, path, anchor, tag, tag_at);
        }
        return _inline_node(indent, path, anchor, tag, tag_at);
    }

    # Reads a node that stays on its line or continues on more indented
    # lines: an alias, a flow collection, or a quoted or plain scalar.
    _inline_node(indent: long, path: String, anchor: String, tag: String, tag_at: ulong): bool {
        var b = _peek();
        if (b == '*') {
            if (!anchor.is_empty || !tag.is_empty) {
                _fail("an alias cannot have an anchor or a tag");
                return false;
            }
            return _alias();
        }
        if (b == '[' || b == '{') {
            _scalar_indent = indent;
            return _flow_collection(path, anchor, tag, tag_at);
        }
        var before = _nodes;
        if (b == '"' || b == '\'') {
            _scalar_indent = indent;
            if (!(b == '"' ? _double_quoted() : _single_quoted())) {
                return false;
            }
            _style(path, b == '"' ? DOUBLE_QUOTED : SINGLE_QUOTED);
            return _scalar_node(_scalar, false, anchor, tag, tag_at, before, path);
        }
        if (!_plain_start()) {
            return false;
        }
        _plain(indent, false);
        return _scalar_node(_scalar, true, anchor, tag, tag_at, before, path);
    }

    # Reads a block mapping whose keys are at column `column`; the position
    # is at its first key. `indent` is its parent's column.
    _block_mapping(column: ulong, indent: long, under_key: bool, path: String, anchor: String, tag: String): bool {
        if (!_enter() || !_collection_tag(tag, "map")) {
            return false;
        }
        if (under_key && indent >= 0 && _notes.is_value() && !_notes.value().indent_seen) {
            _notes.value().indent = column - indent as ulong;
            _notes.value().indent_seen = true;
        }
        var before = _nodes;
        _nodes = _nodes + 1;
        var members = OrderedMap<String, YamlValue>();
        while (true) {
            if (_has_tab_indent(_position)) {
                return _fail("a tab cannot indent YAML; use spaces");
            }
            var comments = _take_pending();
            var key_at = _position;
            var key = "";
            if (_at_indicator('?')) {
                _position = _position + 1;
                if (!_block_node(column as long, COMPACT, path + "?") || !_key_text(key_at)) {
                    return false;
                }
                key = _scalar;
                if (!_end_line(path + "?") || !_skip_to_content()) {
                    return false;
                }
                var key_path = _yaml_path_key(path, key);
                if (_position < _size && _column(_position) == column && _at_indicator(':') && !_at_marker("---")) {
                    _position = _position + 1;
                    if (!_block_node(column as long, COMPACT, key_path)) {
                        return false;
                    }
                } else {
                    _note_offset(key_path);
                    _value = YamlValue.Null;
                    _inline = false;
                }
            } else {
                if (!_implicit_key()) {
                    return false;
                }
                key = _scalar;
                if (!_block_node(column as long, KEYED, _yaml_path_key(path, key))) {
                    return false;
                }
            }
            if (members.contains(key)) {
                _fail_at($"duplicate key '{key}'", key_at);
                return false;
            }
            members[key] = _value;
            var key_path = _yaml_path_key(path, key);
            _file(key_path, comments);
            if (!_end_line(key_path) || !_skip_to_content()) {
                return false;
            }
            if (_position >= _size || _at_marker("---") || _at_marker("...")) {
                break;
            }
            var next = _column(_position);
            if (next < column) {
                break;
            }
            if (next > column) {
                _fail("unexpected indentation; a key of this mapping goes at column " + to_string(column + 1));
                return false;
            }
            if (_at_indicator('-')) {
                _fail("expected a key, found a sequence entry");
                return false;
            }
        }
        _file_end(path, column);
        _value = YamlValue.Mapping(members);
        _inline = false;
        _depth = _depth - 1;
        _register(anchor, before);
        return true;
    }

    # Reads a block sequence whose `-` indicators are at column `column`.
    _block_sequence(
        column: ulong, indent: long, under_key: bool, path: String, anchor: String, tag: String, tag_at: ulong
    ): bool {
        if (!_enter() || !_collection_tag(tag, "seq")) {
            return false;
        }
        if (under_key && indent >= 0 && _notes.is_value() && !_notes.value().sequences_seen) {
            _notes.value().indent_sequences = (column as long) > indent;
            _notes.value().sequences_seen = true;
        }
        var before = _nodes;
        _nodes = _nodes + 1;
        var items = Array<YamlValue>();
        while (true) {
            if (_has_tab_indent(_position)) {
                return _fail("a tab cannot indent YAML; use spaces");
            }
            var item_path = $"{path}[{items.count}]";
            _file(item_path, _take_pending());
            _position = _position + 1;
            if (!_block_node(column as long, COMPACT, item_path)) {
                return false;
            }
            items.append(_value);
            if (!_end_line(item_path) || !_skip_to_content()) {
                return false;
            }
            if (_position >= _size || _at_marker("---") || _at_marker("...")) {
                break;
            }
            var next = _column(_position);
            if (next < column) {
                break;
            }
            if (next > column) {
                _fail("unexpected indentation; an entry of this sequence goes at column " + to_string(column + 1));
                return false;
            }
            if (!_at_indicator('-')) {
                break;
            }
        }
        _file_end(path, column);
        _value = YamlValue.Sequence(items);
        _inline = false;
        _depth = _depth - 1;
        _register(anchor, before);
        return true;
    }

    # Whether the rest of the line, from the position, is an implicit key
    # and its `:`: properties, then a scalar, alias or flow collection on
    # this line, then `:` and a space or the line's end.
    _implicit_key_ahead(): bool {
        var index = _position;
        while (_at(index) == '&' || _at(index) == '!') {
            while (index < _size && !_is_blank(_at(index)) && !_is_break(_at(index))) {
                index = index + 1;
            }
            while (_is_blank(_at(index))) {
                index = index + 1;
            }
        }
        var b = _at(index);
        if (b == '"' || b == '\'') {
            index = index + 1;
            while (true) {
                if (index >= _size || _is_break(_at(index))) {
                    return false;
                }
                if (b == '"' && _at(index) == '\\') {
                    index = index + 2;
                    continue;
                }
                if (_at(index) == b) {
                    if (b == '\'' && _at(index + 1) == '\'') {
                        index = index + 2;
                        continue;
                    }
                    break;
                }
                index = index + 1;
            }
            index = index + 1;
        } else if (b == '[' || b == '{') {
            var depth = 0;
            while (index < _size && !_is_break(_at(index))) {
                var c = _at(index);
                if (c == '[' || c == '{') {
                    depth = depth + 1;
                } else if (c == ']' || c == '}') {
                    depth = depth - 1;
                    if (depth == 0) {
                        break;
                    }
                }
                index = index + 1;
            }
            if (depth != 0) {
                return false;
            }
            index = index + 1;
        } else if (b == '*') {
            while (index < _size && !_is_blank(_at(index)) && !_is_break(_at(index))) {
                index = index + 1;
            }
        } else {
            while (index < _size && !_is_break(_at(index))) {
                var c = _at(index);
                if (c == ':' && _is_space_or_end(index + 1)) {
                    return true;
                }
                if (c == '#' && index > _position && _is_blank(_at(index - 1))) {
                    return false;
                }
                index = index + 1;
            }
            return false;
        }
        while (_is_blank(_at(index))) {
            index = index + 1;
        }
        return _at(index) == ':' && _is_space_or_end(index + 1);
    }

    # Reads an implicit key and its `:`, leaving the key in `_scalar`.
    _implicit_key(): bool {
        var start = _position;
        var anchor = "";
        var tag = "";
        ulong tag_at = 0;
        if (_peek() == '&' || _peek() == '!') {
            if (!_properties()) {
                return false;
            }
            anchor = _anchor;
            tag = _tag;
            tag_at = _tag_at;
            _skip_space();
        }
        var key_at = _position;
        var b = _peek();
        if (b == '[' || b == '{') {
            _fail("a mapping key must be a scalar; this package reads no collections as keys");
            return false;
        }
        if (b == '*') {
            if (!anchor.is_empty || !tag.is_empty) {
                _fail_at("an alias cannot have an anchor or a tag", start);
                return false;
            }
            if (!_alias() || !_key_text(key_at)) {
                return false;
            }
        } else {
            var before = _nodes;
            var plain = b != '"' && b != '\'';
            if (b == '"') {
                if (!_double_quoted()) {
                    return false;
                }
            } else if (b == '\'') {
                if (!_single_quoted()) {
                    return false;
                }
            } else {
                _plain_line(false);
            }
            var key = _scalar;
            if (_text.substr_bytes(key_at, _position - key_at).contains("\n")) {
                return _fail_at("an implicit key must be on one line; use '? ' for a longer key", key_at);
            }
            if (!_scalar_node(key, plain, anchor, tag, tag_at, before, "")) {
                return false;
            }
            _scalar = key;
        }
        _skip_space();
        if (_peek() != ':') {
            _fail("expected ':' after the key");
            return false;
        }
        _position = _position + 1;
        return true;
    }

    # Puts the text of `_value`, a key, in `_scalar`; a collection is an
    # error at `at`.
    _key_text(at: ulong): bool {
        match (_value) {
            Null => {
                _scalar = "";
            }
            Bool(flag) => {
                _scalar = flag ? "true" : "false";
            }
            Integer(n) => {
                _scalar = to_string(n);
            }
            Float(n) => {
                _scalar = to_string(n);
            }
            String(text) => {
                _scalar = text;
            }
            else => {
                _fail_at("a mapping key must be a scalar; this package reads no collections as keys", at);
                return false;
            }
        }
        return true;
    }

    # ── Scalars ────────────────────────────────────────────────────────────

    # Checks that a plain scalar may start at the position.
    _plain_start(): bool {
        var b = _peek();
        var bad = b == ',' || b == ']' || b == '}' || b == '%' || b == '@' || b == '`' || b == '[' || b == '{';
        var next = _at(_position + 1);
        var indicator = (b == ':' || b == '-' || b == '?')
            && (_is_space_or_end(_position + 1) || (_flow > 0 && _is_flow_indicator(next)));
        if (bad || indicator) {
            _fail($"unexpected '{_text.substr_bytes(_position, 1)}'");
            return false;
        }
        return true;
    }

    # Reads a plain scalar into `_scalar`: its first line, then each later
    # line indented past `indent` (any line in a flow collection), folded
    # into one with spaces, or with line breaks where lines were blank.
    _plain(indent: long, flow: bool) {
        var out = StringBuilder();
        out.append(_plain_line(flow));
        while (true) {
            var save = _position;
            _skip_space();
            if (!_is_break(_peek())) {
                _position = save;
                break;
            }
            ulong breaks = 0;
            while (_is_break(_peek())) {
                _line_break();
                breaks = breaks + 1;
                _skip_space();
            }
            var stop = _position >= _size
                || _peek() == '#'
                || _at_marker("---")
                || _at_marker("...")
                || (!flow && (_spaces(_position) as long) <= indent);
            if (stop) {
                _position = save;
                break;
            }
            var line = _plain_line(flow);
            if (line.is_empty) {
                _position = save;
                break;
            }
            out.append(breaks == 1 ? " " : "\n".repeat(breaks - 1));
            out.append(line);
        }
        _scalar = out.to_string();
        _inline = true;
    }

    # Reads the rest of a plain scalar's line: up to a `: `, a ` #`, the
    # line's end or, in a flow collection, a flow indicator. Trailing
    # blanks are not part of it, and the position stays before them.
    _plain_line(flow: bool): String {
        var start = _position;
        var end = _position;
        while (_position < _size) {
            var b = _peek();
            if (_is_break(b)) {
                break;
            }
            if (b == ':' && (_is_space_or_end(_position + 1) || (flow && _is_flow_indicator(_at(_position + 1))))) {
                break;
            }
            if (b == '#' && _position > start && _is_blank(_at(_position - 1))) {
                break;
            }
            if (flow && _is_flow_indicator(b)) {
                break;
            }
            _position = _position + 1;
            if (!_is_blank(b)) {
                end = _position;
            }
        }
        _position = end;
        _scalar = _text.substr_bytes(start, end - start);
        return _scalar;
    }

    # Reads a `"..."` scalar into `_scalar`, decoding escapes and folding
    # line breaks.
    _double_quoted(): bool {
        var open = _position;
        _position = _position + 1;
        var out = Array<u8>();
        ulong blanks = 0;
        while (true) {
            if (_position >= _size) {
                _fail_at("unterminated string", open);
                return false;
            }
            var b = _peek();
            if (b == '"') {
                _position = _position + 1;
                break;
            }
            if (b == '\\' && _is_break(_at(_position + 1))) {
                _position = _position + 1;
                _line_break();
                if (!_fold(out, open, true)) {
                    return false;
                }
                blanks = 0;
                continue;
            }
            if (b == '\\') {
                if (!_escape(out)) {
                    return false;
                }
                blanks = 0;
                continue;
            }
            if (_is_break(b)) {
                _trim(out, blanks);
                _line_break();
                if (!_fold(out, open, false)) {
                    return false;
                }
                blanks = 0;
                continue;
            }
            out.append(b as u8);
            blanks = _is_blank(b) ? blanks + 1 : 0;
            _position = _position + 1;
        }
        _scalar = text.Utf8.decode_lossy(out);
        _inline = true;
        _json_like = true;
        return true;
    }

    # Reads a `'...'` scalar into `_scalar`: `''` is a `'`, and line breaks
    # fold.
    _single_quoted(): bool {
        var open = _position;
        _position = _position + 1;
        var out = Array<u8>();
        ulong blanks = 0;
        while (true) {
            if (_position >= _size) {
                _fail_at("unterminated string", open);
                return false;
            }
            var b = _peek();
            if (b == '\'') {
                if (_at(_position + 1) == '\'') {
                    out.append(b as u8);
                    blanks = 0;
                    _position = _position + 2;
                    continue;
                }
                _position = _position + 1;
                break;
            }
            if (_is_break(b)) {
                _trim(out, blanks);
                _line_break();
                if (!_fold(out, open, false)) {
                    return false;
                }
                blanks = 0;
                continue;
            }
            out.append(b as u8);
            blanks = _is_blank(b) ? blanks + 1 : 0;
            _position = _position + 1;
        }
        _scalar = text.Utf8.decode_lossy(out);
        _inline = true;
        _json_like = true;
        return true;
    }

    # After a line break inside a quoted scalar: skips the next lines'
    # leading blanks, appending a line break for each blank line, or a
    # space when there is none and the break was not escaped.
    _fold(out: u8[], open: ulong, escaped: bool): bool {
        ulong breaks = 0;
        while (true) {
            _skip_space();
            if (!_is_break(_peek())) {
                break;
            }
            _line_break();
            breaks = breaks + 1;
        }
        if (_position >= _size || _at_marker("---") || _at_marker("...")) {
            _fail_at("unterminated string", open);
            return false;
        }
        var parent = _flow > 0 ? _flow_indent : _scalar_indent;
        if (parent >= 0 && (_spaces(_position) as long) <= parent) {
            return _fail("a quoted scalar's next line must be indented past column " + to_string(parent + 1));
        }
        if (breaks == 0 && !escaped) {
            out.append(32);
        }
        for (var index in 0..breaks) {
            out.append(10);
        }
        return true;
    }

    # Removes the last `count` bytes of `out`.
    _trim(out: u8[], count: ulong) {
        for (var index in 0..count) {
            out.remove_at(out.count - 1);
        }
    }

    # Decodes the escape at the position, a '\', onto `out`.
    _escape(out: u8[]): bool {
        var start = _position;
        _position = _position + 1;
        var b = _peek();
        _position = _position + 1;
        uint point = 0;
        var digits = 0;
        if (b == '0') {
            point = 0;
        } else if (b == 'a') {
            point = 7;
        } else if (b == 'b') {
            point = 8;
        } else if (b == 't' || b == '\t') {
            point = 9;
        } else if (b == 'n') {
            point = 10;
        } else if (b == 'v') {
            point = 11;
        } else if (b == 'f') {
            point = 12;
        } else if (b == 'r') {
            point = 13;
        } else if (b == 'e') {
            point = 27;
        } else if (b == ' ' || b == '"' || b == '/' || b == '\\') {
            point = b as uint;
        } else if (b == 'N') {
            point = 133;
        } else if (b == '_') {
            point = 160;
        } else if (b == 'L') {
            point = 8232;
        } else if (b == 'P') {
            point = 8233;
        } else if (b == 'x') {
            digits = 2;
        } else if (b == 'u') {
            digits = 4;
        } else if (b == 'U') {
            digits = 8;
        } else {
            if (_position > _size) {
                _fail_at("unterminated string", start);
            } else {
                _fail_at($"invalid escape '{_text.substr_bytes(start, _position - start)}'", start);
            }
            return false;
        }
        for (var index in 0..digits) {
            var digit = _yaml_digit(_peek());
            if (digit < 0 || _position >= _size) {
                _fail_at($"'\\{_text.substr_bytes(start + 1, 1)}' needs {digits} hexadecimal digits", start);
                return false;
            }
            point = point * 16 + digit as uint;
            _position = _position + 1;
        }
        if (point > 1114111 || (point >= 55296 && point <= 57343)) {
            _fail_at($"'{_text.substr_bytes(start, _position - start)}' is not a Unicode character", start);
            return false;
        }
        text.Utf8.append_code_point(out, point);
        return true;
    }

    # Reads a `|` or `>` block scalar for a node of a collection at column
    # `indent`.
    _block_scalar(indent: long, path: String, anchor: String, tag: String, tag_at: ulong): bool {
        var before = _nodes;
        var header_start = _position;
        var literal = _peek() == '|';
        _position = _position + 1;
        var chomp = 0;
        ulong explicit = 0;
        for (var index in 0..2) {
            var b = _peek();
            if ((b == '-' || b == '+') && chomp == 0) {
                chomp = b == '-' ? -1 : 1;
                _position = _position + 1;
            } else if (b >= '1' && b <= '9' && explicit == 0) {
                explicit = (b - '0') as ulong;
                _position = _position + 1;
            } else if (b == '0') {
                _fail("a block scalar's indentation indicator is 1 to 9");
                return false;
            }
        }
        var header = _text.substr_bytes(header_start, _position - header_start);
        if (!_is_space_or_end(_position) && _peek() != '#') {
            _fail("expected a line break after the block scalar's header");
            return false;
        }
        _skip_space();
        if (!_take_trailing(path)) {
            return false;
        }
        _line_break();
        ulong base = indent < 0 ? 0 : indent as ulong;
        ulong content = base + explicit;
        if (explicit == 0) {
            # The indentation of the first line that is not blank; blank
            # lines before it may not be longer.
            ulong longest = 0;
            var index = _position;
            var found = false;
            while (index < _size) {
                ulong spaces = 0;
                while (_at(index + spaces) == ' ') {
                    spaces = spaces + 1;
                }
                if (!_is_break(_at(index + spaces)) && index + spaces < _size) {
                    content = spaces;
                    found = true;
                    if (longest > spaces && (spaces as long) > indent) {
                        _fail_at("a blank line of a block scalar has more spaces than its first line", index);
                        return false;
                    }
                    break;
                }
                if (spaces > longest) {
                    longest = spaces;
                }
                index = index + spaces;
                if (index >= _size) {
                    break;
                }
                index = index + (_at(index) == '\r' && _at(index + 1) == '\n' ? 2 : 1);
            }
            if (!found || (content as long) <= indent) {
                content = (indent + 1) as ulong;
                if (longest > content) {
                    content = longest;
                }
            }
        }
        var lines = Array<String>();
        while (_position < _size) {
            if (content == 0 && (_at_marker("---") || _at_marker("..."))) {
                break;
            }
            ulong spaces = 0;
            while (spaces < content && _at(_position + spaces) == ' ') {
                spaces = spaces + 1;
            }
            var after = _position + spaces;
            if (after >= _size || _is_break(_at(after))) {
                lines.append("");
                _position = after;
                _line_break();
                continue;
            }
            if (spaces < content) {
                var rest = after;
                while (_is_blank(_at(rest))) {
                    rest = rest + 1;
                }
                if (_at(after) == '\t' && (rest >= _size || _is_break(_at(rest)))) {
                    return _fail_at("a tab cannot indent YAML; use spaces", after);
                }
                break;
            }
            var line_start = after;
            _position = after;
            while (_position < _size && !_is_break(_peek())) {
                _position = _position + 1;
            }
            lines.append(_text.substr_bytes(line_start, _position - line_start));
            _line_break();
        }
        # The line breaks after the last line with text, its own included
        # (the end of the text counts as one): what chomping keeps or drops.
        long last = -1;
        for (var index in 0..lines.count) {
            if (!lines[index].is_empty) {
                last = index as long;
            }
        }
        var trailing = lines.count - (last < 0 ? 0 : last as ulong);
        var body = StringBuilder();
        if (literal) {
            for (var index in 0..(last + 1) as ulong) {
                if (index > 0) {
                    body.append("\n");
                }
                body.append(lines[index]);
            }
        } else {
            _fold_block(body, lines, (last + 1) as ulong);
        }
        if (chomp == 0 && last >= 0 && trailing > 0) {
            body.append("\n");
        } else if (chomp == 1) {
            body.append("\n".repeat(trailing));
        }
        _scalar = body.to_string();
        if (_notes.is_value()) {
            var block = _YamlBlock();
            block.value = _scalar;
            block.header = header;
            block.explicit = explicit;
            block.lines = lines;
            _notes.value().blocks[path] = block;
        }
        if (!_scalar_node(_scalar, false, anchor, tag, tag_at, before, path)) {
            return false;
        }
        _inline = false;
        return true;
    }

    # Folds the first `count` lines of a `>` scalar into `out`: a line
    # break between two lines of text is a space, and a blank line a line
    # break, except around lines indented further, which keep their breaks.
    _fold_block(out: StringBuilder, lines: Array<String>, count: ulong) {
        ulong blank = 0;
        var started = false;
        var previous_more = false;
        for (var index in 0..count) {
            var line = lines[index];
            if (line.is_empty) {
                blank = blank + 1;
                continue;
            }
            var more = line.byte_at(0) == ' ' || line.byte_at(0) == '\t';
            if (!started) {
                out.append("\n".repeat(blank));
            } else if (!more && !previous_more) {
                out.append(blank == 0 ? " " : "\n".repeat(blank));
            } else {
                out.append("\n".repeat(blank + 1));
            }
            out.append(line);
            started = true;
            previous_more = more;
            blank = 0;
        }
    }

    # Makes `_value` the scalar `text` (`plain` when it was neither quoted
    # nor a block scalar) under the tag `tag`, and registers `anchor` for
    # it. `before` is `_nodes` before it began.
    _scalar_node(
        text: String, plain: bool, anchor: String, tag: String, tag_at: ulong, before: ulong, path: String
    ): bool {
        _nodes = _nodes + 1;
        if (tag.is_empty) {
            _value = plain ? _yaml_resolve(text) : YamlValue.String(text);
        } else if (tag == "!" || tag == CORE_TAG + "str") {
            _value = YamlValue.String(text);
        } else if (tag == CORE_TAG + "null") {
            _value = _yaml_resolve(text);
            if (!(_value is Null)) {
                return _fail_at($"'{text}' is not a null", tag_at);
            }
        } else if (tag == CORE_TAG + "bool") {
            _value = _yaml_resolve(text);
            if (!(_value is Bool)) {
                return _fail_at($"'{text}' is not a boolean", tag_at);
            }
        } else if (tag == CORE_TAG + "int" || tag == CORE_TAG + "float") {
            var number = _yaml_number(text);
            var integer = tag == CORE_TAG + "int";
            if (number.is_empty() || (integer && !(number.value() is Integer))) {
                return _fail_at($"'{text}' is not {integer ? "an integer" : "a float"}", tag_at);
            }
            _value = number.value();
            if (!integer) {
                _value = YamlValue.Float(_value.as_float().value());
            }
        } else if (tag == CORE_TAG + "seq" || tag == CORE_TAG + "map") {
            return _fail_at($"'{_tag_name(tag)}' cannot tag a scalar", tag_at);
        } else {
            return _fail_at($"unknown tag '{_tag_name(tag)}'", tag_at);
        }
        if (plain && !(_value is String) && !path.is_empty && _notes.is_value()) {
            _notes.value().plain[path] = text;
        }
        _register(anchor, before);
        return true;
    }

    # Makes `_value` an empty node: `Null`, `""` under `!!str`, or an empty
    # collection under `!!seq` or `!!map`.
    _empty(anchor: String, tag: String, tag_at: ulong): bool {
        var before = _nodes;
        if (tag == CORE_TAG + "seq" || tag == CORE_TAG + "map") {
            _nodes = _nodes + 1;
            _value = tag == CORE_TAG + "seq" ? YamlValue.sequence() : YamlValue.mapping();
            _register(anchor, before);
        } else if (!_scalar_node("", true, anchor, tag, tag_at, before, "")) {
            return false;
        }
        _inline = false;
        return true;
    }

    # Checks that a collection of `kind` (`seq` or `map`) may carry `tag`.
    _collection_tag(tag: String, kind: String): bool {
        if (tag.is_empty || tag == "!" || tag == CORE_TAG + kind) {
            return true;
        }
        var known = tag == CORE_TAG + "str"
            || tag == CORE_TAG + "int"
            || tag == CORE_TAG + "float"
            || tag == CORE_TAG + "bool"
            || tag == CORE_TAG + "null"
            || tag == CORE_TAG + "seq"
            || tag == CORE_TAG + "map";
        if (known) {
            return _fail_at($"'{_tag_name(tag)}' cannot tag a {kind == "seq" ? "sequence" : "mapping"}", _tag_at);
        }
        return _fail_at($"unknown tag '{_tag_name(tag)}'", _tag_at);
    }

    # How an error names a tag: `!!int` for a core tag, else as resolved.
    _tag_name(tag: String): String {
        if (tag.starts_with(CORE_TAG)) {
            return "!!" + tag.substr_bytes(CORE_TAG.size, tag.size - CORE_TAG.size);
        }
        return tag;
    }

    # ── Properties and aliases ─────────────────────────────────────────────

    # Reads a node's anchor and tag, in either order, into `_anchor`,
    # `_tag` and `_tag_at`.
    _properties(): bool {
        _anchor = "";
        _tag = "";
        _tag_at = 0;
        var anchor_seen = false;
        var tag_seen = false;
        while (_peek() == '&' || _peek() == '!') {
            var start = _position;
            if (_peek() == '&') {
                if (anchor_seen) {
                    return _fail("a node can have only one anchor");
                }
                anchor_seen = true;
                _position = _position + 1;
                _anchor = _anchor_name();
                if (_anchor.is_empty) {
                    return _fail_at("expected an anchor name after '&'", start);
                }
            } else {
                if (tag_seen) {
                    return _fail("a node can have only one tag");
                }
                tag_seen = true;
                _tag_at = start;
                if (!_tag_token()) {
                    return false;
                }
            }
            if (!_is_space_or_end(_position) && !(_flow > 0 && _is_flow_indicator(_peek()))) {
                return _fail("expected a space after the node's properties");
            }
            _skip_space();
        }
        return true;
    }

    # Reads a tag at the position, a '!', into `_tag`, resolving its handle.
    _tag_token(): bool {
        var start = _position;
        if (_at(_position + 1) == '<') {
            var close = _text.find(">", _position);
            if (close < 0) {
                return _fail("expected '>' to end the verbatim tag");
            }
            _tag = _text.substr_bytes(_position + 2, close as ulong - _position - 2);
            _position = close as ulong + 1;
            return true;
        }
        while (_position < _size && !_is_blank(_peek()) && !_is_break(_peek())) {
            if (_flow > 0 && _is_flow_indicator(_peek())) {
                break;
            }
            _position = _position + 1;
        }
        var token = _text.substr_bytes(start, _position - start);
        if (token == "!") {
            _tag = "!";
            return true;
        }
        var handle = "!";
        var second = token.find("!", 1);
        if (second > 0) {
            handle = token.substr_bytes(0, second as ulong + 1);
        }
        var suffix = token.substr_bytes(handle.size, token.size - handle.size);
        var prefix = _handles.try_get(handle);
        if (prefix.is_value()) {
            _tag = prefix.value() + suffix;
        } else if (handle == "!!") {
            _tag = CORE_TAG + suffix;
        } else if (handle == "!") {
            _tag = token;
        } else {
            return _fail_at($"undefined tag handle '{handle}'", start);
        }
        return true;
    }

    # Reads an anchor's name: the characters up to a blank, a line break or
    # a flow indicator.
    _anchor_name(): String {
        var start = _position;
        while (_position < _size && !_is_blank(_peek()) && !_is_break(_peek()) && !_is_flow_indicator(_peek())) {
            _position = _position + 1;
        }
        return _text.substr_bytes(start, _position - start);
    }

    # Reads an alias, `*name`, into `_value`.
    _alias(): bool {
        var start = _position;
        _position = _position + 1;
        var name = _anchor_name();
        if (name.is_empty) {
            return _fail_at("expected an anchor name after '*'", start);
        }
        var found = _anchors.try_get(name);
        if (found.is_empty()) {
            return _fail_at($"undefined alias '{name}'", start);
        }
        var size = _anchor_sizes[name];
        _expanded = _expanded + size;
        _nodes = _nodes + size;
        if (_expanded > _max_alias_nodes) {
            return _fail_at(
                $"the aliases stand for more than {_max_alias_nodes} nodes; raise 'max_alias_nodes' to read this document",
                start
            );
        }
        _value = found.value();
        _inline = true;
        _json_like = false;
        return true;
    }

    # Names `_value` `anchor`, unless it is empty; `before` is `_nodes`
    # before the value began.
    _register(anchor: String, before: ulong) {
        if (anchor.is_empty) {
            return;
        }
        _anchors[anchor] = _value;
        _anchor_sizes[anchor] = _nodes - before;
    }

    # ── Flow collections ───────────────────────────────────────────────────

    # Reads a `[...]` or `{...}` collection.
    _flow_collection(path: String, anchor: String, tag: String, tag_at: ulong): bool {
        var open = _position;
        if (_flow == 0) {
            _flow_indent = _scalar_indent;
        }
        var sequence = _peek() == '[';
        if (!_enter() || !_collection_tag(tag, sequence ? "seq" : "map")) {
            return false;
        }
        var before = _nodes;
        _nodes = _nodes + 1;
        _style(path, FLOW);
        _position = _position + 1;
        _flow = _flow + 1;
        var close = sequence ? ']' : '}';
        var items = Array<YamlValue>();
        var members = OrderedMap<String, YamlValue>();
        while (true) {
            if (!_skip_to_content()) {
                return false;
            }
            if (_position >= _size) {
                return _fail_at(sequence ? "expected ']' to end this '['" : "expected '}' to end this '{'", open);
            }
            if (_peek() == close) {
                _position = _position + 1;
                break;
            }
            var entry_path = sequence ? $"{path}[{items.count}]" : path + "?";
            var entry_at = _position;
            var explicit = _peek() == '?'
                && (_is_space_or_end(_position + 1) || _is_flow_indicator(_at(_position + 1)));
            if (explicit) {
                _position = _position + 1;
                if (!_skip_to_content()) {
                    return false;
                }
            }
            var has_key = false;
            var empty_key = _peek() == ':'
                && (_is_space_or_end(_position + 1) || _is_flow_indicator(_at(_position + 1)));
            if ((explicit && (_peek() == ',' || _peek() == close))
                || (_peek() == ':' && (explicit || !sequence || empty_key))) {
                _value = YamlValue.Null;
                _json_like = false;
            } else if (!_flow_node(entry_path)) {
                return false;
            }
            var node = _value;
            var json_like = _json_like;
            var node_end = _position;
            if (!_skip_to_content()) {
                return false;
            }
            var same_line = !_text.substr_bytes(node_end, _position - node_end).contains("\n");
            var pair = _peek() == ':'
                && (!sequence || explicit || same_line)
                && (json_like
                    || _is_space_or_end(_position + 1)
                    || _is_flow_indicator(_at(_position + 1))
                    || _at(_position + 1) == 0);
            var key = "";
            if (pair || explicit || !sequence) {
                _value = node;
                if (!_key_text(entry_at)) {
                    return false;
                }
                key = _scalar;
                has_key = true;
            }
            var member = YamlValue.Null;
            if (pair) {
                _position = _position + 1;
                if (!_skip_to_content()) {
                    return false;
                }
                var key_path = sequence ? $"{entry_path}{_yaml_path_key("", key)}" : _yaml_path_key(path, key);
                if (_peek() != ',' && _peek() != close) {
                    if (!_flow_node(key_path)) {
                        return false;
                    }
                    member = _value;
                }
            }
            if (!sequence) {
                if (members.contains(key)) {
                    return _fail_at($"duplicate key '{key}'", entry_at);
                }
                members[key] = member;
            } else if (has_key) {
                var single = YamlValue.mapping();
                single[key] = member;
                items.append(single);
            } else {
                items.append(node);
            }
            if (!_skip_to_content()) {
                return false;
            }
            if (_peek() == ',') {
                _position = _position + 1;
                continue;
            }
            if (_peek() == close) {
                _position = _position + 1;
                break;
            }
            if (_position >= _size) {
                return _fail_at(sequence ? "expected ']' to end this '['" : "expected '}' to end this '{'", open);
            }
            return _fail(sequence ? "expected ',' or ']'" : "expected ',' or '}'");
        }
        _flow = _flow - 1;
        _depth = _depth - 1;
        _value = sequence ? YamlValue.Sequence(items) : YamlValue.Mapping(members);
        _inline = true;
        _json_like = true;
        _register(anchor, before);
        return true;
    }

    # Reads a node inside a flow collection.
    _flow_node(path: String): bool {
        _note_offset(path);
        var anchor = "";
        var tag = "";
        ulong tag_at = 0;
        if (_peek() == '&' || _peek() == '!') {
            if (!_properties()) {
                return false;
            }
            anchor = _anchor;
            tag = _tag;
            tag_at = _tag_at;
            if (!_skip_to_content()) {
                return false;
            }
        }
        var b = _peek();
        if (b == ',' || b == ']' || b == '}' || (b == ':' && _is_space_or_end(_position + 1))) {
            if (anchor.is_empty && tag.is_empty) {
                return _fail("expected a value");
            }
            _json_like = false;
            return _empty(anchor, tag, tag_at);
        }
        if (b == '*') {
            if (!anchor.is_empty || !tag.is_empty) {
                return _fail("an alias cannot have an anchor or a tag");
            }
            return _alias();
        }
        if (b == '[' || b == '{') {
            return _flow_collection(path, anchor, tag, tag_at);
        }
        var before = _nodes;
        if (b == '"' || b == '\'') {
            if (!(b == '"' ? _double_quoted() : _single_quoted())) {
                return false;
            }
            _style(path, b == '"' ? DOUBLE_QUOTED : SINGLE_QUOTED);
            return _scalar_node(_scalar, false, anchor, tag, tag_at, before, path);
        }
        if (b == '#' || !_plain_start()) {
            return b == '#' ? _fail("expected a value") : false;
        }
        _plain(-1, true);
        _json_like = false;
        return _scalar_node(_scalar, true, anchor, tag, tag_at, before, path);
    }

    # ── Comments and layout ────────────────────────────────────────────────

    # After a value on the position's line: a comment, filed as the
    # value's, and then the line's end.
    _end_line(path: String): bool {
        if (!_inline) {
            return true;
        }
        _inline = false;
        _skip_space();
        if (!_take_trailing(path)) {
            return false;
        }
        if (!_at_line_end()) {
            if (_peek() == ':') {
                return _fail("unexpected ':'; quote a value that holds ': '");
            }
            return _fail("expected a line break after the value");
        }
        return true;
    }

    # At a comment or the line's end: files the comment as the trailing
    # comment of the value at `path`, and moves to the line's end.
    _take_trailing(path: String): bool {
        if (_peek() != '#') {
            return true;
        }
        if (_position > 0 && !_is_blank(_at(_position - 1)) && !_is_break(_at(_position - 1))) {
            return _fail("a comment needs a space before its '#'");
        }
        var start = _position;
        _skip_comment();
        if (_notes.is_value() && !path.is_empty && _flow == 0) {
            _notes.value().trailing[path] = _text.substr_bytes(start, _position - start);
        }
        return true;
    }

    # Skips blanks, comments and line breaks up to the next content, filing
    # each comment line and blank line as pending. A tab in a line's
    # indentation is an error outside flow collections.
    _skip_to_content(): bool {
        var fresh = _position == 0 || _is_break(_at(_position - 1));
        while (true) {
            var line_start = _position;
            _skip_space();
            if (_position >= _size) {
                return true;
            }
            var b = _peek();
            if (b == '#') {
                if (_position > 0 && !_is_blank(_at(_position - 1)) && !_is_break(_at(_position - 1))) {
                    return _fail("a comment needs a space before its '#'");
                }
                var start = _position;
                _skip_comment();
                _pend(_text.substr_bytes(start, _position - start), _column(start));
                fresh = false;
                continue;
            }
            if (_is_break(b)) {
                if (fresh) {
                    _pend("", 0);
                }
                _line_break();
                fresh = true;
                continue;
            }
            if (_flow > 0 && fresh) {
                if (_at_marker("---") || _at_marker("...")) {
                    return _fail("a document marker cannot be inside a flow collection");
                }
                # A closing bracket at the parent's column is common, and kept.
                var closing = _peek() == ']' || _peek() == '}';
                if (_flow_indent >= 0 && !closing && (_spaces(_position) as long) <= _flow_indent) {
                    return _fail(
                        "a line inside a flow collection must be indented past column " + to_string(_flow_indent + 1)
                    );
                }
            }
            return true;
        }
        return true;
    }

    # Whether `at` is the first content of its line and the blanks before
    # it hold a tab.
    _has_tab_indent(at: ulong): bool {
        var index = at;
        while (index > 0 && _is_blank(_at(index - 1))) {
            index = index - 1;
        }
        return (index == 0 || _is_break(_at(index - 1))) && _tab_before(at);
    }

    # Whether the blanks right before `at` hold a tab.
    _tab_before(at: ulong): bool {
        var index = at;
        while (index > 0 && _is_blank(_at(index - 1))) {
            index = index - 1;
            if (_at(index) == '\t') {
                return true;
            }
        }
        return false;
    }

    # How many spaces start the line of `at`: its indentation, which tabs
    # are not part of.
    _spaces(at: ulong): ulong {
        var index = at;
        while (index > 0 && !_is_break(_at(index - 1))) {
            index = index - 1;
        }
        ulong count = 0;
        while (_at(index + count) == ' ') {
            count = count + 1;
        }
        return count;
    }

    # Files a comment or blank line, when keeping comments.
    _pend(text: String, column: ulong) {
        if (_notes.is_empty() || _flow > 0) {
            return;
        }
        var line = _YamlLine();
        line.text = text;
        line.column = column;
        _pending.append(line);
    }

    # The pending lines' text, emptying them.
    _take_pending(): Array<String> {
        var out = Array<String>();
        for (var line in _pending) {
            out.append(line.text);
        }
        _pending = Array<_YamlLine>();
        return out;
    }

    # Files the pending lines as the ones before the value at `path`.
    _file_before(path: String) {
        _file(path, _take_pending());
    }

    _file(path: String, lines: Array<String>) {
        if (_notes.is_value()) {
            _notes.value().add(_notes.value().before, path, lines);
        }
    }

    # At the end of the collection at `path`, whose entries are at
    # `column`: the pending lines up to the last comment indented at least
    # as far are its closing lines; the rest wait for the next value.
    _file_end(path: String, column: ulong) {
        if (_notes.is_empty()) {
            return;
        }
        long last = -1;
        for (var index in 0.._pending.count) {
            if (!_pending[index].text.is_empty && _pending[index].column >= column) {
                last = index as long;
            }
        }
        var closing = Array<String>();
        var rest = Array<_YamlLine>();
        for (var index in 0.._pending.count) {
            if ((index as long) <= last) {
                closing.append(_pending[index].text);
            } else {
                rest.append(_pending[index]);
            }
        }
        _pending = rest;
        _notes.value().add(_notes.value().end, path, closing);
    }

    # Files `style` for the value at `path`.
    _style(path: String, style: int) {
        if (_notes.is_value() && !path.is_empty) {
            _notes.value().styles[path] = style;
        }
    }

    # Files the position as where the value at `path` is, for `decode`.
    _note_offset(path: String) {
        if (_offsets.is_value() && !_offsets.value().contains(path)) {
            _offsets.value()[path] = _position;
        }
    }

    # ── Characters ─────────────────────────────────────────────────────────

    # Counts a collection's nesting, failing past `_max_depth`. Each
    # collection takes one level off when it ends.
    _enter(): bool {
        _depth = _depth + 1;
        if (_depth > _max_depth) {
            return _fail($"collections nest more than {_max_depth} deep");
        }
        return true;
    }

    _peek(): byte {
        return _at(_position);
    }

    _at(index: ulong): byte {
        if (index < _size) {
            return _text.byte_at(index);
        }
        return 0;
    }

    _is_blank(b: byte): bool {
        return b == ' ' || b == '\t';
    }

    _is_break(b: byte): bool {
        return b == '\n' || b == '\r';
    }

    _is_flow_indicator(b: byte): bool {
        return b == ',' || b == '[' || b == ']' || b == '{' || b == '}';
    }

    _is_space_or_end(index: ulong): bool {
        return index >= _size || _is_blank(_at(index)) || _is_break(_at(index));
    }

    _at_line_end(): bool {
        return _position >= _size || _is_break(_peek());
    }

    # Whether the position is at indicator `b` (`-`, `?` or `:`) followed by
    # a space or the line's end.
    _at_indicator(b: byte): bool {
        return _peek() == b && _is_space_or_end(_position + 1);
    }

    # Whether the position starts a line with `marker` (`---` or `...`)
    # followed by a space or the line's end.
    _at_marker(marker: String): bool {
        if (_position + 3 > _size || (_position > 0 && !_is_break(_at(_position - 1)))) {
            return false;
        }
        return _text.substr_bytes(_position, 3) == marker && _is_space_or_end(_position + 3);
    }

    # The column of byte `at`, from 0.
    _column(at: ulong): ulong {
        var index = at;
        while (index > 0 && _text.byte_at(index - 1) != '\n') {
            index = index - 1;
        }
        return at - index;
    }

    _skip_space() {
        while (_is_blank(_peek())) {
            _position = _position + 1;
        }
    }

    # Moves to the end of the comment's line.
    _skip_comment() {
        while (_position < _size && !_is_break(_peek())) {
            _position = _position + 1;
        }
    }

    # Moves past a line break, `\n`, `\r\n` or `\r`, if there is one.
    _line_break() {
        if (_peek() == '\r' && _at(_position + 1) == '\n') {
            _position = _position + 2;
        } else if (_is_break(_peek())) {
            _position = _position + 1;
        }
    }

    # Reads characters up to a blank or line break.
    _token(): String {
        var start = _position;
        while (_position < _size && !_is_blank(_peek()) && !_is_break(_peek())) {
            _position = _position + 1;
        }
        return _text.substr_bytes(start, _position - start);
    }

    _fail(message: String): bool {
        return _fail_at(message, _position);
    }

    # Records the error `message` at byte `offset`, and returns false.
    _fail_at(message: String, offset: ulong): bool {
        _error = YamlError(message, _path);
        _yaml_place(_error, _text, offset);
        return false;
    }
}
