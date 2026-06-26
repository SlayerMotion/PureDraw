# CGS

A Swift binding to the private **CoreGraphics Services / SkyLight** window-server
SPI, the layer the community header collection
[CGSInternal](https://github.com/NUIKit/CGSInternal) documents.

## Why this is a separate package

PureDraw is a portable, dependency-free **Quartz 2D** engine: pure math and
pixels, no Foundation in its core, one-directional dependencies
(`Validation -> Geometry -> Core -> Renderers -> PureDraw`).

This package is the deliberate opposite and therefore lives entirely outside that
hierarchy, in its own SwiftPM package:

- **macOS only.** It talks to `WindowServer`; there is no portable version.
- **Private SPI.** Undocumented, App-Store-rejectable, and liable to change
  between macOS releases. Use it for tooling, research, and development harnesses,
  not shipping App Store software.
- **Uses Foundation / CoreFoundation / CoreGraphics.** Allowed here because this
  is not a core target; nothing in PureDraw's core may depend on it.

It is **not** a drawing API and not a replacement for the WindowServer. It is a
typed client for the existing one: you still need a live GUI session, and most
calls require the appropriate permissions.

## How the binding works

No C or C++ sources (the repo forbids them). Every entry point is declared in pure
Swift with `@_silgen_name`, and symbols are resolved at runtime through dyld via
`-undefined dynamic_lookup` (set in `Package.swift`). CoreGraphics and SkyLight
are already loaded in any GUI process, so the symbols are present at run time
without linking a private framework stub at build time.

Because of the `unsafeFlags` linker setting, this package cannot be consumed as a
remote SwiftPM dependency by URL; depend on it by local path.

## Layout

Each source file mirrors one CGSInternal header and is split into a faithful
"Raw SPI" section (the exact `@_silgen_name` declarations) and a small Swift
wrapper that makes the common path safe and ergonomic:

| File | Header | Wrapper |
|---|---|---|
| `CGSTypes.swift` | shared typedefs | type aliases, `CGError.isSuccess` |
| `CGSConnection.swift` | `CGSConnection.h` | `CGSConnection` |
| `CGSRegion.swift` | `CGSRegion.h` | `CGSRegion` (RAII) |
| `CGSWindow.swift` | `CGSWindow.h` (core subset) | `CGSWindow` (RAII) |
| `CGSSpace.swift` | `CGSSpace.h` | `CGSSpaces` |

See [COVERAGE.md](COVERAGE.md) for exactly which symbols are bound today and what
remains.

## Example

```swift
import CGS
import CoreGraphics

// Region math works without a WindowServer session.
let region = CGSRegion(CGRect(x: 0, y: 0, width: 320, height: 200))!
print(region.bounds, region.isRectangular)

// Windows require a live GUI session and permissions.
let connection = CGSConnection.main
if let window = CGSWindow(connection: connection, frame: CGRect(x: 100, y: 100, width: 320, height: 200)) {
    window.setTitle("Hello from CGS")
    window.alpha = 0.9
    window.orderFront()
    if let ctx = window.makeContext() {
        ctx.setFillColor(CGColor(red: 0.1, green: 0.2, blue: 0.9, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 320, height: 200))
        window.flush()
    }
}
```
