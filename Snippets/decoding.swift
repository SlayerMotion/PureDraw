// Decoding encoded bytes with PureDraw's dependency-free decoders. Every decoder is strict:
// unsupported or malformed input throws, it is never guessed.
import PureDraw

// snippet.hide
func encodedPNG() -> [UInt8] { [] }
func sfntBytes() -> [UInt8] { [] }
func woffBytes() -> [UInt8] { [] }
// snippet.show

// A PNG (or a `data:` URI) decodes into a straight-RGBA `Image`.
do {
    let image = try ImageDecoder.decode(encodedPNG())
    print("decoded \(image.width) x \(image.height)")
} catch {
    print("not a supported image: \(error)")
}

// A font parses from its sfnt bytes; a glyph's outline comes back as a `Path` in font units.
do {
    let font = try Font(data: sfntBytes())
    if let glyph = font.glyphIndex(for: "A"), let outline = font.outline(forGlyph: glyph) {
        print("glyph A is \(outline.elements.count) path elements")
    }
} catch {
    print("not a font: \(error)")
}

// A WOFF 1.0 wrapper is unwrapped to sfnt and parsed in one step.
let webFont = try? Font(woff: woffBytes())
print(webFont.map { "variable: \($0.isVariable)" } ?? "not a WOFF")
