//
//  AlphaInfo.swift
//  PureDraw
//

/// Specifies the alpha channel layout and premultiplication behavior of an Image.
public enum AlphaInfo: String, Equatable, Sendable, Codable, CaseIterable {
    case none
    case premultipliedLast
    case premultipliedFirst
    case last
    case first
    case noneSkipLast
    case noneSkipFirst

    /// Whether the layout carries a real alpha channel (skipped padding bytes do not count).
    public var hasAlpha: Bool {
        switch self {
        case .none, .noneSkipLast, .noneSkipFirst:
            false
        case .premultipliedLast, .premultipliedFirst, .last, .first:
            true
        }
    }

    /// Whether the alpha component precedes the color components in memory.
    public var isAlphaFirst: Bool {
        switch self {
        case .premultipliedFirst, .first, .noneSkipFirst:
            true
        case .none, .premultipliedLast, .last, .noneSkipLast:
            false
        }
    }

    /// Whether color components are premultiplied by alpha.
    public var isPremultiplied: Bool {
        switch self {
        case .premultipliedLast, .premultipliedFirst:
            true
        case .none, .last, .first, .noneSkipLast, .noneSkipFirst:
            false
        }
    }
}
