//
//  ValidationMachineryTests.swift
//  PureDraw
//

import Testing
import Validation

/// Negative tests for the validation machinery itself (the canon's "machinery has
/// its own negative tests"): the erased wrapper must stay quiet on an optional, a
/// wrong type, and a false predicate, while the matching-type positive control
/// proves the negatives are not vacuous. Plus the error-rendering contract.
struct ValidationMachineryTests {
    private var positiveInt: Validation<Void, Int> {
        .init(description: "Int is positive", check: { $0.subject > 0 })
    }

    @Test func firesOnTheMatchingType() {
        let erased = AnyValidation(positiveInt)
        #expect(erased.apply(to: -1 as Any, at: [], in: ()).count == 1) // fires
        #expect(erased.apply(to: 5 as Any, at: [], in: ()).isEmpty) // passes
    }

    @Test func optionalSubjectYieldsNoErrors() {
        // A T? must not satisfy a Validation<T>: the wrapper guards the erasure.
        let erased = AnyValidation(positiveInt)
        let optional: Int? = -1
        #expect(erased.apply(to: optional as Any, at: [], in: ()).isEmpty)
    }

    @Test func wrongTypeYieldsNoErrors() {
        let erased = AnyValidation(positiveInt)
        #expect(erased.apply(to: "not an int" as Any, at: [], in: ()).isEmpty)
    }

    @Test func falsePredicateYieldsNoErrors() {
        // A conditional rule whose `when` never fires stays silent even on bad input.
        let conditional = Validation<Void, Int>(
            description: "Int is positive",
            check: { $0.subject > 0 },
            when: { _ in false }
        )
        #expect(AnyValidation(conditional).apply(to: -1 as Any, at: [], in: ()).isEmpty)
    }

    @Test func sameValueTwiceYieldsTwoErrors() {
        // The positive control: two occurrences of the same failing value of the same
        // type accumulate two errors, proving the negatives above are not vacuous.
        let erased = AnyValidation(positiveInt)
        var errors: [ValidationError] = []
        errors += erased.apply(to: -1 as Any, at: [], in: ())
        errors += erased.apply(to: -1 as Any, at: [], in: ())
        #expect(errors.count == 2)
    }

    @Test func boolFormRendersFailedToSatisfy() {
        let error = AnyValidation(positiveInt).apply(to: -1 as Any, at: [], in: ()).first
        #expect(error?.reason == "Failed to satisfy: Int is positive")
    }

    @Test func errorRendersRootAndPath() {
        let atRoot = ValidationError(reason: "must be positive.", at: [])
        #expect(String(describing: atRoot) == "must be positive at root of document")
        let atPath = ValidationError(reason: "must be positive", at: [ValidationCodingKey("a"), ValidationCodingKey("b")])
        #expect(String(describing: atPath) == "must be positive at path: .a.b")
    }
}
