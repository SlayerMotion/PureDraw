//
//  ValidationErrorCollection.swift
//  PureDraw
//

/// A collection of validation errors accumulated during traversal.
public struct ValidationErrorCollection: Error, CustomStringConvertible, Sendable {
    /// The individual validation failures, in traversal order.
    public let values: [ValidationError]

    /// Creates a collection wrapping the given validation errors.
    public init(values: [ValidationError]) {
        self.values = values
    }

    /// All failure messages, one per line.
    public var localizedDescription: String {
        values.map(\.description).joined(separator: "\n")
    }

    /// All failure messages, one per line.
    public var description: String {
        localizedDescription
    }
}
