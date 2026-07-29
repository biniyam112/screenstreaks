import DeviceActivity
import Foundation

/// Probe build: every callback is logged to the shared app group so the main
/// app can show exactly when — and whether — iOS fired it.
class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private let defaults = UserDefaults(suiteName: "group.com.screenstreaks.screenstreaks")

    private func log(_ line: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        var entries = defaults?.stringArray(forKey: "probe_log") ?? []
        entries.append("\(f.string(from: Date()))  \(line)")
        defaults?.set(Array(entries.suffix(40)), forKey: "probe_log")
    }

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        log("interval started")
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        log("interval ended")
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name,
                                         activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        log("⚠️ THRESHOLD REACHED — \(event.rawValue)")
    }

    override func eventWillReachThresholdWarning(_ event: DeviceActivityEvent.Name,
                                                 activity: DeviceActivityName) {
        super.eventWillReachThresholdWarning(event, activity: activity)
        log("threshold warning")
    }
}
