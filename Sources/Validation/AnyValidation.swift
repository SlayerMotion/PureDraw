//
//  AnyValidation.swift
//  PureDraw
//

/// A type-erased wrapper for validations.
/// This allows a heterogeneous collection of validations to be evaluated during traversal.
/// It filters out subjects that do not match the expected runtime type.
public struct AnyValidation<Document: Sendable>: Sendable {
    private let _apply: @Sendable (Any, [CodingKey], Document) -> [ValidationError]
    public let description: String
    
    public init<Subject>(_ validation: Validation<Document, Subject>) {
        self.description = validation.description
        self._apply = { subject, codingPath, document in
            // Crucial: guard against Optional wrapping matching a non-optional Validation
            guard let typedSubject = subject as? Subject, type(of: subject) == type(of: typedSubject) else {
                return []
            }
            return validation.apply(to: typedSubject, at: codingPath, in: document)
        }
    }
    
    public func apply(to subject: Any, at codingPath: [CodingKey], in document: Document) -> [ValidationError] {
        return _apply(subject, codingPath, document)
    }
}
