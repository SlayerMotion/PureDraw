//
//  Renderer.swift
//  PureDraw
//

import Geometry

/// Defines a bridge that translates drawing command buffers into target-specific outputs.
public protocol Renderer: Sendable {
    associatedtype Output

    /// Translates the recorded commands from the context into the target output format.
    func render(_ context: GraphicsContext) throws -> Output
}
