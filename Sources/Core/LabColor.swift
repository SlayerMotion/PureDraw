//
//  LabColor.swift
//  PureDraw
//

import Foundation

/// A colour in the CIE L*a*b* space, the perceptually near-uniform space behind `CGColorSpaceCreateLab`
/// and colour-difference metrics. `l` is lightness in `0...100`; `a` runs green-to-red and `b`
/// blue-to-yellow, both unbounded in principle. Equal geometric distances in Lab correspond to roughly
/// equal perceived colour differences, which is what makes the CIE76 difference below meaningful.
public struct LabColor: Equatable, Sendable {
    /// Lightness, `0` (black) to `100` (white).
    public let l: Double
    /// Green (negative) to red (positive).
    public let a: Double
    /// Blue (negative) to yellow (positive).
    public let b: Double

    /// Creates a Lab colour from its components.
    public init(l: Double, a: Double, b: Double) {
        self.l = l
        self.a = a
        self.b = b
    }

    /// The CIE76 colour difference (ΔE*ab): the Euclidean distance in Lab. A value near `2.3` is the
    /// just-noticeable difference. This is the original, exact CIE definition; later refinements
    /// (CIE94, CIEDE2000) reweight it but are not required for a perceptual distance.
    public func deltaE76(to other: LabColor) -> Double {
        let dl = l - other.l
        let da = a - other.a
        let db = b - other.b
        return (dl * dl + da * da + db * db).squareRoot()
    }
}
