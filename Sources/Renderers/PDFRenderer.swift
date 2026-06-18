//
//  PDFRenderer.swift
//  PureDraw
//

import Core
import Foundation
import Geometry

/// A renderer that exports a `GraphicsContext` drawing buffer as a PDF document (binary Data).
public struct PDFRenderer: Renderer {
    public typealias Output = Data

    public let width: Double
    public let height: Double

    /// Optional page boundary boxes, in user space (top-left origin); they
    /// convert to PDF coordinates on write. The media box is always the full
    /// page.
    public let cropBox: Rect?
    public let bleedBox: Rect?
    public let trimBox: Rect?
    public let artBox: Rect?

    /// Hot-spot link annotations placed on the page.
    public let links: [PDFLink]

    /// The document outline (bookmarks); empty means no outline.
    public let outline: [PDFOutlineItem]

    /// Standard-security-handler encryption; nil writes an open document.
    public let encryption: PDFEncryption?

    public init(
        width: Double = 500,
        height: Double = 500,
        cropBox: Rect? = nil,
        bleedBox: Rect? = nil,
        trimBox: Rect? = nil,
        artBox: Rect? = nil,
        links: [PDFLink] = [],
        outline: [PDFOutlineItem] = [],
        encryption: PDFEncryption? = nil
    ) {
        self.width = width
        self.height = height
        self.cropBox = cropBox
        self.bleedBox = bleedBox
        self.trimBox = trimBox
        self.artBox = artBox
        self.links = links
        self.outline = outline
        self.encryption = encryption
    }

    /// The `CGPDFPageGetDrawingTransform` equivalent: a transform that fits
    /// `box` into `rect`, rotated by the nearest multiple of 90 degrees,
    /// centered, and scaled down only (never up) when `preserveAspectRatio`
    /// is true.
    public static func drawingTransform(
        fitting box: Rect,
        into rect: Rect,
        rotationDegrees: Int = 0,
        preserveAspectRatio: Bool = true
    ) -> Geometry.AffineTransform {
        let normalized = ((rotationDegrees % 360) + 360) % 360
        let quarterTurns = ((normalized + 45) / 90) % 4
        let rotated = quarterTurns % 2 == 1
        let boxWidth = rotated ? box.height : box.width
        let boxHeight = rotated ? box.width : box.height
        guard boxWidth > 0, boxHeight > 0 else { return .identity }

        var scaleX = rect.width / boxWidth
        var scaleY = rect.height / boxHeight
        if preserveAspectRatio {
            let scale = min(min(scaleX, scaleY), 1.0)
            scaleX = scale
            scaleY = scale
        }

        return Geometry.AffineTransform.identity
            .translatedBy(x: -(box.minX + box.width / 2), y: -(box.minY + box.height / 2))
            .rotated(by: Double(quarterTurns) * Double.pi / 2)
            .scaledBy(x: scaleX, y: scaleY)
            .translatedBy(x: rect.minX + rect.width / 2, y: rect.minY + rect.height / 2)
    }

    public func draw(_ context: GraphicsContext) throws -> Data {
        let writer = PDFWriter()

        // The file ID seeds the encryption key; derive it deterministically so
        // identical input yields identical bytes.
        var prepared: PDFEncryption.Prepared?
        if let encryption {
            let seed = Array("PureDraw \(width)x\(height)".utf8)
                + PDFEncryption.padded(encryption.userPassword)
                + PDFEncryption.padded(encryption.ownerPassword)
            prepared = encryption.prepare(fileID: PDFEncryption.md5(seed))
        }

        /// RC4 preserves length, so headers written before encryption stay valid.
        func encryptedStream(_ data: Data) -> Data {
            guard let prepared else { return data }
            return Data(prepared.encrypt(Array(data), objectID: writer.nextObjectID))
        }

        /// A PDF text string: literal when open, encrypted hex when locked.
        func pdfTextString(_ text: String, objectID: Int) -> String {
            guard let prepared else { return "(\(escapedPDFString(text)))" }
            let encrypted = prepared.encrypt(Array(text.utf8), objectID: objectID)
            return "<" + encrypted.map { String(format: "%02X", $0) }.joined() + ">"
        }

        var extGStates: [ExtGStateKey: String] = [:]
        var shadings: [String: String] = [:] // shading dictionary content -> name
        var images: [String: Int] = [:] // image name -> object ID

        var contentStream = ""

        // PDF coordinate system starts at bottom-left.
        // PureDraw/CoreGraphics coordinate system starts at top-left.
        // We concatenate a transform to flip the Y axis.
        contentStream += "1 0 0 -1 0 \(height) cm\n"

        // Collect the fonts used by native text runs (named, identity-matrix
        // showText). Other text runs are already lowered to outlines.
        var fontUsages: [(font: Font, glyphs: Set<Int>, toUnicode: [Int: UInt32])] = []
        func fontIndex(_ font: Font) -> Int {
            if let index = fontUsages.firstIndex(where: { $0.font == font }) { return index }
            fontUsages.append((font: font, glyphs: [], toUnicode: [:]))
            return fontUsages.count - 1
        }
        for op in context.layerFlattenedCommands {
            guard case let .showText(glyphs, text, font, _, mode, _, _) = op.kind, mode != .invisible else { continue }
            let index = fontIndex(font)
            fontUsages[index].glyphs.formUnion(glyphs)
            if let text {
                let scalars = Array(text.unicodeScalars)
                for (position, glyph) in glyphs.enumerated() where position < scalars.count {
                    fontUsages[index].toUnicode[glyph] = scalars[position].value
                }
            }
        }
        // Embed each font as a Type0/CIDFontType2 with the program in FontFile2.
        var fontObjectIDs: [Int] = []
        for usage in fontUsages {
            fontObjectIDs.append(embedFont(usage.font, usedGlyphs: usage.glyphs, toUnicode: usage.toUnicode, writer: writer, encrypt: encryptedStream))
        }

        for (opIndex, op) in context.layerFlattenedCommands.enumerated() {
            contentStream += "q\n"

            // 1. Transform
            let t = op.state.transform
            if t != .identity {
                contentStream += "\(t.a) \(t.b) \(t.c) \(t.d) \(t.tx) \(t.ty) cm\n"
            }

            // 2. Alpha and Blend Mode
            let fillAlpha = op.state.fillColor.alpha * op.state.alpha
            let strokeAlpha = op.state.strokeColor.alpha * op.state.alpha
            let blendMode = op.state.blendMode
            if fillAlpha < 1.0 || strokeAlpha < 1.0 || blendMode != .normal {
                let key = ExtGStateKey(ca: fillAlpha, CA: strokeAlpha, blendMode: blendMode)
                let gsName: String
                if let existing = extGStates[key] {
                    gsName = existing
                } else {
                    gsName = "GS\(extGStates.count + 1)"
                    extGStates[key] = gsName
                }
                contentStream += "/\(gsName) gs\n"
            }

            // 3. Line properties
            contentStream += "\(op.state.lineWidth) w\n"

            let capValue = switch op.state.lineCap {
            case .butt: 0
            case .round: 1
            case .square: 2
            }
            contentStream += "\(capValue) J\n"

            let joinValue = switch op.state.lineJoin {
            case .miter: 0
            case .round: 1
            case .bevel: 2
            }
            contentStream += "\(joinValue) j\n"
            contentStream += "\(op.state.miterLimit) M\n"
            contentStream += "\(op.state.flatness) i\n"

            if !op.state.dashPattern.isEmpty {
                let patternStr = op.state.dashPattern.map { String($0) }.joined(separator: " ")
                contentStream += "[\(patternStr)] \(op.state.dashPhase) d\n"
            } else {
                contentStream += "[] 0 d\n"
            }

            // 4. Clip Path: clip each path in the stack; PDF's `W n` intersects with the
            // current clip, so the result is their intersection (not the unioned clipPath,
            // which would flood nested clips).
            for clip in op.state.clipPaths {
                contentStream += pdfPathString(for: clip)
                contentStream += "W n\n"
            }

            // 4b. Draw Shadow (if present)
            if let shadow = op.state.shadow {
                contentStream += "q\n"
                contentStream += "1 0 0 1 \(shadow.offset.x) \(shadow.offset.y) cm\n"

                let shadowAlpha = shadow.color.alpha * op.state.alpha
                let shadowKey = ExtGStateKey(ca: shadowAlpha, CA: shadowAlpha, blendMode: .normal)
                let sgsName: String
                if let existing = extGStates[shadowKey] {
                    sgsName = existing
                } else {
                    sgsName = "GS\(extGStates.count + 1)"
                    extGStates[shadowKey] = sgsName
                }
                contentStream += "/\(sgsName) gs\n"
                contentStream += pdfFillColorString(for: shadow.color)

                switch op.kind {
                case let .fill(path, rule):
                    let pathStr = pdfPathString(for: path)
                    contentStream += pathStr
                    if rule == .evenOdd {
                        contentStream += "f*\n"
                    } else {
                        contentStream += "f\n"
                    }
                case let .stroke(path):
                    contentStream += pdfStrokeColorString(for: shadow.color)
                    let pathStr = pdfPathString(for: path)
                    contentStream += pathStr
                    contentStream += "S\n"
                case .drawLinearGradient, .drawRadialGradient:
                    if let clip = op.state.clipPath {
                        let pathStr = pdfPathString(for: clip)
                        contentStream += pathStr
                        contentStream += "f\n"
                    }
                case .beginTransparencyLayer, .endTransparencyLayer, .drawImage, .drawLayer, .drawImageProjective, .dropShadow, .showText:
                    break
                }
                contentStream += "Q\n"
            }

            // 5. Draw
            switch op.kind {
            case let .fill(path, rule):
                contentStream += pdfFillColorString(for: op.state.fillColor)
                let pathStr = pdfPathString(for: path)
                contentStream += pathStr
                if rule == .evenOdd {
                    contentStream += "f*\n"
                } else {
                    contentStream += "f\n"
                }
            case let .stroke(path):
                contentStream += pdfStrokeColorString(for: op.state.strokeColor)
                let pathStr = pdfPathString(for: path)
                contentStream += pathStr
                contentStream += "S\n"
            case let .drawLinearGradient(grad, start, end, options):
                let extendStart = options.contains(.drawsBeforeStartLocation)
                let extendEnd = options.contains(.drawsAfterEndLocation)
                let shadingDict = """
                <<
                  /ShadingType 2
                  /ColorSpace /DeviceRGB
                  /Coords [ \(start.x) \(start.y) \(end.x) \(end.y) ]
                  /Function \(pdfFunction(for: grad))
                  /Extend [ \(extendStart) \(extendEnd) ]
                >>
                """
                let shName: String
                if let existing = shadings[shadingDict] {
                    shName = existing
                } else {
                    shName = "Sh\(shadings.count + 1)"
                    shadings[shadingDict] = shName
                }
                contentStream += "/\(shName) sh\n"
            case let .drawRadialGradient(grad, startCenter, startRadius, endCenter, endRadius, options):
                let extendStart = options.contains(.drawsBeforeStartLocation)
                let extendEnd = options.contains(.drawsAfterEndLocation)
                let shadingDict = """
                <<
                  /ShadingType 3
                  /ColorSpace /DeviceRGB
                  /Coords [ \(startCenter.x) \(startCenter.y) \(startRadius) \(endCenter.x) \(endCenter.y) \(endRadius) ]
                  /Function \(pdfFunction(for: grad))
                  /Extend [ \(extendStart) \(extendEnd) ]
                >>
                """
                let shName: String
                if let existing = shadings[shadingDict] {
                    shName = existing
                } else {
                    shName = "Sh\(shadings.count + 1)"
                    shadings[shadingDict] = shName
                }
                contentStream += "/\(shName) sh\n"
            case let .drawImage(image, rect):
                var rgbData = Data()
                var alphaData = Data()
                rgbData.reserveCapacity(image.width * image.height * 3)
                alphaData.reserveCapacity(image.width * image.height)

                let hasAlpha = image.alphaInfo != .none

                for index in stride(from: 0, to: image.data.count, by: 4) {
                    guard index + 3 < image.data.count else { break }
                    let r = Double(image.data[index]) / 255.0
                    let g = Double(image.data[index + 1]) / 255.0
                    let b = Double(image.data[index + 2]) / 255.0
                    let a = Double(image.data[index + 3]) / 255.0

                    var outR = r
                    var outG = g
                    var outB = b
                    var outA = a

                    switch image.alphaInfo {
                    case .premultipliedLast, .premultipliedFirst:
                        if a > 0 {
                            outR = r / a
                            outG = g / a
                            outB = b / a
                        }
                    case .last, .first:
                        break
                    case .none, .noneSkipLast, .noneSkipFirst:
                        outA = 1.0
                    }

                    rgbData.append(UInt8(min(255, max(0, Int(round(outR * 255.0))))))
                    rgbData.append(UInt8(min(255, max(0, Int(round(outG * 255.0))))))
                    rgbData.append(UInt8(min(255, max(0, Int(round(outB * 255.0))))))
                    alphaData.append(UInt8(min(255, max(0, Int(round(outA * 255.0))))))
                }

                // Valid zlib (FlateDecode) framing; Apple's NSData zlib emits
                // raw DEFLATE that viewers reject.
                let rgbCompressed = Data(PNGEncoder.zlibStored(Array(rgbData)))

                var smaskObjId: Int? = nil
                if hasAlpha {
                    let alphaCompressed = Data(PNGEncoder.zlibStored(Array(alphaData)))
                    var maskHeader = """
                    <<
                      /Type /XObject
                      /Subtype /Image
                      /Width \(image.width)
                      /Height \(image.height)
                      /ColorSpace /DeviceGray
                      /BitsPerComponent 8
                    """
                    maskHeader += "\n  /Filter /FlateDecode\n  /Length \(alphaCompressed.count)\n>>"
                    smaskObjId = writer.append(header: maskHeader, stream: encryptedStream(alphaCompressed))
                }

                var imgHeader = """
                <<
                  /Type /XObject
                  /Subtype /Image
                  /Width \(image.width)
                  /Height \(image.height)
                  /ColorSpace /DeviceRGB
                  /BitsPerComponent 8
                """
                if let maskId = smaskObjId {
                    imgHeader += "\n  /SMask \(maskId) 0 R"
                }

                let imgObjId: Int
                do {
                    imgHeader += "\n  /Filter /FlateDecode\n  /Length \(rgbCompressed.count)\n>>"
                    imgObjId = writer.append(header: imgHeader, stream: encryptedStream(rgbCompressed))
                }

                let imgName = "Img\(opIndex)"
                images[imgName] = imgObjId

                contentStream += "q\n"
                contentStream += "\(rect.width) 0 0 \(rect.height) \(rect.origin.x) \(rect.origin.y) cm\n"
                contentStream += "/\(imgName) Do\n"
                contentStream += "Q\n"
            case let .showText(glyphs, _, font, fontSize, mode, _, position):
                if !glyphs.isEmpty, mode != .invisible {
                    let name = "F\(fontIndex(font))"
                    let renderMode = switch mode {
                    case .fill: 0
                    case .stroke: 1
                    case .fillStroke: 2
                    case .invisible: 3
                    }
                    if mode != .stroke {
                        contentStream += pdfFillColorString(for: op.state.fillColor)
                    }
                    if mode != .fill {
                        contentStream += pdfStrokeColorString(for: op.state.strokeColor)
                    }
                    let hex = glyphs.map { String(format: "%04X", $0 & 0xFFFF) }.joined()
                    contentStream += "BT\n"
                    contentStream += "\(renderMode) Tr\n"
                    contentStream += "/\(name) \(fontSize) Tf\n"
                    // Counter the page Y-flip so glyphs render upright.
                    contentStream += "1 0 0 -1 \(position.x) \(position.y) Tm\n"
                    contentStream += "<\(hex)> Tj\n"
                    contentStream += "ET\n"
                }
            case .beginTransparencyLayer, .endTransparencyLayer:
                break // transparency group flattened
            case .drawLayer:
                break // expanded by layerFlattenedCommands
            case .drawImageProjective:
                throw UnsupportedOperationError(operation: "drawImageProjective", renderer: "PDFRenderer")
            case .dropShadow:
                throw UnsupportedOperationError(operation: "dropShadow", renderer: "PDFRenderer")
            }

            contentStream += "Q\n"
        }

        // Assemble resources and document catalog objects. Image objects may
        // already occupy low IDs, so every reference is computed, not assumed.
        let catalogID = writer.nextObjectID
        let pagesID = catalogID + 1
        let pageID = catalogID + 2
        let contentsID = catalogID + 3
        let annotIDs = links.indices.map { contentsID + 1 + $0 }
        let outlineRootID = contentsID + 1 + links.count
        writer.rootObjectID = catalogID
        var catalogDict = "<< /Type /Catalog /Pages \(pagesID) 0 R"
        if !outline.isEmpty {
            catalogDict += " /Outlines \(outlineRootID) 0 R"
        }
        catalogDict += " >>"
        _ = writer.append(catalogDict)
        _ = writer.append("<< /Type /Pages /Kids [ \(pageID) 0 R ] /Count 1 >>")

        var resourcesStr = "<<"
        if !extGStates.isEmpty {
            resourcesStr += "\n  /ExtGState <<"
            for (key, gsName) in extGStates {
                let bmName = switch key.blendMode {
                case .normal: "Normal"
                case .multiply: "Multiply"
                case .screen: "Screen"
                case .overlay: "Overlay"
                case .darken: "Darken"
                case .lighten: "Lighten"
                case .colorDodge: "ColorDodge"
                case .colorBurn: "ColorBurn"
                case .softLight: "SoftLight"
                case .hardLight: "HardLight"
                case .difference: "Difference"
                case .exclusion: "Exclusion"
                case .hue: "Hue"
                case .saturation: "Saturation"
                case .color: "Color"
                case .luminosity: "Luminosity"
                default: "Normal"
                }
                resourcesStr += "\n    /\(gsName) << /Type /ExtGState /ca \(key.ca) /CA \(key.CA) /BM /\(bmName) >>"
            }
            resourcesStr += "\n  >>"
        }
        if !shadings.isEmpty {
            resourcesStr += "\n  /Shading <<"
            for (key, shName) in shadings {
                resourcesStr += "\n    /\(shName) \(key)"
            }
            resourcesStr += "\n  >>"
        }
        if !images.isEmpty {
            resourcesStr += "\n  /XObject <<"
            for (name, objId) in images {
                resourcesStr += "\n    /\(name) \(objId) 0 R"
            }
            resourcesStr += "\n  >>"
        }
        if !fontObjectIDs.isEmpty {
            resourcesStr += "\n  /Font <<"
            for (index, objID) in fontObjectIDs.enumerated() {
                resourcesStr += "\n    /F\(index) \(objID) 0 R"
            }
            resourcesStr += "\n  >>"
        }
        resourcesStr += "\n>>"

        var pageDict = "<< /Type /Page /Parent \(pagesID) 0 R /MediaBox [ 0 0 \(width) \(height) ]"
        for (name, box) in [("CropBox", cropBox), ("BleedBox", bleedBox), ("TrimBox", trimBox), ("ArtBox", artBox)] {
            if let box {
                pageDict += " /\(name) \(pdfBoxString(for: box))"
            }
        }
        if !annotIDs.isEmpty {
            pageDict += " /Annots [ " + annotIDs.map { "\($0) 0 R" }.joined(separator: " ") + " ]"
        }
        pageDict += " /Contents \(contentsID) 0 R /Resources \(resourcesStr) >>"
        _ = writer.append(pageDict)
        let contentData = encryptedStream(Data(contentStream.utf8))
        _ = writer.append(header: "<< /Length \(contentData.count) >>", stream: contentData)

        for link in links {
            let rect = link.rect
            let pdfRect = "[ \(rect.minX) \(height - rect.maxY) \(rect.maxX) \(height - rect.minY) ]"
            let action = switch link.target {
            case let .url(url):
                "/A << /S /URI /URI \(pdfTextString(url, objectID: writer.nextObjectID)) >>"
            case let .destination(point):
                "/Dest [ \(pageID) 0 R /XYZ \(point.x) \(height - point.y) null ]"
            }
            _ = writer.append("<< /Type /Annot /Subtype /Link /Rect \(pdfRect) /Border [ 0 0 0 ] \(action) >>")
        }

        if !outline.isEmpty {
            appendOutline(to: writer, rootID: outlineRootID, pageID: pageID, textString: pdfTextString)
        }

        if let prepared {
            func hex(_ bytes: [UInt8]) -> String {
                bytes.map { String(format: "%02X", $0) }.joined()
            }
            writer.encryptObjectID = writer.append(
                "<< /Filter /Standard /V 1 /R 2 /O <\(hex(prepared.oValue))> /U <\(hex(prepared.uValue))> /P \(prepared.permissionsValue) >>"
            )
            writer.fileIDHex = hex(prepared.fileID)
        }

        return writer.buildData()
    }

    // MARK: - Outline Assembly

    private func subtreeSize(_ item: PDFOutlineItem) -> Int {
        1 + item.children.reduce(0) { $0 + subtreeSize($1) }
    }

    private func appendOutline(to writer: PDFWriter, rootID: Int, pageID: Int, textString: (String, Int) -> String) {
        let totalCount = outline.reduce(0) { $0 + subtreeSize($1) }
        let firstID = rootID + 1
        let lastID = siblingIDs(for: outline, startingAt: firstID).last ?? firstID
        _ = writer.append("<< /Type /Outlines /First \(firstID) 0 R /Last \(lastID) 0 R /Count \(totalCount) >>")
        appendOutlineItems(outline, parentID: rootID, startingAt: firstID, to: writer, pageID: pageID, textString: textString)
    }

    /// Object IDs of a sibling run laid out in pre-order starting at `startID`.
    private func siblingIDs(for items: [PDFOutlineItem], startingAt startID: Int) -> [Int] {
        var ids: [Int] = []
        var nextID = startID
        for item in items {
            ids.append(nextID)
            nextID += subtreeSize(item)
        }
        return ids
    }

    private func appendOutlineItems(_ items: [PDFOutlineItem], parentID: Int, startingAt startID: Int, to writer: PDFWriter, pageID: Int, textString: (String, Int) -> String) {
        let ids = siblingIDs(for: items, startingAt: startID)
        for (index, item) in items.enumerated() {
            let id = ids[index]
            var dict = "<< /Title \(textString(item.title, id)) /Parent \(parentID) 0 R"
            if index > 0 {
                dict += " /Prev \(ids[index - 1]) 0 R"
            }
            if index < items.count - 1 {
                dict += " /Next \(ids[index + 1]) 0 R"
            }
            if !item.children.isEmpty {
                let childIDs = siblingIDs(for: item.children, startingAt: id + 1)
                dict += " /First \(childIDs[0]) 0 R /Last \(childIDs[childIDs.count - 1]) 0 R"
                dict += " /Count \(item.children.reduce(0) { $0 + subtreeSize($1) })"
            }
            dict += " /Dest [ \(pageID) 0 R /XYZ \(item.destination.x) \(height - item.destination.y) null ]"
            dict += " >>"
            _ = writer.append(dict)
            if !item.children.isEmpty {
                appendOutlineItems(item.children, parentID: id, startingAt: id + 1, to: writer, pageID: pageID, textString: textString)
            }
        }
    }

    /// Escapes backslashes and parentheses for a PDF literal string.
    private func escapedPDFString(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")
    }

    /// A user-space rect (top-left origin) as a PDF rectangle (bottom-left).
    private func pdfBoxString(for box: Rect) -> String {
        "[ \(box.minX) \(height - box.maxY) \(box.maxX) \(height - box.minY) ]"
    }

    /// Embeds a TrueType font as a Type 0 composite font (Identity-H) whose
    /// descendant CIDFontType2 carries the program in FontFile2 with an
    /// identity CID-to-GID map, the used glyph widths, and a ToUnicode CMap
    /// for copy/paste. Returns the Type 0 font object ID.
    private func embedFont(_ font: Font, usedGlyphs: Set<Int>, toUnicode: [Int: UInt32], writer: PDFWriter, encrypt: (Data) -> Data) -> Int {
        let upem = Double(font.unitsPerEm)
        let scale = upem > 0 ? 1000.0 / upem : 1.0
        func scaled(_ value: Double) -> Int {
            Int((value * scale).rounded())
        }
        // A content-derived 6-letter subset tag keeps each distinct font
        // program uniquely named, so a viewer's font cache (keyed by PostScript
        // name) never serves one document's program for another's.
        let psName = "\(Self.subsetTag(for: font.sfntData))+PureDrawFont"

        // FontFile2: the raw sfnt program in a valid zlib (FlateDecode) stream.
        // Apple's NSData zlib compression emits raw DEFLATE, which CoreGraphics
        // cannot decode as FlateDecode, so use PureDraw's zlib writer.
        let program = font.sfntData
        let programStream = Data(PNGEncoder.zlibStored(program))
        let fontFileHeader = "<<\n  /Length1 \(program.count)\n  /Filter /FlateDecode\n  /Length \(programStream.count)\n>>"
        let fontFileID = writer.append(header: fontFileHeader, stream: encrypt(programStream))

        // FontDescriptor. Flag 4 marks a symbolic font (Identity-H encoding).
        let ascent = scaled(font.ascent)
        let descent = scaled(font.descent)
        let descriptor = "<< /Type /FontDescriptor /FontName /\(psName) /Flags 4"
            + " /FontBBox [ 0 \(descent) 1000 \(ascent) ] /ItalicAngle 0"
            + " /Ascent \(ascent) /Descent \(descent) /CapHeight \(ascent) /StemV 80"
            + " /FontFile2 \(fontFileID) 0 R >>"
        let descriptorID = writer.append(descriptor)

        // Per-glyph widths in 1000-unit text space.
        var widths = "[ "
        for glyph in usedGlyphs.sorted() {
            widths += "\(glyph) [\(scaled(font.advanceWidth(forGlyph: glyph)))] "
        }
        widths += "]"

        let cidFont = "<< /Type /Font /Subtype /CIDFontType2 /BaseFont /\(psName)"
            + " /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >>"
            + " /FontDescriptor \(descriptorID) 0 R /CIDToGIDMap /Identity /DW 1000 /W \(widths) >>"
        let cidFontID = writer.append(cidFont)

        // ToUnicode CMap: maps 2-byte glyph codes back to Unicode for search.
        let cmapBody = Data(toUnicodeCMap(toUnicode).utf8)
        let toUnicodeID = writer.append(header: "<< /Length \(cmapBody.count) >>", stream: encrypt(cmapBody))
        let type0 = "<< /Type /Font /Subtype /Type0 /BaseFont /\(psName)"
            + " /Encoding /Identity-H /DescendantFonts [ \(cidFontID) 0 R ]"
            + " /ToUnicode \(toUnicodeID) 0 R >>"
        return writer.append(type0)
    }

    /// A deterministic six-uppercase-letter subset tag (PDF font-naming
    /// convention) derived from the font program via FNV-1a, so distinct
    /// programs get distinct PostScript names.
    private static func subsetTag(for bytes: [UInt8]) -> String {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        var tag = ""
        for _ in 0 ..< 6 {
            tag.append(Character(UnicodeScalar(UInt8(65 + Int(hash % 26)))))
            hash /= 26
        }
        return tag
    }

    /// Builds the ToUnicode CMap stream body mapping 2-byte glyph codes to
    /// Unicode scalars, for selectable/searchable text.
    private func toUnicodeCMap(_ mapping: [Int: UInt32]) -> String {
        var body = """
        /CIDInit /ProcSet findresource begin
        12 dict begin
        begincmap
        /CMapName /Adobe-Identity-UCS def
        /CMapType 2 def
        1 begincodespacerange
        <0000> <FFFF>
        endcodespacerange
        """
        let entries = mapping.sorted { $0.key < $1.key }
        if !entries.isEmpty {
            body += "\n\(entries.count) beginbfchar\n"
            for (glyph, scalar) in entries {
                body += String(format: "<%04X> <%04X>\n", glyph & 0xFFFF, scalar & 0xFFFF)
            }
            body += "endbfchar\n"
        }
        body += "endcmap\nCMapName currentdict /CMap defineresource pop\nend\nend"
        return body
    }

    private func pdfFillColorString(for color: Color) -> String {
        switch color.colorSpace {
        case .deviceRGB:
            "\(color.components[0]) \(color.components[1]) \(color.components[2]) rg\n"
        case .deviceGray:
            "\(color.components[0]) g\n"
        case .deviceCMYK:
            "\(color.components[0]) \(color.components[1]) \(color.components[2]) \(color.components[3]) k\n"
        }
    }

    private func pdfStrokeColorString(for color: Color) -> String {
        switch color.colorSpace {
        case .deviceRGB:
            "\(color.components[0]) \(color.components[1]) \(color.components[2]) RG\n"
        case .deviceGray:
            "\(color.components[0]) G\n"
        case .deviceCMYK:
            "\(color.components[0]) \(color.components[1]) \(color.components[2]) \(color.components[3]) K\n"
        }
    }

    private func pdfPathString(for path: Path) -> String {
        var str = ""
        var currentPoint = Point(x: 0, y: 0)

        for element in path.elements {
            switch element {
            case let .move(to):
                str += "\(to.x) \(to.y) m\n"
                currentPoint = to
            case let .line(to):
                str += "\(to.x) \(to.y) l\n"
                currentPoint = to
            case let .quadCurve(to, control):
                let c1x = currentPoint.x + (2.0 / 3.0) * (control.x - currentPoint.x)
                let c1y = currentPoint.y + (2.0 / 3.0) * (control.y - currentPoint.y)
                let c2x = to.x + (2.0 / 3.0) * (control.x - to.x)
                let c2y = to.y + (2.0 / 3.0) * (control.y - to.y)
                str += "\(c1x) \(c1y) \(c2x) \(c2y) \(to.x) \(to.y) c\n"
                currentPoint = to
            case let .cubicCurve(to, control1, control2):
                str += "\(control1.x) \(control1.y) \(control2.x) \(control2.y) \(to.x) \(to.y) c\n"
                currentPoint = to
            case .close:
                str += "h\n"
            }
        }
        return str
    }

    private func pdfFunction(for gradient: Gradient) -> String {
        let stops = gradient.stops.sorted(by: { $0.location < $1.location })
        if stops.count < 2 {
            return "<< /FunctionType 2 /Domain [ 0 1 ] /C0 [ 0 0 0 ] /C1 [ 0 0 0 ] /N 1 >>"
        }
        if stops.count == 2 {
            let s0 = stops[0]
            let s1 = stops[1]
            return "<< /FunctionType 2 /Domain [ 0 1 ] /C0 [ \(s0.color.red) \(s0.color.green) \(s0.color.blue) ] /C1 [ \(s1.color.red) \(s1.color.green) \(s1.color.blue) ] /N 1 >>"
        }

        var bounds: [String] = []
        var encode: [String] = []
        var functions: [String] = []

        for i in 0 ..< (stops.count - 1) {
            let s0 = stops[i]
            let s1 = stops[i + 1]
            if i > 0 {
                bounds.append("\(s0.location)")
            }
            encode.append("0 1")
            functions
                .append(
                    "<< /FunctionType 2 /Domain [ 0 1 ] /C0 [ \(s0.color.red) \(s0.color.green) \(s0.color.blue) ] /C1 [ \(s1.color.red) \(s1.color.green) \(s1.color.blue) ] /N 1 >>"
                )
        }

        return """
        <<
          /FunctionType 3
          /Domain [ 0 1 ]
          /Functions [
            \(functions.joined(separator: "\n    "))
          ]
          /Bounds [ \(bounds.joined(separator: " ")) ]
          /Encode [ \(encode.joined(separator: " ")) ]
        >>
        """
    }

    // MARK: - Nested Helper Types

    private struct ExtGStateKey: Hashable {
        let ca: Double
        let CA: Double
        let blendMode: BlendMode
    }

    private class PDFWriter {
        var objects: [Data] = []
        var rootObjectID = 1
        var encryptObjectID: Int?
        var fileIDHex: String?

        var nextObjectID: Int {
            objects.count + 1
        }

        func append(_ objectContent: String) -> Int {
            let objIndex = objects.count + 1
            let fullObject = "\(objIndex) 0 obj\n\(objectContent)\nendobj\n"
            objects.append(Data(fullObject.utf8))
            return objIndex
        }

        func append(header: String, stream: Data) -> Int {
            let objIndex = objects.count + 1
            var data = Data()
            data.append(Data("\(objIndex) 0 obj\n\(header)\nstream\n".utf8))
            data.append(stream)
            data.append(Data("\nendstream\nendobj\n".utf8))
            objects.append(data)
            return objIndex
        }

        func buildData() -> Data {
            var data = Data()

            let header = "%PDF-1.4\n"
            data.append(Data(header.utf8))

            var currentOffset = header.count
            var objectOffsets: [Int] = []

            for obj in objects {
                objectOffsets.append(currentOffset)
                data.append(obj)
                currentOffset += obj.count
            }

            let xrefOffset = currentOffset

            var xref = "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
            for offset in objectOffsets {
                xref += String(format: "%010d 00000 n \n", offset)
            }
            data.append(Data(xref.utf8))

            var trailerDict = "/Size \(objects.count + 1)\n  /Root \(rootObjectID) 0 R"
            if let encryptObjectID {
                trailerDict += "\n  /Encrypt \(encryptObjectID) 0 R"
            }
            if let fileIDHex {
                trailerDict += "\n  /ID [ <\(fileIDHex)> <\(fileIDHex)> ]"
            }
            let trailer = """
            trailer
            <<
              \(trailerDict)
            >>
            startxref
            \(xrefOffset)
            %%EOF
            """
            data.append(Data(trailer.utf8))

            return data
        }
    }
}
