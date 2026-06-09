#!/usr/bin/env bash
set -e

echo "Running style and structure checks..."
bash scripts/check-style.sh
bash scripts/check-namespacing.sh

if [ -f Package.swift ]; then
  echo "Running Swift format and lint checks..."
  if command -v swiftformat >/dev/null 2>&1; then
    swiftformat . --config .swiftformat --lint
  else
    echo "check-all: swiftformat not installed, skipping format check"
  fi
  if command -v swiftlint >/dev/null 2>&1; then
    swiftlint --config .swiftlint.yml --strict
  else
    echo "check-all: swiftlint not installed, skipping lint check"
  fi

  echo "Running Swift build and test..."
  swift build
  swift test
fi

echo "All checks passed."
