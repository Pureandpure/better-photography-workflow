import Foundation
import Darwin

public struct MediaMigrationItem: Codable {
    public var oldPath: String
    public var newPath: String
    public var date: String
    public var device: String
    public var kind: String
    public var size: Int64
    public var primaryPath: String?
    public var status: String
    public var sha256: String? = nil
}
public struct MediaMigrationReport: Codable {
    public var schemaVersion = 1
    public var projectId: String
    public var createdAt: String
    public var status: String
    public var items: [MediaMigrationItem]
    public var unclassified: [String]
    public var orphanSidecars: [String]
    public var conflicts: [String]
    public var retainedDirectories: [String]
    public var fileCount: Int { items.count }
    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.size } }
    enum CodingKeys: String, CodingKey { case schemaVersion, projectId, createdAt, status, items, unclassified, orphanSidecars, conflicts, retainedDirectories, fileCount, totalBytes }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion); try c.encode(projectId, forKey: .projectId); try c.encode(createdAt, forKey: .createdAt); try c.encode(status, forKey: .status); try c.encode(items, forKey: .items); try c.encode(unclassified, forKey: .unclassified); try c.encode(orphanSidecars, forKey: .orphanSidecars); try c.encode(conflicts, forKey: .conflicts); try c.encode(retainedDirectories, forKey: .retainedDirectories); try c.encode(fileCount, forKey: .fileCount); try c.encode(totalBytes, forKey: .totalBytes)
    }
    public init(projectId: String, createdAt: String, status: String, items: [MediaMigrationItem], unclassified: [String], orphanSidecars: [String], conflicts: [String], retainedDirectories: [String]) {
        self.projectId = projectId; self.createdAt = createdAt; self.status = status; self.items = items; self.unclassified = unclassified; self.orphanSidecars = orphanSidecars; self.conflicts = conflicts; self.retainedDirectories = retainedDirectories
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion); projectId = try c.decode(String.self, forKey: .projectId); createdAt = try c.decode(String.self, forKey: .createdAt); status = try c.decode(String.self, forKey: .status); items = try c.decode([MediaMigrationItem].self, forKey: .items); unclassified = try c.decode([String].self, forKey: .unclassified); orphanSidecars = try c.decode([String].self, forKey: .orphanSidecars); conflicts = try c.decode([String].self, forKey: .conflicts); retainedDirectories = try c.decode([String].self, forKey: .retainedDirectories)
    }
}

public final class MediaLayoutMigration {
    public var afterGroup: ((Int) throws -> Void)?
    public var afterPublish: ((Int) throws -> Void)?
    public init() {}
    private let raw = ["arw", "raw", "dng", "cr2", "cr3", "nef", "raf", "orf", "rw2"]
    private let image = ["jpg", "jpeg", "heic", "heif", "png", "tif", "tiff"]
    private let video = ["mp4", "mov", "m4v", "mts", "m2ts"]
    private let audio = ["wav", "m4a", "aac", "mp3", "aiff", "aif", "flac"]
    private func isDate(_ s: String) -> Bool { s.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) != nil }
    private func checked(_ relative: String, project: URL) throws -> URL {
        guard relative.hasPrefix("01_MEDIA/"), !relative.split(separator: "/").contains("..") else { throw WorkflowError("迁移路径不在 01_MEDIA 内") }
        let u = project.appendingPathComponent(relative); try safePath(u)
        let root = project.appendingPathComponent("01_MEDIA")
        var ancestor = u
        while !fm.fileExists(atPath: ancestor.path), ancestor.path != root.path { ancestor.deleteLastPathComponent() }
        var rootStat = stat(), pathStat = stat()
        guard lstat(root.path, &rootStat) == 0, lstat(ancestor.path, &pathStat) == 0, rootStat.st_dev == pathStat.st_dev else { throw WorkflowError("拒绝跨文件系统迁移：\(relative)") }
        return u
    }
    private func persist(_ report: MediaMigrationReport, at url: URL) throws {
        try atomic(report, url)
        let file = try FileHandle(forWritingTo: url)
        try file.synchronize(); try file.close()
        let directory = open(url.deletingLastPathComponent().path, O_RDONLY | O_NOFOLLOW)
        if directory >= 0 { _ = fsync(directory); close(directory) }
    }
    public func plan(project: URL, projectID: String) throws -> MediaMigrationReport {
        let active = project.appendingPathComponent(".bpw/media-layout-migrations/active.json")
        try safePath(active)
        if fm.fileExists(atPath: active.path) {
            let report = try JSONDecoder().decode(MediaMigrationReport.self, from: Data(contentsOf: active))
            guard report.schemaVersion == 1, report.projectId == projectID, report.status == "running" else { throw WorkflowError("迁移记录无效，拒绝继续") }
            return report
        }
        let root = project.appendingPathComponent("01_MEDIA"); try safePath(root)
        var report = MediaMigrationReport(projectId: projectID, createdAt: now(), status: "planned", items: [], unclassified: [], orphanSidecars: [], conflicts: [], retainedDirectories: [])
        guard fm.fileExists(atPath: root.path) else { return report }
        var all: [URL] = [], error: Error?
        guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey], options: [], errorHandler: { _, e in error = e; return false }) else { throw WorkflowError("无法扫描素材") }
        while let u = walker.nextObject() as? URL {
            let v = try u.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard v.isSymbolicLink != true else { throw WorkflowError("拒绝迁移符号链接：\(u.path)") }
            if v.isRegularFile == true { all.append(u) }
        }
        if let error { throw error }
        for u in all.sorted(by: { $0.path < $1.path }) {
            let relative = String(u.path.dropFirst(project.path.count + 1)), parts = Array(relative.split(separator: "/").map(String.init).dropFirst())
            let ext = u.pathExtension.lowercased()
            if ["xmp", "photo-edit"].contains(ext) { continue }
            let kind = raw.contains(ext) ? "RAW" : image.contains(ext) ? "JPEG" : video.contains(ext) ? "VIDEO" : audio.contains(ext) ? "AUDIO" : ""
            guard !kind.isEmpty, parts.count >= 2 else { report.unclassified.append(relative); continue }
            let isNew = parts.count >= 4 && ["VIDEO", "PHOTO", "AUDIO"].contains(parts[0]) && isDate(parts[1])
            if ["VIDEO", "PHOTO", "AUDIO"].contains(parts[0]), !isNew { report.unclassified.append(relative); continue }
            let date: String, device: String
            if isNew { date = parts[1]; device = parts[2] }
            else if parts.count >= 3 && isDate(parts[0]) { date = parts[0]; device = parts[1] }
            else {
                device = parts[0]
                let v = try u.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
                let metadata = try NativeMetadata().capture(u)
                guard let resolved = MediaCaptureDateResolver().resolve(metadata: metadata, creationDate: v.creationDate, modificationDate: v.contentModificationDate) else { report.unclassified.append(relative); continue }
                date = day(resolved.date)
            }
            let parent = kind == "VIDEO" || kind == "AUDIO" ? "01_MEDIA/\(kind)/\(date)/\(device)" : "01_MEDIA/PHOTO/\(date)/\(device)/\(kind)"
            let target = parent + "/" + u.lastPathComponent
            let size = (try u.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
            report.items.append(MediaMigrationItem(oldPath: relative, newPath: target, date: date, device: device, kind: kind, size: Int64(size), primaryPath: nil, status: relative == target ? "already" : "planned"))
        }
        for u in all where ["xmp", "photo-edit"].contains(u.pathExtension.lowercased()) {
            let relative = String(u.path.dropFirst(project.path.count + 1)), stem = u.deletingPathExtension().lastPathComponent.lowercased()
            let matches = report.items.filter { item in
                let main = URL(fileURLWithPath: item.oldPath), side = URL(fileURLWithPath: relative)
                return item.kind == "RAW" && main.deletingLastPathComponent().path == side.deletingLastPathComponent().path && main.deletingPathExtension().lastPathComponent.lowercased() == stem
            }
            guard matches.count == 1, let main = matches.first else { report.orphanSidecars.append(relative); continue }
            let new = main.newPath.split(separator: "/").dropLast().joined(separator: "/") + "/" + u.lastPathComponent
            let size = (try u.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
            report.items.append(MediaMigrationItem(oldPath: relative, newPath: new, date: main.date, device: main.device, kind: "SIDECAR", size: Int64(size), primaryPath: main.oldPath, status: relative == new ? "already" : "planned"))
        }
        var targets: [String: String] = [:]
        for item in report.items where item.status != "already" {
            let source = try checked(item.oldPath, project: project), dest = try checked(item.newPath, project: project)
            if let other = targets[item.newPath.lowercased()], other != item.oldPath,
               try digest(checked(other, project: project)) != digest(source) { report.conflicts.append("多个不同来源指向同一目标：\(item.newPath)") }
            targets[item.newPath.lowercased()] = item.oldPath
            if fm.fileExists(atPath: dest.path), try digest(source) != digest(dest) { report.conflicts.append("目标内容不同：\(item.newPath)") }
        }
        report.orphanSidecars.sort(); report.unclassified.sort(); report.conflicts.sort()
        report.retainedDirectories = Array(Set(report.items.filter { $0.status != "already" }.map { $0.oldPath.split(separator: "/").dropLast().joined(separator: "/") })).sorted()
        return report
    }

    public func execute(project: URL, projectID: String, checksum: Bool = false) throws -> MediaMigrationReport {
        let reportDir = project.appendingPathComponent(".bpw/media-layout-migrations")
        let active = reportDir.appendingPathComponent("active.json")
        try safePath(active)
        var report: MediaMigrationReport
        if fm.fileExists(atPath: active.path) {
            report = try JSONDecoder().decode(MediaMigrationReport.self, from: Data(contentsOf: active))
            guard report.schemaVersion == 1, report.projectId == projectID, report.status == "running" else { throw WorkflowError("迁移记录无效，拒绝继续") }
        } else {
            report = try plan(project: project, projectID: projectID)
            guard report.conflicts.isEmpty else { throw WorkflowError(report.conflicts.joined(separator: "\n")) }
            // Persist content identities before touching any original so interrupted deletion is recoverable.
            for i in report.items.indices where report.items[i].status != "already" {
                let source = try checked(report.items[i].oldPath, project: project)
                let before = try fingerprint(source), hash = try digest(source)
                guard before == (try fingerprint(source)) else { throw WorkflowError("预检期间文件变化：\(source.path)") }
                report.items[i].sha256 = hash
            }
            report.status = "running"; try persist(report, at: active)
        }
        // Revalidate the entire journal before any additional mutation.
        for item in report.items where item.status != "already" {
            guard let hash = item.sha256 else { throw WorkflowError("迁移记录缺少校验值") }
            let source = try checked(item.oldPath, project: project), dest = try checked(item.newPath, project: project)
            let sourceExists = fm.fileExists(atPath: source.path), destExists = fm.fileExists(atPath: dest.path)
            guard sourceExists || destExists else { throw WorkflowError("迁移源和目标均不存在：\(item.oldPath)") }
            if sourceExists, try digest(source) != hash { throw WorkflowError("迁移源变化：\(item.oldPath)") }
            if destExists, try digest(dest) != hash { throw WorkflowError("迁移目标冲突：\(item.newPath)") }
        }
        let moving = report.items.indices.filter { report.items[$0].status != "already" }
        let groups = Dictionary(grouping: moving) { report.items[$0].primaryPath ?? report.items[$0].oldPath }
        var completed = 0
        var published = 0
        for key in groups.keys.sorted() {
            let indices = groups[key]!
            for i in indices {
                let item = report.items[i], source = try checked(item.oldPath, project: project), dest = try checked(item.newPath, project: project)
                guard let hash = item.sha256 else { throw WorkflowError("缺少 checksum") }
                if !fm.fileExists(atPath: dest.path) {
                    guard fm.fileExists(atPath: source.path) else { throw WorkflowError("迁移源缺失") }
                    try mkdir(dest.deletingLastPathComponent())
                    let tempDir = dest.deletingLastPathComponent().appendingPathComponent(".bpw-migration-" + UUID().uuidString)
                    try safePath(tempDir)
                    guard Darwin.mkdir(tempDir.path, 0o700) == 0 else { throw WorkflowError("无法创建迁移临时目录") }
                    let temp = tempDir.appendingPathComponent("file.part")
                    defer { _ = rmdir(tempDir.path) }
                    do {
                        let before = try fingerprint(source)
                        try fm.copyItem(at: source, to: temp)
                        let handle = try FileHandle(forWritingTo: temp)
                        try handle.synchronize(); try handle.close()
                        guard before == (try fingerprint(source)), (try fm.attributesOfItem(atPath: temp.path)[.size] as? NSNumber)?.int64Value == item.size else { throw WorkflowError("迁移复制校验失败：\(item.oldPath)") }
                        if checksum, try digest(temp) != hash { throw WorkflowError("迁移 checksum 失败：\(item.oldPath)") }
                        try safePath(dest)
                        guard renameatx_np(AT_FDCWD, temp.path, AT_FDCWD, dest.path, UInt32(RENAME_EXCL)) == 0 else { throw WorkflowError("迁移目标已存在，未覆盖：\(item.newPath)") }
                        published += 1; try afterPublish?(published)
                    } catch { _ = unlink(temp.path); throw error }
                }
            }
            // Verify every member before removing any original in this group.
            var verifiedDestinations: [Int: String] = [:]
            for i in indices {
                let item = report.items[i], dest = try checked(item.newPath, project: project)
                let before = try fingerprint(dest)
                guard try digest(dest) == item.sha256, before == (try fingerprint(dest)) else { throw WorkflowError("迁移目标校验失败：\(item.newPath)") }
                verifiedDestinations[i] = before
            }
            for i in indices {
                let item = report.items[i], source = try checked(item.oldPath, project: project)
                let dest = try checked(item.newPath, project: project)
                guard try fingerprint(dest) == verifiedDestinations[i] else { throw WorkflowError("迁移目标变化：\(item.newPath)") }
                if fm.fileExists(atPath: source.path) {
                    let before = try fingerprint(source)
                    guard try digest(source) == item.sha256, before == (try fingerprint(source)) else { throw WorkflowError("迁移源变化：\(item.oldPath)") }
                    try fm.removeItem(at: source)
                }
                report.items[i].status = "migrated"
                try persist(report, at: active)
            }
            completed += 1; try afterGroup?(completed)
        }
        let migrated = report.items.filter { $0.status == "migrated" }
        var verifiedBytes: Int64 = 0
        for item in migrated {
            let destination = try checked(item.newPath, project: project)
            let size = (try fm.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value
            guard size == item.size else { throw WorkflowError("迁移最终字节数校验失败：\(item.newPath)") }
            verifiedBytes += item.size
        }
        guard migrated.count == moving.count, verifiedBytes == moving.reduce(Int64(0), { $0 + report.items[$1].size }) else { throw WorkflowError("迁移最终数量/字节数不符") }
        report.status = "completed"
        let final = reportDir.appendingPathComponent(UUID().uuidString + ".json")
        try persist(report, at: final)
        try fm.removeItem(at: active)
        return report
    }
}
