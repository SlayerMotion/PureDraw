//
//  ValidationWalker.swift
//  PureDraw
//

/// Recursively traverses a value's properties to run validation rules on any encountered `Validatable` nodes.
struct ValidationWalker<Document: Sendable> {
    let validator: Validator<Document>
    let document: Document

    func walk(_ value: Any, at codingPath: [CodingKey]) -> [ValidationError] {
        var visited = Set<ObjectIdentifier>()
        return walk(value, at: codingPath, visited: &visited)
    }

    private func walk(_ value: Any, at codingPath: [CodingKey], visited: inout Set<ObjectIdentifier>) -> [ValidationError] {
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            if let firstChild = mirror.children.first {
                return walk(firstChild.value, at: codingPath, visited: &visited)
            }
            return []
        }

        // Reference types can form cycles (e.g. a layer drawn into itself);
        // traverse each instance once.
        if mirror.displayStyle == .class {
            let identifier = ObjectIdentifier(value as AnyObject)
            if visited.contains(identifier) {
                return []
            }
            visited.insert(identifier)
        }

        var errors: [ValidationError] = []

        // 1. If the value is Validatable, run the validator and default validations
        if let validatableValue = value as? any Validatable {
            // Apply custom validations from the passed validator
            errors.append(contentsOf: validator.apply(to: validatableValue, at: codingPath, in: document))
            // Apply the type's own default validations
            errors.append(contentsOf: validatableValue.runDefaultValidator(at: codingPath, in: document))
        }

        // 2. Recurse into children

        if let array = value as? [Any] {
            for (index, element) in array.enumerated() {
                let elementPath = codingPath + [ValidationCodingKey(index)]
                errors.append(contentsOf: walk(element, at: elementPath, visited: &visited))
            }
        } else if let dict = value as? [String: Any] {
            for (key, element) in dict {
                let elementPath = codingPath + [ValidationCodingKey(key)]
                errors.append(contentsOf: walk(element, at: elementPath, visited: &visited))
            }
        } else {
            for child in mirror.children {
                guard let label = child.label else { continue }
                let elementPath = codingPath + [ValidationCodingKey(label)]
                errors.append(contentsOf: walk(child.value, at: elementPath, visited: &visited))
            }
        }

        return errors
    }
}
