//
//  Validator.swift
//  PureDraw
//

/// A coordinator that holds an active set of validation rules.
public struct Validator<Document: Sendable>: Sendable {
    private var validations: [AnyValidation<Document>]

    /// Creates a validator holding the given rules (empty by default; add rules with `validating`).
    public init(validations: [AnyValidation<Document>] = []) {
        self.validations = validations
    }

    /// A validator with no rules attached.
    public static var blank: Validator<Document> {
        Validator()
    }

    /// Adds a pre-constructed validation to this validator.
    public func validating(_ validation: Validation<Document, some Any>) -> Validator<Document> {
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
        validating(Validation(description: description, check: check, when: predicate))
    }

    /// Adds a validation closure that returns multiple validation errors.
    public func validating<Subject>(
        _ validate: @escaping @Sendable (ValidationContext<Document, Subject>) -> [ValidationError]
    ) -> Validator<Document> {
        validating(Validation(check: validate, when: { _ in true }))
    }

    /// Adds a validation closure and predicate that returns multiple validation errors.
    public func validating<Subject>(
        _ validate: @escaping @Sendable (ValidationContext<Document, Subject>) -> [ValidationError],
        when predicate: @escaping @Sendable (ValidationContext<Document, Subject>) -> Bool
    ) -> Validator<Document> {
        validating(Validation(check: validate, when: predicate))
    }

    /// Returns the descriptions of all active rules in this validator.
    public var validationDescriptions: [String] {
        validations.map(\.description)
    }

    /// Applies all relevant validations to the given subject.
    public func apply(to subject: Any, at codingPath: [CodingKey], in document: Document) -> [ValidationError] {
        validations.flatMap { $0.apply(to: subject, at: codingPath, in: document) }
    }
}
