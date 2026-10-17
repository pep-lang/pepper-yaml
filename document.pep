## `YamlDocument`: a YAML document that keeps its comments and layout, so
## a file people edit can be read, changed and written back with them.

import "parse";
import "schema";
import "value";
import "write";

## A YAML value with the comments and layout of the text it was read from,
## as `parse_document` makes it.
##
## Each comment belongs to a value, by the value's path from the root `$`
## (`$.server.port`, `$.hosts[0]`): the comment and blank lines before a
## key or `-` stay with its value, a comment at the end of a value's line
## stays on that line, and those after a collection's last entry, indented
## at least as far as its entries, stay at its end. `to_string()` writes
## them back in those places, along with how each value was written: key
## order, flow collections (`[a, b]`) or block ones, quoted, block (`|`,
## `>`) or plain scalars (`0x1f` stays `0x1f`), and the indentation of
## nested mappings and of sequences under a key. So text read and written
## unchanged comes back as it was, or close to it: what is not kept is the
## spacing inside a line, comments inside a flow collection, anchors and
## aliases (each alias is written out in full), and `%` directives.
##
## Change `root` freely. A comment or style whose value is gone (a removed
## key, a sequence shortened past it) is not written; one whose path names
## another value afterwards (an element shifted into its index) goes with
## that value. A value that changed is written in the default way for it.
##
## To save the cost of keeping all this when only the values matter, use
## `parse`.
##
## @example
##     import yaml;
##
##     var text = "# The server.\nserver:\n  port: 8080  # the default\n  hosts: [a, b]\n";
##     var document = yaml.parse_document(text).value();
##     document.root["server"]["port"] = yaml.YamlValue.Integer(9090);
##     assert(
##         document.to_string() == "# The server.\nserver:\n  port: 9090 # the default\n  hosts: [a, b]\n",
##         "the comments and the flow sequence stay"
##     );
##     assert(document.comments("$")[0] == "# The server.", "by path");
export struct YamlDocument {
    ## The document's value.
    var root: YamlValue;
    _YamlNotes _notes;

    ## Creates a document holding `root`, with no comments.
    ##
    ## @param root the document's value
    construct(root: YamlValue = YamlValue.Null) {
        this.root = root;
        _notes = _YamlNotes();
    }

    ## Returns the comment lines before the value at `path`, each with its
    ## `#`, and an empty string for each blank line among them.
    ##
    ## @param path the value's path from the root: `$`, `$.key`, `$[0]`, or
    ##   `$["a key"]` for a key that is not an identifier
    ## @returns the lines, first first; empty when there are none
    comments(path: String): Array<String> {
        var filed = _notes.before.try_get(path);
        var copy = Array<String>();
        if (filed.is_value()) {
            for (var line in filed.value()) {
                copy.append(line);
            }
        }
        return copy;
    }

    ## Replaces the comment lines before the value at `path`. Each must be
    ## a comment, starting with `#`, or empty for a blank line.
    ##
    ## @param path the value's path from the root, as for `comments`
    ## @param comments the lines to write before the value; empty removes
    ##   them
    ## @panics if a line is neither empty nor a one-line comment starting
    ##   with `#` ("a YAML comment starts with '#' and has no line break")
    set_comments(path: String, comments: Array<String>) {
        var copy = Array<String>();
        for (var comment in comments) {
            assert(
                (comment.is_empty || comment.starts_with("#")) && !comment.contains("\n"),
                "a YAML comment starts with '#' and has no line break"
            );
            copy.append(comment);
        }
        _notes.before.remove(path);
        _notes.add(_notes.before, path, copy);
    }

    ## Returns the document as YAML text with its comments and layout.
    ##
    ## @returns the text, ending with a line break
    to_string(): String {
        return _yaml_write(root, _notes);
    }
}

## Parses YAML text holding one document into a `YamlDocument`, keeping
## its comments and layout.
##
## The text is read as `parse` reads it. Use it to change a file people
## edit, such as a configuration file, and write it back with its
## comments; use `parse` when the comments do not matter.
##
## @param text the YAML text
## @param path the name of the text (a file name, say), which the error's
##   `to_string()` puts first
## @param max_depth how deeply collections may nest
## @param max_alias_nodes how many nodes the aliases may stand for in all
## @returns the document, or an error naming the first problem and its
##   line and column
export parse_document(
    text: String, path: String = "", max_depth: ulong = 256, max_alias_nodes: ulong = 1000000
): Result<YamlDocument, YamlError> {
    var document = YamlDocument();
    var parsed = _yaml_parse_noted(
        text,
        path,
        max_depth,
        max_alias_nodes,
        Optional<_YamlNotes>.Value(document._notes),
        Optional<HashMap<String, ulong>>.Empty
    );
    if (parsed.is_err()) {
        return Result<YamlDocument, YamlError>.err(parsed.error());
    }
    document.root = parsed.value();
    return Result<YamlDocument, YamlError>.ok(document);
}
