import Foundation
import ImageIO
import AVFoundation

public struct CaptureMetadata {
    public var date: Date?
    public var deviceEvidence: String
    public var provenance: String
    public init(date: Date?, deviceEvidence: String = "", provenance: String = "metadata") { self.date = date; self.deviceEvidence = deviceEvidence; self.provenance = provenance }
}
public struct ResolvedCaptureDate {
    public var date: Date
    public var provenance: String
}
public struct MediaCaptureDateResolver {
    public init() {}
    public func resolve(metadata: CaptureMetadata, creationDate: Date?, modificationDate: Date?) -> ResolvedCaptureDate? {
        if let date = metadata.date { return ResolvedCaptureDate(date: date, provenance: metadata.provenance) }
        if let creationDate { return ResolvedCaptureDate(date: creationDate, provenance: "file.creationDate") }
        if let modificationDate { return ResolvedCaptureDate(date: modificationDate, provenance: "file.modificationDate") }
        return nil
    }
}
public protocol MetadataProviding { func capture(_ url: URL) throws -> CaptureMetadata }
public struct NativeMetadata: MetadataProviding {
    public init() {}
    public func capture(_ url: URL) throws -> CaptureMetadata {
        if ["mp4", "mov", "m4v"].contains(url.pathExtension.lowercased()) {
            let asset = AVURLAsset(url: url)
            var evidence = ""
            var date: Date?
            for item in asset.commonMetadata + asset.metadata {
                let key = item.identifier?.rawValue.lowercased() ?? item.commonKey?.rawValue.lowercased() ?? ""
                if key.contains("model") || key.contains("make") || key.contains("description") { evidence += " " + (item.stringValue ?? "") }
                if key.contains("creationdate") || key.contains("creation_date") {
                    date = item.dateValue ?? item.stringValue.flatMap { ISO8601DateFormatter().date(from: $0) } ?? date
                }
            }
            if let date { return CaptureMetadata(date: date, deviceEvidence: evidence, provenance: "video.creationDate") }
            return CaptureMetadata(date: nil, deviceEvidence: evidence)
        }
        guard let image = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [String: Any] else { return CaptureMetadata(date: nil) }
        let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        let evidence = "\(tiff[kCGImagePropertyTIFFMake as String] ?? "") \(tiff[kCGImagePropertyTIFFModel as String] ?? "")"
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        if let offset = exif["OffsetTimeOriginal"] as? String { f.timeZone = TimeZone(secondsFromGMT: Self.offset(offset)) }
        let date = (exif[kCGImagePropertyExifDateTimeOriginal as String] as? String ?? exif[kCGImagePropertyExifDateTimeDigitized as String] as? String).flatMap { f.date(from: $0) }
        return CaptureMetadata(date: date, deviceEvidence: evidence, provenance: "exif.original")
    }
    private static func offset(_ text: String) -> Int { let parts = text.dropFirst().split(separator: ":"); guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return 0 }; return (text.hasPrefix("-") ? -1 : 1) * (h * 3600 + m * 60) }
}
public struct MediaFile: Codable {
    public var relativeSourcePath: String
    public var size: Int64
    public var captureTimestamp: Double
    public var dateSource: String
    public var device: String
    public var kind: String
    public func destinationRelativePath(in mediaDirectory: String = "01_MEDIA") -> String {
        let date = day(Date(timeIntervalSince1970: captureTimestamp))
        return "\(mediaDirectory)/\(date)/\(device)/\(kind)/\(URL(fileURLWithPath: relativeSourcePath).lastPathComponent)"
    }
}
public struct MediaScan: Codable {
    public var sourcePath: String
    public var sourceVolumeUUID: String?
    public var devices: [String]
    public var files: [MediaFile]
    public var fileCount: Int { files.count }
    public var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }
    public var startTime: Double { files.map(\.captureTimestamp).min() ?? 0 }
    public var endTime: Double { files.map(\.captureTimestamp).max() ?? 0 }
    public var dates: [String] { Set(files.map { day(Date(timeIntervalSince1970: $0.captureTimestamp)) }).sorted() }
    public var dateGroups: [MediaDateGroup] {
        Dictionary(grouping: files) { day(Date(timeIntervalSince1970: $0.captureTimestamp)) }
            .map { date, files in MediaDateGroup(date: date, fileCount: files.count, totalBytes: files.reduce(Int64(0)) { $0 + $1.size }) }
            .sorted { $0.date > $1.date }
    }
    public func selecting(dates selectedDates: Set<String>) throws -> MediaScan {
        guard !selectedDates.isEmpty else { throw WorkflowError("必须至少选择一个拍摄日期") }
        let available = Set(dates)
        guard selectedDates.isSubset(of: available) else { throw WorkflowError("选择的拍摄日期不在本次扫描结果中") }
        let selectedFiles = files.filter { selectedDates.contains(day(Date(timeIntervalSince1970: $0.captureTimestamp))) }
        return MediaScan(sourcePath: sourcePath, sourceVolumeUUID: sourceVolumeUUID, devices: Set(selectedFiles.map(\.device)).sorted(), files: selectedFiles)
    }
}
public struct MediaDateGroup: Codable, Equatable {
    public var date: String
    public var fileCount: Int
    public var totalBytes: Int64
}
public struct DeviceDetector {
    public static let devices = ["A7R5", "Pocket3", "Action6", "Air3S", "Unknown"]
    public static func detect(metadata: String, relative: String, source: String) -> String {
        let evidence = (metadata + " " + source).lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
        if evidence.contains("ilce7rm5") || evidence.contains("a7r5") { return "A7R5" }
        if evidence.contains("pocket3") { return "Pocket3" }
        if evidence.contains("action6") { return "Action6" }
        if evidence.contains("air3s") { return "Air3S" }
        // ARW + Sony camera hierarchy corroborate Sony, but do not guess a model.
        return "Unknown"
    }
}
public struct MediaScanner {
    public let metadata: MetadataProviding
    public init(metadata: MetadataProviding = NativeMetadata()) { self.metadata = metadata }
    public func scan(_ source: URL, overrideDevice: String? = nil, volumeUUID: String? = nil, onProgress: ((Int) -> Void)? = nil) throws -> MediaScan {
        let source = systemURL(source)
        try safePath(source)
        guard (try source.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true else { throw WorkflowError("媒体来源必须是目录") }
        if let overrideDevice, !DeviceDetector.devices.contains(overrideDevice) { throw WorkflowError("设备参数必须是 A7R5/Pocket3/Action6/Air3S/Unknown") }
        let raw = ["arw", "dng", "cr2", "cr3", "nef", "raf", "orf", "rw2"]
        let image = ["jpg", "jpeg", "heic", "heif", "png", "tif", "tiff"]
        let video = ["mp4", "mov", "m4v", "mts", "m2ts"]
        var files: [MediaFile] = []
        var enumerationError: Error?
        guard let walker = fm.enumerator(at: source, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey], options: [.skipsHiddenFiles], errorHandler: { _, error in enumerationError = error; return false }) else { throw WorkflowError("无法枚举媒体目录") }
        while let u = walker.nextObject() as? URL {
            let v = try u.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey])
            guard v.isSymbolicLink != true else { throw WorkflowError("媒体目录含符号链接，拒绝扫描：\(u.path)") }
            let ext = u.pathExtension.lowercased()
            guard v.isRegularFile == true, (raw + image + video).contains(ext) else { continue }
            let m = try metadata.capture(u)
            guard let capture = MediaCaptureDateResolver().resolve(metadata: m, creationDate: v.creationDate, modificationDate: v.contentModificationDate) else { throw WorkflowError("无法读取拍摄时间：\(u.path)") }
            let relative = String(u.path.dropFirst(source.path.count + 1))
            files.append(MediaFile(relativeSourcePath: relative, size: Int64(v.fileSize ?? 0), captureTimestamp: capture.date.timeIntervalSince1970, dateSource: capture.provenance, device: overrideDevice ?? DeviceDetector.detect(metadata: m.deviceEvidence, relative: relative, source: source.lastPathComponent), kind: raw.contains(ext) ? "RAW" : video.contains(ext) ? "VIDEO" : "JPEG"))
            if files.count == 1 || files.count % 25 == 0 { onProgress?(files.count) }
        }
        if let enumerationError { throw enumerationError }
        guard !files.isEmpty else { throw WorkflowError("没有发现支持的媒体文件") }
        files.sort { $0.relativeSourcePath < $1.relativeSourcePath }
        return MediaScan(sourcePath: source.path, sourceVolumeUUID: volumeUUID, devices: Set(files.map(\.device)).sorted(), files: files)
    }
}
public func mediaSources(volumes: [Volume], pool: WorkspacePool, backupPath: String, protectedBackupVolumeIDs: [String] = []) -> [Volume] {
    volumes.filter { v in
        v.removable && !protectedBackupVolumeIDs.contains(where: { $0.caseInsensitiveCompare(v.uuid) == .orderedSame }) && !pool.workspaces.contains(where: { $0.volumeUUID?.caseInsensitiveCompare(v.uuid) == .orderedSame || $0.path.map { contained(URL(fileURLWithPath: $0), in: URL(fileURLWithPath: v.path)) } == true }) && !contained(URL(fileURLWithPath: backupPath), in: URL(fileURLWithPath: v.path)) && ["DCIM", "PRIVATE", "M4ROOT"].contains(where: { fm.fileExists(atPath: URL(fileURLWithPath: v.path).appendingPathComponent($0).path) })
    }
}
public func validateSource(_ source: URL, store: ProjectStore, backupPath: String) throws {
    let source = systemURL(source)
    try safePath(source)
    let backup = systemURL(URL(fileURLWithPath: backupPath))
    let backupRoot = backupPath.hasPrefix("/Volumes/") ? URL(fileURLWithPath: "/Volumes").appendingPathComponent(backup.pathComponents[2]) : backup
    guard !contained(source, in: backupRoot), !contained(backupRoot, in: source) else { throw WorkflowError("Backup 卷不能作为 ingest source") }
    if store.volumes.contains(where: { v in
        contained(source, in: URL(fileURLWithPath: v.path)) && store.protectedBackupVolumeIDs.contains(where: { $0.caseInsensitiveCompare(v.uuid) == .orderedSame })
    }) { throw WorkflowError("已登记 Backup Volume UUID 不能作为 ingest source（即使卷已改名）") }
    for w in store.pool.workspaces {
        if let root = try store.pool.resolve(w, volumes: store.volumes) {
            let excluded = w.type == "external" ? URL(fileURLWithPath: store.volumes.first(where: { $0.uuid.caseInsensitiveCompare(w.volumeUUID ?? "") == .orderedSame })!.path) : root
            if contained(source, in: excluded) || contained(excluded, in: source) { throw WorkflowError("Workspace 不能作为 ingest source") }
        }
    }
    if source.path.hasPrefix("/Volumes/") {
        guard store.volumes.contains(where: { contained(source, in: URL(fileURLWithPath: $0.path)) }) else { throw WorkflowError("媒体卷未真实挂载") }
    }
}
