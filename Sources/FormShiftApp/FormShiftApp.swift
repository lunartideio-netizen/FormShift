import SwiftUI

@main
struct FormShiftApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            FormShiftRootView()
                .environmentObject(model)
                .onOpenURL { url in
                    if url.isFileURL {
                        model.enqueue(urls: [url])
                    }
                }
                .frame(minWidth: 980, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1_280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("添加文件…") {
                    model.presentImporter()
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandMenu("转换") {
                Button("开始转换") {
                    model.startQueue()
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!model.canStartQueue)

                Button(model.isPaused ? "继续队列" : "暂停队列") {
                    model.togglePause()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(model.jobs.isEmpty)

                Divider()

                Button("移除已完成项目") {
                    model.clearFinished()
                }
                .disabled(!model.hasFinishedJobs)
            }
        }

        Settings {
            FormShiftSettingsView()
                .environmentObject(model)
                .frame(width: 520, height: 380)
        }

        MenuBarExtra("FormShift", systemImage: "arrow.left.arrow.right") {
            MenuBarPopoverView()
                .environmentObject(model)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarPopoverView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isDropTargeted = false
    @State private var isPinned = false

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(FormShiftTheme.cobalt)
                        .frame(width: 28, height: 28)
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("FormShift")
                        .font(.headline)
                    Text(statusSubtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    FloatingDropzoneController.shared.toggle()
                    isPinned = FloatingDropzoneController.shared.isVisible
                } label: {
                    Label(isPinned ? "已置顶" : "常驻置顶", systemImage: isPinned ? "pin.fill" : "pin")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button {
                model.presentImporter()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(FormShiftTheme.cobalt)
                    Text("选择文件快速转换…")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(FormShiftTheme.graphite)
                    Spacer()
                    Text("⌘O")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(FormShiftTheme.cobalt.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(FormShiftTheme.cobalt.opacity(0.20), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Button {
                model.presentImporter()
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: isDropTargeted ? "arrow.down.circle.fill" : "tray.and.arrow.down.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(FormShiftTheme.cobalt)
                    Text(isDropTargeted ? "松开以添加并转换" : "或拖放文件到此")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(FormShiftTheme.graphite)
                    Text("支持图片、音视频、PDF、文档及动图")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isDropTargeted ? FormShiftTheme.cobalt.opacity(0.12) : Color(nsColor: .controlBackgroundColor).opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isDropTargeted ? FormShiftTheme.cobalt : Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                )
            }
            .buttonStyle(.plain)
            .dropDestination(for: URL.self) { urls, _ in
                model.enqueue(urls: urls)
                if model.canStartQueue {
                    model.startQueue()
                }
                return !urls.isEmpty
            } isTargeted: { targeted in
                isDropTargeted = targeted
            }

            Divider()

            HStack {
                Button("打开主窗口", systemImage: "macwindow") {
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                if model.canStartQueue {
                    Button("开始 (\(model.waitingCount))", systemImage: "play.fill") {
                        model.startQueue()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                Button("退出", systemImage: "power", role: .destructive) {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 310)
        .background(.ultraThinMaterial)
        .onAppear {
            FloatingDropzoneController.shared.setup(model: model)
            isPinned = FloatingDropzoneController.shared.isVisible
        }
    }

    private var statusSubtitle: String {
        if model.runningCount > 0 {
            return "正在处理 \(model.runningCount) 个任务..."
        } else if model.waitingCount > 0 {
            return "\(model.waitingCount) 个任务等待转换"
        } else {
            return "就绪 · 随时拖入文件"
        }
    }
}

@MainActor
final class FloatingDropzoneController {
    static let shared = FloatingDropzoneController()

    private var panel: NSPanel?
    private weak var appModel: AppModel?

    func setup(model: AppModel) {
        self.appModel = model
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        if let existing = panel {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        guard let model = appModel else { return }

        let hostingView = NSHostingView(rootView: FloatingDropzoneView(onClose: { [weak self] in
            self?.hide()
        }).environmentObject(model))

        let p = NSPanel(
            contentRect: NSRect(x: 100, y: 100, width: 220, height: 130),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isMovableByWindowBackground = true
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.contentView = hostingView
        p.center()

        self.panel = p
        p.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct FloatingDropzoneView: View {
    @EnvironmentObject private var model: AppModel
    let onClose: () -> Void
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Label("FormShift 置顶投递", systemImage: "arrow.left.arrow.right")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(FormShiftTheme.cobalt)
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 6) {
                Image(systemName: isTargeted ? "arrow.down.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(FormShiftTheme.cobalt)
                Text(isTargeted ? "松开立即转换" : "拖放任意文件到此")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(FormShiftTheme.graphite)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isTargeted ? FormShiftTheme.cobalt.opacity(0.12) : Color(nsColor: .controlBackgroundColor).opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isTargeted ? FormShiftTheme.cobalt : Color.primary.opacity(0.15), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
            )
            .dropDestination(for: URL.self) { urls, _ in
                model.enqueue(urls: urls)
                if model.canStartQueue {
                    model.startQueue()
                }
                return !urls.isEmpty
            } isTargeted: { targeted in
                isTargeted = targeted
            }
        }
        .padding(12)
        .frame(width: 220, height: 130)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        )
    }
}
