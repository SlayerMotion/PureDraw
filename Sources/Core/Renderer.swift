//
//  Renderer.swift
//  PureDraw
//

import Geometry
import Validation

/// Defines a bridge that translates drawing command buffers into target-specific outputs.
public protocol Renderer: Sendable {
    associatedtype Output

    /// Translates the recorded commands from the context into the target output format.
    ///
    /// This is the rendering primitive each backend implements. Call `render(_:)` instead,
    /// which validates the context before drawing; `draw(_:)` may assume a valid context.
    func draw(_ context: GraphicsContext) throws -> Output
}

public extension Renderer {
    /// Validates the context and all of its nested values, then translates the recorded
    /// commands into the target output format.
    ///
    /// - Throws: `ValidationErrorCollection` when the context fails validation, or any
    ///   error thrown by the backend while drawing.
    func render(_ context: GraphicsContext) throws -> Output {
        try context.validate()
        return try draw(context)
    }
}
