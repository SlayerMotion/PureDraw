//
//  ICCProfile.swift
//  PureDraw
//

/// A parsed ICC colour profile, the matrix-RGB subset that covers the common display profiles (sRGB,
/// Display P3, Adobe RGB, Rec. 709/2020): the header essentials plus the RGB-to-XYZ matrix columns and
/// the per-channel tone curves. LUT-based (`A2B`/`B2A`) and non-RGB profiles are read for their header
/// but carry no matrix.
///
/// The matrix columns are the profile connection space (PCS) values that the channels map to, expressed
/// relative to the PCS white (D50 for an XYZ-PCS profile). For a well-formed matrix profile the three
/// columns sum to the media white point, which is the spec invariant the reader is checked against.
public struct ICCProfile: Equatable, Sendable {
    /// The device/profile class signature, e.g. `mntr` (display) or `prtr` (printer).
    public let deviceClass: String
    /// The data colour space signature, e.g. `RGB ` or `GRAY`.
    public let colorSpace: String
    /// The profile connection space signature, `XYZ ` or `Lab `.
    public let connectionSpace: String
    /// The default rendering intent (0 perceptual, 1 relative colorimetric, 2 saturation, 3 absolute).
    public let renderingIntent: Int
    /// The media white point (the `wtpt` tag).
    public let whitePoint: XYZColor

    /// The RGB-to-XYZ matrix columns (the `rXYZ`/`gXYZ`/`bXYZ` tags), or `nil` for a non-matrix profile.
    public let redColumn: XYZColor?
    public let greenColumn: XYZColor?
    public let blueColumn: XYZColor?

    /// The per-channel tone curves (`rTRC`/`gTRC`/`bTRC`), mapping device values to linear light.
    public let redCurve: ICCToneCurve?
    public let greenCurve: ICCToneCurve?
    public let blueCurve: ICCToneCurve?

    public init(
        deviceClass: String,
        colorSpace: String,
        connectionSpace: String,
        renderingIntent: Int,
        whitePoint: XYZColor,
        redColumn: XYZColor? = nil,
        greenColumn: XYZColor? = nil,
        blueColumn: XYZColor? = nil,
        redCurve: ICCToneCurve? = nil,
        greenCurve: ICCToneCurve? = nil,
        blueCurve: ICCToneCurve? = nil
    ) {
        self.deviceClass = deviceClass
        self.colorSpace = colorSpace
        self.connectionSpace = connectionSpace
        self.renderingIntent = renderingIntent
        self.whitePoint = whitePoint
        self.redColumn = redColumn
        self.greenColumn = greenColumn
        self.blueColumn = blueColumn
        self.redCurve = redCurve
        self.greenCurve = greenCurve
        self.blueCurve = blueCurve
    }

    /// Whether the profile carries a full RGB-to-XYZ matrix with tone curves.
    public var isMatrixRGB: Bool {
        redColumn != nil && greenColumn != nil && blueColumn != nil
    }

    /// Converts a device RGB colour (each channel `0...1`) to PCS XYZ: apply each tone curve to its
    /// channel (device to linear), then the matrix columns. Returns `nil` for a non-matrix profile.
    public func toConnectionXYZ(red: Double, green: Double, blue: Double) -> XYZColor? {
        guard let redColumn, let greenColumn, let blueColumn else { return nil }
        let r = (redCurve ?? .identity).value(at: red)
        let g = (greenCurve ?? .identity).value(at: green)
        let b = (blueCurve ?? .identity).value(at: blue)
        return XYZColor(
            x: redColumn.x * r + greenColumn.x * g + blueColumn.x * b,
            y: redColumn.y * r + greenColumn.y * g + blueColumn.y * b,
            z: redColumn.z * r + greenColumn.z * g + blueColumn.z * b
        )
    }
}
