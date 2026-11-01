# The example in the Pepper book's chapter (pep-lang/pepper,
# docs/src/language/yaml.md): keep the two the same.

import yaml;

main(): int {
    var parsed = yaml.parse("server:\n  port: 8080\n  debug: no\n", path = "config.yaml");
    if (parsed.is_err()) {
        print(parsed.error().to_string());
        return 1;
    }
    var root = parsed.value();
    print(root["server"]["port"].as_int().value());      # 8080
    print(root["server"]["debug"].as_string().value());  # no
    root["server"]["port"] = yaml.YamlValue.Integer(9090);
    print(root.to_string());
    return 0;
}
