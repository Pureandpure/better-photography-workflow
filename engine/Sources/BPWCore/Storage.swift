import Foundation
import CryptoKit
import Darwin

public struct WorkflowError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
public let fm = FileManager.default
// Foundation directory enumeration expands macOS system aliases inconsistently.
// Normalize only the two OS-owned aliases, never user symlinks.
public func systemURL(_ url: URL) -> URL {
    let path = "/" + url.path.split(separator: "/").joined(separator: "/")
    for alias in ["/var", "/tmp"] {
        if (path == alias || path.hasPrefix(alias + "/")),
           (try? fm.destinationOfSymbolicLink(atPath: alias)) == "private" + alias {
            return URL(fileURLWithPath: "/private" + path)
        }
    }
    return URL(fileURLWithPath: path)
}
public func now() -> String { ISO8601DateFormatter().string(from: Date()) }
public func day(_ date: Date) -> String {
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
    return f.string(from: date)
}
public func json<T: Encodable>(_ value: T) throws -> Data {
    let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try e.encode(value)
}
public func read<T: Decodable>(_ type: T.Type, _ url: URL, fallback: T) throws -> T {
    try safePath(url)
    guard fm.fileExists(atPath: url.path) else { return fallback }
    return try JSONDecoder().decode(type, from: Data(contentsOf: url))
}
public func safePath(_ url: URL) throws {
    guard url.path.hasPrefix("/"), !url.path.contains("\n"), !url.path.contains("\r") else { throw WorkflowError("不安全路径：\(url.path)") }
    var p = URL(fileURLWithPath: "/")
    for c in url.pathComponents.dropFirst() {
        guard c != "..", c != "." else { throw WorkflowError("拒绝父目录跳转") }
        p.appendPathComponent(c)
        var s = stat()
        if lstat(p.path, &s) == 0, (s.st_mode & S_IFMT) == S_IFLNK, !(p.path == "/var" && (try? fm.destinationOfSymbolicLink(atPath: p.path)) == "private/var"), !(p.path == "/tmp" && (try? fm.destinationOfSymbolicLink(atPath: p.path)) == "private/tmp") { throw WorkflowError("拒绝符号链接：\(p.path)") }
    }
}
public func mkdir(_ url: URL) throws { try safePath(url); try fm.createDirectory(at: url, withIntermediateDirectories: true); try safePath(url) }
public func atomic<T: Encodable>(_ value: T, _ url: URL) throws {
    try mkdir(url.deletingLastPathComponent()); try safePath(url)
    try json(value).write(to: url, options: .atomic)
}
public func digest(_ url: URL) throws -> String {
    try safePath(url)
    let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
    var hash = SHA256()
    while let bytes = try handle.read(upToCount: 4 * 1024 * 1024), !bytes.isEmpty { hash.update(data: bytes) }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
}
public func pathHash(_ path: String) -> String { SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined() }
public func contained(_ child: URL, in root: URL) -> Bool { child.path == root.path || child.path.hasPrefix(root.path + "/") }
public final class StateLock {
    private var fd: Int32 = -1
    public init(_ state: URL) throws {
        try mkdir(state)
        let url = state.appendingPathComponent("engine.lock"); try safePath(url)
        fd = open(url.path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw WorkflowError("无法创建 engine lock") }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { close(fd); fd = -1; throw WorkflowError("另一个项目/导入/备份操作正在运行，请稍后重试") }
    }
    deinit { if fd >= 0 { flock(fd, LOCK_UN); close(fd) } }
}
public struct Volume: Codable, Equatable {
    public var uuid: String
    public var path: String
    public var name: String
    public var removable: Bool
    public init(uuid: String, path: String, name: String, removable: Bool) { self.uuid = uuid; self.path = path; self.name = name; self.removable = removable }
}
public protocol VolumeProviding { func volumes() throws -> [Volume] }
public struct SystemVolumes: VolumeProviding {
    public init() {}
    public func volumes() throws -> [Volume] {
        let urls = fm.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeUUIDStringKey, .volumeNameKey], options: []) ?? []
        return urls.compactMap { url in
            guard url.path.hasPrefix("/Volumes/"), (try? safePath(url)) != nil,
                  let info = try? Self.diskInfo(url.path), let uuid = info["VolumeUUID"] as? String,
                  let mount = info["MountPoint"] as? String, mount == url.path else { return nil }
            return Volume(uuid: uuid, path: mount, name: info["VolumeName"] as? String ?? url.lastPathComponent,
                          removable: (info["RemovableMedia"] as? Bool == true))
        }
    }
    public static func diskInfo(_ path: String) throws -> [String: Any] {
        let p = Process(); let out = Pipe(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil"); p.arguments = ["info", "-plist", path]; p.standardOutput = out; p.standardError = FileHandle.nullDevice
        try p.run(); let data = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        guard p.terminationStatus == 0, let value = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { throw WorkflowError("无法验证挂载卷：\(path)") }
        return value
    }
}
