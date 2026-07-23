import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard = "概览"
    case general = "项目设置"
    case reminders = "提醒事项"
    case backup = "备份"
    case diagnostics = "诊断与日志"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .general: "folder"
        case .reminders: "checklist"
        case .backup: "externaldrive"
        case .diagnostics: "stethoscope"
        }
    }
}

struct RootView: View {
    @ObservedObject var model: AppModel
    @State private var selection: AppSection? = .dashboard

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.symbol)
                    .tag(section)
            }
            .navigationTitle("摄影工作流")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            Group {
                switch selection ?? .dashboard {
                case .dashboard: DashboardView(model: model)
                case .general: GeneralSettingsView(configuration: $model.configuration)
                case .reminders: ReminderSettingsView(configuration: $model.configuration)
                case .backup: BackupSettingsView(configuration: $model.configuration)
                case .diagnostics: DiagnosticsView(model: model)
                }
            }
            .safeAreaInset(edge: .top) { messageBanner }
            .toolbar {
                ToolbarItemGroup {
                    if model.isWorking { ProgressView().controlSize(.small) }
                    Button("保存并应用") { Task { await model.save() } }
                        .keyboardShortcut("s", modifiers: .command)
                        .disabled(model.isWorking || !model.hasUnsavedChanges)
                }
            }
        }
    }

    @ViewBuilder
    private var messageBanner: some View {
        if let error = model.errorMessage {
            BannerView(text: error, symbol: "exclamationmark.triangle.fill", color: .red) {
                model.errorMessage = nil
            }
        } else if let notice = model.notice {
            BannerView(text: notice, symbol: "checkmark.circle.fill", color: .green) {
                model.notice = nil
            }
        }
    }
}

struct BannerView: View {
    let text: String
    let symbol: String
    let color: Color
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text).lineLimit(3)
            Spacer()
            Button(action: dismiss) { Image(systemName: "xmark") }
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }
}
