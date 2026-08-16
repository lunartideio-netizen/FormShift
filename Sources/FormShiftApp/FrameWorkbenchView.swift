import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import FormShiftCore
import FormShiftEngines

enum FrameToolMode: String, CaseIterable, Identifiable {
    case splitGIF
    case sequenceToGIF
    case extractVideoFrames

    var id: String { rawValue }

    var title: String {
        switch self {
        case .splitGIF: "GIF 拆帧"
        case .sequenceToGIF: "序列图合成 GIF"
        case .extractVideoFrames: "视频抽帧 / 截帧"
        }
    }

    var symbol: String {
        switch self {
        case .splitGIF: "square.split.2x2"
        case .sequenceToGIF: "sparkles.rectangle.stack"
        case .extractVideoFrames: "film.stack.fill"
        }
    }
}

struct FrameWorkbenchView: View {
    @EnvironmentObject private var model: AppModel
    @State private var activeTool: FrameToolMode = .splitGIF

    var body: some View {
        VStack(spacing: 0) {
            toolPickerHeader
            Divider()
            Group {
                switch activeTool {
                case .splitGIF: GIFSplitToolView()
                case .sequenceToGIF: SequenceToGIFToolView()
                case .extractVideoFrames: VideoExtractFramesToolView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(FormShiftTheme.ceramic)
    }

    private var toolPickerHeader: some View {
        HStack(spacing: 12) {
            Picker("帧工具", selection: $activeTool) {
                ForEach(FrameToolMode.allCases) { tool in
                    Label(tool.title, systemImage: tool.symbol).tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 480)

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(.bar)
    }
}

// MARK: - 1. Split GIF

struct GIFSplitToolView: View {
    @State private var sourceURL: URL? = nil
    @State private var frameCount: Int = 0
    @State private var format: FormatID = .png
    @State private var isProcessing = false
    @State private var progressValue: Double = 0
    @State private var createdURLs: [URL] = []
    @State private var errorMessage: String? = nil
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 16) {
            if let err = errorMessage {
                FrameNoticeBanner(message: err, isError: true) { errorMessage = nil }
            }
            if !createdURLs.isEmpty {
                FrameMultiResultBanner(urls: createdURLs, title: "已成功拆分导出 \(createdURLs.count) 张图像帧") { createdURLs.removeAll() }
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("源 GIF 文件")
                        .font(.headline)
                        .foregroundStyle(FormShiftTheme.graphite)

                    if let url = sourceURL {
                        VStack(spacing: 14) {
                            HStack(spacing: 14) {
                                Image(systemName: "sparkles.rectangle.stack.fill")
                                    .font(.system(size: 36))
                                    .foregroundStyle(FormShiftTheme.cobalt)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(url.lastPathComponent)
                                        .font(.title3.weight(.semibold))
                                    Text("总帧数: \(frameCount) 帧 · \(fileSizeString(for: url))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("更换", systemImage: "arrow.triangle.2.circlepath") {
                                    chooseGIF()
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(16)
                            .panelSurface(radius: 12)

                            Spacer()
                        }
                    } else {
                        Button {
                            chooseGIF()
                        } label: {
                            VStack(spacing: 12) {
                                Image(systemName: "square.split.2x2")
                                    .font(.system(size: 38))
                                    .foregroundStyle(FormShiftTheme.cobalt)
                                Text("点击或拖放 GIF 动图到这里")
                                    .font(.headline)
                                    .foregroundStyle(FormShiftTheme.graphite)
                                Text("自动解析所有图像帧并无损批量导出为独立图片")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(isDropTargeted ? FormShiftTheme.cobalt.opacity(0.08) : Color(nsColor: .windowBackgroundColor).opacity(0.5))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(isDropTargeted ? FormShiftTheme.cobalt : FormShiftTheme.graphite.opacity(0.2), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                            )
                        }
                        .buttonStyle(.plain)
                        .dropDestination(for: URL.self) { urls, _ in
                            if let first = urls.first(where: { $0.pathExtension.lowercased() == "gif" }) {
                                loadGIF(first)
                                return true
                            }
                            return false
                        } isTargeted: { targeted in
                            isDropTargeted = targeted
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 16) {
                    Text("拆帧导出设置")
                        .font(.headline)
                        .foregroundStyle(FormShiftTheme.graphite)

                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("导出图片格式")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Picker("格式", selection: $format) {
                                Text("PNG (无损推荐)").tag(FormatID.png)
                                Text("JPEG").tag(FormatID.jpeg)
                            }
                            .labelsHidden()
                        }
                    }
                    .padding(14)
                    .panelSurface(radius: 12)

                    Spacer()

                    if isProcessing {
                        ProgressView(value: progressValue)
                            .progressViewStyle(.linear)
                            .tint(FormShiftTheme.cobalt)
                    }

                    Button {
                        startSplit()
                    } label: {
                        HStack {
                            Image(systemName: "square.split.2x2")
                            Text(isProcessing ? "正在拆帧..." : "开始拆帧")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(sourceURL == nil || isProcessing)
                }
                .frame(width: 280)
            }
        }
        .padding(20)
    }

    private func chooseGIF() {
        let panel = NSOpenPanel()
        panel.title = "选择 GIF 文件"
        panel.allowedContentTypes = [.gif]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadGIF(url)
    }

    private func loadGIF(_ url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            errorMessage = "无法读取所选 GIF 文件"
            return
        }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else {
            errorMessage = "所选文件不包含有效图像帧"
            return
        }
        sourceURL = url
        frameCount = count
        createdURLs.removeAll()
        errorMessage = nil
    }

    private func startSplit() {
        guard let src = sourceURL else { return }
        let panel = NSOpenPanel()
        panel.title = "选择拆帧图片保存文件夹"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let outputDir = panel.url else { return }
        _ = outputDir.startAccessingSecurityScopedResource()

        isProcessing = true
        progressValue = 0
        errorMessage = nil
        createdURLs.removeAll()
        let targetFormat = format

        Task.detached(priority: .userInitiated) {
            defer { outputDir.stopAccessingSecurityScopedResource() }
            do {
                let results = try FrameWorkbenchEngine.splitGIF(
                    gifURL: src,
                    destinationDirectory: outputDir,
                    format: targetFormat
                ) { prog in
                    Task { @MainActor in self.progressValue = prog }
                }
                await MainActor.run {
                    self.isProcessing = false
                    self.progressValue = 1.0
                    self.createdURLs = results
                }
            } catch {
                await MainActor.run {
                    self.isProcessing = false
                    self.errorMessage = "拆帧失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func fileSizeString(for url: URL) -> String {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

// MARK: - 2. Image Sequence to GIF

struct SequenceSourceItem: Identifiable, Equatable {
    let id: UUID = UUID()
    let url: URL
    var fileSize: Int64
}

struct SequenceToGIFToolView: View {
    @State private var items: [SequenceSourceItem] = []
    @State private var frameRate: Double = 15
    @State private var loopCount: Int = 0
    @State private var outputFileName = "动画动图"
    @State private var isProcessing = false
    @State private var progressValue: Double = 0
    @State private var resultURL: URL? = nil
    @State private var errorMessage: String? = nil
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 16) {
            if let err = errorMessage {
                FrameNoticeBanner(message: err, isError: true) { errorMessage = nil }
            }
            if let res = resultURL {
                FrameResultBanner(url: res, title: "已成功生成 GIF 动图") { resultURL = nil }
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("待合成图片序列 (共 \(items.count) 帧)")
                            .font(.headline)
                            .foregroundStyle(FormShiftTheme.graphite)
                        Spacer()
                        if !items.isEmpty {
                            Button("清空列表", systemImage: "trash", role: .destructive) {
                                items.removeAll()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    if items.isEmpty {
                        dropZone
                    } else {
                        VStack(spacing: 10) {
                            List {
                                ForEach(items.indices, id: \.self) { idx in
                                    let item = items[idx]
                                    HStack(spacing: 12) {
                                        Text("\(idx + 1)")
                                            .font(.caption.monospacedDigit().weight(.bold))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 28)
                                        Image(systemName: "photo")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(FormShiftTheme.cobalt)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.url.lastPathComponent)
                                                .font(.callout.weight(.medium))
                                                .lineLimit(1)
                                            Text(ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Button("上移", systemImage: "arrow.up") {
                                            moveItem(from: idx, to: idx - 1)
                                        }
                                        .labelStyle(.iconOnly)
                                        .buttonStyle(.plain)
                                        .disabled(idx == 0)
                                        Button("下移", systemImage: "arrow.down") {
                                            moveItem(from: idx, to: idx + 1)
                                        }
                                        .labelStyle(.iconOnly)
                                        .buttonStyle(.plain)
                                        .disabled(idx == items.count - 1)
                                        Button("移除", systemImage: "xmark.circle", role: .destructive) {
                                            items.remove(at: idx)
                                        }
                                        .labelStyle(.iconOnly)
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                            .listStyle(.inset(alternatesRowBackgrounds: true))
                            .panelSurface(radius: 12)
                            .dropDestination(for: URL.self) { urls, _ in
                                addFiles(urls)
                                return true
                            }

                            Button {
                                chooseFiles()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(FormShiftTheme.cobalt)
                                    Text("添加或拖放更多连续图片")
                                        .font(.callout.weight(.medium))
                                        .foregroundStyle(FormShiftTheme.graphite)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(isDropTargeted ? FormShiftTheme.cobalt.opacity(0.08) : Color(nsColor: .windowBackgroundColor).opacity(0.45))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(isDropTargeted ? FormShiftTheme.cobalt : FormShiftTheme.graphite.opacity(0.16), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                                )
                            }
                            .buttonStyle(.plain)
                            .dropDestination(for: URL.self) { urls, _ in
                                addFiles(urls)
                                return true
                            } isTargeted: { targeted in
                                isDropTargeted = targeted
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 16) {
                    Text("动图参数设置")
                        .font(.headline)
                        .foregroundStyle(FormShiftTheme.graphite)

                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("输出文件名")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            TextField("文件名", text: $outputFileName)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("播放帧率: \(Int(frameRate)) fps (每帧 \(String(format: "%.2f", 1.0 / frameRate)) 秒)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Slider(value: $frameRate, in: 1...60, step: 1)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("循环次数")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Picker("循环模式", selection: $loopCount) {
                                Text("无限循环").tag(0)
                                Text("仅播 1 次").tag(1)
                                Text("循环 3 次").tag(3)
                                Text("循环 5 次").tag(5)
                            }
                            .labelsHidden()
                        }
                    }
                    .padding(14)
                    .panelSurface(radius: 12)

                    Spacer()

                    if isProcessing {
                        ProgressView(value: progressValue)
                            .progressViewStyle(.linear)
                            .tint(FormShiftTheme.cobalt)
                    }

                    Button {
                        startCreateGIF()
                    } label: {
                        HStack {
                            Image(systemName: "sparkles.rectangle.stack.fill")
                            Text(isProcessing ? "正在生成..." : "开始生成 GIF")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(items.isEmpty || isProcessing)
                }
                .frame(width: 280)
            }
        }
        .padding(20)
    }

    private var dropZone: some View {
        Button {
            chooseFiles()
        } label: {
            VStack(spacing: 12) {
                Image(systemName: "photo.stack.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(FormShiftTheme.cobalt)
                Text("添加或拖放多张图片到这里")
                    .font(.headline)
                    .foregroundStyle(FormShiftTheme.graphite)
                Text("支持 PNG、JPEG、TIFF、HEIC、WebP 等图片按序生成高质量动图")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isDropTargeted ? FormShiftTheme.cobalt.opacity(0.08) : Color(nsColor: .windowBackgroundColor).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isDropTargeted ? FormShiftTheme.cobalt : FormShiftTheme.graphite.opacity(0.2), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            )
        }
        .buttonStyle(.plain)
        .dropDestination(for: URL.self) { urls, _ in
            addFiles(urls)
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.title = "选择连续图片序列"
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image, .png, .jpeg, .tiff, .heic, .bmp, .webP]
        guard panel.runModal() == .OK else { return }
        addFiles(panel.urls)
    }

    private func addFiles(_ urls: [URL]) {
        let sorted = urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        for url in sorted {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            items.append(SequenceSourceItem(url: url, fileSize: size))
        }
    }

    private func moveItem(from: Int, to: Int) {
        guard from >= 0, from < items.count, to >= 0, to < items.count else { return }
        let item = items.remove(at: from)
        items.insert(item, at: to)
    }

    private func startCreateGIF() {
        guard !items.isEmpty else { return }
        let panel = NSSavePanel()
        panel.title = "保存生成的 GIF 动图"
        panel.nameFieldStringValue = outputFileName.isEmpty ? "动画动图.gif" : "\(outputFileName).gif"
        panel.allowedContentTypes = [.gif]
        guard panel.runModal() == .OK, let destURL = panel.url else { return }
        _ = destURL.startAccessingSecurityScopedResource()

        isProcessing = true
        progressValue = 0
        errorMessage = nil
        resultURL = nil
        let urls = items.map(\.url)
        let options = FrameSequenceOptions(frameRate: frameRate, loopCount: loopCount)

        Task.detached(priority: .userInitiated) {
            defer { destURL.stopAccessingSecurityScopedResource() }
            do {
                let finalURL = try FrameWorkbenchEngine.createGIF(
                    imageURLs: urls,
                    destinationURL: destURL,
                    options: options
                ) { prog in
                    Task { @MainActor in self.progressValue = prog }
                }
                await MainActor.run {
                    self.isProcessing = false
                    self.progressValue = 1.0
                    self.resultURL = finalURL
                }
            } catch {
                await MainActor.run {
                    self.isProcessing = false
                    self.errorMessage = "生成 GIF 失败：\(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - 3. Extract Video Frames

struct VideoExtractFramesToolView: View {
    @State private var sourceURL: URL? = nil
    @State private var durationSeconds: Double = 0
    @State private var strategyMode: Int = 0
    @State private var intervalSec: Double = 1.0
    @State private var singleTimeSec: Double = 0.0
    @State private var totalCount: Int = 10
    @State private var format: FormatID = .png
    @State private var isProcessing = false
    @State private var progressValue: Double = 0
    @State private var createdURLs: [URL] = []
    @State private var errorMessage: String? = nil
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 16) {
            if let err = errorMessage {
                FrameNoticeBanner(message: err, isError: true) { errorMessage = nil }
            }
            if !createdURLs.isEmpty {
                FrameMultiResultBanner(urls: createdURLs, title: "已成功截取导出 \(createdURLs.count) 张视频静帧") { createdURLs.removeAll() }
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("源视频文件")
                        .font(.headline)
                        .foregroundStyle(FormShiftTheme.graphite)

                    if let url = sourceURL {
                        VStack(spacing: 14) {
                            HStack(spacing: 14) {
                                Image(systemName: "film.fill")
                                    .font(.system(size: 36))
                                    .foregroundStyle(FormShiftTheme.cobalt)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(url.lastPathComponent)
                                        .font(.title3.weight(.semibold))
                                    Text("时长: \(String(format: "%.1f", durationSeconds)) 秒 · \(fileSizeString(for: url))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("更换", systemImage: "arrow.triangle.2.circlepath") {
                                    chooseVideo()
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(16)
                            .panelSurface(radius: 12)

                            Spacer()
                        }
                    } else {
                        Button {
                            chooseVideo()
                        } label: {
                            VStack(spacing: 12) {
                                Image(systemName: "film.stack.fill")
                                    .font(.system(size: 38))
                                    .foregroundStyle(FormShiftTheme.cobalt)
                                Text("点击或拖放视频文件到这里")
                                    .font(.headline)
                                    .foregroundStyle(FormShiftTheme.graphite)
                                Text("支持 MP4、MOV、MKV、WebM 等视频按间隔或指定时间抽取高清帧")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(isDropTargeted ? FormShiftTheme.cobalt.opacity(0.08) : Color(nsColor: .windowBackgroundColor).opacity(0.5))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(isDropTargeted ? FormShiftTheme.cobalt : FormShiftTheme.graphite.opacity(0.2), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                            )
                        }
                        .buttonStyle(.plain)
                        .dropDestination(for: URL.self) { urls, _ in
                            if let first = urls.first(where: { ["mp4", "mov", "mkv", "webm", "m4v"].contains($0.pathExtension.lowercased()) }) {
                                loadVideo(first)
                                return true
                            }
                            return false
                        } isTargeted: { targeted in
                            isDropTargeted = targeted
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 16) {
                    Text("抽帧参数设置")
                        .font(.headline)
                        .foregroundStyle(FormShiftTheme.graphite)

                    VStack(alignment: .leading, spacing: 14) {
                        Picker("抽帧模式", selection: $strategyMode) {
                            Text("固定时间间隔").tag(0)
                            Text("单点精准截帧").tag(1)
                            Text("整片等间隔抽帧").tag(2)
                        }
                        .pickerStyle(.radioGroup)

                        Divider()

                        if strategyMode == 0 {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("每隔 \(String(format: "%.1f", intervalSec)) 秒抽一帧")
                                    .font(.caption.weight(.medium))
                                Slider(value: $intervalSec, in: 0.2...30, step: 0.2)
                            }
                        } else if strategyMode == 1 {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("截取时间点: \(String(format: "%.2f", singleTimeSec)) 秒")
                                    .font(.caption.weight(.medium))
                                Slider(value: $singleTimeSec, in: 0...max(0.1, durationSeconds))
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("全片总帧数: \(totalCount) 张")
                                    .font(.caption.weight(.medium))
                                Stepper("帧数", value: $totalCount, in: 2...200)
                            }
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 4) {
                            Text("导出格式")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Picker("格式", selection: $format) {
                                Text("PNG (高清)").tag(FormatID.png)
                                Text("JPEG").tag(FormatID.jpeg)
                                Text("TIFF").tag(FormatID.tiff)
                            }
                            .labelsHidden()
                        }
                    }
                    .padding(14)
                    .panelSurface(radius: 12)

                    Spacer()

                    if isProcessing {
                        ProgressView(value: progressValue)
                            .progressViewStyle(.linear)
                            .tint(FormShiftTheme.cobalt)
                    }

                    Button {
                        startExtract()
                    } label: {
                        HStack {
                            Image(systemName: "film.stack.fill")
                            Text(isProcessing ? "正在截帧..." : "开始截取视频帧")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(sourceURL == nil || isProcessing)
                }
                .frame(width: 280)
            }
        }
        .padding(20)
    }

    private func chooseVideo() {
        let panel = NSOpenPanel()
        panel.title = "选择视频文件"
        panel.allowedContentTypes = [.movie, .video, .quickTimeMovie, .mpeg4Movie]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadVideo(url)
    }

    private func loadVideo(_ url: URL) {
        let asset = AVURLAsset(url: url)
        Task {
            do {
                let dur = try await asset.load(.duration).seconds
                guard dur > 0 else {
                    await MainActor.run { self.errorMessage = "无法读取视频时长" }
                    return
                }
                await MainActor.run {
                    self.sourceURL = url
                    self.durationSeconds = dur
                    self.singleTimeSec = min(1.0, dur / 2)
                    self.createdURLs.removeAll()
                    self.errorMessage = nil
                }
            } catch {
                await MainActor.run { self.errorMessage = "读取视频信息失败：\(error.localizedDescription)" }
            }
        }
    }

    private func startExtract() {
        guard let src = sourceURL else { return }
        let panel = NSOpenPanel()
        panel.title = "选择帧图片导出文件夹"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let outputDir = panel.url else { return }
        _ = outputDir.startAccessingSecurityScopedResource()

        isProcessing = true
        progressValue = 0
        errorMessage = nil
        createdURLs.removeAll()

        let strategy: VideoFrameExtractionStrategy
        switch strategyMode {
        case 0: strategy = .intervalSeconds(intervalSec)
        case 1: strategy = .singleTimestamp(singleTimeSec)
        default: strategy = .totalCount(totalCount)
        }
        let targetFormat = format

        Task.detached(priority: .userInitiated) {
            defer { outputDir.stopAccessingSecurityScopedResource() }
            do {
                let results = try await FrameWorkbenchEngine.extractVideoFrames(
                    videoURL: src,
                    destinationDirectory: outputDir,
                    strategy: strategy,
                    format: targetFormat
                ) { prog in
                    Task { @MainActor in self.progressValue = prog }
                }
                await MainActor.run {
                    self.isProcessing = false
                    self.progressValue = 1.0
                    self.createdURLs = results
                }
            } catch {
                await MainActor.run {
                    self.isProcessing = false
                    self.errorMessage = "截帧失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func fileSizeString(for url: URL) -> String {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

// MARK: - Helper UI Banners

private struct FrameNoticeBanner: View {
    let message: String
    var isError: Bool = false
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(isError ? FormShiftTheme.danger : FormShiftTheme.cobalt)
            Text(message)
                .font(.callout)
            Spacer()
            Button("关闭", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isError ? FormShiftTheme.danger.opacity(0.1) : FormShiftTheme.cobalt.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct FrameResultBanner: View {
    let url: URL
    let title: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(FormShiftTheme.success)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(url.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("打开文件", systemImage: "arrow.up.forward.app") {
                NSWorkspace.shared.open(url)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Button("在 Finder 中显示", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Button("关闭", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(FormShiftTheme.success.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct FrameMultiResultBanner: View {
    let urls: [URL]
    let title: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(FormShiftTheme.success)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                if let first = urls.first {
                    Text("保存在：\(first.deletingLastPathComponent().path)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let folder = urls.first?.deletingLastPathComponent() {
                Button("打开文件夹", systemImage: "folder") {
                    NSWorkspace.shared.open(folder)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Button("关闭", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(FormShiftTheme.success.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
