#!/bin/bash
# Self-check for the reorder logic. No test framework — compile and run.
set -euo pipefail
cd "$(dirname "$0")"
OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT
swiftc Reorder.swift ReorderTests.swift -o "$OUT/tests"
"$OUT/tests"
