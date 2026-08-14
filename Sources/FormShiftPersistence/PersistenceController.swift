import Foundation
import FormShiftCore

public struct JobRecord: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var sourceFileName: String
    public var sourceFormat: String?
    public var outputFormat: String
    public var status: String
    public var statusDetail: String?
    public var destinationFileName: String?
    public var sourcePath: String?
    public var sourceBookmarkData: Data?
    public var destinationPath: String?
    public var byteCount: Int64?
    public var options: ConversionOptions?
    public var createdAt: Date
    public var completedAt: Date?

    public init(job: ConversionJob) {
        id = job.id
        sourceFileName = job.sourceURL.lastPathComponent
        sourceFormat = job.sourceFormat?.rawValue
        outputFormat = job.outputFormat.rawValue
        status = job.status.rawValue
        statusDetail = job.statusDetail
        destinationFileName = job.destinationURL?.lastPathComponent
        sourcePath = job.sourceURL.path
        sourceBookmarkData = try? job.sourceURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        destinationPath = job.destinationURL?.path
        byteCount = (try? job.sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
        options = job.options
        createdAt = job.createdAt
        completedAt = job.completedAt
    }

    public mutating func update(from job: ConversionJob) {
        sourceFormat = job.sourceFormat?.rawValue
        outputFormat = job.outputFormat.rawValue
        status = job.status.rawValue
        statusDetail = job.statusDetail
        destinationFileName = job.destinationURL?.lastPathComponent
        sourcePath = job.sourceURL.path
        sourceBookmarkData = (try? job.sourceURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )) ?? sourceBookmarkData
        destinationPath = job.destinationURL?.path
        byteCount = (try? job.sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? byteCount
        options = job.options
        completedAt = job.completedAt
    }

    public func resolvedSourceURL() -> URL? {
        if let sourceBookmarkData {
            var isStale = false
            if let resolved = try? URL(
                resolvingBookmarkData: sourceBookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                return resolved
            }
        }
        return sourcePath.map { URL(fileURLWithPath: $0) }
    }
}

private struct PersistedState: Codable, Sendable {
    var jobs: [JobRecord] = []
    var presets: [Preset] = []
}

public actor PersistenceController {
    public static let historyRetentionDays = 30
    private let storeURL: URL
    private var state: PersistedState

    public init(storeURL: URL? = nil) throws {
        if let storeURL {
            self.storeURL = storeURL
        } else {
            let base = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = base.appendingPathComponent("FormShift", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.storeURL = directory.appendingPathComponent("History.json")
        }

        if FileManager.default.fileExists(atPath: self.storeURL.path) {
            let data = try Data(contentsOf: self.storeURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            state = try decoder.decode(PersistedState.self, from: data)
        } else {
            state = PersistedState()
        }
    }

    public func upsert(job: ConversionJob) throws {
        if let index = state.jobs.firstIndex(where: { $0.id == job.id }) {
            state.jobs[index].update(from: job)
        } else {
            state.jobs.append(JobRecord(job: job))
        }
        try save()
    }

    public func recentJobs() -> [JobRecord] {
        state.jobs.sorted { $0.createdAt > $1.createdAt }
    }

    public func markInFlightJobsInterrupted(referenceDate: Date = .now) throws {
        var changed = false
        for index in state.jobs.indices where [
            JobStatus.waiting.rawValue,
            JobStatus.analyzing.rawValue,
            JobStatus.running.rawValue
        ].contains(state.jobs[index].status) {
            state.jobs[index].status = JobStatus.interrupted.rawValue
            state.jobs[index].statusDetail = "应用上次退出时任务尚未完成"
            state.jobs[index].completedAt = referenceDate
            changed = true
        }
        if changed { try save() }
    }

    public func deleteJob(id: UUID) throws {
        state.jobs.removeAll { $0.id == id }
        try save()
    }

    public func presets() -> [Preset] {
        state.presets.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func upsert(preset: Preset) throws {
        if let index = state.presets.firstIndex(where: { $0.id == preset.id }) {
            state.presets[index] = preset
        } else {
            state.presets.append(preset)
        }
        try save()
    }

    public func deletePreset(id: UUID) throws {
        state.presets.removeAll { $0.id == id }
        try save()
    }

    public func pruneHistory(referenceDate: Date = .now) throws {
        guard let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -Self.historyRetentionDays,
            to: referenceDate
        ) else { return }
        state.jobs.removeAll { $0.createdAt < cutoff }
        try save()
    }

    public func clearHistory() throws {
        state.jobs.removeAll()
        try save()
    }

    private func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)
        let temporary = storeURL.appendingPathExtension("tmp")
        try data.write(to: temporary, options: .atomic)
        if FileManager.default.fileExists(atPath: storeURL.path) {
            _ = try FileManager.default.replaceItemAt(storeURL, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: storeURL)
        }
    }
}
