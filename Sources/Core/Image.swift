//
//  Image.swift
//  PureDraw
//

/// Represents a raw bitmap image buffer with layout configuration.
public struct Image: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let bitsPerComponent: Int
    public let bitsPerPixel: Int
    public let bytesPerRow: Int
    public let colorSpace: ColorSpace
    public let alphaInfo: AlphaInfo
    public let data: [UInt8]

    public init(
        width: Int,
        height: Int,
        bitsPerComponent: Int = 8,
        bitsPerPixel: Int = 32,
        bytesPerRow: Int? = nil,
        colorSpace: ColorSpace = .deviceRGB,
        alphaInfo: AlphaInfo = .premultipliedLast,
        data: [UInt8]
    ) {
        let computedBytesPerRow = bytesPerRow ?? (width * bitsPerPixel / 8)
        let minBytes = height * computedBytesPerRow
        precondition(data.count >= minBytes, "Data buffer is too small for the requested image dimensions and layout.")

        self.width = width
        self.height = height
        self.bitsPerComponent = bitsPerComponent
        self.bitsPerPixel = bitsPerPixel
        self.bytesPerRow = computedBytesPerRow
        self.colorSpace = colorSpace
        self.alphaInfo = alphaInfo
        self.data = data
    }
}
