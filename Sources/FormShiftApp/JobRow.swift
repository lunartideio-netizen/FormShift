import FormShiftCore
import SwiftUI

struct JobRow: View {
    @EnvironmentObject private var model: AppModel
    let job: UIJobItem
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                if model.selection == .history {
                    Button {
                        model.toggleHistorySelection(id: job.id)
                    } label: {
                        Image(systemName: model.selectedHistoryIDs.contains(job.id) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(model.selectedHistoryIDs.contains(job.id) ? FormShiftTheme.cobalt : .secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(model.selectedHistoryIDs.contains(job.id) ? "已选中" : "未选中")
                }

                fileGlyph

                VStack(alignment: .leading, spacing: 5) {
                    Text(job.sourceURL.lastPathComponent)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(FormShiftTheme.graphite)
                        .lineLimit(1)

                    HStack(spacing: 7) {
                        Text(ByteCountFormatter.string(fromByteCount: job.byteCount, countStyle: .file))
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text(statusText)
                            .foregroundStyle(statusColor)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                ConversionRail(
                    source: job.sourceFormat?.displayName ?? "?",
                    target: job.outputFormat.displayName,
                    status: job.status,
                    progress: job.progress
                )
                .frame(width: 210)

                actionMenu
            }
            .padding(14)

            if job.status == .running || job.status == .analyzing {
                ProgressView(value: job.progress)
                    .progressViewStyle(.linear)
                    .tint(FormShiftTheme.cobalt)
                    .accessibilityLabel("\(job.sourceURL.lastPathComponent) 转换进度")
                    .accessibilityValue(Text(job.progress, format: .percent))
            }
        }
        .background(
            isSelected ? FormShiftTheme.cobalt.opacity(0.07) : Color.clear,
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .panelSurface(radius: 13)
        .overlay(alignment: .leading) {
            if isSelected {
                Capsule()
                    .fill(FormShiftTheme.cobalt)
                    .frame(width: 3, height: 30)
                    .padding(.leading, 1)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(job.sourceURL.lastPathComponent)，从 \(job.sourceFormat?.displayName ?? "未知格式") 转为 \(job.outputFormat.displayName)，\(statusText)")
    }

    private var fileGlyph: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(FormShiftTheme.formatColor(job.sourceFormat?.rawValue ?? "").opacity(0.12))
                .frame(width: 42, height: 42)
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(FormShiftTheme.formatColor(job.sourceFormat?.rawValue ?? ""))
        }
    }

    private var actionMenu: some View {
        Menu {
            if job.status == .succeeded, job.destinationURL != nil {
                Button("打开结果", systemImage: "arrow.up.forward.app") {
                    model.openResult(jobID: job.id)
                }
                Button("在 Finder 中显示", systemImage: "folder") {
                    model.revealResult(jobID: job.id)
                }
                Divider()
            }
            if model.selection == .history,
               job.status == .succeeded || job.status == .failed || job.status == .cancelled || job.status == .interrupted {
                Button("再次转换", systemImage: "arrow.clockwise") {
                    model.requeueFromHistory(jobID: job.id)
                }
            } else if job.status == .failed || job.status == .cancelled || job.status == .interrupted {
                Button("重试", systemImage: "arrow.clockwise") {
                    model.retry(jobID: job.id)
                }
            }
            if job.status == .waiting || job.status == .running || job.status == .analyzing {
                Button("取消", systemImage: "xmark.circle") {
                    model.cancel(jobID: job.id)
                }
            }
            Divider()
            Button("移除", systemImage: "trash", role: .destructive) {
                model.remove(jobID: job.id)
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("\(job.sourceURL.lastPathComponent) 的更多操作")
    }

    private var statusText: String {
        switch job.status {
        case .waiting: "等待转换"
        case .analyzing: "正在分析"
        case .running: "正在转换 · \(job.progress.formatted(.percent.precision(.fractionLength(0))))"
        case .succeeded: "转换完成"
        case .failed: job.detail ?? "转换失败"
        case .cancelled: "已取消"
        case .interrupted: "转换被中断"
        }
    }

    private var statusColor: Color {
        switch job.status {
        case .running, .analyzing: FormShiftTheme.cobalt
        case .succeeded: FormShiftTheme.success
        case .failed: FormShiftTheme.danger
        case .interrupted: FormShiftTheme.processAmber
        default: .secondary
        }
    }

    private var symbol: String {
        switch job.sourceFormat?.category {
        case .image: "photo"
        case .video: "film"
        case .audio: "waveform"
        case .pdf: "doc.richtext"
        case .animatedImage: "sparkles.rectangle.stack"
        case .document: "doc.text.fill"
        case .none: "doc"
        }
    }
}

struct ConversionRail: View {
    let source: String
    let target: String
    let status: JobStatus
    let progress: Double

    var body: some View {
        HStack(spacing: 8) {
            FormatBadge(label: source, color: FormShiftTheme.formatColor(source))

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(FormShiftTheme.machineSilver)
                        .frame(height: 3)
                    Capsule()
                        .fill(railColor)
                        .frame(width: proxy.size.width * railProgress, height: 3)
                    Circle()
                        .fill(railColor)
                        .frame(width: 7, height: 7)
                        .offset(x: max(0, (proxy.size.width - 7) * railProgress))
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 9)

            FormatBadge(label: target, color: FormShiftTheme.formatColor(target))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("从 \(source) 转为 \(target)")
    }

    private var railProgress: Double {
        switch status {
        case .waiting: 0
        case .analyzing: 0.12
        case .running: min(max(progress, 0.05), 0.95)
        case .succeeded: 1
        case .failed, .cancelled, .interrupted: min(max(progress, 0.08), 0.92)
        }
    }

    private var railColor: Color {
        switch status {
        case .succeeded: FormShiftTheme.success
        case .failed: FormShiftTheme.danger
        case .interrupted: FormShiftTheme.processAmber
        default: FormShiftTheme.cobalt
        }
    }
}

private struct FormatBadge: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: 43)
            .padding(.vertical, 5)
            .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(color.opacity(0.22), lineWidth: 1)
            }
    }
}
