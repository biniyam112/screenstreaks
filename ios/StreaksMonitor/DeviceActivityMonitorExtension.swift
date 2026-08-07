import DeviceActivity
import FamilyControls
import Foundation
import UserNotifications

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
        // A DeviceActivityEvent fires once per registration, not once per
        // interval — so after a threshold is hit the next day goes unwatched
        // unless we re-arm it here.
        rearm()
    }

    /// Re-register the threshold event for the interval that just began.
    private func rearm() {
        guard let defaults = defaults else { return }
        let minutes = defaults.integer(forKey: "active_limit")
        guard minutes > 0 else { return }

        var selection = FamilyActivitySelection()
        if let data = defaults.data(forKey: "selection"),
           let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self,
                                                   from: data) {
            selection = decoded
        }
        guard !selection.applicationTokens.isEmpty
                || !selection.categoryTokens.isEmpty
                || !selection.webDomainTokens.isEmpty else { return }

        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        let event = DeviceActivityEvent(
            applications: selection.applicationTokens,
            categories: selection.categoryTokens,
            webDomains: selection.webDomainTokens,
            threshold: DateComponents(minute: minutes)
        )

        let center = DeviceActivityCenter()
        do {
            // Re-register the warning too, or approaching-limit alerts stop
            // after the first midnight.
            let warnEvent = DeviceActivityEvent(
                applications: selection.applicationTokens,
                categories: selection.categoryTokens,
                webDomains: selection.webDomainTokens,
                threshold: DateComponents(minute: max(minutes - 30, 1))
            )
            try center.startMonitoring(
                DeviceActivityName("streaks.probe"),
                during: schedule,
                events: [
                    DeviceActivityEvent.Name("streaks.probe.threshold"): event,
                    DeviceActivityEvent.Name("streaks.probe.warning"): warnEvent,
                ]
            )
            log("re-armed at \(minutes)m")
        } catch {
            log("re-arm failed: \(error.localizedDescription)")
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        // stopMonitoring() also triggers this callback, so ignore any end that
        // arrives before the day is genuinely over.
        let hour = Calendar.current.component(.hour, from: Date())
        guard hour >= 23 || hour == 0 else {
            log("interval ended early (ignored)")
            return
        }
        // Only claim a pass for a day we watched from the beginning. If
        // monitoring started mid-day we never saw the earlier hours, so the
        // absence of a threshold proves nothing.
        if let started = defaults?.object(forKey: "monitoring_started") as? Date,
           !Calendar.current.isDate(started, inSameDayAs: Date()) {
            let lost = defaults?.stringArray(forKey: "lost_days") ?? []
            let pending = defaults?.dictionary(forKey: "pending_outcomes")
                as? [String: Bool] ?? [:]
            if lost.contains(todayKey) || pending[todayKey] == false {
                log("day ended — already over, pass ignored")
            } else {
                record(true, for: todayKey)
                log("day ended — under limit")
            }
        } else {
            // Monitoring began mid-day, so we can't judge it. Record it as
            // partial rather than nothing, so the user sees the app working.
            var partials = defaults?.stringArray(forKey: "partial_days") ?? []
            if !partials.contains(todayKey) { partials.append(todayKey) }
            defaults?.set(partials, forKey: "partial_days")
            log("day ended — partial, not judged")
        }
    }

    private func notify(_ title: String, _ body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name,
                                         activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)

        // The warning event fires 30 minutes short of the limit.
        if event.rawValue == "streaks.probe.warning" {
            log("approaching limit")
            notify("Half an hour left",
                   "You're 30 minutes from your limit today.")
            return
        }
        record(false, for: todayKey)
        // Remember it independently of the drain queue — pending_outcomes is
        // cleared once the app reads it, and the day-end guard needs to know
        // the day was already lost hours later.
        var lost = defaults?.stringArray(forKey: "lost_days") ?? []
        if !lost.contains(todayKey) { lost.append(todayKey) }
        defaults?.set(Array(lost.suffix(30)), forKey: "lost_days")
        log("⚠️ over limit")
        notify("Over your limit", "Today's streak is broken. Fresh start tomorrow.")
    }
}
