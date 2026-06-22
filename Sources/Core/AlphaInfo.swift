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
    /// The image is a single alpha channel with no color components, the `CGImageAlphaInfo.alphaOnly`
    /// equivalent. Each sample is an alpha value and the color is taken as black.
    case alphaOnly

    /// Whether the layout carries a real alpha channel (skipped padding bytes do not count).
    public var hasAlpha: Bool {
        switch self {
        case .none, .noneSkipLast, .noneSkipFirst:
            false
        case .premultipliedLast, .premultipliedFirst, .last, .first, .alphaOnly:
            true
        }
    }

    /// Whether the alpha component precedes the color components in memory. An alpha-only image has no
    /// color components, so the distinction does not apply and this is false.
    public var isAlphaFirst: Bool {
        switch self {
        case .premultipliedFirst, .first, .noneSkipFirst:
            true
        case .none, .premultipliedLast, .last, .noneSkipLast, .alphaOnly:
            false
        }
    }

    /// Whether color components are premultiplied by alpha. An alpha-only image has no color
    /// components to premultiply.
    public var isPremultiplied: Bool {
        switch self {
        case .premultipliedLast, .premultipliedFirst:
            true
        case .none, .last, .first, .noneSkipLast, .noneSkipFirst, .alphaOnly:
            false
        }
    }

    /// Whether the image is a single alpha channel with no color components.
    public var isAlphaOnly: Bool {
        self == .alphaOnly
    }
}
