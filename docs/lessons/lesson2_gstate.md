# Lesson 2: Context State & The GState Stack

A graphics context behaves as a stateful rendering machine. Understanding how parameters accumulate and how to isolate drawing scopes prevents unintended side-effects in complex vector layouts.

---

## 1. Core Concepts

### The Stateful Drawing Machine
A graphics context stores style and configuration parameters globally. When you set a stroke color, a line width, or a clipping boundary, that parameter remains active for all subsequent drawing commands until it is explicitly changed. These parameters form the **graphics state** (GState).

### State Accumulation and Pollution
If you change context parameters inside a subroutine (for example, setting the stroke color to red to draw a warning marker), the stroke color remains red after the subroutine exits. This is called **state pollution**. To prevent it, graphics contexts maintain an internal stack of saved states.

---

## 2. Mathematical Foundations

### LIFO Stack Semantics
The graphics state stack is a Last-In-First-Out (LIFO) memory structure. 
*   **Push (`saveGState()`)**: Pushes a copy of the current active graphics state onto the top of the stack.
*   **Pop (`restoreGState()`)**: Discards the current graphics state, pops the state from the top of the stack, and makes it the active graphics state.

Let the graphics state at step $i$ be $S_i$. The stack operations behave as follows:

$$\text{Stack}_{\text{initial}} = [S_0]$$
$$\text{saveGState()} \implies \text{Stack} = [S_0, S_0']$$
$$\text{Modify State} \implies S_{\text{active}} = S_1 \text{ and Stack} = [S_0]$$
$$\text{restoreGState()} \implies S_{\text{active}} = S_0 \text{ and Stack} = []$$

Any drawing parameters modified between `saveGState()` and `restoreGState()` are completely discarded upon restoration.

### Parameters Stored in the GState
The graphics state stack preserves:
*   Fill and stroke colors
*   Line width, line cap, line join, and miter limit
*   Line dash patterns and phase offsets
*   Alpha (transparency) levels and blend modes
*   Current Transformation Matrix (CTM)
*   Clipping paths
*   Font selection and font size
*   Shadow options

---

## 3. Code Demonstration

The following Swift example demonstrates how to save and restore graphics state to draw overlapping shapes with separate configurations, ensuring zero parameter pollution.

```swift
import Core
import Geometry
import Renderers

func drawGStateDemo() {
    var context = GraphicsContext()
    
    // Set baseline state (Base color: Green, Width: 4.0)
    context.setFillColor(Color(r: 0.2, g: 0.8, b: 0.2, a: 1.0))
    context.setStrokeColor(Color(r: 0.1, g: 0.5, b: 0.1, a: 1.0))
    context.setLineWidth(4.0)
    
    // Draw the baseline shape
    let rect1 = Rect(x: 20, y: 20, width: 100, height: 100)
    context.fill(rect1)
    context.stroke(rect1)
    
    // Save state before entering local drawing scope
    context.saveGState()
    
    // Modify parameters inside the isolated scope (Change to Orange, Width: 10.0)
    context.setFillColor(Color(r: 0.9, g: 0.6, b: 0.1, a: 1.0))
    context.setStrokeColor(Color(r: 0.7, g: 0.4, b: 0.0, a: 1.0))
    context.setLineWidth(10.0)
    
    // Draw isolated shape
    let rect2 = Rect(x: 140, y: 20, width: 100, height: 100)
    context.fill(rect2)
    context.stroke(rect2)
    
    // Restore the state to revert back to baseline parameters
    context.restoreGState()
    
    // Draw another shape; it will use the baseline parameters (Green, Width: 4.0)
    let rect3 = Rect(x: 260, y: 20, width: 100, height: 100)
    context.fill(rect3)
    context.stroke(rect3)
    
    // Render to output
    let renderer = SVGRenderer(width: 380, height: 140)
    do {
        let svg = try renderer.draw(context)
        print("GState SVG Output:\n\(svg)")
    } catch {
        print("Rendering error: \(error)")
    }
}
```

---

## 4. Exercises

1.  **State Tracing**: Trace the line width value for each drawing operation in the sequence below:
    ```
    LineWidth = 2.0
    SaveGState()
    LineWidth = 5.0
    SaveGState()
    LineWidth = 8.0
    RestoreGState()
    DrawLine()
    RestoreGState()
    DrawLine()
    ```
2.  **RAII Wrapper**: Write an extension on `GraphicsContext` that implements a closure-based GState manager:
    ```swift
    mutating func withGState(_ body: (inout GraphicsContext) throws -> Void) rethrows
    ```
    This function must save the state, execute the closure, and guarantee state restoration even if the closure throws an error.
