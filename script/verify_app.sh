#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"

echo "== Swift build =="
swift build

echo ""
echo "== Swift tests =="
swift test

echo ""
echo "== App launch check =="
"$ROOT_DIR/script/build_and_run.sh" --verify

echo ""
echo "Verification complete."
