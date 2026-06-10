//
//  Image.swift
//  PureDraw
//

import Validation

/// Represents a raw bitmap image buffer with layout configuration.
public struct Image: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let bitsPerComponent: Int
    public let bitsPerPixel: Int
    public let bytesPerRow: Int
    public let colorSpace: ColorSpace
    public let alphaInfo: AlphaInfo
    public let maskingColors: [Double]?
    public let data: [UInt8]

    /// Creates an image over the given pixel buffer.
    ///
    /// - Throws: `ValidationError` when `data` is smaller than `height * bytesPerRow`,
    ///   so an image whose buffer cannot back its declared layout is unrepresentable.
    public init(
        width: Int,
        height: Int,
        bitsPerComponent: Int = 8,
        bitsPerPixel: Int = 32,
        bytesPerRow: Int? = nil,
        colorSpace: ColorSpace = .deviceRGB,
        alphaInfo: AlphaInfo = .premultipliedLast,
        maskingColors: [Double]? = nil,
        data: [UInt8]
    ) throws {
        let computedBytesPerRow = bytesPerRow ?? (width * bitsPerPixel / 8)
        let minBytes = height * computedBytesPerRow
        guard data.count >= minBytes else {
            throw ValidationError(
                reason: "data buffer size is smaller than height * bytesPerRow",
                at: [ValidationCodingKey("data")]
            )
        }

        self.width = width
        self.height = height
        self.bitsPerComponent = bitsPerComponent
        self.bitsPerPixel = bitsPerPixel
        self.bytesPerRow = computedBytesPerRow
        self.colorSpace = colorSpace
        self.alphaInfo = alphaInfo
        self.maskingColors = maskingColors
        self.data = data
    }
}

extension Image: Validatable {
    public static var defaultValidator: Validator<Image> {
        Validator()
            .validating(.imageIsValid)
    }
}

public extension Image {
    /// Decodes the color of a single pixel, honoring color space, alpha layout, row padding, and masking colors.
    func pixelColor(x: Int, y: Int) -> Color {
        let bytesPerPixel = bitsPerPixel / 8
        let index = y * bytesPerRow + x * bytesPerPixel
        guard index + bytesPerPixel <= data.count else { return .clear }

        let alphaFirst = alphaInfo.isAlphaFirst
        let hasAlpha = alphaInfo.hasAlpha

        var rawComponents: [Double] = []
        var rawAlpha = 1.0

        switch colorSpace {
        case .deviceGray:
            if bytesPerPixel >= 2 {
                if alphaFirst {
                    rawAlpha = Double(data[index]) / 255.0
                    rawComponents = [Double(data[index + 1]) / 255.0]
                } else {
                    rawComponents = [Double(data[index]) / 255.0]
                    rawAlpha = Double(data[index + 1]) / 255.0
                }
            } else if bytesPerPixel == 1 {
                rawComponents = [Double(data[index]) / 255.0]
                rawAlpha = 1.0
            } else {
                return .clear
            }

        case .deviceRGB:
            if bytesPerPixel >= 4 {
                if alphaFirst {
                    rawAlpha = Double(data[index]) / 255.0
                    rawComponents = [
                        Double(data[index + 1]) / 255.0,
                        Double(data[index + 2]) / 255.0,
                        Double(data[index + 3]) / 255.0,
                    ]
                } else {
                    rawComponents = [
                        Double(data[index]) / 255.0,
                        Double(data[index + 1]) / 255.0,
                        Double(data[index + 2]) / 255.0,
                    ]
                    rawAlpha = Double(data[index + 3]) / 255.0
                }
            } else if bytesPerPixel == 3 {
                rawComponents = [
                    Double(data[index]) / 255.0,
                    Double(data[index + 1]) / 255.0,
                    Double(data[index + 2]) / 255.0,
                ]
                rawAlpha = 1.0
            } else {
                return .clear
            }

        case .deviceCMYK:
            if bytesPerPixel >= 5 {
                if alphaFirst {
                    rawAlpha = Double(data[index]) / 255.0
                    rawComponents = [
                        Double(data[index + 1]) / 255.0,
                        Double(data[index + 2]) / 255.0,
                        Double(data[index + 3]) / 255.0,
                        Double(data[index + 4]) / 255.0,
                    ]
                } else {
                    rawComponents = [
                        Double(data[index]) / 255.0,
                        Double(data[index + 1]) / 255.0,
                        Double(data[index + 2]) / 255.0,
                        Double(data[index + 3]) / 255.0,
                    ]
                    rawAlpha = Double(data[index + 4]) / 255.0
                }
            } else if bytesPerPixel >= 4 {
                rawComponents = [
                    Double(data[index]) / 255.0,
                    Double(data[index + 1]) / 255.0,
                    Double(data[index + 2]) / 255.0,
                    Double(data[index + 3]) / 255.0,
                ]
                rawAlpha = 1.0
            } else {
                return .clear
            }
        }

        // CoreGraphics applies masking colors only to images without alpha; match that here.
        if let masking = maskingColors, !hasAlpha, masking.count == rawComponents.count * 2 {
            var allMatch = true
            for i in 0 ..< rawComponents.count {
                let val = rawComponents[i]
                let minVal = masking[2 * i]
                let maxVal = masking[2 * i + 1]
                if val < minVal || val > maxVal {
                    allMatch = false
                    break
                }
            }
            if allMatch {
                return .clear
            }
        }

        let finalAlpha = hasAlpha ? rawAlpha : 1.0
        let isPremultiplied = alphaInfo.isPremultiplied

        switch colorSpace {
        case .deviceGray:
            let g = rawComponents[0]
            let finalGray = (isPremultiplied && finalAlpha > 0) ? (g / finalAlpha) : g
            return Color(gray: finalGray, alpha: finalAlpha)

        case .deviceRGB:
            let r = rawComponents[0]
            let g = rawComponents[1]
            let b = rawComponents[2]
            let finalR = (isPremultiplied && finalAlpha > 0) ? (r / finalAlpha) : r
            let finalG = (isPremultiplied && finalAlpha > 0) ? (g / finalAlpha) : g
            let finalB = (isPremultiplied && finalAlpha > 0) ? (b / finalAlpha) : b
            return Color(red: finalR, green: finalG, blue: finalB, alpha: finalAlpha)

        case .deviceCMYK:
            let c = rawComponents[0]
            let m = rawComponents[1]
            let y = rawComponents[2]
            let k = rawComponents[3]
            let finalC = (isPremultiplied && finalAlpha > 0) ? (c / finalAlpha) : c
            let finalM = (isPremultiplied && finalAlpha > 0) ? (m / finalAlpha) : m
            let finalY = (isPremultiplied && finalAlpha > 0) ? (y / finalAlpha) : y
            let finalK = (isPremultiplied && finalAlpha > 0) ? (k / finalAlpha) : k
            return Color(cyan: finalC, magenta: finalM, yellow: finalY, black: finalK, alpha: finalAlpha)
        }
    }

    /// Resolves the clip-mask coverage of a pixel: the alpha channel when the image has one, luminance otherwise.
    /// White (or opaque) reveals, black (or transparent) hides. The result is clamped to 0...1.
    func maskCoverage(x: Int, y: Int) -> Double {
        let color = pixelColor(x: x, y: y)
        let coverage = if alphaInfo.hasAlpha {
            color.alpha
        } else {
            0.2126 * color.red + 0.7152 * color.green + 0.0722 * color.blue
        }
        return min(1.0, max(0.0, coverage))
    }
}
