import SwiftUI

enum DooyouStyle {
    static let surfacePrimary = Color(nsColor: .windowBackgroundColor)
    static let surfaceSecondary = Color(red: 0.93, green: 0.91, blue: 0.87)
    static let surfaceElevated = Color(red: 0.99, green: 0.98, blue: 0.96)
    static let accent = Color(red: 0.82, green: 0.42, blue: 0.27)
    static let info = Color(red: 0.22, green: 0.43, blue: 0.65)
    static let success = Color(red: 0.14, green: 0.65, blue: 0.35)
    static let warning = Color(red: 0.82, green: 0.54, blue: 0.13)
    static let error = Color(red: 0.78, green: 0.30, blue: 0.23)
    static let panelRadius: CGFloat = 8
}

func loadColor(_ pct: Double) -> Color {
    if pct >= 90 { return DooyouStyle.error }
    if pct >= 70 { return DooyouStyle.warning }
    return DooyouStyle.success
}

func pressureWord(_ pct: Double) -> String {
    if pct >= 90 { return "높음" }
    if pct >= 70 { return "주의" }
    return "여유"
}

struct DooyouPanel<Content: View>: View {
    let title: String?
    let action: AnyView?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, action: AnyView? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.action = action
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if title != nil || action != nil {
                HStack(spacing: 8) {
                    if let title {
                        Text(title).font(.headline)
                    }
                    Spacer()
                    if let action {
                        action
                    }
                }
            }
            content
        }
        .padding(12)
        .background(DooyouStyle.surfaceElevated.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: DooyouStyle.panelRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DooyouStyle.panelRadius)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

struct StatusCapsule: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.semibold)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.13), in: Capsule())
    }
}

struct MiniProgressBar: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.09))
                Capsule()
                    .fill(color)
                    .frame(width: max(4, proxy.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 4)
    }
}

struct LoadMetricTile: View {
    let label: String
    let value: String
    let detail: String
    let pct: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(pressureWord(pct))
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(loadColor(pct))
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(loadColor(pct))
                    .monospacedDigit()
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            MiniProgressBar(value: pct / 100, color: loadColor(pct))
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .padding(9)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ResourceChip: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct DashboardStatTile: View {
    let label: String
    let value: String
    let sub: String
    let color: Color
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: systemImage)
                    .font(.caption)
                    .foregroundStyle(color)
                Spacer()
            }
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(sub).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .padding(12)
        .background(DooyouStyle.surfaceElevated.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }
}
