import Foundation
import BPWCore

let env = ProcessInfo.processInfo.environment
func emit<T: Encodable>(_ value: T) throws { FileHandle.standardOutput.write(try json(value)); print() }
func ask(_ prompt: String) throws -> String {
    guard isatty(STDIN_FILENO) != 0 else { throw WorkflowError("需要手动选择；非交互调用请指定 --project <id> 或 --new <名称>，以及必要的 --workspace/--device") }
    print(prompt, terminator: " "); fflush(stdout)
    guard let line = readLine(), !line.isEmpty else { throw WorkflowError("已取消") }; return line
}
struct Args {
    var positional: [String] = []
    var options: [String: String] = [:]
    var flags = Set<String>()
    init(_ args: [String]) throws {
        var i = 0
        while i < args.count {
            let a = args[i]
            if ["--dry-run", "--execute", "--checksum", "--json", "--progress"].contains(a) { flags.insert(a) }
            else if a.hasPrefix("--") {
                guard ["--workspace", "--project", "--new", "--device", "--recorder", "--name", "--type", "--dates"].contains(a), i + 1 < args.count else { throw WorkflowError("未知参数/缺少值：\(a)") }
                i += 1; options[a] = args[i]
            } else { positional.append(a) }
            i += 1
        }
    }
}
func selectedSource(_ args: Args, store: ProjectStore, backup: String) throws -> (URL, String?) {
    if let path = args.positional.first {
        guard args.positional.count == 1, path.hasPrefix("/"), !path.split(separator: "/").contains("..") else { throw WorkflowError("媒体路径必须是无父目录跳转的绝对路径") }
        let url = systemURL(URL(fileURLWithPath: path)); try validateSource(url, store: store, backupPath: backup)
        return (url, store.volumes.first(where: { contained(url, in: URL(fileURLWithPath: $0.path)) })?.uuid)
    }
    let candidates = mediaSources(volumes: store.volumes, pool: store.pool, backupPath: backup, protectedBackupVolumeIDs: store.protectedBackupVolumeIDs)
    guard !candidates.isEmpty else { throw WorkflowError("没有检测到媒体卡。普通 SSD 不会自动作为卡；可明确提供来源目录") }
    if candidates.count == 1 { return (URL(fileURLWithPath: candidates[0].path), candidates[0].uuid) }
    for (i, v) in candidates.enumerated() { print("\(i + 1). \(v.name) · \(v.path)") }
    guard let index = Int(try ask("选择媒体编号：")), candidates.indices.contains(index - 1) else { throw WorkflowError("无效选择") }
    return (URL(fileURLWithPath: candidates[index - 1].path), candidates[index - 1].uuid)
}
func chooseWorkspace(_ explicit: String?, store: ProjectStore) throws -> String? {
    if explicit != nil || store.pool.workspacePreference != "ask" { return explicit }
    let online = try store.pool.workspaces.filter { try store.pool.resolve($0, volumes: store.volumes) != nil }
    for (i, w) in online.enumerated() { print("\(i + 1). \(w.name)") }
    guard let index = Int(try ask("选择 Workspace：")), online.indices.contains(index - 1) else { throw WorkflowError("无效 Workspace") }; return online[index - 1].id
}
func run() throws {
    let raw = Array(CommandLine.arguments.dropFirst())
    guard let command = raw.first, let statePath = env["BPW_STATE_DIR"], let work = env["WORK_DIR"] else { throw WorkflowError("请通过 bpw 调用导入后端") }
    let args = try Args(Array(raw.dropFirst()))
    let state = URL(fileURLWithPath: statePath)
    let cancellationURL = state.appendingPathComponent("ingest.cancel")
    if command == "cancel-ingest" {
        try mkdir(state)
        try atomic(true, cancellationURL)
        print("正在安全取消当前导入；已完成文件会保留。")
        return
    }
    let lock = try StateLock(state); defer { withExtendedLifetime(lock) {} }
    let configuredDirectories = (env["BPW_PROJECT_SUBDIRECTORIES"] ?? "").split(separator: "\n").map(String.init)
    let store = try ProjectStore(state: state, workDir: work, volumes: SystemVolumes().volumes(), projectSubdirectories: configuredDirectories.isEmpty ? ["01_MEDIA", "02_PHOTO", "03_VIDEO", "04_CACHE_DELETE", "05_EXPORTS", "99_DOC"] : configuredDirectories)
    let backup = env["BACKUP_DESTINATION"] ?? "/Volumes/PhotographySSD/Photography/01_Projects"
    try store.protectBackup(backup)
    switch command {
    case "workspace":
        switch args.positional.first ?? "list" {
        case "list":
            struct View: Encodable { var workspace: Workspace; var status: String; var resolvedPath: String? }
            try emit(try store.pool.workspaces.map { w in let path = try store.pool.resolve(w, volumes: store.volumes); return View(workspace: w, status: path == nil ? "offline" : "online", resolvedPath: path?.path) })
        case "preference":
            guard args.positional.count == 2, ["auto", "local", "ask"].contains(args.positional[1]) else { throw WorkflowError("用法：bpw workspace preference auto|local|ask") }
            store.pool.workspacePreference = args.positional[1]; try store.savePool(); print("Workspace 策略：\(store.pool.workspacePreference)")
        case "add":
            guard args.positional.count == 3 else { throw WorkflowError("用法：bpw workspace add <id> <绝对路径> --type local|external [--name 名称]") }
            let id = args.positional[1], path = args.positional[2]
            guard id.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil, !store.pool.workspaces.contains(where: { $0.id == id }), path.hasPrefix("/"), !path.split(separator: "/").contains("..") else { throw WorkflowError("Workspace ID/路径无效或 ID 已存在") }
            let url = URL(fileURLWithPath: path); try safePath(url)
            let type = args.options["--type"] ?? (path.hasPrefix("/Volumes/") ? "external" : "local")
            let name = args.options["--name"] ?? id
            let w: Workspace
            if type == "external" {
                guard let v = store.volumes.first(where: { contained(url, in: URL(fileURLWithPath: $0.path)) }), url.path != v.path else { throw WorkflowError("外置 Workspace 必须位于真实挂载卷的子目录") }
                guard !contained(URL(fileURLWithPath: backup), in: URL(fileURLWithPath: v.path)), !store.protectedBackupVolumeIDs.contains(where: { $0.caseInsensitiveCompare(v.uuid) == .orderedSame }) else { throw WorkflowError("Backup 卷不能同时作为 Primary Workspace") }
                w = Workspace(id: id, name: name, type: type, volumeUUID: v.uuid, relativePath: String(path.dropFirst(v.path.count + 1)))
            } else {
                guard type == "local", !path.hasPrefix("/Volumes/") else { throw WorkflowError("local 不能指向 /Volumes") }
                w = Workspace(id: id, name: name, type: type, path: path)
            }
            for other in store.pool.workspaces { if let p = try store.pool.resolve(other, volumes: store.volumes), contained(url, in: p) || contained(p, in: url) { throw WorkflowError("Workspace 路径不能重叠") } }
            try mkdir(url); store.pool.workspaces.append(w)
            if type == "external" { store.pool.externalPrimaryWorkspaceId = id }
            try store.savePool(); print("已登记 Workspace：\(id)")
        default: throw WorkflowError("workspace: list/add/preference")
        }
    case "new":
        guard args.positional.count == 1 else { throw WorkflowError("用法：bpw new 名称 [--workspace id]") }
        let p = try store.create(args.positional[0], workspace: chooseWorkspace(args.options["--workspace"], store: store))
        print(p.path)
    case "project", "projects":
        let action = args.positional.first ?? "list"
        if action == "list" { try emit(store.refresh().filter { command == "project" || $0.status == "online" }) }
        else if action == "show", args.positional.count == 2 {
            guard let p = try store.refresh().first(where: { $0.id == args.positional[1] || $0.path == args.positional[1] }) else { throw WorkflowError("找不到项目") }; try emit(p)
        } else if ["set-stage", "set-favorite"].contains(action), args.positional.count == 3 {
            let p = try store.project(args.positional[1]); let url = state.appendingPathComponent("workflow-projects/\(p.id).plist"); try safePath(url); try mkdir(url.deletingLastPathComponent())
            var value = (fm.contents(atPath: url.path).flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }) ?? [:]
            if action == "set-stage" { guard ["ingest", "verify", "organize", "edit", "export", "archive", "done"].contains(args.positional[2]) else { throw WorkflowError("未知阶段") }; value["stageID"] = args.positional[2] }
            else { guard ["true", "false"].contains(args.positional[2]) else { throw WorkflowError("收藏状态必须是 true/false") }; value["isFavorite"] = args.positional[2] == "true" }
            value["updatedEpoch"] = Int(Date().timeIntervalSince1970); value["projectId"] = p.id; value["projectPath"] = p.path
            try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0).write(to: url, options: .atomic); print("项目状态已更新：\(p.name)")
        } else { throw WorkflowError("project: list/show/set-stage/set-favorite") }
    case "paths":
        let projects = try store.refresh().filter { $0.status == "online" && (args.options["--project"] == nil || $0.id == args.options["--project"] || $0.path == args.options["--project"].map { systemURL(URL(fileURLWithPath: $0)).path }) }
        if args.options["--project"] != nil, projects.isEmpty { throw WorkflowError("项目不存在或 offline") }
        for p in projects { FileHandle.standardOutput.write(Data((p.path + "\0").utf8)) }
    case "validate-project":
        guard args.positional.count == 1 else { throw WorkflowError("缺少项目") }; _ = try store.project(args.positional[0])
    case "media":
        if args.positional == ["list"] { try emit(mediaSources(volumes: store.volumes, pool: store.pool, backupPath: backup, protectedBackupVolumeIDs: store.protectedBackupVolumeIDs)); break }
        let (source, uuid) = try selectedSource(args, store: store, backup: backup)
        let scan = try MediaScanner().scan(source, overrideDevice: args.options["--device"], overrideRecorder: args.options["--recorder"], volumeUUID: uuid, onProgress: args.flags.contains("--progress") ? { count in print("BPW_SCAN_PROGRESS \(count)"); fflush(stdout) } : nil)
        try emit(scan)
    case "imports":
        let history = try read([ImportSummary].self, state.appendingPathComponent("import-history.json"), fallback: [])
        try emit(history.filter { args.options["--project"] == nil || $0.projectId == args.options["--project"] })
    case "ingest":
        let dry = args.flags.contains("--dry-run")
        try? fm.removeItem(at: cancellationURL)
        defer { try? fm.removeItem(at: cancellationURL) }
        guard args.options["--project"] == nil || args.options["--new"] == nil else { throw WorkflowError("--project 与 --new 不能同时使用") }
        let (source, uuid) = try selectedSource(args, store: store, backup: backup)
        let scan = try MediaScanner().scan(source, overrideDevice: args.options["--device"], overrideRecorder: args.options["--recorder"], volumeUUID: uuid)
        let selectedDates: Set<String>?
        if let rawDates = args.options["--dates"] {
            let values = Set(rawDates.split(separator: ",").map(String.init))
            guard !values.isEmpty else { throw WorkflowError("--dates 需要逗号分隔的 yyyy-MM-dd 日期") }
            selectedDates = values
        } else if scan.dates.count == 1 {
            selectedDates = Set(scan.dates)
        } else if dry {
            selectedDates = nil
        } else if isatty(STDIN_FILENO) != 0 {
            print("本次扫描的拍摄日期：")
            for (index, group) in scan.dateGroups.enumerated() { print("\(index + 1). \(group.date) · \(group.fileCount) files · \(group.totalBytes) bytes") }
            let raw = try ask("输入要导入的日期编号（逗号分隔）：")
            let indexes = raw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard !indexes.isEmpty, indexes.allSatisfy({ scan.dateGroups.indices.contains($0 - 1) }) else { throw WorkflowError("日期选择无效") }
            selectedDates = Set(indexes.map { scan.dateGroups[$0 - 1].date })
        } else {
            throw WorkflowError("扫描发现多个拍摄日期；请明确指定 --dates yyyy-MM-dd[,yyyy-MM-dd]。扫描到素材不会自动纳入本次导入。")
        }
        let scopedScan = try selectedDates.map { try scan.selecting(dates: $0) }
        let projects = try store.refresh(persist: !dry)
        var sessions = try read([Session].self, state.appendingPathComponent("sessions.json"), fallback: [])
        let matchScan = scopedScan ?? scan
        let candidates = SessionMatcher.candidates(scan: matchScan, sessions: sessions, projects: projects)
        let engine = IngestEngine(); engine.progress = { print($0) }
        engine.cancellationRequested = { fm.fileExists(atPath: cancellationURL.path) }
        if dry {
            struct Preview: Encodable { var scan: MediaScan; var dateGroups: [MediaDateGroup]; var selectedDates: [String]; var candidates: [SessionCandidate]; var plan: IngestPlan?; var workspace: String?; var destinationProjectPath: String? }
            let project = args.options["--project"].flatMap { id in projects.first { $0.id == id || $0.path == systemURL(URL(fileURLWithPath: id)).path } }
            if args.options["--project"] != nil, project == nil || project?.status != "online" { throw WorkflowError("dry-run 项目不存在或 offline；旧项目请先 project list 补 ID") }
            let target = try project.map { URL(fileURLWithPath: $0.path) } ?? args.options["--new"].map { try store.plannedLocation($0, workspace: args.options["--workspace"]) }
            if project == nil, let target, fm.fileExists(atPath: target.path) { throw WorkflowError("新项目目录已存在，请选择 --project") }
            try emit(Preview(scan: scan, dateGroups: scan.dateGroups, selectedDates: selectedDates?.sorted() ?? [], candidates: candidates, plan: try target.flatMap { target in try scopedScan.map { try engine.plan($0, project: target, checksum: args.flags.contains("--checksum")) } }, workspace: args.options["--workspace"], destinationProjectPath: target?.path))
            return
        }
        let importScan = try scopedScan ?? { throw WorkflowError("没有选择本次导入日期") }()
        print("[Import] Scan found \(scan.fileCount) files · \(scan.dateGroups.count) capture dates")
        print("[Import] Selected dates: \(selectedDates!.sorted().joined(separator: ", "))")
        print("[Import] Scope: \(importScan.fileCount) files / \(importScan.totalBytes) bytes")
        if !scan.orphanSidecars.isEmpty { print("未找到唯一 RAW 主文件的附属文件（不导入）：\n" + scan.orphanSidecars.joined(separator: "\n")) }
        if importScan.files.contains(where: { $0.dateSource.hasPrefix("file.") }) { print("部分拍摄时间来自文件创建/修改日期；请检查日期范围") }
        let p: ProjectRecord
        if let id = args.options["--project"] { p = try store.project(id) }
        else if let name = args.options["--new"] { p = try store.create(name, workspace: chooseWorkspace(args.options["--workspace"], store: store)) }
        else if let match = candidates.first(where: \.automatic), let project = projects.first(where: { $0.id == match.projectId }) { p = project; print("Session 自动匹配：\(p.name)（\(match.score)）") }
        else {
            let online = projects.filter { $0.status == "online" }.sorted { a, b in
                let sa = candidates.first(where: { $0.projectId == a.id })?.score ?? 0, sb = candidates.first(where: { $0.projectId == b.id })?.score ?? 0
                return sa == sb ? a.updatedEpoch > b.updatedEpoch : sa > sb
            }
            for (i, project) in online.enumerated() { let score = candidates.first(where: { $0.projectId == project.id })?.score ?? 0; print("\(i + 1). \(project.name) · \(project.workspaceId)\(score > 0 ? " · 建议 \(score)" : "")") }
            print("\(online.count + 1). 创建新项目")
            guard let index = Int(try ask("请选择项目：")), (1...online.count + 1).contains(index) else { throw WorkflowError("无效选择") }
            if index == online.count + 1 { p = try store.create(ask("项目名称："), workspace: chooseWorkspace(args.options["--workspace"], store: store)) }
            else { p = online[index - 1] }
        }
        try validateSource(source, store: store, backupPath: backup)
        let result = try engine.ingest(importScan, project: URL(fileURLWithPath: p.path), projectID: p.id, checksum: args.flags.contains("--checksum"))
        SessionMatcher.record(scan: importScan, projectId: p.id, sessions: &sessions); try atomic(sessions, state.appendingPathComponent("sessions.json"))
        try atomic(result, state.appendingPathComponent("last-import.json"))
        var history = try read([ImportSummary].self, state.appendingPathComponent("import-history.json"), fallback: [])
        history.insert(ImportSummary(result, name: p.name), at: 0)
        try atomic(Array(history.prefix(100)), state.appendingPathComponent("import-history.json"))
        print("✓ \(scan.devices.joined(separator: ", ")) 导入完成：\(result.verifiedFileCount) files · \(result.verifiedBytes) bytes\nPrimary Workspace：\(p.workspaceId)\nProject：\(p.name)\n\(p.path)\n卡上源文件全部保留。备份请执行 bpw sync；导入成功不代表备份完成。")
    case "migrate-media-layout":
        guard let id = args.options["--project"], args.positional.isEmpty, !(args.flags.contains("--execute") && args.flags.contains("--dry-run")) else { throw WorkflowError("用法：migrate-media-layout --project <UUID|编号> [--dry-run|--execute] [--checksum]") }
        let projects = try store.refresh(persist: false)
        let project: ProjectRecord?
        if let index = Int(id), index > 0, projects.indices.contains(index - 1) { project = projects[index - 1] }
        else { project = projects.first { $0.id == id } }
        guard let project, project.status == "online" else { throw WorkflowError("项目不存在或离线；请先运行 project list") }
        let migration = MediaLayoutMigration(), url = URL(fileURLWithPath: project.path)
        let report = try args.flags.contains("--execute") ? migration.execute(project: url, projectID: project.id, checksum: args.flags.contains("--checksum")) : migration.plan(project: url, projectID: project.id)
        try emit(report)
    default: throw WorkflowError("未知 backend command：\(command)")
    }
}
do { try run() } catch { FileHandle.standardError.write(Data(("bpw: \(error.localizedDescription)\n").utf8)); exit(1) }
