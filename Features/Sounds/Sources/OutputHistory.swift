import Foundation

struct OutputRecord: Codable, Equatable, Sendable {
    var bundleID: String
    var pid: pid_t
    var deviceName: String
    var startedAt: Date
    var stoppedAt: Date?
}

struct OutputSource: Identifiable, Equatable, Sendable {
    var id: String
    var bundleID: String
    var pid: pid_t
    var deviceName: String
    var startedAt: Date
    var stoppedAt: Date?
    var isSystem: Bool

    var isPlaying: Bool { stoppedAt == nil }

    func relativeDescription(now: Date) -> String {
        if isPlaying {
            return "играет с \(startedAt.formatted(date: .omitted, time: .shortened))"
        }

        let seconds = max(0, Int(now.timeIntervalSince(stoppedAt ?? startedAt)))
        if seconds < 60 {
            return "играл \(seconds) с назад"
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return "играл \(minutes) мин назад"
        }

        return "играл \(minutes / 60) ч назад"
    }
}

struct OutputHistory: Sendable {
    private var records: [OutputRecord] = []
    private let limit = 64
    private let persistHorizon: TimeInterval = 24 * 60 * 60

    mutating func started(bundleID: String, pid: pid_t, deviceName: String, at: Date) {
        if let index = records.firstIndex(where: { $0.pid == pid && $0.stoppedAt == nil }) {
            records[index].deviceName = deviceName
            records[index].bundleID = bundleID
            return
        }

        if !bundleID.isEmpty,
            let index = records.firstIndex(where: {
                $0.bundleID == bundleID && $0.stoppedAt == nil
            })
        {
            records[index].pid = pid
            records[index].deviceName = deviceName
            return
        }

        records.append(
            OutputRecord(
                bundleID: bundleID,
                pid: pid,
                deviceName: deviceName,
                startedAt: at,
                stoppedAt: nil
            )
        )
        trim()
    }

    mutating func stopped(bundleID: String, pid: pid_t, at: Date) {
        if let index = records.firstIndex(where: { $0.pid == pid && $0.stoppedAt == nil }) {
            records[index].stoppedAt = at
            return
        }

        if !bundleID.isEmpty,
            let index = records.firstIndex(where: {
                $0.bundleID == bundleID && $0.stoppedAt == nil
            })
        {
            records[index].stoppedAt = at
        }
    }

    func current(hidingSystem: Bool) -> [OutputSource] {
        present(records.filter { $0.stoppedAt == nil }, hidingSystem: hidingSystem)
            .sorted { $0.startedAt > $1.startedAt }
    }

    func recent(since: Date, hidingSystem: Bool) -> [OutputSource] {
        let currentIDs = Set(current(hidingSystem: false).map(\.id))
        let stopped = records.filter { record in
            guard let stoppedAt = record.stoppedAt else { return false }
            return stoppedAt >= since
        }
        return present(stopped, hidingSystem: hidingSystem)
            .filter { !currentIDs.contains($0.id) }
            .sorted { ($0.stoppedAt ?? $0.startedAt) > ($1.stoppedAt ?? $1.startedAt) }
    }

    func latestNonSystem() -> OutputSource? {
        current(hidingSystem: true).first ?? recent(since: .distantPast, hidingSystem: true).first
    }

    func source(bundleID: String) -> OutputSource? {
        current(hidingSystem: false).first { $0.bundleID == bundleID }
            ?? recent(since: .distantPast, hidingSystem: false).first { $0.bundleID == bundleID }
    }

    func pids(for bundleID: String) -> [pid_t] {
        if bundleID.isEmpty {
            return source(bundleID: bundleID).map { [$0.pid] } ?? []
        }

        let playing = records.filter { $0.bundleID == bundleID && $0.stoppedAt == nil }.map(\.pid)
        if !playing.isEmpty { return playing }
        return source(bundleID: bundleID).map { [$0.pid] } ?? []
    }

    mutating func load(from url: URL, now: Date) {
        guard let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([OutputRecord].self, from: data)
        else { return }

        let cutoff = now.addingTimeInterval(-persistHorizon)
        records = decoded.compactMap { record in
            var record = record
            if record.stoppedAt == nil {
                record.stoppedAt = now
            }
            let last = record.stoppedAt ?? record.startedAt
            return last >= cutoff ? record : nil
        }
    }

    func save(to url: URL, now: Date) {
        let cutoff = now.addingTimeInterval(-persistHorizon)
        let payload = records.filter { record in
            (record.stoppedAt ?? record.startedAt) >= cutoff
        }
        guard let data = try? JSONEncoder().encode(payload) else { return }

        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    private func present(_ records: [OutputRecord], hidingSystem: Bool) -> [OutputSource] {
        var grouped: [String: OutputRecord] = [:]
        var order: [String] = []

        for record in records {
            let key = record.bundleID.isEmpty ? "pid:\(record.pid)" : record.bundleID
            if grouped[key] == nil {
                order.append(key)
                grouped[key] = record
                continue
            }

            if record.startedAt > (grouped[key]?.startedAt ?? .distantPast) {
                grouped[key] = record
            }
        }

        return order.compactMap { key in
            guard let record = grouped[key] else { return nil }
            let isSystem = SystemAudioIdentity.isSystem(bundleID: record.bundleID)
            if hidingSystem, isSystem { return nil }
            return OutputSource(
                id: key,
                bundleID: record.bundleID,
                pid: record.pid,
                deviceName: record.deviceName,
                startedAt: record.startedAt,
                stoppedAt: record.stoppedAt,
                isSystem: isSystem
            )
        }
    }

    private mutating func trim() {
        if records.count <= limit { return }
        let overflow = records.count - limit
        var removed = 0
        records.removeAll { record in
            guard removed < overflow, record.stoppedAt != nil else { return false }
            removed += 1
            return true
        }
    }
}
