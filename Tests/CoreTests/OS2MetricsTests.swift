import Foundation
import Testing
@testable import PureDraw

/// OS/2 typographic metrics drive line height in Core Text and SwiftUI, distinct
/// from the `hhea` em-box. These tests pin the parse two ways: a deterministic
/// synthetic font exercises both the OS/2 path and the absent-table fallback, and
/// a macOS-gated check reads Arial's real published values as a ground-truth oracle.
@Suite("OS/2 typographic metrics")
struct OS2MetricsTests {

    /// Builds a minimal valid OS/2 table (version 0, 78+ bytes) carrying the three
    /// typographic metrics at their fixed offsets 68/70/72.
    private func os2Table(typoAscender: Int, typoDescender: Int, typoLineGap: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 96) // zero through version, panose, ranges
        func putI16(_ value: Int, at index: Int) {
            bytes[index] = UInt8((value >> 8) & 0xFF)
            bytes[index + 1] = UInt8(value & 0xFF)
        }
        putI16(typoAscender, at: 68)
        putI16(typoDescender & 0xFFFF, at: 70) // two's-complement for negative descenders
        putI16(typoLineGap, at: 72)
        return bytes
    }

    @Test func readsOS2TypoMetricsDistinctFromHhea() throws {
        // Values chosen to differ from MiniFont's hhea (800 / -200 / 0), so a pass
        // proves the OS/2 path is taken, not an hhea coincidence.
        let os2 = os2Table(typoAscender: 750, typoDescender: -250, typoLineGap: 90)
        let font = try Font(data: MiniFont.build(extraTables: [("OS/2", os2)]))
        #expect(font.typoAscender == 750)
        #expect(font.typoDescender == -250)
        #expect(font.typoLineGap == 90)
        // hhea metrics remain unchanged and distinct, confirming the two are separate.
        #expect(font.ascent == 800)
        #expect(font.descent == -200)
    }

    @Test func fallsBackToHheaWhenNoOS2() throws {
        // MiniFont carries no OS/2 table: the typo metrics must fall back to hhea
        // (ascender 800, descender -200, lineGap 0).
        let font = try Font(data: MiniFont.build())
        #expect(font.typoAscender == font.ascent)
        #expect(font.typoDescender == font.descent)
        #expect(font.typoLineGap == 0)
    }

    #if os(macOS)
    @Test func arialOS2MatchesPublishedValues() throws {
        // Real-artifact oracle: Arial's OS/2 (unitsPerEm 2048) publishes
        // sTypoAscender 1491, sTypoDescender -431, sTypoLineGap 307. These differ
        // from its hhea metrics (1854 / -434), so reading them proves the OS/2 path
        // end to end on a shipping font.
        let path = "/System/Library/Fonts/Supplemental/Arial.ttf"
        guard let data = try? Array(Data(contentsOf: URL(fileURLWithPath: path))) else {
            return // Arial not present on this host; the synthetic tests still cover the parse.
        }
        let font = try Font(data: data)
        #expect(font.unitsPerEm == 2048)
        #expect(font.typoAscender == 1491)
        #expect(font.typoDescender == -431)
        #expect(font.typoLineGap == 307)
        #expect(font.ascent == 1854)   // hhea, distinct from typo
        #expect(font.descent == -434)
    }
    #endif
}
