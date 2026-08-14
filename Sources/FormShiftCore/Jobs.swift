import Foundation

public enum JobStatus: String, Codable, CaseIterable, Sendable {
    case waiting
    case analyzing
    case running
    case succeeded
    case failed
    case cancelled
    case interrupted
}

public struct ConversionJob: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let sourceURL: URL
    public var sourceFormat: FormatID?
    public var outputFormat: FormatID
    public var options: ConversionOptions
    public var status: JobStatus
    public var progress: Double
    public var statusDetail: String?
    public var destinationURL: URL?
    public let createdAt: Date
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        sourceURL: URL,
        sourceFormat: FormatID? = nil,
        outputFormat: FormatID,
        options: ConversionOptions = .init(),
        status: JobStatus = .waiting,
        progress: Double = 0,
        statusDetail: String? = nil,
        destinationURL: URL? = nil,
        createdAt: Date = .now,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.sourceFormat = sourceFormat
        self.outputFormat = outputFormat
        self.options = options
        self.status = status
        self.progress = progress
        self.statusDetail = statusDetail
        self.destinationURL = destinationURL
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}

public struct Preset: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var outputFormat: FormatID
    public var options: ConversionOptions
    public var schemaVersion: Int

    public init(
        id: UUID = UUID(),
        name: String,
        outputFormat: FormatID,
        options: ConversionOptions,
        schemaVersion: Int = 1
    ) {
        self.id = id
        self.name = name
        self.outputFormat = outputFormat
        self.options = options
        self.schemaVersion = schemaVersion
    }
}
