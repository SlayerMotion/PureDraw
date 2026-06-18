//
//  PDFEncryption.swift
//  PureDraw
//

/// Settings for PDF standard-security-handler encryption (revision 2,
/// 40-bit RC4), the writer-side counterpart of unlocking with
/// `CGPDFDocumentUnlockWithPassword`. This is a compatibility feature, not
/// modern cryptography: it gates viewers on a password and carries the
/// permission flags below, exactly as PDF 1.4 defines them.
public struct PDFEncryption: Equatable, Sendable {
    /// User-permission flags carried in the document's /P entry.
    public struct Permissions: OptionSet, Equatable, Sendable {
        /// The PDF /P permission bit mask.
        public let rawValue: UInt32

        /// Creates a permission set from its raw bit mask.
        public init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        /// Allows printing the document.
        public static let printing = Permissions(rawValue: 1 << 2)
        /// Allows modifying the document's contents.
        public static let modifying = Permissions(rawValue: 1 << 3)
        /// Allows copying text and graphics out of the document.
        public static let copying = Permissions(rawValue: 1 << 4)
        /// Allows adding or modifying annotations and form fields.
        public static let annotating = Permissions(rawValue: 1 << 5)
        /// All of the above permissions.
        public static let all: Permissions = [.printing, .modifying, .copying, .annotating]
    }

    /// The password viewers must supply (empty means open without prompt).
    public let userPassword: String
    /// The owner password; defaults to the user password.
    public let ownerPassword: String
    /// The operations a viewer is permitted to perform.
    public let permissions: Permissions

    /// Creates an encryption configuration from the user and owner passwords and the permissions.
    public init(userPassword: String = "", ownerPassword: String? = nil, permissions: Permissions = .all) {
        self.userPassword = userPassword
        self.ownerPassword = ownerPassword ?? userPassword
        self.permissions = permissions
    }

    /// The signed /P value: permission bits over the reserved-ones mask.
    var permissionsValue: Int32 {
        Int32(bitPattern: 0xFFFF_FFC0 | permissions.rawValue)
    }

    /// Derives the document keys. The file identifier must already be chosen.
    func prepare(fileID: [UInt8]) -> Prepared {
        let paddedUser = Self.padded(userPassword)
        let paddedOwner = Self.padded(ownerPassword)

        // /O: the user password encrypted under a key from the owner password.
        let ownerKey = Array(Self.md5(paddedOwner)[0 ..< 5])
        let oValue = Self.rc4(key: ownerKey, paddedUser)

        // File key: MD5 over padded user password, /O, /P, and the file ID.
        var keyInput = paddedUser + oValue
        let p = UInt32(bitPattern: permissionsValue)
        keyInput.append(contentsOf: [
            UInt8(p & 0xFF), UInt8((p >> 8) & 0xFF), UInt8((p >> 16) & 0xFF), UInt8((p >> 24) & 0xFF),
        ])
        keyInput += fileID
        let fileKey = Array(Self.md5(keyInput)[0 ..< 5])

        // /U: the padding string encrypted under the file key.
        let uValue = Self.rc4(key: fileKey, Self.passwordPad)

        return Prepared(fileKey: fileKey, oValue: oValue, uValue: uValue, permissionsValue: permissionsValue, fileID: fileID)
    }

    /// Derived encryption state for one document.
    struct Prepared {
        let fileKey: [UInt8]
        let oValue: [UInt8]
        let uValue: [UInt8]
        let permissionsValue: Int32
        let fileID: [UInt8]

        /// Encrypts string or stream bytes for the given object.
        func encrypt(_ bytes: [UInt8], objectID: Int, generation: Int = 0) -> [UInt8] {
            var keyInput = fileKey
            keyInput.append(contentsOf: [
                UInt8(objectID & 0xFF), UInt8((objectID >> 8) & 0xFF), UInt8((objectID >> 16) & 0xFF),
                UInt8(generation & 0xFF), UInt8((generation >> 8) & 0xFF),
            ])
            let objectKey = Array(PDFEncryption.md5(keyInput)[0 ..< min(fileKey.count + 5, 16)])
            return PDFEncryption.rc4(key: objectKey, bytes)
        }
    }

    // MARK: - Standard Security Handler Primitives

    /// The 32-byte padding string from the PDF specification.
    static let passwordPad: [UInt8] = [
        0x28, 0xBF, 0x4E, 0x5E, 0x4E, 0x75, 0x8A, 0x41, 0x64, 0x00, 0x4E, 0x56, 0xFF, 0xFA, 0x01, 0x08,
        0x2E, 0x2E, 0x00, 0xB6, 0xD0, 0x68, 0x3E, 0x80, 0x2F, 0x0C, 0xA9, 0xFE, 0x64, 0x53, 0x69, 0x7A,
    ]

    static func padded(_ password: String) -> [UInt8] {
        let bytes = Array(password.utf8).prefix(32)
        return Array(bytes) + Array(passwordPad[0 ..< (32 - bytes.count)])
    }

    static func rc4(key: [UInt8], _ data: [UInt8]) -> [UInt8] {
        var s = Array(UInt8(0) ... UInt8(255))
        var j = 0
        for i in 0 ..< 256 {
            j = (j + Int(s[i]) + Int(key[i % key.count])) & 0xFF
            s.swapAt(i, j)
        }
        var output = [UInt8]()
        output.reserveCapacity(data.count)
        var i = 0
        j = 0
        for byte in data {
            i = (i + 1) & 0xFF
            j = (j + Int(s[i])) & 0xFF
            s.swapAt(i, j)
            output.append(byte ^ s[(Int(s[i]) + Int(s[j])) & 0xFF])
        }
        return output
    }

    static func md5(_ message: [UInt8]) -> [UInt8] {
        let shifts: [UInt32] = [
            7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
            5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
            4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
            6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
        ]
        let table: [UInt32] = [
            0xD76A_A478, 0xE8C7_B756, 0x2420_70DB, 0xC1BD_CEEE,
            0xF57C_0FAF, 0x4787_C62A, 0xA830_4613, 0xFD46_9501,
            0x6980_98D8, 0x8B44_F7AF, 0xFFFF_5BB1, 0x895C_D7BE,
            0x6B90_1122, 0xFD98_7193, 0xA679_438E, 0x49B4_0821,
            0xF61E_2562, 0xC040_B340, 0x265E_5A51, 0xE9B6_C7AA,
            0xD62F_105D, 0x0244_1453, 0xD8A1_E681, 0xE7D3_FBC8,
            0x21E1_CDE6, 0xC337_07D6, 0xF4D5_0D87, 0x455A_14ED,
            0xA9E3_E905, 0xFCEF_A3F8, 0x676F_02D9, 0x8D2A_4C8A,
            0xFFFA_3942, 0x8771_F681, 0x6D9D_6122, 0xFDE5_380C,
            0xA4BE_EA44, 0x4BDE_CFA9, 0xF6BB_4B60, 0xBEBF_BC70,
            0x289B_7EC6, 0xEAA1_27FA, 0xD4EF_3085, 0x0488_1D05,
            0xD9D4_D039, 0xE6DB_99E5, 0x1FA2_7CF8, 0xC4AC_5665,
            0xF429_2244, 0x432A_FF97, 0xAB94_23A7, 0xFC93_A039,
            0x655B_59C3, 0x8F0C_CC92, 0xFFEF_F47D, 0x8584_5DD1,
            0x6FA8_7E4F, 0xFE2C_E6E0, 0xA301_4314, 0x4E08_11A1,
            0xF753_7E82, 0xBD3A_F235, 0x2AD7_D2BB, 0xEB86_D391,
        ]

        var padded = message
        let bitLength = UInt64(message.count) * 8
        padded.append(0x80)
        while padded.count % 64 != 56 {
            padded.append(0)
        }
        for shift in stride(from: 0, to: 64, by: 8) {
            padded.append(UInt8((bitLength >> UInt64(shift)) & 0xFF))
        }

        var a0: UInt32 = 0x6745_2301
        var b0: UInt32 = 0xEFCD_AB89
        var c0: UInt32 = 0x98BA_DCFE
        var d0: UInt32 = 0x1032_5476

        for chunkStart in stride(from: 0, to: padded.count, by: 64) {
            var words = [UInt32](repeating: 0, count: 16)
            for wordIndex in 0 ..< 16 {
                let base = chunkStart + wordIndex * 4
                words[wordIndex] = UInt32(padded[base])
                    | (UInt32(padded[base + 1]) << 8)
                    | (UInt32(padded[base + 2]) << 16)
                    | (UInt32(padded[base + 3]) << 24)
            }

            var a = a0
            var b = b0
            var c = c0
            var d = d0

            for round in 0 ..< 64 {
                var f: UInt32
                var g: Int
                switch round {
                case 0 ..< 16:
                    f = (b & c) | (~b & d)
                    g = round
                case 16 ..< 32:
                    f = (d & b) | (~d & c)
                    g = (5 * round + 1) % 16
                case 32 ..< 48:
                    f = b ^ c ^ d
                    g = (3 * round + 5) % 16
                default:
                    f = c ^ (b | ~d)
                    g = (7 * round) % 16
                }
                f = f &+ a &+ table[round] &+ words[g]
                a = d
                d = c
                c = b
                b = b &+ ((f << shifts[round]) | (f >> (32 - shifts[round])))
            }

            a0 = a0 &+ a
            b0 = b0 &+ b
            c0 = c0 &+ c
            d0 = d0 &+ d
        }

        var digest = [UInt8]()
        digest.reserveCapacity(16)
        for value in [a0, b0, c0, d0] {
            digest.append(UInt8(value & 0xFF))
            digest.append(UInt8((value >> 8) & 0xFF))
            digest.append(UInt8((value >> 16) & 0xFF))
            digest.append(UInt8((value >> 24) & 0xFF))
        }
        return digest
    }
}
