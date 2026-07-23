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
    @Published private(set) var isWorking = false
    @Published var projectName = ""
    @Published var notice: String?
    @Published var errorMessage: String?

    private let client = BPWClient()

    var hasUnsavedChanges: Bool { configuration != savedConfiguration }
    var menuSymbol: String { status.scanHealthy ? "camera.aperture" : "exclamationmark.triangle" }

    func start() async {
        await refreshAll()
    }

    func refreshAll() async {
        await perform {
            async let loadedConfiguration = self.client.loadConfiguration()
            async let loadedStatus = self.client.run(["status"])
            let (config, statusResult) = try await (loadedConfiguration, loadedStatus)
            self.configuration = config
            self.savedConfiguration = config
            self.consumeStatus(statusResult)
        }
    }

    func refreshStatus() async {
        await perform {
            self.consumeStatus(try await self.client.run(["status"]))
        }
    }

    func save() async {
        guard let validation = configuration.validationMessage else {
            let newConfiguration = configuration
            await perform(success: "配置已保存并重新加载后台服务。") {
                _ = try await self.client.saveConfiguration(newConfiguration)
                self.savedConfiguration = newConfiguration
                self.consumeStatus(try await self.client.run(["status"]))
            }
            return
        }
        errorMessage = validation
    }

    func runScan() async { await runCommand(["scan"], success: "扫描完成。") }
    func runSync() async { await runCommand(["sync"], success: "同步命令已完成。") }

    func createProject() async {
        let name = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { errorMessage = "请输入项目名称。"; return }
        await runCommand(["new", name], success: "项目已创建并生成提醒事项。")
        if errorMessage == nil { projectName = "" }
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

    private func runCommand(_ arguments: [String], success: String) async {
        await perform(success: success) {
            let result = try await self.client.run(arguments)
            guard result.succeeded else { throw BPWError.commandFailed(result.output) }
            self.consumeStatus(try await self.client.run(["status"]))
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
