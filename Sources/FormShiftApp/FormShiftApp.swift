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

    var body: some View {
        VStack(spacing: 14) {
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
                Button("打开窗口", systemImage: "macwindow") {
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button {
                model.presentImporter()
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: isDropTargeted ? "arrow.down.circle.fill" : "plus.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(FormShiftTheme.cobalt)
                    Text(isDropTargeted ? "松开以添加" : "拖放文件到此快速转换")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(FormShiftTheme.graphite)
                    Text("支持图片、视频、音频、PDF、Word")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isDropTargeted ? FormShiftTheme.cobalt.opacity(0.1) : Color(nsColor: .windowBackgroundColor).opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isDropTargeted ? FormShiftTheme.cobalt : Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
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

            HStack {
                if model.canStartQueue {
                    Button("开始转换 (\(model.waitingCount))", systemImage: "play.fill") {
                        model.startQueue()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                Spacer()
                Button("退出", systemImage: "power", role: .destructive) {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(.ultraThinMaterial)
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
