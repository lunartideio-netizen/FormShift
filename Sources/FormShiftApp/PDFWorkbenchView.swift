import AppKit
import CoreGraphics
import Foundation
import PDFKit
import SwiftUI
import UniformTypeIdentifiers
import FormShiftCore
import FormShiftEngines

enum PDFToolMode: String, CaseIterable, Identifiable {
    case merge
    case split
    case reorder
    case extractImages

    var id: String { rawValue }

    var title: String {
        switch self {
        case .merge: "合并 / 多图转 PDF"
        case .split: "PDF 拆分"
        case .reorder: "页面重排与旋转"
        case .extractImages: "批量导出图片"
        }
    }

    var symbol: String {
        switch self {
        case .merge: "doc.on.doc.fill"
        case .split: "scissors"
        case .reorder: "arrow.up.arrow.down.square"
        case .extractImages: "photo.on.rectangle.angled"
        }
    }
}

struct PDFWorkbenchView: View {
    @EnvironmentObject private var model: AppModel
    @State private var activeTool: PDFToolMode = .merge

    var body: some View {
        VStack(spacing: 0) {
            toolPickerHeader
            Divider()
            Group {
                switch activeTool {
                case .merge: PDFMergeToolView()
                case .split: PDFSplitToolView()
                case .reorder: PDFReorderRotateToolView()
                case .extractImages: PDFExtractImagesToolView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(FormShiftTheme.ceramic)
    }

    private var toolPickerHeader: some View {
        HStack(spacing: 12) {
            Picker("PDF 工具", selection: $activeTool) {
                ForEach(PDFToolMode.allCases) { tool in
                    Label(tool.title, systemImage: tool.symbol).tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 520)

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(.bar)
    }
}

// MARK: - 1. Merge & Multi-Image to PDF

struct MergeSourceItem: Identifiable, Equatable {
    let id: UUID = UUID()
    let url: URL
    let isPDF: Bool
    var pageCount: Int
    var fileSize: Int64
}

struct PDFMergeToolView: View {
    @State private var items: [MergeSourceItem] = []
    @State private var pageSizePreset: PDFPageSizePreset = .matchImage
    @State private var marginPoints: CGFloat = 0
    @State private var outputFileName = "合并文档"
    @State private var isProcessing = false
    @State private var progressValue: Double = 0
    @State private var resultURL: URL? = nil
    @State private var errorMessage: String? = nil
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 16) {
            if let err = errorMessage {
                NoticeBanner(message: err, isError: true) { errorMessage = nil }
            }
            if let res = resultURL {
                ResultBanner(url: res, title: "已成功生成 PDF 文件") { resultURL = nil }
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("待合并文件列表 (共 \(items.count) 项，预计 \(totalEstimatedPages) 页)")
                            .font(.headline)
                            .foregroundStyle(FormShiftTheme.graphite)
                        Spacer()
                        Button("添加文件", systemImage: "plus") {
                            chooseFiles()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        if !items.isEmpty {
                            Button("清空", systemImage: "trash", role: .destructive) {
                                items.removeAll()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    if items.isEmpty {
                        dropZone
                    } else {
                        List {
                            ForEach(items.indices, id: \.self) { idx in
                                let item = items[idx]
                                HStack(spacing: 12) {
                                    Text("\(idx + 1)")
                                        .font(.caption.monospacedDigit().weight(.bold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 20)
                                    Image(systemName: item.isPDF ? "doc.richtext" : "photo")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(item.isPDF ? FormShiftTheme.danger : FormShiftTheme.cobalt)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.url.lastPathComponent)
                                            .font(.callout.weight(.medium))
                                            .lineLimit(1)
                                        Text(item.isPDF ? "PDF 文件 · \(item.pageCount) 页" : "图片文件 · \(ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file))")
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
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 16) {
                    Text("合并与页面设置")
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
                            Text("图片页面版式")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Picker("版式", selection: $pageSizePreset) {
                                ForEach(PDFPageSizePreset.allCases, id: \.self) { preset in
                                    Text(preset.displayName).tag(preset)
                                }
                            }
                            .labelsHidden()
                        }

                        if pageSizePreset != .matchImage {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("页面边距: \(Int(marginPoints)) pt")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                Slider(value: $marginPoints, in: 0...72, step: 6)
                            }
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
                        startMerge()
                    } label: {
                        HStack {
                            Image(systemName: "doc.on.doc.fill")
                            Text(isProcessing ? "正在合并..." : "开始合并为 PDF")
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

    private var totalEstimatedPages: Int {
        items.reduce(0) { $0 + ($1.isPDF ? $1.pageCount : 1) }
    }

    private var dropZone: some View {
        Button {
            chooseFiles()
        } label: {
            VStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(FormShiftTheme.cobalt)
                Text("添加或拖放图片/PDF 文件到这里")
                    .font(.headline)
                    .foregroundStyle(FormShiftTheme.graphite)
                Text("支持按顺序将多张图片、多个 PDF 或混合文件合并为一份 PDF")
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
        panel.title = "选择要合并的文件"
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf, .image, .jpeg, .png, .tiff, .heic, .bmp, .webP]
        guard panel.runModal() == .OK else { return }
        addFiles(panel.urls)
    }

    private func addFiles(_ urls: [URL]) {
        for url in urls {
            let isPDF = url.pathExtension.lowercased() == "pdf"
            var pages = 1
            if isPDF, let doc = PDFDocument(url: url) {
                pages = doc.pageCount
            }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            items.append(MergeSourceItem(url: url, isPDF: isPDF, pageCount: pages, fileSize: size))
        }
    }

    private func moveItem(from: Int, to: Int) {
        guard from >= 0, from < items.count, to >= 0, to < items.count else { return }
        let item = items.remove(at: from)
        items.insert(item, at: to)
    }

    private func startMerge() {
        guard !items.isEmpty else { return }
        let panel = NSSavePanel()
        panel.title = "保存合并后的 PDF 文件"
        panel.nameFieldStringValue = outputFileName.isEmpty ? "合并文档.pdf" : "\(outputFileName).pdf"
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK, let destURL = panel.url else { return }

        isProcessing = true
        progressValue = 0
        errorMessage = nil
        resultURL = nil

        let mergeItems = items
        let options = PDFImageMergeOptions(pageSizePreset: pageSizePreset, marginPoints: marginPoints)

        Task.detached(priority: .userInitiated) {
            do {
                let allImages = mergeItems.allSatisfy { !$0.isPDF }
                let allPDFs = mergeItems.allSatisfy { $0.isPDF }

                let finalURL: URL
                if allImages {
                    finalURL = try PDFWorkbenchEngine.createPDF(
                        fromImages: mergeItems.map(\.url),
                        destinationURL: destURL,
                        options: options
                    ) { prog in
                        Task { @MainActor in self.progressValue = prog }
                    }
                } else if allPDFs {
                    finalURL = try PDFWorkbenchEngine.mergePDFs(
                        pdfURLs: mergeItems.map(\.url),
                        destinationURL: destURL
                    ) { prog in
                        Task { @MainActor in self.progressValue = prog }
                    }
                } else {
                    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: tempDir) }

                    var pdfSegments: [URL] = []
                    for (idx, item) in mergeItems.enumerated() {
                        if item.isPDF {
                            pdfSegments.append(item.url)
                        } else {
                            let singlePDFURL = tempDir.appendingPathComponent("seg_\(idx).pdf")
                            _ = try PDFWorkbenchEngine.createPDF(
                                fromImages: [item.url],
                                destinationURL: singlePDFURL,
                                options: options
                            )
                            pdfSegments.append(singlePDFURL)
                        }
                    }
                    finalURL = try PDFWorkbenchEngine.mergePDFs(pdfURLs: pdfSegments, destinationURL: destURL) { prog in
                        Task { @MainActor in self.progressValue = prog }
                    }
                }
                await MainActor.run {
                    self.isProcessing = false
                    self.progressValue = 1.0
                    self.resultURL = finalURL
                }
            } catch {
                await MainActor.run {
                    self.isProcessing = false
                    self.errorMessage = "合并失败：\(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - 2. Split PDF

struct PDFSplitToolView: View {
    @State private var sourceURL: URL? = nil
    @State private var totalPages: Int = 0
    @State private var splitModeIndex: Int = 0
    @State private var fixedPageChunk: Int = 1
    @State private var customRangesText: String = "1-2, 3-5"
    @State private var isProcessing = false
    @State private var progressValue: Double = 0
    @State private var createdURLs: [URL] = []
    @State private var errorMessage: String? = nil
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 16) {
            if let err = errorMessage {
                NoticeBanner(message: err, isError: true) { errorMessage = nil }
            }
            if !createdURLs.isEmpty {
                MultiResultBanner(urls: createdURLs, title: "已成功拆分生成 \(createdURLs.count) 份 PDF") { createdURLs.removeAll() }
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("源 PDF 文件")
                        .font(.headline)
                        .foregroundStyle(FormShiftTheme.graphite)

                    if let url = sourceURL {
                        VStack(spacing: 14) {
                            HStack(spacing: 14) {
                                Image(systemName: "doc.richtext.fill")
                                    .font(.system(size: 36))
                                    .foregroundStyle(FormShiftTheme.danger)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(url.lastPathComponent)
                                        .font(.title3.weight(.semibold))
                                    Text("总页数: \(totalPages) 页 · \(fileSizeString(for: url))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("更换", systemImage: "arrow.triangle.2.circlepath") {
                                    choosePDF()
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(16)
                            .panelSurface(radius: 12)

                            Spacer()
                        }
                    } else {
                        Button {
                            choosePDF()
                        } label: {
                            VStack(spacing: 12) {
                                Image(systemName: "scissors.circle.fill")
                                    .font(.system(size: 38))
                                    .foregroundStyle(FormShiftTheme.cobalt)
                                Text("点击或拖放要拆分的 PDF 文件")
                                    .font(.headline)
                                    .foregroundStyle(FormShiftTheme.graphite)
                                Text("支持单页独立拆分、固定页数均分或自定义页码区间")
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
                            if let first = urls.first(where: { $0.pathExtension.lowercased() == "pdf" }) {
                                loadPDF(first)
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
                    Text("拆分策略")
                        .font(.headline)
                        .foregroundStyle(FormShiftTheme.graphite)

                    VStack(alignment: .leading, spacing: 14) {
                        Picker("拆分模式", selection: $splitModeIndex) {
                            Text("每页单独一份").tag(0)
                            Text("按页数均分").tag(1)
                            Text("指定页码区间").tag(2)
                        }
                        .pickerStyle(.radioGroup)

                        Divider()

                        if splitModeIndex == 1 {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("每份页数: \(fixedPageChunk) 页")
                                    .font(.caption.weight(.medium))
                                Stepper("页数", value: $fixedPageChunk, in: 1...max(1, totalPages))
                                    .labelsHidden()
                            }
                        } else if splitModeIndex == 2 {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("页码区间 (逗号分隔)")
                                    .font(.caption.weight(.medium))
                                TextField("例如: 1-3, 4-7, 8", text: $customRangesText)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.caption.monospaced())
                            }
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
                            Image(systemName: "scissors")
                            Text(isProcessing ? "正在拆分..." : "开始拆分 PDF")
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

    private func choosePDF() {
        let panel = NSOpenPanel()
        panel.title = "选择 PDF 文件"
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadPDF(url)
    }

    private func loadPDF(_ url: URL) {
        guard let doc = PDFDocument(url: url), doc.pageCount > 0 else {
            errorMessage = "无法读取所选 PDF 文件"
            return
        }
        sourceURL = url
        totalPages = doc.pageCount
        fixedPageChunk = max(1, min(2, doc.pageCount))
        createdURLs.removeAll()
        errorMessage = nil
    }

    private func startSplit() {
        guard let src = sourceURL else { return }
        let panel = NSOpenPanel()
        panel.title = "选择拆分输出文件夹"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let outputDir = panel.url else { return }

        isProcessing = true
        progressValue = 0
        errorMessage = nil
        createdURLs.removeAll()

        let strategy: PDFSplitStrategy
        switch splitModeIndex {
        case 0: strategy = .eachPage
        case 1: strategy = .fixedPageCount(fixedPageChunk)
        default: strategy = .pageRanges(customRangesText)
        }

        Task.detached(priority: .userInitiated) {
            do {
                let results = try PDFWorkbenchEngine.splitPDF(
                    pdfURL: src,
                    destinationDirectory: outputDir,
                    strategy: strategy
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
                    self.errorMessage = "拆分失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func fileSizeString(for url: URL) -> String {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

// MARK: - 3. Reorder & Rotate PDF Pages

struct PDFReorderRotateToolView: View {
    @State private var sourceURL: URL? = nil
    @State private var pageSpecs: [PDFPageSpec] = []
    @State private var thumbnails: [Int: NSImage] = [:]
    @State private var isProcessing = false
    @State private var progressValue: Double = 0
    @State private var resultURL: URL? = nil
    @State private var errorMessage: String? = nil
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 16) {
            if let err = errorMessage {
                NoticeBanner(message: err, isError: true) { errorMessage = nil }
            }
            if let res = resultURL {
                ResultBanner(url: res, title: "已成功生成重排后的 PDF") { resultURL = nil }
            }

            if pageSpecs.isEmpty {
                emptyDropZone
            } else {
                VStack(spacing: 12) {
                    toolbarHeader
                    pageGridView
                }
            }
        }
        .padding(20)
    }

    private var emptyDropZone: some View {
        Button {
            choosePDF()
        } label: {
            VStack(spacing: 12) {
                Image(systemName: "arrow.up.arrow.down.square.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(FormShiftTheme.cobalt)
                Text("点击或拖放要重排/旋转页面的 PDF")
                    .font(.headline)
                    .foregroundStyle(FormShiftTheme.graphite)
                Text("支持单页/全部顺时针/逆时针旋转，移动重排顺序，或剔除特定页面")
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
            if let first = urls.first(where: { $0.pathExtension.lowercased() == "pdf" }) {
                loadPDF(first)
                return true
            }
            return false
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
    }

    private var toolbarHeader: some View {
        HStack(spacing: 10) {
            Text("\(sourceURL?.lastPathComponent ?? "文档") · 共 \(pageSpecs.count) 页 (保留 \(activePageCount) 页)")
                .font(.headline)
                .foregroundStyle(FormShiftTheme.graphite)

            Spacer()

            Button("全部顺时针 90°", systemImage: "rotate.right") {
                for idx in pageSpecs.indices {
                    pageSpecs[idx].rotationAngle = (pageSpecs[idx].rotationAngle + 90) % 360
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button("全部逆时针 90°", systemImage: "rotate.left") {
                for idx in pageSpecs.indices {
                    let r = (pageSpecs[idx].rotationAngle - 90) % 360
                    pageSpecs[idx].rotationAngle = r < 0 ? r + 360 : r
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button("反转顺序", systemImage: "arrow.up.and.down.righttriangle.up.righttriangle.down") {
                pageSpecs.reverse()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button("重置", systemImage: "arrow.counterclockwise") {
                resetSpecs()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button("导出新 PDF", systemImage: "arrow.down.doc.fill") {
                saveReorderedPDF()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(activePageCount == 0 || isProcessing)
        }
        .padding(.horizontal, 4)
    }

    private var activePageCount: Int {
        pageSpecs.filter(\.isIncluded).count
    }

    private var pageGridView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 16)], spacing: 16) {
                ForEach(pageSpecs.indices, id: \.self) { idx in
                    let spec = pageSpecs[idx]
                    VStack(spacing: 8) {
                        ZStack(alignment: .topTrailing) {
                            thumbnailView(for: spec.originalPageIndex, rotation: spec.rotationAngle)
                                .frame(height: 160)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                                .opacity(spec.isIncluded ? 1.0 : 0.35)

                            if spec.rotationAngle != 0 {
                                Text("\(spec.rotationAngle)°")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(FormShiftTheme.cobalt, in: Capsule())
                                    .padding(6)
                            }
                        }

                        HStack {
                            Text("第 \(idx + 1) 页 (原 \(spec.originalPageIndex))")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(spec.isIncluded ? .primary : .secondary)
                            Spacer()
                            Toggle("", isOn: $pageSpecs[idx].isIncluded)
                                .toggleStyle(.checkbox)
                                .labelsHidden()
                        }

                        HStack(spacing: 6) {
                            Button("向左旋转", systemImage: "rotate.left") {
                                let r = (pageSpecs[idx].rotationAngle - 90) % 360
                                pageSpecs[idx].rotationAngle = r < 0 ? r + 360 : r
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.bordered)
                            .controlSize(.mini)

                            Button("向右旋转", systemImage: "rotate.right") {
                                pageSpecs[idx].rotationAngle = (pageSpecs[idx].rotationAngle + 90) % 360
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.bordered)
                            .controlSize(.mini)

                            Spacer()

                            Button("左移", systemImage: "chevron.left") {
                                movePage(from: idx, to: idx - 1)
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .disabled(idx == 0)

                            Button("右移", systemImage: "chevron.right") {
                                movePage(from: idx, to: idx + 1)
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .disabled(idx == pageSpecs.count - 1)
                        }
                    }
                    .padding(10)
                    .panelSurface(radius: 10)
                }
            }
            .padding(4)
        }
    }

    @ViewBuilder
    private func thumbnailView(for originalPageNum: Int, rotation: Int) -> some View {
        if let img = thumbnails[originalPageNum] {
            Image(nsImage: img)
                .resizable()
                .scaledToFit()
                .rotationEffect(.degrees(Double(rotation)))
        } else {
            VStack {
                ProgressView().controlSize(.small)
                Text("P\(originalPageNum)").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func choosePDF() {
        let panel = NSOpenPanel()
        panel.title = "选择 PDF 文件"
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadPDF(url)
    }

    private func loadPDF(_ url: URL) {
        guard let doc = PDFDocument(url: url), doc.pageCount > 0 else {
            errorMessage = "无法读取所选 PDF 文件"
            return
        }
        sourceURL = url
        pageSpecs = (1...doc.pageCount).map { PDFPageSpec(originalPageIndex: $0) }
        thumbnails.removeAll()
        resultURL = nil
        errorMessage = nil

        // Render thumbnails asynchronously in background
        Task.detached(priority: .userInitiated) {
            for p in 1...doc.pageCount {
                if let page = doc.page(at: p - 1) {
                    let thumb = page.thumbnail(of: CGSize(width: 140, height: 180), for: .mediaBox)
                    await MainActor.run {
                        self.thumbnails[p] = thumb
                    }
                }
            }
        }
    }

    private func movePage(from: Int, to: Int) {
        guard from >= 0, from < pageSpecs.count, to >= 0, to < pageSpecs.count else { return }
        let item = pageSpecs.remove(at: from)
        pageSpecs.insert(item, at: to)
    }

    private func resetSpecs() {
        guard let url = sourceURL, let doc = PDFDocument(url: url) else { return }
        pageSpecs = (1...doc.pageCount).map { PDFPageSpec(originalPageIndex: $0) }
    }

    private func saveReorderedPDF() {
        guard let src = sourceURL else { return }
        let panel = NSSavePanel()
        panel.title = "保存重排后的 PDF"
        let baseName = src.deletingPathExtension().lastPathComponent
        panel.nameFieldStringValue = "\(baseName)_已重排.pdf"
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK, let destURL = panel.url else { return }

        isProcessing = true
        progressValue = 0
        errorMessage = nil
        resultURL = nil
        let specs = pageSpecs

        Task.detached(priority: .userInitiated) {
            do {
                let finalURL = try PDFWorkbenchEngine.reorderAndRotatePDF(
                    pdfURL: src,
                    pageSpecs: specs,
                    destinationURL: destURL
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
                    self.errorMessage = "保存失败：\(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - 4. Extract Images from PDF

struct PDFExtractImagesToolView: View {
    @State private var sourceURL: URL? = nil
    @State private var totalPages: Int = 0
    @State private var format: FormatID = .png
    @State private var scope: PDFPageExportScope = .allPages
    @State private var customRangeText: String = "1-3, 5"
    @State private var scale: Int = 2
    @State private var trimBorders: Bool = false
    @State private var colorProfile: ImageColorProfile = .automatic
    @State private var isProcessing = false
    @State private var progressValue: Double = 0
    @State private var exportedURLs: [URL] = []
    @State private var errorMessage: String? = nil
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 16) {
            if let err = errorMessage {
                NoticeBanner(message: err, isError: true) { errorMessage = nil }
            }
            if !exportedURLs.isEmpty {
                MultiResultBanner(urls: exportedURLs, title: "已成功导出 \(exportedURLs.count) 张图片") { exportedURLs.removeAll() }
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("源 PDF 文件")
                        .font(.headline)
                        .foregroundStyle(FormShiftTheme.graphite)

                    if let url = sourceURL {
                        VStack(spacing: 14) {
                            HStack(spacing: 14) {
                                Image(systemName: "doc.richtext.fill")
                                    .font(.system(size: 36))
                                    .foregroundStyle(FormShiftTheme.danger)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(url.lastPathComponent)
                                        .font(.title3.weight(.semibold))
                                    Text("总页数: \(totalPages) 页 · \(fileSizeString(for: url))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("更换", systemImage: "arrow.triangle.2.circlepath") {
                                    choosePDF()
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(16)
                            .panelSurface(radius: 12)

                            Spacer()
                        }
                    } else {
                        Button {
                            choosePDF()
                        } label: {
                            VStack(spacing: 12) {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.system(size: 38))
                                    .foregroundStyle(FormShiftTheme.cobalt)
                                Text("点击或拖放要提取图片的 PDF 文件")
                                    .font(.headline)
                                    .foregroundStyle(FormShiftTheme.graphite)
                                Text("支持整份导出、高清渲染精度与自动裁白边")
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
                            if let first = urls.first(where: { $0.pathExtension.lowercased() == "pdf" }) {
                                loadPDF(first)
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
                    Text("图片导出设置")
                        .font(.headline)
                        .foregroundStyle(FormShiftTheme.graphite)

                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("目标格式")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Picker("目标格式", selection: $format) {
                                Text("PNG (无损)").tag(FormatID.png)
                                Text("JPEG").tag(FormatID.jpeg)
                                Text("TIFF").tag(FormatID.tiff)
                            }
                            .labelsHidden()
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("导出页面范围")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Picker("导出范围", selection: $scope) {
                                Text("全部页面").tag(PDFPageExportScope.allPages)
                                Text("仅第 1 页").tag(PDFPageExportScope.firstPage)
                                Text("指定页码").tag(PDFPageExportScope.customRange)
                            }
                            .labelsHidden()
                        }

                        if scope == .customRange {
                            TextField("例如: 1-3, 5, 8", text: $customRangeText)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption.monospaced())
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("渲染精度")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Picker("渲染精度", selection: $scale) {
                                Text("标准 · 1×").tag(1)
                                Text("清晰 · 2×").tag(2)
                                Text("高精度 · 3×").tag(3)
                            }
                            .labelsHidden()
                        }

                        Toggle("智能裁剪白边", isOn: $trimBorders)
                            .toggleStyle(.checkbox)
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
                        startExport()
                    } label: {
                        HStack {
                            Image(systemName: "photo.on.rectangle.angled")
                            Text(isProcessing ? "正在导出..." : "开始导出图片")
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

    private func choosePDF() {
        let panel = NSOpenPanel()
        panel.title = "选择 PDF 文件"
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadPDF(url)
    }

    private func loadPDF(_ url: URL) {
        guard let doc = PDFDocument(url: url), doc.pageCount > 0 else {
            errorMessage = "无法读取所选 PDF 文件"
            return
        }
        sourceURL = url
        totalPages = doc.pageCount
        exportedURLs.removeAll()
        errorMessage = nil
    }

    private func startExport() {
        guard let src = sourceURL else { return }
        let panel = NSOpenPanel()
        panel.title = "选择图片导出文件夹"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let outputDir = panel.url else { return }

        isProcessing = true
        progressValue = 0
        errorMessage = nil
        exportedURLs.removeAll()

        let options = ConversionOptions(
            trimBorders: trimBorders,
            imageColorProfile: colorProfile,
            pdfRenderScale: scale,
            pdfPageExportScope: scope,
            pdfCustomPageRange: customRangeText
        )
        let targetFormat = format

        Task.detached(priority: .userInitiated) {
            do {
                let results = try PDFWorkbenchEngine.exportPDFPagesToImages(
                    pdfURL: src,
                    format: targetFormat,
                    options: options,
                    destinationDirectory: outputDir
                ) { prog in
                    Task { @MainActor in self.progressValue = prog }
                }
                await MainActor.run {
                    self.isProcessing = false
                    self.progressValue = 1.0
                    self.exportedURLs = results
                }
            } catch {
                await MainActor.run {
                    self.isProcessing = false
                    self.errorMessage = "导出失败：\(error.localizedDescription)"
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

private struct NoticeBanner: View {
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

private struct ResultBanner: View {
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

private struct MultiResultBanner: View {
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
