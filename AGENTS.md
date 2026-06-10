# Agent guide for PureDraw

PureDraw is a dependency-free, Swift-native 2D vector graphics engine: a
"Virtual PostScript Machine" API compatible with CoreGraphics (Quartz) and the
HTML5 Canvas. Read this file first, then load rules from `docs/rules/` as the
task requires.

## Hard constraints

- **Zero external dependencies.** `Package.swift` must keep an empty
  dependency list. Do not add SPM packages.
- **Pure Swift.** No bundled C/C++ sources.
- **No Foundation in the core targets.** Foundation is allowed only where the
  target already imports it (renderer outputs, tests).
- **Cross-platform.** The library builds on macOS, Linux, Windows, and WASM;
  platform-specific code (CoreGraphics) stays behind `#if canImport` gates.

## Layout

- `Sources/Validation` -> `Sources/Geometry` -> `Sources/Core` ->
  `Sources/Renderers` -> `Sources/PureDraw` (umbrella). Dependencies point one
  direction only.
- Tests live in `Tests/<Target>Tests` and use Swift Testing
  (`@Test`, `#expect`).
- `docs/DESIGN.md` explains the architecture; the Quartz feature roadmap is in
  `docs/prioritized_roadmap.md`.

## Commands

- `swift build` - build all targets
- `swift test` - run the full suite
- `swiftformat . --config .swiftformat` - format before committing
- `swiftlint --config .swiftlint.yml` - lint
- `scripts/check-all.sh` - the aggregate gate CI runs; keep it green
- Git hooks: `git config core.hooksPath .githooks` (run once per clone)

## Rules

The full rule set lives in [docs/rules/](docs/rules/); the index is
[docs/rules/README.md](docs/rules/README.md) and the short overview is
[docs/rules/CONVENTIONS.md](docs/rules/CONVENTIONS.md). Always relevant here:

- [docs/rules/engineering.md](docs/rules/engineering.md)
- [docs/rules/code-style.md](docs/rules/code-style.md)
- [docs/rules/namespacing.md](docs/rules/namespacing.md)
- [docs/rules/concurrency.md](docs/rules/concurrency.md)
- [docs/rules/cross-platform.md](docs/rules/cross-platform.md)
- [docs/rules/testing.md](docs/rules/testing.md)
- [docs/rules/testing-discipline.md](docs/rules/testing-discipline.md)
- [docs/rules/verification.md](docs/rules/verification.md)
- [docs/rules/commits.md](docs/rules/commits.md)
- [docs/rules/git-discipline.md](docs/rules/git-discipline.md)
