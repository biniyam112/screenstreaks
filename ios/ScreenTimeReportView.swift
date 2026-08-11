import DeviceActivity
import Flutter
import SwiftUI
import UIKit

@available(iOS 16.0, *)
extension DeviceActivityReport.Context {
    /// Must match the context the report extension declares, or iOS has no
    /// scene to render. The extension defines its own copy — they're separate
    /// targets and can't share the declaration.
    static let totalActivity = Self("Total Activity")
}

/// Bridges the DeviceActivityReport SwiftUI view into Flutter. The numbers
/// live inside a sandboxed extension — we can render them but never read them.
@available(iOS 16.0, *)
class ScreenTimeReportFactory: NSObject, FlutterPlatformViewFactory {
    func create(withFrame frame: CGRect,
                viewIdentifier viewId: Int64,
                arguments args: Any?) -> FlutterPlatformView {
        ScreenTimeReportPlatformView(frame: frame)
    }
}

@available(iOS 16.0, *)
class ScreenTimeReportPlatformView: NSObject, FlutterPlatformView {
    private let controller: UIHostingController<TodayReport>

    init(frame: CGRect) {
        controller = UIHostingController(rootView: TodayReport())
        controller.view.frame = frame
        controller.view.backgroundColor = .clear
        super.init()
    }

    func view() -> UIView { controller.view }
}

@available(iOS 16.0, *)
struct TodayReport: View {
    // Midnight to now — the same window the threshold counts over.
    private var filter: DeviceActivityFilter {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        return DeviceActivityFilter(
            segment: .daily(during: DateInterval(start: start, end: Date())),
            users: .all,
            devices: .init([.iPhone])
        )
    }

    var body: some View {
        DeviceActivityReport(.totalActivity, filter: filter)
            .frame(maxWidth: .infinity)
    }
}
