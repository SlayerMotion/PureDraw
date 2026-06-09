//
//  ValidationErrorCollection.swift
//  PureDraw
//

/// A collection of validation errors accumulated during traversal.
public struct ValidationErrorCollection: Error, CustomStringConvertible, Sendable {
    public let values: [ValidationError]

    public init(values: [ValidationError]) {
        self.values = values
    }

    public var localizedDescription: String {
        values.map(\.description).joined(separator: "\n")
    }

    public var description: String {
        localizedDescription
    }
}
