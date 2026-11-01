#!/usr/bin/env bash
# Runs the package's tests: the [Test] functions in tests/, with pepper test.
#
# Usage: tests/run.sh [path/to/pepper]   (default: pepper on PATH)
set -euxo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
pepper="${1:-pepper}"
build="$(mktemp -d)"
trap 'rm -rf "$build"' EXIT

# The package is the module `yaml`: a folder of that name on the import path.
mkdir "$build/packages"
ln -s "$root" "$build/packages/yaml"
"$pepper" test -I "$build/packages" "$root/tests"

# The Pepper book's example.
"$pepper" build -I "$build/packages" "$root/examples/book/main.pep" -o "$build/book_example"
"$build/book_example" | grep -qx "8080"
