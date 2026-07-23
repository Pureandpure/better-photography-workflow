import Foundation

actor BPWClient {
    private let fileManager = FileManager.default

    private func cliURL() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["BPW_CLI_PATH"],
           fileManager.isExecutableFile(atPath: override) {
            return URL(fileURLWithPath: override)
        }
        let installed = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/bpw")
        guard fileManager.isExecutableFile(atPath: installed.path) else { throw BPWError.cliNotFound }
        return installed
    }

    func run(_ arguments: [String]) throws -> BPWCommandResult {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = try cliURL()
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        return BPWCommandResult(output: output.trimmingCharacters(in: .whitespacesAndNewlines),
                                exitCode: process.terminationStatus)
    }

    func loadConfiguration() throws -> BPWConfiguration {
        let result = try run(["config", "export"])
        guard result.succeeded else { throw BPWError.commandFailed(result.output) }
        guard let data = result.output.data(using: .utf8) else {
            throw BPWError.invalidOutput("无法读取 bpw 配置输出。")
        }
        do {
            return try JSONDecoder().decode(BPWConfiguration.self, from: data)
        } catch {
            throw BPWError.invalidOutput("配置解析失败：\(error.localizedDescription)")
        }
    }

    func saveConfiguration(_ configuration: BPWConfiguration) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        let temporaryURL = fileManager.temporaryDirectory
            .appendingPathComponent("bpw-gui-\(UUID().uuidString).json")
        try data.write(to: temporaryURL, options: .atomic)
        defer { try? fileManager.removeItem(at: temporaryURL) }

        let apply = try run(["config", "apply", temporaryURL.path])
        guard apply.succeeded else { throw BPWError.commandFailed(apply.output) }
        let install = try run(["install"])
        guard install.succeeded else { throw BPWError.commandFailed(install.output) }
        return [apply.output, install.output].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
