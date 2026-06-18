# Getting Started

Draw a picture and render it to an image.

## Overview

PureDraw separates *describing* a picture from *rendering* it. You issue drawing
commands to a ``GraphicsContext``, then hand the context to a renderer.

### Describe the picture

A ``GraphicsContext`` is a value type that records drawing operations together
with the graphics state in effect when each is issued.

```swift
import PureDraw

var context = GraphicsContext()

// A filled square.
context.setFillColor(Color(red: 0.2, green: 0.5, blue: 0.9))
context.fill(Rect(x: 10, y: 10, width: 80, height: 80))

// A circle outlined on top of it.
context.setStrokeColor(.black)
context.setLineWidth(4)
context.strokeEllipse(in: Rect(x: 20, y: 20, width: 60, height: 60))
```

Because each command captures the current state, changing the fill color later
does not affect shapes already recorded. Bracket temporary changes with
``GraphicsContext/saveGState()`` and ``GraphicsContext/restoreGState()``, and
build free-form shapes with ``GraphicsContext/move(to:)``,
``GraphicsContext/addLine(to:)``, ``GraphicsContext/addCurve(to:control1:control2:)``,
and ``GraphicsContext/fillPath(using:)``.

### Render it

```swift
let renderer = BitmapRenderer(width: 100, height: 100)
let image = try renderer.render(context)   // a raw-RGBA Image
```

``Renderer/render(_:)`` validates the context, rejecting non-finite or
out-of-range values before drawing, then produces the backend's output (an
``Image`` for ``BitmapRenderer``).

To produce a document or code instead of pixels, swap in a different renderer
without changing the drawing code; see <doc:ChoosingARenderer>.
