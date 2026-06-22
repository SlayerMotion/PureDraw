//
//  ICCProfileWriter.swift
//  PureDraw
//

/// Writes a minimal matrix-RGB ICC profile (ICC.1): a 128-byte header, a tag table, and the
/// `wtpt`/`rXYZ`/`gXYZ`/`bXYZ` matrix tags with per-channel `curveType` gamma tone curves. The output
/// is a spec-valid display (`mntr`) RGB-to-XYZ profile that ``ICCProfileReader`` round-trips and that a
/// colour-managed consumer can read. Parametric (`para`) tone curves and LUT-based profiles are not
/// emitted; the gamma `curveType` covers the common case.
public struct ICCProfileWriter {
    public init() {}

    /// Builds the profile bytes for the given matrix columns, per-channel gamma, and media white point.
    public func write(
        redColumn: XYZColor,
        greenColumn: XYZColor,
        blueColumn: XYZColor,
        gamma: Double,
        whitePoint: XYZColor = XYZColor(x: 0.9642, y: 1.0, z: 0.8249),
        renderingIntent: Int = 1
    ) -> [UInt8] {
        // Tag layout: 7 tags after the table; XYZType is 20 bytes, a one-entry curveType padded to 16.
        let tagSignatures = ["wtpt", "rXYZ", "gXYZ", "bXYZ", "rTRC", "gTRC", "bTRC"]
        let tableStart = 128
        let dataStart = tableStart + 4 + tagSignatures.count * 12
        let xyzSize = 20, curveSize = 16

        var tagData: [UInt8] = []
        var offsets: [(offset: Int, size: Int)] = []
        func appendTag(_ bytes: [UInt8], size: Int) {
            offsets.append((dataStart + tagData.count, size))
            tagData.append(contentsOf: bytes)
        }
        appendTag(xyzType(whitePoint), size: xyzSize)
        appendTag(xyzType(redColumn), size: xyzSize)
        appendTag(xyzType(greenColumn), size: xyzSize)
        appendTag(xyzType(blueColumn), size: xyzSize)
        for _ in 0 ..< 3 {
            appendTag(gammaCurve(gamma), size: curveSize)
        }

        var output = [UInt8](repeating: 0, count: dataStart)
        // Header.
        writeSignature("mntr", into: &output, at: 12)
        writeSignature("RGB ", into: &output, at: 16)
        writeSignature("XYZ ", into: &output, at: 20)
        writeSignature("acsp", into: &output, at: 36)
        writeUInt32(0x0430_0000, into: &output, at: 8) // version 4.3
        writeUInt32(UInt32(renderingIntent), into: &output, at: 64)
        writeXYZ(XYZColor(x: 0.9642, y: 1.0, z: 0.8249), into: &output, at: 68) // PCS illuminant D50
        // Tag table.
        writeUInt32(UInt32(tagSignatures.count), into: &output, at: tableStart)
        for (index, signature) in tagSignatures.enumerated() {
            let entry = tableStart + 4 + index * 12
            writeSignature(signature, into: &output, at: entry)
            writeUInt32(UInt32(offsets[index].offset), into: &output, at: entry + 4)
            writeUInt32(UInt32(offsets[index].size), into: &output, at: entry + 8)
        }
        output.append(contentsOf: tagData)
        writeUInt32(UInt32(output.count), into: &output, at: 0) // profile size
        return output
    }

    // MARK: Typed elements

    private func xyzType(_ color: XYZColor) -> [UInt8] {
        var bytes = Array("XYZ ".utf8) + [0, 0, 0, 0]
        bytes.append(contentsOf: s15Fixed16(color.x))
        bytes.append(contentsOf: s15Fixed16(color.y))
        bytes.append(contentsOf: s15Fixed16(color.z))
        return bytes
    }

    private func gammaCurve(_ gamma: Double) -> [UInt8] {
        // curveType with one entry: the gamma as u8Fixed8. Padded to a 4-byte boundary.
        var bytes = Array("curv".utf8) + [0, 0, 0, 0]
        bytes.append(contentsOf: uint32Bytes(1))
        let fixed = UInt16(min(65535.0, max(0.0, (gamma * 256.0).rounded())))
        bytes.append(UInt8(fixed >> 8))
        bytes.append(UInt8(fixed & 0xFF))
        while bytes.count < 16 {
            bytes.append(0)
        }
        return bytes
    }

    // MARK: Big-endian primitives

    private func uint32Bytes(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }

    private func s15Fixed16(_ value: Double) -> [UInt8] {
        uint32Bytes(UInt32(bitPattern: Int32((value * 65536.0).rounded())))
    }

    private func writeUInt32(_ value: UInt32, into data: inout [UInt8], at offset: Int) {
        let bytes = uint32Bytes(value)
        for i in 0 ..< 4 {
            data[offset + i] = bytes[i]
        }
    }

    private func writeSignature(_ signature: String, into data: inout [UInt8], at offset: Int) {
        let bytes = Array(signature.utf8)
        for i in 0 ..< min(4, bytes.count) {
            data[offset + i] = bytes[i]
        }
    }

    private func writeXYZ(_ color: XYZColor, into data: inout [UInt8], at offset: Int) {
        let bytes = s15Fixed16(color.x) + s15Fixed16(color.y) + s15Fixed16(color.z)
        for i in 0 ..< 12 {
            data[offset + i] = bytes[i]
        }
    }
}
