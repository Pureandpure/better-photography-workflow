import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("收件台").font(.largeTitle.bold())
                    Text("创建真实项目、查看素材库状态，并处理刚摄取的内容。")
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210))], spacing: 14) {
                    StatusCard(title: "扫描服务", value: model.status["扫描服务"],
                               symbol: "folder.badge.gearshape", healthy: model.status.scanHealthy)
                    StatusCard(title: "备份", value: model.status.backupEnabled ? "已启用" : "未启用",
                               symbol: "externaldrive", healthy: true)
                    StatusCard(title: "进行中项目", value: "\(model.activeProjects.count)",
                               symbol: "film.stack", healthy: true)
                    StatusCard(title: "外接硬盘", value: model.status["外接硬盘已连接"],
                               symbol: "externaldrive.connected.to.line.below", healthy: true)
                }

                IngestView(model: model)

                GroupBox("新建视频项目") {
                    HStack(spacing: 12) {
                        TextField("例如：杭州 Vlog", text: $model.projectName)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { Task { await model.createProject() } }
                        Button("创建项目") { Task { await model.createProject() } }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.isWorking)
                    }
                    .padding(.vertical, 6)
                }

                GroupBox("快捷操作") {
                    HStack(spacing: 12) {
                        Button { Task { await model.runScan() } } label: {
                            Label("立即扫描", systemImage: "arrow.clockwise")
                        }
                        Button { Task { await model.runSync() } } label: {
                            Label("立即备份", systemImage: "externaldrive.badge.timemachine")
                        }
                        .disabled(!model.configuration.enableBackup)
                        Button(action: model.openWorkDirectory) {
                            Label("打开主素材库", systemImage: "folder")
                        }
                    }
                    .buttonStyle(.bordered)
                    .padding(.vertical, 6)
                }

                GroupBox("当前主素材库") {
                    LabeledContent("位置") {
                        Text(model.configuration.workDir)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 6)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("最近运行").font(.headline)
                    LabeledContent("扫描", value: model.status["最近扫描"])
                    LabeledContent("同步", value: model.status["最近同步"])
                    LabeledContent("最近成功同步", value: model.status["最近成功同步"])
                }
            }
            .padding(28)
        }
        .navigationTitle("收件台")
    }
}

struct StatusCard: View {
    let title: String
    let value: String
    let symbol: String
    let healthy: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .frame(width: 42, height: 42)
                .background((healthy ? Color.accentColor : Color.orange).opacity(0.14), in: .circle)
                .foregroundStyle(healthy ? Color.accentColor : Color.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.headline).lineLimit(1)
            }
            Spacer()
        }
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.separator.opacity(0.45)))
    }
}
