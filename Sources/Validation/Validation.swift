//
//  Validation.swift
//  PureDraw
//

/// An atomic validation rule.
/// Validations are declarative and composable. The description states the *correct* state,
/// not the failure state.
public struct Validation<Document: Sendable, Subject: Sendable>: Sendable {
    public let description: String
    private let check: @Sendable (ValidationContext<Document, Subject>) -> [ValidationError]
    private let predicate: @Sendable (ValidationContext<Document, Subject>) -> Bool
    
    /// Creates a validation that can produce multiple errors.
    public init(
        description: String? = nil,
        check: @escaping @Sendable (ValidationContext<Document, Subject>) -> [ValidationError],
        when predicate: @escaping @Sendable (ValidationContext<Document, Subject>) -> Bool = { _ in true }
    ) {
        self.description = description ?? ""
        self.check = check
        self.predicate = predicate
    }
    
    /// Creates a single-error boolean validation.
    /// If `check` returns false, an error is automatically generated using the description.
    public init(
        description: String,
        check: @escaping @Sendable (ValidationContext<Document, Subject>) -> Bool,
        when predicate: @escaping @Sendable (ValidationContext<Document, Subject>) -> Bool = { _ in true }
    ) {
        self.description = description
        self.check = { context in
            if check(context) {
                return []
            } else {
                return [ValidationError(reason: "Failed to satisfy: \(description)", at: context.codingPath)]
            }
        }
        self.predicate = predicate
    }
    
    /// Applies the validation if the predicate is met.
    public func apply(to subject: Subject, at codingPath: [CodingKey], in document: Document) -> [ValidationError] {
        let context = ValidationContext(document: document, subject: subject, codingPath: codingPath)
        guard predicate(context) else { return [] }
        return check(context)
    }
}
