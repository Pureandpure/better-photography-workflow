import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case inbox = "收件台"
    case activeProjects = "进行中"
    case completed = "已完成"
    case workflows = "工作流"
    case devices = "设备"
    case transfers = "传输记录"
    case settings = "设置"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .inbox: "tray"
        case .activeProjects: "clock"
        case .completed: "checkmark.circle"
        case .workflows: "point.3.connected.trianglepath.dotted"
        case .devices: "externaldrive.connected.to.line.below"
        case .transfers: "arrow.left.arrow.right.circle"
        case .settings: "gearshape"
        }
    }

}

struct RootView: View {
    @ObservedObject var model: AppModel
    @State private var selection: AppSection? = .activeProjects

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                HStack(spacing: 10) {
                    Label(section.rawValue, systemImage: section.symbol)
                    Spacer()
                    if let badge = badge(for: section), badge > 0 {
                        Text("\(badge)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
                .tag(section)
            }
            .navigationTitle("创作者工作流")
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 250)
        } detail: {
            Group {
                switch selection ?? .activeProjects {
                case .inbox: DashboardView(model: model)
                case .activeProjects: ActiveProjectsView(model: model)
                case .completed: CompletedProjectsView(model: model)
                case .workflows: ReminderSettingsView(configuration: $model.configuration)
                case .devices: DevicesView(model: model)
                case .transfers: DiagnosticsView(model: model)
                case .settings: SettingsHubView(configuration: $model.configuration)
                }
            }
            .safeAreaInset(edge: .top) { messageBanner }
            .toolbar {
                ToolbarItemGroup {
                    if model.isWorking { ProgressView().controlSize(.small) }
                    if selection == .settings {
                        Button("保存并应用") { Task { await model.save() } }
                            .keyboardShortcut("s", modifiers: .command)
                            .disabled(model.isWorking || !model.hasUnsavedChanges)
                    }
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private func badge(for section: AppSection) -> Int? {
        switch section {
        case .inbox: model.inboxCount
        case .activeProjects: model.activeProjects.count
        case .completed: model.completedProjects.count
        default: nil
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

private struct SectionPlaceholderView: View {
    let title: String
    let message: String
    let symbol: String

    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(message))
            .navigationTitle(title)
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
