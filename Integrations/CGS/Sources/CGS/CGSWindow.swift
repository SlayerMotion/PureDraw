import CoreGraphics
import Foundation

// WindowServer windows (CGSWindow.h).
//
// This binds the high-value subset of the window API: creation, ordering,
// geometry, level, alpha, opacity, title/properties, the drawing context, window
// lists, and shadows. The exotic surface (warps, backdrops, genie/sheet
// animations, drag regions, status-bar registration, tag bitfields) is catalogued
// in COVERAGE.md and intentionally not yet bound.

// MARK: - Enums

/// Backing store kind for a new window (`CGSBackingType`).
public enum CGSBackingType: Int32 {
    case nonRetained = 0
    case retained = 1
    case buffered = 2
}

/// How a window is ordered relative to another (`CGSWindowOrderingMode`).
public enum CGSWindowOrderingMode: Int32 {
    case below = -1
    case out = 0
    case above = 1
    case `in` = 2
}

/// Whether other processes may read/capture a window (`CGSSharingState`).
public enum CGSSharingState: Int32 {
    case none = 0
    case readOnly = 1
    case readWrite = 2
}

// MARK: - Raw SPI

@_silgen_name("CGSNewWindow")
public func CGSNewWindow(
    _ cid: CGSConnectionID,
    _ backingType: Int32,
    _ left: CGFloat,
    _ top: CGFloat,
    _ region: CGSRegionRef?,
    _ outWID: UnsafeMutablePointer<CGWindowID>
) -> CGError

@_silgen_name("CGSReleaseWindow")
public func CGSReleaseWindow(_ cid: CGSConnectionID, _ wid: CGWindowID) -> CGError

@_silgen_name("CGSOrderWindow")
public func CGSOrderWindow(_ cid: CGSConnectionID, _ wid: CGWindowID, _ mode: Int32, _ relativeToWID: CGWindowID) -> CGError

@_silgen_name("CGSOrderFrontConditionally")
public func CGSOrderFrontConditionally(_ cid: CGSConnectionID, _ wid: CGWindowID, _ force: Bool) -> CGError

@_silgen_name("CGSMoveWindow")
public func CGSMoveWindow(_ cid: CGSConnectionID, _ wid: CGWindowID, _ origin: UnsafePointer<CGPoint>) -> CGError

@_silgen_name("CGSGetScreenRectForWindow")
public func CGSGetScreenRectForWindow(_ cid: CGSConnectionID, _ wid: CGWindowID, _ outRect: UnsafeMutablePointer<CGRect>) -> CGError

@_silgen_name("CGSGetWindowMouseLocation")
public func CGSGetWindowMouseLocation(_ cid: CGSConnectionID, _ wid: CGWindowID, _ outPos: UnsafeMutablePointer<CGPoint>) -> CGError

@_silgen_name("CGSGetWindowAlpha")
public func CGSGetWindowAlpha(_ cid: CGSConnectionID, _ wid: CGWindowID, _ outAlpha: UnsafeMutablePointer<CGFloat>) -> CGError

@_silgen_name("CGSSetWindowAlpha")
public func CGSSetWindowAlpha(_ cid: CGSConnectionID, _ wid: CGWindowID, _ alpha: CGFloat) -> CGError

@_silgen_name("CGSGetWindowOpacity")
public func CGSGetWindowOpacity(_ cid: CGSConnectionID, _ wid: CGWindowID, _ outIsOpaque: UnsafeMutablePointer<Bool>) -> CGError

@_silgen_name("CGSSetWindowOpacity")
public func CGSSetWindowOpacity(_ cid: CGSConnectionID, _ wid: CGWindowID, _ isOpaque: Bool) -> CGError

@_silgen_name("CGSGetWindowLevel")
public func CGSGetWindowLevel(_ cid: CGSConnectionID, _ wid: CGWindowID, _ outLevel: UnsafeMutablePointer<CGWindowLevel>) -> CGError

@_silgen_name("CGSSetWindowLevel")
public func CGSSetWindowLevel(_ cid: CGSConnectionID, _ wid: CGWindowID, _ level: CGWindowLevel) -> CGError

@_silgen_name("CGSSetWindowTitle")
public func CGSSetWindowTitle(_ cid: CGSConnectionID, _ wid: CGWindowID, _ title: CFString) -> CGError

@_silgen_name("CGSGetWindowProperty")
public func CGSGetWindowProperty(_ cid: CGSConnectionID, _ wid: CGWindowID, _ key: CFString, _ outValue: UnsafeMutablePointer<Unmanaged<CFTypeRef>?>) -> CGError

@_silgen_name("CGSSetWindowProperty")
public func CGSSetWindowProperty(_ cid: CGSConnectionID, _ wid: CGWindowID, _ key: CFString, _ value: CFTypeRef) -> CGError

@_silgen_name("CGSGetWindowSharingState")
public func CGSGetWindowSharingState(_ cid: CGSConnectionID, _ wid: CGWindowID, _ outState: UnsafeMutablePointer<Int32>) -> CGError

@_silgen_name("CGSSetWindowSharingState")
public func CGSSetWindowSharingState(_ cid: CGSConnectionID, _ wid: CGWindowID, _ state: Int32) -> CGError

@_silgen_name("CGSGetWindowTransform")
public func CGSGetWindowTransform(_ cid: CGSConnectionID, _ wid: CGWindowID, _ outTransform: UnsafeMutablePointer<CGAffineTransform>) -> CGError

@_silgen_name("CGSSetWindowTransform")
public func CGSSetWindowTransform(_ cid: CGSConnectionID, _ wid: CGWindowID, _ transform: CGAffineTransform) -> CGError

@_silgen_name("CGSSetWindowShadowParameters")
public func CGSSetWindowShadowParameters(_ cid: CGSConnectionID, _ wid: CGWindowID, _ standardDeviation: CGFloat, _ density: CGFloat, _ offsetX: Int32, _ offsetY: Int32) -> CGError

@_silgen_name("CGSInvalidateWindowShadow")
public func CGSInvalidateWindowShadow(_ cid: CGSConnectionID, _ wid: CGWindowID) -> CGError

/// Drawing.
@_silgen_name("CGWindowContextCreate")
public func CGWindowContextCreate(_ cid: CGSConnectionID, _ wid: CGWindowID, _ options: CFDictionary?) -> Unmanaged<CGContext>?

@_silgen_name("CGSFlushWindow")
public func CGSFlushWindow(_ cid: CGSConnectionID, _ wid: CGWindowID, _ flushRegion: CGSRegionRef?) -> CGError

/// Window lists.
@_silgen_name("CGSGetWindowCount")
public func CGSGetWindowCount(_ cid: CGSConnectionID, _ targetCID: CGSConnectionID, _ outCount: UnsafeMutablePointer<Int32>) -> CGError

@_silgen_name("CGSGetWindowList")
public func CGSGetWindowList(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ count: Int32,
    _ list: UnsafeMutablePointer<CGWindowID>,
    _ outCount: UnsafeMutablePointer<Int32>
) -> CGError

@_silgen_name("CGSGetOnScreenWindowCount")
public func CGSGetOnScreenWindowCount(_ cid: CGSConnectionID, _ targetCID: CGSConnectionID, _ outCount: UnsafeMutablePointer<Int32>) -> CGError

@_silgen_name("CGSGetOnScreenWindowList")
public func CGSGetOnScreenWindowList(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ count: Int32,
    _ list: UnsafeMutablePointer<CGWindowID>,
    _ outCount: UnsafeMutablePointer<Int32>
) -> CGError

// MARK: - Wrapper

/// A WindowServer window handle. When it owns the id (the default, e.g. a window it created) it
/// releases it on `deinit`; a *borrowed* handle (e.g. one returned by `CGSGetWindowList`, whose id
/// the caller does not own) does not, so wrapping a listed window cannot double-release it.
public final class CGSWindow {
    public let connection: CGSConnection
    public let id: CGWindowID
    private let owned: Bool

    /// Wrap a window id. With `owned: true` (the default) this handle releases the window on
    /// `deinit`; pass `owned: false` for ids the caller does not own (see `borrowing(_:on:)`).
    public init(connection: CGSConnection, id: CGWindowID, owned: Bool = true) {
        self.connection = connection
        self.id = id
        self.owned = owned
    }

    /// Wraps a window id the caller does NOT own (e.g. from `CGSGetWindowList`); `deinit` will not
    /// release it.
    public static func borrowing(_ id: CGWindowID, on connection: CGSConnection = .main) -> CGSWindow {
        CGSWindow(connection: connection, id: id, owned: false)
    }

    deinit {
        if owned { _ = CGSReleaseWindow(connection.id, id) }
    }

    /// Create a window whose drawable shape is `frame` (in global, top-left
    /// coordinates). The backing region is the frame translated to the origin.
    public convenience init?(
        connection: CGSConnection = .main,
        frame: CGRect,
        backing: CGSBackingType = .buffered
    ) {
        let localShape = CGRect(origin: .zero, size: frame.size)
        guard let region = CGSRegion(localShape) else { return nil }
        var wid: CGWindowID = 0
        let status = CGSNewWindow(
            connection.id,
            backing.rawValue,
            frame.minX,
            frame.minY,
            region.ref,
            &wid
        )
        guard status.isSuccess else { return nil }
        self.init(connection: connection, id: wid)
    }

    /// Bring the window on screen, ordered above everything (`kCGSOrderAbove`).
    @discardableResult
    public func orderFront() -> Bool {
        CGSOrderWindow(connection.id, id, CGSWindowOrderingMode.above.rawValue, 0).isSuccess
    }

    /// Take the window off screen (`kCGSOrderOut`).
    @discardableResult
    public func orderOut() -> Bool {
        CGSOrderWindow(connection.id, id, CGSWindowOrderingMode.out.rawValue, 0).isSuccess
    }

    /// Order this window relative to another.
    @discardableResult
    public func order(_ mode: CGSWindowOrderingMode, relativeTo other: CGSWindow?) -> Bool {
        CGSOrderWindow(connection.id, id, mode.rawValue, other?.id ?? 0).isSuccess
    }

    public var alpha: CGFloat {
        get {
            var value: CGFloat = 0
            _ = CGSGetWindowAlpha(connection.id, id, &value)
            return value
        }
        set { _ = CGSSetWindowAlpha(connection.id, id, newValue) }
    }

    public var level: CGWindowLevel {
        get {
            var value: CGWindowLevel = 0
            _ = CGSGetWindowLevel(connection.id, id, &value)
            return value
        }
        set { _ = CGSSetWindowLevel(connection.id, id, newValue) }
    }

    /// The window's frame in screen coordinates.
    public var screenFrame: CGRect {
        var rect = CGRect.zero
        _ = CGSGetScreenRectForWindow(connection.id, id, &rect)
        return rect
    }

    @discardableResult
    public func move(to origin: CGPoint) -> Bool {
        var origin = origin
        return CGSMoveWindow(connection.id, id, &origin).isSuccess
    }

    @discardableResult
    public func setTitle(_ title: String) -> Bool {
        CGSSetWindowTitle(connection.id, id, title as CFString).isSuccess
    }

    /// A CoreGraphics context backed by this window. Caller draws into it, then
    /// calls `flush()`. Returns `nil` if the server refuses a context.
    public func makeContext(options: CFDictionary? = nil) -> CGContext? {
        CGWindowContextCreate(connection.id, id, options)?.takeRetainedValue()
    }

    @discardableResult
    public func flush(region: CGSRegion? = nil) -> Bool {
        CGSFlushWindow(connection.id, id, region?.ref).isSuccess
    }
}
