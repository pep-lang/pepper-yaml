# The yaml package's writer: block style, quoting only what needs it, and
# text that reads back as the value written.

import yaml;

# Writes `value`, reads it back and writes it again: the two texts match.
round_trip(value: yaml.YamlValue): String {
    var written = value.to_string();
    var read = yaml.parse(written);
    if (read.is_err()) {
        print(written);
        print(read.error().to_string());
        panic("the written text does not parse");
    }
    expect_equal(read.value().to_string(), written);
    return written;
}

[Test]
writes_block_style() {
    var root = yaml.YamlValue.mapping();
    root["name"] = yaml.YamlValue.String("demo");
    var server = yaml.YamlValue.mapping();
    server["port"] = yaml.YamlValue.Integer(8080);
    server["ratio"] = yaml.YamlValue.Float(0.5);
    server["whole"] = yaml.YamlValue.Float(2.0);
    server["debug"] = yaml.YamlValue.Bool(false);
    server["none"] = yaml.YamlValue.Null;
    root["server"] = server;
    var hosts = yaml.YamlValue.sequence();
    hosts.append(yaml.YamlValue.String("a"));
    var entry = yaml.YamlValue.mapping();
    entry["host"] = yaml.YamlValue.String("b");
    entry["weight"] = yaml.YamlValue.Integer(2);
    hosts.append(entry);
    hosts.append(yaml.YamlValue.sequence([yaml.YamlValue.Integer(1), yaml.YamlValue.Integer(2)]));
    hosts.append(yaml.YamlValue.sequence());
    root["hosts"] = hosts;
    root["empty"] = yaml.YamlValue.mapping();
    expect_equal(
        round_trip(root),
        "name: demo\nserver:\n  port: 8080\n  ratio: 0.5\n  whole: 2.0\n  debug: false\n  none: null\nhosts:\n  - a\n  - host: b\n    weight: 2\n  - - 1\n    - 2\n  - []\nempty: {}\n"
    );
}

[Test]
quotes_only_what_needs_it() {
    var root = yaml.YamlValue.mapping();
    var texts = [
        "plain words",
        "yes",
        "true",
        "null",
        "~",
        "",
        "42",
        "0x1f",
        "1.5",
        ".inf",
        "- dash",
        "a: b",
        "a #b",
        "#hash",
        "trailing ",
        " leading",
        "[x]",
        "&anchor",
        "*alias",
        "!tag",
        "|",
        ">",
        "'q'",
        "\"q\"",
        "%p",
        "@at",
        "---",
        "tab\there",
        "ü and 😀",
        "a:b",
        "a#b",
        "key:"
    ];
    for (var index in 0..texts.count) {
        root[$"k{index}"] = yaml.YamlValue.String(texts[index]);
    }
    var written = round_trip(root);
    var read = yaml.parse(written).value();
    for (var index in 0..texts.count) {
        expect_equal(read[$"k{index}"].as_string().value(), texts[index]);
    }
    expect_true(written.contains("k0: plain words\n"));
    expect_true(written.contains("k1: \"yes\"\n"));
    expect_true(written.contains("k28: ü and 😀\n"));
    expect_true(written.contains("k29: a:b\n"));
}

[Test]
writes_line_breaks_as_literal_blocks() {
    var root = yaml.YamlValue.mapping();
    root["one"] = yaml.YamlValue.String("a\nb\n");
    root["strip"] = yaml.YamlValue.String("a\nb");
    root["keep"] = yaml.YamlValue.String("a\n\n");
    root["indented"] = yaml.YamlValue.String("  a\nb\n");
    root["spaces"] = yaml.YamlValue.String("a\n  \nb");
    root["control"] = yaml.YamlValue.String("a\rb\n");
    var list = yaml.YamlValue.sequence([yaml.YamlValue.String("x\ny\n")]);
    root["list"] = list;
    var written = round_trip(root);
    expect_true(
        written.starts_with("one: |\n  a\n  b\nstrip: |-\n  a\n  b\nkeep: |+\n  a\n\nindented: |2\n    a\n  b\n")
    );
    expect_true(written.contains("spaces: \"a\\n  \\nb\"\n"));
    expect_true(written.contains("control: \"a\\rb\\n\"\n"));
    expect_true(written.contains("list:\n  - |\n    x\n    y\n"));
    var read = yaml.parse(written).value();
    expect_equal(read["keep"].as_string().value(), "a\n\n");
    expect_equal(read["indented"].as_string().value(), "  a\nb\n");
}

[Test]
writes_keys_and_scalars() {
    var root = yaml.YamlValue.mapping();
    root["a key"] = yaml.YamlValue.Integer(1);
    root["a: b"] = yaml.YamlValue.Integer(2);
    root[""] = yaml.YamlValue.Integer(3);
    root["true"] = yaml.YamlValue.Integer(4);
    root["nan"] = yaml.YamlValue.Float(0.0 / 0.0);
    root["inf"] = yaml.YamlValue.Float(-1.0 / 0.0);
    root["big"] = yaml.YamlValue.Float(1e20);
    expect_equal(round_trip(root), "a key: 1\n\"a: b\": 2\n\"\": 3\ntrue: 4\nnan: .nan\ninf: -.inf\nbig: 1e+20\n");
    expect_equal(yaml.YamlValue.Null.to_string(), "null\n");
    expect_equal(yaml.YamlValue.String("x").to_string(), "x\n");
}

[Test]
writes_several_documents() {
    var map = yaml.YamlValue.mapping();
    map["a"] = yaml.YamlValue.Integer(1);
    var text = yaml.write_all([map, yaml.YamlValue.String("x\ny\n"), yaml.YamlValue.sequence()]);
    expect_equal(text, "---\na: 1\n---\n|\n  x\n  y\n--- []\n");
    var read = yaml.parse_all(text).value();
    expect_equal(read.count, 3);
    expect_equal(read[1].as_string().value(), "x\ny\n");
}
