//
//  VariationAxis.swift
//  PureDraw
//

/// One design-variation axis of an OpenType variable font, read from the `fvar` table
/// (PureDraw #77). The coordinate range is in user space (for example weight 100...900),
/// with `defaultValue` the position the un-instanced font renders at.
public struct VariationAxis: Equatable, Sendable {
    /// The four-character axis tag, such as `wght`, `wdth`, `opsz`, `slnt`, or `ital`.
    public let tag: String
    /// The minimum user-space coordinate the axis accepts.
    public let minValue: Double
    /// The user-space coordinate the un-instanced font renders at.
    public let defaultValue: Double
    /// The maximum user-space coordinate the axis accepts.
    public let maxValue: Double
    /// The `name` table ID of the axis's human-readable label.
    public let nameID: Int

    /// Creates a variation axis from its tag, coordinate range, and label name ID.
    public init(tag: String, minValue: Double, defaultValue: Double, maxValue: Double, nameID: Int) {
        self.tag = tag
        self.minValue = minValue
        self.defaultValue = defaultValue
        self.maxValue = maxValue
        self.nameID = nameID
    }
}
