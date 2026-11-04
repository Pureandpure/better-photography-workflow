import AppKit
import SwiftUI

struct SettingsHubView: View {
    @Binding var configuration: BPWConfiguration
    @State private var selection = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("设置类别", selection: $selection) {
                Text("项目").tag(0)
                Text("工作流").tag(1)
                Text("存储").tag(2)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)
            .padding()

            Divider()

            switch selection {
            case 0: GeneralSettingsView(configuration: $configuration)
            case 1: ReminderSettingsView(configuration: $configuration)
            default: BackupSettingsView(configuration: $configuration)
            }
        }
        .navigationTitle("设置")
    }
}

struct GeneralSettingsView: View {
    @Binding var configuration: BPWConfiguration

    var body: some View {
        Form {
            Section("主素材库") {
                HStack {
                    TextField("绝对路径", text: $configuration.workDir)
                    Button("选择…") {
                        if let path = chooseDirectory(startingAt: configuration.workDir) {
                            configuration.workDir = path
                        }
                    }
                }
                Text("选择项目库根目录，例如 SSD 的 01_PROJECTS。新项目名称以年份开头（如 2027-01_旅行）时会归入对应年份；未写年份则归入今年。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("项目结构") {
                Toggle("创建新项目时自动补齐目录", isOn: $configuration.autoCreateProjectStructure)
                ForEach(configuration.projectSubdirectories.indices, id: \.self) { index in
                    HStack {
                        TextField("子目录", text: $configuration.projectSubdirectories[index])
                        Button(role: .destructive) {
                            configuration.projectSubdirectories.remove(at: index)
                        } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.plain)
                    }
                }
                Button("添加子目录", systemImage: "plus") {
                    configuration.projectSubdirectories.append("新目录")
                }
            }

            Section("后台扫描") {
                Stepper(value: $configuration.scanInterval, in: 30...86_400, step: 30) {
                    LabeledContent("补偿扫描间隔", value: "\(configuration.scanInterval) 秒")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("项目设置")
    }
}

struct ReminderSettingsView: View {
    @Binding var configuration: BPWConfiguration

    var body: some View {
        Form {
            Section("提醒事项列表") {
                TextField("列表名称", text: $configuration.reminderListName)
                HStack {
                    Stepper("小时：\(configuration.reminderHour)", value: $configuration.reminderHour, in: 0...23)
                    Stepper("分钟：\(configuration.reminderMinute)", value: $configuration.reminderMinute, in: 0...59)
                }
                Text("所有任务使用本地时间，截止日以项目目录创建日期为基准。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            TaskEditor(title: "阶段一", name: $configuration.task1Name,
                       days: $configuration.task1Days, description: $configuration.task1Description)
            TaskEditor(title: "阶段二", name: $configuration.task2Name,
                       days: $configuration.task2Days, description: $configuration.task2Description)
            TaskEditor(title: "阶段三", name: $configuration.task3Name,
                       days: $configuration.task3Days, description: $configuration.task3Description)
            TaskEditor(title: "阶段四", name: $configuration.task4Name,
                       days: $configuration.task4Days, description: $configuration.task4Description)
        }
        .formStyle(.grouped)
        .navigationTitle("提醒事项")
    }
}

struct TaskEditor: View {
    let title: String
    @Binding var name: String
    @Binding var days: Int
    @Binding var description: String

    var body: some View {
        Section(title) {
            TextField("任务名称", text: $name)
            Stepper(value: $days, in: 0...365) {
                LabeledContent("截止时间", value: "项目创建后第 \(days) 天")
            }
            TextField("任务说明", text: $description, axis: .vertical)
                .lineLimit(2...4)
        }
    }
}

struct BackupSettingsView: View {
    @Binding var configuration: BPWConfiguration

    var body: some View {
        Form {
            Section {
                Toggle("启用外接硬盘备份", isOn: $configuration.enableBackup)
                Text("这是主素材库之外可选的第二份副本。若 SSD 已经是唯一素材库，可保持关闭。备份使用系统 rsync，并在同步前验证真实挂载点、路径和文件系统。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("外接硬盘") {
                TextField("Finder 中的卷名", text: $configuration.backupVolumeName)
                HStack {
                    TextField("备份目标目录", text: $configuration.backupDestination)
                    Button("选择…") {
                        if let path = chooseDirectory(startingAt: configuration.backupDestination) {
                            configuration.backupDestination = path
                            let components = URL(fileURLWithPath: path).pathComponents
                            if components.count > 2, components[1] == "Volumes" {
                                configuration.backupVolumeName = components[2]
                            }
                        }
                    }
                }
                Stepper(value: $configuration.syncInterval, in: 60...604_800, step: 60) {
                    LabeledContent("自动同步间隔", value: "\(configuration.syncInterval) 秒")
                }
            }
            .disabled(!configuration.enableBackup)

            Section("删除模式") {
                Text("多 Workspace 备份始终保留目标文件；旧删除配置保留，但本轮 sync 不启用删除。")
                Label("安全模式只新增和更新文件，不删除目标端内容。", systemImage: "checkmark.shield")
                    .foregroundStyle(.secondary)
            }
            .disabled(!configuration.enableBackup)
        }
        .formStyle(.grouped)
        .navigationTitle("备份")
    }
}

@MainActor
private func chooseDirectory(startingAt path: String) -> String? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    if !path.isEmpty { panel.directoryURL = URL(fileURLWithPath: path) }
    return panel.runModal() == .OK ? panel.url?.path : nil
}
