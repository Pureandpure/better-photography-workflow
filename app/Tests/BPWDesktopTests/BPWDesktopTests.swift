import XCTest
@testable import BPWDesktop

final class BPWDesktopTests: XCTestCase {
    func testIngestScanDecodesBackendMetadataAndSummary() throws {
        let payload = #"{"sourcePath":"/Volumes/卡","devices":["A7R5"],"files":[{"size":1024,"captureTimestamp":1790759520,"dateSource":"exif.original"}]}"#
        let scan = try JSONDecoder().decode(IngestScanRecord.self, from: Data(payload.utf8))
        XCTAssertTrue(scan.summary.contains("A7R5"))
        XCTAssertTrue(scan.summary.contains("1 files"))
        XCTAssertFalse(scan.dateRange.isEmpty)
    }

    func testImportPreviewGroupsSelectedDatesByDeviceAndKind() throws {
        let payload = #"{"sourcePath":"/tmp/card","devices":["A7R5"],"files":[{"size":100,"captureTimestamp":1790759520,"dateSource":"exif.original","device":"A7R5","kind":"RAW"},{"size":200,"captureTimestamp":1790759520,"dateSource":"video.creationDate","device":"A7R5","kind":"VIDEO"}]}"#
        let scan = try JSONDecoder().decode(IngestScanRecord.self, from: Data(payload.utf8))
        let groups = scan.destinationGroups(selectedDates: Set(scan.dates))
        XCTAssertEqual(groups.count, 2)
        XCTAssertTrue(groups.contains { $0.contains("A7R5 · RAW") && $0.contains("1 个文件") })
        XCTAssertTrue(groups.contains { $0.contains("A7R5 · VIDEO") })
        XCTAssertTrue(scan.destinationGroups(selectedDates: []).isEmpty)
    }

    func testRecentImportDecodesUnicodeAndDevices() throws {
        let payload = #"{"id":"i","projectName":"平潭旅行","devices":["Pocket3"],"importedAt":"2026-09-30T10:00:00Z","status":"success","fileCount":2,"totalBytes":1024}"#
        let record = try JSONDecoder().decode(RecentImportRecord.self, from: Data(payload.utf8))
        XCTAssertEqual(record.projectName, "平潭旅行")
        XCTAssertEqual(record.devices, ["Pocket3"])
    }

    func testConfigurationRoundTripPreservesUnicodeAndPaths() throws {
        var configuration = BPWConfiguration()
        configuration.workDir = "/Users/测试/Pictures/猫咪 & 夏日"
        configuration.reminderListName = "🍎修图计划"
        configuration.projectSubdirectories = ["01_RAW", "参考 资料"]

        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(BPWConfiguration.self, from: data)

        XCTAssertEqual(decoded, configuration)
        XCTAssertNil(decoded.validationMessage)
    }

    func testBackupMustRemainInsideConfiguredVolume() {
        var configuration = BPWConfiguration()
        configuration.workDir = "/tmp/Photography"
        configuration.enableBackup = true
        configuration.backupVolumeName = "Photo SSD"
        configuration.backupDestination = "/tmp/not-the-volume"

        XCTAssertNotNil(configuration.validationMessage)

        configuration.backupDestination = "/Volumes/Photo SSD/Photography"
        XCTAssertNil(configuration.validationMessage)
    }

    func testStatusParserKeepsValuesContainingPunctuation() {
        let status = BPWStatus(text: """
        扫描服务：已加载
        最近扫描：2026-07-23 22:00:00；success；0s；scan_completed
        """)

        XCTAssertTrue(status.scanHealthy)
        XCTAssertEqual(status["最近扫描"], "2026-07-23 22:00:00；success；0s；scan_completed")
    }

    func testRealProjectRecordMapsToWorkflowAndDisplayName() {
        let record = CreatorProjectRecord(
            id: "project-1",
            path: "/Volumes/Creator SSD/素材/2026-09-01_东京 Vlog",
            directoryName: "2026-09-01_东京 Vlog",
            createdEpoch: 1_700_000_000,
            updatedEpoch: 1_700_000_100,
            currentStageID: "edit",
            isFavorite: true,
            deviceNames: ["iPhone 17 Pro", "Pocket3"]
        )

        let project = CreatorProject(record: record)

        XCTAssertEqual(project.name, "东京 Vlog")
        XCTAssertEqual(project.currentStageID, "edit")
        XCTAssertEqual(project.progress, 71)
        XCTAssertEqual(project.nextStageID, "export")
        XCTAssertTrue(project.isFavorite)
        XCTAssertEqual(project.devices.map(\.name), ["iPhone 17 Pro", "Pocket3"])
        XCTAssertEqual(project.storageSummary, "外置主素材库 · 1 份副本")
    }

    func testDoneProjectIsComplete() {
        let record = CreatorProjectRecord(
            id: "done",
            path: "/tmp/Project",
            directoryName: "Project",
            createdEpoch: 0,
            updatedEpoch: 0,
            currentStageID: "done",
            isFavorite: false,
            deviceNames: []
        )

        let project = CreatorProject(record: record)
        XCTAssertTrue(project.isComplete)
        XCTAssertEqual(project.progress, 100)
        XCTAssertNil(project.nextStageID)
    }
}
