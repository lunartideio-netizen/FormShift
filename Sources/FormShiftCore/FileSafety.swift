import Foundation

public enum FileSafety {
    public static func destinationURL(
        for source: URL,
        outputFormat: FormatID,
        directory: URL? = nil,
        pattern: String? = nil,
        fileManager: FileManager = .default
    ) -> URL {
        let targetDirectory = directory ?? source.deletingLastPathComponent()
        let baseName = source.deletingPathExtension().lastPathComponent
        let resolvedBase: String
        if let p = pattern, !p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd"
            let dateStr = formatter.string(from: Date())
            resolvedBase = p
                .replacingOccurrences(of: "{name}", with: baseName)
                .replacingOccurrences(of: "{format}", with: outputFormat.fileExtension)
                .replacingOccurrences(of: "{date}", with: dateStr)
        } else {
            resolvedBase = baseName
        }
        var candidate = targetDirectory
            .appendingPathComponent(resolvedBase)
            .appendingPathExtension(outputFormat.fileExtension)

        if candidate.standardizedFileURL == source.standardizedFileURL || fileManager.fileExists(atPath: candidate.path) {
            var index = 1
            repeat {
                candidate = targetDirectory
                    .appendingPathComponent("\(resolvedBase) \(index)")
                    .appendingPathExtension(outputFormat.fileExtension)
                index += 1
            } while fileManager.fileExists(atPath: candidate.path)
        }
        return candidate
    }

    public static func temporaryURL(for destination: URL, jobID: UUID) -> URL {
        destination.deletingLastPathComponent()
            .appendingPathComponent(".formshift-\(jobID.uuidString)")
            .appendingPathExtension(destination.pathExtension)
    }
}
