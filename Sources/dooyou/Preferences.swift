import Foundation
import SwiftUI

enum MascotID: String, CaseIterable, Identifiable, Codable {
    case coton, cat, turtle, whiteDog, blackDog, fox, hamster, penguin, dragon, slime, robot, otter, horse

    var id: String { rawValue }

    static let featured: [MascotID] = [.coton, .cat, .turtle]

    var title: String {
        switch self {
        case .coton: return "두유"
        case .cat: return "고양이"
        case .turtle: return "거북이"
        case .whiteDog: return "하양이"
        case .blackDog: return "까망이"
        case .fox: return "아기 여우"
        case .hamster: return "햄스터"
        case .penguin: return "아기 펭귄"
        case .dragon: return "아기 드래곤"
        case .slime: return "슬라임"
        case .robot: return "미니 로봇"
        case .otter: return "수달"
        case .horse: return "말"
        }
    }

    var systemSymbol: String {
        switch self {
        case .coton: return "pawprint.fill"
        case .cat: return "pawprint.fill"
        case .turtle: return "tortoise.fill"
        case .whiteDog: return "cloud.fill"
        case .blackDog: return "moon.fill"
        case .fox: return "leaf.fill"
        case .hamster: return "circle.grid.2x2.fill"
        case .penguin: return "snowflake"
        case .dragon: return "flame.fill"
        case .slime: return "drop.fill"
        case .robot: return "cpu.fill"
        case .otter: return "water.waves"
        case .horse: return "hare.fill"
        }
    }
}

enum BackgroundThemeID: String, CaseIterable, Identifiable, Codable {
    case automatic, room, forest, playground, park, space

    var id: String { rawValue }

    static let featured: [BackgroundThemeID] = [.automatic, .room, .forest, .space]

    var title: String {
        switch self {
        case .automatic: return "자동"
        case .room: return "방"
        case .forest: return "숲"
        case .playground: return "놀이터"
        case .park: return "공원"
        case .space: return "스페이스"
        }
    }

    var menuLabel: String {
        switch self {
        case .automatic: return "자동"
        case .room: return "웜"
        case .forest: return "그린"
        case .playground: return "팝"
        case .park: return "파크"
        case .space: return "다크"
        }
    }
}

struct AppPreferences: Codable {
    var mascot: MascotID = .coton
    var backgroundTheme: BackgroundThemeID = .automatic
    var onboardingSeen = false
    var monthlySubscriptionUSD: Double? = nil   // ROI 카드 — 옵셔널: 구 preferences.json과 디코드 호환
}

final class PreferencesModel: ObservableObject {
    @Published private(set) var preferences = PreferencesModel.load()
    var didChange: (() -> Void)?

    var mascot: MascotID { preferences.mascot }
    var backgroundTheme: BackgroundThemeID { preferences.backgroundTheme }
    var shouldShowOnboarding: Bool { !preferences.onboardingSeen }

    func setMascot(_ mascot: MascotID) {
        guard MascotID.featured.contains(mascot) else { return }
        preferences.mascot = mascot
        save()
    }

    func setBackgroundTheme(_ theme: BackgroundThemeID) {
        preferences.backgroundTheme = theme
        save()
    }

    func finishOnboarding() {
        preferences.onboardingSeen = true
        save()
    }

    var monthlySubscriptionUSD: Double? { preferences.monthlySubscriptionUSD }

    func setMonthlySubscription(_ usd: Double) {
        preferences.monthlySubscriptionUSD = usd
        save()
    }

    private func save() {
        try? FileManager.default.createDirectory(at: appSupportDirectoryURL(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(preferences) {
            try? data.write(to: preferencesFileURL())
        }
        didChange?()
    }

    private static func load() -> AppPreferences {
        guard let data = try? Data(contentsOf: preferencesFileURL()),
              let prefs = try? JSONDecoder().decode(AppPreferences.self, from: data) else {
            return AppPreferences()
        }
        var clean = prefs
        if !MascotID.featured.contains(clean.mascot) {
            clean.mascot = .coton
        }
        if !BackgroundThemeID.featured.contains(clean.backgroundTheme) {
            clean.backgroundTheme = .automatic
        }
        return clean
    }
}

func appSupportDirectoryURL() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    return base.appendingPathComponent("dooyou", isDirectory: true)
}

private func preferencesFileURL() -> URL {
    appSupportDirectoryURL().appendingPathComponent("preferences.json")
}

struct PreferencesDashboardSection: View {
    @ObservedObject var preferences: PreferencesModel

    var body: some View {
        DooyouPanel("마스코트와 배경") {
            HStack {
                Text("메뉴바에서 보이는 dooyou 아이콘만 가볍게 바꿉니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(preferences.backgroundTheme.title).font(.caption).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(featuredMascots) { mascot in
                    Button {
                        preferences.setMascot(mascot)
                    } label: {
                        VStack(spacing: 5) {
                            MascotPreview(mascot: mascot, background: preferences.backgroundTheme, height: 24)
                                .frame(height: 26)
                            Text(mascot.title).font(.caption2).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(preferences.mascot == mascot ? DooyouStyle.accent.opacity(0.13) : Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(preferences.mascot == mascot ? DooyouStyle.accent.opacity(0.55) : .clear, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                ForEach(BackgroundThemeID.featured) { theme in
                    Button {
                        preferences.setBackgroundTheme(theme)
                    } label: {
                        HStack(spacing: 6) {
                            MascotPreview(mascot: preferences.mascot, background: theme, height: 18)
                                .frame(width: 34, height: 18)
                            Text(theme.menuLabel)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(preferences.backgroundTheme == theme ? DooyouStyle.accent : .secondary)
                }
            }
        }
    }

    private var featuredMascots: [MascotID] {
        MascotID.featured
    }
}

struct MascotPreview: View {
    let mascot: MascotID
    let background: BackgroundThemeID
    let height: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.22)) { timeline in
            let frame = Int(timeline.date.timeIntervalSinceReferenceDate / 0.22) % max(dooyouFrames.count, 1)
            Image(nsImage: dooyouImage(frame, height: height, isSprinting: false, mascot: mascot, background: background))
                .resizable()
                .scaledToFit()
        }
    }
}
