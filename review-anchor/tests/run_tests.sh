#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$ROOT_DIR"

echo "=== Running Review Anchor Lua Test Suite ==="

echo "-> Running test_diff_p.lua..."
nvim --headless -l review-anchor/tests/test_diff_p.lua

echo "-> Running test_git_notes.lua..."
nvim --headless -l review-anchor/tests/test_git_notes.lua

echo "-> Running test_anchors.lua..."
nvim --headless -l review-anchor/tests/test_anchors.lua

echo "-> Running test_startup.lua..."
nvim --headless -l review-anchor/tests/test_startup.lua

echo "-> Running test_inline.lua..."
nvim --headless -l review-anchor/tests/test_inline.lua

echo "-> Running test_repo_init.lua..."
nvim --headless -l review-anchor/tests/test_repo_init.lua

echo "=== All Tests Passed Successfully! ==="
