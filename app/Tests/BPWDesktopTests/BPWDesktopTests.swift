import XCTest
@testable import BPWDesktop

final class BPWDesktopTests: XCTestCase {
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
}
