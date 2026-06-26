import CoreGraphics
import Foundation

// Core type aliases for the CoreGraphics Services (CGS) interface.
//
// These mirror the typedefs in the community CGSInternal headers. The values are
// plain scalars or CoreFoundation handles, so the Swift representations below are
// ABI-compatible with the C declarations the WindowServer exports.

/// A handle to a connection to the WindowServer (`CGSConnectionID`, a C `int`).
public typealias CGSConnectionID = Int32

/// Identifier for a managed space / virtual desktop (`CGSSpaceID`, a C `size_t`).
public typealias CGSSpaceID = Int

/// Opaque CoreFoundation handle for a server-side region (`CGSRegionRef`).
///
/// Modelled as an `OpaquePointer` rather than a bridged `CFTypeRef` because the
/// lifetime is managed explicitly through `CGSReleaseRegion`, which keeps the
/// `@_silgen_name` declarations free of `Unmanaged` retain/release bridging.
public typealias CGSRegionRef = OpaquePointer

/// Opaque handle returned by `CGSRegionEnumerator`.
public typealias CGSRegionEnumeratorRef = OpaquePointer

// `CGWindowID`, `CGWindowLevel`, `CGEventMask`, `CGError`, `CGRect`, `CGPoint`,
// `CGFloat`, and `CGAffineTransform` are all public CoreGraphics types and are
// reused directly.

public extension CGError {
    /// Convenience: did the call succeed (`kCGErrorSuccess`)?
    @inlinable var isSuccess: Bool {
        self == .success
    }
}
