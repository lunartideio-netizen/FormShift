import Foundation
import FormShiftCore

public enum FFmpegBinarySource: String, Sendable {
    case bundled
    case developmentPATH
    case unavailable
}

public struct FFmpegAvailability: Sendable {
    public let source: FFmpegBinarySource
    public let ffmpegURL: URL?
    public let ffprobeURL: URL?

    public var isAvailable: Bool { ffmpegURL != nil && ffprobeURL != nil }
    public var isDevelopmentFallback: Bool { source == .developmentPATH }
}

public final class FFmpegEngine: ConversionEngine, @unchecked Sendable {
    public let id = "ffmpeg"
    public let capabilities: [ConversionCapability]
    public let availability: FFmpegAvailability

    private let processStore = ProcessStore()
    private let inventory: FFmpegInventory

    public init() {
        let resolved = Self.resolveBinaries()
        availability = resolved
        if let ffmpegURL = resolved.ffmpegURL {
            inventory = FFmpegInventory.inspect(ffmpegURL: ffmpegURL)
        } else {
            inventory = .empty
        }
        capabilities = Self.makeCapabilities(availability: resolved, inventory: inventory)
    }

    public init(ffmpegURL: URL, ffprobeURL: URL, source: FFmpegBinarySource = .developmentPATH) {
        availability = FFmpegAvailability(
            source: source,
            ffmpegURL: ffmpegURL,
            ffprobeURL: ffprobeURL
        )
        inventory = FFmpegInventory.inspect(ffmpegURL: ffmpegURL)
        capabilities = Self.makeCapabilities(availability: availability, inventory: inventory)
    }

    public func probe(url: URL) async throws -> MediaDescriptor {
        guard let ffprobeURL = availability.ffprobeURL else {
            throw ConversionError.engineUnavailable("ffprobe 未内嵌，开发环境 PATH 中也未找到")
        }
        let arguments = [
            "-v", "error",
            "-show_entries", "format=duration,format_name,size:stream=codec_type,codec_name,width,height,avg_frame_rate",
            "-of", "json",
            url.path
        ]
        let result = try ProcessRunner.capture(executableURL: ffprobeURL, arguments: arguments)
        guard result.status == 0 else {
            throw ConversionError.processFailed(result.output.nonEmpty ?? "ffprobe 无法读取文件")
        }
        let data = Data(result.output.utf8)
        let payload: FFprobePayload
        do {
            payload = try JSONDecoder().decode(FFprobePayload.self, from: data)
        } catch {
            throw ConversionError.processFailed("ffprobe 返回了无效数据：\(error.localizedDescription)")
        }
        guard let format = Self.detectFormat(payload: payload, url: url) else {
            throw ConversionError.unsupportedInput(url)
        }

        let videoStream = payload.streams.first { $0.codecType == "video" }
        let hasAudio = payload.streams.contains { $0.codecType == "audio" }
        let duration = Double(payload.format.duration ?? "")
        let size = Int64(payload.format.size ?? "")
            ?? ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0)
        return MediaDescriptor(
            url: url,
            format: format,
            byteCount: size,
            pixelWidth: videoStream?.width,
            pixelHeight: videoStream?.height,
            durationSeconds: duration,
            frameRate: Self.parseFrameRate(videoStream?.averageFrameRate),
            hasAudio: hasAudio,
            codecName: videoStream?.codecName ?? payload.streams.first?.codecName
        )
    }

    public func validate(source: MediaDescriptor, output: FormatID, options: ConversionOptions) throws {
        try SharedValidation.validateCommon(options)
        guard availability.isAvailable else {
            throw ConversionError.engineUnavailable("FFmpeg/ffprobe 未内嵌，开发环境 PATH 中也未找到")
        }
        guard capabilities.contains(where: { $0.input == source.format && $0.output == output }) else {
            throw ConversionError.unsupportedConversion(source.format, output)
        }
        if let end = options.trimEndSeconds,
           let duration = source.durationSeconds,
           end > duration + 0.001 {
            throw ConversionError.invalidOptions("结束时间超过媒体时长")
        }
        if let bitrate = options.videoBitrateKbps, bitrate <= 0 {
            throw ConversionError.invalidOptions("视频码率必须大于 0")
        }
        if let bitrate = options.audioBitrateKbps, bitrate <= 0 {
            throw ConversionError.invalidOptions("音频码率必须大于 0")
        }
        if let frameRate = options.frameRate, frameRate <= 0 {
            throw ConversionError.invalidOptions("帧率必须大于 0")
        }
        if let sampleRate = options.sampleRate, sampleRate <= 0 {
            throw ConversionError.invalidOptions("采样率必须大于 0")
        }
        if let channels = options.audioChannels, !(1...8).contains(channels) {
            throw ConversionError.invalidOptions("声道数必须在 1 到 8 之间")
        }
        if output.category == .video {
            guard source.pixelWidth != nil, source.pixelHeight != nil else {
                throw ConversionError.invalidOptions("源文件没有可转换的视频画面")
            }
            _ = try selectedVideoEncoder(
                for: output,
                requested: options.videoCodec,
                preferHardware: options.preferHardwareEncoding
            )
        } else if output.category == .animatedImage {
            guard source.pixelWidth != nil, source.pixelHeight != nil else {
                throw ConversionError.invalidOptions("源文件没有可转换的视频画面")
            }
            guard options.videoCodec == .automatic else {
                throw ConversionError.invalidOptions("GIF 输出不能设置视频编码器")
            }
        } else if options.videoCodec != .automatic {
            throw ConversionError.invalidOptions("音频或 GIF 输出不能设置视频编码器")
        }
        if output.category == .audio, source.hasAudio != true {
            throw ConversionError.invalidOptions("源文件没有可转换的音轨")
        }
        if output.category == .audio,
           preferredAudioEncoder(for: output) == "vorbis",
           let channels = options.audioChannels,
           channels != 2 {
            throw ConversionError.invalidOptions("内置 Vorbis 编码器当前只支持双声道输出")
        }
    }

    public func makePlan(
        jobID: UUID,
        source: MediaDescriptor,
        output: FormatID,
        destination: URL,
        options: ConversionOptions
    ) throws -> ConversionPlan {
        try validate(source: source, output: output, options: options)
        return try SharedValidation.makePlan(
            engineID: id,
            capabilities: capabilities,
            jobID: jobID,
            source: source,
            output: output,
            destination: destination,
            options: options
        )
    }

    public func run(
        plan: ConversionPlan,
        progress: @escaping @Sendable (ConversionProgress) -> Void
    ) async throws -> URL {
        guard plan.engineID == id else {
            throw ConversionError.invalidOptions("任务不属于 FFmpeg 引擎")
        }
        guard let executableURL = availability.ffmpegURL else {
            throw ConversionError.engineUnavailable("FFmpeg 不可用")
        }
        try validate(source: plan.source, output: plan.outputFormat, options: plan.options)
        try Task.checkCancellation()
        try EngineFileSafety.prepareTemporaryOutput(for: plan)

        let arguments = try makeArguments(for: plan)
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        let processBox = ProcessBox(process: process, outputPipe: outputPipe, errorPipe: errorPipe)

        do {
            let outcome = try await withTaskCancellationHandler {
                try await runProcess(
                    processBox,
                    jobID: plan.jobID,
                    duration: effectiveDuration(for: plan),
                    progress: progress
                )
            } onCancel: {
                self.processStore.cancel(jobID: plan.jobID)
            }
            if outcome.cancelled || Task.isCancelled {
                throw ConversionError.cancelled
            }
            guard outcome.status == 0 else {
                throw ConversionError.processFailed(outcome.error.nonEmpty ?? "FFmpeg 退出码 \(outcome.status)")
            }
            try Task.checkCancellation()
            let result = try EngineFileSafety.commitTemporaryOutput(for: plan)
            progress(.init(fraction: 1, detail: "转换完成"))
            return result
        } catch is CancellationError {
            processStore.cancel(jobID: plan.jobID)
            EngineFileSafety.cleanupTemporaryOutput(for: plan)
            throw ConversionError.cancelled
        } catch {
            EngineFileSafety.cleanupTemporaryOutput(for: plan)
            throw error
        }
    }

    public func cancel(jobID: UUID) async {
        processStore.cancel(jobID: jobID)
    }

    private func runProcess(
        _ box: ProcessBox,
        jobID: UUID,
        duration: Double?,
        progress: @escaping @Sendable (ConversionProgress) -> Void
    ) async throws -> ProcessOutcome {
        do {
            try box.process.run()
        } catch {
            processStore.remove(jobID: jobID)
            throw ConversionError.processFailed("无法启动 FFmpeg：\(error.localizedDescription)")
        }
        guard processStore.register(box.process, jobID: jobID) else {
            box.process.terminate()
            box.process.waitUntilExit()
            processStore.remove(jobID: jobID)
            throw ConversionError.cancelled
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let stderrCollector = LockedData()
                let stderrGroup = DispatchGroup()
                stderrGroup.enter()
                DispatchQueue.global(qos: .utility).async {
                    stderrCollector.set(box.errorPipe.fileHandleForReading.readDataToEndOfFile())
                    stderrGroup.leave()
                }

                var lineBuffer = Data()
                while true {
                    let chunk = box.outputPipe.fileHandleForReading.readData(ofLength: 4096)
                    if chunk.isEmpty { break }
                    lineBuffer.append(chunk)
                    Self.consumeProgressLines(buffer: &lineBuffer, duration: duration, progress: progress)
                }
                Self.consumeProgressLines(buffer: &lineBuffer, duration: duration, progress: progress, consumeRemainder: true)
                // Process may already have been reaped by Foundation by the time
                // the progress pipe reaches EOF. Calling waitUntilExit again can
                // stall on some macOS versions during long sequential queues.
                if box.process.isRunning {
                    box.process.waitUntilExit()
                }
                stderrGroup.wait()
                let cancelled = self.processStore.remove(jobID: jobID)
                let errorText = String(data: stderrCollector.value, encoding: .utf8) ?? ""
                continuation.resume(returning: ProcessOutcome(
                    status: box.process.terminationStatus,
                    error: errorText.trimmingCharacters(in: .whitespacesAndNewlines),
                    cancelled: cancelled
                ))
            }
        }
    }

    private func makeArguments(for plan: ConversionPlan) throws -> [String] {
        var arguments = [
            "-nostdin", "-hide_banner", "-loglevel", "error",
            "-progress", "pipe:1", "-nostats", "-n",
            "-i", plan.source.url.path
        ]

        if let start = plan.options.trimStartSeconds {
            arguments += ["-ss", Self.decimal(start)]
        }
        if let end = plan.options.trimEndSeconds {
            let length = end - (plan.options.trimStartSeconds ?? 0)
            arguments += ["-t", Self.decimal(length)]
        }

        switch plan.outputFormat.category {
        case .video:
            let encoder = try selectedVideoEncoder(
                for: plan.outputFormat,
                requested: plan.options.videoCodec,
                preferHardware: plan.options.preferHardwareEncoding
            )
            arguments += ["-c:v", encoder]
            if let bitrate = plan.options.videoBitrateKbps {
                arguments += ["-b:v", "\(bitrate)k"]
            }
            let filters = videoFilters(options: plan.options, includeDefaultGIFFrameRate: false)
            if !filters.isEmpty { arguments += ["-vf", filters.joined(separator: ",")] }
            if plan.options.removeAudio || plan.source.hasAudio != true {
                arguments.append("-an")
            } else if let audioEncoder = preferredAudioEncoder(for: plan.outputFormat) {
                arguments += ["-c:a", audioEncoder]
                arguments += encoderCompatibilityArguments(for: audioEncoder, options: plan.options)
                arguments += audioArguments(options: plan.options)
            }
            if encoder.contains("h264") || encoder.contains("hevc") {
                arguments += ["-pix_fmt", "yuv420p"]
            }
        case .audio:
            arguments.append("-vn")
            guard let encoder = preferredAudioEncoder(for: plan.outputFormat) else {
                throw ConversionError.engineUnavailable("缺少 \(plan.outputFormat.displayName) 音频编码器")
            }
            arguments += ["-c:a", encoder]
            arguments += encoderCompatibilityArguments(for: encoder, options: plan.options)
            arguments += audioArguments(options: plan.options)
        case .animatedImage:
            arguments.append("-an")
            let filters = videoFilters(options: plan.options, includeDefaultGIFFrameRate: true)
            if !filters.isEmpty { arguments += ["-vf", filters.joined(separator: ",")] }
            arguments += ["-loop", "0"]
        case .image, .pdf:
            throw ConversionError.unsupportedConversion(plan.source.format, plan.outputFormat)
        }

        arguments += plan.options.metadataPolicy == .preserve
            ? ["-map_metadata", "0"]
            : ["-map_metadata", "-1"]
        arguments += ["-f", Self.outputMuxer(for: plan.outputFormat)]
        arguments.append(plan.temporaryURL.path)
        return arguments
    }

    private func videoFilters(options: ConversionOptions, includeDefaultGIFFrameRate: Bool) -> [String] {
        var filters: [String] = []
        if let crop = options.crop {
            filters.append("crop=\(crop.width):\(crop.height):\(crop.x):\(crop.y)")
        }
        let rotation = ((options.rotationDegrees % 360) + 360) % 360
        switch rotation {
        case 90: filters.append("transpose=clock")
        case 180: filters += ["hflip", "vflip"]
        case 270: filters.append("transpose=cclock")
        default: break
        }
        switch (options.width, options.height) {
        case let (width?, height?):
            if options.preserveAspectRatio {
                filters.append("scale=w=\(width):h=\(height):force_original_aspect_ratio=decrease:force_divisible_by=2")
            } else {
                filters.append("scale=\(width):\(height)")
            }
        case let (width?, nil): filters.append("scale=\(width):-2")
        case let (nil, height?): filters.append("scale=-2:\(height)")
        case (nil, nil): break
        }
        if let frameRate = options.frameRate {
            filters.append("fps=\(Self.decimal(frameRate))")
        } else if includeDefaultGIFFrameRate {
            filters.append("fps=12")
        }
        return filters
    }

    private func audioArguments(options: ConversionOptions) -> [String] {
        var arguments: [String] = []
        if let bitrate = options.audioBitrateKbps { arguments += ["-b:a", "\(bitrate)k"] }
        if let sampleRate = options.sampleRate { arguments += ["-ar", "\(sampleRate)"] }
        if let channels = options.audioChannels { arguments += ["-ac", "\(channels)"] }
        if options.normalizeAudio { arguments += ["-af", "loudnorm"] }
        return arguments
    }

    private func encoderCompatibilityArguments(
        for encoder: String,
        options: ConversionOptions
    ) -> [String] {
        // FFmpeg's bundled native Opus and Vorbis encoders are explicitly marked
        // experimental. Enable them only when the inventory selected those exact
        // native encoders; external libopus/libvorbis builds do not need this.
        var arguments = encoder == "opus" || encoder == "vorbis"
            ? ["-strict", "experimental"]
            : []
        if encoder == "vorbis", options.audioChannels == nil {
            arguments += ["-ac", "2"]
        }
        return arguments
    }

    private func selectedVideoEncoder(
        for output: FormatID,
        requested: VideoCodec,
        preferHardware: Bool
    ) throws -> String {
        if requested == .automatic {
            let candidates: [String]
            switch output {
            case .mp4:
                candidates = ["h264_videotoolbox", "libx264", "h264", "hevc_videotoolbox", "libx265", "hevc", "av1_videotoolbox", "libsvtav1", "libaom-av1", "av1"]
            case .mov:
                candidates = ["h264_videotoolbox", "libx264", "h264", "hevc_videotoolbox", "libx265", "hevc", "prores_videotoolbox", "prores_ks", "prores"]
            case .mkv:
                candidates = ["h264_videotoolbox", "libx264", "h264", "hevc_videotoolbox", "libx265", "hevc", "libvpx-vp9", "vp9", "libsvtav1", "libaom-av1", "av1"]
            case .webm:
                candidates = ["libvpx-vp9", "vp9", "libsvtav1", "libaom-av1", "av1"]
            default:
                candidates = []
            }
            guard let encoder = prioritized(candidates, preferHardware: preferHardware)
                .first(where: inventory.encoders.contains) else {
                throw ConversionError.engineUnavailable("当前 FFmpeg 缺少适用于 \(output.displayName) 的视频编码器")
            }
            return encoder
        }

        let codec = requested
        guard Self.allowedCodecs(for: output).contains(codec) else {
            throw ConversionError.invalidOptions("\(output.displayName) 不支持 \(codec.rawValue) 编码")
        }
        let candidates: [String]
        switch codec {
        case .automatic: candidates = []
        case .h264: candidates = ["h264_videotoolbox", "libx264", "h264"]
        case .hevc: candidates = ["hevc_videotoolbox", "libx265", "hevc"]
        case .proRes: candidates = ["prores_videotoolbox", "prores_ks", "prores"]
        case .vp9: candidates = ["libvpx-vp9", "vp9"]
        case .av1: candidates = ["av1_videotoolbox", "libsvtav1", "libaom-av1", "av1"]
        }
        guard let encoder = prioritized(candidates, preferHardware: preferHardware)
            .first(where: inventory.encoders.contains) else {
            throw ConversionError.engineUnavailable("当前 FFmpeg 未包含 \(codec.rawValue) 编码器")
        }
        return encoder
    }

    private func prioritized(_ candidates: [String], preferHardware: Bool) -> [String] {
        guard !preferHardware else { return candidates }
        let software = candidates.filter { !$0.contains("videotoolbox") }
        let hardware = candidates.filter { $0.contains("videotoolbox") }
        return software + hardware
    }

    private func preferredAudioEncoder(for output: FormatID) -> String? {
        let candidates: [String]
        switch output {
        case .mp3: candidates = ["libmp3lame", "mp3"]
        case .m4a, .aac: candidates = ["aac"]
        case .wav: candidates = ["pcm_s16le"]
        case .aiff: candidates = ["pcm_s16be"]
        case .flac: candidates = ["flac"]
        case .alac: candidates = ["alac"]
        case .ogg: candidates = ["libvorbis", "vorbis", "libopus"]
        case .opus: candidates = ["libopus", "opus"]
        case .webm: candidates = ["libopus", "opus", "libvorbis", "vorbis"]
        case .mp4, .mov, .mkv: candidates = ["aac", "libopus", "opus"]
        default: return nil
        }
        return candidates.first(where: inventory.encoders.contains)
    }

    private func effectiveDuration(for plan: ConversionPlan) -> Double? {
        guard let fullDuration = plan.source.durationSeconds else { return nil }
        let start = plan.options.trimStartSeconds ?? 0
        let end = min(plan.options.trimEndSeconds ?? fullDuration, fullDuration)
        return max(0, end - start)
    }

    private static func consumeProgressLines(
        buffer: inout Data,
        duration: Double?,
        progress: @escaping @Sendable (ConversionProgress) -> Void,
        consumeRemainder: Bool = false
    ) {
        while let newline = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[..<newline]
            buffer.removeSubrange(...newline)
            if let line = String(data: lineData, encoding: .utf8) {
                emitProgress(line: line, duration: duration, progress: progress)
            }
        }
        if consumeRemainder, !buffer.isEmpty {
            if let line = String(data: buffer, encoding: .utf8) {
                emitProgress(line: line, duration: duration, progress: progress)
            }
            buffer.removeAll()
        }
    }

    private static func emitProgress(
        line: String,
        duration: Double?,
        progress: @escaping @Sendable (ConversionProgress) -> Void
    ) {
        let pair = line.split(separator: "=", maxSplits: 1).map(String.init)
        guard pair.count == 2 else { return }
        if pair[0] == "progress", pair[1] == "end" {
            progress(.init(fraction: 0.99, detail: "正在完成文件"))
            return
        }
        guard (pair[0] == "out_time_us" || pair[0] == "out_time_ms"),
              let microseconds = Double(pair[1]),
              let duration,
              duration > 0 else { return }
        let fraction = microseconds / 1_000_000 / duration
        progress(.init(fraction: min(fraction, 0.99), detail: "正在转换"))
    }

    private static func makeCapabilities(
        availability: FFmpegAvailability,
        inventory: FFmpegInventory
    ) -> [ConversionCapability] {
        guard availability.isAvailable else { return [] }
        let videoInputs: [FormatID] = [.mp4, .mov, .mkv, .webm]
        let audioInputs: [FormatID] = [.mp3, .m4a, .aac, .wav, .aiff, .flac, .alac, .ogg, .opus]
        let videoOutputs: [FormatID] = [.mp4, .mov, .mkv, .webm].filter {
            outputFormatIsAvailable($0, inventory: inventory)
        }
        let audioOutputs: [FormatID] = [.mp3, .m4a, .aac, .wav, .aiff, .flac, .alac, .ogg, .opus].filter {
            outputFormatIsAvailable($0, inventory: inventory)
        }
        let gifAvailable = outputFormatIsAvailable(.gif, inventory: inventory)

        var result: [ConversionCapability] = []
        for input in videoInputs {
            for output in videoOutputs {
                result.append(.init(
                    engineID: "ffmpeg", input: input, output: output,
                    supportsResize: true, supportsCrop: true, supportsTrim: true, supportsMetadata: true
                ))
            }
            for output in audioOutputs {
                result.append(.init(
                    engineID: "ffmpeg", input: input, output: output,
                    supportsTrim: true, supportsMetadata: true
                ))
            }
            if gifAvailable {
                result.append(.init(
                    engineID: "ffmpeg", input: input, output: .gif,
                    supportsResize: true, supportsCrop: true, supportsTrim: true, supportsMetadata: false
                ))
            }
        }
        if gifAvailable {
            for output in videoOutputs {
                result.append(.init(
                    engineID: "ffmpeg", input: .gif, output: output,
                    supportsResize: true, supportsCrop: true, supportsTrim: true, supportsMetadata: false
                ))
            }
            result.append(.init(
                engineID: "ffmpeg", input: .gif, output: .gif,
                supportsResize: true, supportsCrop: true, supportsTrim: true, supportsMetadata: false
            ))
        }
        for input in audioInputs {
            for output in audioOutputs {
                result.append(.init(
                    engineID: "ffmpeg", input: input, output: output,
                    supportsTrim: true, supportsMetadata: true
                ))
            }
        }
        return result
    }

    private static func outputFormatIsAvailable(_ format: FormatID, inventory: FFmpegInventory) -> Bool {
        let muxers: [String]
        let encoders: [String]
        switch format {
        case .mp4: muxers = ["mp4"]; encoders = ["h264_videotoolbox", "libx264", "h264", "hevc_videotoolbox", "libx265", "hevc"]
        case .mov: muxers = ["mov"]; encoders = ["h264_videotoolbox", "libx264", "h264", "prores_videotoolbox", "prores_ks", "prores"]
        case .mkv: muxers = ["matroska"]; encoders = ["h264_videotoolbox", "libx264", "h264", "libvpx-vp9", "vp9"]
        case .webm: muxers = ["webm"]; encoders = ["libvpx-vp9", "vp9", "libsvtav1", "libaom-av1", "av1"]
        case .gif: muxers = ["gif"]; encoders = ["gif"]
        case .mp3: muxers = ["mp3"]; encoders = ["libmp3lame", "mp3"]
        case .m4a: muxers = ["ipod"]; encoders = ["aac"]
        case .aac: muxers = ["adts", "aac"]; encoders = ["aac"]
        case .wav: muxers = ["wav"]; encoders = ["pcm_s16le"]
        case .aiff: muxers = ["aiff"]; encoders = ["pcm_s16be"]
        case .flac: muxers = ["flac"]; encoders = ["flac"]
        case .alac: muxers = ["ipod"]; encoders = ["alac"]
        case .ogg: muxers = ["ogg"]; encoders = ["libvorbis", "vorbis", "libopus"]
        case .opus: muxers = ["opus", "ogg"]; encoders = ["libopus", "opus"]
        default: return false
        }
        return muxers.contains(where: inventory.muxers.contains)
            && encoders.contains(where: inventory.encoders.contains)
    }

    private static func allowedCodecs(for output: FormatID) -> Set<VideoCodec> {
        switch output {
        case .mp4: [.h264, .hevc, .av1]
        case .mov: [.h264, .hevc, .proRes]
        case .mkv: [.h264, .hevc, .proRes, .vp9, .av1]
        case .webm: [.vp9, .av1]
        default: []
        }
    }

    private static func detectFormat(payload: FFprobePayload, url: URL) -> FormatID? {
        let names = Set(payload.format.formatName.split(separator: ",").map(String.init))
        let extensionFormat = FormatID.from(url: url)
        let hasVideo = payload.streams.contains { $0.codecType == "video" }
        let audioCodec = payload.streams.first { $0.codecType == "audio" }?.codecName

        if names.contains("gif") { return .gif }
        if names.contains("matroska") || names.contains("webm") {
            return extensionFormat == .webm || names == ["webm"] ? .webm : .mkv
        }
        if !names.isDisjoint(with: ["mov", "mp4", "m4a", "3gp", "3g2", "mj2"]) {
            if extensionFormat == .mov { return .mov }
            if !hasVideo, audioCodec == "alac" { return .alac }
            if !hasVideo, extensionFormat == .m4a { return .m4a }
            return hasVideo ? .mp4 : .m4a
        }
        if names.contains("mp3") { return .mp3 }
        if names.contains("aac") { return .aac }
        if names.contains("wav") { return .wav }
        if names.contains("aiff") { return .aiff }
        if names.contains("flac") { return .flac }
        if names.contains("ogg") {
            return audioCodec == "opus" ? .opus : .ogg
        }
        return nil
    }

    private static func parseFrameRate(_ value: String?) -> Double? {
        guard let value else { return nil }
        let parts = value.split(separator: "/")
        if parts.count == 2, let numerator = Double(parts[0]), let denominator = Double(parts[1]), denominator != 0 {
            return numerator / denominator
        }
        return Double(value)
    }

    private static func decimal(_ value: Double) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func outputMuxer(for output: FormatID) -> String {
        switch output {
        case .mp4: "mp4"
        case .mov: "mov"
        case .mkv: "matroska"
        case .webm: "webm"
        case .gif: "gif"
        case .mp3: "mp3"
        case .m4a, .alac: "ipod"
        case .aac: "adts"
        case .wav: "wav"
        case .aiff: "aiff"
        case .flac: "flac"
        case .ogg: "ogg"
        case .opus: "opus"
        case .jpeg, .png, .heic, .tiff, .bmp, .webp, .avif, .pdf: "data"
        }
    }

    private static func resolveBinaries() -> FFmpegAvailability {
        let fileManager = FileManager.default
        let bundle = Bundle.main
        let helpersURL = bundle.bundleURL.appendingPathComponent("Contents/Helpers", isDirectory: true)
        let resourceCandidates: [(URL?, URL?)] = [
            (bundle.url(forAuxiliaryExecutable: "ffmpeg"), bundle.url(forAuxiliaryExecutable: "ffprobe")),
            (helpersURL.appendingPathComponent("ffmpeg"), helpersURL.appendingPathComponent("ffprobe")),
            (bundle.resourceURL?.appendingPathComponent("ffmpeg"), bundle.resourceURL?.appendingPathComponent("ffprobe")),
            (bundle.executableURL?.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/ffmpeg"),
             bundle.executableURL?.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/ffprobe"))
        ]
        for (ffmpeg, ffprobe) in resourceCandidates {
            if let ffmpeg, let ffprobe,
               fileManager.isExecutableFile(atPath: ffmpeg.path),
               fileManager.isExecutableFile(atPath: ffprobe.path) {
                return FFmpegAvailability(source: .bundled, ffmpegURL: ffmpeg, ffprobeURL: ffprobe)
            }
        }

        let paths = ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":").map(String.init) ?? []
        let ffmpeg = paths.lazy.map { URL(fileURLWithPath: $0).appendingPathComponent("ffmpeg") }
            .first { fileManager.isExecutableFile(atPath: $0.path) }
        let ffprobe = paths.lazy.map { URL(fileURLWithPath: $0).appendingPathComponent("ffprobe") }
            .first { fileManager.isExecutableFile(atPath: $0.path) }
        if let ffmpeg, let ffprobe {
            return FFmpegAvailability(source: .developmentPATH, ffmpegURL: ffmpeg, ffprobeURL: ffprobe)
        }
        return FFmpegAvailability(source: .unavailable, ffmpegURL: nil, ffprobeURL: nil)
    }
}

private struct FFprobePayload: Decodable {
    struct Format: Decodable {
        let duration: String?
        let formatName: String
        let size: String?

        enum CodingKeys: String, CodingKey {
            case duration, size
            case formatName = "format_name"
        }
    }

    struct Stream: Decodable {
        let codecType: String?
        let codecName: String?
        let width: Int?
        let height: Int?
        let averageFrameRate: String?

        enum CodingKeys: String, CodingKey {
            case width, height
            case codecType = "codec_type"
            case codecName = "codec_name"
            case averageFrameRate = "avg_frame_rate"
        }
    }

    let format: Format
    let streams: [Stream]
}

private struct FFmpegInventory: Sendable {
    let encoders: Set<String>
    let muxers: Set<String>

    static let empty = FFmpegInventory(encoders: [], muxers: [])

    static func inspect(ffmpegURL: URL) -> FFmpegInventory {
        let encoderOutput = try? ProcessRunner.capture(
            executableURL: ffmpegURL,
            arguments: ["-hide_banner", "-encoders"]
        )
        let muxerOutput = try? ProcessRunner.capture(
            executableURL: ffmpegURL,
            arguments: ["-hide_banner", "-muxers"]
        )
        return FFmpegInventory(
            encoders: parseTable(encoderOutput?.output ?? "", kind: .encoder),
            muxers: parseTable(muxerOutput?.output ?? "", kind: .muxer)
        )
    }

    private enum TableKind { case encoder, muxer }

    private static func parseTable(_ output: String, kind: TableKind) -> Set<String> {
        var result: Set<String> = []
        for line in output.split(separator: "\n") {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2 else { continue }
            let flags = String(fields[0])
            switch kind {
            case .encoder:
                guard flags.count == 6, flags.first == "V" || flags.first == "A" else { continue }
            case .muxer:
                guard flags.contains("E") else { continue }
            }
            for name in fields[1].split(separator: ",") {
                result.insert(String(name))
            }
        }
        return result
    }
}

private struct ProcessCaptureResult: Sendable {
    let status: Int32
    let output: String
}

private enum ProcessRunner {
    static func capture(executableURL: URL, arguments: [String]) throws -> ProcessCaptureResult {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ProcessCaptureResult(
            status: process.terminationStatus,
            output: String(data: data, encoding: .utf8) ?? ""
        )
    }
}

private final class ProcessStore: @unchecked Sendable {
    private let lock = NSLock()
    private var processes: [UUID: Process] = [:]
    private var cancelledJobs: Set<UUID> = []

    func register(_ process: Process, jobID: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelledJobs.contains(jobID) else { return false }
        processes[jobID] = process
        return true
    }

    func cancel(jobID: UUID) {
        lock.lock()
        cancelledJobs.insert(jobID)
        let process = processes[jobID]
        lock.unlock()
        if process?.isRunning == true {
            process?.terminate()
        }
    }

    @discardableResult
    func remove(jobID: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        processes.removeValue(forKey: jobID)
        return cancelledJobs.remove(jobID) != nil
    }
}

private final class ProcessBox: @unchecked Sendable {
    let process: Process
    let outputPipe: Pipe
    let errorPipe: Pipe

    init(process: Process, outputPipe: Pipe, errorPipe: Pipe) {
        self.process = process
        self.outputPipe = outputPipe
        self.errorPipe = errorPipe
    }
}

private final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    var value: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func set(_ data: Data) {
        lock.lock()
        storage = data
        lock.unlock()
    }
}

private struct ProcessOutcome: Sendable {
    let status: Int32
    let error: String
    let cancelled: Bool
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
