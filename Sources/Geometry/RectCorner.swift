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
    public let rawValue: Int
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let minXMinY = RectCorner(rawValue: 1 << 0)
    public static let maxXMinY = RectCorner(rawValue: 1 << 1)
    public static let minXMaxY = RectCorner(rawValue: 1 << 2)
    public static let maxXMaxY = RectCorner(rawValue: 1 << 3)

    /// All four corners (the default, an ordinary rounded rectangle).
    public static let all: RectCorner = [.minXMinY, .maxXMinY, .minXMaxY, .maxXMaxY]
}
