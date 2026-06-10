//
//  RenderingIntent.swift
//  PureDraw
//

/// Represents the rendering intent determines how colors are mapped between color spaces.
public enum RenderingIntent: String, Equatable, Sendable, Codable, CaseIterable {
    case `default`
    case absoluteColorimetric
    case relativeColorimetric
    case perceptual
    case saturation
}
