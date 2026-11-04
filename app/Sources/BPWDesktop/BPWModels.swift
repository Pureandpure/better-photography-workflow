import Foundation

struct BPWConfiguration: Codable, Equatable, Sendable {
    var schemaVersion = 1
    var workDir = ""
    var reminderListName = "🍎摄影工作流"
    var autoCreateProjectStructure = true
    var projectSubdirectories = ["01_MEDIA", "02_PHOTO", "03_VIDEO", "04_CACHE_DELETE", "05_EXPORTS", "99_DOC"]
    var reminderHour = 20
    var reminderMinute = 0
    var task1Name = "① 初筛废片"
    var task1Days = 1
    var task1Description = "删除严重失焦、误触快门、明显重复和完全不可用的照片。"
    var task2Name = "② 精选待修照片"
    var task2Days = 3
    var task2Description = "从保留照片中选出值得调色、精修和交付的照片。"
    var task3Name = "③ 调色与精修"
    var task3Days = 7
    var task3Description = "完成调色、局部调整和必要的深度修图。"
    var task4Name = "④ 导出、备份与归档"
    var task4Days = 10
    var task4Description = "导出最终成片，确认备份，并将精选照片加入作品集或 iCloud。"
    var enableBackup = false
    var backupVolumeName = "PhotographySSD"
    var backupDestination = "/Volumes/PhotographySSD/Photography/01_Projects"
    var backupAllowDelete = false
    var scanInterval = 300
    var syncInterval = 3600

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "SCHEMA_VERSION"
        case workDir = "WORK_DIR"
        case reminderListName = "REMINDER_LIST_NAME"
        case autoCreateProjectStructure = "AUTO_CREATE_PROJECT_STRUCTURE"
        case projectSubdirectories = "PROJECT_SUBDIRECTORIES"
        case reminderHour = "REMINDER_HOUR"
        case reminderMinute = "REMINDER_MINUTE"
        case task1Name = "TASK_1_NAME"
        case task1Days = "TASK_1_DAYS"
        case task1Description = "TASK_1_DESCRIPTION"
        case task2Name = "TASK_2_NAME"
        case task2Days = "TASK_2_DAYS"
        case task2Description = "TASK_2_DESCRIPTION"
        case task3Name = "TASK_3_NAME"
        case task3Days = "TASK_3_DAYS"
        case task3Description = "TASK_3_DESCRIPTION"
        case task4Name = "TASK_4_NAME"
        case task4Days = "TASK_4_DAYS"
        case task4Description = "TASK_4_DESCRIPTION"
        case enableBackup = "ENABLE_BACKUP"
        case backupVolumeName = "BACKUP_VOLUME_NAME"
        case backupDestination = "BACKUP_DESTINATION"
        case backupAllowDelete = "BACKUP_ALLOW_DELETE"
        case scanInterval = "SCAN_INTERVAL"
        case syncInterval = "SYNC_INTERVAL"
    }

    var validationMessage: String? {
        guard workDir.hasPrefix("/") else { return "工作目录必须是绝对路径。" }
        guard !reminderListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "提醒事项列表名称不能为空。"
        }
        guard !projectSubdirectories.isEmpty,
              projectSubdirectories.allSatisfy({ !$0.isEmpty && !$0.hasPrefix("/") && !$0.contains("..") && !$0.contains("\n") && !$0.contains("\r") }) else {
            return "项目子目录必须是安全的相对路径。"
        }
        guard (0...23).contains(reminderHour), (0...59).contains(reminderMinute) else {
            return "提醒时间无效。"
        }
        guard scanInterval > 0, syncInterval > 0 else { return "后台运行间隔必须大于 0。" }
        if enableBackup {
            let root = "/Volumes/\(backupVolumeName)"
            guard !backupVolumeName.isEmpty,
                  backupDestination == root || backupDestination.hasPrefix(root + "/") else {
                return "备份目标必须位于所选外接硬盘中。"
            }
        }
        return nil
    }
}

struct BPWStatus: Equatable, Sendable {
    let values: [String: String]

    init(text: String) {
        var parsed: [String: String] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let separator = line.firstIndex(of: "：") else { continue }
            let key = String(line[..<separator])
            let value = String(line[line.index(after: separator)...])
            parsed[key] = value
        }
        values = parsed
    }

    subscript(_ key: String) -> String { values[key] ?? "未知" }
    var scanHealthy: Bool { self["扫描服务"] == "已加载" }
    var backupEnabled: Bool { self["备份已启用"] == "是" }
}

struct BPWCommandResult: Sendable {
    let output: String
    let exitCode: Int32

    var succeeded: Bool { exitCode == 0 }
}

enum BPWError: LocalizedError {
    case cliNotFound
    case commandFailed(String)
    case invalidOutput(String)

    var errorDescription: String? {
        switch self {
        case .cliNotFound:
            return "找不到 bpw。请先在项目目录运行 ./install.sh。"
        case .commandFailed(let message), .invalidOutput(let message):
            return message
        }
    }
}
