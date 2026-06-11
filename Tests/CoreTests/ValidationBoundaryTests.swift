//
//  ValidationBoundaryTests.swift
//  PureDraw
//

@testable import Core
import Geometry
import Testing
import Validation

/// A failing + near-miss succeeding pair for every value-type rule, each applied in
/// isolation. The succeeding fixture sits at the exact boundary the rule almost
/// trips. (`imageIsValid`, `drawLayerHasValidDimensions`,
/// `transparencyLayersAreBalanced`, and the Font rule have both directions in
/// `ValidationCompletenessTests`.)
struct ValidationBoundaryTests {
    private func fails<S>(_ rule: Validation<Void, S>, _ subject: S) -> Bool {
        !rule.apply(to: subject, at: [], in: ()).isEmpty
    }

    private func passes<S>(_ rule: Validation<Void, S>, _ subject: S) -> Bool {
        rule.apply(to: subject, at: [], in: ()).isEmpty
    }

    private var gradient: Gradient {
        Gradient(stops: [GradientStop(color: .black, location: 0), GradientStop(color: .white, location: 1)])
    }

    @Test func colorBoundary() {
        #expect(passes(.colorIsValid, Color(red: 1, green: 1, blue: 1, alpha: 1)))
        #expect(fails(.colorIsValid, Color(red: 1.0001, green: 0, blue: 0, alpha: 1)))
    }

    @Test func pointBoundary() {
        #expect(passes(.pointIsFinite, Point(x: 0, y: 0)))
        #expect(fails(.pointIsFinite, Point(x: .infinity, y: 0)))
    }

    @Test func rectDimensionsBoundary() {
        // Zero is the boundary (a degenerate rect is tolerated, like CG); negative fails.
        #expect(passes(.rectHasValidDimensions, Rect(x: 0, y: 0, width: 0, height: 1)))
        #expect(fails(.rectHasValidDimensions, Rect(x: 0, y: 0, width: -1, height: 1)))
    }

    @Test func rectFiniteBoundary() {
        #expect(passes(.rectIsFinite, Rect(x: 0, y: 0, width: 1, height: 1)))
        #expect(fails(.rectIsFinite, Rect(x: 0, y: 0, width: .nan, height: 1)))
    }

    @Test func affineReversibleBoundary() {
        #expect(passes(.matrixIsReversible, .identity))
        #expect(fails(.matrixIsReversible, AffineTransform(a: 0, b: 0, c: 0, d: 0, tx: 0, ty: 0)))
    }

    @Test func affineFiniteBoundary() {
        #expect(passes(.matrixIsFinite, .identity))
        #expect(fails(.matrixIsFinite, AffineTransform(a: .nan, b: 0, c: 0, d: 1, tx: 0, ty: 0)))
    }

    @Test func projectiveReversibleBoundary() {
        #expect(passes(.projectiveMatrixIsReversible, .identity))
        #expect(fails(.projectiveMatrixIsReversible, ProjectiveTransform(AffineTransform(a: 0, b: 0, c: 0, d: 0, tx: 0, ty: 0))))
    }

    @Test func projectiveFiniteBoundary() {
        #expect(passes(.projectiveMatrixIsFinite, .identity))
        #expect(fails(.projectiveMatrixIsFinite, ProjectiveTransform(AffineTransform(a: .nan, b: 0, c: 0, d: 1, tx: 0, ty: 0))))
    }

    @Test func gradientStopCountBoundary() {
        #expect(passes(.gradientIsValid, gradient)) // two stops, the minimum
        #expect(fails(.gradientIsValid, Gradient(stops: [GradientStop(color: .black, location: 0)])))
    }

    @Test func gradientStopLocationBoundary() {
        #expect(passes(.gradientStopIsValid, GradientStop(color: .black, location: 1)))
        #expect(fails(.gradientStopIsValid, GradientStop(color: .black, location: 1.0001)))
    }

    @Test func shadowBlurBoundary() {
        #expect(passes(.shadowIsValid, Shadow(offset: Point(x: 0, y: 0), blur: 0, color: .black)))
        #expect(fails(.shadowIsValid, Shadow(offset: Point(x: 0, y: 0), blur: -0.0001, color: .black)))
    }

    @Test func crumpleDeformerBoundary() {
        // Any finite values pass (a zero/negative radius is tolerated); a non-finite
        // field fails.
        #expect(passes(.crumpleDeformerValuesAreFinite, CrumpleDeformer(center: Point(x: 0, y: 0), radius: 0)))
        #expect(fails(.crumpleDeformerValuesAreFinite, CrumpleDeformer(center: Point(x: 0, y: 0), radius: .nan)))
    }

    @Test func graphicStateLineWidthBoundary() {
        #expect(passes(.graphicStateIsValid, GraphicState(lineWidth: 0)))
        #expect(fails(.graphicStateIsValid, GraphicState(lineWidth: -1)))
    }

    @Test func drawOperationPathBoundary() {
        var nonEmpty = Path()
        nonEmpty.addRect(Rect(x: 0, y: 0, width: 1, height: 1))
        #expect(passes(.drawOperationPathIsNotEmpty, DrawOperation(kind: .fill(nonEmpty, rule: .winding), state: GraphicState())))
        #expect(fails(.drawOperationPathIsNotEmpty, DrawOperation(kind: .fill(Path(), rule: .winding), state: GraphicState())))
    }

    @Test func linearGradientPointsBoundary() {
        let distinct = DrawOperation(
            kind: .drawLinearGradient(gradient, start: Point(x: 0, y: 0), end: Point(x: 1, y: 1), options: []),
            state: GraphicState()
        )
        let coincident = DrawOperation(
            kind: .drawLinearGradient(gradient, start: Point(x: 0, y: 0), end: Point(x: 0, y: 0), options: []),
            state: GraphicState()
        )
        #expect(passes(.linearGradientPointsAreDistinct, distinct))
        #expect(fails(.linearGradientPointsAreDistinct, coincident))
    }

    @Test func radialGradientRadiusBoundary() {
        let valid = DrawOperation(
            kind: .drawRadialGradient(gradient, startCenter: Point(x: 0, y: 0), startRadius: 0, endCenter: Point(x: 0, y: 0), endRadius: 1, options: []),
            state: GraphicState()
        )
        let negative = DrawOperation(
            kind: .drawRadialGradient(gradient, startCenter: Point(x: 0, y: 0), startRadius: -1, endCenter: Point(x: 0, y: 0), endRadius: 1, options: []),
            state: GraphicState()
        )
        #expect(passes(.radialGradientIsValid, valid))
        #expect(fails(.radialGradientIsValid, negative))
    }
}
