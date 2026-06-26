import CoreGraphics
import Foundation

// Spaces / virtual desktops (CGSSpace.h).
//
// Spaces functions live in SkyLight on modern macOS and operate on CoreFoundation
// arrays of space-id numbers. They require a live WindowServer session.

// MARK: - Enums

/// Kind of a space (`CGSSpaceType`).
public enum CGSSpaceType: Int32 {
    case user = 0
    case fullscreen = 1
    case system = 2
}

/// Selector mask for `CGSCopySpaces` (`CGSSpaceMask`).
///
/// The individual bits are taken directly from the header; the convenience masks
/// are documented compositions of those bits, mirroring the `kCGS*SpacesMask`
/// constants used by callers.
public struct CGSSpaceMask: OptionSet {
    public let rawValue: Int32
    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }

    public static let includesCurrent = CGSSpaceMask(rawValue: 1 << 0)
    public static let includesOthers = CGSSpaceMask(rawValue: 1 << 1)
    public static let includesUser = CGSSpaceMask(rawValue: 1 << 2)
    public static let visible = CGSSpaceMask(rawValue: 1 << 16)

    public static let currentSpace: CGSSpaceMask = [.includesUser, .includesCurrent]
    public static let otherSpaces: CGSSpaceMask = [.includesUser, .includesOthers]
    public static let allSpaces: CGSSpaceMask = [.includesUser, .includesOthers, .includesCurrent]
    public static let allVisibleSpaces: CGSSpaceMask = [.visible, .includesUser, .includesOthers, .includesCurrent]
}

/// Per-display space management mode (`CGSSpaceManagementMode`).
public enum CGSSpaceManagementMode: Int32 {
    case none = 0
    case perDesktop = 1
}

// MARK: - Raw SPI

@_silgen_name("CGSSpaceCreate")
public func CGSSpaceCreate(_ cid: CGSConnectionID, _ null: UnsafeMutableRawPointer?, _ options: CFDictionary?) -> CGSSpaceID

@_silgen_name("CGSSpaceDestroy")
public func CGSSpaceDestroy(_ cid: CGSConnectionID, _ sid: CGSSpaceID)

@_silgen_name("CGSSpaceCopyName")
public func CGSSpaceCopyName(_ cid: CGSConnectionID, _ sid: CGSSpaceID) -> Unmanaged<CFString>?

@_silgen_name("CGSSpaceSetName")
public func CGSSpaceSetName(_ cid: CGSConnectionID, _ sid: CGSSpaceID, _ name: CFString) -> CGError

@_silgen_name("CGSSpaceGetType")
public func CGSSpaceGetType(_ cid: CGSConnectionID, _ sid: CGSSpaceID) -> Int32

@_silgen_name("CGSGetActiveSpace")
public func CGSGetActiveSpace(_ cid: CGSConnectionID) -> CGSSpaceID

@_silgen_name("CGSCopySpaces")
public func CGSCopySpaces(_ cid: CGSConnectionID, _ mask: Int32) -> Unmanaged<CFArray>?

@_silgen_name("CGSCopySpacesForWindows")
public func CGSCopySpacesForWindows(_ cid: CGSConnectionID, _ mask: Int32, _ windowIDs: CFArray) -> Unmanaged<CFArray>?

@_silgen_name("CGSSpaceCopyValues")
public func CGSSpaceCopyValues(_ cid: CGSConnectionID, _ space: CGSSpaceID) -> Unmanaged<CFDictionary>?

@_silgen_name("CGSSpaceSetValues")
public func CGSSpaceSetValues(_ cid: CGSConnectionID, _ sid: CGSSpaceID, _ values: CFDictionary) -> CGError

@_silgen_name("CGSGetSpaceManagementMode")
public func CGSGetSpaceManagementMode(_ cid: CGSConnectionID) -> Int32

@_silgen_name("CGSSetSpaceManagementMode")
public func CGSSetSpaceManagementMode(_ cid: CGSConnectionID, _ mode: Int32) -> CGError

@_silgen_name("CGSShowSpaces")
public func CGSShowSpaces(_ cid: CGSConnectionID, _ spaces: CFArray)

@_silgen_name("CGSHideSpaces")
public func CGSHideSpaces(_ cid: CGSConnectionID, _ spaces: CFArray)

@_silgen_name("CGSAddWindowsToSpaces")
public func CGSAddWindowsToSpaces(_ cid: CGSConnectionID, _ windows: CFArray, _ spaces: CFArray)

@_silgen_name("CGSRemoveWindowsFromSpaces")
public func CGSRemoveWindowsFromSpaces(_ cid: CGSConnectionID, _ windows: CFArray, _ spaces: CFArray)

@_silgen_name("CGSManagedDisplaySetCurrentSpace")
public func CGSManagedDisplaySetCurrentSpace(_ cid: CGSConnectionID, _ display: CFString, _ space: CGSSpaceID)

// MARK: - Wrapper

/// Stateless helpers over the spaces API. All take a connection (defaulting to
/// the main one) since spaces are a process-global concept.
public enum CGSSpaces {
    /// The id of the currently active space.
    public static func active(connection: CGSConnection = .main) -> CGSSpaceID {
        CGSGetActiveSpace(connection.id)
    }

    /// All space ids matching `mask`.
    public static func all(_ mask: CGSSpaceMask = .allSpaces, connection: CGSConnection = .main) -> [CGSSpaceID] {
        guard let array = CGSCopySpaces(connection.id, mask.rawValue)?.takeRetainedValue() else { return [] }
        return spaceIDs(from: array)
    }

    /// The spaces that the given windows currently occupy.
    public static func forWindows(_ windowIDs: [CGWindowID], mask: CGSSpaceMask = .allSpaces, connection: CGSConnection = .main) -> [CGSSpaceID] {
        let windows = windowIDs.map { NSNumber(value: $0) } as CFArray
        guard let array = CGSCopySpacesForWindows(connection.id, mask.rawValue, windows)?.takeRetainedValue() else { return [] }
        return spaceIDs(from: array)
    }

    /// The type of a space.
    public static func type(of sid: CGSSpaceID, connection: CGSConnection = .main) -> CGSSpaceType? {
        CGSSpaceType(rawValue: CGSSpaceGetType(connection.id, sid))
    }

    /// Move windows onto the given spaces.
    public static func add(windows windowIDs: [CGWindowID], to spaceIDs: [CGSSpaceID], connection: CGSConnection = .main) {
        let windows = windowIDs.map { NSNumber(value: $0) } as CFArray
        let spaces = spaceIDs.map { NSNumber(value: $0) } as CFArray
        CGSAddWindowsToSpaces(connection.id, windows, spaces)
    }

    /// Remove windows from the given spaces.
    public static func remove(windows windowIDs: [CGWindowID], from spaceIDs: [CGSSpaceID], connection: CGSConnection = .main) {
        let windows = windowIDs.map { NSNumber(value: $0) } as CFArray
        let spaces = spaceIDs.map { NSNumber(value: $0) } as CFArray
        CGSRemoveWindowsFromSpaces(connection.id, windows, spaces)
    }

    private static func spaceIDs(from array: CFArray) -> [CGSSpaceID] {
        ((array as NSArray) as? [Any] ?? []).compactMap { element in
            (element as? NSNumber)?.intValue
        }
    }
}
