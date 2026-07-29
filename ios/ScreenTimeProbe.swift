import DeviceActivity
import FamilyControls
import Flutter
import SwiftUI
import UIKit

@available(iOS 16.0, *)
struct AppPickerView: View {
    @State var selection = FamilyActivitySelection()
    var onDone: (FamilyActivitySelection) -> Void

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
                let picker = AppPickerView { selection in
                    if let data = try? JSONEncoder().encode(selection) {
                        UserDefaults(suiteName: suite)?.set(data, forKey: "selection")
                    }
                    host.dismiss(animated: true)
                    result("\(selection.applicationTokens.count) apps, "
                           + "\(selection.categoryTokens.count) categories")
                }
                host.present(UIHostingController(rootView: picker), animated: true)

            case "startProbe":
                let minutes = (call.arguments as? Int) ?? 2
                do {
                    try start(thresholdMinutes: minutes)
                    result("monitoring — threshold \(minutes)m")
                } catch {
                    result(FlutterError(code: "start_failed",
                                        message: "\(error)", details: nil))
                }

            case "readLog":
                result(UserDefaults(suiteName: suite)?
                    .stringArray(forKey: "probe_log") ?? [])

            case "clearLog":
                UserDefaults(suiteName: suite)?.removeObject(forKey: "probe_log")
                result("cleared")

            case "stop":
                DeviceActivityCenter().stopMonitoring([activity])
                result("stopped")

            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private static func start(thresholdMinutes: Int) throws {
        var selection = FamilyActivitySelection()
        if let data = UserDefaults(suiteName: suite)?.data(forKey: "selection"),
           let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self,
                                                   from: data) {
            selection = decoded
        }

        // Start a minute out so earlier usage today can't trigger it — a
        // schedule the system reads as already underway is one documented
        // cause of instant false thresholds.
        let cal = Calendar.current
        let startAt = cal.date(byAdding: .minute, value: 1, to: Date())!

        let schedule = DeviceActivitySchedule(
            intervalStart: cal.dateComponents([.hour, .minute], from: startAt),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: false
        )

        let activityEvent = DeviceActivityEvent(
            applications: selection.applicationTokens,
            categories: selection.categoryTokens,
            webDomains: selection.webDomainTokens,
            threshold: DateComponents(minute: thresholdMinutes)
        )

        let center = DeviceActivityCenter()
        center.stopMonitoring([activity])
        try center.startMonitoring(activity, during: schedule,
                                   events: [eventName: activityEvent])
    }
}
