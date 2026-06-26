# CGS coverage

Status of the binding against the 19 CGSInternal headers. "Bound" means the
symbols were transcribed from the actual header and verified to compile and, where
side-effect-free, to resolve and run.

Symbols are only added after their signatures are read from the source header,
never reconstructed from memory.

## Bound (spine)

| Header | State | Notes |
|---|---|---|
| `CGSConnection.h` | Bound | Lifecycle, pid, menu-bar, update bracketing, properties, new/death notifications. PSN lookup (`CGSGetConnectionIDForPSN`) skipped: needs `ProcessSerialNumber`. |
| `CGSRegion.h` | Bound (full) | All create / op / query / enumerate functions. `CGSNewRegionWithQDRgn` skipped: needs `RgnHandle` (QuickDraw). |
| `CGSWindow.h` | Bound (core subset) | Create, release, order, move, screen rect, mouse loc, alpha, opacity, level, title, properties, sharing state, transform, basic shadow, window context + flush, window lists. |
| `CGSSpace.h` | Bound (full) | Create/destroy, name, type, active, copy spaces, spaces-for-windows, show/hide, add/remove windows, values, management mode. |

## Not yet bound

Catalogued, header not yet transcribed. Each is one more file following the same
raw-SPI + wrapper pattern.

| Header | What it covers |
|---|---|
| `CGSWindow.h` (remainder) | Warps, backdrops, genie/sheet animations, drag/activation regions, status-bar registration, tag bitfields, color space, autofill, acceleration. |
| `CGSEvent.h` | Synthetic events, event taps, event masks. |
| `CGSHotKeys.h` | Global hot-key registration. |
| `CGSDisplays.h` | Display configuration and enumeration. |
| `CGSDevice.h` | Input/display device handling. |
| `CGSCursor.h` | Cursor image, position, visibility. |
| `CGSSession.h` | Login / fast-user-switching sessions. |
| `CGSWorkspace.h` | Workspace state. |
| `CGSSurface.h` | Window surfaces / IOSurface attachment. |
| `CGSTile.h` | Tiling. |
| `CGSTransitions.h` | Window transition effects. |
| `CGSCIFilter.h` | Core Image filters attached to windows. |
| `CGSAccessibility.h` | Accessibility display settings (invert, reduce transparency). |
| `CGSDebug.h` | Debug options (e.g. coloured window flashing). |
| `CGSMisc.h` | Assorted helpers. |

## Constraints carried by every binding here

- Pure Swift only (`@_silgen_name`), no C/C++ sources.
- Faithful signatures transcribed from the source header.
- Wrappers stay thin: they add memory safety (RAII), Swift types, and defaults,
  never new behavior the SPI does not provide.
