//
//  Image+ColorManaged.swift
//  PureDraw
//

public extension Image {
    /// Colour-manages this image's pixels from `source` to `destination`, the `CGImage` colour-space
    /// conversion analog: every pixel's device RGB is mapped through the source profile to the shared PCS
    /// and back through the destination, so the image keeps its appearance across the two colour spaces.
    /// Alpha is carried through unchanged. The result is an opaque-format premultiplied RGBA image that
    /// draws on every backend. Returns `nil` if either profile is not a matrix-RGB profile.
    func colorManaged(from source: ICCProfile, to destination: ICCProfile) -> Image? {
        guard source.isMatrixRGB, destination.isMatrixRGB else { return nil }

        func byte(_ value: Double) -> UInt8 {
            UInt8(min(255, max(0, Int(value * 255 + 0.5))))
        }

        var bytes = [UInt8]()
        bytes.reserveCapacity(width * height * 4)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let color = pixelColor(x: x, y: y)
                let converted = source.convert(red: color.red, green: color.green, blue: color.blue, to: destination)
                let red = converted?.red ?? color.red
                let green = converted?.green ?? color.green
                let blue = converted?.blue ?? color.blue
                // Store premultiplied by the unchanged alpha.
                let alpha = color.alpha
                bytes.append(byte(red * alpha))
                bytes.append(byte(green * alpha))
                bytes.append(byte(blue * alpha))
                bytes.append(byte(alpha))
            }
        }

        return try? Image(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            colorSpace: .deviceRGB,
            alphaInfo: .premultipliedLast,
            data: bytes
        )
    }
}
