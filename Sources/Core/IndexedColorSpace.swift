//
//  IndexedColorSpace.swift
//  PureDraw
//

/// An indexed (palette) color space, the `CGColorSpaceCreateIndexed` equivalent: a small color table
/// over a base color space, where each image sample is an *index* into the table rather than a color
/// value.
///
/// An indexed space belongs to a sampled image, never to a single ``Color``: a color value is always a
/// concrete device color, so "an indexed color" is not a representable state. The palette entries are
/// ordinary ``Color`` values in the base space, and each carries its own alpha (a transparent palette
/// entry, the analog of a PNG `tRNS` table, needs no separate alpha channel). An image is indexed when
/// its ``Image/indexedColorSpace`` is set; its byte samples are then looked up here.
public struct IndexedColorSpace: Equatable, Sendable {
    /// The base color space the palette entries are expressed in.
    public let base: ColorSpace
    /// The color table; sample `i` resolves to `palette[i]`.
    public let palette: [Color]

    /// Creates an indexed color space over `base` with the given color table.
    public init(base: ColorSpace, palette: [Color]) {
        self.base = base
        self.palette = palette
    }

    /// Resolves a sample to its palette color, clamping an out-of-range index to the table's bounds, as
    /// Core Graphics does. An empty palette has no color and resolves to clear.
    public func color(at index: Int) -> Color {
        guard !palette.isEmpty else { return .clear }
        let clamped = min(max(0, index), palette.count - 1)
        return palette[clamped]
    }
}
