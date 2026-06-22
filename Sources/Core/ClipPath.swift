//
//  ClipPath.swift
//  PureDraw
//

/// A single entry on the clip stack: a path together with the fill rule that decides which points it
/// encloses.
///
/// Core Graphics' `clip(using:)` clips to the region a path fills under a winding or even-odd rule,
/// and intersects that with the current clip. Keeping the rule attached to the path (rather than
/// assuming winding for every clip) lets a clip honor `evenOdd`, so a self-overlapping or
/// nested-subpath clip masks to its even-odd region instead of flooding the overlap.
public struct ClipPath: Sendable, Equatable {
    /// The clip outline.
    public var path: Path

    /// The fill rule selecting the path's interior.
    public var rule: FillRule

    public init(path: Path, rule: FillRule = .winding) {
        self.path = path
        self.rule = rule
    }
}
