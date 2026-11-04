import AppKit
import SwiftUI

struct DetectedMediaVolume: Codable, Identifiable, Sendable {
    var uuid: String
    var path: String
    var name: String
    var removable: Bool
    var id: String { uuid }
}
struct RecentImportRecord: Codable, Identifiable, Sendable {
    var id: String
    var projectName: String
    var devices: [String]
    var importedAt: String
    var status: String
    var fileCount: Int
    var totalBytes: Int64
}
struct ImportProgressRecord: Codable, Sendable {
    var stage: String
    var copiedBytes: Int64
    var totalBytes: Int64
    var completedFiles: Int
    var totalFiles: Int
    var currentFile: String
    var bytesPerSecond: Double
    var etaSeconds: Double
    var fractionCompleted: Double { totalBytes > 0 ? min(1, Double(copiedBytes) / Double(totalBytes)) : 0 }
}
struct IngestScanRecord: Codable, Sendable {
    struct File: Codable, Sendable {
        var size: Int64
        var captureTimestamp: Double
        var dateSource: String
        var device: String?
        var kind: String?
    }
    var sourcePath: String
    var devices: [String]
    var files: [File]
    var dates: [String] { Set(files.map { Self.day(Date(timeIntervalSince1970: $0.captureTimestamp)) }).sorted() }
    var dateGroups: [MediaDateGroup] {
        Dictionary(grouping: files) { Self.day(Date(timeIntervalSince1970: $0.captureTimestamp)) }
            .map { date, files in MediaDateGroup(date: date, fileCount: files.count, totalBytes: files.reduce(Int64(0)) { $0 + $1.size }) }
            .sorted { $0.date > $1.date }
    }
    static func day(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = .current; formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    var summary: String {
        let bytes = files.reduce(Int64(0)) { $0 + $1.size }
        return "\(devices.joined(separator: ", ")) · \(files.count) files · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
    }
    var dateRange: String {
        let dates = files.map { Date(timeIntervalSince1970: $0.captureTimestamp) }
        guard let start = dates.min(), let end = dates.max() else { return "" }
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short
        return "\(formatter.string(from: start)) — \(formatter.string(from: end))"
    }
    func destinationGroups(selectedDates: Set<String>) -> [String] {
        let selected = files.filter { selectedDates.contains(Self.day(Date(timeIntervalSince1970: $0.captureTimestamp))) && $0.device != nil && $0.kind != nil }
        let groups = Dictionary(grouping: selected) { file in
            "\(Self.day(Date(timeIntervalSince1970: file.captureTimestamp))) · \(file.device!) · \(file.kind!)"
        }
        return groups.keys.sorted().map { key in
            let group = groups[key]!
            let bytes = group.reduce(Int64(0)) { $0 + $1.size }
            return "\(key) · \(group.count) 个文件 · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
        }
    }
}

struct IngestView: View {
    @ObservedObject var model: AppModel
    @State private var source = ""
    @State private var device = ""
    @State private var projectID = ""
    @State private var newName = ""
    @State private var workspaceID = ""
    @State private var checksum = false
    @State private var selectedDates = Set<String>()
    @State private var scannedDevice = ""
    var body: some View {
        GroupBox("素材导入") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    TextField("媒体卡或来源目录", text: $source).textFieldStyle(.roundedBorder)
                    Button("选择…") {
                        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
                        if panel.runModal() == .OK { source = panel.url?.path ?? "" }
                    }
                    Button("检测媒体卡") { Task { await model.detectMedia() } }
                }
                ForEach(model.mediaVolumes) { volume in
                    Button("\(volume.name) · \(volume.path)") { source = volume.path }
                }
                Picker("设备", selection: $device) {
                    Text("自动识别").tag("")
                    ForEach(["A7R5", "Pocket3", "Action6", "Air3S", "Unknown"], id: \.self) { Text($0).tag($0) }
                }
                Button("扫描拍摄时间") {
                    Task {
                        await model.inspectMedia(source: source, device: device)
                        scannedDevice = device
                        selectProjectDateIfAvailable()
                    }
                }
                    .disabled(source.isEmpty)
                if model.isWorking && model.ingestScan == nil {
                    ProgressView(model.scanProgress)
                }
                if let scan = model.ingestScan {
                    Text(scan.summary).font(.headline)
                    Text("选择本次导入日期；未选择的日期不会进入导入计划。")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(scan.dateGroups, id: \.date) { group in
                        Toggle(isOn: Binding(
                            get: { selectedDates.contains(group.date) },
                            set: { isSelected in
                                if isSelected { selectedDates.insert(group.date) } else { selectedDates.remove(group.date) }
                            }
                        )) {
                            HStack {
                                Text(group.date).fontWeight(.medium)
                                Spacer()
                                Text("\(group.fileCount) 个文件 · \(ByteCountFormatter.string(fromByteCount: group.totalBytes, countStyle: .file))")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    ForEach(scan.destinationGroups(selectedDates: selectedDates), id: \.self) { group in
                        Text(group).font(.caption).foregroundStyle(.secondary)
                    }
                    if scan.files.contains(where: { $0.dateSource.hasPrefix("file.") }) {
                        Text("部分时间来自文件创建或修改日期，请检查并手动选择项目。")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                Picker("导入项目", selection: $projectID) {
                    Text("创建新项目").tag("")
                    ForEach(model.projects) { Text($0.name).tag($0.id) }
                }
                if projectID.isEmpty {
                    TextField("新项目名称，例如：平潭旅行", text: $newName).textFieldStyle(.roundedBorder)
                    TextField("Workspace ID（留空按策略；ask 策略需要填写）", text: $workspaceID).textFieldStyle(.roundedBorder)
                }
                Toggle("完整 checksum 校验（增加目标读取时间）", isOn: $checksum)
                HStack {
                    Button("生成导入计划") {
                        Task { await model.importMedia(source: source, device: device, projectID: projectID, newName: newName, workspaceID: workspaceID, checksum: checksum, selectedDates: selectedDates, dryRun: true) }
                    }
                    .disabled(selectedDates.isEmpty || source != model.ingestScan?.sourcePath || device != scannedDevice || model.isWorking)
                    Button("开始导入") {
                        Task { await model.importMedia(source: source, device: device, projectID: projectID, newName: newName, workspaceID: workspaceID, checksum: checksum, selectedDates: selectedDates, dryRun: false) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedDates.isEmpty || source != model.ingestScan?.sourcePath || device != scannedDevice || !model.hasImportPlan(for: selectedDates, source: source, device: device, projectID: projectID, newName: newName, workspaceID: workspaceID, checksum: checksum) || model.isWorking)
                    if model.isWorking {
                        ProgressView().controlSize(.small)
                        Text("正在执行，请勿拔出媒体或工作盘。")
                        Button("安全取消") { Task { await model.cancelImport() } }
                    }
                }
                if !model.ingestProgress.isEmpty {
                    Text(model.ingestProgress).font(.caption).foregroundStyle(.secondary)
                }
                if let progress = model.importProgress {
                    ProgressView(value: progress.fractionCompleted)
                    HStack {
                        Text(progress.stage == "verifying" ? "正在验证" : ByteCountFormatter.string(fromByteCount: progress.copiedBytes, countStyle: .file) + " / " + ByteCountFormatter.string(fromByteCount: progress.totalBytes, countStyle: .file))
                        Spacer()
                        Text("\(Int(progress.fractionCompleted * 100))%")
                    }.font(.caption)
                    HStack {
                        Text("\(progress.completedFiles) / \(progress.totalFiles) 个文件")
                        Spacer()
                        if progress.bytesPerSecond > 0 {
                            Text("\(ByteCountFormatter.string(fromByteCount: Int64(progress.bytesPerSecond), countStyle: .file))/s · 剩余约 \(Int(progress.etaSeconds / 60)) 分钟")
                        }
                    }.font(.caption).foregroundStyle(.secondary)
                    if !progress.currentFile.isEmpty {
                        Text(progress.currentFile).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                    }
                }
                if !selectedDates.isEmpty {
                    Text("本次范围：\(selectedDates.sorted().joined(separator: "、"))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("复制后保留源文件；不会覆盖冲突文件。导入完成后请另行备份。")
                    .font(.caption).foregroundStyle(.secondary)
                if !model.recentImports.isEmpty {
                    Text("最近导入").font(.headline)
                    ForEach(model.recentImports.prefix(5)) { item in
                        Text("✓ \(item.devices.joined(separator: ", ")) · \(item.projectName) · \(item.fileCount) files")
                            .font(.caption)
                    }
                }
                if !model.ingestOutput.isEmpty {
                    ScrollView { Text(model.ingestOutput).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 180)
                }
            }.padding(.vertical, 6)
        }
        .onChange(of: projectID) { _, _ in selectProjectDateIfAvailable() }
    }

    private func selectProjectDateIfAvailable() {
        guard let scan = model.ingestScan else { selectedDates = []; return }
        let projectDate = model.projects.first(where: { $0.id == projectID })?.directoryName.prefix(10)
        let preferred = projectDate.flatMap { scan.dates.contains(String($0)) ? String($0) : nil }
            ?? scan.dates.first(where: { $0 == IngestScanRecord.day(Date()) })
        selectedDates = preferred.map { [$0] }.map(Set.init) ?? []
    }
}

struct MediaDateGroup {
    var date: String
    var fileCount: Int
    var totalBytes: Int64
}
