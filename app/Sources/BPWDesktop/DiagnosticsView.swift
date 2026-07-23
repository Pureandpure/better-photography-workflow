import AppKit
import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject var model: AppModel
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("内容", selection: $tab) {
                    Text("系统检查").tag(0)
                    Text("运行日志").tag(1)
                    Text("原始状态").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
                Spacer()
                Button("刷新") {
                    Task {
                        if tab == 0 { await model.runDoctor() }
                        else if tab == 1 { await model.loadLogs() }
                        else { await model.refreshStatus() }
                    }
                }
                Button("复制") {
                    let text = tab == 0 ? model.diagnosticText : (tab == 1 ? model.logText : model.statusText)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            }
            .padding()

            Divider()

            ScrollView([.vertical, .horizontal]) {
                Text(displayedText.isEmpty ? "点击“刷新”读取内容。" : displayedText)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
        }
        .navigationTitle("诊断与日志")
        .task {
            if model.diagnosticText.isEmpty { await model.runDoctor() }
        }
    }

    private var displayedText: String {
        if tab == 0 { model.diagnosticText }
        else if tab == 1 { model.logText }
        else { model.statusText }
    }
}
