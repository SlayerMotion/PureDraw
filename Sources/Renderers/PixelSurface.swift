//
//  PixelSurface.swift
//  PureDraw
//

/// The rasterizer's pixel store, abstracted over component precision so the same compositing code can
/// accumulate into 8-bit bytes or 32-bit floats.
///
/// Pixels are premultiplied RGBA, four components per pixel, addressed by the byte-style index
/// `(y * width + x) * 4`. The byte backing quantizes on every write exactly as the original renderer
/// did, so an 8-bit render is byte-for-byte unchanged. The float backing keeps the full Double result
/// of each blend, so overlapping translucent draws no longer lose precision at each step and a smooth
/// gradient stays smooth, the point of a float bitmap output.
struct PixelSurface {
    /// Whether components are stored as full-precision floats rather than quantized bytes.
    let isFloat: Bool
    private var bytes: [UInt8]
    private var floats: [Double]

    /// Creates a zero-filled surface for `pixelCount` pixels.
    init(pixelCount: Int, float: Bool) {
        isFloat = float
        if float {
            floats = [Double](repeating: 0, count: pixelCount * 4)
            bytes = []
        } else {
            bytes = [UInt8](repeating: 0, count: pixelCount * 4)
            floats = []
        }
    }

    /// The premultiplied RGBA at `index` as normalized values.
    func read(_ index: Int) -> (r: Double, g: Double, b: Double, a: Double) {
        if isFloat {
            return (floats[index], floats[index + 1], floats[index + 2], floats[index + 3])
        }
        return (
            Double(bytes[index]) / 255.0,
            Double(bytes[index + 1]) / 255.0,
            Double(bytes[index + 2]) / 255.0,
            Double(bytes[index + 3]) / 255.0
        )
    }

    /// The premultiplied alpha at `index`, used by the layer/shadow silhouette readers.
    func alpha(_ index: Int) -> Double {
        isFloat ? floats[index + 3] : Double(bytes[index + 3]) / 255.0
    }

    /// Stores premultiplied RGBA at `index`. The byte backing quantizes (the original behavior); the
    /// float backing keeps the value, guarding only against a non-finite channel.
    mutating func write(_ index: Int, _ r: Double, _ g: Double, _ b: Double, _ a: Double) {
        if isFloat {
            floats[index] = Self.floatStore(r)
            floats[index + 1] = Self.floatStore(g)
            floats[index + 2] = Self.floatStore(b)
            floats[index + 3] = Self.floatStore(a)
        } else {
            bytes[index] = Self.toByte(r)
            bytes[index + 1] = Self.toByte(g)
            bytes[index + 2] = Self.toByte(b)
            bytes[index + 3] = Self.toByte(a)
        }
    }

    /// The output bytes for an ``Image``: the bytes as-is, or the floats serialized little-endian as
    /// 32-bit IEEE floats (the `kCGBitmapFloatComponents` layout `Image.pixelColor` decodes).
    func outputData() -> [UInt8] {
        if !isFloat { return bytes }
        var out = [UInt8]()
        out.reserveCapacity(floats.count * 4)
        for value in floats {
            let bits = Float(value).bitPattern
            out.append(UInt8(bits & 0xFF))
            out.append(UInt8((bits >> 8) & 0xFF))
            out.append(UInt8((bits >> 16) & 0xFF))
            out.append(UInt8((bits >> 24) & 0xFF))
        }
        return out
    }

    /// Quantizes a channel to a byte, clamping in Double space before the integer conversion so a
    /// non-finite or out-of-range channel degrades to a clamped byte instead of trapping. This is the
    /// renderer's original quantizer, kept identical so 8-bit output does not change.
    static func toByte(_ value: Double) -> UInt8 {
        let scaled = (value * 255.0).rounded()
        guard scaled.isFinite else { return 0 }
        return UInt8(min(255.0, max(0.0, scaled)))
    }

    /// Stores a float channel, mapping a non-finite value to 0 (transparent/black). The range is not
    /// clamped, so high-dynamic-range values above 1 are preserved.
    static func floatStore(_ value: Double) -> Double {
        value.isFinite ? value : 0
    }
}
