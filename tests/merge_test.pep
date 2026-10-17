# The yaml package's YAML 1.1 merge keys (`<<`), read with `merge_keys`.

import yaml;

merged(source: String): yaml.YamlValue {
    var result = yaml.parse(source, merge_keys = true);
    if (result.is_err()) {
        print(result.error().to_string());
        panic("parse failed");
    }
    return result.value();
}

merge_error_of(source: String): String {
    var result = yaml.parse(source, path = "test.yaml", merge_keys = true);
    expect_true(result.is_err());
    return result.error().to_string();
}

struct Job {
    var retries: int;
    var timeout: int;
}

keys_of(value: yaml.YamlValue): String {
    var out = "";
    for (var (key, member) in value.as_mapping().value()) {
        out = out + key + " ";
    }
    return out;
}

[Test]
keeps_merge_keys_ordinary_by_default() {
    var root = yaml.parse("base: &b {x: 1}\njob:\n  <<: *b\n").value();
    expect_equal(root["job"]["<<"]["x"].as_int().value(), 1);
    expect_true(root["job"]["x"].is_null());
}

[Test]
merges_a_mapping() {
    var root = merged("defaults: &defaults\n  retries: 3\n  timeout: 30\njob:\n  <<: *defaults\n  timeout: 60\n");
    expect_equal(root["job"]["retries"].as_int().value(), 3);
    expect_equal(root["job"]["timeout"].as_int().value(), 60);
    expect_true(root["job"]["<<"].is_null());
    expect_equal(keys_of(root["job"]), "retries timeout ");
}

[Test]
lets_the_mapping_win_wherever_its_key_is() {
    var root = merged("b: &b {x: 1, y: 2}\nj:\n  x: 0\n  <<: *b\n  z: 3\n");
    expect_equal(root["j"]["x"].as_int().value(), 0);
    expect_equal(root["j"]["y"].as_int().value(), 2);
    expect_equal(keys_of(root["j"]), "x y z ");
}

[Test]
lets_an_earlier_list_entry_win() {
    var root = merged("a: &a {x: 1}\nb: &b {x: 2, y: 2}\nj:\n  <<: [*a, *b]\n");
    expect_equal(root["j"]["x"].as_int().value(), 1);
    expect_equal(root["j"]["y"].as_int().value(), 2);
}

[Test]
merges_in_flow_and_inline_mappings() {
    var root = merged("a: &a {x: 1}\nj: {<<: *a, y: 2}\nk:\n  <<: {z: 3}\n");
    expect_equal(root["j"]["x"].as_int().value(), 1);
    expect_equal(root["j"]["y"].as_int().value(), 2);
    expect_equal(root["k"]["z"].as_int().value(), 3);
}

[Test]
keeps_a_quoted_merge_key() {
    var root = merged("a: &a {x: 1}\nj:\n  \"<<\": *a\n");
    expect_equal(root["j"]["<<"]["x"].as_int().value(), 1);
}

[Test]
merges_in_decode() {
    var source = "base: &b {retries: 3, timeout: 30}\n<<: *b\ntimeout: 60\n";
    var job = yaml.decode<Job>(source, merge_keys = true).value();
    expect_equal(job.retries, 3);
    expect_equal(job.timeout, 60);
}

[Test]
reports_a_merge_of_something_else() {
    expect_equal(
        merge_error_of("a: 1\nj:\n  <<: 5\n"),
        "test.yaml:3:7: error: a merge key ('<<') must name a mapping or a list of mappings"
    );
    expect_equal(
        merge_error_of("a: &a {x: 1}\nj:\n  <<: [*a, 2]\n"),
        "test.yaml:3:12: error: a merge key's list ('<<') must hold only mappings"
    );
}

[Test]
counts_merged_nodes_toward_max_alias_nodes() {
    var bomb = "a: &a {x: 1, y: 2}\nb: &b {<<: [*a, *a]}\nc: &c {<<: [*b, *b]}\nd: {<<: [*c, *c]}\n";
    var bounded = yaml.parse(bomb, path = "test.yaml", max_alias_nodes = 10, merge_keys = true);
    expect_true(bounded.is_err());
    expect_true(bounded.error().message.contains("max_alias_nodes"));
    expect_true(yaml.parse(bomb, merge_keys = true).is_ok());
}

[Test]
writes_a_merge_key_back_as_it_was() {
    var source = "base: &b\n  x: 1\njob:\n  <<: *b\n  y: 2\n";
    var document = yaml.parse_document(source).value();
    expect_true(document.to_string().contains("<<"));
}
