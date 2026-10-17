# The yaml package's parser: the core schema, block and flow collections,
# scalars of every style, anchors, tags, documents, and errors with their
# line and column.

import text;
import yaml;

parsed(source: String): yaml.YamlValue {
    var result = yaml.parse(source);
    if (result.is_err()) {
        print(result.error().to_string());
        panic("parse failed");
    }
    return result.value();
}

error_of(source: String): String {
    var result = yaml.parse(source, path = "test.yaml");
    expect_true(result.is_err());
    return result.error().to_string();
}

[Test]
reads_the_core_schema() {
    var root = parsed(
        "a: null\nb: ~\nc:\nd: true\ne: False\nf: yes\ng: no\nh: on\ni: 42\nj: -7\nk: 0x1f\nl: 0o17\nm: 1.5\nn: 6.02e23\no: .inf\np: -.Inf\nq: .nan\nr: 1_000\ns: 012\nt: +3\nu: 1.\n"
    );
    expect_true(root["a"].is_null());
    expect_true(root["b"].is_null());
    expect_true(root["c"].is_null());
    expect_true(root["d"].as_bool().value());
    expect_false(root["e"].as_bool().value());
    expect_equal(root["f"].as_string().value(), "yes");
    expect_equal(root["g"].as_string().value(), "no");
    expect_equal(root["h"].as_string().value(), "on");
    expect_equal(root["i"].as_int().value(), 42);
    expect_equal(root["j"].as_int().value(), -7);
    expect_equal(root["k"].as_int().value(), 31);
    expect_equal(root["l"].as_int().value(), 15);
    expect_equal(root["m"].as_float().value(), 1.5);
    expect_equal(root["n"].as_float().value(), 6.02e23);
    expect_true(root["o"].as_float().value() > 1e308);
    expect_true(root["p"].as_float().value() < -1e308);
    var nan = root["q"].as_float().value();
    expect_true(nan != nan);
    expect_equal(root["r"].as_string().value(), "1_000");
    expect_equal(root["s"].as_int().value(), 12);
    expect_equal(root["t"].as_int().value(), 3);
    expect_equal(root["u"].type_name(), "float");
}

[Test]
reads_block_collections() {
    var root = parsed(
        "server:\n  host: localhost\n  ports:\n    - 80\n    - 443\nusers:\n- name: ada\n  admin: true\n- name: bob\n-\n- - nested\n  - again\n"
    );
    expect_equal(root["server"]["host"].as_string().value(), "localhost");
    expect_equal(root["server"]["ports"][1].as_int().value(), 443);
    expect_equal(root["users"][0]["name"].as_string().value(), "ada");
    expect_true(root["users"][0]["admin"].as_bool().value());
    expect_equal(root["users"][1]["name"].as_string().value(), "bob");
    expect_true(root["users"][2].is_null());
    expect_equal(root["users"][3][1].as_string().value(), "again");
    expect_equal(root["users"].as_sequence().value().count, 4);
}

[Test]
keeps_key_order() {
    var root = parsed("zebra: 1\napple: 2\nmango: 3\n");
    var keys = Array<String>();
    for (var (key, member) in root.as_mapping().value()) {
        keys.append(key);
    }
    expect_equal(keys.count, 3);
    expect_equal(keys[0], "zebra");
    expect_equal(keys[2], "mango");
}

[Test]
reads_flow_collections() {
    var root = parsed(
        "list: [a, 'b c', \"d\", [1, 2], {x: 1}]\nmap: {a: 1, b: [true], c: , \"d\":e}\npairs: [one: 1, two]\nempty: [[], {}]\nmulti: [\n  a,\n  b, # a comment\n]\n"
    );
    expect_equal(root["list"][1].as_string().value(), "b c");
    expect_equal(root["list"][3][1].as_int().value(), 2);
    expect_equal(root["list"][4]["x"].as_int().value(), 1);
    expect_true(root["map"]["b"][0].as_bool().value());
    expect_true(root["map"]["c"].is_null());
    expect_equal(root["map"]["d"].as_string().value(), "e");
    expect_equal(root["pairs"][0]["one"].as_int().value(), 1);
    expect_equal(root["pairs"][1].as_string().value(), "two");
    expect_true(root["empty"][0].as_sequence().value().is_empty);
    expect_true(root["empty"][1].as_mapping().value().is_empty);
    expect_equal(root["multi"].as_sequence().value().count, 2);
}

[Test]
reads_plain_scalars() {
    var root = parsed(
        "url: http://example.com:8080/a#b\nfolded: one\n  two\n\n  three\ncolon: a:b\nhash: a#b\nkey with spaces: v\n-dash: 1\n? explicit\n: value\n"
    );
    expect_equal(root["url"].as_string().value(), "http://example.com:8080/a#b");
    expect_equal(root["folded"].as_string().value(), "one two\nthree");
    expect_equal(root["colon"].as_string().value(), "a:b");
    expect_equal(root["hash"].as_string().value(), "a#b");
    expect_equal(root["key with spaces"].as_string().value(), "v");
    expect_equal(root["-dash"].as_int().value(), 1);
    expect_equal(root["explicit"].as_string().value(), "value");
}

[Test]
reads_quoted_scalars() {
    var root = parsed(
        "double: \"tab\\there \\u00e9 \\U0001F600 \\x41 \\\" \\\\ \\/\"\nsingle: 'it''s \\n raw'\nfolded: \"one\n  two\n\n  three\"\njoined: \"a\\\n   b\"\nkey: \"1\"\n"
    );
    expect_equal(root["double"].as_string().value(), "tab\there é 😀 A \" \\ /");
    expect_equal(root["single"].as_string().value(), "it's \\n raw");
    expect_equal(root["folded"].as_string().value(), "one two\nthree");
    expect_equal(root["joined"].as_string().value(), "ab");
    expect_equal(root["key"].as_string().value(), "1");
}

[Test]
reads_block_scalars() {
    var root = parsed(
        "literal: |\n  line one\n    indented\n  line three\nfolded: >\n  one\n  two\n\n  three\n    kept\n  four\nstrip: |-\n  text\n\n\nkeep: |+\n  text\n\n\nindicated: |2\n    four spaces\nlast: x\n"
    );
    expect_equal(root["literal"].as_string().value(), "line one\n  indented\nline three\n");
    expect_equal(root["folded"].as_string().value(), "one two\nthree\n  kept\nfour\n");
    expect_equal(root["strip"].as_string().value(), "text");
    expect_equal(root["keep"].as_string().value(), "text\n\n\n");
    expect_equal(root["indicated"].as_string().value(), "  four spaces\n");
    expect_equal(root["last"].as_string().value(), "x");
    var top = parsed("--- |\n  a\n  b\n");
    expect_equal(top.as_string().value(), "a\nb\n");
}

[Test]
reads_anchors_and_aliases() {
    var root = parsed(
        "base: &base\n  host: localhost\n  port: 80\ncopy: *base\nname: &n ada\nagain: *n\nlist: [&x 1, *x]\n"
    );
    expect_equal(root["copy"]["port"].as_int().value(), 80);
    expect_equal(root["again"].as_string().value(), "ada");
    expect_equal(root["list"][1].as_int().value(), 1);
    # An alias is its anchor's value, shared.
    root["base"]["port"] = yaml.YamlValue.Integer(81);
    expect_equal(root["copy"]["port"].as_int().value(), 81);
    expect_equal(error_of("a: *missing\n"), "test.yaml:1:4: error: undefined alias 'missing'");
}

[Test]
stops_a_billion_laughs() {
    var bomb = "a: &a [x, x, x, x, x, x, x, x, x, x]\nb: &b [*a, *a, *a, *a, *a, *a, *a, *a, *a, *a]\nc: &c [*b, *b, *b, *b, *b, *b, *b, *b, *b, *b]\nd: &d [*c, *c, *c, *c, *c, *c, *c, *c, *c, *c]\ne: &e [*d, *d, *d, *d, *d, *d, *d, *d, *d, *d]\nf: &f [*e, *e, *e, *e, *e, *e, *e, *e, *e, *e]\n";
    var result = yaml.parse(bomb);
    expect_true(result.is_err());
    expect_true(result.error().message.starts_with("the aliases stand for more than 1000000 nodes"));
    expect_equal(result.error().line, 6);
    expect_true(yaml.parse(bomb, max_alias_nodes = 100000000).is_ok());
}

[Test]
reads_tags() {
    var root = parsed(
        "a: !!str 42\nb: !!int \"7\"\nc: !!float 1\nd: ! 12\ne: !!bool true\nf: !!map {x: 1}\ng: !!seq\n- 1\nh: !!str\n"
    );
    expect_equal(root["a"].as_string().value(), "42");
    expect_equal(root["b"].as_int().value(), 7);
    expect_equal(root["c"].type_name(), "float");
    expect_equal(root["d"].as_string().value(), "12");
    expect_true(root["e"].as_bool().value());
    expect_equal(root["f"]["x"].as_int().value(), 1);
    expect_equal(root["g"][0].as_int().value(), 1);
    expect_equal(root["h"].as_string().value(), "");
    var handled = parsed("%TAG !e! tag:yaml.org,2002:\n---\nn: !e!int 5\nv: !<tag:yaml.org,2002:str> 5\n");
    expect_equal(handled["n"].as_int().value(), 5);
    expect_equal(handled["v"].as_string().value(), "5");
    expect_equal(error_of("a: !python/object x\n"), "test.yaml:1:4: error: unknown tag '!python/object'");
    expect_equal(error_of("a: !!int nope\n"), "test.yaml:1:4: error: 'nope' is not an integer");
    expect_equal(error_of("a: !!str [1]\n"), "test.yaml:1:4: error: '!!str' cannot tag a sequence");
    expect_equal(error_of("a: !x!y 1\n"), "test.yaml:1:4: error: undefined tag handle '!x!'");
}

[Test]
reads_documents() {
    var documents = yaml.parse_all("# first\n--- 1\n--- two\n...\n---\nthree: 3\n...\n").value();
    expect_equal(documents.count, 3);
    expect_equal(documents[0].as_int().value(), 1);
    expect_equal(documents[1].as_string().value(), "two");
    expect_equal(documents[2]["three"].as_int().value(), 3);
    expect_true(parsed("").is_null());
    expect_true(parsed("# only a comment\n").is_null());
    expect_true(parsed("---\n").is_null());
    expect_true(yaml.parse_all("").value().is_empty);
    expect_equal(
        error_of("a: 1\n---\nb: 2\n"),
        "test.yaml:2:1: error: expected one document, found several; use 'parse_all' to read them"
    );
    expect_equal(parsed("%YAML 1.2\n---\na: 1\n")["a"].as_int().value(), 1);
    expect_equal(
        error_of("%YAML 2.0\n---\n"),
        "test.yaml:1:7: error: unsupported YAML version '2.0'; this package reads YAML 1.2"
    );
}

[Test]
reports_errors_where_they_are() {
    expect_equal(error_of("a: 1\na: 2\n"), "test.yaml:2:1: error: duplicate key 'a'");
    expect_equal(error_of("a:\n\tb: 1\n"), "test.yaml:2:2: error: a tab cannot indent YAML; use spaces");
    expect_equal(
        error_of("a: b: c\n"),
        "test.yaml:1:4: error: a mapping cannot start on the line of its key; start it on the next line"
    );
    expect_equal(error_of("a: \"open\n"), "test.yaml:1:4: error: unterminated string");
    expect_equal(error_of("a: [1, 2\n"), "test.yaml:1:4: error: expected ']' to end this '['");
    expect_equal(error_of("a: 1\n  b: 2\n"), "test.yaml:2:4: error: unexpected ':'; quote a value that holds ': '");
    expect_equal(
        error_of("a:\n  b:\n    c: 1\n   d: 2\n"),
        "test.yaml:4:4: error: unexpected indentation; a key of this mapping goes at column 3"
    );
    expect_equal(
        error_of("[a]: 1\n"),
        "test.yaml:1:1: error: a mapping key must be a scalar; this package reads no collections as keys"
    );
    expect_equal(error_of("a: \"\\q\"\n"), "test.yaml:1:5: error: invalid escape '\\q'");
}

[Test]
bounds_nesting() {
    var deep = "[".repeat(300) + "]".repeat(300);
    expect_equal(yaml.parse(deep).error().message, "collections nest more than 256 deep");
    expect_true(yaml.parse(deep, max_depth = 400).is_ok());
}

[Test]
decodes_utf16() {
    var little = text.Utf16.encode("\u{feff}a: é\n");
    expect_equal(yaml.parse(yaml.decode_text(little).value()).value()["a"].as_string().value(), "é");
    var big = text.Utf16.encode("a: 1\n", big_endian = true);
    expect_equal(yaml.parse(yaml.decode_text(big).value()).value()["a"].as_int().value(), 1);
    expect_equal(yaml.decode_text("a: 1".bytes()).value(), "a: 1");
    var thirty_two = Array<u8>();
    thirty_two.append(0);
    thirty_two.append(0);
    thirty_two.append(0);
    thirty_two.append(97);
    expect_true(yaml.decode_text(thirty_two).is_err());
}
