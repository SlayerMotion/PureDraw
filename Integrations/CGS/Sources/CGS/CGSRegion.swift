import CoreGraphics
import Foundation

// Server-side regions (CGSRegion.h).
//
// Regions are CoreFoundation objects created and released through the CGS API.
// They are local, math-only objects: creating and querying them does not require
// a live WindowServer connection, which makes them the safest part of CGS to
// exercise in isolation.

// MARK: - Raw SPI

@_silgen_name("CGSNewRegionWithRect")
public func CGSNewRegionWithRect(_ rect: UnsafePointer<CGRect>, _ outRegion: UnsafeMutablePointer<CGSRegionRef?>) -> CGError

@_silgen_name("CGSNewRegionWithRectList")
public func CGSNewRegionWithRectList(_ rects: UnsafePointer<CGRect>, _ rectCount: Int32, _ outRegion: UnsafeMutablePointer<CGSRegionRef?>) -> CGError

@_silgen_name("CGSNewEmptyRegion")
public func CGSNewEmptyRegion(_ outRegion: UnsafeMutablePointer<CGSRegionRef?>) -> CGError

@_silgen_name("CGSReleaseRegion")
public func CGSReleaseRegion(_ region: CGSRegionRef) -> CGError

@_silgen_name("CGSCopyRegion")
public func CGSCopyRegion(_ region: CGSRegionRef, _ outRegion: UnsafeMutablePointer<CGSRegionRef?>) -> CGError

@_silgen_name("CGSOffsetRegion")
public func CGSOffsetRegion(_ region: CGSRegionRef, _ offsetLeft: CGFloat, _ offsetTop: CGFloat, _ outRegion: UnsafeMutablePointer<CGSRegionRef?>) -> CGError

@_silgen_name("CGSUnionRegion")
public func CGSUnionRegion(_ region1: CGSRegionRef, _ region2: CGSRegionRef, _ outRegion: UnsafeMutablePointer<CGSRegionRef?>) -> CGError

@_silgen_name("CGSUnionRegionWithRect")
public func CGSUnionRegionWithRect(_ region: CGSRegionRef, _ rect: UnsafePointer<CGRect>, _ outRegion: UnsafeMutablePointer<CGSRegionRef?>) -> CGError

@_silgen_name("CGSDiffRegion")
public func CGSDiffRegion(_ region1: CGSRegionRef, _ region2: CGSRegionRef, _ outRegion: UnsafeMutablePointer<CGSRegionRef?>) -> CGError

@_silgen_name("CGSXorRegion")
public func CGSXorRegion(_ region1: CGSRegionRef, _ region2: CGSRegionRef, _ outRegion: UnsafeMutablePointer<CGSRegionRef?>) -> CGError

@_silgen_name("CGSGetRegionBounds")
public func CGSGetRegionBounds(_ region: CGSRegionRef, _ outRect: UnsafeMutablePointer<CGRect>) -> CGError

@_silgen_name("CGSRegionsEqual")
public func CGSRegionsEqual(_ region1: CGSRegionRef, _ region2: CGSRegionRef) -> Bool

@_silgen_name("CGSRegionInRegion")
public func CGSRegionInRegion(_ region1: CGSRegionRef, _ region2: CGSRegionRef) -> Bool

@_silgen_name("CGSRegionIntersectsRegion")
public func CGSRegionIntersectsRegion(_ region1: CGSRegionRef, _ region2: CGSRegionRef) -> Bool

@_silgen_name("CGSRegionIntersectsRect")
public func CGSRegionIntersectsRect(_ region: CGSRegionRef, _ rect: UnsafePointer<CGRect>) -> Bool

@_silgen_name("CGSPointInRegion")
public func CGSPointInRegion(_ region: CGSRegionRef, _ point: UnsafePointer<CGPoint>) -> Bool

@_silgen_name("CGSRectInRegion")
public func CGSRectInRegion(_ region: CGSRegionRef, _ rect: UnsafePointer<CGRect>) -> Bool

@_silgen_name("CGSRegionIsEmpty")
public func CGSRegionIsEmpty(_ region: CGSRegionRef) -> Bool

@_silgen_name("CGSRegionIsRectangular")
public func CGSRegionIsRectangular(_ region: CGSRegionRef) -> Bool

@_silgen_name("CGSRegionEnumerator")
public func CGSRegionEnumerator(_ region: CGSRegionRef) -> CGSRegionEnumeratorRef?

@_silgen_name("CGSReleaseRegionEnumerator")
public func CGSReleaseRegionEnumerator(_ enumerator: CGSRegionEnumeratorRef)

@_silgen_name("CGSNextRect")
public func CGSNextRect(_ enumerator: CGSRegionEnumeratorRef) -> UnsafeMutablePointer<CGRect>?

// MARK: - Wrapper

/// An owned CGS region. The underlying handle is released on `deinit`.
public final class CGSRegion {
    public let ref: CGSRegionRef

    /// Wrap an already-owned region handle (ownership transfers to this object).
    public init(owning ref: CGSRegionRef) {
        self.ref = ref
    }

    deinit {
        _ = CGSReleaseRegion(ref)
    }

    /// A region covering a single rectangle.
    public convenience init?(_ rect: CGRect) {
        var rect = rect
        var out: CGSRegionRef?
        guard CGSNewRegionWithRect(&rect, &out).isSuccess, let region = out else { return nil }
        self.init(owning: region)
    }

    /// A region covering the union of several rectangles.
    public convenience init?(_ rects: [CGRect]) {
        var out: CGSRegionRef?
        let ok = rects.withUnsafeBufferPointer { buffer -> Bool in
            guard let base = buffer.baseAddress else { return false }
            return CGSNewRegionWithRectList(base, Int32(buffer.count), &out).isSuccess
        }
        guard ok, let region = out else { return nil }
        self.init(owning: region)
    }

    /// Builds an owned region from a CGS call that returns one through an out-parameter,
    /// collapsing the repeated `var out; guard call(&out).isSuccess, let …` dance.
    private static func make(_ body: (UnsafeMutablePointer<CGSRegionRef?>) -> CGError) -> CGSRegion? {
        var out: CGSRegionRef?
        guard body(&out).isSuccess, let region = out else { return nil }
        return CGSRegion(owning: region)
    }

    /// An empty region.
    public static func empty() -> CGSRegion? {
        make { CGSNewEmptyRegion($0) }
    }

    public var bounds: CGRect {
        var rect = CGRect.zero
        _ = CGSGetRegionBounds(ref, &rect)
        return rect
    }

    public var isEmpty: Bool {
        CGSRegionIsEmpty(ref)
    }

    public var isRectangular: Bool {
        CGSRegionIsRectangular(ref)
    }

    public func contains(_ point: CGPoint) -> Bool {
        var point = point
        return CGSPointInRegion(ref, &point)
    }

    public func intersects(_ other: CGSRegion) -> Bool {
        CGSRegionIntersectsRegion(ref, other.ref)
    }

    public func union(_ other: CGSRegion) -> CGSRegion? {
        CGSRegion.make { CGSUnionRegion(ref, other.ref, $0) }
    }

    public func subtracting(_ other: CGSRegion) -> CGSRegion? {
        CGSRegion.make { CGSDiffRegion(ref, other.ref, $0) }
    }

    /// The component rectangles that make up this region.
    public var rectangles: [CGRect] {
        guard let enumerator = CGSRegionEnumerator(ref) else { return [] }
        defer { CGSReleaseRegionEnumerator(enumerator) }
        var result: [CGRect] = []
        while let next = CGSNextRect(enumerator) {
            result.append(next.pointee)
        }
        return result
    }
}
