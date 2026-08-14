import Foundation

public protocol ConversionEngine: Sendable {
    var id: String { get }
    var capabilities: [ConversionCapability] { get }

    func probe(url: URL) async throws -> MediaDescriptor
    func validate(source: MediaDescriptor, output: FormatID, options: ConversionOptions) throws
    func makePlan(
        jobID: UUID,
        source: MediaDescriptor,
        output: FormatID,
        destination: URL,
        options: ConversionOptions
    ) throws -> ConversionPlan
    func run(
        plan: ConversionPlan,
        progress: @escaping @Sendable (ConversionProgress) -> Void
    ) async throws -> URL
    func cancel(jobID: UUID) async
}

public actor EngineRegistry {
    private var engines: [String: any ConversionEngine] = [:]

    public init() {}

    public func register(_ engine: any ConversionEngine) {
        engines[engine.id] = engine
    }

    public func engine(id: String) -> (any ConversionEngine)? {
        engines[id]
    }

    public func allEngines() -> [any ConversionEngine] {
        Array(engines.values)
    }

    public func engine(input: FormatID, output: FormatID) -> (any ConversionEngine)? {
        engines.values.first { engine in
            engine.capabilities.contains { $0.input == input && $0.output == output }
        }
    }

    public func capabilities(for input: FormatID) -> [ConversionCapability] {
        engines.values
            .flatMap(\.capabilities)
            .filter { $0.input == input }
            .sorted { $0.output.displayName < $1.output.displayName }
    }
}

public enum ConversionError: LocalizedError, Sendable {
    case unsupportedInput(URL)
    case permissionDenied(URL)
    case outputPermissionDenied(URL)
    case unsupportedConversion(FormatID, FormatID)
    case invalidOptions(String)
    case engineUnavailable(String)
    case processFailed(String)
    case cancelled
    case outputMissing

    public var errorDescription: String? {
        switch self {
        case .unsupportedInput(let url): "无法识别文件：\(url.lastPathComponent)"
        case .permissionDenied(let url): "没有权限读取文件：\(url.lastPathComponent)，请重新添加文件"
        case .outputPermissionDenied(let url): "没有权限写入文件夹：\(url.lastPathComponent)，请重新选择输出位置"
        case .unsupportedConversion(let input, let output): "不支持从 \(input.displayName) 转换到 \(output.displayName)"
        case .invalidOptions(let detail): "设置无效：\(detail)"
        case .engineUnavailable(let engine): "转换引擎不可用：\(engine)"
        case .processFailed(let detail): "转换失败：\(detail)"
        case .cancelled: "转换已取消"
        case .outputMissing: "转换结束，但没有生成输出文件"
        }
    }
}
