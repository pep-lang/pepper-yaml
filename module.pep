## YAML 1.2: parse text into a `YamlValue`, look values up and change
## them, write values back as YAML, edit a document keeping its comments
## and layout, and convert structs to YAML and back.
##
## Bring it in with `import yaml`. Parsing follows YAML 1.2 with its core
## schema, so `yes`, `no`, `on` and `off` are strings, not booleans. It is
## safe for untrusted text: only the core schema's tags are read, aliases
## may not stand for more than a set number of nodes, and nesting is
## bounded. Errors carry a line and column, like a compiler's. Mappings
## keep their keys in the order they were written.
##
## - `YamlValue`: a value of any kind
## - `parse`, `parse_all`, `YamlError`, `decode_text`: reading
## - `YamlValue.to_string`, `write_all`: writing
## - `parse_document`, `YamlDocument`: changing a file people edit without
##   losing its comments
## - `encode`, `decode`, `to_yaml`, `from_yaml`: struct conversion, with the
##   attributes of the `serialize` module, as `json` converts structs
##
## @example
##     import yaml;
##
##     main(): int {
##         var parsed = yaml.parse("name: demo\nversion: 0.1.0\ntags: [cli, yaml]\n");
##         if (parsed.is_err()) {
##             print(parsed.error().to_string());
##             return 1;
##         }
##         var root = parsed.value();
##         assert(root["name"].as_string().value() == "demo", "a string");
##         root["tags"].append(yaml.YamlValue.String("new"));
##         print(root.to_string());
##         return 0;
##     }

# This file only gathers the module's public API from its other files.

import "convert";
import "document";
import "parse";
import "value";
import "write";

export YamlValue;
export YamlError;
export parse;
export parse_all;
export decode_text;
export write_all;
export YamlDocument;
export parse_document;
export to_yaml;
export from_yaml;
export encode;
export decode;
