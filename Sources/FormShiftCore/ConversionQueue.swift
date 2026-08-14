import Foundation

public actor ConversionQueue {
    private let registry: EngineRegistry
    private var jobsByID: [UUID: ConversionJob] = [:]
    private var order: [UUID] = []
    private var runningTasks: [UUID: Task<Void, Never>] = [:]
    private var runningEngines: [UUID: any ConversionEngine] = [:]
    private var observers: [UUID: AsyncStream<[ConversionJob]>.Continuation] = [:]
    private var paused = false
    private var outputDirectory: URL?

    public init(registry: EngineRegistry, outputDirectory: URL? = nil) {
        self.registry = registry
        self.outputDirectory = outputDirectory
    }

    deinit {
        for continuation in observers.values {
            continuation.finish()
        }
    }

    public func updates() -> AsyncStream<[ConversionJob]> {
        let observerID = UUID()
        return AsyncStream { continuation in
            observers[observerID] = continuation
            continuation.yield(snapshot())
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeObserver(observerID) }
            }
        }
    }

    public func snapshot() -> [ConversionJob] {
        order.compactMap { jobsByID[$0] }
    }

    @discardableResult
    public func enqueue(
        urls: [URL],
        outputFormat: FormatID,
        options: ConversionOptions = .init()
    ) -> [UUID] {
        let newJobs = urls.map { url in
            ConversionJob(
                sourceURL: url,
                sourceFormat: FormatID.from(url: url),
                outputFormat: outputFormat,
                options: options
            )
        }
        enqueue(jobs: newJobs)
        return newJobs.map(\.id)
    }

    public func enqueue(jobs: [ConversionJob]) {
        for job in jobs where jobsByID[job.id] == nil {
            jobsByID[job.id] = job
            order.append(job.id)
        }
        publish()
        schedule()
    }

    public func setOutputDirectory(_ directory: URL?) {
        outputDirectory = directory
    }

    public func pause() {
        paused = true
        publish()
    }

    public func resume() {
        paused = false
        publish()
        schedule()
    }

    public func cancel(jobID: UUID) async {
        guard var job = jobsByID[jobID] else { return }
        runningTasks[jobID]?.cancel()
        if let engine = runningEngines[jobID] {
            await engine.cancel(jobID: jobID)
        }
        if job.status == .waiting || job.status == .analyzing || job.status == .running {
            job.status = .cancelled
            job.statusDetail = ConversionError.cancelled.localizedDescription
            job.completedAt = .now
            jobsByID[jobID] = job
        }
        publish()
    }

    public func retry(jobID: UUID) {
        guard var job = jobsByID[jobID], [.failed, .cancelled, .interrupted].contains(job.status) else { return }
        job.status = .waiting
        job.statusDetail = nil
        job.progress = 0
        job.completedAt = nil
        job.destinationURL = nil
        jobsByID[jobID] = job
        publish()
        schedule()
    }

    public func markRunningJobsInterrupted() {
        for id in order {
            guard var job = jobsByID[id], job.status == .running || job.status == .analyzing else { continue }
            job.status = .interrupted
            job.statusDetail = "上次运行意外中断，可重新尝试"
            job.completedAt = .now
            jobsByID[id] = job
        }
        publish()
    }

    private func removeObserver(_ id: UUID) {
        observers[id] = nil
    }

    private func publish() {
        let current = snapshot()
        for continuation in observers.values {
            continuation.yield(current)
        }
    }

    private func schedule() {
        guard !paused else { return }
        let runningJobs = runningTasks.keys.compactMap { jobsByID[$0] }
        let heavyCount = runningJobs.filter { isHeavy($0) }.count
        let lightCount = runningJobs.count - heavyCount
        var freeHeavy = max(0, 1 - heavyCount)
        var freeLight = max(0, 4 - lightCount)

        for id in order {
            guard runningTasks[id] == nil, let job = jobsByID[id], job.status == .waiting else { continue }
            if isHeavy(job) {
                guard freeHeavy > 0 else { continue }
                freeHeavy -= 1
            } else {
                guard freeLight > 0 else { continue }
                freeLight -= 1
            }
            runningTasks[id] = Task { await self.execute(jobID: id) }
        }
    }

    private func isHeavy(_ job: ConversionJob) -> Bool {
        let categories = [job.sourceFormat?.category, job.outputFormat.category]
        return categories.contains(.video) || categories.contains(.audio) || categories.contains(.animatedImage)
    }

    private func execute(jobID: UUID) async {
        do {
            try Task.checkCancellation()
            guard var job = jobsByID[jobID] else { return }
            let hasDirectSecurityScope = job.sourceURL.startAccessingSecurityScopedResource()
            defer {
                if hasDirectSecurityScope {
                    job.sourceURL.stopAccessingSecurityScopedResource()
                }
            }
            job.status = .analyzing
            job.statusDetail = "正在分析文件"
            jobsByID[jobID] = job
            publish()

            guard let inputFormat = job.sourceFormat ?? FormatID.from(url: job.sourceURL) else {
                throw ConversionError.unsupportedInput(job.sourceURL)
            }
            guard let engine = await registry.engine(input: inputFormat, output: job.outputFormat) else {
                throw ConversionError.unsupportedConversion(inputFormat, job.outputFormat)
            }
            runningEngines[jobID] = engine
            let source = try await engine.probe(url: job.sourceURL)
            try engine.validate(source: source, output: job.outputFormat, options: job.options)
            let destination = FileSafety.destinationURL(
                for: job.sourceURL,
                outputFormat: job.outputFormat,
                directory: outputDirectory
            )
            let plan = try engine.makePlan(
                jobID: jobID,
                source: source,
                output: job.outputFormat,
                destination: destination,
                options: job.options
            )

            job.sourceFormat = source.format
            job.status = .running
            job.statusDetail = "正在转换"
            job.destinationURL = destination
            jobsByID[jobID] = job
            publish()

            let result = try await engine.run(plan: plan) { [weak self] progress in
                Task { await self?.receive(progress: progress, for: jobID) }
            }
            try Task.checkCancellation()

            guard FileManager.default.fileExists(atPath: result.path) else {
                throw ConversionError.outputMissing
            }
            job.status = .succeeded
            job.progress = 1
            job.statusDetail = "转换完成"
            job.destinationURL = result
            job.completedAt = .now
            jobsByID[jobID] = job
        } catch is CancellationError {
            markCancelled(jobID)
        } catch let error as ConversionError where error == .cancelled {
            markCancelled(jobID)
        } catch {
            if var job = jobsByID[jobID], job.status != .cancelled {
                job.status = .failed
                job.statusDetail = error.localizedDescription
                job.completedAt = .now
                jobsByID[jobID] = job
            }
        }
        runningTasks[jobID] = nil
        runningEngines[jobID] = nil
        publish()
        schedule()
    }

    private func receive(progress: ConversionProgress, for jobID: UUID) {
        guard var job = jobsByID[jobID], job.status == .running else { return }
        job.progress = progress.fraction
        if let detail = progress.detail { job.statusDetail = detail }
        jobsByID[jobID] = job
        publish()
    }

    private func markCancelled(_ jobID: UUID) {
        guard var job = jobsByID[jobID] else { return }
        job.status = .cancelled
        job.statusDetail = ConversionError.cancelled.localizedDescription
        job.completedAt = .now
        jobsByID[jobID] = job
    }
}

extension ConversionError: Equatable {
    public static func == (lhs: ConversionError, rhs: ConversionError) -> Bool {
        switch (lhs, rhs) {
        case (.cancelled, .cancelled), (.outputMissing, .outputMissing): true
        default: false
        }
    }
}
