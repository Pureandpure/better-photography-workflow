import XCTest
import ImageIO
import UniformTypeIdentifiers
import AVFoundation
@testable import BPWCore

private struct FixtureMetadata: MetadataProviding {
    var device = "SONY ILCE-7RM5"
    var date = Date(timeIntervalSince1970: 1_790_800_000)
    func capture(_ url: URL) throws -> CaptureMetadata { CaptureMetadata(date: date, deviceEvidence: device, provenance: "exif.original") }
}
private struct MultiDateFixtureMetadata: MetadataProviding {
    func capture(_ url: URL) throws -> CaptureMetadata {
        let dates: [String: Double] = ["DJI_01.MP4": 1_790_800_000, "DJI_02.MP4": 1_790_886_400, "DJI_03.MP4": 1_790_972_800]
        return CaptureMetadata(date: Date(timeIntervalSince1970: dates[url.lastPathComponent]!), provenance: "video.creationDate")
    }
}
final class WorkflowTests: XCTestCase {
    var root: URL!
    var project: URL { root.appendingPathComponent("project") }
    var card: URL { root.appendingPathComponent("card") }
    var state: URL { root.appendingPathComponent("state") }
    var work: URL { root.appendingPathComponent("work") }
    override func setUpWithError() throws { root = systemURL(fm.temporaryDirectory).appendingPathComponent(UUID().uuidString); for d in [root!, project, card, state, work] { try mkdir(d) } }
    override func tearDownWithError() throws { try fm.removeItem(at: root) }
    @discardableResult func file(_ name: String = "DCIM/DSC0001.ARW", bytes: String = "original") throws -> URL { let u = card.appendingPathComponent(name); try mkdir(u.deletingLastPathComponent()); try Data(bytes.utf8).write(to: u); return u }
    func scan(_ device: String = "SONY ILCE-7RM5") throws -> MediaScan { try MediaScanner(metadata: FixtureMetadata(device: device)).scan(card) }
    func store(_ volumes: [Volume] = []) throws -> ProjectStore { try ProjectStore(state: state, workDir: work.path, volumes: volumes) }
    func testNewProjectHasStableIDAndStructure() throws { let s = try store(); let p = try s.create("平潭 & 夏日"); XCTAssertNotNil(UUID(uuidString: p.id)); XCTAssertEqual(URL(fileURLWithPath: p.path).deletingLastPathComponent().lastPathComponent, String(day(Date()).prefix(4))); for kind in ["VIDEO", "PHOTO", "AUDIO"] { XCTAssertTrue(fm.fileExists(atPath: URL(fileURLWithPath: p.path).appendingPathComponent("01_MEDIA/\(kind)").path)) }; XCTAssertEqual(try s.refresh().first?.id, p.id) }
    func testDeviceDiscoveryAcrossMixedMediaLayouts() throws {
        let s = try store(), p = try s.create("混合目录")
        let root = URL(fileURLWithPath: p.path)
        for path in ["01_MEDIA/Legacy/RAW", "01_MEDIA/2026-09-30/Pocket3/VIDEO", "01_MEDIA/PHOTO/2026-09-30/A7R5/RAW", "01_MEDIA/VIDEO/2026-09-30/A7R5", "01_MEDIA/AUDIO/2026-09-30/Recorder", "01_ORIGINALS/iPhone"] {
            try mkdir(root.appendingPathComponent(path))
        }
        XCTAssertEqual(try s.refresh().first?.deviceNames, ["A7R5", "Legacy", "Pocket3", "Recorder", "iPhone"])
    }
    func testExplicitProjectYearSelectsYearFolder() throws { let p = try store().create("2027-01_旅行"); XCTAssertEqual(URL(fileURLWithPath: p.path).deletingLastPathComponent().lastPathComponent, "2027"); XCTAssertEqual(URL(fileURLWithPath: p.path).lastPathComponent, "2027-01_旅行") }
    func testLegacyIDMigrationPreservesReminderAndStage() throws {
        let p = work.appendingPathComponent("2026-09-30_旧项目"); try mkdir(p); try mkdir(state.appendingPathComponent("projects")); try mkdir(state.appendingPathComponent("workflow-projects"))
        try Data("done".utf8).write(to: state.appendingPathComponent("projects/\(pathHash(p.path)).done"))
        try PropertyListSerialization.data(fromPropertyList: ["stageID": "edit", "isFavorite": true], format: .xml, options: 0).write(to: state.appendingPathComponent("workflow-projects/\(pathHash(p.path)).plist"))
        let s = try store(); let record = try XCTUnwrap(s.refresh().first)
        XCTAssertTrue(fm.fileExists(atPath: state.appendingPathComponent("projects/\(record.id).done").path)); XCTAssertEqual(record.currentStageID, "edit"); XCTAssertTrue(record.isFavorite)
    }
    func testDirectoryMoveKeepsID() throws { let s = try store(); let p = try s.create("移动"); let dest = URL(fileURLWithPath: p.path).deletingLastPathComponent().appendingPathComponent("重命名"); try fm.moveItem(atPath: p.path, toPath: dest.path); XCTAssertEqual(try s.refresh().first?.id, p.id) }
    func testLegacyWorkDirConfigChangeUpdatesDefaultWorkspace() throws {
        let s = try store(); _ = try s.refresh()
        let other = root.appendingPathComponent("new local"); try mkdir(other)
        let changed = try ProjectStore(state: state, workDir: other.path, volumes: [])
        XCTAssertEqual(try changed.pool.resolve(changed.pool.workspaces[0], volumes: [])?.path, other.path)
    }
    func testBackupUUIDRemainsProtectedAfterRename() throws {
        let volume = Volume(uuid: "BACKUP", path: card.path, name: "original", removable: true)
        let s = try store([volume]); try s.protectBackup(card.appendingPathComponent("Backup").path)
        let renamed = Volume(uuid: "BACKUP", path: root.appendingPathComponent("renamed").path, name: "renamed", removable: true)
        let changed = try store([renamed]); try changed.protectBackup(card.appendingPathComponent("Backup").path)
        XCTAssertThrowsError(try validateSource(URL(fileURLWithPath: renamed.path), store: changed, backupPath: card.appendingPathComponent("Backup").path))
    }
    func testFreshAmbiguousSameWorkspaceCopiesRejected() throws {
        let s = try store(), p = try s.create("primary")
        try fm.copyItem(atPath: p.path, toPath: URL(fileURLWithPath: p.path).deletingLastPathComponent().appendingPathComponent("copy").path)
        try fm.removeItem(at: state.appendingPathComponent("projects.json"))
        let fresh = try store(); XCTAssertThrowsError(try fresh.refresh())
    }
    func testMinimalV1ProjectIdentityGetsPrimaryWithoutChangingID() throws {
        let p = work.appendingPathComponent("legacy id"); try mkdir(p); let id = UUID().uuidString
        try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "id": id, "name": "已有项目", "createdAt": now()]).write(to: p.appendingPathComponent(".bpw-project.json"))
        let s = try store(); XCTAssertEqual(try s.refresh().first?.id, id)
        let value = try JSONDecoder().decode(ProjectIdentity.self, from: Data(contentsOf: p.appendingPathComponent(".bpw-project.json")))
        XCTAssertEqual(value.primaryWorkspaceId, "local"); XCTAssertEqual(value.id, id)
    }
    func testLocalOnline() throws { let s = try store(); XCTAssertEqual(try s.pool.resolve(s.pool.workspaces[0], volumes: []), work) }
    func testExternalOffline() throws { let w = Workspace(id: "ssd", name: "ssd", type: "external", volumeUUID: "UUID", relativePath: "Projects"); XCTAssertNil(try WorkspacePool(workspaces: [w]).resolve(w, volumes: [])) }
    func testUUIDRenameAndRejectWrongUUID() throws {
        let w = Workspace(id: "ssd", name: "Old name", type: "external", volumeUUID: "UUID", relativePath: "Projects")
        let p = WorkspacePool(workspaces: [w]); let v = Volume(uuid: "uuid", path: root.path, name: "renamed", removable: true)
        XCTAssertEqual(try p.resolve(w, volumes: [v])?.path, root.appendingPathComponent("Projects").path)
        XCTAssertNil(try p.resolve(w, volumes: [Volume(uuid: "OTHER", path: root.path, name: "Old name", removable: true)]))
    }
    func testAutoPrefersSSDThenLocal() throws {
        let s = try store(); let w = Workspace(id: "ssd", name: "SSD", type: "external", volumeUUID: "UUID", relativePath: "Projects"); s.pool.workspaces.append(w); s.pool.externalPrimaryWorkspaceId = "ssd"
        let v = Volume(uuid: "UUID", path: root.path, name: "SSD", removable: true)
        XCTAssertEqual(try s.pool.preferred(nil, volumes: [v]).id, "ssd"); XCTAssertEqual(try s.pool.preferred(nil, volumes: []).id, "local")
    }
    func testAskNeedsExplicitWorkspace() throws { let s = try store(); s.pool.workspacePreference = "ask"; XCTAssertThrowsError(try s.pool.preferred(nil, volumes: [])); XCTAssertEqual(try s.pool.preferred("local", volumes: []).id, "local") }
    func testRetainedCopyNeverBecomesActive() throws {
        let s = try store(); let p = try s.create("原件"); let other = root.appendingPathComponent("other"); try mkdir(other)
        try fm.copyItem(at: URL(fileURLWithPath: p.path), to: other.appendingPathComponent(p.directoryName))
        s.pool.workspaces.append(Workspace(id: "other", name: "other", type: "local", path: other.path))
        XCTAssertEqual(try s.refresh().filter { $0.status == "online" }.count, 1)
    }
    func testOfflineRegistryRetained() throws { let s = try store(); let p = try s.create("offline"); try fm.moveItem(atPath: p.path, toPath: root.appendingPathComponent("detached").path); XCTAssertEqual(try s.refresh().first?.status, "offline") }
    func testA7R5ScanUsesCaptureMetadata() throws { _ = try file(); let s = try scan(); XCTAssertEqual(s.devices, ["A7R5"]); XCTAssertEqual(s.files[0].captureTimestamp, FixtureMetadata().date.timeIntervalSince1970); XCTAssertEqual(s.totalBytes, 8); XCTAssertTrue(s.files[0].destinationRelativePath(in: "01_MEDIA").contains("/A7R5/RAW/DSC0001.ARW")) }
    func testDJIScan() throws { _ = try file("DCIM/DJI_20260930_001.MP4"); XCTAssertEqual(try scan("DJI Osmo Pocket 3").devices, ["Pocket3"]) }
    func testOtherDJIModels() { XCTAssertEqual(DeviceDetector.detect(metadata: "DJI Osmo Action 6", relative: "", source: ""), "Action6"); XCTAssertEqual(DeviceDetector.detect(metadata: "DJI Air 3S", relative: "", source: ""), "Air3S") }
    func testUnknownDoesNotGuessDJIModelFromFilename() throws { _ = try file("DCIM/DJI_001.MP4"); XCTAssertEqual(try scan("DJI").devices, ["Unknown"]) }
    func testExplicitDeviceOverride() throws { _ = try file(); XCTAssertEqual(try MediaScanner().scan(card, overrideDevice: "Pocket3").devices, ["Pocket3"]) }
    func testCaptureDatePrecedesMtime() throws { let u = try file(); try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: u.path); XCTAssertEqual(try scan().files[0].dateSource, "exif.original") }
    func testCaptureDateResolverUsesMetadataThenCreationThenModification() {
        let resolver = MediaCaptureDateResolver(), metadataDate = Date(timeIntervalSince1970: 30), creation = Date(timeIntervalSince1970: 20), modification = Date(timeIntervalSince1970: 10)
        XCTAssertEqual(resolver.resolve(metadata: CaptureMetadata(date: metadataDate, provenance: "video.creationDate"), creationDate: creation, modificationDate: modification)?.date, metadataDate)
        XCTAssertEqual(resolver.resolve(metadata: CaptureMetadata(date: nil), creationDate: creation, modificationDate: modification)?.provenance, "file.creationDate")
        XCTAssertEqual(resolver.resolve(metadata: CaptureMetadata(date: nil), creationDate: nil, modificationDate: modification)?.provenance, "file.modificationDate")
    }
    func testOnePhysicalFolderProducesSeparateCaptureDateGroups() throws {
        for name in ["DJI_01.MP4", "DJI_02.MP4", "DJI_03.MP4"] { _ = try file("DCIM/001/\(name)") }
        let result = try MediaScanner(metadata: MultiDateFixtureMetadata()).scan(card)
        XCTAssertEqual(result.dateGroups.count, 3)
        XCTAssertEqual(result.dateGroups.map(\.fileCount), [1, 1, 1])
        XCTAssertEqual(Set(result.dateGroups.map(\.date)), Set(result.dates))
    }
    func testSelectedImportScopeExcludesUnselectedDatesFromPlan() throws {
        for name in ["DJI_01.MP4", "DJI_02.MP4", "DJI_03.MP4"] { _ = try file("DCIM/001/\(name)") }
        let result = try MediaScanner(metadata: MultiDateFixtureMetadata()).scan(card)
        let selectedDate = try XCTUnwrap(result.dates.last)
        let scoped = try result.selecting(dates: [selectedDate])
        XCTAssertEqual(scoped.dates, [selectedDate])
        XCTAssertEqual(scoped.fileCount, 1)
        XCTAssertEqual(try IngestEngine().plan(scoped, project: project).copyCount, 1)
        XCTAssertThrowsError(try result.selecting(dates: []))
    }
    func testNativeEXIFAdapterReadsRealImageMetadata() throws {
        let url = card.appendingPathComponent("test.jpg")
        let pixels: [UInt8] = [255, 0, 0, 255]
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, [kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:09:30 09:12:00"], kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFModel: "ILCE-7RM5"]] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest)); let m = try NativeMetadata().capture(url); XCTAssertNotNil(m.date); XCTAssertTrue(m.deviceEvidence.contains("ILCE-7RM5")); XCTAssertEqual(m.provenance, "exif.original")
    }
    func writeJPEG(_ url: URL, model: String, timestamp: String) throws {
        try mkdir(url.deletingLastPathComponent())
        let pixels: [UInt8] = [255, 0, 0, 255]
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, [kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: timestamp], kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFModel: model]] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw WorkflowError("JPEG fixture failed") }
    }
    func testNativeCLITripSessionAcrossFourDevicesAndRetry() throws {
        let bin = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("bpw-engine")
        XCTAssertTrue(fm.isExecutableFile(atPath: bin.path))
        func execute(_ arguments: [String]) throws -> String {
            let process = Process(), pipe = Pipe(); process.executableURL = bin; process.arguments = arguments
            var environment = ProcessInfo.processInfo.environment
            environment["WORK_DIR"] = work.path; environment["BPW_STATE_DIR"] = state.path; environment["BACKUP_DESTINATION"] = root.appendingPathComponent("backup").path
            process.environment = environment; process.standardInput = FileHandle.nullDevice; process.standardOutput = pipe; process.standardError = pipe
            try process.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
            let result = String(decoding: data, as: UTF8.self)
            XCTAssertEqual(process.terminationStatus, 0, result); return result
        }
        try writeJPEG(card.appendingPathComponent("DCIM/DSC0001.JPG"), model: "ILCE-7RM5", timestamp: "2026:09:30 08:42:00")
        try writeJPEG(card.appendingPathComponent("DCIM/DSC0002.JPG"), model: "ILCE-7RM5", timestamp: "2026:09:30 18:37:00")
        _ = try execute(["ingest", card.path, "--new", "平潭旅行"])
        let p = try XCTUnwrap(store().refresh().first)
        for (model, device) in [("DJI Osmo Pocket 3", "Pocket3"), ("DJI Osmo Action 6", "Action6"), ("DJI Air 3S", "Air3S")] {
            let source = root.appendingPathComponent(device)
            try writeJPEG(source.appendingPathComponent("DCIM/DJI_001.JPG"), model: model, timestamp: "2026:09:30 09:12:00")
            try writeJPEG(source.appendingPathComponent("DCIM/DJI_002.JPG"), model: model, timestamp: "2026:09:30 17:53:00")
            let result = try execute(["ingest", source.path]); XCTAssertTrue(result.contains("Session 自动匹配"))
            XCTAssertTrue(fm.fileExists(atPath: URL(fileURLWithPath: p.path).appendingPathComponent("01_MEDIA/PHOTO/2026-09-30/\(device)/JPEG/DJI_001.JPG").path))
        }
        let retry = try execute(["ingest", card.path]); XCTAssertTrue(retry.contains("skip DCIM/DSC0001.JPG"))
        XCTAssertTrue(fm.fileExists(atPath: card.appendingPathComponent("DCIM/DSC0001.JPG").path))
        XCTAssertEqual(try store().refresh().filter { $0.status == "online" }.count, 1)
    }
    func testNativeVideoCaptureDateAndModel() async throws {
        let url = card.appendingPathComponent("test.mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let created = AVMutableMetadataItem(); created.identifier = .quickTimeMetadataCreationDate; created.value = "2026-09-30T09:12:00+08:00" as NSString; created.dataType = kCMMetadataBaseDataType_UTF8 as String
        let model = AVMutableMetadataItem(); model.identifier = .quickTimeMetadataModel; model.value = "DJI Osmo Pocket 3" as NSString; model.dataType = kCMMetadataBaseDataType_UTF8 as String
        writer.metadata = [created, model]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 16, AVVideoHeightKey: 16])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 16, kCVPixelBufferHeightKey as String: 16])
        writer.add(input); XCTAssertTrue(writer.startWriting()); writer.startSession(atSourceTime: .zero)
        var pixel: CVPixelBuffer?; XCTAssertEqual(CVPixelBufferCreate(nil, 16, 16, kCVPixelFormatType_32ARGB, nil, &pixel), kCVReturnSuccess)
        let start = Date()
        while !input.isReadyForMoreMediaData, Date().timeIntervalSince(start) < 5 { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(adaptor.append(try XCTUnwrap(pixel), withPresentationTime: .zero))
        input.markAsFinished(); await writer.finishWriting(); XCTAssertEqual(writer.status, .completed)
        let metadata = try NativeMetadata().capture(url)
        XCTAssertEqual(metadata.date, ISO8601DateFormatter().date(from: "2026-09-30T09:12:00+08:00"))
        XCTAssertTrue(metadata.deviceEvidence.contains("Pocket 3")); XCTAssertEqual(metadata.provenance, "video.creationDate")
    }
    func testDuplicateIngestSkipsWithoutRenamingOrDeleting() throws {
        let src = try file(); let s = try scan(); let engine = IngestEngine(); let id = UUID().uuidString
        _ = try engine.ingest(s, project: project, projectID: id)
        let dest = project.appendingPathComponent(s.files[0].destinationRelativePath(in: "01_MEDIA")), before = try fingerprint(dest)
        XCTAssertEqual(try engine.plan(s, project: project).skipCount, 1)
        let second = try engine.ingest(s, project: project, projectID: id)
        XCTAssertEqual(second.status, "success"); XCTAssertEqual(try fingerprint(dest), before); XCTAssertEqual(try Data(contentsOf: src), Data("original".utf8))
    }
    func testSameSizeConflictNeverOverwrites() throws {
        let src = try file(); let s = try scan(); let engine = IngestEngine(); _ = try engine.ingest(s, project: project, projectID: UUID().uuidString)
        let dest = project.appendingPathComponent(s.files[0].destinationRelativePath(in: "01_MEDIA")); try Data("conflict".utf8).write(to: dest)
        XCTAssertThrowsError(try engine.ingest(s, project: project, projectID: UUID().uuidString)); XCTAssertEqual(try Data(contentsOf: src), Data("original".utf8)); XCTAssertEqual(try Data(contentsOf: dest), Data("conflict".utf8))
    }
    func testExistingUnknownIdenticalFileCanSkipAfterHash() throws { _ = try file(); let s = try scan(); let dest = project.appendingPathComponent(s.files[0].destinationRelativePath(in: "01_MEDIA")); try mkdir(dest.deletingLastPathComponent()); try Data("original".utf8).write(to: dest); XCTAssertEqual(try IngestEngine().plan(s, project: project).skipCount, 1) }
    func testInterruptedRetry() throws {
        _ = try file(); _ = try file("DCIM/DSC0002.ARW"); let s = try scan(), engine = IngestEngine()
        engine.afterCopy = { count in if count == 1 { throw WorkflowError("interrupted") } }
        XCTAssertThrowsError(try engine.ingest(s, project: project, projectID: UUID().uuidString)); engine.afterCopy = nil
        XCTAssertEqual(try engine.plan(s, project: project).skipCount, 1); let result = try engine.ingest(s, project: project, projectID: UUID().uuidString); XCTAssertEqual(result.verifiedFileCount, 2); XCTAssertEqual(result.verifiedBytes, 16)
    }
    func testCancellationKeepsCompletedFilesAndRemovesPartialWork() throws {
        _ = try file("DCIM/DSC0001.ARW"); _ = try file("DCIM/DSC0002.ARW")
        let result = try scan(), engine = IngestEngine(); var cancelled = false
        engine.cancellationRequested = { cancelled }
        engine.afterCopy = { count in if count == 1 { cancelled = true } }
        XCTAssertThrowsError(try engine.ingest(result, project: project, projectID: "cancel-test"))
        let first = project.appendingPathComponent(result.files[0].destinationRelativePath())
        let second = project.appendingPathComponent(result.files[1].destinationRelativePath())
        XCTAssertTrue(fm.fileExists(atPath: first.path))
        XCTAssertFalse(fm.fileExists(atPath: second.path))
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: project.appendingPathComponent(".bpw/partials").path).filter { $0.hasSuffix(".part") }.count, 0)
        let manifestURL = try XCTUnwrap(fm.contentsOfDirectory(at: project.appendingPathComponent(".bpw/imports"), includingPropertiesForKeys: nil).first)
        XCTAssertEqual(try JSONDecoder().decode(ImportManifest.self, from: Data(contentsOf: manifestURL)).status, "cancelled")
    }
    func testCopyProgressReportsByteTotalsSpeedAndVerificationStage() throws {
        _ = try file(); let engine = IngestEngine(); var events: [ImportProgressEvent] = []
        engine.progress = { line in
            guard line.hasPrefix("BPW_PROGRESS "), let data = String(line.dropFirst("BPW_PROGRESS ".count)).data(using: .utf8),
                  let event = try? JSONDecoder().decode(ImportProgressEvent.self, from: data) else { return }
            events.append(event)
        }
        let manifest = try engine.ingest(scan(), project: project, projectID: "progress-test")
        XCTAssertTrue(events.contains { $0.stage == "copying" && $0.totalBytes == manifest.totalBytes && $0.copiedBytes == manifest.totalBytes && $0.completedFiles == 1 })
        XCTAssertEqual(events.last?.stage, "verifying")
    }
    func testInsufficientSpaceCopiesNothing() throws { _ = try file(); let s = try scan(), engine = IngestEngine(); engine.freeSpace = { _ in 0 }; XCTAssertThrowsError(try engine.ingest(s, project: project, projectID: "id")); XCTAssertFalse(fm.fileExists(atPath: project.appendingPathComponent("01_MEDIA").path)) }
    func testSourceChangedAfterScanRejects() throws { let u = try file(); let s = try scan(); try Data("larger original".utf8).write(to: u); XCTAssertThrowsError(try IngestEngine().ingest(s, project: project, projectID: "id")) }
    func testDestinationSymlinkRejected() throws { _ = try file(); try fm.createSymbolicLink(at: project.appendingPathComponent("01_MEDIA"), withDestinationURL: root); XCTAssertThrowsError(try IngestEngine().ingest(scan(), project: project, projectID: "id")) }
    func testSourceSymlinkRejected() throws { let u = try file(); try fm.createSymbolicLink(at: card.appendingPathComponent("link.ARW"), withDestinationURL: u); XCTAssertThrowsError(try scan()) }
    func testSameNameInsideSourceConflictIsPreflighted() throws { _ = try file("DCIM/100/DSC0001.ARW"); _ = try file("DCIM/101/DSC0001.ARW", bytes: "another"); let s = try scan(); XCTAssertFalse(try IngestEngine().plan(s, project: project).conflicts.isEmpty); XCTAssertThrowsError(try IngestEngine().ingest(s, project: project, projectID: "id")) }
    func testChecksumVerification() throws { _ = try file(); let result = try IngestEngine().ingest(scan(), project: project, projectID: "id", checksum: true); XCTAssertEqual(result.files[0].sha256.count, 64); XCTAssertEqual(result.status, "success") }
    func testLockRejectsConcurrentAndReleases() throws { var first: StateLock? = try StateLock(state); XCTAssertThrowsError(try StateLock(state)); first = nil; _ = try StateLock(state); withExtendedLifetime(first) {} }
    func testBackupAndWorkspaceVolumesExcludedFromAutoScan() throws {
        try mkdir(card.appendingPathComponent("DCIM"))
        let v = Volume(uuid: "U", path: card.path, name: "SD", removable: true)
        let empty = WorkspacePool(workspaces: [])
        XCTAssertEqual(mediaSources(volumes: [v], pool: empty, backupPath: root.appendingPathComponent("backup").path).count, 1)
        XCTAssertTrue(mediaSources(volumes: [v], pool: empty, backupPath: card.appendingPathComponent("backup").path).isEmpty)
        let pool = WorkspacePool(workspaces: [Workspace(id: "ssd", name: "ssd", type: "external", volumeUUID: "U", relativePath: "Projects")])
        XCTAssertTrue(mediaSources(volumes: [v], pool: pool, backupPath: "/offline").isEmpty)
    }
    func testOrdinarySSDWithoutCameraHierarchyExcluded() { XCTAssertTrue(mediaSources(volumes: [Volume(uuid: "u", path: card.path, name: "SSD", removable: true)], pool: WorkspacePool(workspaces: []), backupPath: "/offline").isEmpty) }
    func testExplicitWorkspaceSourceRejected() throws { let s = try store(); XCTAssertThrowsError(try validateSource(work, store: s, backupPath: "/offline")) }
    func testExplicitBackupSourceRejected() throws { let s = try store(); XCTAssertThrowsError(try validateSource(card, store: s, backupPath: card.appendingPathComponent("backup").path)) }
    func testStaleVolumesDirectoryRejected() throws { let s = try store(); XCTAssertThrowsError(try validateSource(URL(fileURLWithPath: "/Volumes/unmounted"), store: s, backupPath: "/offline")) }
    func session(_ s: MediaScan, project: ProjectRecord, offset: Double = 0) -> Session { Session(projectId: project.id, captureDate: s.dates[0], startTime: s.startTime + offset - 100, endTime: s.endTime + offset + 100, lastIngestAt: Date().timeIntervalSince1970 - 60, devices: ["A7R5"]) }
    func testSameDateOverlapAutomaticallyMatches() throws { _ = try file(); let s = try scan(), p = try store().create("旅行"); XCTAssertTrue(SessionMatcher.candidates(scan: s, sessions: [session(s, project: p)], projects: [p])[0].automatic) }
    func testSameDateDifferentTimeDoesNotAutoMatch() throws { _ = try file(); let s = try scan(), p = try store().create("旅行"); XCTAssertFalse(SessionMatcher.candidates(scan: s, sessions: [session(s, project: p, offset: 3600)], projects: [p])[0].automatic) }
    func testDifferentDateDoesNotMatch() throws { _ = try file(); let s = try scan(), p = try store().create("旅行"); var ses = session(s, project: p); ses.captureDate = "2000-01-01"; XCTAssertTrue(SessionMatcher.candidates(scan: s, sessions: [ses], projects: [p]).isEmpty) }
    func testAmbiguousProjectsAlwaysAsk() throws { _ = try file(); let s = try scan(), store = try store(), a = try store.create("A"), b = try store.create("B"); XCTAssertTrue(SessionMatcher.candidates(scan: s, sessions: [session(s, project: a), session(s, project: b)], projects: [a, b]).allSatisfy { !$0.automatic }) }
    func testFileTimeFallbackNeverAutoMatches() throws { _ = try file(); var s = try scan(); s.files[0].dateSource = "file.creationDate"; let p = try store().create("旅行"); XCTAssertFalse(SessionMatcher.candidates(scan: s, sessions: [session(s, project: p)], projects: [p])[0].automatic) }
    func testInactiveOrOfflineProjectExcluded() throws { _ = try file(); let s = try scan(); var p = try store().create("旅行"); let ses = session(s, project: p); p.status = "offline"; XCTAssertTrue(SessionMatcher.candidates(scan: s, sessions: [ses], projects: [p]).isEmpty); p.status = "online"; p.currentStageID = "done"; XCTAssertTrue(SessionMatcher.candidates(scan: s, sessions: [ses], projects: [p]).isEmpty) }
    func testOldSessionExcluded() throws { _ = try file(); let s = try scan(), p = try store().create("旅行"); var ses = session(s, project: p); ses.lastIngestAt -= 8 * 86400; XCTAssertTrue(SessionMatcher.candidates(scan: s, sessions: [ses], projects: [p]).isEmpty) }
    func testDryRefreshDoesNotCreateMetadataOrRegistry() throws { try mkdir(work.appendingPathComponent("legacy")); let s = try store(); _ = try s.refresh(persist: false); XCTAssertFalse(fm.fileExists(atPath: work.appendingPathComponent("legacy/.bpw-project.json").path)); XCTAssertFalse(fm.fileExists(atPath: state.appendingPathComponent("projects.json").path)) }
}
