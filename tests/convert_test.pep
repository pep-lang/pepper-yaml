# The yaml package's struct conversion: `encode` and `decode` through
# reflection, with the `serialize` attributes, and located errors.

import json;
import serialize;
import yaml;

struct Limits {
    var max_connections: int;
    [Name("time-out")]
    var timeout: double;
}

struct Server {
    [Required]
    var host: String;
    var port: int;
    var tags: Array<String>;
    var limits: Limits;
    var backup: String?;
    var weights: OrderedMap<String, int>;
    [Ignore]
    var started: long;
}

[Tag("kind")]
enum Shape {
    Circle(radius: int),
    Point,
}

struct Drawing {
    var shapes: Array<Shape>;
}

[Test]
encodes_a_struct() {
    var server = Server();
    server.host = "localhost";
    server.port = 8080;
    server.tags = ["web", "yes"];
    server.limits = Limits();
    server.limits.max_connections = 16;
    server.limits.timeout = 2.5;
    server.weights = OrderedMap<String, int>();
    server.weights["a"] = 1;
    server.started = 99;
    expect_equal(
        yaml.encode(server),
        "host: localhost\nport: 8080\ntags:\n  - web\n  - \"yes\"\nlimits:\n  max_connections: 16\n  time-out: 2.5\nbackup: null\nweights:\n  a: 1\n"
    );
}

[Test]
decodes_a_struct() {
    var text = "host: example.com\nport: 443\ntags: [a, b]\nlimits:\n  max_connections: 8\n  time-out: 1\nbackup: other\nweights: {x: 2}\nstarted: 5\nextra: ignored\n";
    var server = yaml.decode<Server>(text).value();
    expect_equal(server.host, "example.com");
    expect_equal(server.port, 443);
    expect_equal(server.tags[1], "b");
    expect_equal(server.limits.max_connections, 8);
    expect_equal(server.limits.timeout, 1.0);
    expect_equal(server.backup.value(), "other");
    expect_equal(server.weights["x"], 2);
    expect_equal(server.started, 0);
    var round = yaml.decode<Server>(yaml.encode(server)).value();
    expect_equal(round.limits.max_connections, 8);
    expect_true(yaml.decode<Server>("host: a\nbackup: null\n").value().backup.is_empty());
}

[Test]
decodes_tagged_enums() {
    var drawing = yaml.decode<Drawing>("shapes:\n  - kind: Circle\n    radius: 2\n  - kind: Point\n").value();
    expect_equal(drawing.shapes.count, 2);
    expect_true(drawing.shapes[0] is Circle);
    expect_equal(yaml.encode(drawing), "shapes:\n  - kind: Circle\n    radius: 2\n  - kind: Point\n");
}

[Test]
locates_conversion_errors() {
    var bad = yaml.decode<Server>("host: a\nlimits:\n  max_connections: lots\n", path = "server.yaml");
    expect_equal(
        bad.error().to_string(), "server.yaml:3:20: error: $.limits.max_connections: expected a number, found a string"
    );
    expect_equal(bad.error().value_path, "$.limits.max_connections");
    var missing = yaml.decode<Server>("port: 1\n", path = "server.yaml");
    expect_equal(missing.error().to_string(), "server.yaml:1:1: error: $: missing required key 'host'");
    var kind = yaml.decode<Server>("host: a\nlimits: [1]\n");
    expect_equal(kind.error().to_string(), "2:9: error: $.limits: expected a mapping, found a sequence");
    var unknown = yaml.decode<Server>("host: a\nextra: 1\n", unknown_keys = json.UnknownKeys.Reject);
    expect_equal(unknown.error().to_string(), "2:8: error: $.extra: unknown key 'extra'");
    var syntax = yaml.decode<Server>("host: [\n", path = "server.yaml");
    expect_equal(syntax.error().to_string(), "server.yaml:1:7: error: expected ']' to end this '['");
}

[Test]
converts_values() {
    var value = yaml.to_yaml(["a", "b"]);
    expect_equal(value.to_string(), "- a\n- b\n");
    var back = yaml.from_yaml<Array<String>>(value).value();
    expect_equal(back[1], "b");
    expect_equal(
        yaml.from_yaml<int>(yaml.YamlValue.String("x")).error().to_string(),
        "error: $: expected a number, found a string"
    );
}
