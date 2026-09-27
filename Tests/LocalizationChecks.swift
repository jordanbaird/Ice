import Foundation

// 使用内存存储，测试不会改动用户的应用设置。
private final class MemoryDefaults: UserDefaults {
    var values: [String: Any] = [:]

    override func object(forKey defaultName: String) -> Any? {
        values[defaultName]
    }

    override func string(forKey defaultName: String) -> String? {
        values[defaultName] as? String
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        values[defaultName] = value
    }

    override func removeObject(forKey defaultName: String) {
        values.removeValue(forKey: defaultName)
    }
}

@main
struct LocalizationChecks {
    static func main() throws {
        let defaults = MemoryDefaults()
        defaults.values["ShowIceIcon"] = false
        precondition(AppLanguage.current(in: defaults) == .system)

        AppLanguage.simplifiedChinese.save(to: defaults)
        precondition(AppLanguage.current(in: defaults) == .simplifiedChinese)
        precondition(defaults.values["AppleLanguages"] as? [String] == ["zh-Hans"])

        AppLanguage.english.save(to: defaults)
        precondition(AppLanguage.current(in: defaults) == .english)
        precondition(defaults.values["AppleLanguages"] as? [String] == ["en"])

        let restored = MemoryDefaults()
        restored.values = defaults.values
        precondition(AppLanguage.current(in: restored) == .english)

        AppLanguage.system.save(to: defaults)
        precondition(AppLanguage.current(in: defaults) == .system)
        precondition(defaults.values["AppleLanguages"] == nil)
        precondition(defaults.values["ShowIceIcon"] as? Bool == false)

        defaults.set("invalid", forKey: "IceLanguage")
        precondition(AppLanguage.current(in: defaults) == .system)
        precondition(Set(AppLanguage.allCases.map(\.rawValue)).count == AppLanguage.allCases.count)

        let resources = URL(fileURLWithPath: CommandLine.arguments[1])
        let chinese = Bundle(url: resources.appendingPathComponent("zh-Hans.lproj"))!
        let english = Bundle(url: resources.appendingPathComponent("en.lproj"))!
        precondition(String(localized: "Language", bundle: chinese) == "语言")
        precondition(String(localized: "Language", bundle: english) == "Language")
        precondition(String(localized: "Follow System", bundle: chinese) == "跟随系统")

        let section = String(localized: "Hidden", bundle: chinese)
        precondition(String(localized: "Show the \(section) Section", bundle: chinese) == "显示隐藏区域")
        let seconds = "0.5"
        precondition(String(localized: "\(seconds) seconds", bundle: chinese) == "0.5 秒")
        let appName = "Example App"
        precondition(String(localized: "Not enough room to show \"\(appName)\"", bundle: chinese) == "没有足够的空间显示“Example App”")
        print("通过：语言选择、设置恢复、系统语言回退、中英文资源加载及动态文本。")
    }
}
