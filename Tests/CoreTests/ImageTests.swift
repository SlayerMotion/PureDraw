//
//  ImageTests.swift
//  PureDraw
//

@testable import Core
import Geometry
import Testing

struct ImageTests {
    @Test func imageInitialization() {
        let width = 4
        let height = 4
        let bytesPerRow = width * 4
        let pixelData = [UInt8](repeating: 255, count: height * bytesPerRow)

        let image = Image(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            colorSpace: .deviceRGB,
            alphaInfo: .premultipliedLast,
            data: pixelData
        )

        #expect(image.width == width)
        #expect(image.height == height)
        #expect(image.bitsPerComponent == 8)
        #expect(image.bitsPerPixel == 32)
        #expect(image.bytesPerRow == bytesPerRow)
        #expect(image.colorSpace == .deviceRGB)
        #expect(image.alphaInfo == .premultipliedLast)
        #expect(image.data == pixelData)
    }

    @Test func imageDefaultArguments() {
        let width = 2
        let height = 2
        let correctData = [UInt8](repeating: 0, count: 16) // 2 * 2 * 4 = 16 bytes

        let image = Image(width: width, height: height, data: correctData)

        #expect(image.bitsPerComponent == 8)
        #expect(image.bitsPerPixel == 32)
        #expect(image.bytesPerRow == 8) // width * bitsPerPixel / 8 = 8
        #expect(image.colorSpace == .deviceRGB)
        #expect(image.alphaInfo == .premultipliedLast)
    }
}
