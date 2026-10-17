## `YamlValue`: a YAML value of any kind, as the core schema reads it.

import "write";

## A YAML value: `null`, a boolean, an integer, a float, a string, a
## sequence or a mapping. `yaml.parse` makes one from text and
## `to_string` writes it back.
##
## Look values up with `value["key"]` and `value[index]`. A lookup that
## finds nothing (a missing key, an index past the end, or a lookup on a
## value of another kind) gives `Null` rather than panicking, so lookups
## chain: `root["server"]["port"]`. Then read the value with an `as_`
## method, which gives none when the value is of another kind, or `match`
## on its case.
##
## A mapping's keys are strings: a key written as another scalar (`1:`,
## `true:`) is the text it was written as. A `Mapping` keeps its keys in
## the order they were written.
##
## A `Sequence` or `Mapping` case holds its array or map by reference, so
## changing them through `value[key] = ...`, `append` or the map from
## `as_mapping()` changes every holder of the value. An alias (`*name`) in
## the text is the very value its anchor names, not a copy.
##
## @example
##     import yaml;
##
##     var server = yaml.YamlValue.mapping();
##     server["host"] = yaml.YamlValue.String("localhost");
##     server["ports"] = yaml.YamlValue.sequence([yaml.YamlValue.Integer(80)]);
##     assert(server.to_string() == "host: localhost\nports:\n  - 80\n", "block style");
##     assert(server["ports"][0].as_int().value() == 80, "a lookup");
##     assert(server["missing"]["deeper"].is_null(), "lookups chain");
export enum YamlValue {
    ## `null`, `~`, or nothing at all.
    Null,
    ## `true` or `false`.
    ##
    ## @param value the boolean
    Bool(value: bool),
    ## A 64-bit integer: `42`, `-7`, `0x1f`, `0o17`.
    ##
    ## @param value the integer
    Integer(value: long),
    ## A 64-bit float: `1.5`, `6.02e23`, `.inf`, `.nan`.
    ##
    ## @param value the number
    Float(value: double),
    ## A string.
    ##
    ## @param value the text
    String(value: String),
    ## A sequence, holding its elements in order.
    ##
    ## @param items the elements
    Sequence(items: Array<YamlValue>),
    ## A mapping, holding its members in the order they were written.
    ##
    ## @param members the members, by key
    Mapping(members: OrderedMap<String, YamlValue>),

    ## Returns a new, empty mapping.
    ##
    ## @returns a `Mapping` with no members
    static mapping(): YamlValue {
        return YamlValue.Mapping(OrderedMap<String, YamlValue>());
    }

    ## Returns a sequence holding `items`, which it keeps by reference
    ## rather than copying.
    ##
    ## @param items the elements; an empty array when not given
    ## @returns a `Sequence` of `items`
    static sequence(items: Array<YamlValue> = Array<YamlValue>()): YamlValue {
        return YamlValue.Sequence(items);
    }

    ## Reads `value[key]`: the member named `key` of a mapping.
    ##
    ## @param key the member's key
    ## @returns the member, or `Null` when this is not a mapping or has no
    ##   member named `key`
    [](key: String): YamlValue {
        if (this is Mapping(members)) {
            var found = members.try_get(key);
            if (found.is_value()) {
                return found.value();
            }
        }
        return YamlValue.Null;
    }

    ## Writes `value[key] = member`: sets the member named `key` of a
    ## mapping. A new key goes at the end; an existing key keeps its place.
    ##
    ## @param key the member's key
    ## @param member the value to store
    ## @returns `member`, the value of the assignment expression
    ## @panics if this is not a mapping ("YamlValue[key] = value needs a
    ##   mapping")
    [](key: String, member: YamlValue): YamlValue {
        if (this is Mapping(members)) {
            members[key] = member;
            return member;
        }
        panic($"YamlValue[key] = value needs a mapping, not {_yaml_kind(this)}");
        return member;
    }

    ## Reads `value[index]`: an element of a sequence.
    ##
    ## @param index the element's position, from 0
    ## @returns the element, or `Null` when this is not a sequence or
    ##   `index` is past its end
    [](index: ulong): YamlValue {
        if (this is Sequence(items)) {
            if (index < items.count) {
                return items[index];
            }
        }
        return YamlValue.Null;
    }

    ## Writes `value[index] = element`: replaces an element of a sequence.
    ##
    ## @param index the element's position, from 0
    ## @param element the value to store
    ## @returns `element`, the value of the assignment expression
    ## @panics if this is not a sequence ("YamlValue[index] = value needs a
    ##   sequence")
    ## @panics if `index` is not less than the sequence's count (as
    ##   `Array`'s indexer does)
    [](index: ulong, element: YamlValue): YamlValue {
        if (this is Sequence(items)) {
            items[index] = element;
            return element;
        }
        panic($"YamlValue[index] = value needs a sequence, not {_yaml_kind(this)}");
        return element;
    }

    ## Appends `element` to the end of a sequence.
    ##
    ## @param element the value to append
    ## @panics if this is not a sequence ("YamlValue.append needs a
    ##   sequence")
    append(element: YamlValue) {
        if (this is Sequence(items)) {
            items.append(element);
            return;
        }
        panic($"YamlValue.append needs a sequence, not {_yaml_kind(this)}");
    }

    ## Returns whether this is a mapping with a member named `key`.
    ##
    ## @param key the key to look for
    ## @returns true when the member exists
    contains(key: String): bool {
        if (this is Mapping(members)) {
            return members.contains(key);
        }
        return false;
    }

    ## Removes the member named `key` from a mapping.
    ##
    ## @param key the key to remove
    ## @returns true when this is a mapping and the member was there
    remove(key: String): bool {
        if (this is Mapping(members)) {
            return members.remove(key);
        }
        return false;
    }

    ## Returns whether this is `Null`.
    ##
    ## @returns true for `Null`
    is_null(): bool {
        return this is Null;
    }

    ## Returns what kind of value this is, as errors name it: `null`,
    ## `boolean`, `integer`, `float`, `string`, `sequence` or `mapping`.
    ##
    ## @returns the kind's name
    type_name(): String {
        match (this) {
            Null => { return "null"; }
            Bool(value) => { return "boolean"; }
            Integer(value) => { return "integer"; }
            Float(value) => { return "float"; }
            String(value) => { return "string"; }
            Sequence(items) => { return "sequence"; }
            Mapping(members) => { return "mapping"; }
        }
        return "";
    }

    ## Returns the boolean, when this is one.
    ##
    ## @returns the value of a `Bool`, or none
    as_bool(): bool? {
        if (this is Bool(value)) {
            return Optional<bool>.Value(value);
        }
        return Optional<bool>.Empty;
    }

    ## Returns the integer, when this is one.
    ##
    ## @returns the value of an `Integer`, or none
    as_int(): long? {
        if (this is Integer(value)) {
            return Optional<long>.Value(value);
        }
        return Optional<long>.Empty;
    }

    ## Returns the number as a `double`, when this is a `Float` or an
    ## `Integer`.
    ##
    ## @returns the number, or none
    as_float(): double? {
        match (this) {
            Integer(value) => { return Optional<double>.Value(value as double); }
            Float(value) => { return Optional<double>.Value(value); }
            else => {}
        }
        return Optional<double>.Empty;
    }

    ## Returns the string, when this is one.
    ##
    ## @returns the text of a `String`, or none
    as_string(): String? {
        if (this is String(value)) {
            return Optional<String>.Value(value);
        }
        return Optional<String>.Empty;
    }

    ## Returns the elements, when this is a sequence. The array is the one
    ## this value holds, not a copy.
    ##
    ## @returns the elements of a `Sequence`, or none
    as_sequence(): Array<YamlValue>? {
        if (this is Sequence(items)) {
            return Optional<Array<YamlValue>>.Value(items);
        }
        return Optional<Array<YamlValue>>.Empty;
    }

    ## Returns the members, when this is a mapping. The map is the one this
    ## value holds, not a copy.
    ##
    ## @returns the members of a `Mapping`, or none
    as_mapping(): OrderedMap<String, YamlValue>? {
        if (this is Mapping(members)) {
            return Optional<OrderedMap<String, YamlValue>>.Value(members);
        }
        return Optional<OrderedMap<String, YamlValue>>.Empty;
    }

    ## Returns the value as a YAML document in block style: a mapping's
    ## members as `key: value` lines, a sequence's elements as `- value`
    ## lines, nested collections indented by two spaces, and a string with
    ## line breaks as a `|` literal block. Strings are quoted only when
    ## plain text would read back as something else.
    ##
    ## @returns the YAML text, ending with a line break
    ## @example
    ##     import yaml;
    ##
    ##     var root = yaml.parse("name: demo\ntags: [a, b]\n").value();
    ##     assert(root.to_string() == "name: demo\ntags:\n  - a\n  - b\n", "block style");
    to_string(): String {
        return _yaml_write(this, _YamlNotes());
    }
}

# How an error names a value's kind: "a string", "an integer".
export _yaml_kind(value: YamlValue): String {
    match (value) {
        Null => { return "null"; }
        Integer(value) => { return "an integer"; }
        else => {}
    }
    return $"a {value.type_name()}";
}
