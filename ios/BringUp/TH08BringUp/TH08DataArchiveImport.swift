import Foundation

enum TH08DataArchiveImport {
    static let requiredNames: Set<String> = ["th08.dat", "thbgm.dat"]
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
                return "\(name) does not contain a valid PBG archive header."
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

    /// Checks the PBG signature and decodes the three encrypted header fields.
    /// This mirrors the retail loader's header transform and rejects impossible
    /// table metadata before the files are installed. It does not decompress
    /// or validate every archive entry; that remains an engine-side load check.
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
