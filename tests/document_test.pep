# The yaml package's `YamlDocument`: text read and written back keeps its
# comments and layout, and edits change only what they touch.

import yaml;

document_of(source: String): yaml.YamlDocument {
    var result = yaml.parse_document(source);
    if (result.is_err()) {
        print(result.error().to_string());
        panic("parse_document failed");
    }
    return result.value();
}

[Test]
writes_unchanged_text_back_as_it_was() {
    var texts = [
        "# A service.\nname: web # its name\n\nserver:\n  # Where it listens.\n  host: 0.0.0.0\n  port: 0x1f90\n  tls: ~\n  # closing the server\n\n# Hosts to call.\nhosts:\n  - a\n  # the backup\n  - b\nflags: [fast, 'quiet']\nmeta: {owner: ada, team: core}\nscript: |\n  echo one\n  echo two\nsummary: >-\n  one\n  two\nquoted: \"text\"\nsingle: 'text'\n# the end\n",
        "---\nlist:\n- a\n- b\nmap:\n    deep:\n        deeper: 1\n",
        "- name: a\n  value: 1\n- name: b\n  # about c\n  c: 2\n",
        "plain scalar\n",
        "- |2\n    leading spaces\n- >\n  folded\n  text\n\n- last\n",
    ];
    for (var source in texts) {
        expect_equal(document_of(source).to_string(), source);
    }
}

[Test]
keeps_comments_through_edits() {
    var document = document_of(
        "# Settings.\neditor:\n  tab_size: 4  # spaces\n  wrap: true\n  # more to come\nfiles:\n  - a.txt\n  - b.txt\n"
    );
    document.root["editor"]["wrap"] = yaml.YamlValue.Bool(false);
    document.root["editor"]["font"] = yaml.YamlValue.String("mono");
    document.root["files"].append(yaml.YamlValue.String("c.txt"));
    expect_equal(
        document.to_string(),
        "# Settings.\neditor:\n  tab_size: 4 # spaces\n  wrap: false\n  font: mono\n  # more to come\nfiles:\n  - a.txt\n  - b.txt\n  - c.txt\n"
    );
    expect_equal(document.comments("$")[0], "# Settings.");
    document.set_comments("$.files", ["", "# The files."]);
    document.root["editor"].remove("tab_size");
    expect_equal(
        document.to_string(),
        "# Settings.\neditor:\n  wrap: false\n  font: mono\n  # more to come\n\n# The files.\nfiles:\n  - a.txt\n  - b.txt\n  - c.txt\n"
    );
}

[Test]
writes_changed_values_in_the_default_way() {
    var document = document_of("port: 0x1f90\nname: 'web'\nscript: |\n  a\nlist: [1, 2]\n");
    document.root["port"] = yaml.YamlValue.Integer(80);
    document.root["name"] = yaml.YamlValue.String("it's");
    document.root["script"] = yaml.YamlValue.String("b\n");
    document.root["list"].append(yaml.YamlValue.Integer(3));
    expect_equal(document.to_string(), "port: 80\nname: 'it''s'\nscript: |\n  b\nlist: [1, 2, 3]\n");
}

[Test]
starts_empty() {
    var document = yaml.YamlDocument();
    expect_equal(document.to_string(), "null\n");
    document.root = yaml.YamlValue.mapping();
    document.root["a"] = yaml.YamlValue.Integer(1);
    document.set_comments("$.a", ["# one"]);
    expect_equal(document.to_string(), "# one\na: 1\n");
}

[Test]
[ShouldPanic("a YAML comment starts with '#'")]
rejects_a_comment_without_a_hash() {
    var document = yaml.YamlDocument();
    document.set_comments("$", ["no hash"]);
}
