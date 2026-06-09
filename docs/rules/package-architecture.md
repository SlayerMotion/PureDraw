# Package Architecture

How to decompose the repository into focused SPM targets within its single package.

## Extreme Packaging

Follow the "Extreme Packaging" pattern. Rather than building one large monolith target (e.g. `PureDrawCore`), separate concerns into focused, single-responsibility targets.

```text
Sources/
├── PureDrawMath/         # Core matrix and point primitives
├── PureDrawGeometry/     # Path and shape construction
├── PureDrawRender/       # GState and command buffers
└── PureDraw/             # The public facade (exports the underlying targets)
```

## Dependency Rules

1. **Unidirectional flow:** Higher-level targets (Render) depend on lower-level targets (Math).
2. **No cycles:** Circular dependencies are hard failures in SPM.
3. **No external dependencies:** PureDraw is a root-level standalone library. The `dependencies` array in `Package.swift` MUST remain empty.

## Target Facades

To avoid burdening the user with `import PureDrawMath`, `import PureDrawGeometry`, use a facade target (`PureDraw`) that uses `@_exported import` to expose the underlying public API.
