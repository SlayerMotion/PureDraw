# Variable Font Interpolation

How a glyph outline is interpolated to a weight, width, or optical-size instance.

## Overview

A variable font carries one master outline plus deltas that move its points as you
travel along design axes. `Font.outline(forGlyph:variations:)` evaluates those deltas
for a chosen instance. The narrative is here; the code is in `Font.swift`, verified
against CoreText's own instanced paths on a real variable font in
`VariableFontCoreTextTests`.

### Normalizing the coordinates

The axes (`fvar`) are user-space ranges, for example weight 100 to 900. Each chosen
coordinate is first clamped to its axis and mapped to the normalized range -1 to 1,
piecewise about the default. If the font has an `avar` table, the normalized value is
then remapped through that axis's segment map, a piecewise-linear curve, so the
interpolation matches what the platform shaper does. Skipping `avar` is the most
common reason a hand-rolled instancer disagrees with the system.

### The tuple variation store (gvar)

`gvar` holds, per glyph, a set of *tuples*. Each tuple has a peak position in axis
space and a set of point deltas, and contributes to the instance in proportion to a
**scalar** computed from the peak and the current coordinate: the standard per-axis
tent (FreeType's `ft_var_apply_tuple`), a product over axes where a peak of zero
leaves an axis out and a current coordinate of zero against a nonzero peak zeroes the
tuple. Intermediate-region tuples carry explicit start and end bounds.

The deltas themselves are packed twice over: a packed *point-number* list says which
points a tuple touches (or all of them), and packed *delta* runs encode the x and
then y offsets, with run-length encoding for repeated and zero deltas. Tuples may
share one point-number list for the glyph.

### Filling in the untouched points (IUP)

A tuple usually touches only some of a contour's points. The rest are filled by
**Interpolation of Untouched Points**: for each untouched point, look along the
contour to the nearest touched point on each side and linearly interpolate its delta
by the point's own coordinate, independently for x and y; outside the touched range,
the nearer touched delta is used unchanged. This is what lets a font ship sparse
deltas and still deform smoothly.

### Composite glyphs

A composite glyph (an accented letter, say) has no contour of its own; its `gvar`
deltas shift each *component's* offset instead, and each component is itself
interpolated. There is no IUP for composites: each component is one independent
point. Accented letters in the cross-check against CoreText exercise exactly this
path.

### The result

The accumulated, scaled deltas are added to the master points, and the outline is
rebuilt. At the default instance every scalar is zero, so the result is exactly the
static outline, which the test pins as a sanity check.
