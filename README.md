# pepper-yaml

YAML 1.2 for [Pepper](https://github.com/pep-lang/pepper): read YAML into
a value, change it and write it back, edit a file without losing its
comments, and convert structs to YAML and back. It has the same shape as
the runtime's `json` and `toml` modules.

One module, **`yaml`**:

- **`yaml.parse(text)`** reads one document into a `YamlValue`: `Null`,
  `Bool`, `Integer`, `Float`, `String`, `Sequence` or `Mapping` (which
  keeps its keys in the order they were written). Look values up with
  `value["key"]` and `value[index]`, which give `Null` when there is
  nothing there, so lookups chain; read them with `as_string()`,
  `as_int()`, `as_float()`, `as_bool()`, `as_sequence()` and
  `as_mapping()`. **`yaml.parse_all(text)`** reads every document of a
  stream (`---`).
- **`value.to_string()`** writes YAML in block style, quoting only what
  would read back as something else; **`yaml.write_all(documents)`**
  writes a stream.
- **`yaml.parse_document(text)`** gives a `YamlDocument`: change its
  `root` and `to_string()` writes it back with its comments, blank lines,
  key order, flow or block collections, scalar styles and indentation.
  `comments(path)` and `set_comments(path, lines)` read and change the
  comments before a value (`$.server.port`).
- **`yaml.encode(value)`** and **`yaml.decode<T>(text)`** convert structs,
  enums, arrays, maps and `Optional`s through reflection, with the
  `serialize` attributes (`[Name("x")]`, `[Ignore]`, `[Required]`,
  `[Tag("kind")]`, `[Untagged]`), exactly as `json.encode` and
  `json.decode` do. `to_yaml` and `from_yaml` convert to and from a
  `YamlValue`.
- **`merge_keys = true`**, given to `parse`, `parse_all` or `decode`,
  applies YAML 1.1 merge keys (`<<: *base`, `<<: [*a, *b]`): the
  mapping's own keys win, an earlier mapping of a list wins over a later
  one, and merged nodes count toward `max_alias_nodes`. Without it, `<<`
  is an ordinary key, as YAML 1.2 says. `parse_document` never merges,
  so it writes a `<<` line back as it was.
- **`yaml.decode_text(bytes)`** decodes a file's bytes, UTF-8 or UTF-16,
  for `parse`.

```pepper
import serialize;
import yaml;

struct Server {
    [Required]
    var host: String;
    var port: int;
    var tags: Array<String>;
}

main(): int {
    var parsed = yaml.parse("host: localhost\nport: 8080\ndebug: no\n", path = "server.yaml");
    if (parsed.is_err()) {
        print(parsed.error().to_string());   # server.yaml:LINE:COLUMN: error: ...
        return 1;
    }
    var root = parsed.value();
    print(root["port"].as_int().value());       # 8080
    print(root["debug"].as_string().value());   # no: a string, as YAML 1.2 says

    var server = yaml.decode<Server>("host: a\nport: 80\ntags: [web]\n").value();
    print(yaml.encode(server));                 # host: a\nport: 80\ntags:\n  - web\n

    var document = yaml.parse_document("# The port.\nport: 80  # default\n").value();
    document.root["port"] = yaml.YamlValue.Integer(81);
    print(document.to_string());                # # The port.\nport: 81 # default\n
    return 0;
}
```

## What it reads

- **YAML 1.2** block and flow collections, plain, quoted and block (`|`,
  `>`, with chomping and indentation indicators) scalars, anchors and
  aliases, explicit keys (`? `), multiple documents, `%YAML` and `%TAG`
  directives. It passes every case of the
  [YAML test suite](https://github.com/yaml/yaml-test-suite) that its
  limits below allow: all 95 invalid inputs are rejected, and 275 of the
  307 valid ones read as the suite says; the other 32 use tags outside
  the core schema or collections as keys.
- **The core schema** only: `null`, `~` and an empty value are `Null`;
  `true` and `false` (in three spellings) are booleans; `42`, `0x2a` and
  `0o52` are integers; `1.5`, `1e3`, `.inf` and `.nan` are floats. `yes`,
  `no`, `on` and `off` are strings, so YAML 1.1's "Norway problem" (`NO`
  read as `false`) cannot happen. The writer quotes them, so older readers
  see strings too.
- **Safe for untrusted text**: only the core schema's tags (`!!str`,
  `!!int`, `!!float`, `!!bool`, `!!null`, `!!seq`, `!!map`, and `!`) are
  read; any other tag is an error, so no text can ask for a type to be
  made. An alias is the very value its anchor names, not a copy, and the
  nodes all aliases stand for may not pass `max_alias_nodes` (a million by
  default), which stops the "billion laughs" attack. Collections nest at
  most `max_depth` (256) deep.
- **Errors** are clang-style, at the line and column of the problem:
  `config.yaml:4:3: error: undefined alias 'base'`. `decode`'s conversion
  errors also name the value's path: `server.yaml:1:7: error: $.port:
  expected a number, found a string`.

## Limits

- A mapping's keys are strings. A scalar key written as another kind
  (`1:`, `true:`) is the text it was written as, and a collection used as
  a key (`[a, b]: 1`, or `? - a`) is an error. Duplicate keys are an error.
- Tags outside the core schema, such as `!!set`, `!!omap`, `!!binary` or
  application tags (`!point`), are errors.
- YAML 1.1's merge key (`<<: *base`) is an ordinary key, as YAML 1.2
  says, unless `merge_keys` is given. A `<<` inside a flow sequence's
  single pair (`[<<: *a]`) never merges.
- `YamlDocument` does not keep the spacing inside a line, comments inside
  a flow collection, anchors and aliases (each alias is written out in
  full), or directives; a value that changed is written in the default
  way. It holds one document.
- There is no streaming (event) reader yet; the whole text is read into a
  tree. One can come later, if a large-file use case shows up.
- Struct conversion goes through `json.JsonValue`, so it shares `json`'s
  rules and messages; a compile error for a type it cannot convert says
  "to JSON".

## Using it

This repository is a package: `pep.toml` marks its root, and its root
`module.pep` is the `yaml` module. Add it to a project under the name
`yaml`:

```sh
pepper package add pep-lang/pepper-yaml --name yaml
```

which writes

```toml
[dependencies]
yaml = { github = "pep-lang/pepper-yaml" }
```

Without a project, put a folder named `yaml` that holds (or links to) this
repository on the import path: `pepper build -I packages main.pep`.

## Tests

```sh
tests/run.sh path/to/pepper
```

runs the `[Test]` functions in `tests/` with `pepper test`: the parser
(`parse_test.pep`), the writer (`write_test.pep`), documents
(`document_test.pep`), merge keys (`merge_test.pep`) and struct
conversion (`convert_test.pep`).

## Design

- **A package**, fetched with `pepper package add`, rather than a runtime
  module, since few programs need YAML.
- **Key names keep their case**, and the attributes are the ones `json`
  and `toml` share.

## Releasing

CI (`.github/workflows/ci.yml`) runs the tests on Linux, macOS and
Windows for every push to `main` and every pull request. To release, set
`version` in `pep.toml`, merge, then push the matching tag
(`git tag v1.0.0 && git push origin v1.0.0`): CI tests the tag and
publishes a GitHub release for it. `pepper package add` and `pepper
package update` find versions by their tags.

## License

Apache-2.0; see [LICENSE](LICENSE).
