//
//  PDFEncryptionTests.swift
//  PureDraw
//

import Core
import Foundation
import Geometry
@testable import Renderers
import Testing

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

struct PDFEncryptionTests {
    @Test func md5MatchesKnownVectors() {
        #expect(hex(PDFEncryption.md5([])) == "d41d8cd98f00b204e9800998ecf8427e")
        #expect(hex(PDFEncryption.md5(Array("abc".utf8))) == "900150983cd24fb0d6963f7d28e17f72")
        #expect(
            hex(PDFEncryption.md5(Array("The quick brown fox jumps over the lazy dog".utf8)))
                == "9e107d9d372bb6826bd81d3542a419d6"
        )
    }

    @Test func rc4MatchesKnownVector() {
        let encrypted = PDFEncryption.rc4(key: Array("Key".utf8), Array("Plaintext".utf8))
        #expect(hex(encrypted) == "bbf316e8d940af0ad3")
        // RC4 is symmetric.
        #expect(PDFEncryption.rc4(key: Array("Key".utf8), encrypted) == Array("Plaintext".utf8))
    }

    @Test func encryptedDocumentHasEncryptDictionaryAndScrambledContent() throws {
        var context = GraphicsContext()
        context.setFillColor(.black)
        context.addRect(Rect(x: 0, y: 0, width: 10, height: 10))
        context.fillPath()

        let open = try PDFRenderer(width: 100, height: 100).render(context)
        let locked = try PDFRenderer(
            width: 100,
            height: 100,
            outline: [PDFOutlineItem(title: "Top", destination: Point(x: 0, y: 0))],
            encryption: PDFEncryption(userPassword: "secret", permissions: [.printing])
        ).render(context)

        let lockedText = String(decoding: locked, as: UTF8.self)
        #expect(lockedText.contains("/Filter /Standard /V 1 /R 2"))
        #expect(lockedText.contains("/Encrypt"))
        #expect(lockedText.contains("/ID [ <"))
        // Permission bits: print only, reserved high bits set.
        #expect(lockedText.contains("/P -64508") || lockedText.contains("/P \(Int32(bitPattern: 0xFFFF_FFC4))"))

        // The content stream must not appear in cleartext.
        let openText = String(decoding: open, as: UTF8.self)
        #expect(openText.contains("re") || openText.contains(" m\n"))
        #expect(!lockedText.contains("0.0 0.0 m"), "path operators must be encrypted")
        // The title string must be hex, not a literal.
        #expect(!lockedText.contains("(Top)"))

        #if canImport(CoreGraphics)
            let provider = try #require(CGDataProvider(data: locked as CFData))
            let document = try #require(CGPDFDocument(provider))
            #expect(document.isEncrypted)
            #expect(document.unlockWithPassword("wrong") == false)
            #expect(document.unlockWithPassword("secret"))
            #expect(document.isUnlocked)
            #expect(document.numberOfPages == 1)
            #expect(document.allowsPrinting)
            #expect(!document.allowsCopying)
        #endif
    }

    @Test func emptyUserPasswordOpensWithoutPrompt() throws {
        var context = GraphicsContext()
        context.setFillColor(.black)
        context.addRect(Rect(x: 0, y: 0, width: 10, height: 10))
        context.fillPath()

        let locked = try PDFRenderer(
            width: 100,
            height: 100,
            encryption: PDFEncryption(userPassword: "", ownerPassword: "owner")
        ).render(context)

        #if canImport(CoreGraphics)
            let provider = try #require(CGDataProvider(data: locked as CFData))
            let document = try #require(CGPDFDocument(provider))
            #expect(document.isEncrypted)
            // An empty user password unlocks implicitly.
            #expect(document.isUnlocked)
            #expect(document.numberOfPages == 1)
        #endif
    }

    private func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}
