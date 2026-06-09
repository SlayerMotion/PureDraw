//
//  Validatable.swift
//  PureDraw
//

/// A protocol for types that can be traversed and validated.
public protocol Validatable: Sendable {
    /// The default validator for this type, containing standard checks.
    static var defaultValidator: Validator<Self> { get }

    /// Internal helper to dynamically evaluate default validations during traversal.
    func runDefaultValidator(at codingPath: [CodingKey], in document: Any) -> [ValidationError]
}

public extension Validatable {
    static var defaultValidator: Validator<Self> {
        .blank
    }

    func runDefaultValidator(at codingPath: [CodingKey], in document: Any) -> [ValidationError] {
        let doc = (document as? Self) ?? self
        return Self.defaultValidator.apply(to: self, at: codingPath, in: doc)
    }

    /// Validates the object and all of its nested children using the provided validator.
    /// Throws a `ValidationErrorCollection` if any validations fail.
    func validate(using validator: Validator<Self> = .blank) throws {
        let walker = ValidationWalker(validator: validator, document: self)
        let errors = walker.walk(self, at: [])
        guard errors.isEmpty else {
            throw ValidationErrorCollection(values: errors)
        }
    }
}
