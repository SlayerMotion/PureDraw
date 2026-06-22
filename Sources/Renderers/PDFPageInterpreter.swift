//
//  PDFPageInterpreter.swift
//  PureDraw
//

import Core
import Geometry

/// Replays a PDF page's content stream into a ``GraphicsContext``, the read-side counterpart of
/// `CGContextDrawPDFPage`. It dispatches the content operators through ``PDFScanner`` into graphics
/// state, path construction, and painting calls, reproducing the drawing as recorded operations.
///
/// This slice covers path building (`m`, `l`, `c`, `re`, `h`), painting (`f`, `f*`, `S`), color
/// (`rg`/`g`/`k` and the stroke forms), the CTM (`cm`), the graphics-state stack (`q`/`Q`), and line
/// parameters (`w`, `J`, `j`, `M`, `d`). Operators it does not yet replay (text `BT`/`Tj`, images
/// `Do`, shadings `sh`, clipping `W`, extended state `gs`) are skipped rather than misdrawn, so a page
/// that uses them is reproduced only in part. The class form lets the scanner's escaping handlers
/// mutate the accumulating context.
public final class PDFPageInterpreter {
    /// The context the content is replayed into.
    public private(set) var context = GraphicsContext()

    public init() {}

    /// Interprets the content-stream bytes, returning the resulting context.
    public func interpret(_ content: [UInt8]) -> GraphicsContext {
        context = GraphicsContext()
        var scanner = PDFScanner()
        registerPathOperators(into: &scanner)
        registerColorOperators(into: &scanner)
        registerStateOperators(into: &scanner)
        scanner.scan(content)
        return context
    }

    private func numbers(_ operands: [PDFScanner.Operand]) -> [Double] {
        operands.compactMap(\.numberValue)
    }

    private func registerPathOperators(into scanner: inout PDFScanner) {
        // Path construction.
        scanner.setHandler(forOperator: "m") { [self] ops in
            let n = numbers(ops)
            if n.count >= 2 { context.move(to: Point(x: n[0], y: n[1])) }
        }
        scanner.setHandler(forOperator: "l") { [self] ops in
            let n = numbers(ops)
            if n.count >= 2 { context.addLine(to: Point(x: n[0], y: n[1])) }
        }
        scanner.setHandler(forOperator: "c") { [self] ops in
            let n = numbers(ops)
            if n.count >= 6 {
                context.addCurve(
                    to: Point(x: n[4], y: n[5]),
                    control1: Point(x: n[0], y: n[1]),
                    control2: Point(x: n[2], y: n[3])
                )
            }
        }
        scanner.setHandler(forOperator: "re") { [self] ops in
            let n = numbers(ops)
            if n.count >= 4 { context.addRect(Rect(x: n[0], y: n[1], width: n[2], height: n[3])) }
        }
        scanner.setHandler(forOperator: "h") { [self] _ in context.closeSubpath() }

        // Painting.
        scanner.setHandler(forOperator: "f") { [self] _ in context.fillPath(using: .winding) }
        scanner.setHandler(forOperator: "F") { [self] _ in context.fillPath(using: .winding) }
        scanner.setHandler(forOperator: "f*") { [self] _ in context.fillPath(using: .evenOdd) }
        scanner.setHandler(forOperator: "S") { [self] _ in context.strokePath() }
    }

    private func registerColorOperators(into scanner: inout PDFScanner) {
        scanner.setHandler(forOperator: "rg") { [self] ops in
            let n = numbers(ops)
            if n.count >= 3 { context.setFillColor(Color(red: n[0], green: n[1], blue: n[2])) }
        }
        scanner.setHandler(forOperator: "RG") { [self] ops in
            let n = numbers(ops)
            if n.count >= 3 { context.setStrokeColor(Color(red: n[0], green: n[1], blue: n[2])) }
        }
        scanner.setHandler(forOperator: "g") { [self] ops in
            let n = numbers(ops)
            if let g = n.first { context.setFillColor(Color(gray: g)) }
        }
        scanner.setHandler(forOperator: "G") { [self] ops in
            let n = numbers(ops)
            if let g = n.first { context.setStrokeColor(Color(gray: g)) }
        }
        scanner.setHandler(forOperator: "k") { [self] ops in
            let n = numbers(ops)
            if n.count >= 4 { context.setFillColor(Color(cyan: n[0], magenta: n[1], yellow: n[2], black: n[3])) }
        }
        scanner.setHandler(forOperator: "K") { [self] ops in
            let n = numbers(ops)
            if n.count >= 4 { context.setStrokeColor(Color(cyan: n[0], magenta: n[1], yellow: n[2], black: n[3])) }
        }
    }

    private func registerStateOperators(into scanner: inout PDFScanner) {
        scanner.setHandler(forOperator: "cm") { [self] ops in
            let n = numbers(ops)
            if n.count >= 6 {
                context.concatenate(AffineTransform(a: n[0], b: n[1], c: n[2], d: n[3], tx: n[4], ty: n[5]))
            }
        }
        scanner.setHandler(forOperator: "q") { [self] _ in context.saveGState() }
        scanner.setHandler(forOperator: "Q") { [self] _ in context.restoreGState() }
        scanner.setHandler(forOperator: "w") { [self] ops in
            if let width = numbers(ops).first { context.setLineWidth(width) }
        }
        scanner.setHandler(forOperator: "J") { [self] ops in
            if let cap = numbers(ops).first { context.setLineCap(Self.lineCap(Int(cap))) }
        }
        scanner.setHandler(forOperator: "j") { [self] ops in
            if let join = numbers(ops).first { context.setLineJoin(Self.lineJoin(Int(join))) }
        }
        scanner.setHandler(forOperator: "M") { [self] ops in
            if let limit = numbers(ops).first { context.setMiterLimit(limit) }
        }
        scanner.setHandler(forOperator: "d") { [self] ops in
            guard case let .array(elements)? = ops.first else { return }
            let lengths = elements.compactMap(\.numberValue)
            let phase = ops.count >= 2 ? (ops[1].numberValue ?? 0) : 0
            context.setLineDash(phase: phase, lengths: lengths)
        }
    }

    private static func lineCap(_ value: Int) -> LineCap {
        switch value {
        case 1: .round
        case 2: .square
        default: .butt
        }
    }

    private static func lineJoin(_ value: Int) -> LineJoin {
        switch value {
        case 1: .round
        case 2: .bevel
        default: .miter
        }
    }
}
