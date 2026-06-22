//
//  Image.swift
//  PureDraw
//

import Validation

/// Represents a raw bitmap image buffer with layout configuration.
public struct Image: Sendable, Equatable {
    /// The width in pixels.
    public let width: Int
    /// The height in pixels.
    public let height: Int
    /// The number of bits per color component.
    public let bitsPerComponent: Int
    /// The number of bits per pixel (all components plus any alpha).
    public let bitsPerPixel: Int
    /// The number of bytes per row of pixels, including any row padding.
    public let bytesPerRow: Int
    /// The color space the pixel components are interpreted in.
    public let colorSpace: ColorSpace
    /// How the alpha channel is stored and whether it is premultiplied.
    public let alphaInfo: AlphaInfo
    /// Optional color or color-range to treat as transparent (chroma key), if any.
    public let maskingColors: [Double]?
    /// Optional per-color-component decode array, the `CGImage` `decode` parameter: two values
    /// `[min, max]` per color component (alpha is never decoded), remapping each sampled component
    /// from `[0, 1]` onto `[min, max]`. `nil` is the identity decode. A reversed pair `[1, 0]`
    /// inverts the component.
    public let decode: [Double]?
    /// The indexed (palette) color space, if this image's samples are palette indices rather than
    /// color components. When set, each 8-bit sample is an index resolved through the palette; the
    /// base space and per-entry alpha come from the palette colors. `nil` is an ordinary direct-color
    /// image.
    public let indexedColorSpace: IndexedColorSpace?
    /// The raw pixel bytes, laid out per the other fields.
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
        decode: [Double]? = nil,
        indexedColorSpace: IndexedColorSpace? = nil,
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
        self.decode = decode
        self.indexedColorSpace = indexedColorSpace
        self.data = data
    }
}

extension Image: Validatable {
    /// Validates that the dimensions and layout are positive and consistent with the buffer size.
    public static var defaultValidator: Validator<Image> {
        Validator()
            .validating(.imageIsValid)
    }
}

public extension Image {
    /// Decodes the color of a single pixel, honoring color space, alpha layout, row padding, and masking colors.
    func pixelColor(x: Int, y: Int) -> Color {
        let bytesPerPixel = bitsPerPixel / 8
        let pixelStart = y * bytesPerRow + x * bytesPerPixel
        guard pixelStart + bytesPerPixel <= data.count else { return .clear }

        // An indexed image's sample is a palette index, not a color component: read the 8-bit index and
        // resolve it through the table, whose entries carry their own color and alpha. Sub-byte
        // (1/2/4-bit) indices are not yet unpacked (#133/#135).
        if let indexed = indexedColorSpace {
            return indexed.color(at: Int(data[pixelStart]))
        }

        let alphaFirst = alphaInfo.isAlphaFirst
        let hasAlpha = alphaInfo.hasAlpha

        let componentCount = switch colorSpace {
        case .deviceGray: 1
        case .deviceRGB: 3
        case .deviceCMYK: 4
        }

        // Width of one component in bytes. Only whole-byte depths are decoded here; sub-byte
        // (1/2/4-bit) and indexed bitmaps depend on the indexed colour-space work (#133).
        let bytesPerComponent: Int = switch bitsPerComponent {
        case 16, 32: bitsPerComponent / 8
        default: 1
        }

        /// Reads the slot-th component of this pixel as a normalized value. Components are laid out in
        /// order with the alpha (or skipped byte) first or last; `slot` indexes that physical order.
        /// 8-bit is `byte / 255`, 16-bit big-endian is `word / 65535`, 32-bit is an IEEE float in host
        /// (little-endian) order, the `kCGBitmapFloatComponents` layout, which may exceed 1 for HDR.
        func readNormalized(slot: Int) -> Double {
            let offset = pixelStart + slot * bytesPerComponent
            guard offset + bytesPerComponent <= data.count else { return 0 }
            switch bitsPerComponent {
            case 16:
                let value = (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
                return Double(value) / 65535.0
            case 32:
                let bits = UInt32(data[offset])
                    | (UInt32(data[offset + 1]) << 8)
                    | (UInt32(data[offset + 2]) << 16)
                    | (UInt32(data[offset + 3]) << 24)
                return Double(Float(bitPattern: bits))
            default:
                return Double(data[offset]) / 255.0
            }
        }

        // Physical slots: when alpha (or a skipped byte) is first, the color components follow it.
        let colorSlotBase = alphaFirst ? 1 : 0
        var rawComponents: [Double] = []
        rawComponents.reserveCapacity(componentCount)
        for component in 0 ..< componentCount {
            var value = readNormalized(slot: colorSlotBase + component)
            // The decode array remaps each color component from [0, 1] onto [min, max]; alpha is
            // never decoded. A reversed pair inverts the component.
            if let decode, decode.count >= 2 * (component + 1) {
                let lower = decode[2 * component]
                let upper = decode[2 * component + 1]
                value = lower + value * (upper - lower)
            }
            rawComponents.append(value)
        }

        var rawAlpha = 1.0
        if hasAlpha {
            // Alpha sits before the color components (first) or after them (last).
            let alphaSlot = alphaFirst ? 0 : componentCount
            rawAlpha = readNormalized(slot: alphaSlot)
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

    /// Returns the sub-image covering the given pixel rectangle, or `nil` when the
    /// rectangle does not overlap the image. The requested rectangle is clamped to
    /// the image bounds first, so a partly out-of-bounds rectangle yields the
    /// overlapping portion rather than failing. The pixel layout (depth, color
    /// space, alpha, masking) is preserved; only `bytesPerRow` tightens to the new
    /// width. This is the analog of cropping a `CGImage` to a sub-rectangle.
    func cropped(x cropX: Int, y cropY: Int, width cropWidth: Int, height cropHeight: Int) -> Image? {
        guard cropWidth > 0, cropHeight > 0 else { return nil }
        let x0 = max(0, cropX)
        let y0 = max(0, cropY)
        // Compute the far edges without trapping: a request whose far edge overflows
        // Int extends past the image, so it clamps to the image bound.
        let (sumX, overflowX) = cropX.addingReportingOverflow(cropWidth)
        let (sumY, overflowY) = cropY.addingReportingOverflow(cropHeight)
        let x1 = overflowX ? width : min(width, sumX)
        let y1 = overflowY ? height : min(height, sumY)
        let croppedW = x1 - x0
        let croppedH = y1 - y0
        guard croppedW > 0, croppedH > 0 else { return nil }

        let bytesPerPixel = bitsPerPixel / 8
        let newBytesPerRow = croppedW * bytesPerPixel
        var newData = [UInt8](repeating: 0, count: croppedH * newBytesPerRow)
        for row in 0 ..< croppedH {
            let srcStart = (y0 + row) * bytesPerRow + x0 * bytesPerPixel
            let dstStart = row * newBytesPerRow
            newData.replaceSubrange(dstStart ..< dstStart + newBytesPerRow, with: data[srcStart ..< srcStart + newBytesPerRow])
        }
        return try? Image(
            width: croppedW,
            height: croppedH,
            bitsPerComponent: bitsPerComponent,
            bitsPerPixel: bitsPerPixel,
            bytesPerRow: newBytesPerRow,
            colorSpace: colorSpace,
            alphaInfo: alphaInfo,
            maskingColors: maskingColors,
            decode: decode,
            indexedColorSpace: indexedColorSpace,
            data: newData
        )
    }

    /// A copy of this image with its alpha modulated per pixel by `mask`, the analog of
    /// `CGImageCreateWithMask`. By default `mask` is a soft (alpha) mask: its coverage multiplies this
    /// image's alpha, so the image shows where the mask reveals and hides where it blocks. With
    /// `asImageMask` true the mask is a Core Graphics image mask, inverted, so the image is painted
    /// where the mask is dark and blocked where it is light. The mask is sampled to this image's
    /// dimensions; the result is an opaque-format RGBA image that draws on every backend.
    func masked(by mask: Image, asImageMask: Bool = false) -> Image? {
        func byte(_ value: Double) -> UInt8 {
            UInt8(min(255, max(0, Int(value * 255 + 0.5))))
        }
        var bytes = [UInt8]()
        bytes.reserveCapacity(width * height * 4)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let color = pixelColor(x: x, y: y)
                // Sample the mask at the matching normalized position (nearest).
                let u = (Double(x) + 0.5) / Double(width)
                let v = (Double(y) + 0.5) / Double(height)
                let maskX = min(mask.width - 1, max(0, Int(u * Double(mask.width))))
                let maskY = min(mask.height - 1, max(0, Int(v * Double(mask.height))))
                let coverage = mask.maskCoverage(x: maskX, y: maskY)
                let alpha = color.alpha * (asImageMask ? 1 - coverage : coverage)
                bytes.append(byte(color.red * alpha))
                bytes.append(byte(color.green * alpha))
                bytes.append(byte(color.blue * alpha))
                bytes.append(byte(alpha))
            }
        }
        return try? Image(width: width, height: height, alphaInfo: .premultipliedLast, data: bytes)
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
