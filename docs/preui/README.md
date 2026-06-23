# Core Graphics pre-UI

`cg-preUI.yaml` is the headless UI contract for the Core Graphics/PureDraw
inspector window. It is intentionally data-only so PureDraw keeps its zero
external dependency rule: no PureDraw package target imports PureReflection.

The document is consumed by the UI layer and validated by PureReflection's
`PreUIDocumentYAML` and `PreUIDocumentValidator`. It describes:

- a theorem-status `coverage_claims` block for the required Core Graphics schema/action/editor
  catalog in this document
- graphics-state fields and defaults
- explicit affine and projective transform matrices (`a/b/c/d/tx/ty` and `m11...m33`)
- validation rules for every editable numeric, integer, and numeric-list input
- line width, dash, cap, join, and miter stroke controls
- paint, path construction, clip, gradient, and draw actions
- presentation-neutral glyph/category/preview hints for later animated buttons
- the `transform-matrix` and `stroke-style` editor contracts the UI layer must implement separately
  in AppKit, UIKit, and SwiftUI

## Matrix editor contract

`transform-matrix` is one editor id with two Core Graphics forms:

- affine: stores `a/b/c/d/tx/ty`, displays a 3x3 grid, and locks the non-affine cells to `0, 0, 1`
- projective: stores a full `m11...m33` 3x3 grid

The editor must also expose calculator controls over the same data: translate, rotate, scale, skew,
flip, concatenate, invert, reset, decompose, preset application, live preview, and Swift code
projection in literal and recipe forms. This mirrors the local Transform Matrix Calculator research in
`../../../PureDrawResearch/TransformMatrix` and the more detailed calculator app in
`../../../PureDrawResearch/TransformCalc/Transform matrix calculator app-2`.

The detailed app fixes the affine decomposition contract to `tx`, `ty`, `rotation`, `sx`, `sy`, and
`skewX`, with presets for identity, rotate 30 degrees, scale 1.5, horizontal flip, shear, and card
tilt. The raw 2D matrix grid still stores only `a/b/c/d/tx/ty`; the locked display cells are derived.

The `surface.editor_contracts` block records these requirements as data: matrix dimension, field
order, locked cells, decomposition fields, operations, presets, code projections, preview, and exact
finite decimal input policy.

Validation is part of the contract, not a renderer preference. Each editable cell is an exact finite
decimal token: reject letters, partial numbers such as `12abc`, empty required cells, `NaN`,
infinities, and out-of-range fields before commit. The containing transform record then validates the
determinant and rejects singular matrices.

Each native renderer implements this separately:

- AppKit: formatter or control delegate validation plus pointer-dense grid editing
- UIKit: keypad input delegate validation plus touch-sized operation controls
- SwiftUI: binding-level filtering and validation state

The durable contract is this file. AppKit/UIKit/SwiftUI renderers are replaceable.

## Coverage gate

`surface.coverage_claims` lists every schema subject in this file, every schema subject that must be
directly grouped in the Core Graphics window, every action-palette slot, and every required editor id.
PureReflection validates those lists along with normal reference closure, so a future edit cannot
silently drop the transform editor, stroke editor, action palette, or a declared Core Graphics schema
while still reporting the YAML as conforming.
