import Foundation

enum TH08DataArchiveImport {
    static let requiredNames: Set<String> = ["th08.dat", "thbgm.dat"]
    // PbgArchive::ParseHeader compares a little-endian ReadInt() with the
    // multi-character constant 'ZGBP'; the bytes on disk are therefore PBGZ.
    private static let archiveMagic = Data("PBGZ".utf8)
    private static let pbgHeaderSize = 12
    private static let maximumEntryCount: Int64 = 100_000
    private static let maximumFileTableSize: Int64 = 128 * 1024 * 1024

    enum ImportError: LocalizedError {
        case missingFiles
        case unexpectedFiles
        case emptyFile(String)
        case invalidArchive(String)
        case cannotAccessFile(String)
        case transactionFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingFiles:
                return "Select both th08.dat and thbgm.dat."
            case .unexpectedFiles:
                return "The selection must contain only th08.dat and thbgm.dat."
            case .emptyFile(let name):
                return "\(name) is empty."
            case .invalidArchive(let name):
                return "\(name) does not contain a valid PBG archive."
            case .cannotAccessFile(let name):
                return "Could not access \(name)."
            case .transactionFailed(let message):
                return "Import failed: \(message)"
            }
        }
    }

    /// Imports the user's original archives as one directory-level transaction.
    /// Existing archives remain in place unless both files are staged.
    static func installPair(from urls: [URL]) throws -> URL {
        let selectedNames = urls.map { $0.lastPathComponent }
        guard Set(selectedNames) == requiredNames, urls.count == requiredNames.count else {
            let selected = Set(selectedNames)
            if !requiredNames.isSubset(of: selected) {
                throw ImportError.missingFiles
            }
            throw ImportError.unexpectedFiles
        }

        let filesByName = Dictionary(uniqueKeysWithValues: urls.map {
            ($0.lastPathComponent, $0)
        })

        let fileManager = FileManager.default
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let destination = support.appendingPathComponent("TH08Data", isDirectory: true)
        let staging = support.appendingPathComponent(
            "TH08Data.staging.\(UUID().uuidString)",
            isDirectory: true
        )
        let backup = support.appendingPathComponent(
            "TH08Data.backup.\(UUID().uuidString)",
            isDirectory: true
        )

        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        var preserveBackup = false
        defer {
            try? fileManager.removeItem(at: staging)
            if !preserveBackup {
                try? fileManager.removeItem(at: backup)
            }
        }

        for name in requiredNames.sorted() {
            guard let source = filesByName[name] else {
                throw ImportError.missingFiles
            }

            let didStartAccess = source.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess {
                    source.stopAccessingSecurityScopedResource()
                }
            }

            guard fileManager.isReadableFile(atPath: source.path) else {
                throw ImportError.cannotAccessFile(name)
            }

            let values = try source.resourceValues(forKeys: [.fileSizeKey])
            guard let size = values.fileSize, size > 0 else {
                throw ImportError.emptyFile(name)
            }

            try validatePBGArchive(at: source, fileSize: Int64(size), name: name)

            let stagedFile = staging.appendingPathComponent(name)
            do {
                try fileManager.copyItem(at: source, to: stagedFile)
            } catch {
                throw ImportError.transactionFailed(error.localizedDescription)
            }
        }

        var movedOldDirectory = false
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.moveItem(at: destination, to: backup)
            movedOldDirectory = true
        }

        do {
            try fileManager.moveItem(at: staging, to: destination)
        } catch {
            if movedOldDirectory {
                do {
                    try fileManager.moveItem(at: backup, to: destination)
                } catch {
                    preserveBackup = true
                }
            }
            throw ImportError.transactionFailed(error.localizedDescription)
        }

        return destination
    }

    /// Validates the retail PBG signature, encrypted header, compressed file
    /// table, and entry boundaries before the pair is installed. Asset payloads
    /// remain compressed and are decoded by the game engine at load time.
    private static func validatePBGArchive(at url: URL, fileSize: Int64, name: String) throws {
        guard fileSize >= Int64(archiveMagic.count + pbgHeaderSize) else {
            throw ImportError.invalidArchive(name)
        }

        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw ImportError.cannotAccessFile(name)
        }
        defer { try? handle.close() }

        let prefix: Data
        do {
            prefix = try handle.read(upToCount: archiveMagic.count + pbgHeaderSize) ?? Data()
        } catch {
            throw ImportError.cannotAccessFile(name)
        }

        guard prefix.count == archiveMagic.count + pbgHeaderSize,
              prefix.prefix(archiveMagic.count) == archiveMagic else {
            throw ImportError.invalidArchive(name)
        }

        let encryptedHeader = Array(prefix.dropFirst(archiveMagic.count))
        let header = decryptPBGBytes(
            encryptedHeader,
            xorValue: 0x1b,
            xorIncrement: 0x37,
            chunkSize: pbgHeaderSize,
            maximumBytes: 0x400
        )
        guard header.count == pbgHeaderSize,
              let encodedEntryCount = readUInt32LE(header, at: 0),
              let encodedTableOffset = readUInt32LE(header, at: 4),
              let encodedTableSize = readUInt32LE(header, at: 8) else {
            throw ImportError.invalidArchive(name)
        }

        let entryCount = Int64(Int32(bitPattern: encodedEntryCount)) - 123_456
        let tableOffset = Int64(Int32(bitPattern: encodedTableOffset)) - 345_678
        let tableSize = Int64(Int32(bitPattern: encodedTableSize)) - 567_891

        guard entryCount > 0,
              entryCount <= maximumEntryCount,
              tableOffset >= Int64(archiveMagic.count + pbgHeaderSize),
              tableOffset < fileSize,
              tableSize > 0,
              tableSize <= maximumFileTableSize else {
            throw ImportError.invalidArchive(name)
        }

        // Validate the complete encrypted/compressed file table before installing
        // the pair. The decoder is a bounded Swift port of the retail LZSS reader.
        do {
            try handle.seek(toOffset: UInt64(tableOffset))
            let compressedTable = try handle.readToEnd() ?? Data()
            guard !compressedTable.isEmpty else {
                throw ImportError.invalidArchive(name)
            }
            let decryptedTable = Data(decryptPBGBytes(
                Array(compressedTable),
                xorValue: 0x3e,
                xorIncrement: 0x9b,
                chunkSize: 0x80,
                maximumBytes: 0x400
            ))
            let decodedTable = try decodeLZSS(
                decryptedTable,
                expectedSize: Int(tableSize)
            )
            try validateFileTable(
                decodedTable,
                entryCount: Int(entryCount),
                dataStart: Int64(archiveMagic.count + pbgHeaderSize),
                tableOffset: tableOffset,
                fileSize: fileSize
            )
        } catch let error as ImportError {
            throw error
        } catch {
            throw ImportError.invalidArchive(name)
        }
    }

    /// Decodes the retail LZSS bitstream. Bits are consumed most-significant
    /// first; a zero offset terminates the stream. Output and back-references
    /// are bounded so malformed archives cannot cause unbounded allocation.
    static func decodeLZSS(_ input: Data, expectedSize: Int) throws -> [UInt8] {
        let dictionarySize = 1 << 13
        guard expectedSize > 0,
              expectedSize <= Int(maximumFileTableSize),
              !input.isEmpty else {
            throw ImportError.invalidArchive("file table")
        }

        let source = Array(input)
        var dictionary = [UInt8](repeating: 0, count: dictionarySize)
        var output = [UInt8]()
        output.reserveCapacity(expectedSize)
        var inputIndex = 0
        var bitMask: UInt8 = 0x80
        var currentByte: UInt8 = 0
        var dictionaryHead = 1

        func readBit() throws -> UInt32 {
            if bitMask == 0x80 {
                guard inputIndex < source.count else {
                    throw ImportError.invalidArchive("truncated LZSS stream")
                }
                currentByte = source[inputIndex]
                inputIndex += 1
            }
            let bit: UInt32 = (currentByte & bitMask) == 0 ? 0 : 1
            bitMask >>= 1
            if bitMask == 0 { bitMask = 0x80 }
            return bit
        }

        func readBits(_ count: Int) throws -> Int {
            var value = 0
            for _ in 0..<count {
                value = (value << 1) | Int(try readBit())
            }
            return value
        }

        var terminated = false
        while true {
            if try readBit() != 0 {
                guard output.count < expectedSize else {
                    throw ImportError.invalidArchive("LZSS output exceeds declared size")
                }
                let literal = UInt8(try readBits(8))
                output.append(literal)
                dictionary[dictionaryHead] = literal
                dictionaryHead = (dictionaryHead + 1) & (dictionarySize - 1)
            } else {
                let offset = try readBits(13)
                if offset == 0 {
                    terminated = true
                    break
                }
                let length = try readBits(4) + 3
                guard output.count + length <= expectedSize else {
                    throw ImportError.invalidArchive("LZSS output exceeds declared size")
                }
                for index in 0..<length {
                    let value = dictionary[(offset + index) & (dictionarySize - 1)]
                    output.append(value)
                    dictionary[dictionaryHead] = value
                    dictionaryHead = (dictionaryHead + 1) & (dictionarySize - 1)
                }
            }
        }

        guard terminated, output.count == expectedSize else {
            throw ImportError.invalidArchive("incomplete LZSS file table")
        }
        return output
    }

    /// Parses NUL-terminated names followed by three little-endian DWORDs.
    /// Every payload offset must remain inside the archive's data region and
    /// offsets must be monotonic, matching the sentinel-based retail layout.
    static func validateFileTable(
        _ table: [UInt8],
        entryCount: Int,
        dataStart: Int64,
        tableOffset: Int64,
        fileSize: Int64
    ) throws {
        var cursor = 0
        var previousOffset = dataStart

        for _ in 0..<entryCount {
            guard cursor < table.count,
                  let terminator = table[cursor...].firstIndex(of: 0),
                  terminator > cursor else {
                throw ImportError.invalidArchive("invalid file-table name")
            }
            cursor = terminator + 1
            guard cursor <= table.count - 12 else {
                throw ImportError.invalidArchive("truncated file-table entry")
            }

            guard let rawOffset = readUInt32LE(table, at: cursor),
                  let rawSize = readUInt32LE(table, at: cursor + 4),
                  readUInt32LE(table, at: cursor + 8) != nil else {
                throw ImportError.invalidArchive("invalid file-table entry")
            }
            let offset = Int64(rawOffset)
            let decompressedSize = Int64(rawSize)
            guard offset >= previousOffset,
                  offset <= tableOffset,
                  offset < fileSize,
                  decompressedSize <= maximumFileTableSize else {
                throw ImportError.invalidArchive("file-table entry is out of bounds")
            }
            previousOffset = offset
            cursor += 12
        }

        guard cursor == table.count else {
            throw ImportError.invalidArchive("unexpected trailing file-table data")
        }
    }

    /// Port of FileSystem::Decrypt's byte ordering and rolling XOR transform.
    private static func decryptPBGBytes(
        _ input: [UInt8],
        xorValue: UInt8,
        xorIncrement: UInt8,
        chunkSize: Int,
        maximumBytes: Int
    ) -> [UInt8] {
        guard !input.isEmpty, chunkSize > 0 else { return input }

        var output = [UInt8](repeating: 0, count: input.count)
        var inputIndex = 0
        var outputIndex = 0
        var remaining = input.count
        var key = xorValue
        var bytesLeftToDecrypt = maximumBytes

        var unencryptedCount = remaining % chunkSize < chunkSize / 4
            ? remaining % chunkSize
            : 0
        unencryptedCount += remaining & 1
        remaining -= unencryptedCount

        while remaining > 0 && bytesLeftToDecrypt > 0 {
            let currentChunkSize = min(chunkSize, remaining)
            let firstPassCount = (currentChunkSize + 1) / 2
            for index in 0..<firstPassCount {
                output[outputIndex + currentChunkSize - 1 - index * 2] = input[inputIndex] ^ key
                inputIndex += 1
                key &+= xorIncrement
            }

            let secondPassCount = currentChunkSize / 2
            if secondPassCount > 0 {
                for index in 0..<secondPassCount {
                    output[outputIndex + currentChunkSize - 2 - index * 2] = input[inputIndex] ^ key
                    inputIndex += 1
                    key &+= xorIncrement
                }
            }

            remaining -= currentChunkSize
            outputIndex += currentChunkSize
            bytesLeftToDecrypt -= currentChunkSize
        }

        let trailingCount = remaining + unencryptedCount
        if trailingCount > 0 {
            for index in 0..<trailingCount {
                output[outputIndex + index] = input[inputIndex + index]
            }
        }
        return output
    }

    private static func readUInt32LE(_ bytes: [UInt8], at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= bytes.count else { return nil }
        return UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }
}
