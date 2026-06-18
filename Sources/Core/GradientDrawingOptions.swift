//
//  GradientDrawingOptions.swift
//  PureDraw
//

/// Options for drawing gradients, controlling whether drawing extends beyond the start or end locations.
public struct GradientDrawingOptions: OptionSet, Sendable, Equatable {
    /// The bit mask backing the option set.
    public let rawValue: Int

    /// Creates an option set from its raw bit mask.
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Fill the region before the first stop with the start color instead of leaving it uncovered.
    public static let drawsBeforeStartLocation = GradientDrawingOptions(rawValue: 1 << 0)
    /// Fill the region after the last stop with the end color instead of leaving it uncovered.
    public static let drawsAfterEndLocation = GradientDrawingOptions(rawValue: 1 << 1)
}
