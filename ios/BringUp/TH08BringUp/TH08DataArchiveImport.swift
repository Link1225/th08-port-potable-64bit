import Foundation

enum TH08DataArchiveImport {
    static let requiredNames: Set<String> = ["th08.dat", "thbgm.dat"]
    private static let archiveMagic = Data("ZGBP".utf8)

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
                return "\(name) does not have the expected PBG archive signature."
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

            let handle = try FileHandle(forReadingFrom: source)
            let signature = try handle.read(upToCount: archiveMagic.count) ?? Data()
            try handle.close()
            guard signature == archiveMagic else {
                throw ImportError.invalidArchive(name)
            }

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
}
