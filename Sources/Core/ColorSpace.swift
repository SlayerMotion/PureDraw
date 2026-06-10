//
//  ColorSpace.swift
//  PureDraw
//

/// Represents the color space model of a Color.
public enum ColorSpace: String, Equatable, Sendable {
    case deviceRGB = "DeviceRGB"
    case deviceCMYK = "DeviceCMYK"
    case deviceGray = "DeviceGray"
}
