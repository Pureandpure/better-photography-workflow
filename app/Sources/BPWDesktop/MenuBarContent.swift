import AppKit
import SwiftUI

struct MenuBarContent: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("创作者工作流").font(.headline)
            Text("扫描：\(model.status["扫描服务"]) · 备份：\(model.status["备份已启用"])")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Button("打开控制中心") {
                openWindow(id: "main")
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            Button("新建项目…") {
                openWindow(id: "main")
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            Button("立即扫描") { Task { await model.runScan() } }
            Button("立即备份") { Task { await model.runSync() } }
                .disabled(!model.configuration.enableBackup)
            Divider()
            Button("退出") { NSApplication.shared.terminate(nil) }
        }
        .padding(8)
        .frame(width: 260)
        .task { await model.refreshStatus() }
    }
}
