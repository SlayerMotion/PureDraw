# Changelog

All notable changes to PureDraw are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Image-based clipping masks: `GraphicsContext.clip(to:mask:)`, honored by
  `BitmapRenderer` and `CoreGraphicsRenderer`.
- Color masking on `Image` via `maskingColors`, applied consistently by both
  pixel renderers (no-alpha layouts only, matching CoreGraphics semantics).
- `Image.pixelColor(x:y:)` and `Image.maskCoverage(x:y:)` for per-pixel
  sampling across gray, RGB, and CMYK layouts.
- `AlphaInfo.hasAlpha`, `AlphaInfo.isAlphaFirst`, and
  `AlphaInfo.isPremultiplied`.
- Validation now rejects images whose `bitsPerComponent` is not 8, making the
  assumption baked into pixel decoding explicit.

### Changed

- **Breaking:** `Image.init` throws `ValidationError` when the data buffer is
  smaller than `height * bytesPerRow`, instead of trapping via `precondition`.
  Construction sites must use `try`.
- **Breaking:** `Renderer` now requires `draw(_:)` instead of `render(_:)`.
  `render(_:)` is provided by a protocol extension that validates the context
  first and throws `ValidationErrorCollection` for invalid input, so every
  backend enforces validation. Existing call sites of `render(_:)` keep
  working; custom renderers must rename their implementation to `draw(_:)`.
