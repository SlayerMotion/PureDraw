import CoreGraphics
import Foundation

// WindowServer connection management.
//
// Raw `@_silgen_name` declarations transcribed from CGSConnection.h, followed by
// a small Swift wrapper. A connection is the per-process channel to the
// WindowServer; almost every other CGS call takes one as its first argument.

// MARK: - Raw SPI

/// The shared connection for this process.
@_silgen_name("CGSMainConnectionID")
public func CGSMainConnectionID() -> CGSConnectionID

/// The connection bound to the calling thread (may differ from the main one).
@_silgen_name("CGSDefaultConnectionForThread")
public func CGSDefaultConnectionForThread() -> CGSConnectionID

@_silgen_name("CGSNewConnection")
public func CGSNewConnection(_ unused: Int32, _ outConnection: UnsafeMutablePointer<CGSConnectionID>) -> CGError

@_silgen_name("CGSReleaseConnection")
public func CGSReleaseConnection(_ cid: CGSConnectionID) -> CGError

@_silgen_name("CGSConnectionGetPID")
public func CGSConnectionGetPID(_ cid: CGSConnectionID, _ outPID: UnsafeMutablePointer<pid_t>) -> CGError

@_silgen_name("CGSMenuBarExists")
public func CGSMenuBarExists(_ cid: CGSConnectionID) -> Bool

@_silgen_name("CGSShutdownServerConnections")
public func CGSShutdownServerConnections() -> CGError

/// Connection properties.
@_silgen_name("CGSCopyConnectionProperty")
public func CGSCopyConnectionProperty(_ cid: CGSConnectionID, _ targetCID: CGSConnectionID, _ key: CFString, _ outValue: UnsafeMutablePointer<Unmanaged<CFTypeRef>?>) -> CGError

@_silgen_name("CGSSetConnectionProperty")
public func CGSSetConnectionProperty(_ cid: CGSConnectionID, _ targetCID: CGSConnectionID, _ key: CFString, _ value: CFTypeRef) -> CGError

/// Batched update bracketing: coalesce a set of window changes into one flush.
@_silgen_name("CGSDisableUpdate")
public func CGSDisableUpdate(_ cid: CGSConnectionID) -> CGError

@_silgen_name("CGSReenableUpdate")
public func CGSReenableUpdate(_ cid: CGSConnectionID) -> CGError

// Connection lifecycle notifications. The procs are plain C function pointers.
public typealias CGSNewConnectionNotificationProc = @convention(c) (CGSConnectionID) -> Void
public typealias CGSConnectionDeathNotificationProc = @convention(c) (CGSConnectionID) -> Void

@_silgen_name("CGSRegisterForNewConnectionNotification")
public func CGSRegisterForNewConnectionNotification(_ proc: CGSNewConnectionNotificationProc) -> CGError

@_silgen_name("CGSRemoveNewConnectionNotification")
public func CGSRemoveNewConnectionNotification(_ proc: CGSNewConnectionNotificationProc) -> CGError

@_silgen_name("CGSRegisterForConnectionDeathNotification")
public func CGSRegisterForConnectionDeathNotification(_ proc: CGSConnectionDeathNotificationProc) -> CGError

@_silgen_name("CGSRemoveConnectionDeathNotification")
public func CGSRemoveConnectionDeathNotification(_ proc: CGSConnectionDeathNotificationProc) -> CGError

// MARK: - Wrapper

/// A typed handle around a `CGSConnectionID`.
public struct CGSConnection: Equatable {
    public let id: CGSConnectionID

    public init(id: CGSConnectionID) {
        self.id = id
    }

    /// The shared connection for this process.
    public static var main: CGSConnection {
        CGSConnection(id: CGSMainConnectionID())
    }

    /// The connection bound to the calling thread.
    public static var current: CGSConnection {
        CGSConnection(id: CGSDefaultConnectionForThread())
    }

    /// The pid that owns this connection, or `nil` if the query failed.
    public func ownerPID() -> pid_t? {
        var pid: pid_t = 0
        return CGSConnectionGetPID(id, &pid).isSuccess ? pid : nil
    }

    /// Whether a menu bar exists for this connection.
    public var menuBarExists: Bool {
        CGSMenuBarExists(id)
    }

    /// Coalesce window changes made inside `body` into a single server flush.
    @discardableResult
    public func withBatchedUpdates<T>(_ body: () throws -> T) rethrows -> T {
        _ = CGSDisableUpdate(id)
        defer { _ = CGSReenableUpdate(id) }
        return try body()
    }
}
