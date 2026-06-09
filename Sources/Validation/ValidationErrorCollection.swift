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
    
    public var description: String {
        guard !values.isEmpty else { return "No validation errors." }
        let errorDescriptions = values.map { " - \($0.description)" }.joined(separator: "\n")
        return "Validation failed with \(values.count) error(s):\n\(errorDescriptions)"
    }
}
