import Core
import Geometry
import Testing

/// Adversarial fuzzing of the SVG path-data mini-language parser (untrusted text input).
/// Two invariants: `parse` must never trap on any string (it returns nil/partial for
/// garbage), and the normal form is idempotent: printing a parse and re-parsing yields the
/// same printed form, so the parser and printer agree on a canonical shape.
struct SVGPathDataFuzzTests {
    private struct SplitMix64: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    @Test func malformedPathsDoNotTrap() {
        let cases: [String] = [
            "", " ", "M", "Z", "z", "m", "M M", "L 1", "1 2 3 4", "M 1,2,3,4",
            "C", "A 1 1 0 0 1", "M1e999 0", "M nan 0", "M inf -inf", "MMMMMMMMMM",
            "🎨 M 0 0", "M0 0L", "M..0 0", "M-.-. 0", "M 0 0 0 0 0 0 0 0",
            "A 0 0 0 0 0 0 0", "Q", "S 1 1", "T", "H", "V", "h v c s",
            String(repeating: "M 0 0 L 1 1 ", count: 5000),
            String(repeating: "c", count: 10000),
            String(repeating: "1 ", count: 50000),
            "M \(Double.greatestFiniteMagnitude) 0",
        ]
        for c in cases {
            _ = SVGPathData.parse(c)
        } // must not trap

        let alphabet = Array("MLHVCSQTAZmlhvcsqtaz0123456789 ,.-+eE")
        for seed in UInt64(1) ... 300 {
            var rng = SplitMix64(state: seed &* 0x100_0000_01B3 &+ 0xCBF2_9CE4_8422_2325)
            let length = Int.random(in: 0 ... 300, using: &rng)
            let s = String((0 ..< length).map { _ in alphabet.randomElement(using: &rng) ?? " " })
            _ = SVGPathData.parse(s) // must not trap
        }
    }

    @Test func parsePrintNormalFormIsIdempotent() {
        // A canonical path-command alphabet that mostly parses, so the round-trip is exercised.
        let commands = ["M", "L", "H", "V", "C", "S", "Q", "T", "Z"]
        for seed in UInt64(1) ... 300 {
            var rng = SplitMix64(state: seed &* 0x1000_0193 &+ 0x811C_9DC5)
            var s = ""
            for _ in 0 ..< Int.random(in: 1 ... 24, using: &rng) {
                let cmd = commands.randomElement(using: &rng) ?? "M"
                s += cmd + " "
                if cmd != "Z" {
                    for _ in 0 ..< Int.random(in: 1 ... 6, using: &rng) {
                        s += "\(Double(Int.random(in: -200 ... 200, using: &rng)) / 4.0) "
                    }
                }
            }
            guard let elements = SVGPathData.parse(s) else { continue }
            let printed = SVGPathData.print(elements)
            guard let reparsed = SVGPathData.parse(printed) else {
                Issue.record("printed normal form failed to reparse: \(printed)")
                continue
            }
            // Printing the reparse must equal the first printed form: parse/print agree on a
            // fixed canonical shape (one round reaches the fixed point).
            #expect(SVGPathData.print(reparsed) == printed, "normal form not idempotent for seed \(seed)")
        }
    }
}
