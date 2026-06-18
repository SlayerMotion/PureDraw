//
//  ValidationContext.swift
//  PureDraw
//

/// The read-only bundle every validation check receives.
/// It carries the full document for cross-cutting checks, the specific subject being validated,
/// and the exact location in the document tree.
public struct ValidationContext<Document: Sendable, Subject: Sendable>: Sendable {
    /// The global document root.
    public let document: Document

    /// The specific value being validated.
    public let subject: Subject

    /// The path from the document root to this subject.
    public let codingPath: [CodingKey]

    /// Creates a context from the document root, the value under validation, and its path.
    public init(document: Document, subject: Subject, codingPath: [CodingKey]) {
        self.document = document
        self.subject = subject
        self.codingPath = codingPath
    }
}
