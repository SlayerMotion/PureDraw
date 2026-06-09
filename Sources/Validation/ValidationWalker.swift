//
//  ValidationWalker.swift
//  PureDraw
//

/// Recursively traverses a value's properties to run validation rules on any encountered `Validatable` nodes.
struct ValidationWalker<Document: Sendable> {
    let validator: Validator<Document>
    let document: Document
    
    func walk(_ value: Any, at codingPath: [CodingKey]) -> [ValidationError] {
        var errors: [ValidationError] = []
        
        // 1. If the value is Validatable, run the validator and default validations
        if let validatableValue = value as? any Validatable {
            // Apply custom validations from the passed validator
            errors.append(contentsOf: validator.apply(to: validatableValue, at: codingPath, in: document))
            // Apply the type's own default validations
            errors.append(contentsOf: validatableValue.runDefaultValidator(at: codingPath, in: document))
        }
        
        // 2. Recurse into children
        let mirror = Mirror(reflecting: value)
        
        if let array = value as? [Any] {
            for (index, element) in array.enumerated() {
                let elementPath = codingPath + [ValidationCodingKey(index)]
                errors.append(contentsOf: walk(element, at: elementPath))
            }
        } else if let dict = value as? [String: Any] {
            for (key, element) in dict {
                let elementPath = codingPath + [ValidationCodingKey(key)]
                errors.append(contentsOf: walk(element, at: elementPath))
            }
        } else {
            for child in mirror.children {
                guard let label = child.label else { continue }
                let elementPath = codingPath + [ValidationCodingKey(label)]
                errors.append(contentsOf: walk(child.value, at: elementPath))
            }
        }
        
        return errors
    }
}
