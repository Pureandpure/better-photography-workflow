import Foundation
import CryptoKit
import Darwin

public struct ImportEntry: Codable {
    public var relativeSourcePath: String
    public var destinationPath: String
    public var size: Int64
    public var captureTimestamp: Double
    public var sha256: String
    public var sourceFingerprint: String
    public var destinationFingerprint: String
}
public struct ImportManifest: Codable {
    public var schemaVersion = 1
    public var id: String
    public var projectId: String
    public var devices: [String]
    public var captureDates: [String]
    public var sourcePath: String
    public var sourceVolumeUUID: String?
    public var importedAt: String
    public var status: String
    public var fileCount: Int
    public var totalBytes: Int64
    public var verifiedFileCount: Int
    public var verifiedBytes: Int64
    public var files: [ImportEntry]
    public var error: String?
}
public struct ImportSummary: Codable {
    public var id: String
    public var projectId: String
    public var projectName: String
    public var devices: [String]
    public var importedAt: String
    public var status: String
    public var fileCount: Int
    public var totalBytes: Int64
    public init(_ manifest: ImportManifest, name: String) {
        id = manifest.id; projectId = manifest.projectId; projectName = name; devices = manifest.devices
        importedAt = manifest.importedAt; status = manifest.status; fileCount = manifest.verifiedFileCount; totalBytes = manifest.verifiedBytes
    }
}
public func fingerprint(_ url: URL) throws -> String {
    try safePath(url); var s = stat()
    guard lstat(url.path, &s) == 0, (s.st_mode & S_IFMT) == S_IFREG else { throw WorkflowError("文件不存在或不是普通文件：\(url.path)") }
    return "\(s.st_dev):\(s.st_ino):\(s.st_size):\(s.st_mtimespec.tv_sec):\(s.st_mtimespec.tv_nsec):\(s.st_ctimespec.tv_sec):\(s.st_ctimespec.tv_nsec)"
}
public struct IngestPlan: Codable {
    public var copyCount: Int
    public var skipCount: Int
    public var copyBytes: Int64
    public var requiredFreeBytes: Int64
    public var totalBytes: Int64
    public var conflicts: [String]
}
public struct ImportProgressEvent: Codable {
    public var stage: String
    public var copiedBytes: Int64
    public var totalBytes: Int64
    public var completedFiles: Int
    public var totalFiles: Int
    public var currentFile: String
    public var bytesPerSecond: Double
    public var etaSeconds: Double
}
public final class IngestEngine {
    public let mediaDirectory: String
    public init(mediaDirectory: String = "01_MEDIA") { self.mediaDirectory = mediaDirectory }
    public var freeSpace: (URL) throws -> Int64 = { url in
        let attrs = try fm.attributesOfFileSystem(forPath: url.path)
        guard let bytes = attrs[.systemFreeSize] as? NSNumber else { throw WorkflowError("无法读取目标剩余空间") }; return bytes.int64Value
    }
    public var afterCopy: ((Int) throws -> Void)?
    public var progress: ((String) -> Void)?
    public var cancellationRequested: () -> Bool = { false }
    private func report(_ event: ImportProgressEvent) {
        guard let data = try? JSONEncoder().encode(event), let json = String(data: data, encoding: .utf8) else { return }
        progress?("BPW_PROGRESS " + json)
    }
    private func entries(_ project: URL) throws -> [ImportEntry] {
        let root = project.appendingPathComponent(".bpw/imports"); try safePath(root)
        guard fm.fileExists(atPath: root.path) else { return [] }
        var result: [ImportEntry] = []
        for file in try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            try safePath(file)
            let manifest = try JSONDecoder().decode(ImportManifest.self, from: Data(contentsOf: file))
            guard manifest.schemaVersion == 1 else { throw WorkflowError("不支持的 import manifest") }
            result += manifest.files
        }
        return result
    }
    private func same(_ file: MediaFile, source: URL, dest: URL, known: [ImportEntry], checksum: Bool) throws -> Bool {
        let sf = try fingerprint(source), df = try fingerprint(dest)
        let destinationPath = file.destinationRelativePath(in: mediaDirectory)
        if !checksum, known.contains(where: { $0.relativeSourcePath == file.relativeSourcePath && $0.destinationPath == destinationPath && $0.size == file.size && $0.captureTimestamp == file.captureTimestamp && $0.sourceFingerprint == sf && $0.destinationFingerprint == df }) { return true }
        let before = sf
        let srcHash = try digest(source), dstHash = try digest(dest)
        guard before == (try fingerprint(source)), df == (try fingerprint(dest)) else { throw WorkflowError("比较期间文件发生变化") }
        return srcHash == dstHash
    }
    public func plan(_ scan: MediaScan, project: URL, checksum: Bool = false) throws -> IngestPlan {
        try safePath(project)
        let known = try entries(project)
        var destinations: [String: URL] = [:]
        var conflicts: [String] = [], copyCount = 0, skipCount = 0, bytes: Int64 = 0
        for f in scan.files {
            let src = URL(fileURLWithPath: scan.sourcePath).appendingPathComponent(f.relativeSourcePath)
            let relativePath = f.destinationRelativePath(in: mediaDirectory)
            let dest = project.appendingPathComponent(relativePath); try safePath(src); try safePath(dest)
            if let prior = destinations[dest.path.lowercased()] {
                if try digest(prior) != digest(src) { conflicts.append("同批次同名不同内容：\(relativePath)") }
                else { skipCount += 1 }
                continue
            }
            destinations[dest.path.lowercased()] = src
            if fm.fileExists(atPath: dest.path) {
                if try same(f, source: src, dest: dest, known: known, checksum: checksum) { skipCount += 1 }
                else { conflicts.append("conflict：\(relativePath)") }
            } else { copyCount += 1; bytes += f.size }
        }
        return IngestPlan(copyCount: copyCount, skipCount: skipCount, copyBytes: bytes, requiredFreeBytes: bytes + max(256 * 1024 * 1024, bytes / 20), totalBytes: scan.totalBytes, conflicts: conflicts)
    }
    public func ingest(_ scan: MediaScan, project: URL, projectID: String, checksum: Bool = false) throws -> ImportManifest {
        let plan = try self.plan(scan, project: project, checksum: checksum)
        guard plan.conflicts.isEmpty else { throw WorkflowError(plan.conflicts.joined(separator: "\n")) }
        guard try freeSpace(project) >= plan.requiredFreeBytes else { throw WorkflowError("目标空间不足，需 \(plan.requiredFreeBytes) bytes（含安全余量）") }
        var manifest = ImportManifest(id: UUID().uuidString, projectId: projectID, devices: scan.devices, captureDates: scan.dates, sourcePath: scan.sourcePath, sourceVolumeUUID: scan.sourceVolumeUUID, importedAt: now(), status: "running", fileCount: scan.fileCount, totalBytes: scan.totalBytes, verifiedFileCount: 0, verifiedBytes: 0, files: [])
        let manifestURL = project.appendingPathComponent(".bpw/imports/\(manifest.id).json")
        let partials = project.appendingPathComponent(".bpw/partials")
        try mkdir(partials)
        // Check filesystem support before transferring any original media.
        let probe = partials.appendingPathComponent(UUID().uuidString + ".probe")
        let probeTarget = partials.appendingPathComponent(UUID().uuidString + ".probe")
        try Data().write(to: probe, options: .withoutOverwriting)
        defer { try? fm.removeItem(at: probe); try? fm.removeItem(at: probeTarget) }
        guard renameatx_np(AT_FDCWD, probe.path, AT_FDCWD, probeTarget.path, UInt32(RENAME_EXCL)) == 0 else {
            throw WorkflowError("目标文件系统不支持安全的 exclusive rename，未开始复制；请使用支持的工作卷")
        }
        try Data([1]).write(to: probe, options: .withoutOverwriting)
        guard renameatx_np(AT_FDCWD, probe.path, AT_FDCWD, probeTarget.path, UInt32(RENAME_EXCL)) != 0, errno == EEXIST else {
            throw WorkflowError("目标文件系统 exclusive rename 检查失败，未开始复制")
        }
        try atomic(manifest, manifestURL)
        do {
            var known = try entries(project)
            let copyStarted = Date()
            var completedBytes: Int64 = 0
            for (i, f) in scan.files.enumerated() {
                if cancellationRequested() { throw WorkflowError("导入已取消") }
                let src = URL(fileURLWithPath: scan.sourcePath).appendingPathComponent(f.relativeSourcePath)
                let relativePath = f.destinationRelativePath(in: mediaDirectory)
                let dest = project.appendingPathComponent(relativePath)
                let before = try fingerprint(src)
                let attrs = try fm.attributesOfItem(atPath: src.path)
                guard (attrs[.size] as? NSNumber)?.int64Value == f.size else { throw WorkflowError("扫描后源文件大小发生变化") }
                try safePath(dest); try mkdir(dest.deletingLastPathComponent())
                var hash: String
                if fm.fileExists(atPath: dest.path) {
                    guard try same(f, source: src, dest: dest, known: known, checksum: checksum) else { throw WorkflowError("conflict：\(dest.path)") }
                    hash = try known.last(where: { $0.sourceFingerprint == before && $0.destinationPath == relativePath })?.sha256 ?? digest(src)
                    progress?("[\(i + 1)/\(scan.fileCount)] skip \(f.relativeSourcePath)")
                    completedBytes += f.size
                    let elapsed = max(0.001, Date().timeIntervalSince(copyStarted)), speed = Double(completedBytes) / elapsed
                    report(ImportProgressEvent(stage: "copying", copiedBytes: completedBytes, totalBytes: scan.totalBytes, completedFiles: i + 1, totalFiles: scan.fileCount, currentFile: f.relativeSourcePath, bytesPerSecond: speed, etaSeconds: speed > 0 ? Double(max(0, scan.totalBytes - completedBytes)) / speed : 0))
                } else {
                    let temp = partials.appendingPathComponent(UUID().uuidString + ".part")
                    try safePath(temp)
                    let outputFD = open(temp.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
                    guard outputFD >= 0 else { throw WorkflowError("无法创建复制临时文件") }
                    let out = FileHandle(fileDescriptor: outputFD, closeOnDealloc: true)
                    let inputFD = open(src.path, O_RDONLY | O_NOFOLLOW)
                    guard inputFD >= 0 else { try? out.close(); throw WorkflowError("无法读取源文件") }
                    let input = FileHandle(fileDescriptor: inputFD, closeOnDealloc: true)
                    var sha = SHA256(), copied: Int64 = 0, lastPercent = -1
                    do {
                        while let data = try input.read(upToCount: 4 * 1024 * 1024), !data.isEmpty {
                            if cancellationRequested() { throw WorkflowError("导入已取消") }
                            try out.write(contentsOf: data); sha.update(data: data); copied += Int64(data.count)
                            let percent = Int(copied * 100 / max(1, f.size))
                            if percent / 10 != lastPercent / 10 {
                                progress?("[\(i + 1)/\(scan.fileCount)] \(percent)% \(f.relativeSourcePath)")
                                let elapsed = max(0.001, Date().timeIntervalSince(copyStarted))
                                let copiedTotal = completedBytes + copied
                                let speed = Double(copiedTotal) / elapsed
                                report(ImportProgressEvent(stage: "copying", copiedBytes: copiedTotal, totalBytes: scan.totalBytes, completedFiles: i, totalFiles: scan.fileCount, currentFile: f.relativeSourcePath, bytesPerSecond: speed, etaSeconds: speed > 0 ? Double(max(0, scan.totalBytes - copiedTotal)) / speed : 0))
                                lastPercent = percent
                            }
                        }
                        try out.synchronize(); try out.close(); try input.close()
                        guard copied == f.size, before == (try fingerprint(src)) else { throw WorkflowError("复制期间源文件变化/字节数不符") }
                        hash = sha.finalize().map { String(format: "%02x", $0) }.joined()
                        if checksum, try digest(temp) != hash { throw WorkflowError("checksum 校验失败") }
                        if cancellationRequested() { throw WorkflowError("导入已取消") }
                        try safePath(dest)
                        // Exclusive rename publishes atomically without replacing any existing target.
                        guard renameatx_np(AT_FDCWD, temp.path, AT_FDCWD, dest.path, UInt32(RENAME_EXCL)) == 0 else { throw WorkflowError("目标已存在或发布失败，不会覆盖：\(dest.path)") }
                        try fm.setAttributes([.modificationDate: attrs[.modificationDate] ?? Date()], ofItemAtPath: dest.path)
                    } catch {
                        try? out.close(); try? input.close(); try? fm.removeItem(at: temp); throw error
                    }
                }
                guard before == (try fingerprint(src)), (try fm.attributesOfItem(atPath: dest.path)[.size] as? NSNumber)?.int64Value == f.size else { throw WorkflowError("导入校验失败：\(dest.path)") }
                let entry = ImportEntry(relativeSourcePath: f.relativeSourcePath, destinationPath: relativePath, size: f.size, captureTimestamp: f.captureTimestamp, sha256: hash, sourceFingerprint: before, destinationFingerprint: try fingerprint(dest))
                manifest.files.append(entry); known.append(entry); manifest.verifiedFileCount += 1; manifest.verifiedBytes += f.size
                completedBytes += f.size
                let elapsed = max(0.001, Date().timeIntervalSince(copyStarted)), speed = Double(completedBytes) / elapsed
                report(ImportProgressEvent(stage: "copying", copiedBytes: completedBytes, totalBytes: scan.totalBytes, completedFiles: i + 1, totalFiles: scan.fileCount, currentFile: f.relativeSourcePath, bytesPerSecond: speed, etaSeconds: speed > 0 ? Double(max(0, scan.totalBytes - completedBytes)) / speed : 0))
                try atomic(manifest, manifestURL)
                try afterCopy?(i + 1)
            }
            // Recheck every final path immediately before declaring completion.
            report(ImportProgressEvent(stage: "verifying", copiedBytes: manifest.verifiedBytes, totalBytes: scan.totalBytes, completedFiles: manifest.verifiedFileCount, totalFiles: scan.fileCount, currentFile: "", bytesPerSecond: 0, etaSeconds: 0))
            for entry in manifest.files {
                guard try fingerprint(project.appendingPathComponent(entry.destinationPath)) == entry.destinationFingerprint else { throw WorkflowError("完成校验发现目标变化") }
            }
            guard manifest.verifiedFileCount == scan.fileCount, manifest.verifiedBytes == scan.totalBytes else { throw WorkflowError("完成校验数量/总字节不符") }
            manifest.status = "success"; try atomic(manifest, manifestURL); return manifest
        } catch {
            manifest.status = error.localizedDescription == "导入已取消" ? "cancelled" : "failed"
            manifest.error = error.localizedDescription; try? atomic(manifest, manifestURL); throw error
        }
    }
}
