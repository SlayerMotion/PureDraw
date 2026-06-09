//
//  ValidationError.swift
//  PureDraw
//

/// Represents a single validation failure, providing a reason and the exact path
/// in the document where the failure occurred.
public struct ValidationError: Error, CustomStringConvertible, Sendable {
    public let reason: String
    public let codingPath: [CodingKey]
    
    public init(reason: String, at codingPath: [CodingKey]) {
        self.reason = reason
        self.codingPath = codingPath
    }
    
    public var description: String {
        let cleanReason = reason.hasSuffix(".") ? String(reason.dropLast()) : reason
        if codingPath.isEmpty {
            return "\(cleanReason) at root of document"
        } else {
            let pathString = codingPath.map { $0.stringValue }.joined(separator: ".")
            return "\(cleanReason) at path: .\(pathString)"
        }
    }
}
