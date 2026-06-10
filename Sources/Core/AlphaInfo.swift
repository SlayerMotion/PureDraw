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
}
