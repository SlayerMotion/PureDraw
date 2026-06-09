//
//  GradientDrawingOptions.swift
//  PureDraw
//

/// Options for drawing gradients, controlling whether drawing extends beyond the start or end locations.
public struct GradientDrawingOptions: OptionSet, Sendable, Equatable {
    public let rawValue: Int
    
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    public static let drawsBeforeStartLocation = GradientDrawingOptions(rawValue: 1 << 0)
    public static let drawsAfterEndLocation = GradientDrawingOptions(rawValue: 1 << 1)
}
