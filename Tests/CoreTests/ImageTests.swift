//
//  ImageTests.swift
//  PureDraw
//

@testable import Core
import Geometry
import Testing
import Validation

struct ImageTests {
    @Test func imageInitialization() throws {
        let width = 4
        let height = 4
        let bytesPerRow = width * 4
        let pixelData = [UInt8](repeating: 255, count: height * bytesPerRow)

        let image = try Image(
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

    @Test func imageDefaultArguments() throws {
        let width = 2
        let height = 2
        let correctData = [UInt8](repeating: 0, count: 16) // 2 * 2 * 4 = 16 bytes

        let image = try Image(width: width, height: height, data: correctData)

        #expect(image.bitsPerComponent == 8)
        #expect(image.bitsPerPixel == 32)
        #expect(image.bytesPerRow == 8) // width * bitsPerPixel / 8 = 8
        #expect(image.colorSpace == .deviceRGB)
        #expect(image.alphaInfo == .premultipliedLast)
    }

    @Test func imageValidation() throws {
        let correctData = [UInt8](repeating: 0, count: 16)
        let image = try Image(width: 2, height: 2, data: correctData)

        // A correct image must validate without throwing errors
        try image.validate()

        // Create an invalid image (negative dimension) and expect validation failure
        let invalidImage = try Image(width: -1, height: 2, bytesPerRow: 8, data: correctData)
        #expect(throws: ValidationErrorCollection.self) {
            try invalidImage.validate()
        }
    }

    @Test func undersizedBufferThrowsOnInit() {
        let tooSmall = [UInt8](repeating: 0, count: 15) // 2 * 2 * 4 = 16 bytes needed

        #expect(throws: ValidationError.self) {
            _ = try Image(width: 2, height: 2, data: tooSmall)
        }
    }

    @Test func nonEightBitComponentsFailValidation() throws {
        let data = [UInt8](repeating: 0, count: 32)
        let image = try Image(width: 2, height: 2, bitsPerComponent: 16, bitsPerPixel: 64, data: data)

        #expect(throws: ValidationErrorCollection.self) {
            try image.validate()
        }
    }
}
