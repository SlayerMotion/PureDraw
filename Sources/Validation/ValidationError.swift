//
//  ValidationError.swift
//  PureDraw
//

/// Represents a single validation failure, providing a reason and the exact path
/// in the document where the failure occurred.
public struct ValidationError: Error, CustomStringConvertible, Sendable {
    /// A human-readable explanation of why validation failed.
    public let reason: String
    /// The path to the value that failed, from the document root.
    public let codingPath: [CodingKey]

    /// Creates a validation error from a reason and the path where it occurred.
    public init(reason: String, at codingPath: [CodingKey]) {
        self.reason = reason
        self.codingPath = codingPath
    }

    /// The coding path rendered as a dotted string.
    public var codingPathString: String {
        codingPath.stringValue
    }

    /// A message combining the reason and the path where the failure occurred.
    public var description: String {
        let cleanReason = reason.hasSuffix(".") ? String(reason.dropLast()) : reason
        guard !codingPath.isEmpty else {
            return "\(cleanReason) at root of document"
        }
        return "\(cleanReason) at path: \(codingPath.stringValue)"
    }
}
