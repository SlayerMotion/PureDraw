//
//  DrawOperation.swift
//  PureDraw
//

/// Represents an immutable, recorded drawing command that binds geometry with its drawing state.
public struct DrawOperation: Equatable, Sendable, Validatable {
    public enum Kind: Equatable, Sendable {
        case fill(Path, rule: FillRule)
        case stroke(Path)
    }
    
    public let kind: Kind
    public let state: GraphicState
    
    public init(kind: Kind, state: GraphicState) {
        self.kind = kind
        self.state = state
    }
}
