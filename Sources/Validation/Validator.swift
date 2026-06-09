//
//  Validator.swift
//  PureDraw
//

/// A coordinator that holds an active set of validation rules.
public struct Validator<Document: Sendable>: Sendable {
    private var validations: [AnyValidation<Document>]
    
    public init(validations: [AnyValidation<Document>] = []) {
        self.validations = validations
    }
    
    /// A validator with no rules attached.
    public static var blank: Validator<Document> {
        return Validator()
    }
    
    /// Adds a pre-constructed validation to this validator.
    public func validating<Subject>(_ validation: Validation<Document, Subject>) -> Validator<Document> {
        var copy = self
        copy.validations.append(AnyValidation(validation))
        return copy
    }
    
    /// Adds a single-error boolean validation to this validator.
    public func validating<Subject>(
        _ description: String,
        check: @escaping @Sendable (ValidationContext<Document, Subject>) -> Bool,
        when predicate: @escaping @Sendable (ValidationContext<Document, Subject>) -> Bool = { _ in true }
    ) -> Validator<Document> {
        return validating(Validation(description: description, check: check, when: predicate))
    }
    
    /// Returns the descriptions of all active rules in this validator.
    public var validationDescriptions: [String] {
        return validations.map { $0.description }
    }
    
    /// Applies all relevant validations to the given subject.
    public func apply(to subject: Any, at codingPath: [CodingKey], in document: Document) -> [ValidationError] {
        return validations.flatMap { $0.apply(to: subject, at: codingPath, in: document) }
    }
}
