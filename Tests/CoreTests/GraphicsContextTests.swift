//
//  GraphicsContextTests.swift
//  PureDraw
//

@testable import Core
import Foundation
import Geometry
import Testing
import Validation

struct GraphicsContextTests {
    @Test func colorInitializationAndDefaults() {
        let black = Color.black
        #expect(black.red == 0.0)
        #expect(black.green == 0.0)
        #expect(black.blue == 0.0)
        #expect(black.alpha == 1.0)

        let custom = Color(red: 0.5, green: 0.2, blue: 0.8, alpha: 0.5)
        #expect(custom.red == 0.5)
        #expect(custom.green == 0.2)
        #expect(custom.blue == 0.8)
        #expect(custom.alpha == 0.5)
    }

    @Test func contextStateSavingAndRestoring() {
        var context = GraphicsContext()
        #expect(context.currentState.lineWidth == 1.0)
        #expect(context.currentState.strokeColor == Color.black)

        // Modify state
        context.setLineWidth(5.0)
        context.setStrokeColor(Color(red: 1, green: 0, blue: 0))
        #expect(context.currentState.lineWidth == 5.0)
        #expect(context.currentState.strokeColor.red == 1.0)

        // Save state
        context.saveGState()

        // Modify state again
        context.setLineWidth(10.0)
        context.setStrokeColor(Color(red: 0, green: 1, blue: 0))
        #expect(context.currentState.lineWidth == 10.0)
        #expect(context.currentState.strokeColor.green == 1.0)

        // Restore state
        context.restoreGState()
        #expect(context.currentState.lineWidth == 5.0)
        #expect(context.currentState.strokeColor.red == 1.0)
        #expect(context.currentState.strokeColor.green == 0.0)
    }

    @Test func contextTransformations() {
        var context = GraphicsContext()
        #expect(context.currentState.transform == .identity)

        context.translate(by: 10, 20)
        #expect(context.currentState.transform.tx == 10)
        #expect(context.currentState.transform.ty == 20)

        context.scale(by: 2, 3)
        // Concatenated transform: translation then scale
        // A point (1,1) is translated by (10,20) to (11,21), and then scaled by (2,3) to (22, 63).
        let pt = Point(x: 1, y: 1).applying(context.currentState.transform)
        #expect(pt.x == 22)
        #expect(pt.y == 63)
    }

    @Test func pathConstructionAndDrawingActions() {
        var context = GraphicsContext()
        #expect(context.commands.isEmpty)

        // Add a line segment
        context.move(to: Point(x: 0, y: 0))
        context.addLine(to: Point(x: 100, y: 100))
        #expect(context.currentPath.elements.count == 2)

        // Stroke the path
        context.strokePath()
        #expect(context.currentPath.isEmpty)
        #expect(context.commands.count == 1)

        let op = context.commands[0]
        if case let .stroke(path) = op.kind {
            #expect(path.elements.count == 2)
        } else {
            Issue.record("Expected .stroke command")
        }
        #expect(op.state.lineWidth == 1.0)
    }

    @Test func rectAndPathOperations() {
        var context = GraphicsContext()
        let rect = Rect(x: 10, y: 20, width: 200, height: 100)
        context.addRect(rect)

        // A rect contains move, line, line, line, close = 5 elements
        #expect(context.currentPath.elements.count == 5)

        context.fillPath(using: .evenOdd)
        #expect(context.currentPath.isEmpty)
        #expect(context.commands.count == 1)

        let op = context.commands[0]
        if case let .fill(path, rule) = op.kind {
            #expect(path.elements.count == 5)
            #expect(rule == .evenOdd)
        } else {
            Issue.record("Expected .fill command")
        }
    }

    @Test func clippingAccumulation() {
        var context = GraphicsContext()
        #expect(context.currentState.clipPath == nil)

        // Clip 1
        context.move(to: Point(x: 0, y: 0))
        context.addLine(to: Point(x: 50, y: 50))
        context.clip()

        #expect(context.currentState.clipPath != nil)
        #expect(context.currentState.clipPath?.elements.count == 2)

        // Clip 2
        context.move(to: Point(x: 10, y: 10))
        context.addLine(to: Point(x: 20, y: 20))
        context.clip()

        // clipping paths accumulate by adding elements together to form intersection / compound path
        #expect(context.currentState.clipPath?.elements.count == 4)
    }

    @Test func colorValidationRules() {
        let validColor = Color.black
        let invalidColor = Color(red: 1.5, green: -0.1, blue: 0.5)

        let validResult = Validation<Void, Color>.colorIsValid.apply(to: validColor, at: [], in: ())
        #expect(validResult.isEmpty)

        let invalidResult = Validation<Void, Color>.colorIsValid.apply(to: invalidColor, at: [], in: ())
        #expect(invalidResult.count == 1)
    }

    @Test func graphicStateValidationRules() {
        // Valid state
        let validState = GraphicState()
        let validResult = Validation<Void, GraphicState>.graphicStateIsValid.apply(to: validState, at: [], in: ())
        #expect(validResult.isEmpty)

        // Invalid state (negative line width and invalid alpha)
        let invalidState = GraphicState(lineWidth: -2.0, alpha: 1.5)
        let invalidResult = Validation<Void, GraphicState>.graphicStateIsValid.apply(to: invalidState, at: [], in: ())
        #expect(invalidResult.count == 2)

        #expect(invalidResult.contains { $0.reason == "lineWidth cannot be negative" })
        #expect(invalidResult.contains { $0.reason == "alpha must be between 0.0 and 1.0" })
    }

    @Test func flatnessAndLineProperties() {
        var context = GraphicsContext()
        #expect(context.currentState.flatness == 0.6)

        context.setFlatness(0.8)
        #expect(context.currentState.flatness == 0.8)

        // Invalid state (negative flatness)
        let invalidState = GraphicState(flatness: -0.1)
        let invalidResult = Validation<Void, GraphicState>.graphicStateIsValid.apply(to: invalidState, at: [], in: ())
        #expect(invalidResult.contains { $0.reason == "flatness cannot be negative" })
    }

    @Test func contextAddLinesAndStrokeLineSegments() {
        var context = GraphicsContext()
        let points = [Point(x: 10, y: 10), Point(x: 20, y: 20), Point(x: 30, y: 10), Point(x: 40, y: 20)]

        // 1. Test addLines(between:)
        context.addLines(between: points)
        #expect(context.currentPath.elements.count == 4)

        context.strokePath()
        #expect(context.commands.count == 1)
        #expect(context.currentPath.isEmpty)

        // 2. Test strokeLineSegments(between:)
        context.strokeLineSegments(between: points)
        #expect(context.commands.count == 2)
        // Verify segments path was created correctly with 2 segments (4 elements: move, line, move, line)
        if case let .stroke(segmentsPath) = context.commands.last?.kind {
            #expect(segmentsPath.elements.count == 4)
            if case let .move(p1) = segmentsPath.elements[0] {
                #expect(p1 == Point(x: 10, y: 10))
            }
            if case let .line(p2) = segmentsPath.elements[1] {
                #expect(p2 == Point(x: 20, y: 20))
            }
            if case let .move(p3) = segmentsPath.elements[2] {
                #expect(p3 == Point(x: 30, y: 10))
            }
            if case let .line(p4) = segmentsPath.elements[3] {
                #expect(p4 == Point(x: 40, y: 20))
            }
        } else {
            Issue.record("Expected a stroke command for line segments")
        }
    }
}
