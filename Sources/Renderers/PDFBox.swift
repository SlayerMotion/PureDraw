//
//  PDFBox.swift
//  PureDraw
//

/// The named rectangles a PDF page can carry, the `CGPDFPageGetBoxRect` boxes. Every page has a media
/// box; the others default to it when absent, as Core Graphics does.
public enum PDFBox: String, Equatable, Sendable, CaseIterable {
    case media = "MediaBox"
    case crop = "CropBox"
    case bleed = "BleedBox"
    case trim = "TrimBox"
    case art = "ArtBox"
}
