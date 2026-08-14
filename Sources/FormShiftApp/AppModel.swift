import AppKit
import Foundation
import FormShiftCore
import FormShiftEngines
import FormShiftPersistence
import SwiftUI
import UniformTypeIdentifiers

enum WorkspaceSection: String, CaseIterable, Identifiable {
    case convert
    case queue
    case history
    case presets

    var id: String { rawValue }

    var title: String {
        switch self {
        case .convert: "转换"
        case .queue: "队列"
        case .history: "历史"
        case .presets: "预设"
        }
    }

    var symbol: String {
        switch self {
        case .convert: "arrow.triangle.2.circlepath"
        case .queue: "list.bullet.rectangle"
        case .history: "clock.arrow.circlepath"
        case .presets: "slider.horizontal.2.square"
        }
    }
}

struct UIJobItem: Identifiable, Equatable {
    let id: UUID
    let sourceURL: URL
    var sourceFormat: FormatID?
    var outputFormat: FormatID
    var status: JobStatus
    var progress: Double
    var detail: String?
    var byteCount: Int64
    var options: ConversionOptions?
    var destinationURL: URL?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        sourceURL: URL,
        sourceFormat: FormatID?,
        outputFormat: FormatID,
        status: JobStatus = .waiting,
        progress: Double = 0,
        detail: String? = nil,
        byteCount: Int64 = 0,
        options: ConversionOptions? = nil,
        destinationURL: URL? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.sourceFormat = sourceFormat
        self.outputFormat = outputFormat
        self.status = status
        self.progress = progress
        self.detail = detail
        self.byteCount = byteCount
        self.options = options
        self.destinationURL = destinationURL
        self.createdAt = createdAt
    }
}

enum OutputLocation: String, CaseIterable, Identifiable {
    case sourceFolder
    case chosenFolder
    case askEveryTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sourceFolder: "原文件目录"
        case .chosenFolder: "固定目录"
        case .askEveryTime: "每次询问"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var selection: WorkspaceSection = .convert
    @Published var jobs: [UIJobItem] = []
    @Published var selectedJobID: UUID?
    @Published var targetFormat: FormatID = .png
    @Published var targetFormats: [FormatID] = [.png]
    @Published var quality = 0.85
    @Published var resizeEnabled = false
    @Published var width = 1920
    @Published var height = 1080
    @Published var keepAspectRatio = true
    @Published var imageSizingMode: ImageSizingMode = .fit
    @Published var trimBorders = false
    @Published var cropEnabled = false
    @Published var cropX = 0
    @Published var cropY = 0
    @Published var cropWidth = 1000
    @Published var cropHeight = 1000
    @Published var rotationDegrees = 0
    @Published var removeMetadata = false
    @Published var hardwareEncoding = true
    @Published var codec: VideoCodec = .automatic
    @Published var frameRate = 30
    @Published var sampleRate = 48_000
    @Published var audioChannels = 2
    @Published var colorProfile: ImageColorProfile = .automatic
    @Published var pdfImageScale = 2
    @Published var presets: [Preset] = []
    @Published var outputLocation: OutputLocation = .sourceFolder
    @Published var isAdvancedExpanded = false
    @Published var isPaused = false
    @Published var isDropTargeted = false
    @Published var importNotice: String?

    @Published var supportedFormats = FormatID.allCases

    private var queue: ConversionQueue?
    private var persistence: PersistenceController?
    private var historyBridge: QueueHistoryBridge?
    private var queueObservationTask: Task<Void, Never>?
    private var submittedJobIDs: Set<UUID> = []
    private var chosenOutputDirectory: URL?
    private var outputsByInput: [FormatID: Set<FormatID>] = [:]
    private var hasExplicitTargetSelection = false
    private var optionsByTarget: [FormatID: ConversionOptions] = [:]
    private let securityScopedResources = SecurityScopedResourceStore()

    init() {
        Task { [weak self] in
            await self?.configureServices()
        }
    }

    var visibleJobs: [UIJobItem] {
        switch selection {
        case .convert: jobs.filter { $0.status == .waiting || $0.status == .analyzing || $0.status == .running }
        case .queue: jobs.filter {
            $0.status == .waiting || $0.status == .analyzing || $0.status == .running
                || (submittedJobIDs.contains($0.id) && $0.status != .succeeded)
        }
        case .history: jobs
            .filter { $0.status == .succeeded || $0.status == .failed || $0.status == .cancelled || $0.status == .interrupted }
            .sorted { $0.createdAt > $1.createdAt }
        case .presets: []
        }
    }

    var waitingCount: Int { jobs.filter { $0.status == .waiting }.count }
    var runningCount: Int { jobs.filter { $0.status == .running || $0.status == .analyzing }.count }
    var finishedCount: Int { jobs.filter { [.succeeded, .failed, .cancelled, .interrupted].contains($0.status) }.count }
    var canStartQueue: Bool { !isPaused && jobs.contains { $0.status == .waiting } }
    var hasFinishedJobs: Bool { jobs.contains { $0.status == .succeeded || $0.status == .failed || $0.status == .cancelled } }

    var selectedJob: UIJobItem? {
        guard let selectedJobID else { return nil }
        return jobs.first { $0.id == selectedJobID }
    }

    var formatChoices: [FormatID] {
        guard let input = selectedJob?.sourceFormat,
              let outputs = outputsByInput[input] else {
            return supportedFormats
        }
        return supportedFormats.filter { outputs.contains($0) }
    }

    var hasMultipleTargets: Bool { targetFormats.count > 1 }

    func isTargetFormatSelected(_ format: FormatID) -> Bool {
        targetFormats.contains(format)
    }

    func presentImporter() {
        let panel = NSOpenPanel()
        panel.title = "添加文件或文件夹"
        panel.prompt = "添加"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.data]
        panel.allowsOtherFileTypes = true
        panel.resolvesAliases = true
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in
                self?.enqueue(urls: panel.urls)
            }
        }
    }

    func importFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            enqueue(urls: urls)
        case .failure(let error):
            if (error as NSError).code != NSUserCancelledError {
                importNotice = "无法读取所选文件：\(error.localizedDescription)"
            }
        }
    }

    func enqueue(urls: [URL]) {
        // SwiftUI's importer and drag/drop grant sandbox access through
        // security-scoped URLs. Keep each imported root active while the app is
        // using its queued jobs; otherwise asynchronous probing can lose access.
        urls.forEach { securityScopedResources.retain($0) }
        let expanded = expandDirectories(in: urls)
        var accepted = 0
        var createdJobs = 0
        var rejected = 0

        for url in expanded {
            guard let sourceFormat = FormatID.from(url: url) else {
                rejected += 1
                continue
            }

            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            let outputs: [FormatID]
            if hasExplicitTargetSelection {
                outputs = targetFormats.filter { outputsByInput[sourceFormat]?.contains($0) == true }
            } else {
                outputs = [preferredOutput(for: sourceFormat)]
            }
            guard !outputs.isEmpty else {
                rejected += 1
                continue
            }

            for output in outputs {
                let item = UIJobItem(
                    sourceURL: url,
                    sourceFormat: sourceFormat,
                    outputFormat: output,
                    byteCount: Int64(values?.fileSize ?? 0)
                )
                jobs.append(item)
                selectedJobID = selectedJobID ?? item.id
                createdJobs += 1
            }
            accepted += 1
        }

        if !hasExplicitTargetSelection {
            refreshTargetFormatsFromWaitingJobs()
        }

        if rejected > 0 {
            importNotice = accepted > 0
                ? "已添加 \(accepted) 个文件，将生成 \(createdJobs) 个结果；\(rejected) 个文件不支持所选目标格式。"
                : "所选内容中没有可识别或兼容的文件。"
        } else if createdJobs > accepted {
            importNotice = "已添加 \(accepted) 个文件，将生成 \(createdJobs) 个格式结果。"
        } else {
            importNotice = nil
        }
    }

    func applyTargetFormat(_ format: FormatID) {
        let inheritedOptions = currentOptions(for: format)
        targetFormat = format
        targetFormats = [format]
        optionsByTarget = [format: inheritedOptions]
        applyInspectorOptions(inheritedOptions)
        hasExplicitTargetSelection = true
        var skipped = 0
        for index in jobs.indices where jobs[index].status == .waiting {
            if let input = jobs[index].sourceFormat,
               let outputs = outputsByInput[input],
               !outputs.contains(format) {
                skipped += 1
            } else {
                jobs[index].outputFormat = format
            }
        }
        deduplicateWaitingJobs()
        if skipped > 0 {
            importNotice = "已应用到兼容任务；跳过了 \(skipped) 个不支持该输出格式的文件。"
        }
    }

    func selectTargetFormat(_ format: FormatID) {
        guard targetFormats.contains(format), targetFormat != format else { return }
        optionsByTarget[targetFormat] = currentOptions(for: targetFormat)
        let inheritedOptions = optionsByTarget[format] ?? currentOptions(for: format)
        targetFormat = format
        optionsByTarget[format] = inheritedOptions
        applyInspectorOptions(inheritedOptions)
        if let matchingJob = jobs.first(where: { $0.status == .waiting && $0.outputFormat == format }) {
            selectedJobID = matchingJob.id
        }
    }

    func toggleTargetFormat(_ format: FormatID) {
        if targetFormats.contains(format) {
            removeTargetFormat(format)
        } else {
            addTargetFormat(format)
        }
    }

    func addTargetFormat(_ format: FormatID) {
        guard !targetFormats.contains(format) else {
            selectTargetFormat(format)
            return
        }
        hasExplicitTargetSelection = true
        optionsByTarget[targetFormat] = currentOptions(for: targetFormat)
        let inheritedOptions = optionsByTarget[format] ?? currentOptions(for: format)
        targetFormats.append(format)
        targetFormat = format
        optionsByTarget[format] = inheritedOptions
        applyInspectorOptions(inheritedOptions)

        let representatives = waitingSourceRepresentatives()
        var added = 0
        var skipped = 0
        for item in representatives {
            guard let input = item.sourceFormat,
                  outputsByInput[input]?.contains(format) == true else {
                skipped += 1
                continue
            }
            guard !jobs.contains(where: {
                $0.status == .waiting && $0.sourceURL == item.sourceURL && $0.outputFormat == format
            }) else { continue }
            jobs.append(UIJobItem(
                sourceURL: item.sourceURL,
                sourceFormat: item.sourceFormat,
                outputFormat: format,
                byteCount: item.byteCount
            ))
            added += 1
        }
        if skipped > 0 {
            importNotice = added > 0
                ? "已增加 \(format.displayName) 输出；跳过 \(skipped) 个不兼容文件。"
                : "当前文件不能转换为 \(format.displayName)。"
        } else if added > 0 {
            importNotice = "已增加 \(format.displayName) 输出，将多生成 \(added) 个结果。"
        }
    }

    func removeTargetFormat(_ format: FormatID) {
        guard targetFormats.contains(format) else { return }
        guard targetFormats.count > 1 else {
            importNotice = "至少保留一个目标格式。"
            return
        }
        let affectedSources = Set(jobs.filter {
            $0.status == .waiting && $0.outputFormat == format
        }.map(\.sourceURL))
        let wouldOrphanSource = affectedSources.contains { sourceURL in
            jobs.filter { $0.status == .waiting && $0.sourceURL == sourceURL }.count <= 1
        }
        guard !wouldOrphanSource else {
            importNotice = "不能移除 \(format.displayName)：至少有一个文件只剩这一种兼容输出。"
            return
        }
        hasExplicitTargetSelection = true
        optionsByTarget[targetFormat] = currentOptions(for: targetFormat)
        let removableIDs = Set(jobs.filter {
            $0.status == .waiting && $0.outputFormat == format
        }.map(\.id))
        jobs.removeAll { removableIDs.contains($0.id) }
        submittedJobIDs.subtract(removableIDs)
        targetFormats.removeAll { $0 == format }
        optionsByTarget[format] = nil
        if targetFormat == format {
            targetFormat = targetFormats[0]
            if let options = optionsByTarget[targetFormat] {
                applyInspectorOptions(options)
            }
        }
        if let selectedJobID, removableIDs.contains(selectedJobID) {
            self.selectedJobID = jobs.first(where: {
                $0.status == .waiting && $0.outputFormat == targetFormat
            })?.id ?? jobs.first?.id
        }
    }

    func startQueue() {
        guard canStartQueue else { return }
        guard let queue else {
            importNotice = "转换引擎仍在初始化，请稍后再试。"
            return
        }

        let pendingItems = jobs.filter {
            $0.status == .waiting && !submittedJobIDs.contains($0.id)
        }
        guard !pendingItems.isEmpty else { return }
        optionsByTarget[targetFormat] = currentOptions(for: targetFormat)

        let directory: URL?
        switch outputLocation {
        case .sourceFolder:
            guard authorizeSourceDirectories(for: pendingItems.map(\.sourceURL)) else { return }
            directory = nil
        case .chosenFolder:
            guard let selected = chosenOutputDirectory ?? chooseOutputDirectory() else { return }
            chosenOutputDirectory = selected
            directory = selected
        case .askEveryTime:
            guard let selected = chooseOutputDirectory() else { return }
            directory = selected
        }

        let pendingIDs = Set(pendingItems.map(\.id))
        for index in jobs.indices where pendingIDs.contains(jobs[index].id) {
            jobs[index].options = optionsByTarget[jobs[index].outputFormat]
                ?? currentOptions(for: jobs[index].outputFormat)
        }
        let pendingJobs = pendingItems.map { item in
                ConversionJob(
                    id: item.id,
                    sourceURL: item.sourceURL,
                    sourceFormat: item.sourceFormat,
                    outputFormat: item.outputFormat,
                    options: optionsByTarget[item.outputFormat]
                        ?? currentOptions(for: item.outputFormat)
                )
            }
        submittedJobIDs.formUnion(pendingJobs.map(\.id))
        selection = .queue
        importNotice = nil
        Task {
            await queue.setOutputDirectory(directory)
            await queue.enqueue(jobs: pendingJobs)
        }
    }

    func togglePause() {
        isPaused.toggle()
        guard let queue else { return }
        Task {
            if isPaused {
                await queue.pause()
            } else {
                await queue.resume()
            }
        }
    }

    func cancel(jobID: UUID) {
        guard let queue, submittedJobIDs.contains(jobID) else {
            updateJob(id: jobID) { job in
                guard job.status == .waiting else { return }
                job.status = .cancelled
                job.detail = "已取消"
            }
            return
        }
        Task { await queue.cancel(jobID: jobID) }
    }

    func retry(jobID: UUID) {
        if let queue, submittedJobIDs.contains(jobID) {
            Task { await queue.retry(jobID: jobID) }
        } else {
            updateJob(id: jobID) { job in
                guard job.status == .failed || job.status == .cancelled || job.status == .interrupted else { return }
                job.status = .waiting
                job.progress = 0
                job.detail = nil
            }
        }
        selection = .queue
    }

    func requeueFromHistory(jobID: UUID) {
        guard let original = jobs.first(where: { $0.id == jobID }) else { return }
        guard [.succeeded, .failed, .cancelled, .interrupted].contains(original.status) else {
            selectedJobID = jobID
            return
        }
        guard FileManager.default.fileExists(atPath: original.sourceURL.path) else {
            importNotice = "原文件已移动或删除，无法再次转换：\(original.sourceURL.lastPathComponent)"
            return
        }

        securityScopedResources.retain(original.sourceURL)
        targetFormat = original.outputFormat
        targetFormats = [original.outputFormat]
        hasExplicitTargetSelection = true
        if let options = original.options {
            applyInspectorOptions(options)
            optionsByTarget = [original.outputFormat: options]
        } else {
            optionsByTarget = [original.outputFormat: currentOptions(for: original.outputFormat)]
        }

        let restored = UIJobItem(
            sourceURL: original.sourceURL,
            sourceFormat: original.sourceFormat,
            outputFormat: original.outputFormat,
            status: .waiting,
            byteCount: original.byteCount,
            options: original.options
        )
        jobs.append(restored)
        selectedJobID = restored.id
        selection = .convert
        importNotice = "已恢复“\(original.sourceURL.lastPathComponent)”的上次转换设置。"
    }

    func remove(jobID: UUID) {
        jobs.removeAll { $0.id == jobID }
        if selectedJobID == jobID {
            selectedJobID = jobs.first?.id
        }
        if let persistence {
            Task { try? await persistence.deleteJob(id: jobID) }
        }
    }

    func clearFinished() {
        let removedIDs = Set(jobs.filter { $0.status == .succeeded || $0.status == .failed || $0.status == .cancelled }.map(\.id))
        jobs.removeAll { removedIDs.contains($0.id) }
        if let selectedJobID, removedIDs.contains(selectedJobID) {
            self.selectedJobID = jobs.first?.id
        }
        if let persistence {
            Task {
                for id in removedIDs {
                    try? await persistence.deleteJob(id: id)
                }
            }
        }
    }

    func openResult(jobID: UUID) {
        guard let url = jobs.first(where: { $0.id == jobID })?.destinationURL,
              FileManager.default.fileExists(atPath: url.path) else {
            importNotice = "转换结果已被移动或删除。"
            return
        }
        NSWorkspace.shared.open(url)
    }

    func revealResult(jobID: UUID) {
        guard let url = jobs.first(where: { $0.id == jobID })?.destinationURL,
              FileManager.default.fileExists(atPath: url.path) else {
            importNotice = "转换结果已被移动或删除。"
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func savePreset(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            importNotice = "请输入预设名称。"
            return
        }
        optionsByTarget[targetFormat] = currentOptions(for: targetFormat)
        let existing = presets.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
        let preset = Preset(
            id: existing?.id ?? UUID(),
            name: name,
            outputFormat: targetFormat,
            options: optionsByTarget[targetFormat] ?? currentOptions(for: targetFormat)
        )
        presets.removeAll { $0.id == preset.id }
        presets.append(preset)
        presets.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if let persistence {
            Task {
                do {
                    try await persistence.upsert(preset: preset)
                } catch {
                    self.importNotice = "无法保存预设：\(error.localizedDescription)"
                }
            }
        }
        importNotice = "已保存预设“\(name)”。"
    }

    func applyPreset(_ preset: Preset) {
        applyInspectorOptions(preset.options)
        applyTargetFormat(preset.outputFormat)
        optionsByTarget = [preset.outputFormat: preset.options]
        selection = .convert
        importNotice = "已应用预设“\(preset.name)”。"
    }

    func deletePreset(id: UUID) {
        presets.removeAll { $0.id == id }
        if let persistence {
            Task { try? await persistence.deletePreset(id: id) }
        }
    }

    func updateJob(id: UUID, mutation: (inout UIJobItem) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        mutation(&jobs[index])
    }

    private func configureServices() async {
        let registry = await DefaultEngineRegistryFactory.makeRegistry()
        let capabilities = await registry.allEngines().flatMap(\.capabilities)
        let availableOutputs = Set(capabilities.map(\.output))
        outputsByInput = Dictionary(grouping: capabilities, by: \.input)
            .mapValues { Set($0.map(\.output)) }
        supportedFormats = FormatID.allCases.filter { availableOutputs.contains($0) }

        if let ffmpeg = await registry.engine(id: "ffmpeg") as? FFmpegEngine {
            switch ffmpeg.availability.source {
            case .developmentPATH:
                importNotice = "开发模式：媒体转换使用本机 FFmpeg；发布包必须改用内置固定版本。"
            case .unavailable:
                importNotice = "未找到 FFmpeg，当前只能使用图片和 PDF 转换。"
            case .bundled:
                break
            }
        }

        let queue = ConversionQueue(registry: registry)
        self.queue = queue
        do {
            let persistence = try PersistenceController()
            try await persistence.pruneHistory()
            try await persistence.markInFlightJobsInterrupted()
            self.persistence = persistence
            loadPersistedHistory(await persistence.recentJobs())
            presets = await persistence.presets()
            let bridge = QueueHistoryBridge(queue: queue, persistence: persistence)
            historyBridge = bridge
            await bridge.start()
        } catch {
            importNotice = "历史记录不可用：\(error.localizedDescription)"
        }

        queueObservationTask = Task { [weak self, queue] in
            let stream = await queue.updates()
            for await snapshot in stream {
                guard !Task.isCancelled else { break }
                self?.applyQueueSnapshot(snapshot)
            }
        }
    }

    private func applyQueueSnapshot(_ snapshot: [ConversionJob]) {
        for engineJob in snapshot {
            guard let index = jobs.firstIndex(where: { $0.id == engineJob.id }) else { continue }
            jobs[index].sourceFormat = engineJob.sourceFormat
            jobs[index].outputFormat = engineJob.outputFormat
            jobs[index].status = engineJob.status
            jobs[index].progress = engineJob.progress
            jobs[index].detail = engineJob.statusDetail
            jobs[index].options = engineJob.options
            jobs[index].destinationURL = engineJob.destinationURL
        }
    }

    private func loadPersistedHistory(_ records: [JobRecord]) {
        for record in records {
            guard let outputFormat = FormatID(rawValue: record.outputFormat),
                  let status = JobStatus(rawValue: record.status),
                  [.succeeded, .failed, .cancelled, .interrupted].contains(status) else {
                continue
            }
            let resolvedSourceURL = record.resolvedSourceURL()
            let sourceURL = resolvedSourceURL ?? URL(fileURLWithPath: "/FormShift-Legacy-History/\(record.sourceFileName)")
            if resolvedSourceURL != nil {
                securityScopedResources.retain(sourceURL)
            }
            let destinationURL = record.destinationPath.map { URL(fileURLWithPath: $0) }
            jobs.append(UIJobItem(
                id: record.id,
                sourceURL: sourceURL,
                sourceFormat: record.sourceFormat.flatMap(FormatID.init(rawValue:)),
                outputFormat: outputFormat,
                status: status,
                progress: status == .succeeded ? 1 : 0,
                detail: record.statusDetail,
                byteCount: record.byteCount ?? 0,
                options: record.options,
                destinationURL: destinationURL,
                createdAt: record.createdAt
            ))
        }
    }

    private func applyInspectorOptions(_ options: ConversionOptions) {
        quality = options.quality
        resizeEnabled = options.width != nil || options.height != nil
        if let width = options.width { self.width = width }
        if let height = options.height { self.height = height }
        keepAspectRatio = options.preserveAspectRatio
        imageSizingMode = options.imageSizingMode
        trimBorders = options.trimBorders
        cropEnabled = options.crop != nil
        if let crop = options.crop {
            cropX = crop.x
            cropY = crop.y
            cropWidth = crop.width
            cropHeight = crop.height
        }
        rotationDegrees = options.rotationDegrees
        colorProfile = options.imageColorProfile
        pdfImageScale = options.pdfRenderScale
        removeMetadata = options.metadataPolicy == .remove
        codec = options.videoCodec
        hardwareEncoding = options.preferHardwareEncoding
        if let frameRate = options.frameRate { self.frameRate = max(1, Int(frameRate.rounded())) }
        if let sampleRate = options.sampleRate { self.sampleRate = sampleRate }
        if let audioChannels = options.audioChannels { self.audioChannels = audioChannels }
    }

    private func currentOptions(for outputFormat: FormatID) -> ConversionOptions {
        ConversionOptions(
            quality: quality,
            width: resizeEnabled ? max(1, width) : nil,
            height: resizeEnabled ? max(1, height) : nil,
            preserveAspectRatio: outputFormat.category == .image || outputFormat.category == .pdf
                ? imageSizingMode != .stretch
                : keepAspectRatio,
            imageSizingMode: imageSizingMode,
            trimBorders: trimBorders,
            crop: cropEnabled ? CropRect(
                x: max(0, cropX),
                y: max(0, cropY),
                width: max(1, cropWidth),
                height: max(1, cropHeight)
            ) : nil,
            rotationDegrees: rotationDegrees,
            imageColorProfile: colorProfile,
            pdfRenderScale: pdfImageScale,
            videoCodec: codec,
            preferHardwareEncoding: hardwareEncoding,
            frameRate: outputFormat.category == .video || outputFormat.category == .animatedImage
                ? Double(frameRate)
                : nil,
            sampleRate: outputFormat.category == .audio ? sampleRate : nil,
            audioChannels: outputFormat.category == .audio ? audioChannels : nil,
            metadataPolicy: removeMetadata ? .remove : .preserve
        )
    }

    private func chooseOutputDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "选择输出文件夹"
        panel.prompt = "选择"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        securityScopedResources.retain(url)
        return url
    }

    private func authorizeSourceDirectories(for sourceURLs: [URL]) -> Bool {
        let directories = Set(sourceURLs.map {
            $0.deletingLastPathComponent().standardizedFileURL
        }).sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

        for directory in directories where !securityScopedResources.hasDirectoryAccess(to: directory) {
            let panel = NSOpenPanel()
            panel.title = "授权保存到原文件目录"
            panel.message = "FormShift 需要访问“\(directory.lastPathComponent)”才能在原文件旁创建转换结果。"
            panel.prompt = "允许保存"
            panel.directoryURL = directory
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = false
            panel.allowsMultipleSelection = false

            guard panel.runModal() == .OK, let selected = panel.url else {
                importNotice = "未授权原文件目录，转换没有开始。"
                return false
            }
            let normalizedSelection = selected.standardizedFileURL
            guard Self.directory(normalizedSelection, contains: directory) else {
                importNotice = "请选择原文件所在文件夹“\(directory.lastPathComponent)”或它的上级文件夹。"
                return false
            }
            securityScopedResources.retain(normalizedSelection)
            guard securityScopedResources.hasDirectoryAccess(to: directory) else {
                importNotice = "无法获得“\(directory.lastPathComponent)”的写入权限，请重新选择输出位置。"
                return false
            }
        }
        return true
    }

    private static func directory(_ root: URL, contains candidate: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let candidatePath = candidate.standardizedFileURL.path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }

    func openLicenseFolder() {
        guard let resources = Bundle.main.resourceURL else {
            importNotice = "当前开发运行方式没有打包许可证文件。"
            return
        }
        let folder = resources.appendingPathComponent("Licenses", isDirectory: true)
        guard FileManager.default.fileExists(atPath: folder.path) else {
            importNotice = "当前开发运行方式没有打包许可证文件。"
            return
        }
        NSWorkspace.shared.open(folder)
    }

    private func preferredOutput(for input: FormatID) -> FormatID {
        let preferred: FormatID = switch input.category {
        case .image: input == .png ? .jpeg : .png
        case .animatedImage: .mp4
        case .video: .mp4
        case .audio: .m4a
        case .pdf: .png
        }
        let outputs = outputsByInput[input] ?? []
        return outputs.contains(preferred) ? preferred : (supportedFormats.first { outputs.contains($0) } ?? preferred)
    }

    private func waitingSourceRepresentatives() -> [UIJobItem] {
        var seen: Set<URL> = []
        return jobs.filter { $0.status == .waiting }.filter { item in
            seen.insert(item.sourceURL).inserted
        }
    }

    private func refreshTargetFormatsFromWaitingJobs() {
        guard let format = selectedJob.flatMap({ job in
            job.status == .waiting ? job.outputFormat : nil
        }) ?? jobs.first(where: { $0.status == .waiting })?.outputFormat else { return }
        // Before the user explicitly selects multiple outputs, the inspector
        // follows the active task only. Mixed batches may use different safe
        // defaults per media category; that is not the same as asking every
        // source file to generate every displayed format.
        targetFormat = format
        targetFormats = [format]
        optionsByTarget = [format: currentOptions(for: format)]
    }

    private func deduplicateWaitingJobs() {
        struct WaitingKey: Hashable {
            let sourceURL: URL
            let outputFormat: FormatID
        }
        var seen: Set<WaitingKey> = []
        let duplicateIDs = Set(jobs.compactMap { item -> UUID? in
            guard item.status == .waiting else { return nil }
            let key = WaitingKey(sourceURL: item.sourceURL, outputFormat: item.outputFormat)
            return seen.insert(key).inserted ? nil : item.id
        })
        jobs.removeAll { duplicateIDs.contains($0.id) }
        submittedJobIDs.subtract(duplicateIDs)
        if let selectedJobID, duplicateIDs.contains(selectedJobID) {
            self.selectedJobID = jobs.first(where: { $0.status == .waiting })?.id ?? jobs.first?.id
        }
    }

    private func expandDirectories(in urls: [URL]) -> [URL] {
        urls.flatMap { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { return [url] }

            let keys: [URLResourceKey] = [.isRegularFileKey, .isHiddenKey]
            let contents = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
            return (contents?.allObjects as? [URL] ?? []).filter { child in
                let childValues = try? child.resourceValues(forKeys: Set(keys))
                return childValues?.isRegularFile == true && childValues?.isHidden != true
            }
        }
    }
}

private final class SecurityScopedResourceStore {
    private var activeURLs: Set<URL> = []
    private var activeDirectories: Set<URL> = []

    func retain(_ url: URL) {
        let normalized = url.standardizedFileURL
        guard !activeURLs.contains(normalized) else { return }
        if normalized.startAccessingSecurityScopedResource() {
            activeURLs.insert(normalized)
            if (try? normalized.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                activeDirectories.insert(normalized)
            }
        }
    }

    func hasDirectoryAccess(to directory: URL) -> Bool {
        let candidatePath = directory.standardizedFileURL.path
        return activeDirectories.contains { root in
            let rootPath = root.path
            return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
        }
    }

    deinit {
        for url in activeURLs {
            url.stopAccessingSecurityScopedResource()
        }
    }
}
