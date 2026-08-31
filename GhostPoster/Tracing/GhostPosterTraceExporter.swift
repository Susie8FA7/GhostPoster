#if DEBUG
import Foundation

enum GhostPosterTraceExporter {
    static func createFile(
        data: Data,
        generatedAt: Date = Date(),
        directory: URL = FileManager.default.temporaryDirectory
    ) throws -> URL {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"

        let filename = "ghostposter-trace-\(formatter.string(from: generatedAt)).json"
        let url = directory.appendingPathComponent(filename, isDirectory: false)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func removeFile(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
#endif
