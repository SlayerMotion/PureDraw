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
