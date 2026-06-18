# Type 2 Charstrings (CFF and CFF2)

One interpreter for PostScript-outlined glyphs, shared by CFF1 and CFF2.

## Overview

CFF (`CFF `) and CFF2 (`CFF2`) store glyph outlines as Type 2 charstrings: tiny
stack programs whose operators move the pen and append curves. The two formats share
the entire geometric vocabulary, so PureDraw shares one interpreter,
`Type2Interpreter`, and injects only the differences. The narrative is here; the
code is `Sources/Core/Type2Interpreter.swift`, with `CFFFont` and `CFF2Font` as the
two front ends.

### The machine

A charstring is read as a stream of operands and operators. Numbers (in several
compact encodings) push onto an operand stack; an operator consumes the stack and
acts. The path operators are the heart of it:

- `rmoveto` / `hmoveto` / `vmoveto` start a new contour.
- `rlineto`, and the alternating-axis `hlineto` / `vlineto`, append lines.
- `rrcurveto` appends cubic Béziers; `vvcurveto`, `hhcurveto`, and the
  alternating-tangent `vhcurveto` / `hvcurveto` are compact forms that imply zero
  components, so one operator can append several curves.
- `callsubr` / `callgsubr` jump into a shared subroutine, indexed with the standard
  bias (107, 1131, or 32768 by population) so that small signed indices reach the
  common middle of the subroutine list.

Curves are built relative to the current point: each control and end point is a delta
from the last, which the interpreter accumulates as it walks the operands.

### Where CFF1 and CFF2 differ

The interpreter takes three switches:

- **Leading width.** A CFF1 charstring may carry the glyph's advance width as an
  extra leading operand on its first stack-clearing operator; CFF2 never does. The
  `hasWidth` flag gates that.
- **`blend` and `vsindex`.** CFF2 adds variation: `vsindex` selects a region set,
  and `blend` interpolates values across regions. At the default instance the blended
  value is just the default, so `blend` keeps the *n* default operands and drops the
  region deltas; `regionCount` tells it how many deltas to drop for the current
  `vsindex`.
- **`endchar`.** CFF1 ends a glyph with `endchar`; a CFF2 charstring ends at its
  length.

### A bug the shared design surfaced

CFF2's `vstore` is DICT operator 24, above the range the original CFF DICT parser
treated as operators (it stopped at 21). The operator was silently skipped, leaving
the variation store unparsed, so `blend` dropped zero deltas and corrupted every
blended glyph. The fix was one line: operands begin at 28, so operators run through
27. The lesson is that a parser's *accepting* set is as load-bearing as its rejecting
set. `CFF2FontTests` checks the result against CoreText on a real CFF2 font.
