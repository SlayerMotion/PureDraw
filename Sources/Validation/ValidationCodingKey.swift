//
//  ValidationCodingKey.swift
//  PureDraw
//

/// A simple CodingKey implementation for constructing paths during validation.
public struct ValidationCodingKey: CodingKey, Sendable, CustomStringConvertible {
    /// The key's string form (a property name).
    public var stringValue: String
    /// The key's integer form (a collection index), when it represents one.
    public var intValue: Int?

    /// Creates a key from a property name.
    public init(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    /// Creates a key from a collection index.
    public init(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }

    /// Creates a key from a property name.
    public init(_ stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    /// Creates a key from a collection index.
    public init(_ intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }

    /// The key's string value.
    public var description: String {
        stringValue
    }
}

public extension [CodingKey] {
    /// Formats the array of coding keys into a string, using dot-notation for keys and brackets for indices.
    var stringValue: String {
        map { key in
            if let intValue = key.intValue {
                return "[\(intValue)]"
            }
            let stringVal = key.stringValue
            if stringVal.contains("/") {
                return "['\(stringVal)']"
            }
            return ".\(stringVal)"
        }.joined()
    }
}
