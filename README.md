# PureDraw

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)

PureDraw is a dependency-free, Swift-native 2D graphics engine.

It provides a "Virtual PostScript Machine" API compatible with CoreGraphics (Quartz) and the HTML5 Canvas. The package is intentionally strict about portability:

- no external SwiftPM dependencies
- no bundled C sources
- no Foundation requirement in the library target
- macOS, Linux, Windows, and WASI build gates

It is a sibling project to [PureXML](https://github.com/mihaelamj/PureXML) and [PureYAML](https://github.com/mihaelamj/PureYAML).

## Philosophy
PureDraw implements the mathematical foundation of 2D rendering:
1. **Affine Transforms:** Full 3x3 Matrix math for coordinate space mapping.
2. **Path Construction:** Resolution-independent Bézier curves and geometry.
3. **Painter's Algorithm:** A state-based command buffer that separates drawing intent from the final pixel rasterization.

## License
MIT.
