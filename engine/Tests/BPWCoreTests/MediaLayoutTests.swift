import XCTest
@testable import BPWCore

private struct LayoutMetadata: MetadataProviding {
    func capture(_ url: URL) throws -> CaptureMetadata {
        CaptureMetadata(date: Date(timeIntervalSince1970: url.lastPathComponent.hasPrefix("next") ? 1_790_886_400 : 1_790_800_000), deviceEvidence: url.lastPathComponent.hasPrefix("dji") ? "Pocket 3" : "ILCE-7RM5", provenance: "fixture")
    }
}
private struct NoMetadata: MetadataProviding { func capture(_ url: URL) throws -> CaptureMetadata { CaptureMetadata(date: nil) } }
final class MediaLayoutTests: XCTestCase {
    var root: URL!; var card: URL!; var project: URL!
    override func setUpWithError() throws {
        root = systemURL(fm.temporaryDirectory).appendingPathComponent(UUID().uuidString); card = root.appendingPathComponent("card"); project = root.appendingPathComponent("project")
        try mkdir(card); try mkdir(project)
    }
    override func tearDownWithError() throws { try fm.removeItem(at: root) }
    @discardableResult func write(_ base: URL, _ path: String, _ text: String = "content") throws -> URL {
        let u = base.appendingPathComponent(path); try mkdir(u.deletingLastPathComponent()); try Data(text.utf8).write(to: u); return u
    }
    func testNewPathsMixedDatesDevicesAudioAndSidecars() throws {
        for name in ["a.ARW", "a.xmp", "a.photo-edit", "a.JPG", "a.HEIC", "a.MOV", "dji.MP4", "next.MOV", "record.wav", "orphan.xmp"] { try write(card, name) }
        let scan = try MediaScanner(metadata: LayoutMetadata()).scan(card, overrideRecorder: "Zoom H6")
        XCTAssertEqual(scan.orphanSidecars, ["orphan.xmp"]); XCTAssertEqual(scan.files.count, 9)
        let paths = scan.files.map { $0.destinationRelativePath() }
        XCTAssertTrue(paths.contains { $0.contains("/PHOTO/") && $0.hasSuffix("/A7R5/RAW/a.ARW") })
        XCTAssertTrue(paths.contains { $0.hasSuffix("/A7R5/RAW/a.xmp") })
        XCTAssertTrue(paths.contains { $0.hasSuffix("/A7R5/RAW/a.photo-edit") })
        XCTAssertTrue(paths.contains { $0.hasSuffix("/A7R5/JPEG/a.HEIC") })
        XCTAssertTrue(paths.contains { $0.contains("/VIDEO/") && $0.hasSuffix("/A7R5/a.MOV") })
        XCTAssertTrue(paths.contains { $0.contains("/VIDEO/") && $0.hasSuffix("/Pocket3/dji.MP4") })
        XCTAssertTrue(paths.contains { $0.contains("/AUDIO/") && $0.hasSuffix("/Zoom H6/record.wav") })
        XCTAssertEqual(scan.dates.count, 2)
        let result = try IngestEngine().ingest(scan, project: project, projectID: "test", checksum: true)
        XCTAssertEqual(result.verifiedFileCount, 9); XCTAssertEqual(result.files.count, 9)
        XCTAssertEqual(try IngestEngine().plan(scan, project: project).skipCount, 9)
    }
    func testAudioFallbackAndSafeOverride() throws {
        for ext in ["wav", "m4a", "aac", "mp3", "aiff", "aif", "flac"] { try write(card, "sample.\(ext)") }
        let scan = try MediaScanner(metadata: NoMetadata()).scan(card)
        XCTAssertEqual(scan.fileCount, 7)
        XCTAssertEqual(scan.files[0].device, "Audio"); XCTAssertTrue(scan.files[0].dateSource.hasPrefix("file."))
        XCTAssertThrowsError(try MediaScanner().scan(card, overrideRecorder: "../unsafe"))
        let r = MediaCaptureDateResolver()
        XCTAssertEqual(r.resolve(metadata: CaptureMetadata(date: nil), creationDate: nil, modificationDate: Date(timeIntervalSince1970: 5))?.provenance, "file.modificationDate")
    }
    func testOrphanOnlyScanReportsWithoutGuessing() throws {
        try write(card, "lonely.xmp", "metadata")
        let scan = try MediaScanner().scan(card)
        XCTAssertEqual(scan.fileCount, 0); XCTAssertEqual(scan.orphanSidecars, ["lonely.xmp"])
    }
    func testSameContentExistingTargetIsRecognized() throws {
        let old = try write(project, "01_MEDIA/2026-09-30/A7R5/RAW/a.ARW", "same")
        let new = try write(project, "01_MEDIA/PHOTO/2026-09-30/A7R5/RAW/a.ARW", "same")
        let migration = MediaLayoutMigration()
        let preview = try migration.plan(project: project, projectID: "test")
        XCTAssertTrue(preview.conflicts.isEmpty)
        XCTAssertTrue(preview.items.contains { $0.status == "already" && $0.oldPath == "01_MEDIA/PHOTO/2026-09-30/A7R5/RAW/a.ARW" })
        _ = try migration.execute(project: project, projectID: "test")
        XCTAssertFalse(fm.fileExists(atPath: old.path)); XCTAssertEqual(try Data(contentsOf: new), Data("same".utf8))
    }
    func testJPEGEditFollowsUniquePhotoDuringMigration() throws {
        let old = "01_MEDIA/Air3S/"
        try write(project, old + "image.JPG", "photo")
        try write(project, old + "image.photo-edit", "edit")
        let migration = MediaLayoutMigration(), plan = try migration.plan(project: project, projectID: "test")
        let main = try XCTUnwrap(plan.items.first { $0.kind == "JPEG" })
        let side = try XCTUnwrap(plan.items.first { $0.kind == "SIDECAR" })
        XCTAssertEqual(side.primaryPath, main.oldPath)
        XCTAssertEqual((side.newPath as NSString).deletingLastPathComponent, (main.newPath as NSString).deletingLastPathComponent)
        XCTAssertTrue(plan.orphanSidecars.isEmpty); XCTAssertTrue(plan.conflicts.isEmpty)
        _ = try migration.execute(project: project, projectID: "test")
        XCTAssertEqual(try Data(contentsOf: project.appendingPathComponent(side.newPath)), Data("edit".utf8))
    }
    func testAmbiguousJPEGSidecarBlocksMigration() throws {
        let old = "01_MEDIA/2026-09-30/A7R5/JPEG/"
        try write(project, old + "a.jpg", "one"); try write(project, old + "a.heic", "two"); try write(project, old + "a.photo-edit", "edit")
        let migration = MediaLayoutMigration(), plan = try migration.plan(project: project, projectID: "test")
        XCTAssertEqual(plan.orphanSidecars, [old + "a.photo-edit"]); XCTAssertFalse(plan.conflicts.isEmpty)
        XCTAssertThrowsError(try migration.execute(project: project, projectID: "test"))
        XCTAssertTrue(fm.fileExists(atPath: project.appendingPathComponent(old + "a.jpg").path))
    }
    func testSidecarPrefersUniqueRawWhenJPEGSharesBasename() throws {
        let old = "01_MEDIA/2026-09-30/A7R5/RAW/"
        try write(project, old + "a.ARW"); try write(project, old + "a.JPG"); try write(project, old + "a.xmp")
        let plan = try MediaLayoutMigration().plan(project: project, projectID: "test")
        XCTAssertEqual(plan.items.first { $0.kind == "SIDECAR" }?.primaryPath, old + "a.ARW")
        XCTAssertTrue(plan.conflicts.isEmpty)
    }
    func testLegacyDuplicateAndMigrationKeepManifest() throws {
        try write(card, "a.ARW")
        let scan = try MediaScanner(metadata: LayoutMetadata()).scan(card), f = scan.files[0]
        let old = project.appendingPathComponent(f.legacyDestinationRelativePath()); try mkdir(old.deletingLastPathComponent()); try fm.copyItem(at: card.appendingPathComponent("a.ARW"), to: old)
        let engine = IngestEngine(); XCTAssertEqual(try engine.plan(scan, project: project).skipCount, 1)
        let manifest = try engine.ingest(scan, project: project, projectID: "test")
        let manifestFile = project.appendingPathComponent(".bpw/imports/\(manifest.id).json"), before = try Data(contentsOf: manifestFile)
        let migration = MediaLayoutMigration(); let preview = try migration.plan(project: project, projectID: "test")
        XCTAssertEqual(preview.items.filter { $0.status == "planned" }.count, 1); XCTAssertTrue(fm.fileExists(atPath: old.path))
        _ = try migration.execute(project: project, projectID: "test")
        XCTAssertFalse(fm.fileExists(atPath: old.path)); XCTAssertEqual(try Data(contentsOf: manifestFile), before)
        XCTAssertEqual(try engine.plan(scan, project: project).skipCount, 1)
        XCTAssertEqual(try engine.ingest(scan, project: project, projectID: "test").verifiedFileCount, 1)
    }
    func testMigrationDryRunConflictAndRecovery() throws {
        let old = "01_MEDIA/2026-09-30/A7R5/RAW/"
        for (name, value) in [("a.ARW", "raw"), ("a.xmp", "xmp"), ("a.photo-edit", "edit"), ("orphan.xmp", "orphan"), ("b.ARW", "second")] { try write(project, old + name, value) }
        try write(project, old + "unknown.bin", "unclassified")
        let originalTime = Date(timeIntervalSince1970: 1_600_000_000)
        try fm.setAttributes([.modificationDate: originalTime], ofItemAtPath: project.appendingPathComponent(old + "a.ARW").path)
        let migration = MediaLayoutMigration(), preview = try migration.plan(project: project, projectID: "test")
        XCTAssertEqual(preview.items.count, 4); XCTAssertEqual(preview.orphanSidecars, [old + "orphan.xmp"])
        XCTAssertEqual(preview.unclassified, [old + "unknown.bin"])
        XCTAssertEqual(preview.items.first { $0.oldPath == old + "a.xmp" }?.primaryPath, old + "a.ARW")
        XCTAssertTrue(fm.fileExists(atPath: project.appendingPathComponent(old + "a.ARW").path)); XCTAssertFalse(fm.fileExists(atPath: project.appendingPathComponent(".bpw").path))
        let conflict = try write(project, "01_MEDIA/PHOTO/2026-09-30/A7R5/RAW/a.ARW", "different")
        XCTAssertFalse(try migration.plan(project: project, projectID: "test").conflicts.isEmpty)
        XCTAssertThrowsError(try migration.execute(project: project, projectID: "test"))
        XCTAssertTrue(fm.fileExists(atPath: project.appendingPathComponent(old + "a.xmp").path)); XCTAssertTrue(fm.fileExists(atPath: project.appendingPathComponent(old + "b.ARW").path))
        try fm.removeItem(at: conflict)
        migration.afterGroup = { _ in throw WorkflowError("simulated interruption") }
        XCTAssertThrowsError(try migration.execute(project: project, projectID: "test", checksum: true))
        migration.afterGroup = nil
        let report = try migration.execute(project: project, projectID: "test", checksum: true)
        XCTAssertEqual(report.status, "completed"); XCTAssertEqual(report.items.filter { $0.status == "migrated" }.count, 4)
        XCTAssertFalse(fm.fileExists(atPath: project.appendingPathComponent(old + "a.ARW").path))
        XCTAssertTrue(fm.fileExists(atPath: project.appendingPathComponent("01_MEDIA/PHOTO/2026-09-30/A7R5/RAW/a.xmp").path))
        let moved = project.appendingPathComponent("01_MEDIA/PHOTO/2026-09-30/A7R5/RAW/a.ARW")
        XCTAssertEqual((try fm.attributesOfItem(atPath: moved.path)[.modificationDate] as? Date)?.timeIntervalSince1970, originalTime.timeIntervalSince1970)
        XCTAssertTrue(fm.fileExists(atPath: project.appendingPathComponent(old + "orphan.xmp").path))
        let reports = try fm.contentsOfDirectory(at: project.appendingPathComponent(".bpw/media-layout-migrations"), includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        let saved = try JSONDecoder().decode(MediaMigrationReport.self, from: Data(contentsOf: XCTUnwrap(reports.first)))
        XCTAssertTrue(saved.items.contains { $0.oldPath == old + "a.ARW" && $0.newPath == "01_MEDIA/PHOTO/2026-09-30/A7R5/RAW/a.ARW" })
    }
    func testSidecarConflictPreventsPrimaryImport() throws {
        try write(card, "a.ARW", "raw"); try write(card, "a.xmp", "source-sidecar")
        let scan = try MediaScanner(metadata: LayoutMetadata()).scan(card), side = try XCTUnwrap(scan.files.first { $0.kind == "SIDECAR" })
        try write(project, side.destinationRelativePath(), "other-sidecar")
        XCTAssertThrowsError(try IngestEngine().ingest(scan, project: project, projectID: "test"))
        let main = try XCTUnwrap(scan.files.first { $0.kind == "RAW" })
        XCTAssertFalse(fm.fileExists(atPath: project.appendingPathComponent(main.destinationRelativePath()).path))
    }
    func testPrimaryConflictPreventsSidecarImport() throws {
        try write(card, "a.raw", "raw"); try write(card, "a.xmp", "sidecar")
        let scan = try MediaScanner(metadata: LayoutMetadata()).scan(card)
        let main = try XCTUnwrap(scan.files.first { $0.kind == "RAW" }), side = try XCTUnwrap(scan.files.first { $0.kind == "SIDECAR" })
        try write(project, main.destinationRelativePath(), "different")
        XCTAssertThrowsError(try IngestEngine().ingest(scan, project: project, projectID: "test"))
        XCTAssertFalse(fm.fileExists(atPath: project.appendingPathComponent(side.destinationRelativePath()).path))
    }
    func testPrimaryChangedAfterPreflightStopsSidecar() throws {
        try write(card, "a.raw", "raw"); try write(card, "a.xmp", "sidecar")
        let scan = try MediaScanner(metadata: LayoutMetadata()).scan(card)
        let main = try XCTUnwrap(scan.files.first { $0.kind == "RAW" }), side = try XCTUnwrap(scan.files.first { $0.kind == "SIDECAR" })
        let engine = IngestEngine()
        engine.afterCopy = { count in if count == 1 { try Data("bad".utf8).write(to: self.project.appendingPathComponent(main.destinationRelativePath())) } }
        XCTAssertThrowsError(try engine.ingest(scan, project: project, projectID: "test"))
        XCTAssertFalse(fm.fileExists(atPath: project.appendingPathComponent(side.destinationRelativePath()).path))
    }
    func testInterruptedPublicationKeepsCompleteSourceGroup() throws {
        let old = "01_MEDIA/2026-09-30/A7R5/RAW/"
        try write(project, old + "a.ARW", "raw"); try write(project, old + "a.xmp", "xmp")
        let migration = MediaLayoutMigration()
        migration.afterPublish = { _ in throw WorkflowError("interrupted inside group") }
        XCTAssertThrowsError(try migration.execute(project: project, projectID: "test"))
        XCTAssertTrue(fm.fileExists(atPath: project.appendingPathComponent(old + "a.ARW").path))
        XCTAssertTrue(fm.fileExists(atPath: project.appendingPathComponent(old + "a.xmp").path))
        migration.afterPublish = nil
        XCTAssertEqual(try migration.execute(project: project, projectID: "test").status, "completed")
        XCTAssertFalse(fm.fileExists(atPath: project.appendingPathComponent(old + "a.ARW").path))
        XCTAssertFalse(fm.fileExists(atPath: project.appendingPathComponent(old + "a.xmp").path))
    }
    func testManifestMappingWithDifferentMigratedDate() throws {
        let source = try write(card, "a.ARW", "raw")
        let scan = try MediaScanner(metadata: LayoutMetadata()).scan(card), f = scan.files[0]
        let legacy = try write(project, "01_MEDIA/A7R5/RAW/a.ARW", "raw")
        let entry = ImportEntry(relativeSourcePath: f.relativeSourcePath, destinationPath: "01_MEDIA/A7R5/RAW/a.ARW", size: f.size, captureTimestamp: f.captureTimestamp, sha256: try digest(source), sourceFingerprint: try fingerprint(source), destinationFingerprint: try fingerprint(legacy))
        let manifest = ImportManifest(id: "legacy", projectId: "test", devices: ["A7R5"], captureDates: scan.dates, sourcePath: card.path, sourceVolumeUUID: nil, importedAt: now(), status: "success", fileCount: 1, totalBytes: f.size, verifiedFileCount: 1, verifiedBytes: f.size, files: [entry], error: nil)
        try atomic(manifest, project.appendingPathComponent(".bpw/imports/legacy.json"))
        let report = try MediaLayoutMigration().execute(project: project, projectID: "test")
        XCTAssertNotEqual(report.items[0].newPath, f.destinationRelativePath())
        XCTAssertEqual(try IngestEngine().plan(scan, project: project).skipCount, 1)
        _ = try IngestEngine().ingest(scan, project: project, projectID: "test")
        XCTAssertFalse(fm.fileExists(atPath: project.appendingPathComponent(f.destinationRelativePath()).path))
    }
    func testMigrationCLIRequiresExplicitExecute() throws {
        let work = root.appendingPathComponent("work"), state = root.appendingPathComponent("state")
        try mkdir(work); try mkdir(state)
        let store = try ProjectStore(state: state, workDir: work.path, volumes: [])
        let record = try store.create("CLI"), p = URL(fileURLWithPath: record.path)
        let source = try write(p, "01_MEDIA/2026-09-30/A7R5/RAW/a.ARW", "original")
        let bin = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("bpw-engine")
        func run(_ args: [String]) throws -> (Int32, String) {
            let process = Process(), pipe = Pipe(); process.executableURL = bin; process.arguments = args
            var env = ProcessInfo.processInfo.environment; env["WORK_DIR"] = work.path; env["BPW_STATE_DIR"] = state.path; env["BACKUP_DESTINATION"] = root.appendingPathComponent("backup").path
            process.environment = env; process.standardOutput = pipe; process.standardError = pipe
            try process.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        }
        try write(card, "record.wav", "audio")
        let audio = try run(["media", card.path, "--recorder", "Zoom H6"])
        XCTAssertEqual(audio.0, 0, audio.1)
        let audioScan = try JSONDecoder().decode(MediaScan.self, from: Data(audio.1.utf8))
        XCTAssertEqual(audioScan.files.first?.device, "Zoom H6")
        let preview = try run(["migrate-media-layout", "--project", record.id]); XCTAssertEqual(preview.0, 0, preview.1)
        XCTAssertTrue(fm.fileExists(atPath: source.path)); XCTAssertFalse(fm.fileExists(atPath: p.appendingPathComponent(".bpw/media-layout-migrations").path))
        let execute = try run(["migrate-media-layout", "--project", record.id, "--execute", "--checksum"]); XCTAssertEqual(execute.0, 0, execute.1)
        XCTAssertFalse(fm.fileExists(atPath: source.path)); XCTAssertTrue(fm.fileExists(atPath: p.appendingPathComponent("01_MEDIA/PHOTO/2026-09-30/A7R5/RAW/a.ARW").path))
    }
}
