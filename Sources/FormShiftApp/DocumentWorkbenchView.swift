import AppKit
import Foundation
import PDFKit
import SwiftUI
import UniformTypeIdentifiers
import FormShiftCore
import FormShiftEngines

enum DocumentToolMode: String, CaseIterable, Identifiable {
    case officeToPDF
    case pdfToOffice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .officeToPDF: "Office / 文本转 PDF"
        case .pdfToOffice: "PDF 逆向转 Word / Excel / 文本"
        }
    }

    var symbol: String {
        switch self {
        case .officeToPDF: "arrow.forward.doc.fill"
        case .pdfToOffice: "doc.text.fill"
        }
    }
}

struct DocumentWorkbenchView: View {
    @EnvironmentObject private var model: AppModel
    @State private var activeTool: DocumentToolMode = .officeToPDF
    @State private var preloadedPDFURL: URL? = nil
    @State private var preloadedOfficeURL: URL? = nil

    var body: some View {
        VStack(spacing: 0) {
            toolPickerHeader
            Divider()
            Group {
                switch activeTool {
                case .officeToPDF: OfficeToPDFToolView(activeTool: $activeTool, preloadedURL: $preloadedOfficeURL, onSwitchToPDF: { url in
                    preloadedPDFURL = url
                    activeTool = .pdfToOffice
                })
                case .pdfToOffice: PDFToOfficeToolView(activeTool: $activeTool, preloadedURL: $preloadedPDFURL, onSwitchToOffice: { url in
                    preloadedOfficeURL = url
                    activeTool = .officeToPDF
                })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(FormShiftTheme.ceramic)
    }

    private var toolPickerHeader: some View {
        HStack(spacing: 12) {
            Picker("文档工具", selection: $activeTool) {
                ForEach(DocumentToolMode.allCases) { tool in
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

// MARK: - 1. Office to PDF Tool View

struct OfficeToPDFToolView: View {
    @Binding var activeTool: DocumentToolMode
    @Binding var preloadedURL: URL?
    var onSwitchToPDF: (URL) -> Void

    @State private var sourceURL: URL? = nil
    @State private var outputFileName = ""
    @State private var isProcessing = false
    @State private var progressValue: Double = 0
    @State private var resultURL: URL? = nil
    @State private var errorMessage: String? = nil
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 16) {
            if let err = errorMessage {
                DocNoticeBanner(message: err, isError: true) { errorMessage = nil }
            }
            if let res = resultURL {
                DocResultBanner(url: res, title: "已成功生成 PDF 文档") { resultURL = nil }
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("源 Office / 文本文件")
                        .font(.headline)
                        .foregroundStyle(FormShiftTheme.graphite)

                    if let url = sourceURL {
                        VStack(spacing: 14) {
                            HStack(spacing: 14) {
                                Image(systemName: fileIcon(for: url))
                                    .font(.system(size: 36))
                                    .foregroundStyle(FormShiftTheme.cobalt)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(url.lastPathComponent)
                                        .font(.title3.weight(.semibold))
                                    Text("类型: \(url.pathExtension.uppercased()) · \(fileSizeString(for: url))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("更换", systemImage: "arrow.triangle.2.circlepath") {
                                    chooseFile()
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(16)
                            .panelSurface(radius: 12)

                            Spacer()
                        }
                    } else {
                        Button {
                            chooseFile()
                        } label: {
                            VStack(spacing: 12) {
                                Image(systemName: "doc.badge.plus")
                                    .font(.system(size: 38))
                                    .foregroundStyle(FormShiftTheme.cobalt)
                                Text("点击或拖放 Word / Excel / PPT / 文本文件到这里")
                                    .font(.headline)
                                    .foregroundStyle(FormShiftTheme.graphite)
                                Text("支持 .docx, .doc, .xlsx, .xls, .pptx, .ppt, .rtf, .txt, .csv 原生或高保真转 PDF")
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
                            if let first = urls.first {
                                handleIncomingFile(first)
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
                    Text("PDF 输出设置")
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

                        VStack(alignment: .leading, spacing: 6) {
                            Text("排版引擎模式")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            if let url = sourceURL, (url.pathExtension.lowercased() == "docx" || url.pathExtension.lowercased() == "doc" || url.pathExtension.lowercased() == "rtf" || url.pathExtension.lowercased() == "txt" || url.pathExtension.lowercased() == "csv") {
                                Label("macOS 原生排版引擎 (开箱即用)", systemImage: "checkmark.seal.fill")
                                    .font(.caption)
                                    .foregroundStyle(FormShiftTheme.success)
                            } else if DocumentWorkbenchEngine.isLibreOfficeAvailable() {
                                Label("已检测到 LibreOffice 高保真排版核心", systemImage: "checkmark.seal.fill")
                                    .font(.caption)
                                    .foregroundStyle(FormShiftTheme.success)
                            } else {
                                Label("Excel/PPT 建议安装 LibreOffice 获得最佳还原", systemImage: "info.circle")
                                    .font(.caption)
                                    .foregroundStyle(FormShiftTheme.processAmber)
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
                        startConvert()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.forward.doc.fill")
                            Text(isProcessing ? "正在转换为 PDF..." : "开始生成 PDF")
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
        .onAppear {
            if let preloaded = preloadedURL {
                loadFile(preloaded)
                preloadedURL = nil
            }
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "选择要转为 PDF 的文档"
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.data]
        panel.allowsOtherFileTypes = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        handleIncomingFile(url)
    }

    private func handleIncomingFile(_ url: URL) {
        if url.pathExtension.lowercased() == "pdf" {
            onSwitchToPDF(url)
        } else {
            loadFile(url)
        }
    }

    private func loadFile(_ url: URL) {
        sourceURL = url
        outputFileName = url.deletingPathExtension().lastPathComponent
        resultURL = nil
        errorMessage = nil
    }

    var bodyWithOnAppear: some View {
        self.onAppear {
            if let preloaded = preloadedURL {
                loadFile(preloaded)
                preloadedURL = nil
            }
        }
    }

    private func startConvert() {
        guard let src = sourceURL else { return }
        let panel = NSSavePanel()
        panel.title = "保存生成的 PDF 文件"
        panel.nameFieldStringValue = outputFileName.isEmpty ? "\(src.deletingPathExtension().lastPathComponent).pdf" : "\(outputFileName).pdf"
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK, let destURL = panel.url else { return }
        _ = destURL.startAccessingSecurityScopedResource()

        isProcessing = true
        progressValue = 0
        errorMessage = nil
        resultURL = nil

        Task.detached(priority: .userInitiated) {
            defer { destURL.stopAccessingSecurityScopedResource() }
            do {
                let finalURL = try DocumentWorkbenchEngine.convertOfficeToPDF(
                    sourceURL: src,
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
                    self.errorMessage = "转换失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func fileIcon(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "docx", "doc": return "doc.text.fill"
        case "xlsx", "xls", "csv": return "tablecells.fill"
        case "pptx", "ppt": return "play.rectangle.fill"
        default: return "doc.fill"
        }
    }

    private func fileSizeString(for url: URL) -> String {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

// MARK: - 2. PDF to Office Tool View

struct PDFToOfficeToolView: View {
    @Binding var activeTool: DocumentToolMode
    @Binding var preloadedURL: URL?
    var onSwitchToOffice: (URL) -> Void

    @State private var sourceURL: URL? = nil
    @State private var totalPages: Int = 0
    @State private var targetFormat: PDFToOfficeFormat = .docx
    @State private var pageScope: PDFPageExportScope = .allPages
    @State private var customRangeText: String = "1-3"
    @State private var outputFileName = ""
    @State private var isProcessing = false
    @State private var progressValue: Double = 0
    @State private var resultURL: URL? = nil
    @State private var errorMessage: String? = nil
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 16) {
            if let err = errorMessage {
                DocNoticeBanner(message: err, isError: true) { errorMessage = nil }
            }
            if let res = resultURL {
                DocResultBanner(url: res, title: "已成功逆向导出文档") { resultURL = nil }
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
                                Image(systemName: "doc.text.viewfinder")
                                    .font(.system(size: 38))
                                    .foregroundStyle(FormShiftTheme.cobalt)
                                Text("点击或拖放 PDF 文件到这里")
                                    .font(.headline)
                                    .foregroundStyle(FormShiftTheme.graphite)
                                Text("逆向重组段落版面转可编辑 Word (.docx)、提取表格转 Excel (.xlsx/.csv) 或导出纯文本")
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
                            if let first = urls.first {
                                handleIncomingFile(first)
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
                    Text("逆向输出设置")
                        .font(.headline)
                        .foregroundStyle(FormShiftTheme.graphite)

                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("目标格式")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Picker("目标格式", selection: $targetFormat) {
                                ForEach(PDFToOfficeFormat.allCases) { fmt in
                                    Text(fmt.displayName).tag(fmt)
                                }
                            }
                            .labelsHidden()
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("导出页面范围")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Picker("导出范围", selection: $pageScope) {
                                Text("全部页面").tag(PDFPageExportScope.allPages)
                                Text("仅第 1 页").tag(PDFPageExportScope.firstPage)
                                Text("指定页码").tag(PDFPageExportScope.customRange)
                            }
                            .labelsHidden()
                        }

                        if pageScope == .customRange {
                            TextField("例如: 1-3, 5", text: $customRangeText)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption.monospaced())
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
                        startConvert()
                    } label: {
                        HStack {
                            Image(systemName: "doc.text.viewfinder")
                            Text(isProcessing ? "正在逆向导出..." : "开始逆向导出")
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
        .onAppear {
            if let preloaded = preloadedURL {
                loadPDF(preloaded)
                preloadedURL = nil
            }
        }
    }

    private func choosePDF() {
        let panel = NSOpenPanel()
        panel.title = "选择 PDF 文件"
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        handleIncomingFile(url)
    }

    private func handleIncomingFile(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        if ["docx", "doc", "xlsx", "xls", "pptx", "ppt", "rtf", "txt", "csv"].contains(ext) {
            onSwitchToOffice(url)
        } else {
            loadPDF(url)
        }
    }

    private func loadPDF(_ url: URL) {
        guard let doc = PDFDocument(url: url), doc.pageCount > 0 else {
            errorMessage = "无法读取所选 PDF 文件"
            return
        }
        sourceURL = url
        totalPages = doc.pageCount
        outputFileName = url.deletingPathExtension().lastPathComponent
        resultURL = nil
        errorMessage = nil
    }

    private func startConvert() {
        guard let src = sourceURL else { return }
        let panel = NSSavePanel()
        panel.title = "保存导出的文档"
        let baseName = outputFileName.isEmpty ? src.deletingPathExtension().lastPathComponent : outputFileName
        panel.nameFieldStringValue = "\(baseName).\(targetFormat.fileExtension)"
        guard panel.runModal() == .OK, let destURL = panel.url else { return }
        _ = destURL.startAccessingSecurityScopedResource()

        isProcessing = true
        progressValue = 0
        errorMessage = nil
        resultURL = nil
        let format = targetFormat
        let options = DocumentConversionOptions(pageScope: pageScope, customPageRange: customRangeText)

        Task.detached(priority: .userInitiated) {
            defer { destURL.stopAccessingSecurityScopedResource() }
            do {
                let finalURL: URL
                switch format {
                case .docx:
                    finalURL = try DocumentWorkbenchEngine.convertPDFToWord(pdfURL: src, destinationURL: destURL, options: options) { prog in
                        Task { @MainActor in self.progressValue = prog }
                    }
                case .xlsx:
                    finalURL = try DocumentWorkbenchEngine.convertPDFToExcel(pdfURL: src, destinationURL: destURL, options: options, asCSV: false) { prog in
                        Task { @MainActor in self.progressValue = prog }
                    }
                case .csv:
                    finalURL = try DocumentWorkbenchEngine.convertPDFToExcel(pdfURL: src, destinationURL: destURL, options: options, asCSV: true) { prog in
                        Task { @MainActor in self.progressValue = prog }
                    }
                case .pptx, .txt:
                    finalURL = try DocumentWorkbenchEngine.convertPDFToText(pdfURL: src, destinationURL: destURL, options: options) { prog in
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
                    self.errorMessage = "导出失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func fileSizeString(for url: URL) -> String {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var bodyWithOnAppear: some View {
        self.onAppear {
            if let preloaded = preloadedURL {
                loadPDF(preloaded)
                preloadedURL = nil
            }
        }
    }
}

// MARK: - Helper UI Banners

private struct DocNoticeBanner: View {
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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .background(isError ? FormShiftTheme.danger.opacity(0.08) : FormShiftTheme.cobalt.opacity(0.08), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(isError ? FormShiftTheme.danger.opacity(0.25) : FormShiftTheme.cobalt.opacity(0.25), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
    }
}

private struct DocResultBanner: View {
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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .background(FormShiftTheme.success.opacity(0.09), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(FormShiftTheme.success.opacity(0.28), lineWidth: 1)
        }
        .shadow(color: FormShiftTheme.success.opacity(0.12), radius: 8, x: 0, y: 3)
    }
}
