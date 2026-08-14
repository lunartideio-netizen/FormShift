import FormShiftCore
import SwiftUI

struct FormShiftRootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            FormShiftSidebar()
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 250)
        } content: {
            WorkspaceView()
                .navigationSplitViewColumnWidth(min: 500, ideal: 720)
        } detail: {
            ConversionInspector()
                .navigationSplitViewColumnWidth(min: 270, ideal: 310, max: 360)
        }
        .navigationSplitViewStyle(.balanced)
        .background(FormShiftTheme.ceramic)
        .tint(FormShiftTheme.cobalt)
        .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: model.selection)
    }
}

private struct FormShiftSidebar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            brand
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 20)

            List(WorkspaceSection.allCases, selection: $model.selection) { section in
                Label {
                    HStack {
                        Text(section.title)
                        Spacer()
                        if let count = count(for: section), count > 0 {
                            Text(count, format: .number)
                                .font(.caption.monospacedDigit().weight(.medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(.primary.opacity(0.07), in: Capsule())
                        }
                    }
                } icon: {
                    Image(systemName: section.symbol)
                }
                .tag(section)
                .accessibilityLabel("\(section.title)\(count(for: section).map { "，\($0) 项" } ?? "")")
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 8) {
                Label("所有处理都在本机完成", systemImage: "lock.shield")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(FormShiftTheme.graphite)
                Text("不上传文件，不覆盖原件。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(FormShiftTheme.ceramic.opacity(0.62), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(12)
        }
        .background(.ultraThinMaterial)
    }

    private var brand: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(FormShiftTheme.graphite)
                    .frame(width: 34, height: 34)
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(FormShiftTheme.ceramic)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("FormShift")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                Text("LOCAL CONVERSION")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(1.25)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("FormShift，本地格式转换")
    }

    private func count(for section: WorkspaceSection) -> Int? {
        switch section {
        case .convert: model.waitingCount
        case .queue: model.waitingCount + model.runningCount
        case .history: model.finishedCount
        case .presets: model.presets.count
        }
    }
}

private struct WorkspaceView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceHeader()

            Divider()

            Group {
                switch model.selection {
                case .presets:
                    PresetsView()
                default:
                    JobWorkspace()
                }
            }
        }
        .background(FormShiftTheme.ceramic)
    }
}

private struct WorkspaceHeader: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.selection.title)
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .foregroundStyle(FormShiftTheme.graphite)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if model.selection == .queue, !model.jobs.isEmpty {
                Button {
                    model.togglePause()
                } label: {
                    Label(model.isPaused ? "继续" : "暂停", systemImage: model.isPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(.bordered)
                .help(model.isPaused ? "允许下一个任务开始" : "当前任务结束后暂停队列")
            }

            if model.selection != .presets {
                Button {
                    model.presentImporter()
                } label: {
                    Label("添加文件", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("o", modifiers: [.command])
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.bar)
    }

    private var subtitle: String {
        switch model.selection {
        case .convert: "选择输出格式，然后开始转换"
        case .queue: model.isPaused ? "队列已暂停，当前任务不会被强制中断" : "按顺序处理，重型任务一次运行一个"
        case .history: "点击记录可恢复上次设置并再次转换"
        case .presets: "保存常用格式与参数组合"
        }
    }
}

private struct JobWorkspace: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            if let notice = model.importNotice {
                NoticeBar(text: notice) {
                    model.importNotice = nil
                }
            }

            if model.selection == .convert {
                ConversionDropZone()
            }

            if model.visibleJobs.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.visibleJobs) { job in
                            JobRow(job: job, isSelected: model.selectedJobID == job.id)
                                .onTapGesture {
                                    if model.selection == .history {
                                        model.requeueFromHistory(jobID: job.id)
                                    } else {
                                        model.selectedJobID = job.id
                                    }
                                }
                                .focusable()
                                .onKeyPress(.return) {
                                    if model.selection == .history {
                                        model.requeueFromHistory(jobID: job.id)
                                    } else {
                                        model.selectedJobID = job.id
                                    }
                                    return .handled
                                }
                        }
                    }
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var emptyState: some View {
        switch model.selection {
        case .history:
            ContentUnavailableView(
                "还没有转换记录",
                systemImage: "clock.arrow.circlepath",
                description: Text("完成、失败或取消的任务会显示在这里。")
            )
        case .queue:
            ContentUnavailableView(
                "队列是空的",
                systemImage: "list.bullet.rectangle",
                description: Text("从“转换”中添加文件，任务会在这里排队。")
            )
        default:
            Spacer(minLength: 0)
        }
    }
}

private struct ConversionDropZone: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            model.presentImporter()
        } label: {
            dropLabel
        }
        .buttonStyle(.plain)
        .accessibilityLabel("添加文件或文件夹")
        .accessibilityHint("点击打开文件选择器，也可以把文件拖到这里")
        .dropDestination(for: URL.self) { urls, _ in
            model.enqueue(urls: urls)
            return !urls.isEmpty
        } isTargeted: { targeted in
            model.isDropTargeted = targeted
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: model.isDropTargeted)
    }

    private var dropLabel: some View {
        VStack(spacing: 11) {
            dropIcon

            Text(model.isDropTargeted ? "松开即可添加" : "把文件或文件夹放在这里")
                .font(.headline)
                .foregroundStyle(FormShiftTheme.graphite)

            Text("图片、视频、音频、PDF 和 GIF · 或按 ⌘O 选择")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, model.jobs.isEmpty ? 48 : 22)
        .background(dropBackground)
        .overlay(dropBorder)
        .contentShape(Rectangle())
    }

    private var dropIcon: some View {
        ZStack {
            Circle()
                .fill(model.isDropTargeted ? FormShiftTheme.cobalt.opacity(0.16) : FormShiftTheme.machineSilver.opacity(0.75))
                .frame(width: 52, height: 52)
            Image(systemName: model.isDropTargeted ? "arrow.down" : "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(model.isDropTargeted ? FormShiftTheme.cobalt : FormShiftTheme.graphite)
        }
        .scaleEffect(model.isDropTargeted && !reduceMotion ? 1.08 : 1)
    }

    private var dropBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(model.isDropTargeted ? FormShiftTheme.cobalt.opacity(0.055) : Color(nsColor: .windowBackgroundColor).opacity(0.58))
    }

    private var dropBorder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(
                model.isDropTargeted ? FormShiftTheme.cobalt : FormShiftTheme.graphite.opacity(0.16),
                style: StrokeStyle(lineWidth: model.isDropTargeted ? 2 : 1, dash: [7, 5])
            )
    }
}

private struct NoticeBar: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(FormShiftTheme.cobalt)
            Text(text)
                .font(.callout)
            Spacer()
            Button("关闭", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .accessibilityLabel("关闭提示")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(FormShiftTheme.cobalt.opacity(0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct PresetsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var presetName = ""

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                TextField("预设名称，例如：网页图片", text: $presetName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(savePreset)
                    .accessibilityLabel("预设名称")
                Button("保存当前设置", systemImage: "plus", action: savePreset)
                    .buttonStyle(.borderedProminent)
                    .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(14)
            .panelSurface(radius: 12)

            if model.presets.isEmpty {
                ContentUnavailableView {
                    Label("还没有预设", systemImage: "slider.horizontal.2.square")
                } description: {
                    Text("在右侧调整格式和参数，输入名称后保存。")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.presets) { preset in
                            HStack(spacing: 14) {
                                Text(preset.outputFormat.displayName)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(FormShiftTheme.formatColor(preset.outputFormat.rawValue))
                                    .frame(width: 52)
                                    .padding(.vertical, 7)
                                    .background(
                                        FormShiftTheme.formatColor(preset.outputFormat.rawValue).opacity(0.10),
                                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    )

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(preset.name)
                                        .font(.callout.weight(.semibold))
                                    Text(presetSummary(preset))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                Button("应用") {
                                    model.applyPreset(preset)
                                }
                                .buttonStyle(.borderedProminent)

                                Menu {
                                    Button("删除预设", systemImage: "trash", role: .destructive) {
                                        model.deletePreset(id: preset.id)
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .frame(width: 24, height: 24)
                                }
                                .menuStyle(.borderlessButton)
                                .menuIndicator(.hidden)
                                .fixedSize()
                                .accessibilityLabel("\(preset.name) 的更多操作")
                            }
                            .padding(14)
                            .panelSurface(radius: 12)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FormShiftTheme.ceramic)
    }

    private func savePreset() {
        let name = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        model.savePreset(named: name)
        presetName = ""
    }

    private func presetSummary(_ preset: Preset) -> String {
        var parts = [preset.options.quality.formatted(.percent.precision(.fractionLength(0)))]
        if let width = preset.options.width, let height = preset.options.height {
            parts.append("\(width)×\(height)")
        }
        if preset.options.trimBorders { parts.append("裁白边") }
        if preset.options.metadataPolicy == .remove { parts.append("移除元数据") }
        return parts.joined(separator: " · ")
    }
}

struct FormShiftSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("输出") {
                Picker("默认保存位置", selection: $model.outputLocation) {
                    ForEach(OutputLocation.allCases) { location in
                        Text(location.title).tag(location)
                    }
                }
                Text("FormShift 永远不会覆盖原文件；重名文件会自动添加序号。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("隐私") {
                LabeledContent("网络访问", value: "关闭")
                LabeledContent("遥测与分析", value: "关闭")
            }

            Section("开源许可") {
                LabeledContent("FormShift", value: "GNU GPLv3")
                Button("查看许可证与 FFmpeg 构建记录") {
                    model.openLicenseFolder()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
