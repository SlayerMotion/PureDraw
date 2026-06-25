#if canImport(Foundation)
    @testable import Core
    import Foundation
    import Testing

    /// The lookup-indexed GSUB model (`gsubLookupIndices` + `gsubLookup(at:)`)
    /// exposes each lookup whole, with contextual lookups (types 5/6) keeping their
    /// nested references as lookup indices so the shaper can recurse. The proving
    /// case is Noto Nastaliq Urdu, whose required-ligature feature `rlig` carries
    /// its contextual rules in ChainContext formats 1 and 2 (glyph- and class-based)
    /// rather than format 3. The older `chainingSubstitutions` accessor reads only
    /// format 3, so it sees none of these; the new model must surface them.
    @Suite("GSUB lookup-indexed model surfaces format 1/2 contextual rules")
    struct GSUBLookupModelTests {
        private static let nastaliq = "/System/Library/Fonts/NotoNastaliq.ttc"

        @Test func positionalFormsAreMultipleSubstitutions() {
            guard let data = FileManager.default.contents(atPath: Self.nastaliq),
                  let font = try? Font(data: [UInt8](data))
            else {
                return
            }
            let active = font.gsubFeatureIndices(scripts: ["arab"])
            let isol = font.gsubLookupIndices(features: ["isol"], restrictTo: active)
            #expect(!isol.isEmpty, "Nastaliq must select isol lookups")
            // Every isol lookup in this font is a type-2 multiple substitution.
            for index in isol {
                guard let lookup = font.gsubLookup(at: index) else { continue }
                if case let .multiple(map) = lookup.kind {
                    #expect(!map.isEmpty, "isol multiple substitution must not be empty")
                } else {
                    Issue.record("isol lookup \(index) expected .multiple, got \(lookup.kind)")
                }
            }
        }

        @Test func rligContextualRulesAreSurfacedFromFormats1And2() {
            guard let data = FileManager.default.contents(atPath: Self.nastaliq),
                  let font = try? Font(data: [UInt8](data))
            else {
                return
            }
            let active = font.gsubFeatureIndices(scripts: ["arab"])
            let rlig = font.gsubLookupIndices(features: ["rlig"], restrictTo: active)
            #expect(!rlig.isEmpty, "Nastaliq must select rlig lookups")

            var contextRuleCount = 0
            var recordCount = 0
            var nestedTypesSeen: Set<String> = []
            for index in rlig {
                guard let lookup = font.gsubLookup(at: index) else { continue }
                guard case let .context(rules) = lookup.kind else { continue }
                contextRuleCount += rules.count
                for rule in rules {
                    #expect(!rule.input.isEmpty, "a contextual rule must have a non-empty input")
                    for record in rule.records {
                        recordCount += 1
                        // The nested reference resolves to a real lookup; record its
                        // kind so we prove the recursion targets (type 1 and type 6).
                        if let nested = font.gsubLookup(at: record.lookupIndex) {
                            switch nested.kind {
                            case .single: nestedTypesSeen.insert("single")
                            case .context: nestedTypesSeen.insert("context")
                            case .multiple: nestedTypesSeen.insert("multiple")
                            case .ligature: nestedTypesSeen.insert("ligature")
                            default: nestedTypesSeen.insert("other")
                            }
                        }
                    }
                }
            }
            // The format 3-only accessor sees nothing here; the new model must surface
            // the format 1/2 rules. NotoNastaliq carries many.
            #expect(contextRuleCount > 0, "rlig must surface format 1/2 contextual rules, found \(contextRuleCount)")
            #expect(recordCount > 0, "contextual rules must carry nested lookup records, found \(recordCount)")
            #expect(nestedTypesSeen.contains("single"), "rlig nested lookups must include type-1 single, saw \(nestedTypesSeen)")
            #expect(nestedTypesSeen.contains("context"), "rlig nested lookups must include recursive type-6 context, saw \(nestedTypesSeen)")

            // The old accessor, format-3 only, returns no chaining rules for these
            // format 1/2 lookups: this is the gap the new model closes.
            #expect(font.chainingSubstitutions(feature: "rlig", restrictTo: active).isEmpty, "rlig has no format-3 rules; the format-3 accessor must be empty")
        }
    }
#endif
