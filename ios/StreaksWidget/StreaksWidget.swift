import WidgetKit
import SwiftUI

extension Color {
    /// Mirrors AppColors in lib/colors.dart — keep in sync by hand.
    /// Brand hues read well on both backgrounds, so only the neutrals swap.
    static let brandPrimary = Color(red: 0.063, green: 0.725, blue: 0.506) // #10B981
    static let brandAccent  = Color(red: 0.984, green: 0.549, blue: 0.235) // #FB8C3C

    static let surfaceDark  = Color(red: 0.086, green: 0.086, blue: 0.098) // #161619
    static let surfaceLight = Color(red: 1.0,   green: 1.0,   blue: 1.0)   // #FFFFFF
    static let textDark     = Color(red: 0.957, green: 0.957, blue: 0.965) // #F4F4F6
    static let textLight    = Color(red: 0.086, green: 0.086, blue: 0.102) // #16161A
}

/// "6 people · under 4h" — the supporting line under the group name.
func footerDetail(_ g: GroupInfo) -> String {
    var parts: [String] = []
    if let m = g.members, m > 0 { parts.append("\(m) people") }
    if g.limit > 0 { parts.append("under " + formatLimit(g.limit)) }
    return parts.joined(separator: " · ")
}

func formatLimit(_ minutes: Int) -> String {
    let h = minutes / 60, m = minutes % 60
    if h == 0 { return "\(m)m" }
    return m == 0 ? "\(h)h" : "\(h)h\(String(format: "%02d", m))"
}

/// Names longer than the row can hold collapse to initials — "Hernando
/// Sierra" becomes "H.S." rather than being cut mid-word.
func shortName(_ name: String, max: Int) -> String {
    if name.count <= max { return name }
    let parts = name.split(separator: " ").filter { !$0.isEmpty }
    if parts.isEmpty { return name }
    return parts.prefix(2)
        .map { String($0.prefix(1)).uppercased() }
        .joined()
}

struct Friend: Codable, Identifiable {
    let name: String
    let streak: Int
    let isMe: Bool
    let limit: Int?
    let photo: String?
    var id: String { name }
}

struct GroupInfo: Codable {
    let name: String?
    let streak: Int
    let limit: Int
    let members: Int?
}

struct StreakEntry: TimelineEntry {
    let date: Date
    let friends: [Friend]
    let group: GroupInfo?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> StreakEntry {
        StreakEntry(
            date: Date(),
            friends: [
                Friend(name: "You", streak: 7, isMe: true, limit: 330, photo: nil),
                Friend(name: "Sam", streak: 5, isMe: false, limit: 240, photo: nil),
                Friend(name: "Ada", streak: 3, isMe: false, limit: 180, photo: nil),
            ],
            group: GroupInfo(name: "Work", streak: 12, limit: 180, members: 5)
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (StreakEntry) -> ()) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakEntry>) -> ()) {
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        completion(Timeline(entries: [loadEntry()], policy: .after(next)))
    }

    private func loadEntry() -> StreakEntry {
        let defaults = UserDefaults(suiteName: "group.com.screenstreaks.screenstreaks")

        var friends: [Friend] = []
        if let json = defaults?.string(forKey: "leaderboard"),
           let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([Friend].self, from: data) {
            friends = decoded
        }

        var group: GroupInfo? = nil
        if let json = defaults?.string(forKey: "group"),
           let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(GroupInfo.self, from: data) {
            group = decoded
        }

        return StreakEntry(date: Date(), friends: friends, group: group)
    }
}

/// Cached photo from the app group, or coloured initials as a fallback.
struct WidgetAvatar: View {
    let friend: Friend
    let size: CGFloat
    let text: Color

    private var initials: String {
        let parts = friend.name.split(separator: " ")
        if parts.isEmpty { return "?" }
        if parts.count == 1 { return String(parts[0].prefix(1)).uppercased() }
        return (String(parts[0].prefix(1)) + String(parts[parts.count - 1].prefix(1)))
            .uppercased()
    }

    private var image: UIImage? {
        guard let name = friend.photo,
              let dir = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier:
                    "group.com.screenstreaks.screenstreaks")
        else { return nil }
        return UIImage(contentsOfFile: dir.appendingPathComponent(name).path)
    }

    var body: some View {
        Group {
            if let img = image {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Text(initials)
                    .font(.system(size: size * 0.36, weight: .bold))
                    .foregroundStyle(friend.isMe ? Color.brandPrimary
                                                 : text.opacity(0.6))
            }
        }
        .frame(width: size, height: size)
        .background(text.opacity(0.1))
        .clipShape(Circle())
    }
}

struct StreaksWidgetEntryView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.widgetFamily) var family
    var entry: StreakEntry

    var isDark: Bool { colorScheme == .dark }
    var text: Color { isDark ? .textDark : .textLight }

    /// Medium is wide enough for a second column of ranks 4-6.
    var isWide: Bool { family != .systemSmall }
    var capacity: Int { isWide ? 6 : 3 }

    /// Longest name the row can hold before it crowds the columns.
    var maxNameChars: Int { isWide ? 13 : 7 }

    func row(_ i: Int, _ f: Friend) -> some View {
        HStack(spacing: 0) {
            WidgetAvatar(friend: f, size: 24, text: text)

            Text(f.name)
                .font(.system(size: 13, weight: f.isMe ? .heavy : .medium))
                .foregroundStyle(f.isMe ? Color.brandPrimary : text)
                .lineLimit(1)
                .padding(.leading, 8)

            Spacer(minLength: 4)

            // Fixed columns so the streak numbers line up whatever the
            // name length.
            if let l = f.limit, l > 0 {
                Text(formatLimit(l))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(text.opacity(0.38))
                    .frame(width: 32, alignment: .trailing)
            } else {
                Spacer().frame(width: 32)
            }

            Text("\(f.streak)")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(text)
                .frame(width: 18, alignment: .trailing)

            Image(systemName: "flame.fill")
                .font(.system(size: 10))
                .foregroundStyle(f.streak > 0 ? Color.brandAccent
                                              : text.opacity(0.3))
                .padding(.leading, 3)
        }
    }

    var body: some View {
        let shown = Array(entry.friends.prefix(capacity).enumerated())
        let left = shown.filter { $0.offset < 3 }
        let right = shown.filter { $0.offset >= 3 }

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.brandAccent)
                Text("DAYS UNDR")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(text.opacity(0.55))
                    .tracking(0.8)
            }

            if entry.friends.isEmpty {
                Spacer()
                Text("Open the app to sync")
                    .font(.caption2)
                    .foregroundStyle(text.opacity(0.5))
                Spacer()
            } else {
                Spacer(minLength: 8)

                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 11) {
                        ForEach(left, id: \.element.id) { i, f in row(i, f) }
                    }
                    .frame(maxWidth: .infinity)

                    if isWide && !right.isEmpty {
                        VStack(alignment: .leading, spacing: 11) {
                            ForEach(right, id: \.element.id) { i, f in row(i, f) }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                Spacer(minLength: 8)

                Rectangle()
                    .fill(text.opacity(0.12))
                    .frame(height: 1)

                Spacer(minLength: 8)

                if let g = entry.group {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text((g.name ?? "GROUP"))
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(text.opacity(0.85))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)

                            Spacer(minLength: 4)

                            if g.limit > 0 {
                                Text(formatLimit(g.limit))
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(text.opacity(0.38))
                                    .padding(.trailing, 5)
                                Text("\(g.streak)")
                                    .font(.system(size: 13, weight: .heavy))
                                    .foregroundStyle(Color.brandPrimary)
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(g.streak > 0 ? Color.brandAccent
                                                                  : text.opacity(0.3))
                            } else {
                                Image(systemName: "nosign")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(text.opacity(0.35))
                            }
                        }

                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(text.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
}

/// Background that follows the system appearance.
struct ThemedBackground: View {
    @Environment(\.colorScheme) var colorScheme
    var body: some View {
        (colorScheme == .dark ? Color.surfaceDark : Color.surfaceLight)
    }
}

struct StreaksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StreaksWidget", provider: Provider()) { entry in
            StreaksWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) { ThemedBackground() }
        }
        .configurationDisplayName("Undr")
        .description("Your group's streak and the top three.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
