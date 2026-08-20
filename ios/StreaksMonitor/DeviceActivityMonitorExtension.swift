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
        defaults?.set(Date().timeIntervalSince1970, forKey: "last_callback_at")
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
        // The overnight watcher shares these callbacks — only the daily
        // monitor should start or end a day.
        guard activity.rawValue == "streaks.probe" else { return }
        log("day started")
        // A DeviceActivityEvent fires once per registration, not once per
        // interval — so after a threshold is hit the next day goes unwatched
        // unless we re-arm it here.
        rearm()
    }

    /// Re-register the threshold event for the interval that just began.
    private func rearm() {
        guard let defaults = defaults else { return }

        // A limit change queued yesterday takes effect now — this is the
        // actual start of the new day, rather than whenever the app is next
        // opened. Clearing it here is what tells Dart it has landed.
        var minutes = defaults.integer(forKey: "active_limit")
        let queued = defaults.integer(forKey: "pending_limit")
        if queued > 0 && queued != minutes {
            minutes = queued
            defaults.set(queued, forKey: "active_limit")
            defaults.removeObject(forKey: "pending_limit")
            log("limit changed to \(queued)m")
        }
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
            // Stamp midnight, not now — a re-arm at interval start covers
            // the whole day, and stamping "now" made the partial guard treat
            // every day as a mid-day start and refuse to record it.
            defaults.set(Calendar.current.startOfDay(for: Date()),
                         forKey: "monitoring_started")
            log("re-armed at \(minutes)m")
        } catch {
            log("re-arm failed: \(error.localizedDescription)")
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard activity.rawValue == "streaks.probe" else { return }
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
        // Covered the whole day if counting began at or before midnight.
        // The midnight re-arm stamps startOfDay, so a normal day passes;
        // only a genuine mid-day start is partial.
        let dayStart = Calendar.current.startOfDay(for: Date())
        if let started = defaults?.object(forKey: "monitoring_started") as? Date,
           started <= dayStart {
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

        // An hour of use between 2 and 5am is a screen left on, not a
        // person — flag the day so the app can offer the sleep pass.
        if event.rawValue == "streaks.overnight.threshold" {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.timeZone = .current
            defaults?.set(true, forKey: "sleep_flag_" + f.string(from: Date()))
            log("overnight use — screen likely left on")
            return
        }

        // The warning event fires 30 minutes short of the limit.
        if event.rawValue == "streaks.probe.warning" {
            log("approaching limit")
            // Remember when, so the app can show where the day stands.
            defaults?.set(Date(), forKey: "warned_at_" + todayKey)
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
        defaults?.set(Date(), forKey: "over_at_" + todayKey)
        log("⚠️ over limit")
        notify("Over your limit", "Today's streak is broken. Fresh start tomorrow.")
    }
}
