#!/usr/bin/env bash
set -e

echo "Running style and structure checks..."
bash scripts/check-style.sh
bash scripts/check-namespacing.sh

echo "Running Swift build and test..."
swift build
swift test

echo "All checks passed."
