# PureDraw

Dependency-free, Swift-native 2D vector graphics engine. The agent entry point
is [AGENTS.md](AGENTS.md); the full rule set is indexed in
[docs/rules/README.md](docs/rules/README.md).

Non-negotiables for any change in this repo:

- No external SPM dependencies, no C/C++ sources, no Foundation in the core
  targets.
- Dependencies flow one direction: Validation -> Geometry -> Core -> Renderers
  -> PureDraw.
- Renderer backends must stay consistent with each other: a context rendered by
  `BitmapRenderer` and `CoreGraphicsRenderer` should produce the same picture.
- Format (`swiftformat . --config .swiftformat`), lint
  (`swiftlint --config .swiftlint.yml`), and run `swift test` before every
  commit; `scripts/check-all.sh` is the aggregate gate.
- Commits follow `<type>(<scope>): summary` per
  [docs/rules/commits.md](docs/rules/commits.md).
