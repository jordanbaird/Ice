import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    static let setupCompletedKey = "InitialLanguageSelectionCompleted"

    static var hasCompletedSetup: Bool {
        UserDefaults.standard.bool(forKey: setupCompletedKey)
    }

    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"
    case french = "fr"
    case german = "de"
    case spanish = "es"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: String(localized: "Follow System")
        case .simplifiedChinese: "简体中文"
        case .english: "English"
        case .traditionalChinese: "繁體中文"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .french: "Français"
        case .german: "Deutsch"
        case .spanish: "Español"
        }
    }

    var resolvedIdentifier: String {
        guard self == .system else { return rawValue }
        let languages = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String]
        let supported = Self.allCases.filter { $0 != .system }.map(\.rawValue)
        return Bundle.preferredLocalizations(from: supported, forPreferences: languages ?? Locale.preferredLanguages).first ?? "en"
    }

    // 首次设置时预览所选语言，不提前写入用户设置。
    var previewBundle: Bundle {
        guard let path = Bundle.main.path(forResource: resolvedIdentifier, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .main }
        return bundle
    }

    static func current(in defaults: UserDefaults = .standard) -> AppLanguage {
        guard let identifier = defaults.string(forKey: "IceLanguage") else {
            return .system
        }
        return AppLanguage(rawValue: identifier) ?? .system
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: "IceLanguage")
        // 仅修改本应用的语言，跟随系统时移除覆盖值。
        if self == .system {
            defaults.removeObject(forKey: "AppleLanguages")
        } else {
            defaults.set([rawValue], forKey: "AppleLanguages")
        }
    }
}
