//
//  ErgonomicAPITests.swift
//  PureDraw
//

@testable import Core
import Geometry
import Testing

/// The convenience APIs that round out the Core Graphics surface: coordinate
/// conversion between user and device space, rectangle clipping, and clearing.
/// These assert the defining invariants rather than pixels: conversion is the
/// CTM and its exact inverse, a clip only narrows, and a clear records a
/// Porter-Duff clear.
struct ErgonomicAPITests {
    private func approxEqual(_ a: Point, _ b: Point, tol: Double = 1e-9) -> Bool {
        abs(a.x - b.x) <= tol && abs(a.y - b.y) <= tol
    }

    // MARK: Coordinate conversion

    @Test func deviceSpaceAppliesTheCTM() {
        var context = GraphicsContext()
        context.translate(by: 10, 20)
        context.scale(by: 2, 3)
        let device = context.convertToDeviceSpace(Point(x: 4, y: 5))
        // Each op prepends to the local frame, so the point is translated then
        // scaled: (4+10, 5+20) scaled by (2,3) = (28, 75).
        #expect(approxEqual(device, Point(x: 28, y: 75)))
    }

    @Test func userSpaceInvertsDeviceSpace() {
        var context = GraphicsContext()
        context.translate(by: 7, -3)
        context.rotate(by: 0.6)
        context.scale(by: 1.5, 0.8)
        // A non-trivial CTM: the round trip must return the original point.
        for point in [Point(x: 0, y: 0), Point(x: 12, y: -5), Point(x: -8, y: 9)] {
            let roundTrip = context.convertToUserSpace(context.convertToDeviceSpace(point))
            #expect(approxEqual(roundTrip, point, tol: 1e-7))
        }
    }

    @Test func rectConversionIsTheCornerBoundingBox() {
        var context = GraphicsContext()
        context.rotate(by: .pi / 2) // a quarter turn swaps the extents
        let rect = context.convertToDeviceSpace(Rect(x: 0, y: 0, width: 4, height: 2))
        // A 4x2 rectangle rotated a quarter turn has a 2x4 axis-aligned bounding
        // box (the sign of the rotation only moves the origin, not the extents).
        #expect(abs(rect.width - 2) <= 1e-9)
        #expect(abs(rect.height - 4) <= 1e-9)
        // One corner stays at the origin; the box is offset onto one axis.
        #expect(abs(rect.minX) <= 1e-9 || abs(rect.minY) <= 1e-9)
    }

    @Test func conversionUsesTheCurrentStateNotADefault() {
        var context = GraphicsContext()
        let identityResult = context.convertToDeviceSpace(Point(x: 3, y: 4))
        #expect(approxEqual(identityResult, Point(x: 3, y: 4)))
        context.translate(by: 100, 0)
        #expect(approxEqual(context.convertToDeviceSpace(Point(x: 3, y: 4)), Point(x: 103, y: 4)))
    }

    // MARK: Rectangle clipping

    @Test func clipToRectPushesOneClip() {
        var context = GraphicsContext()
        context.clip(to: Rect(x: 0, y: 0, width: 10, height: 10))
        #expect(context.currentState.clipPaths.count == 1)
        context.clip(to: Rect(x: 2, y: 2, width: 4, height: 4))
        // A second clip narrows: the stack is the intersection, kept as two paths.
        #expect(context.currentState.clipPaths.count == 2)
    }

    @Test func clipToRectsUnionsIntoOneEntry() {
        var context = GraphicsContext()
        context.clip(to: [Rect(x: 0, y: 0, width: 4, height: 4), Rect(x: 8, y: 8, width: 4, height: 4)])
        // The union of the rectangles is a single clip-stack entry.
        #expect(context.currentState.clipPaths.count == 1)
    }

    @Test func clipToNoRectsClipsEverythingAway() {
        var context = GraphicsContext()
        context.clip(to: [])
        #expect(context.currentState.clipPaths.count == 1)
        // The pushed region is degenerate (zero area): nothing remains drawable.
        let box = context.currentState.clipPaths[0].path.boundingBox
        #expect(box.isEmpty || box.isNull)
    }

    // MARK: Clear

    @Test func clearRecordsAClearBlendedFill() {
        var context = GraphicsContext()
        context.setFillColor(Color(red: 1, green: 0, blue: 0, alpha: 1))
        context.setAlpha(0.5)
        context.clear(Rect(x: 0, y: 0, width: 5, height: 5))
        #expect(context.commands.count == 1)
        let op = context.commands[0]
        guard case .fill = op.kind else {
            Issue.record("clear should record a fill")
            return
        }
        // Clear is unconditional: blend is .clear and global alpha is forced to 1
        // so it fully zeroes the region regardless of the current fill state.
        #expect(op.state.blendMode == .clear)
        #expect(op.state.alpha == 1)
    }
}
