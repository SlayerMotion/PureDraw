//
//  PDFScannerTests.swift
//  PureDraw
//

import Core
import Foundation
import Geometry
@testable import Renderers
import Testing

struct PDFScannerTests {
    @Test func dispatchesOperatorsWithOperands() {
        var scanner = PDFScanner()
        var moves: [[PDFScanner.Operand]] = []
        var lines: [[PDFScanner.Operand]] = []
        var strokes = 0
        scanner.setHandler(forOperator: "m") { moves.append($0) }
        scanner.setHandler(forOperator: "l") { lines.append($0) }
        scanner.setHandler(forOperator: "S") { _ in strokes += 1 }

        scanner.scan("q 10 20 m 30.5 -40 l S Q")

        #expect(moves == [[.integer(10), .integer(20)]])
        #expect(lines == [[.real(30.5), .integer(-40)]])
        #expect(strokes == 1)
    }

    @Test func parsesCompositeOperands() {
        var scanner = PDFScanner()
        var dashes: [[PDFScanner.Operand]] = []
        var marked: [[PDFScanner.Operand]] = []
        var texts: [[PDFScanner.Operand]] = []
        scanner.setHandler(forOperator: "d") { dashes.append($0) }
        scanner.setHandler(forOperator: "BDC") { marked.append($0) }
        scanner.setHandler(forOperator: "Tj") { texts.append($0) }

        scanner.scan("[1 2.5] 0 d /Span << /Lang (en) /Open true >> BDC (Hi \\(there\\)) Tj <48 69> Tj")

        #expect(dashes == [[.array([.integer(1), .real(2.5)]), .integer(0)]])
        #expect(marked == [[
            .name("Span"),
            .dictionary(["Lang": .string(Array("en".utf8)), "Open": .boolean(true)]),
        ]])
        #expect(texts == [
            [.string(Array("Hi (there)".utf8))],
            [.string(Array("Hi".utf8))],
        ])
    }

    @Test func unknownOperatorsConsumeOperands() {
        var scanner = PDFScanner()
        var moves: [[PDFScanner.Operand]] = []
        var fills: [[PDFScanner.Operand]] = []
        scanner.setHandler(forOperator: "m") { moves.append($0) }
        scanner.setHandler(forOperator: "f") { fills.append($0) }

        // The unregistered "cm" must clear its six operands off the stack,
        // so "m" sees exactly its own two.
        scanner.scan("1 0 0 -1 0 100 cm 5 5 m f % trailing comment\n")

        #expect(moves == [[.integer(5), .integer(5)]])
        #expect(fills == [[]])
    }

    @Test func scansOurOwnRendererOutput() throws {
        var context = GraphicsContext()
        context.setFillColor(Color(red: 1, green: 0, blue: 0, alpha: 1))
        context.move(to: Point(x: 1, y: 2))
        context.addLine(to: Point(x: 30, y: 2))
        context.addLine(to: Point(x: 30, y: 20))
        context.closeSubpath()
        context.fillPath()

        let pdf = try PDFRenderer(width: 50, height: 50).render(context)
        let text = String(decoding: pdf, as: UTF8.self)
        let streamStart = try #require(text.range(of: "stream\n"))
        let streamEnd = try #require(text.range(of: "\nendstream"))
        let content = String(text[streamStart.upperBound ..< streamEnd.lowerBound])

        var scanner = PDFScanner()
        var moveTargets: [Point] = []
        var lineCount = 0
        var fillCount = 0
        scanner.setHandler(forOperator: "m") { operands in
            if operands.count == 2, let x = operands[0].numberValue, let y = operands[1].numberValue {
                moveTargets.append(Point(x: x, y: y))
            }
        }
        scanner.setHandler(forOperator: "l") { _ in lineCount += 1 }
        scanner.setHandler(forOperator: "f") { _ in fillCount += 1 }

        scanner.scan(content)

        #expect(moveTargets == [Point(x: 1, y: 2)])
        #expect(lineCount == 2)
        #expect(fillCount == 1)
    }
}
