import Foundation

public enum FileSafety {
    public static func destinationURL(
        for source: URL,
        outputFormat: FormatID,
        directory: URL? = nil,
        fileManager: FileManager = .default
    ) -> URL {
        let targetDirectory = directory ?? source.deletingLastPathComponent()
        let baseName = source.deletingPathExtension().lastPathComponent
        var candidate = targetDirectory
            .appendingPathComponent(baseName)
            .appendingPathExtension(outputFormat.fileExtension)

        if candidate.standardizedFileURL == source.standardizedFileURL || fileManager.fileExists(atPath: candidate.path) {
            var index = 1
            repeat {
                candidate = targetDirectory
                    .appendingPathComponent("\(baseName) \(index)")
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
