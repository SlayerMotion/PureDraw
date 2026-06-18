# PureDraw: audit findings

Repo: https://github.com/SlayerMotion/PureDraw · open issues at audit start: 14
Status: looping (round 2 found 1 new; need a clean round to confirm dry)

These are NEW isolated findings, deduped against existing open GitHub issues. Not yet filed.

## Round 1 (6 new)

1. **Missing blend modes in BitmapRenderer**: hue, saturation, color, luminosity, and all
   Porter-Duff operators fall back to source-over, diverging from CoreGraphicsRenderer.
   `Sources/Renderers/BitmapRenderer.swift:632-638`. Severity: bug/gap.
2. **No dimension validation in vector renderers**: SVG/Canvas/PostScript accept zero,
   negative, NaN dimensions silently; BitmapRenderer guards (`:37-42`).
   `SVGRenderer.swift:20`, `PostScriptRenderer.swift:20`, `CanvasRenderer.swift:166`. Severity: gap.
3. **No cross-renderer consistency tests**: repo rule requires Bitmap == CoreGraphics output;
   no pairwise pixel test exists. `Tests/RenderersTests/`. Severity: gap/test.
4. **No output-correctness tests for Canvas / PostScript renderers**: only smoke tests.
   `Tests/RenderersTests/RendererTests.swift:225,262`. Severity: test.
5. **Silent op-skips in vector renderers**: `drawImageProjective`, `dropShadow`, `showText`
   are `continue`/`break`-ed with no throw/log → silent data loss.
   `SVGRenderer.swift:86,208`, `PostScriptRenderer.swift:260`. Severity: gap.
6. **No infinite/NaN geometry validation in SVG/Canvas serialization**: Core/Bitmap validate;
   vector paths serialized unchecked. Severity: gap.

## Round 2 (1 new)

7. **CanvasRenderer `contextName` is not validated**: accepts empty string or a string that is
   not a valid JavaScript identifier, so it can emit invalid/broken JS silently.
   `Sources/Renderers/CanvasRenderer.swift:17-19`. Severity: bug.

## Round 3 (6 new)

8. **PNGEncoder.encodeAnimated traps on NaN/Inf frameDelay**: also allows negative delays.
   `Sources/Renderers/PNGEncoder.swift:42`. Severity: bug (crash).
9. **PDFRenderer dimensions unvalidated**: width/height used directly in draw(), no >0/finite guard
   (BitmapRenderer guards; PDFRenderer was outside round-1 scope).
   `Sources/Renderers/PDFRenderer.swift:34-54`. Severity: bug.
10. **Pattern init accepts invalid params**: bounds can be invalid; xStep/yStep default to invalid.
    `Sources/Core/Pattern.swift:32-38`. Severity: bug.
11. **ImageMetadata GPS coords lack range validation**: lat/long parsed, never range-checked.
    `Sources/Core/ImageMetadata.swift:230-234`. Severity: gap.
12. **Color component NaN validation is implicit**: `contains()` returns false for NaN but the
    error message is misleading. `Sources/Core/Validations+Graphics.swift:5-18`. Severity: gap.
13. **GradientStop location NaN validation is implicit**: same pattern.
    `Sources/Core/Validations+Graphics.swift:142-149`. Severity: gap.

## Round 4 (2 new)

14. **Rect finitude check ignores origin**: `rectIsFinite` validates width/height but not
    origin.x/origin.y, so NaN/Inf origins pass. `Sources/Geometry/Validations+Geometry.swift:66-72`.
    Severity: bug.
15. **Orphaned doc comment for clip(to:mask:)**: doc block at `:423-424` is stranded ~100 lines
    from its method (`:525`). `Sources/Core/GraphicsContext.swift:423`. Severity: refactor (minor).

## Round 5 (2 new: same class)

16. **CoverageRasterizer maxX/Y finiteness gap**: bounds calc lacks finite guard.
    `Sources/Renderers/CoverageRasterizer.swift:66`. Severity: bug.
17. **PostScriptRenderer maxX/Y Int conversion without finiteness check**: can trap on Inf/NaN.
    `Sources/Renderers/PostScriptRenderer.swift:91-92`. Severity: bug.

> CONVERGENCE NOTE: rounds 3-5 keep surfacing instances of ONE systemic gap:
> **pervasive missing NaN/finiteness validation** across renderers + geometry (#8,9,10,11,
> 12,13,14,16,17). These should be filed as **one umbrella issue** ("uniform finite/NaN
> validation pass across PureDraw inputs") with the call-site list, not N separate issues.
> The loop will keep finding more call sites; that is instance enumeration, not new classes.

## Round 6 (theme-excluded convergence check): DRY

No new defect of a different class. (Noted but rejected: one truly-unreachable dead branch at
`CoreGraphicsRenderer.swift:208`: no functional impact, not worth filing.)

## CONVERGED ✓
17 raw findings → ~8 distinct filable issues:
- 6 standalone: blend modes (#1), cross-renderer consistency tests (#3), Canvas/PostScript
  output tests (#4), silent vector op-skips (#5), CanvasRenderer contextName (#7), orphaned
  doc comment (#15, minor).
- 1 umbrella: **uniform finite/NaN/range validation pass** covering call sites #2, #6, #8, #9,
  #10, #11, #12, #13, #14, #16, #17.
Decision pending from user: file these vs fix in code.

---
Filed as GitHub issues #111-#117 on 2026-06-16.
