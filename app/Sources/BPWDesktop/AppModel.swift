import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var configuration = BPWConfiguration()
    @Published private(set) var savedConfiguration = BPWConfiguration()
    @Published private(set) var status = BPWStatus(text: "")
    @Published private(set) var statusText = "正在读取状态…"
    @Published private(set) var diagnosticText = ""
    @Published private(set) var logText = ""
    @Published private(set) var projects: [CreatorProject] = []
    @Published private(set) var projectsLoaded = false
    @Published private(set) var isWorking = false
    @Published private(set) var mediaVolumes: [DetectedMediaVolume] = []
    @Published private(set) var ingestScan: IngestScanRecord?
    @Published private(set) var recentImports: [RecentImportRecord] = []
    @Published private(set) var ingestOutput = ""
    @Published private(set) var plannedImportDates: [String] = []
    @Published private(set) var plannedImportContext = ""
    @Published private(set) var ingestProgress = ""
    @Published private(set) var importProgress: ImportProgressRecord?
    @Published private(set) var scanProgress = ""
    @Published var projectName = ""
    @Published var notice: String?
    @Published var errorMessage: String?

    private let client = BPWClient()

    var hasUnsavedChanges: Bool { configuration != savedConfiguration }
    var menuSymbol: String { status.scanHealthy ? "camera.aperture" : "exclamationmark.triangle" }
    var activeProjects: [CreatorProject] { projects.filter { !$0.isComplete } }
    var completedProjects: [CreatorProject] { projects.filter(\.isComplete) }
    var inboxCount: Int { activeProjects.filter { $0.currentStageID == "ingest" }.count }

    func start() async {
        await refreshAll()
    }

    func refreshAll() async {
        await perform {
            async let loadedConfiguration = self.client.loadConfiguration()
            async let loadedStatus = self.client.run(["status"])
            async let loadedProjects = self.client.loadProjects()
            let (config, statusResult, projects) = try await (loadedConfiguration, loadedStatus, loadedProjects)
            self.configuration = config
            self.savedConfiguration = config
            self.projects = projects
            self.projectsLoaded = true
            self.consumeStatus(statusResult)
            let history = try await self.client.run(["imports"])
            if history.succeeded { self.recentImports = try JSONDecoder().decode([RecentImportRecord].self, from: Data(history.output.utf8)) }
        }
    }

    func refreshStatus() async {
        await perform {
            self.consumeStatus(try await self.client.run(["status"]))
        }
    }

    func refreshProjects() async {
        await perform {
            self.projects = try await self.client.loadProjects()
            self.projectsLoaded = true
        }
    }

    func save() async {
        guard let validation = configuration.validationMessage else {
            let newConfiguration = configuration
            await perform(success: "配置已保存并重新加载后台服务。") {
                _ = try await self.client.saveConfiguration(newConfiguration)
                self.savedConfiguration = newConfiguration
                self.consumeStatus(try await self.client.run(["status"]))
                self.projects = try await self.client.loadProjects()
                self.projectsLoaded = true
            }
            return
        }
        errorMessage = validation
    }

    func detectMedia() async {
        await perform {
            let result = try await self.client.run(["media", "list"])
            guard result.succeeded else { throw BPWError.commandFailed(result.output) }
            self.mediaVolumes = try JSONDecoder().decode([DetectedMediaVolume].self, from: Data(result.output.utf8))
            if self.mediaVolumes.isEmpty { self.notice = "没有检测到媒体卡，可使用“选择”明确指定来源目录。" }
        }
    }

    func inspectMedia(source: String, device: String, recorder: String) async {
        ingestScan = nil
        plannedImportDates = []
        plannedImportContext = ""
        importProgress = nil
        scanProgress = "正在分析素材…"
        await perform {
            var args = ["media", source]
            if !device.isEmpty { args += ["--device", device] }
            if !recorder.isEmpty { args += ["--recorder", recorder] }
            args.append("--progress")
            let result = try await self.client.run(args, onOutput: { line in
                guard line.hasPrefix("BPW_SCAN_PROGRESS ") else { return }
                Task { @MainActor in self.scanProgress = "已扫描 \(line.dropFirst("BPW_SCAN_PROGRESS ".count)) 个素材" }
            })
            guard result.succeeded else { throw BPWError.commandFailed(result.output) }
            let json = result.output.components(separatedBy: .newlines).filter { !$0.hasPrefix("BPW_SCAN_PROGRESS ") }.joined(separator: "\n")
            self.ingestScan = try JSONDecoder().decode(IngestScanRecord.self, from: Data(json.utf8))
            self.scanProgress = "扫描完成 · \(self.ingestScan?.files.count ?? 0) 个素材"
        }
    }

    func importMedia(source: String, device: String, recorder: String, projectID: String, newName: String,
                     workspaceID: String, checksum: Bool, selectedDates: Set<String>, dryRun: Bool) async {
        guard !source.isEmpty, !projectID.isEmpty || !newName.isEmpty else {
            errorMessage = "请选择来源与项目，或输入新项目名称。"; return
        }
        guard !selectedDates.isEmpty else { errorMessage = "请选择本次导入日期。"; return }
        await perform {
            self.ingestProgress = dryRun ? "正在生成导入计划…" : "正在导入…"
            self.importProgress = nil
            if dryRun { self.plannedImportDates = []; self.plannedImportContext = "" }
            var args = ["ingest", source]
            args += projectID.isEmpty ? ["--new", newName] : ["--project", projectID]
            if !workspaceID.isEmpty { args += ["--workspace", workspaceID] }
            if !device.isEmpty { args += ["--device", device] }
            if !recorder.isEmpty { args += ["--recorder", recorder] }
            args += ["--dates", selectedDates.sorted().joined(separator: ",")]
            if checksum { args.append("--checksum") }
            if dryRun { args.append("--dry-run") }
            let result = try await self.client.run(args, onOutput: { line in
                Task { @MainActor in
                    if line.hasPrefix("BPW_PROGRESS "),
                       let data = String(line.dropFirst("BPW_PROGRESS ".count)).data(using: .utf8),
                       let event = try? JSONDecoder().decode(ImportProgressRecord.self, from: data) {
                        self.importProgress = event
                    } else {
                        self.ingestProgress = line
                    }
                }
            })
            self.ingestOutput = result.output
            self.ingestProgress = result.succeeded ? (dryRun ? "导入计划已生成" : "导入完成") : "导入失败"
            if dryRun && result.succeeded {
                self.plannedImportDates = selectedDates.sorted()
                self.plannedImportContext = Self.importContext(source: source, device: device, recorder: recorder, projectID: projectID, newName: newName, workspaceID: workspaceID, checksum: checksum)
            }
            if !dryRun { self.plannedImportDates = []; self.plannedImportContext = "" }
            let history = try await self.client.run(["imports"])
            if history.succeeded { self.recentImports = try JSONDecoder().decode([RecentImportRecord].self, from: Data(history.output.utf8)) }
            guard result.succeeded else { throw BPWError.commandFailed(result.output) }
            self.notice = dryRun ? "预览完成，尚未复制素材。" : "导入完成，源文件保留。请继续备份。"
            self.projects = try await self.client.loadProjects()
            self.projectsLoaded = true
            self.consumeStatus(try await self.client.run(["status"]))
        }
    }

    func hasImportPlan(for dates: Set<String>, source: String, device: String, recorder: String, projectID: String,
                       newName: String, workspaceID: String, checksum: Bool) -> Bool {
        plannedImportDates == dates.sorted() && plannedImportContext == Self.importContext(source: source, device: device, recorder: recorder, projectID: projectID, newName: newName, workspaceID: workspaceID, checksum: checksum)
    }

    private static func importContext(source: String, device: String, recorder: String, projectID: String, newName: String, workspaceID: String, checksum: Bool) -> String {
        [source, device, recorder, projectID, newName, workspaceID, checksum ? "checksum" : "standard"].joined(separator: "\u{0}")
    }

    func cancelImport() async {
        ingestProgress = "正在安全取消…"
        do {
            let result = try await BPWClient().run(["cancel-ingest"])
            guard result.succeeded else { throw BPWError.commandFailed(result.output) }
            ingestProgress = result.output
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func runScan() async { await runCommand(["scan"], success: "扫描完成。") }
    func runSync() async { await runCommand(["sync"], success: "同步命令已完成。") }

    func createProject() async {
        let name = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { errorMessage = "请输入项目名称。"; return }
        await runCommand(["new", name], success: "项目已创建并生成提醒事项。")
        if errorMessage == nil { projectName = "" }
    }

    func advanceProject(_ project: CreatorProject) async {
        guard let nextStageID = project.nextStageID else { return }
        await setProjectStage(project, stageID: nextStageID)
    }

    func setProjectStage(_ project: CreatorProject, stageID: String) async {
        guard CreatorProject.stages.contains(where: { $0.id == stageID }) else {
            errorMessage = "未知的项目阶段。"
            return
        }
        await perform(success: stageID == "done" ? "项目已完成并归档到 Done。" : "项目阶段已更新。") {
            let result = try await self.client.run(["projects", "set-stage", project.path, stageID])
            guard result.succeeded else { throw BPWError.commandFailed(result.output) }
            self.projects = try await self.client.loadProjects()
            self.projectsLoaded = true
        }
    }

    func setProjectFavorite(_ project: CreatorProject, favorite: Bool) async {
        await perform {
            let result = try await self.client.run([
                "projects", "set-favorite", project.path, favorite ? "true" : "false"
            ])
            guard result.succeeded else { throw BPWError.commandFailed(result.output) }
            self.projects = try await self.client.loadProjects()
            self.projectsLoaded = true
        }
    }

    func runDoctor() async {
        await perform {
            let result = try await self.client.run(["doctor"])
            self.diagnosticText = result.output
            guard result.succeeded else { throw BPWError.commandFailed(result.output) }
        }
    }

    func loadLogs() async {
        await perform {
            let result = try await self.client.run(["logs"])
            self.logText = result.output
            guard result.succeeded else { throw BPWError.commandFailed(result.output) }
        }
    }

    func openWorkDirectory() {
        guard !configuration.workDir.isEmpty else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: configuration.workDir))
    }

    func openProject(_ project: CreatorProject) {
        NSWorkspace.shared.open(URL(fileURLWithPath: project.path))
    }

    private func runCommand(_ arguments: [String], success: String) async {
        await perform(success: success) {
            let result = try await self.client.run(arguments)
            guard result.succeeded else { throw BPWError.commandFailed(result.output) }
            self.consumeStatus(try await self.client.run(["status"]))
            self.projects = try await self.client.loadProjects()
            self.projectsLoaded = true
        }
    }

    private func consumeStatus(_ result: BPWCommandResult) {
        statusText = result.output
        status = BPWStatus(text: result.output)
        if !result.succeeded { errorMessage = result.output }
    }

    private func perform(success: String? = nil,
                         operation: @escaping @MainActor () async throws -> Void) async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        notice = nil
        do {
            try await operation()
            notice = success
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }
}
