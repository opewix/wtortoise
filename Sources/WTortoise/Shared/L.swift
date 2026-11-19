import Foundation

/// Две строки интерфейса — русская и английская. По умолчанию английская, с названиями как в TortoiseGit;
/// русский включается в настройках (ключ `language` = `ru`).
enum L {
    static let languageKey = "language"

    static let isRussian: Bool = {
        if let value = UserDefaults.standard.string(forKey: languageKey) { return value == "ru" }
        // Расширение Finder живёт в песочнице со своими настройками — выбор языка читает из файла настроек приложения.
        if let entry = getpwuid(getuid()), let home = entry.pointee.pw_dir {
            let file = String(cString: home) + "/Library/Preferences/dev.oleg.wtortoise.plist"
            if let value = NSDictionary(contentsOfFile: file)?[languageKey] as? String { return value == "ru" }
        }
        return false
    }()

    static func t(_ ru: String, _ en: String) -> String {
        isRussian ? ru : en
    }
}
