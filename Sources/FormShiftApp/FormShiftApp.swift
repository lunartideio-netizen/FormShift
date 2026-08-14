import SwiftUI

@main
struct FormShiftApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            FormShiftRootView()
                .environmentObject(model)
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
    }
}
