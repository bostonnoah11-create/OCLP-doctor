import Foundation
import Darwin

public enum DiagnosticReportLocation: String, Sendable {
    case system, user
    var label: String { self == .system ? "System DiagnosticReports" : "User DiagnosticReports" }
}

public struct DiagnosticReportDocument: Sendable {
    public let location: DiagnosticReportLocation
    public let data: Data
    public init(location: DiagnosticReportLocation, data: Data) {
        self.location = location; self.data = data
    }
}

public struct DiagnosticReportReadBatch: Sendable {
    public var documents: [DiagnosticReportDocument]
    public var readableDirectories: Int
    public var missingDirectories: Int
    public var unreadableDirectories: Int
    public var candidateCount: Int
    public var unreadableFiles: Int
    public var oversizedFiles: Int
    public var limitedFiles: Int
    public var enumerationLimited: Bool

    public init(documents: [DiagnosticReportDocument] = [], readableDirectories: Int = 2,
                missingDirectories: Int = 0, unreadableDirectories: Int = 0, candidateCount: Int = 0,
                unreadableFiles: Int = 0, oversizedFiles: Int = 0, limitedFiles: Int = 0,
                enumerationLimited: Bool = false) {
        self.documents = documents; self.readableDirectories = readableDirectories
        self.missingDirectories = missingDirectories; self.unreadableDirectories = unreadableDirectories
        self.candidateCount = candidateCount; self.unreadableFiles = unreadableFiles
        self.oversizedFiles = oversizedFiles; self.limitedFiles = limitedFiles
        self.enumerationLimited = enumerationLimited
    }
}

public protocol DiagnosticReportReading: Sendable {
    func read(since: Date, until: Date) -> DiagnosticReportReadBatch
}

public struct LocalDiagnosticReportReader: DiagnosticReportReading {
    private let directories: [(DiagnosticReportLocation, URL)]
    public init() {
        directories = [(.system, URL(fileURLWithPath: "/Library/Logs/DiagnosticReports")),
            (.user, FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports"))]
    }
    // Fixture-only injection; the public initializer always uses the two scoped roots.
    init(systemDirectory: URL, userDirectory: URL) {
        directories = [(.system, systemDirectory), (.user, userDirectory)]
    }

    public func read(since: Date, until: Date) -> DiagnosticReportReadBatch {
        var batch = DiagnosticReportReadBatch(readableDirectories: 0)
        var candidates = [(date: Date, location: DiagnosticReportLocation, url: URL, size: Int)]()
        let manager = FileManager.default
        for (location, directory) in directories {
            do {
                let properties = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard properties.isDirectory == true, properties.isSymbolicLink != true else {
                    batch.unreadableDirectories += 1; continue
                }
                let entries = try manager.contentsOfDirectory(at: directory,
                    includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey],
                    options: [.skipsHiddenFiles])
                batch.readableDirectories += 1
                if entries.count > 10_000 { batch.enumerationLimited = true }
                for url in entries.prefix(10_000) {
                    let name = url.lastPathComponent.lowercased()
                    guard ["panic", "ips", "diag"].contains(url.pathExtension.lowercased()) ||
                        name.contains("sleepwake") || name.contains("sleep_wake") || name.contains("sleep-wake") else { continue }
                    do {
                        let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey])
                        guard info.isRegularFile == true, info.isSymbolicLink != true else { continue }
                        guard let date = info.contentModificationDate, let size = info.fileSize else {
                            batch.unreadableFiles += 1; continue
                        }
                        // Modification time selects candidates only; never becomes an event time.
                        guard date >= since else { continue }
                        candidates.append((date, location, url, size))
                    } catch { batch.unreadableFiles += 1 }
                }
            } catch {
                let failure = error as NSError
                if failure.domain == NSCocoaErrorDomain && [NSFileReadNoSuchFileError, NSFileNoSuchFileError].contains(failure.code) {
                    batch.missingDirectories += 1
                } else { batch.unreadableDirectories += 1 }
            }
        }
        candidates.sort { $0.date > $1.date }
        batch.candidateCount = candidates.count
        batch.limitedFiles += max(0, candidates.count - 40)
        var remainingBudget = 8_388_608
        for candidate in candidates.prefix(40) {
            if Task.isCancelled { batch.limitedFiles += 1; continue }
            if candidate.size > 1_048_576 { batch.oversizedFiles += 1; continue }
            guard remainingBudget > 0, candidate.size <= remainingBudget else { batch.limitedFiles += 1; continue }
            switch Self.readRegularFile(candidate.url, limit: min(1_048_576, remainingBudget), remainingBudget: &remainingBudget) {
            case .data(let data):
                batch.documents.append(DiagnosticReportDocument(location: candidate.location, data: data))
            case .tooLarge:
                batch.oversizedFiles += 1
            case .unreadable, .missing: batch.unreadableFiles += 1
            }
        }
        return batch
    }

    // Internal read seam permits a real partial-read/I/O-failure test without changing files.
    static func readRegularFile(_ url: URL, limit: Int, remainingBudget: inout Int,
        readBytes: (Int32, UnsafeMutableRawPointer?, Int) -> Int = { Darwin.read($0, $1, $2) }) -> FileReadOutcome {
        let descriptor = url.path.withCString { Darwin.open($0, O_RDONLY | O_NOFOLLOW | O_NONBLOCK) }
        guard descriptor >= 0 else { return .unreadable }
        defer { Darwin.close(descriptor) }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0, (metadata.st_mode & S_IFMT) == S_IFREG else { return .unreadable }
        guard metadata.st_size <= limit else { return .tooLarge }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: min(limit, 65_536))
        while result.count < limit {
            let requested = min(min(buffer.count, limit - result.count), max(0, remainingBudget))
            guard requested > 0 else { return .tooLarge }
            let readCount = buffer.withUnsafeMutableBytes { readBytes(descriptor, $0.baseAddress, requested) }
            if readCount == 0 { return .data(result) }
            if readCount < 0 {
                if errno == EINTR { continue }
                return .unreadable
            }
            // Charge successful reads immediately, including those preceding an I/O failure.
            remainingBudget -= readCount
            result.append(contentsOf: buffer.prefix(readCount))
        }
        // Avoid an extra byte beyond the total cap; stat detects growth at the boundary.
        guard fstat(descriptor, &metadata) == 0, metadata.st_size <= limit else { return .tooLarge }
        return .data(result)
    }
}
