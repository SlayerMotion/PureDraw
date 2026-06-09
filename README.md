# PureDraw

[![Style and namespacing](https://github.com/mihaelamj/PureDraw/actions/workflows/style.yml/badge.svg)](https://github.com/mihaelamj/PureDraw/actions/workflows/style.yml)
[![Swift macOS](https://github.com/mihaelamj/PureDraw/actions/workflows/swift-macos.yml/badge.svg)](https://github.com/mihaelamj/PureDraw/actions/workflows/swift-macos.yml)
[![Swift Linux](https://github.com/mihaelamj/PureDraw/actions/workflows/swift-linux.yml/badge.svg)](https://github.com/mihaelamj/PureDraw/actions/workflows/swift-linux.yml)
[![Swift Windows](https://github.com/mihaelamj/PureDraw/actions/workflows/swift-windows.yml/badge.svg)](https://github.com/mihaelamj/PureDraw/actions/workflows/swift-windows.yml)
[![Swift WASM](https://github.com/mihaelamj/PureDraw/actions/workflows/swift-wasm.yml/badge.svg)](https://github.com/mihaelamj/PureDraw/actions/workflows/swift-wasm.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)
![SwiftPM](https://img.shields.io/badge/SwiftPM-compatible-brightgreen.svg)

PureDraw is a dependency-free, Swift-native 2D graphics engine.

It provides a "Virtual PostScript Machine" API compatible with CoreGraphics (Quartz) and the HTML5 Canvas. The package is intentionally strict about portability:

- no external SwiftPM dependencies
- no bundled C sources
- no Foundation requirement in the library target
- macOS, Linux, Windows, and WASI build gates

It is a sibling project to [PureXML](https://github.com/mihaelamj/PureXML) and [PureYAML](https://github.com/mihaelamj/PureYAML).

## Roadmap

```mermaid
flowchart TB
classDef done fill:#34c759,stroke:#000,color:#fff
classDef active fill:#007aff,stroke:#000,color:#fff
classDef review fill:#ff9500,stroke:#000,color:#fff
classDef todo fill:#8e8e93,stroke:#000,color:#fff
classDef blocked fill:#ff3b30,stroke:#000,color:#fff

L1["Done"]:::done
L2["Active"]:::active
L3["Review"]:::review
L4["To Do"]:::todo
L5["Blocked"]:::blocked

L1 ~~~ L2
L2 ~~~ L3
L3 ~~~ L4
L4 ~~~ L5
```

```mermaid
flowchart TB
classDef done fill:#34c759,stroke:#000,color:#fff
classDef active fill:#007aff,stroke:#000,color:#fff
classDef review fill:#ff9500,stroke:#000,color:#fff
classDef todo fill:#8e8e93,stroke:#000,color:#fff
classDef blocked fill:#ff3b30,stroke:#000,color:#fff

E0["E0 (#1): Mathematical Primitives"]:::done
E1["E1 (#2): Path Construction"]:::done
E2["E2 (#3): Graphic State Management"]:::done
E3["E3 (#4): Rendering Bridge"]:::done

E0 --> E1
E1 --> E2
E2 --> E3
```

## Philosophy
PureDraw implements the mathematical foundation of 2D rendering:
1. **Affine Transforms:** Full 3x3 Matrix math for coordinate space mapping.
2. **Path Construction:** Resolution-independent Bézier curves and geometry.
3. **Painter's Algorithm:** A state-based command buffer that separates drawing intent from the final pixel rasterization.

## License
MIT.

## Community & Documentation

- [CONTRIBUTING.md](CONTRIBUTING.md): Guidelines for submitting PRs and feature requests.
- [SECURITY.md](SECURITY.md): Vulnerability reporting instructions.
- [SUPPORT.md](SUPPORT.md): How to get help.
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md): Community standards.
- [AGENTS.md](AGENTS.md): AI Agent instructions for working within this repository.
