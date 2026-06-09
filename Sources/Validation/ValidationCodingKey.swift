//
//  ValidationCodingKey.swift
//  PureDraw
//

/// A simple CodingKey implementation for constructing paths during validation.
public struct ValidationCodingKey: CodingKey, Sendable, CustomStringConvertible {
    public var stringValue: String
    public var intValue: Int?
    
    public init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }
    
    public init(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
    
    public init(_ stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }
    
    public init(_ intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
    
    public var description: String {
        return stringValue
    }
}

public extension Array where Element == CodingKey {
    /// Formats the array of coding keys into a string, using dot-notation for keys and brackets for indices.
    var stringValue: String {
        return self.map { key in
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

