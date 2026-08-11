import SwiftUI

struct TotalActivityView: View {
    let totalActivity: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("TODAY, PER SCREEN TIME")
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Text(totalActivity)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
