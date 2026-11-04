import Foundation

enum CreatorStageState: Equatable, Sendable {
    case completed
    case current
    case pending
}

struct CreatorWorkflowStage: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let symbol: String
}

struct CreatorDevice: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let detail: String
    let symbol: String
}

struct CreatorProjectRecord: Codable, Equatable, Sendable {
    let id: String
    let path: String
    let directoryName: String
    let createdEpoch: Int
    let updatedEpoch: Int
    let currentStageID: String
    let isFavorite: Bool
    let deviceNames: [String]
}

struct CreatorProject: Identifiable, Equatable, Sendable {
    let id: String
    let path: String
    let directoryName: String
    let name: String
    let updatedEpoch: Int
    let currentStageIndex: Int
    let devices: [CreatorDevice]
    let destinationName: String
    let destinationPath: String
    let storageSummary: String
    let isFavorite: Bool

    static let stages = [
        CreatorWorkflowStage(id: "ingest", name: "素材摄取", symbol: "square.and.arrow.down"),
        CreatorWorkflowStage(id: "verify", name: "完整性校验", symbol: "checkmark.shield"),
        CreatorWorkflowStage(id: "organize", name: "素材分类", symbol: "folder"),
        CreatorWorkflowStage(id: "edit", name: "剪辑中", symbol: "pencil"),
        CreatorWorkflowStage(id: "export", name: "导出成片", symbol: "square.and.arrow.up"),
        CreatorWorkflowStage(id: "archive", name: "项目归档", symbol: "archivebox"),
        CreatorWorkflowStage(id: "done", name: "Done", symbol: "flag.checkered")
    ]

    init(record: CreatorProjectRecord) {
        id = record.id
        path = record.path
        directoryName = record.directoryName
        name = Self.displayName(for: record.directoryName)
        updatedEpoch = record.updatedEpoch
        currentStageIndex = Self.stages.firstIndex(where: { $0.id == record.currentStageID }) ?? 0
        devices = record.deviceNames.map { deviceName in
            CreatorDevice(
                id: "\(record.id)-\(deviceName)",
                name: deviceName,
                detail: "已发现素材目录",
                symbol: Self.symbol(for: deviceName)
            )
        }
        destinationName = Self.volumeName(for: record.path)
        destinationPath = record.path
        storageSummary = record.path.hasPrefix("/Volumes/")
            ? "外置主素材库 · 1 份副本"
            : "本机主素材库 · 1 份副本"
        isFavorite = record.isFavorite
    }

    var progress: Int {
        [8, 24, 46, 71, 84, 96, 100][currentStageIndex]
    }

    var currentStageID: String { Self.stages[currentStageIndex].id }
    var isComplete: Bool { currentStageID == "done" }
    var nextStageID: String? {
        guard currentStageIndex < Self.stages.count - 1 else { return nil }
        return Self.stages[currentStageIndex + 1].id
    }

    var updatedText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "更新于 \(formatter.string(from: Date(timeIntervalSince1970: TimeInterval(updatedEpoch))))"
    }

    var completedStageSummary: String {
        let completedNames = Self.stages.prefix(currentStageIndex).map(\.name)
        if completedNames.isEmpty { return "等待完成第一个工作流阶段" }
        return completedNames.joined(separator: "、") + " 已完成"
    }

    func state(for index: Int) -> CreatorStageState {
        if index < currentStageIndex { return .completed }
        if index == currentStageIndex { return .current }
        return .pending
    }

    private static func displayName(for directoryName: String) -> String {
        guard directoryName.count > 11 else { return directoryName }
        let prefix = String(directoryName.prefix(11))
        let datePart = String(prefix.prefix(10))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        if prefix.hasSuffix("_"), formatter.date(from: datePart) != nil {
            return String(directoryName.dropFirst(11))
        }
        return directoryName
    }

    private static func symbol(for deviceName: String) -> String {
        let lowercase = deviceName.lowercased()
        if lowercase.contains("iphone") { return "iphone" }
        if lowercase.contains("air") || lowercase.contains("drone") || lowercase.contains("无人机") {
            return "airplane"
        }
        if lowercase.contains("pocket") || lowercase.contains("action") || lowercase.contains("gopro") {
            return "video"
        }
        if lowercase.contains("audio") || lowercase.contains("mic") || lowercase.contains("录音") {
            return "waveform"
        }
        return "camera"
    }

    private static func volumeName(for projectPath: String) -> String {
        let projectURL = URL(fileURLWithPath: projectPath)
        if let values = try? projectURL.resourceValues(forKeys: [.volumeNameKey]),
           let volumeName = values.volumeName,
           !volumeName.isEmpty {
            return volumeName
        }
        return projectURL.deletingLastPathComponent().lastPathComponent
    }
}
