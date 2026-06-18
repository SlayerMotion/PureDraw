//
//  VariationInstance.swift
//  PureDraw
//

/// A named instance of a variable font: a labelled point in the variation space, read from the
/// `fvar` table (PureDraw #77). `coordinates` gives the user-space value for each axis, in the
/// same order as `Font.variationAxes`.
public struct VariationInstance: Equatable, Sendable {
    /// The `name` table ID of the instance's subfamily label (for example "Bold" or "Condensed").
    public let subfamilyNameID: Int
    /// One user-space coordinate per axis, in axis order.
    public let coordinates: [Double]
    /// The `name` table ID of the instance's PostScript name, when the font supplies one.
    public let postScriptNameID: Int?

    /// Creates a named instance from its subfamily name ID, per-axis coordinates, and optional
    /// PostScript name ID.
    public init(subfamilyNameID: Int, coordinates: [Double], postScriptNameID: Int?) {
        self.subfamilyNameID = subfamilyNameID
        self.coordinates = coordinates
        self.postScriptNameID = postScriptNameID
    }
}
