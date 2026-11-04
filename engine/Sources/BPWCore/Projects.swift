import Foundation

public struct Workspace: Codable, Equatable {
    public var id: String
    public var name: String
    public var type: String
    public var path: String?
    public var volumeUUID: String?
    public var relativePath: String?
    public init(id: String, name: String, type: String, path: String? = nil, volumeUUID: String? = nil, relativePath: String? = nil) { self.id = id; self.name = name; self.type = type; self.path = path; self.volumeUUID = volumeUUID; self.relativePath = relativePath }
}
public struct WorkspacePool: Codable {
    public var schemaVersion = 1
    public var workspacePreference = "auto"
    public var legacyWorkDir: String?
    public var externalPrimaryWorkspaceId: String?
    public var autoIngestMatchedSession = false
    public var workspaces: [Workspace]
    public init(workspaces: [Workspace]) { self.workspaces = workspaces }
    public func resolve(_ w: Workspace, volumes: [Volume]) throws -> URL? {
        if w.type == "external" {
            guard let uuid = w.volumeUUID, let v = volumes.first(where: { $0.uuid.caseInsensitiveCompare(uuid) == .orderedSame }) else { return nil }
            guard let relative = w.relativePath, !relative.hasPrefix("/"), !relative.split(separator: "/").contains("..") else { throw WorkflowError("不安全 Workspace relativePath") }
            let u = URL(fileURLWithPath: v.path).appendingPathComponent(relative); try safePath(u); return u
        }
        guard w.type == "local", let path = w.path, path.hasPrefix("/"), !path.hasPrefix("/Volumes/") else { throw WorkflowError("local 必须是 Mac 本地绝对路径，外置目录请注册 external") }
        let u = systemURL(URL(fileURLWithPath: path)); try safePath(u); return fm.fileExists(atPath: path) ? u : nil
    }
    public func preferred(_ explicit: String?, volumes: [Volume]) throws -> Workspace {
        if let explicit {
            guard let w = workspaces.first(where: { $0.id == explicit }), try resolve(w, volumes: volumes) != nil else { throw WorkflowError("Workspace 不存在或 offline：\(explicit)") }; return w
        }
        if workspacePreference == "ask" { throw WorkflowError("workspacePreference=ask，请使用 --workspace <id>") }
        if workspacePreference == "auto", let w = workspaces.first(where: { $0.id == externalPrimaryWorkspaceId }), try resolve(w, volumes: volumes) != nil { return w }
        guard let w = workspaces.first(where: { $0.type == "local" }), try resolve(w, volumes: volumes) != nil else { throw WorkflowError("没有在线本地 Workspace，请先 workspace add") }; return w
    }
}
public struct ProjectIdentity: Codable {
    public var schemaVersion = 1
    public var id: String
    public var name: String
    public var createdAt: String
    public var primaryWorkspaceId: String
    public var reminderOriginalPath: String?
    public init(id: String = UUID().uuidString, name: String, workspace: String, path: String) { self.id = id; self.name = name; createdAt = now(); primaryWorkspaceId = workspace; reminderOriginalPath = path }
}
public struct ProjectRecord: Codable {
    public var id: String
    public var name: String
    public var workspaceId: String
    public var relativePath: String
    public var path: String
    public var lastSeenAt: String
    public var status: String
    public var directoryName: String
    public var createdEpoch: Int
    public var updatedEpoch: Int
    public var currentStageID: String
    public var isFavorite: Bool
    public var deviceNames: [String]
}
public final class ProjectStore {
    public let state: URL
    public var pool: WorkspacePool
    public let volumes: [Volume]
    public let projectSubdirectories: [String]
    public var registry: [ProjectRecord] = []
    public var protectedBackupVolumeIDs: [String] = []
    public init(state: URL, workDir: String, volumes: [Volume], projectSubdirectories: [String] = ["01_MEDIA", "02_PHOTO", "03_VIDEO", "04_CACHE_DELETE", "05_EXPORTS", "99_DOC"]) throws {
        self.state = state; self.volumes = volumes; self.projectSubdirectories = projectSubdirectories
        // Preserve a legacy external WORK_DIR, but pin its actual UUID rather than its display name.
        var initial: [Workspace] = []
        if workDir.hasPrefix("/Volumes/") {
            if let v = volumes.first(where: { contained(URL(fileURLWithPath: workDir), in: URL(fileURLWithPath: $0.path)) }) {
                initial.append(Workspace(id: "legacy", name: v.name, type: "external", volumeUUID: v.uuid, relativePath: String(workDir.dropFirst(v.path.count + 1))))
            }
            initial.append(Workspace(id: "local", name: "MacBook", type: "local", path: fm.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Photography_Work").path))
        } else { initial.append(Workspace(id: "local", name: "MacBook", type: "local", path: workDir)) }
        pool = try read(WorkspacePool.self, state.appendingPathComponent("workspaces.json"), fallback: WorkspacePool(workspaces: initial))
        if pool.externalPrimaryWorkspaceId == nil { pool.externalPrimaryWorkspaceId = initial.first(where: { $0.type == "external" })?.id }
        if let previousWorkDir = pool.legacyWorkDir, previousWorkDir != workDir {
            if !workDir.hasPrefix("/Volumes/"), let index = pool.workspaces.firstIndex(where: { $0.id == "local" && $0.type == "local" }) {
                pool.workspaces[index].path = workDir
            } else if workDir.hasPrefix("/Volumes/"), let external = initial.first(where: { $0.type == "external" }) {
                if let existing = try pool.workspaces.first(where: { try pool.resolve($0, volumes: volumes)?.path == systemURL(URL(fileURLWithPath: workDir)).path }) {
                    pool.externalPrimaryWorkspaceId = existing.id
                } else if let index = pool.workspaces.firstIndex(where: { workspace in
                    workspace.type == "external" && workspace.volumeUUID?.caseInsensitiveCompare(external.volumeUUID ?? "") == .orderedSame &&
                    ((try? pool.resolve(workspace, volumes: volumes)).map { contained($0, in: URL(fileURLWithPath: workDir)) } ?? false)
                }) {
                    // A selected library root can be the parent of the previously registered year folder.
                    // Retarget that same workspace so existing Project IDs keep their primary workspace.
                    pool.workspaces[index].relativePath = external.relativePath
                    pool.workspaces[index].name = external.name
                    pool.externalPrimaryWorkspaceId = pool.workspaces[index].id
                } else {
                    pool.workspaces.removeAll { $0.id == "legacy" }
                    pool.workspaces.append(external); pool.externalPrimaryWorkspaceId = external.id
                }
            } else if workDir.hasPrefix("/Volumes/") { throw WorkflowError("新的 WORK_DIR 卷 offline，连接后再登记 UUID") }
        }
        pool.legacyWorkDir = workDir
        guard pool.schemaVersion == 1, ["auto", "local", "ask"].contains(pool.workspacePreference), Set(pool.workspaces.map(\.id)).count == pool.workspaces.count else { throw WorkflowError("Workspace 配置版本/策略/ID 无效") }
        registry = try read([ProjectRecord].self, state.appendingPathComponent("projects.json"), fallback: [])
        if workDir.hasPrefix("/Volumes/"), !fm.fileExists(atPath: state.appendingPathComponent("workspaces.json").path), initial.count == 1 { throw WorkflowError("原 WORK_DIR 外置卷 offline；连接原卷后重试以登记 UUID") }
    }
    public func protectBackup(_ path: String) throws {
        let file = state.appendingPathComponent("protected-backup-volumes.json")
        protectedBackupVolumeIDs = try read([String].self, file, fallback: [])
        if let volume = volumes.first(where: { contained(systemURL(URL(fileURLWithPath: path)), in: URL(fileURLWithPath: $0.path)) }),
           !protectedBackupVolumeIDs.contains(where: { $0.caseInsensitiveCompare(volume.uuid) == .orderedSame }) {
            protectedBackupVolumeIDs.append(volume.uuid)
            try atomic(protectedBackupVolumeIDs, file)
        }
    }
    public func savePool() throws { try atomic(pool, state.appendingPathComponent("workspaces.json")) }
    public func identity(_ project: URL, workspace: String) throws -> ProjectIdentity {
        try safePath(project)
        let file = project.appendingPathComponent(".bpw-project.json")
        var value: ProjectIdentity
        if fm.fileExists(atPath: file.path) {
            try safePath(file)
            // schema v1 permits metadata made by earlier clients without workspace fields.
            var object = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any] ?? [:]
            let needsWorkspace = object["primaryWorkspaceId"] == nil
            if needsWorkspace { object["primaryWorkspaceId"] = registry.first(where: { $0.id == object["id"] as? String })?.workspaceId ?? workspace; object["reminderOriginalPath"] = project.path }
            value = try JSONDecoder().decode(ProjectIdentity.self, from: JSONSerialization.data(withJSONObject: object))
            guard value.schemaVersion == 1, UUID(uuidString: value.id) != nil else { throw WorkflowError("无效 Project ID：\(file.path)") }
            if needsWorkspace { try atomic(value, file) }
        } else {
            value = ProjectIdentity(name: project.lastPathComponent.range(of: "^\\d{4}-\\d{2}-\\d{2}_", options: .regularExpression) == nil ? project.lastPathComponent : String(project.lastPathComponent.dropFirst(11)), workspace: workspace, path: project.path)
            // Persist identity first; retry always uses the same UUID before migrating local state.
            try atomic(value, file)
        }
        for (dir, suffix) in [("projects", ".done"), ("workflow-projects", ".plist")] {
            let old = state.appendingPathComponent(dir).appendingPathComponent(pathHash(value.reminderOriginalPath ?? project.path) + suffix)
            let target = state.appendingPathComponent(dir).appendingPathComponent(value.id + suffix)
            if fm.fileExists(atPath: old.path), !fm.fileExists(atPath: target.path) { try safePath(old); try mkdir(target.deletingLastPathComponent()); try safePath(target); try fm.copyItem(at: old, to: target) }
        }
        return value
    }
    public func refresh(persist: Bool = true) throws -> [ProjectRecord] {
        var records = registry.map { p -> ProjectRecord in var p = p; p.status = "offline"; return p }
        var seen = Set<String>()
        for w in pool.workspaces {
            guard let root = try pool.resolve(w, volumes: volumes) else { continue }
            guard fm.fileExists(atPath: root.path) else { continue }
            let children = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]).sorted { $0.lastPathComponent < $1.lastPathComponent }
            let yearFolders = children.filter { $0.lastPathComponent.range(of: "^\\d{4}$", options: .regularExpression) != nil }
            let candidates: [URL]
            if yearFolders.isEmpty { candidates = children }
            else {
                candidates = try yearFolders.flatMap { yearFolder in
                    try safePath(yearFolder)
                    return try fm.contentsOfDirectory(at: yearFolder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]).sorted { $0.lastPathComponent < $1.lastPathComponent }
                }
            }
            for u in candidates {
                try safePath(u)
                guard (try u.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true else { continue }
                let identity: ProjectIdentity
                if !persist, !fm.fileExists(atPath: u.appendingPathComponent(".bpw-project.json").path) { continue }
                if persist { identity = try self.identity(u, workspace: w.id) }
                else {
                    let file = u.appendingPathComponent(".bpw-project.json"); try safePath(file)
                    identity = try JSONDecoder().decode(ProjectIdentity.self, from: Data(contentsOf: file))
                    guard identity.schemaVersion == 1, UUID(uuidString: identity.id) != nil else { throw WorkflowError("无效 Project ID") }
                }
                let previous = registry.first(where: { $0.id == identity.id })
                // A retained copy never becomes active while the registered primary copy exists.
                if identity.primaryWorkspaceId != w.id { continue }
                if let previous, previous.path != u.path, fm.fileExists(atPath: previous.path) { continue }
                guard seen.insert(identity.id).inserted else { throw WorkflowError("同 Project ID 的两个 active 副本，请保留一个 Primary") }
                let values = try u.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
                let stateURL = state.appendingPathComponent("workflow-projects/\(identity.id).plist")
                try safePath(stateURL)
                let stateData = fm.contents(atPath: stateURL.path)
                let workflow = stateData.flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] } ?? [:]
                let relativePath = String(u.path.dropFirst(root.path.hasSuffix("/") ? root.path.count : root.path.count + 1))
                let record = ProjectRecord(id: identity.id, name: identity.name, workspaceId: w.id, relativePath: relativePath, path: u.path, lastSeenAt: now(), status: "online", directoryName: u.lastPathComponent,
                    createdEpoch: Int((values.creationDate ?? Date()).timeIntervalSince1970), updatedEpoch: max(Int((values.contentModificationDate ?? Date()).timeIntervalSince1970), workflow["updatedEpoch"] as? Int ?? 0), currentStageID: workflow["stageID"] as? String ?? "ingest", isFavorite: workflow["isFavorite"] as? Bool ?? false, deviceNames: try devices(u))
                records.removeAll { $0.id == record.id }; records.append(record)
            }
        }
        registry = records.sorted { $0.directoryName < $1.directoryName }
        if persist { try savePool(); try atomic(registry, state.appendingPathComponent("projects.json")) }
        return registry
    }
    private func devices(_ project: URL) throws -> [String] {
        let roots = ["01_ORIGINALS", "01_MEDIA", "01_RAW"].map { project.appendingPathComponent($0) }
        var names = Set<String>()
        func directories(_ parent: URL) throws -> [URL] {
            try safePath(parent)
            return try fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]).filter {
                try safePath($0)
                return try $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
            }
        }
        func isDate(_ name: String) -> Bool { name.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) != nil }
        for root in roots where fm.fileExists(atPath: root.path) {
            for u in try directories(root) {
                if root.lastPathComponent == "01_MEDIA", ["VIDEO", "PHOTO", "AUDIO"].contains(u.lastPathComponent) {
                    for date in try directories(u) where isDate(date.lastPathComponent) {
                        for device in try directories(date) { names.insert(device.lastPathComponent) }
                    }
                } else if isDate(u.lastPathComponent) {
                    for device in try directories(u) { names.insert(device.lastPathComponent) }
                } else { names.insert(u.lastPathComponent) }
            }
        }
        return names.sorted()
    }
    public func plannedLocation(_ name: String, workspace: String? = nil) throws -> URL {
        guard !name.isEmpty, !name.contains("/"), !name.contains("\n"), !name.contains("\r"), name != ".", name != ".." else { throw WorkflowError("项目名称不能为空、包含斜杠或换行") }
        let w = try pool.preferred(workspace, volumes: volumes)
        guard let root = try pool.resolve(w, volumes: volumes) else { throw WorkflowError("workspace offline") }
        let hasExplicitDatePrefix = name.range(of: "^\\d{4}(?:-\\d{2}(?:-\\d{2})?)?_", options: .regularExpression) != nil
        let directory = hasExplicitDatePrefix ? name : "\(day(Date()))_\(name)"
        let year = String(name.prefix(4).range(of: "^\\d{4}$", options: .regularExpression) != nil ? name.prefix(4) : day(Date()).prefix(4))
        guard year.range(of: "^\\d{4}$", options: .regularExpression) != nil else { throw WorkflowError("项目名称无法确定年份") }
        let yearRoot = root.appendingPathComponent(year); try safePath(yearRoot)
        let project = yearRoot.appendingPathComponent(directory); try safePath(project)
        return project
    }
    public func create(_ name: String, workspace: String? = nil) throws -> ProjectRecord {
        let project = try plannedLocation(name, workspace: workspace)
        let w = try pool.preferred(workspace, volumes: volumes)
        let yearRoot = project.deletingLastPathComponent()
        if !fm.fileExists(atPath: yearRoot.path) { try fm.createDirectory(at: yearRoot, withIntermediateDirectories: false) }
        try safePath(yearRoot)
        guard !fm.fileExists(atPath: project.path) else { throw WorkflowError("项目目录已存在，不会覆盖：\(project.path)") }
        try fm.createDirectory(at: project, withIntermediateDirectories: false)
        _ = try identity(project, workspace: w.id)
        for sub in projectSubdirectories { try mkdir(project.appendingPathComponent(sub)) }
        guard let record = try refresh().first(where: { $0.path == project.path }) else { throw WorkflowError("新项目登记失败") }; return record
    }
    public func project(_ idOrPath: String) throws -> ProjectRecord {
        guard let p = try refresh().first(where: { $0.id == idOrPath || $0.path == systemURL(URL(fileURLWithPath: idOrPath)).path }), p.status == "online" else { throw WorkflowError("项目不存在或 workspace offline：\(idOrPath)") }; return p
    }
}
