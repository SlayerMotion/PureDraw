//
//  RectCorner.swift
//  PureDraw
//

/// The four corners of a rectangle, as an option set, for selectively rounding a
/// rounded rectangle (`Path.addRoundedRect(in:cornerWidth:cornerHeight:corners:)`
/// and `addContinuousRoundedRect(in:cornerRadius:corners:)`). Corners not in the set
/// stay square. Named by which extreme of each axis they sit at, matching the
/// `CACornerMask` convention (`minXMinY` is the top-left in a top-left-origin space).
///
/// Apple-native equivalent (the "regress to Apple frameworks" mapping): selective
/// corner rounding is not in Core Graphics, `CGPath(roundedRect:cornerWidth:cornerHeight:)`
/// rounds all four corners. The native per-corner shapes live one layer up:
/// `UIBezierPath(roundedRect:byRoundingCorners:cornerRadii:)` (UIKit, the direct analogue
/// of this option set), and SwiftUI's `UnevenRoundedRectangle`. So this is a UIKit/SwiftUI
/// equivalent provided at the Core-Graphics layer, not a non-Apple invention.
public struct RectCorner: OptionSet, Sendable, Hashable {
    /// The bit mask backing the option set.
    public let rawValue: Int
    /// Creates a corner set from its raw bit mask.
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// The corner at minimum x and minimum y (top-left in a top-left-origin space).
    public static let minXMinY = RectCorner(rawValue: 1 << 0)
    /// The corner at maximum x and minimum y (top-right).
    public static let maxXMinY = RectCorner(rawValue: 1 << 1)
    /// The corner at minimum x and maximum y (bottom-left).
    public static let minXMaxY = RectCorner(rawValue: 1 << 2)
    /// The corner at maximum x and maximum y (bottom-right).
    public static let maxXMaxY = RectCorner(rawValue: 1 << 3)

    /// All four corners (the default, an ordinary rounded rectangle).
    public static let all: RectCorner = [.minXMinY, .maxXMinY, .minXMaxY, .maxXMaxY]
}
