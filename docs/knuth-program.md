# The Knuth Program for the Pure\* Core

A roadmap to make the core Knuth-grade. The four workstreams are not a menu,
they are a dependency chain, and the order is the method:

> **Define correctness, make it executable, prove the key property, then write
> the literature on the finished thing.**

You do not write the book on code that is still moving. This is PureDraw-centric
(PureDraw is the dependency-free core and where the work starts), with the
cross-package pieces noted and tracked in their own repositories.

Tracking epic: [SlayerMotion/PureDraw#127](https://github.com/SlayerMotion/PureDraw/issues/127).

## 1. Define correctness: spec first

**How he did it.** The TeXbook is the normative *definition* of the language,
written before the program was frozen. "TeX the language" is separate from "TeX
the implementation", and the implementation must obey the book. Then he froze
it: bug fixes only, the version number converging to pi, a signed declaration
that it is done.

**How we do it.** A normative spec (a `SPEC.md` or a normative DocC reference
article) defines, independent of any code:

- the coordinate system and the `GraphicsContext` command vocabulary,
- the `DrawList` / `DrawOperation` execution semantics,
- the `.slm` surface grammar in EBNF,
- the canonical pixel semantics and the antialiasing tolerance that defines
  "correct output".

`BitmapRenderer` then becomes *a conforming implementation of the spec*, not the
definition. Declare 1.0 semantics frozen: changes are bug fixes only; features
go to a clearly numbered next line.

Issue: [#123](https://github.com/SlayerMotion/PureDraw/issues/123).

## 2. Make it executable: one brutal gate

**How he did it.** `trip` (TeX) and `trap` (METAFONT): a single, deliberately
ugly, *maximal* input that drives every code path including error and
pathological cases, with a byte-exact expected log. Running it and diffing is
the acceptance gate. It is adversarial, not representative.

**How we do it.** One named `trip` fixture per package that exercises every
feature plus the degenerate, empty, maximal, malformed, and concurrent cases,
with a checked-in expected output. A change to its output requires a deliberate,
reviewed re-baseline, the way Knuth re-published the trip log. The shared,
cross-implementation truth lives in the conformance corpus.

Issues: PureDraw [#124](https://github.com/SlayerMotion/PureDraw/issues/124),
conformance corpus [PureConformance#6](https://github.com/SlayerMotion/PureConformance/issues/6),
[PureLayer#227](https://github.com/SlayerMotion/PureLayer/issues/227),
[PureMetalRenderer#8](https://github.com/SlayerMotion/PureMetalRenderer/issues/8),
[PureComposition#122](https://github.com/SlayerMotion/PureComposition/issues/122).

## 3. Prove the key property: by construction

The crown jewel.

**How he did it.** WEB's TANGLE and WEAVE are two projections of one source, so
they cannot disagree by construction. For an inverse pair he proves
`decode . encode = id` by structural induction over the grammar: each production
is a small lemma.

**How we do it.** Derive both `parse` and `print` from a single bidirectional
grammar definition (the invertible ParserPrinter), so `parse(print(x)) = x` on
the canonical form holds by the structure of the shared definition, one trivial
lemma per production. Make the proof checkable: an exhaustive generative test
over every production and arity (small cases checked completely) plus a written
induction sketch in the spec.

Order of attack:

1. **SVG path data** (smallest grammar) as the proof-of-concept. Closes
   [#110](https://github.com/SlayerMotion/PureDraw/issues/110) properly, as a
   theorem rather than a refactor.
2. Lift the same technique to `.slm` <-> Swift code.
3. And to the lowered-tree <-> emitted-Swift round-trip, the property the whole
   ecosystem leans on ("verify by reflection, not pixels").

Issue: [#125](https://github.com/SlayerMotion/PureDraw/issues/125).

## 4. Write the literature: on the frozen core

**How he did it.** WEB weaves prose and code in human-comprehension order; the
explanation leads, the code is subordinate; TANGLE compiles it and WEAVE
typesets it, so the documentation cannot rot.

**How we do it (Apple-native).** No WEB, but Swift gives the guarantee that
matters: *compiled snippets*. A DocC article per codec and per compiler pass,
narrative first, with the real code embedded as a Swift snippet the build
compiles, so the prose's code can never drift from the shipping code. Done
*after* the core is frozen (step 1), so the literature is about something that
no longer moves.

Issues: codecs [#126](https://github.com/SlayerMotion/PureDraw/issues/126),
compiler [PureComposition#122](https://github.com/SlayerMotion/PureComposition/issues/122).

## First move

Start at step 3 on the smallest grammar: build the bidirectional SVG-path
grammar, derive `parse` / `print` from it, prove the canonical round-trip by
exhaustive generation, and write the induction sketch. It is bounded, it closes
#110 as a theorem, and it is the working proof-of-concept for the technique we
then apply to `.slm` and the lowered tree. With that pattern proven, the spec
(step 1) gives the round-trip a formal home, the trip tests (step 2) gild it,
and the literate rewrite (step 4) writes it up.

## Why this order

Each step depends on the previous one:

| Step | Produces | Depends on |
|---|---|---|
| 1. Spec | the definition of "correct" | nothing |
| 2. Trip / conformance | "correct" made executable | the spec |
| 3. Proof | the key property as a theorem | the spec's grammar |
| 4. Literate | the readable book | a frozen, correct core |
