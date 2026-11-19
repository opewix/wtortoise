import Foundation

/// Команды программы. Общие для приложения и расширения Finder: расширение строит из них меню
/// и зовёт приложение ссылкой `wtortoise://<команда>?path=…`.
enum Command: String, CaseIterable {
    case commit, pull, fetch, push
    case diff, log, status, blame
    case add, revert, rename, remove = "delete"
    case switchBranch = "switch", merge, branch, tag
    case stashSave = "stash", stashPop = "stashpop"
    case clone, initRepo = "init"
    case settings, about

    static let scheme = "wtortoise"

    var title: String {
        switch self {
        case .commit: return L.t("Фиксация…", "Commit...")
        case .pull: return L.t("Получить (Pull)…", "Pull...")
        case .fetch: return L.t("Извлечь (Fetch)…", "Fetch...")
        case .push: return L.t("Отправить (Push)…", "Push...")
        case .diff: return L.t("Сравнить", "Diff")
        case .log: return L.t("Показать журнал", "Show log")
        case .status: return L.t("Проверить изменения", "Check for modifications")
        case .add: return L.t("Добавить…", "Add...")
        case .revert: return L.t("Убрать изменения…", "Revert...")
        case .blame: return L.t("Авторы строк (Blame)", "Blame")
        case .rename: return L.t("Переименовать…", "Rename...")
        case .remove: return L.t("Удалить…", "Delete")
        case .switchBranch: return L.t("Переключить / Извлечь…", "Switch/Checkout...")
        case .merge: return L.t("Слить…", "Merge...")
        case .branch: return L.t("Создать ветку…", "Create Branch...")
        case .tag: return L.t("Создать метку…", "Create Tag...")
        case .stashSave: return L.t("Спрятать изменения…", "Stash changes")
        case .stashPop: return L.t("Достать спрятанное", "Stash Pop")
        case .clone: return L.t("Клонировать…", "Clone...")
        case .initRepo: return L.t("Создать здесь хранилище…", "Create repository here...")
        case .settings: return L.t("Настройки", "Settings")
        case .about: return L.t("О программе", "About")
        }
    }

    var glyph: Glyph {
        switch self {
        case .commit: return .commit
        case .pull: return .pull
        case .fetch: return .fetch
        case .push: return .push
        case .diff: return .diff
        case .log: return .log
        case .status: return .status
        case .add: return .add
        case .revert: return .revert
        case .blame: return .blame
        case .rename: return .rename
        case .remove: return .remove
        case .switchBranch: return .switchBranch
        case .merge: return .merge
        case .branch: return .branch
        case .tag: return .tag
        case .stashSave: return .stash
        case .stashPop: return .stashPop
        case .clone: return .clone
        case .initRepo: return .initRepo
        case .settings: return .settings
        case .about: return .about
        }
    }

    /// Группа «WTortoise» контекстного меню; Pull, Fetch и Commit стоят над ней отдельными пунктами.
    static let submenuGroups: [[Command]] = [
        [.push], [.log, .status, .diff, .blame], [.add, .revert, .rename, .remove],
        [.switchBranch, .merge, .branch, .tag], [.stashSave, .stashPop], [.clone], [.settings, .about],
    ]

    /// Название пункта, стоящего прямо в контекстном меню, а не в группе: с «Git» впереди, как в оригинале.
    var topLevelTitle: String { "Git " + title }

    /// Название для кнопки: без многоточия.
    var plainTitle: String {
        title.replacingOccurrences(of: "...", with: "").replacingOccurrences(of: "…", with: "")
    }

    static func commitTitle(branch: String) -> String {
        L.t("Git: фиксация в «\(branch)»…", "Git Commit -> \"\(branch)\"...")
    }

    /// Номер для NSMenuItem.tag: Finder возвращает расширению копию пункта, от которой остаются
    /// только заголовок и tag.
    var tag: Int { Command.allCases.firstIndex(of: self)! + 1 }

    static func with(tag: Int) -> Command? {
        let all = Command.allCases
        return tag >= 1 && tag <= all.count ? all[tag - 1] : nil
    }

    func url(paths: [String]) -> URL {
        var parts = URLComponents()
        parts.scheme = Command.scheme
        parts.host = rawValue
        parts.queryItems = paths.map { URLQueryItem(name: "path", value: $0) }
        return parts.url!
    }

    /// Обратно: команда и пути из ссылки.
    static func parse(_ url: URL) -> (Command, [String])? {
        guard url.scheme == scheme, let host = url.host, let command = Command(rawValue: host) else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return (command, items.filter { $0.name == "path" }.compactMap(\.value))
    }
}

/// Поиск хранилища по пути — без запуска git, чтобы работало и в песочнице расширения.
enum RepoPath {
    /// Корень рабочей копии: ближайшая папка вверх, где есть `.git` (папка или файл-ссылка).
    static func root(of path: String) -> String? {
        let fm = FileManager.default
        var dir = path
        var isDir: ObjCBool = false
        if !(fm.fileExists(atPath: dir, isDirectory: &isDir) && isDir.boolValue) {
            dir = (dir as NSString).deletingLastPathComponent
        }
        while !dir.isEmpty {
            if fm.fileExists(atPath: dir + "/.git") { return dir }
            if dir == "/" { return nil }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return nil
    }

    /// Папка git для корня: сама `.git` либо та, на которую указывает файл `.git` (worktree, submodule).
    static func gitDir(root: String) -> String {
        let dotGit = root + "/.git"
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: dotGit, isDirectory: &isDir), !isDir.boolValue,
           let text = try? String(contentsOfFile: dotGit, encoding: .utf8), text.hasPrefix("gitdir:") {
            let target = text.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespacesAndNewlines)
            return target.hasPrefix("/") ? target : root + "/" + target
        }
        return dotGit
    }

    /// Текущая ветка из `HEAD`; nil — HEAD отсоединён или не читается.
    static func branch(root: String) -> String? {
        guard let head = try? String(contentsOfFile: gitDir(root: root) + "/HEAD", encoding: .utf8) else { return nil }
        let line = head.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "ref: refs/heads/"
        return line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)) : nil
    }

    static func relative(_ path: String, to root: String) -> String {
        if path == root { return "" }
        return path.hasPrefix(root + "/") ? String(path.dropFirst(root.count + 1)) : path
    }
}
