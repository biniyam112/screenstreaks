import DeviceActivity
import Foundation

/// Writes each day's outcome to the shared app group. The Flutter app drains
/// these on launch and turns them into check-ins.
class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private let defaults = UserDefaults(suiteName: "group.com.screenstreaks.screenstreaks")

    private var todayKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: Date())
    }

    private func log(_ line: String) {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        var entries = defaults?.stringArray(forKey: "probe_log") ?? []
        entries.append("\(f.string(from: Date()))  \(line)")
        defaults?.set(Array(entries.suffix(40)), forKey: "probe_log")
    }

    /// A miss is final — once they're over for the day it can't become a pass.
    private func record(_ limitMet: Bool, for day: String) {
        var pending = defaults?.dictionary(forKey: "pending_outcomes") as? [String: Bool] ?? [:]
        if pending[day] == false { return }
        pending[day] = limitMet
        defaults?.set(pending, forKey: "pending_outcomes")
    }

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        log("day started")
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        record(true, for: todayKey)
        log("day ended — under limit")
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name,
                                         activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        record(false, for: todayKey)
        log("⚠️ over limit")
    }
}
