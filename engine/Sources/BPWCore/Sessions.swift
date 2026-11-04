import Foundation
public struct Session: Codable {
    public var projectId: String
    public var captureDate: String
    public var startTime: Double
    public var endTime: Double
    public var lastIngestAt: Double
    public var devices: [String]
    public init(projectId: String, captureDate: String, startTime: Double, endTime: Double, lastIngestAt: Double, devices: [String]) { self.projectId = projectId; self.captureDate = captureDate; self.startTime = startTime; self.endTime = endTime; self.lastIngestAt = lastIngestAt; self.devices = devices }
}
public struct SessionCandidate: Codable {
    public var projectId: String
    public var score: Int
    public var automatic: Bool
}
public enum SessionMatcher {
    public static func candidates(scan: MediaScan, sessions: [Session], projects: [ProjectRecord], at: Double = Date().timeIntervalSince1970) -> [SessionCandidate] {
        var scores: [String: Int] = [:]
        // Birth/mtime fallback is unsuitable evidence for unattended project selection.
        let trusted = scan.files.allSatisfy { !$0.dateSource.hasPrefix("file.") }
        let recentProject = sessions.max { $0.lastIngestAt < $1.lastIngestAt }?.projectId
        for s in sessions {
            guard scan.dates.contains(s.captureDate), let p = projects.first(where: { $0.id == s.projectId }), p.status == "online", p.currentStageID != "done", at - s.lastIngestAt < 7 * 86400, at >= s.lastIngestAt else { continue }
            let daily = scan.files.filter { day(Date(timeIntervalSince1970: $0.captureTimestamp)) == s.captureDate }
            let start = daily.map(\.captureTimestamp).min() ?? 0, end = daily.map(\.captureTimestamp).max() ?? 0
            let overlap = min(end, s.endTime) - max(start, s.startTime)
            // A broad multi-day union is never used as time-overlap evidence.
            let score = 50 + (overlap >= 0 ? 30 : 0) + (s.projectId == recentProject ? 10 : 0) + 5
            scores[s.projectId] = max(scores[s.projectId] ?? 0, score)
        }
        let sorted = scores.sorted { $0.value > $1.value }
        return sorted.map { SessionCandidate(projectId: $0.key, score: $0.value, automatic: trusted && scan.dates.count == 1 && sorted.count == 1 && $0.value >= 85) }
    }
    public static func record(scan: MediaScan, projectId: String, sessions: inout [Session]) {
        for d in scan.dates {
            let files = scan.files.filter { day(Date(timeIntervalSince1970: $0.captureTimestamp)) == d }
            let start = files.map(\.captureTimestamp).min()!, end = files.map(\.captureTimestamp).max()!
            // Keep separate non-overlapping shoots instead of bridging morning and evening sessions.
            if let index = sessions.firstIndex(where: { $0.projectId == projectId && $0.captureDate == d && min(end, $0.endTime) >= max(start, $0.startTime) }) {
                sessions[index].startTime = min(start, sessions[index].startTime); sessions[index].endTime = max(end, sessions[index].endTime); sessions[index].lastIngestAt = Date().timeIntervalSince1970; sessions[index].devices = Set(sessions[index].devices + scan.devices).sorted()
            } else { sessions.append(Session(projectId: projectId, captureDate: d, startTime: start, endTime: end, lastIngestAt: Date().timeIntervalSince1970, devices: scan.devices)) }
        }
    }
}
