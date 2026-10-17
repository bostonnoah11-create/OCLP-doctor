import Foundation

public enum FileReadOutcome: Equatable, Sendable {
    case missing
    case unreadable
    case tooLarge
    case data(Data)

    var description: String {
        switch self {
        case .missing: return "missing"
        case .unreadable: return "unreadable"
        case .tooLarge: return "size limit exceeded"
        case .data: return "read"
        }
    }
}

public protocol FileReading: Sendable {
    func read(_ url: URL, maxBytes: Int) -> FileReadOutcome
    func canonicalURL(for url: URL) -> URL
}

public struct LocalFileReader: FileReading {
    public init() {}

    public func canonicalURL(for url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    public func read(_ url: URL, maxBytes: Int = 1_048_576) -> FileReadOutcome {
        // Bound every read even if a caller accidentally requests a larger limit.
        let limit = min(max(0, maxBytes), 1_048_576)
        do {
            let properties = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard properties.isRegularFile == true else { return .unreadable }
            if let size = properties.fileSize, size > limit { return .tooLarge }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: limit + 1) ?? Data()
            guard data.count <= limit else { return .tooLarge }
            return .data(data)
        } catch {
            let failure = error as NSError
            if failure.domain == NSCocoaErrorDomain &&
                (failure.code == NSFileReadNoSuchFileError || failure.code == NSFileNoSuchFileError) {
                return .missing
            }
            if failure.domain == NSPOSIXErrorDomain && failure.code == 2 { return .missing }
            return .unreadable
        }
    }
}
