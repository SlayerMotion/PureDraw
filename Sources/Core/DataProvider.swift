//
//  DataProvider.swift
//  PureDraw
//

/// Supplies raw bytes from an arbitrary source (in-memory buffers, generated
/// content, platform file APIs) so consumers of graphics data never depend on
/// where the bytes live. The `CGDataProvider` equivalent.
public struct DataProvider: Sendable {
    private let loader: @Sendable () throws -> [UInt8]

    /// A provider over an in-memory buffer.
    public init(data: [UInt8]) {
        loader = { data }
    }

    /// A provider that produces its bytes on demand. The loader runs on every
    /// call to `data()`; wrap it in your own cache if loading is expensive.
    public init(_ loader: @escaping @Sendable () throws -> [UInt8]) {
        self.loader = loader
    }

    /// Loads the underlying bytes.
    public func data() throws -> [UInt8] {
        try loader()
    }
}

public extension Image {
    /// Creates an image whose pixel data comes from a provider.
    init(
        width: Int,
        height: Int,
        bitsPerComponent: Int = 8,
        bitsPerPixel: Int = 32,
        bytesPerRow: Int? = nil,
        colorSpace: ColorSpace = .deviceRGB,
        alphaInfo: AlphaInfo = .premultipliedLast,
        maskingColors: [Double]? = nil,
        provider: DataProvider
    ) throws {
        try self.init(
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bitsPerPixel: bitsPerPixel,
            bytesPerRow: bytesPerRow,
            colorSpace: colorSpace,
            alphaInfo: alphaInfo,
            maskingColors: maskingColors,
            data: provider.data()
        )
    }
}
