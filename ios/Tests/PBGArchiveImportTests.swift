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

        expectFailure("missing LZSS terminator") {
            _ = try TH08DataArchiveImport.decodeLZSS(
                Data(compressed.dropLast()),
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
        print("PBG archive import tests passed")
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
        if mask != 0x80 { output.append(current) }
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
        for _ in 0..<14 { writeBit(0) }
        if mask != 0x80 { output.append(current) }
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
