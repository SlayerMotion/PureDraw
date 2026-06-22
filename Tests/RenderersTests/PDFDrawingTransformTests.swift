//
//  PDFDrawingTransformTests.swift
//  PureDraw
//

import Geometry
import Renderers
import Testing

/// The page drawing transform fits a box into a destination rect, preserving aspect ratio and
/// centering, the `CGPDFPageGetDrawingTransform` rule for an unrotated page. These assert the corner
/// mappings: the box's corners land on the fitted, centered rectangle inside the destination.
struct PDFDrawingTransformTests {
    private func page(_ width: Double, _ height: Double) -> PDFDocument.Page {
        let box = Rect(x: 0, y: 0, width: width, height: height)
        return PDFDocument.Page(mediaBox: box, cropBox: box)
    }

    private func approx(_ a: Point, _ b: Point, tol: Double = 1e-9) -> Bool {
        abs(a.x - b.x) <= tol && abs(a.y - b.y) <= tol
    }

    @Test func identityWhenBoxEqualsDestination() {
        let transform = page(100, 200).drawingTransform(in: Rect(x: 0, y: 0, width: 100, height: 200))
        #expect(approx(Point(x: 0, y: 0).applying(transform), Point(x: 0, y: 0)))
        #expect(approx(Point(x: 100, y: 200).applying(transform), Point(x: 100, y: 200)))
    }

    @Test func uniformScaleWhenAspectMatches() {
        // A 100x200 box into a 200x400 rect scales by 2 with no centering offset.
        let transform = page(100, 200).drawingTransform(in: Rect(x: 0, y: 0, width: 200, height: 400))
        #expect(approx(Point(x: 100, y: 200).applying(transform), Point(x: 200, y: 400)))
        #expect(approx(Point(x: 50, y: 100).applying(transform), Point(x: 100, y: 200)))
    }

    @Test func preservesAspectAndCentersInWiderRect() {
        // A square box into a wide rect: scale to the limiting height, center horizontally.
        let transform = page(100, 100).drawingTransform(in: Rect(x: 0, y: 0, width: 300, height: 100))
        // Scale = min(300/100, 100/100) = 1; centered: x offset = (300 - 100)/2 = 100.
        #expect(approx(Point(x: 0, y: 0).applying(transform), Point(x: 100, y: 0)))
        #expect(approx(Point(x: 100, y: 100).applying(transform), Point(x: 200, y: 100)))
    }

    @Test func centersInTallerRect() {
        // A square box into a tall rect: scale to the limiting width, center vertically.
        let transform = page(100, 100).drawingTransform(in: Rect(x: 0, y: 0, width: 100, height: 300))
        #expect(approx(Point(x: 0, y: 0).applying(transform), Point(x: 0, y: 100)))
        #expect(approx(Point(x: 100, y: 100).applying(transform), Point(x: 100, y: 200)))
    }

    @Test func honorsDestinationOrigin() {
        let transform = page(100, 100).drawingTransform(in: Rect(x: 10, y: 20, width: 100, height: 100))
        #expect(approx(Point(x: 0, y: 0).applying(transform), Point(x: 10, y: 20)))
        #expect(approx(Point(x: 100, y: 100).applying(transform), Point(x: 110, y: 120)))
    }
}
