import DeviceActivity
import FamilyControls
import Flutter
import SwiftUI
import UIKit

@available(iOS 16.0, *)
struct AppPickerView: View {
    @State var selection: FamilyActivitySelection
    var onDone: (FamilyActivitySelection) -> Void

    init(initial: FamilyActivitySelection,
         onDone: @escaping (FamilyActivitySelection) -> Void) {
        _selection = State(initialValue: initial)
        self.onDone = onDone
    }

    var body: some View {
        NavigationView {
            FamilyActivityPicker(selection: $selection)
                .navigationTitle("Apps to count")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { onDone(selection) }
                    }
                }
        }
    }
}

@available(iOS 16.0, *)
enum ScreenTimeProbe {
    static let suite = "group.com.screenstreaks.screenstreaks"
    static let activity = DeviceActivityName("streaks.probe")
    static let eventName = DeviceActivityEvent.Name("streaks.probe.threshold")

    /// Resolved at call time — under the UIScene lifecycle there's no window
    /// yet when the engine registers plugins.
    private static var topViewController: UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        var vc = window?.rootViewController
        while let presented = vc?.presentedViewController { vc = presented }
        return vc
    }

    static func register(messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(
            name: "screenstreaks/screentime",
            binaryMessenger: messenger
        )

        channel.setMethodCallHandler { call, result in
            switch call.method {
            case "authorize":
                Task { @MainActor in
                    do {
                        try await AuthorizationCenter.shared
                            .requestAuthorization(for: .individual)
                        result("authorized")
                    } catch {
                        result(FlutterError(code: "denied",
                                            message: "\(error)", details: nil))
                    }
                }

            case "pickApps":
                guard let host = topViewController else {
                    result(FlutterError(code: "no_vc",
                                        message: "No view controller", details: nil))
                    return
                }
                // Seed the picker with what's already chosen, so reopening it
                // shows the current selection rather than a blank sheet.
                restoreSelectionIfNeeded()
                var current = FamilyActivitySelection()
                if let saved = UserDefaults(suiteName: suite)?
                    .data(forKey: "selection"),
                   let decoded = try? JSONDecoder()
                    .decode(FamilyActivitySelection.self, from: saved) {
                    current = decoded
                }
                let picker = AppPickerView(initial: current) { selection in
                    if let data = try? JSONEncoder().encode(selection) {
                        UserDefaults(suiteName: suite)?.set(data, forKey: "selection")
                        // Also keep a copy outside the app group — installs wipe
                        // the shared container but not the app's own defaults.
                        UserDefaults.standard.set(data, forKey: "selection_backup")
                    }
                    host.dismiss(animated: true)
                    let apps = selection.applicationTokens.count
                    let cats = selection.categoryTokens.count
                    // Category-only selections frequently fail to trigger
                    // thresholds — flag it so the UI can nudge the user.
                    let warn = (apps == 0 && cats > 0)
                        ? " — pick individual apps too, categories alone may not count"
                        : ""
                    result("\(apps) apps, \(cats) categories\(warn)")
                }
                host.present(UIHostingController(rootView: picker), animated: true)

            case "startProbe":
                let minutes = (call.arguments as? Int) ?? 2
                // startMonitoring blocks on a system service, so keep it off
                // the main thread or the UI hitches while it registers.
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try start(thresholdMinutes: minutes)
                        DispatchQueue.main.async {
                            result("monitoring — threshold \(minutes)m")
                        }
                    } catch {
                        DispatchQueue.main.async {
                            result(FlutterError(code: "start_failed",
                                                message: "\(error)",
                                                details: nil))
                        }
                    }
                }

            case "appGroupPath":
                // Where Dart should write cached avatar files so WidgetKit
                // can read them — widgets have no network access.
                let url = FileManager.default.containerURL(
                    forSecurityApplicationGroupIdentifier: suite)
                result(url?.path ?? "")

            case "hasSelection":
                restoreSelectionIfNeeded()
                let data = UserDefaults(suiteName: suite)?.data(forKey: "selection")
                result(data != nil)

            case "monitoringSince":
                let d = UserDefaults(suiteName: suite)?
                    .object(forKey: "monitoring_started") as? Date
                result(d?.timeIntervalSince1970 ?? 0)

            case "overTimes":
                // When each recent miss crossed the threshold — a crossing
                // between 2 and 5am is almost certainly a screen left on.
                let defaults = UserDefaults(suiteName: suite)
                var out: [String: Double] = [:]
                for (key, value) in defaults?.dictionaryRepresentation() ?? [:] {
                    guard key.hasPrefix("over_at_"),
                          let date = value as? Date else { continue }
                    out[String(key.dropFirst("over_at_".count))] =
                        date.timeIntervalSince1970
                }
                result(out)

            case "dayState":
                // Where today stands: 0 under, 1 approaching, 2 over, with
                // the time each was reached so the app can say when.
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd"
                f.timeZone = .current
                let key = f.string(from: Date())
                let defaults = UserDefaults(suiteName: suite)
                let warned = defaults?.object(forKey: "warned_at_" + key) as? Date
                let over = defaults?.object(forKey: "over_at_" + key) as? Date
                result([
                    "state": over != nil ? 2 : (warned != nil ? 1 : 0),
                    "warnedAt": warned?.timeIntervalSince1970 ?? 0,
                    "overAt": over?.timeIntervalSince1970 ?? 0,
                ])

            case "authorizeNotifications":
                // The extension posts through UNUserNotificationCenter, so
                // ask there rather than through the Flutter plugin.
                UNUserNotificationCenter.current().requestAuthorization(
                    options: [.alert, .sound, .badge]
                ) { granted, _ in
                    DispatchQueue.main.async { result(granted) }
                }

            case "activeLimit":
                result(UserDefaults(suiteName: suite)?.integer(forKey: "active_limit") ?? 0)

            case "readPartials":
                result(UserDefaults(suiteName: suite)?
                    .stringArray(forKey: "partial_days") ?? [])

            case "clearPartials":
                let days = (call.arguments as? [String]) ?? []
                let defaults = UserDefaults(suiteName: suite)
                var partials = defaults?.stringArray(forKey: "partial_days") ?? []
                partials.removeAll { days.contains($0) }
                defaults?.set(partials, forKey: "partial_days")
                result("cleared \(days.count)")

            case "readPending":
                result(UserDefaults(suiteName: suite)?
                    .dictionary(forKey: "pending_outcomes") ?? [:])

            case "clearPending":
                let days = (call.arguments as? [String]) ?? []
                let defaults = UserDefaults(suiteName: suite)
                var pending = defaults?.dictionary(forKey: "pending_outcomes")
                    as? [String: Bool] ?? [:]
                for day in days { pending.removeValue(forKey: day) }
                defaults?.set(pending, forKey: "pending_outcomes")
                result("cleared \(days.count)")

            case "lastCallback":
                // Newest entry in the extension's log, as epoch seconds.
                // Lets the app spot a monitor that's live but silent.
                let entries = UserDefaults(suiteName: suite)?
                    .stringArray(forKey: "probe_log") ?? []
                let stamp = UserDefaults(suiteName: suite)?
                    .double(forKey: "last_callback_at") ?? 0
                result(entries.isEmpty ? 0 : stamp)

            case "appendLog":
                // Lets Dart write into the same log the extension uses, so
                // failures on the app side are visible in the probe.
                let msg = (call.arguments as? String) ?? ""
                let defaults = UserDefaults(suiteName: suite)
                var entries = defaults?.stringArray(forKey: "probe_log") ?? []
                let f = DateFormatter()
                f.dateFormat = "MM-dd HH:mm:ss"
                entries.insert("\(f.string(from: Date()))  \(msg)", at: 0)
                defaults?.set(Array(entries.prefix(60)), forKey: "probe_log")
                result("logged")

            case "readLog":
                result(UserDefaults(suiteName: suite)?
                    .stringArray(forKey: "probe_log") ?? [])

            case "clearLog":
                UserDefaults(suiteName: suite)?.removeObject(forKey: "probe_log")
                result("cleared")

            case "stop":
                DeviceActivityCenter().stopMonitoring([activity])
                // Clear the stored limit too — the switch and the pill both
                // read it, so leaving it set makes the UI claim it's still on.
                let defaults = UserDefaults(suiteName: suite)
                defaults?.removeObject(forKey: "active_limit")
                defaults?.removeObject(forKey: "monitoring_started")
                result("stopped")

            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    /// Puts the app-group copy back after an install wiped it.
    static func restoreSelectionIfNeeded() {
        let defaults = UserDefaults(suiteName: suite)
        guard defaults?.data(forKey: "selection") == nil,
              let backup = UserDefaults.standard.data(forKey: "selection_backup")
        else { return }
        defaults?.set(backup, forKey: "selection")
    }

    private static func start(thresholdMinutes: Int) throws {
        restoreSelectionIfNeeded()
        var selection = FamilyActivitySelection()
        if let data = UserDefaults(suiteName: suite)?.data(forKey: "selection"),
           let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self,
                                                   from: data) {
            selection = decoded
        }

        // Full day, repeating. Because the interval is already underway when
        // monitoring starts mid-day, usage accrued earlier today counts toward
        // the threshold — which is what we want: if they're already over, say so.
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )

        // includesPastActivity counts usage from the interval start rather
        // than from when monitoring was registered, so starting mid-day picks
        // up the hours already spent. iOS 17.4+.
        let activityEvent: DeviceActivityEvent
        if #available(iOS 17.4, *) {
            activityEvent = DeviceActivityEvent(
                applications: selection.applicationTokens,
                categories: selection.categoryTokens,
                webDomains: selection.webDomainTokens,
                threshold: DateComponents(minute: thresholdMinutes),
                includesPastActivity: true
            )
        } else {
            activityEvent = DeviceActivityEvent(
                applications: selection.applicationTokens,
                categories: selection.categoryTokens,
                webDomains: selection.webDomainTokens,
                threshold: DateComponents(minute: thresholdMinutes)
            )
        }

        let center = DeviceActivityCenter()
        center.stopMonitoring([activity])
        // A second event 30 minutes short of the limit gives us the
        // approaching-limit warning; iOS has no separate warning API.
        let warnMinutes = max(thresholdMinutes - 30, 1)
        let warnEvent = DeviceActivityEvent(
            applications: selection.applicationTokens,
            categories: selection.categoryTokens,
            webDomains: selection.webDomainTokens,
            threshold: DateComponents(minute: warnMinutes)
        )
        try center.startMonitoring(activity, during: schedule, events: [
            eventName: activityEvent,
            DeviceActivityEvent.Name("streaks.probe.warning"): warnEvent,
        ])
        let defaults = UserDefaults(suiteName: suite)
        defaults?.set(thresholdMinutes, forKey: "active_limit")
        // Remember when this interval began so a partial first day isn't
        // recorded as a pass — we can only prove a day we watched in full.
        defaults?.set(Date(), forKey: "monitoring_started")
    }
}
