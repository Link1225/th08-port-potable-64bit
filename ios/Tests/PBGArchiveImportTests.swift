import Foundation

@main
enum PBGArchiveImportTests {
    static func main() throws {
        let table = makeTable([
            ("a.bin", 16, 4, 0),
            ("b.bin", 32, 8, 7)
        ])
        let compressed = encodeLiteralLZSS(table)
        let decoded = try TH08DataArchiveImport.decodeLZSS(
            Data(compressed),
            expectedSize: table.count
        )
        precondition(decoded == table, "LZSS literal round-trip failed")

        let retailEOFCompressed = Array(compressed.dropLast())
        let retailEOFDecoded = try TH08DataArchiveImport.decodeLZSS(
            Data(retailEOFCompressed),
            expectedSize: table.count
        )
        precondition(retailEOFDecoded == table, "Retail LZSS zero-padding at EOF failed")

        let decryptedHeaderVector = TH08DataArchiveImport.decryptPBGBytes(
            Array(UInt8(0)...UInt8(11)),
            xorValue: 0x1b,
            xorIncrement: 0x37,
            chunkSize: 12,
            maximumBytes: 0x400
        )
        precondition(
            decryptedHeaderVector == [115, 43, 75, 243, 3, 195, 219, 139, 155, 83, 99, 27],
            "PBG header decryption vector failed"
        )

        // Exercise odd/even tails, partial chunks, and the retail 0x400-byte
        // decryption limit using deterministic payloads of varied lengths.
        for chunkSize in [12, 0x80] {
            for count in [1, 2, 3, 11, 12, 13, 24, 25, 127, 128, 129, 255, 256, 257, 1023, 1024, 1025, 2049] {
                let source = (0..<count).map {
                    UInt8(truncatingIfNeeded: $0 &* 37 &+ count &* 11)
                }
                let encrypted = TH08DataArchiveImport.encryptPBGBytes(
                    source,
                    xorValue: 0x3e,
                    xorIncrement: 0x9b,
                    chunkSize: chunkSize,
                    maximumBytes: 0x400
                )
                let decrypted = TH08DataArchiveImport.decryptPBGBytes(
                    encrypted,
                    xorValue: 0x3e,
                    xorIncrement: 0x9b,
                    chunkSize: chunkSize,
                    maximumBytes: 0x400
                )
                precondition(
                    decrypted == source,
                    "PBG rolling XOR round-trip failed for size \\(count), chunk \\(chunkSize)"
                )
            }
        }

        let archive = makeRetailPBGArchive()
        let archiveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("th08-pbg-test-\(UUID().uuidString).dat")
        try Data(archive).write(to: archiveURL)
        defer { try? FileManager.default.removeItem(at: archiveURL) }
        try TH08DataArchiveImport.validatePBGArchive(
            at: archiveURL,
            fileSize: Int64(archive.count),
            name: "synthetic-th08.dat"
        )

        let pairDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("th08-pbg-pair-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: pairDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: pairDirectory) }
        try Data(archive).write(to: pairDirectory.appendingPathComponent("th08.dat"))
        try Data(archive).write(to: pairDirectory.appendingPathComponent("thbgm.dat"))
        try TH08DataArchiveImport.validatePair(at: pairDirectory)
        try FileManager.default.removeItem(at: pairDirectory.appendingPathComponent("thbgm.dat"))
        expectFailure("incomplete installed archive pair") {
            try TH08DataArchiveImport.validatePair(at: pairDirectory)
        }

        var damagedArchive = archive
        damagedArchive[0] ^= 0xff
        let damagedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("th08-pbg-damaged-\(UUID().uuidString).dat")
        try Data(damagedArchive).write(to: damagedURL)
        defer { try? FileManager.default.removeItem(at: damagedURL) }
        expectFailure("invalid retail PBG signature") {
            try TH08DataArchiveImport.validatePBGArchive(
                at: damagedURL,
                fileSize: Int64(damagedArchive.count),
                name: "damaged.dat"
            )
        }

        let repeatedBytes = try TH08DataArchiveImport.decodeLZSS(
            Data(encodeBackReferenceLZSS()),
            expectedSize: 4
        )
        precondition(repeatedBytes == Array("AAAA".utf8), "LZSS back-reference decoding failed")

        try TH08DataArchiveImport.validateFileTable(
            decoded,
            entryCount: 2,
            dataStart: 16,
            tableOffset: 96,
            fileSize: 128
        )

        expectFailure("wrong declared output size") {
            _ = try TH08DataArchiveImport.decodeLZSS(
                Data(compressed),
                expectedSize: table.count - 1
            )
        }

        expectFailure("truncated LZSS payload") {
            _ = try TH08DataArchiveImport.decodeLZSS(
                Data(compressed.dropLast(3)),
                expectedSize: table.count
            )
        }

        let descendingOffsets = makeTable([
            ("a.bin", 32, 4, 0),
            ("b.bin", 16, 8, 0)
        ])
        expectFailure("descending payload offsets") {
            try TH08DataArchiveImport.validateFileTable(
                descendingOffsets,
                entryCount: 2,
                dataStart: 16,
                tableOffset: 96,
                fileSize: 128
            )
        }

        let payloadStartsAtTable = makeTable([
            ("a.bin", 96, 4, 0)
        ])
        expectFailure("payload starts inside file table") {
            try TH08DataArchiveImport.validateFileTable(
                payloadStartsAtTable,
                entryCount: 1,
                dataStart: 16,
                tableOffset: 96,
                fileSize: 128
            )
        }
        print("PBG archive import tests passed")
    }

    private static func makeRetailPBGArchive() -> [UInt8] {
        let entries: [(String, UInt32, UInt32, UInt32)] = [
            ("a.bin", 16, 4, 0),
            ("b.bin", 32, 4, 0),
            ("c.bin", 48, 4, 0),
            ("d.bin", 64, 4, 0)
        ]
        let table = makeTable(entries)
        let compressedTable = encodeLiteralLZSS(table)
        let tableOffset: UInt32 = 128
        let encryptedTable = TH08DataArchiveImport.encryptPBGBytes(
            compressedTable,
            xorValue: 0x3e,
            xorIncrement: 0x9b,
            chunkSize: 0x80,
            maximumBytes: 0x400
        )

        var header = [UInt8]()
        appendUInt32LE(UInt32(entries.count) + 123_456, to: &header)
        appendUInt32LE(tableOffset + 345_678, to: &header)
        appendUInt32LE(UInt32(table.count) + 567_891, to: &header)
        let encryptedHeader = TH08DataArchiveImport.encryptPBGBytes(
            header,
            xorValue: 0x1b,
            xorIncrement: 0x37,
            chunkSize: 12,
            maximumBytes: 0x400
        )

        var archive = Array("PBGZ".utf8)
        archive.append(contentsOf: encryptedHeader)
        archive.append(contentsOf: repeatElement(0, count: Int(tableOffset) - archive.count))
        archive.append(contentsOf: encryptedTable)
        return archive
    }

    private static func makeTable(_ entries: [(String, UInt32, UInt32, UInt32)]) -> [UInt8] {
        var bytes = [UInt8]()
        for (name, offset, size, metadata) in entries {
            bytes.append(contentsOf: name.utf8)
            bytes.append(0)
            appendUInt32LE(offset, to: &bytes)
            appendUInt32LE(size, to: &bytes)
            appendUInt32LE(metadata, to: &bytes)
        }
        return bytes
    }

    private static func appendUInt32LE(_ value: UInt32, to bytes: inout [UInt8]) {
        bytes.append(UInt8(value & 0xff))
        bytes.append(UInt8((value >> 8) & 0xff))
        bytes.append(UInt8((value >> 16) & 0xff))
        bytes.append(UInt8((value >> 24) & 0xff))
    }

    private static func encodeBackReferenceLZSS() -> [UInt8] {
        var output = [UInt8]()
        var current: UInt8 = 0
        var mask: UInt8 = 0x80

        func writeBit(_ bit: UInt8) {
            if bit != 0 { current |= mask }
            mask >>= 1
            if mask == 0 {
                output.append(current)
                current = 0
                mask = 0x80
            }
        }

        func writeBits(_ value: Int, count: Int) {
            for shift in stride(from: count - 1, through: 0, by: -1) {
                writeBit(UInt8((value >> shift) & 1))
            }
        }

        writeBit(1)
        writeBits(0x41, count: 8)
        writeBit(0)
        writeBits(1, count: 13)
        writeBits(0, count: 4)
        writeBit(0)
        writeBits(0, count: 13)
        return output
    }

    private static func encodeLiteralLZSS(_ bytes: [UInt8]) -> [UInt8] {
        var output = [UInt8]()
        var current: UInt8 = 0
        var mask: UInt8 = 0x80

        func writeBit(_ bit: UInt8) {
            if bit != 0 { current |= mask }
            mask >>= 1
            if mask == 0 {
                output.append(current)
                current = 0
                mask = 0x80
            }
        }

        for byte in bytes {
            writeBit(1)
            for shift in stride(from: 7, through: 0, by: -1) {
                writeBit((byte >> shift) & 1)
            }
        }

        // A zero flag followed by a zero 13-bit offset terminates the stream.
        // Match the retail encoder: do not flush a partially filled final byte.
        for _ in 0..<14 { writeBit(0) }
        return output
    }

    private static func expectFailure(_ label: String, _ body: () throws -> Void) {
        do {
            try body()
            fatalError("Expected failure: \(label)")
        } catch {
            // Expected malformed-input rejection.
        }
    }
}
