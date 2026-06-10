//
//  InterpolationQuality.swift
//  PureDraw
//

/// Represents the level of interpolation quality to use for image scaling/rendering.
public enum InterpolationQuality: String, Equatable, Sendable, Codable, CaseIterable {
    case `default`
    case none
    case low
    case medium
    case high
}
