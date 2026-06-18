//
//  AnyValidation.swift
//  PureDraw
//

/// A type-erased wrapper for validations.
/// This allows a heterogeneous collection of validations to be evaluated during traversal.
/// It filters out subjects that do not match the expected runtime type.
public struct AnyValidation<Document: Sendable>: Sendable {
    private let _apply: @Sendable (Any, [CodingKey], Document) -> [ValidationError]
    /// A human-readable description of the wrapped validation rule.
    public let description: String

    /// Type-erases a typed validation so it can be stored alongside rules for other subject types.
    public init<Subject>(_ validation: Validation<Document, Subject>) {
        description = validation.description
        _apply = { subject, codingPath, document in
            // Crucial: guard against Optional wrapping matching a non-optional Validation
            guard let typedSubject = subject as? Subject, type(of: subject) == type(of: typedSubject) else {
                return []
            }
            return validation.apply(to: typedSubject, at: codingPath, in: document)
        }
    }

    /// Applies the wrapped rule to `subject` if its runtime type matches, returning any failures.
    public func apply(to subject: Any, at codingPath: [CodingKey], in document: Document) -> [ValidationError] {
        _apply(subject, codingPath, document)
    }
}
