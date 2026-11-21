import AppKit
import FinderSync

/// Главное окно — когда программу открыли саму, а не командой из Finder: папка и кнопки команд.
final class HomeController: ToolWindow, NSTextFieldDelegate {
    private let path = UI.field(width: 420)
    private let state = UI.label("", color: .secondaryLabelColor)
    private let extensionState = UI.label("")

    static func show(path: String?) {
        if let existing = ToolWindow.live.first(where: { $0 is HomeController }) {
            existing.showWindow(nil)
            if let path { (existing as? HomeController)?.setPath(path) }
            return
        }
        HomeController(path: path).present()
    }

    private init(path initial: String?) {
        super.init(title: "WTortoise", size: NSSize(width: 600, height: 400), resizable: false)
        path.stringValue = initial ?? UserDefaults.standard.string(forKey: "lastPath") ?? ""
        path.placeholderString = L.t("Папка рабочей копии", "Working tree folder")
        path.delegate = self
        let browse = ClosureButton(L.t("Обзор…", "Browse...")) { [weak self] in self?.browse() }

        let groups: [[Command]] = [
            [.sync, .commit, .pull, .fetch, .push],
            [.log, .status, .diff, .blame],
            [.add, .revert, .rename, .remove],
            [.switchBranch, .merge, .branch, .tag],
            [.stashSave, .stashPop, .clone, .initRepo],
            [.settings, .about],
        ]
        let grid = NSGridView(numberOfColumns: 4, rows: 0)
        grid.rowSpacing = 6
        grid.columnSpacing = 6
        grid.translatesAutoresizingMaskIntoConstraints = false
        for group in groups {
            grid.addRow(with: group.map { command in
                let button = ClosureButton(command.plainTitle) { [weak self] in self?.run(command) }
                button.image = command.glyph.image()
                button.imagePosition = .imageLeading
                button.alignment = .left
                button.widthAnchor.constraint(equalToConstant: 168).isActive = true
                return button
            })
        }

        let extensionButton = ClosureButton(L.t("Расширения Finder…", "Finder Extensions...")) {
            FIFinderSyncController.showExtensionManagementInterface()
        }
        let content = UI.column([
            UI.row([UI.label(L.t("Папка:", "Folder:")), path, browse]), state, grid,
            UI.row([extensionState, extensionButton]),
        ], spacing: 10)
        install(content, buttons: [closeButton])
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func setPath(_ value: String) {
        path.stringValue = value
        refresh()
    }

    func controlTextDidChange(_ obj: Notification) { refresh() }

    private var current: String {
        (path.stringValue.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
    }

    private func refresh() {
        if current.isEmpty {
            state.stringValue = L.t("Выберите папку — или вызывайте команды правой кнопкой в Finder.",
                                    "Choose a folder — or use the right-click menu in Finder.")
        } else if let repo = Git.root(of: current) {
            state.stringValue = L.t("Рабочая копия: \(UI.short(repo)), ветка «\(RepoPath.branch(root: repo) ?? "HEAD")»",
                                    "Working tree: \(UI.short(repo)), branch “\(RepoPath.branch(root: repo) ?? "HEAD")”")
        } else {
            state.stringValue = L.t("Здесь нет хранилища Git: доступны «Клонировать» и «Создать здесь хранилище».",
                                    "No Git repository here: Clone and Create repository are available.")
        }
        extensionState.stringValue = FIFinderSyncController.isExtensionEnabled
            ? L.t("Меню и значки в Finder включены.", "The Finder menu and badges are on.")
            : L.t("Меню в Finder выключено — включите расширение WTortoise:", "The Finder menu is off — enable the WTortoise extension:")
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if !current.isEmpty { panel.directoryURL = URL(fileURLWithPath: current) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setPath(url.path)
    }

    private func run(_ command: Command) {
        let needsPath = ![.settings, .about].contains(command)
        if needsPath && current.isEmpty { return browse() }
        if !current.isEmpty { UserDefaults.standard.set(current, forKey: "lastPath") }
        Dispatcher.run(command, paths: current.isEmpty ? [] : [current])
    }
}

/// Настройки: путь к git и подпись автора.
final class SettingsController: ToolWindow {
    private let gitPath = UI.field(Settings.gitPath, placeholder: Git.detected, width: 320)
    private let name = UI.field(Git.config("user.name"), width: 320)
    private let email = UI.field(Git.config("user.email"), width: 320)
    private let language = UI.popup(["English", "Русский"], selected: L.isRussian ? "Русский" : "English")

    static func show() {
        if let existing = ToolWindow.live.first(where: { $0 is SettingsController }) { return existing.showWindow(nil) }
        SettingsController().present()
    }

    private init() {
        super.init(title: L.t("Настройки - WTortoise", "Settings - WTortoise"), size: NSSize(width: 480, height: 220), resizable: false)
        let form = Form()
        form.section("Git")
        form.row(L.t("Путь к git:", "Git executable:"), gitPath)
        form.section(L.t("Автор фиксаций (общая настройка git)", "Commit author (global git config)"))
        form.row(L.t("Имя:", "Name:"), name)
        form.row("Email:", email)
        form.section(L.t("Язык", "Language"))
        form.row(L.t("Язык окон и меню:", "Language:"), language)
        form.wide(UI.label(L.t("Смена языка действует после перезапуска программы.", "A language change takes effect after the app is restarted."), color: .secondaryLabelColor))
        install(form.view, buttons: [ClosureButton("OK", key: "\r") { [weak self] in self?.save() }, cancelButton])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func save() {
        let custom = (gitPath.stringValue.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
        if !custom.isEmpty && !FileManager.default.isExecutableFile(atPath: custom) {
            return UI.alert(L.t("По этому пути нет исполняемого файла git.", "There is no git executable at this path."), info: custom)
        }
        Settings.gitPath = custom
        UserDefaults.standard.set(language.indexOfSelectedItem == 1 ? "ru" : "en", forKey: L.languageKey)
        for (key, field, old) in [("user.name", name, Git.config("user.name")), ("user.email", email, Git.config("user.email"))] {
            let value = field.stringValue.trimmingCharacters(in: .whitespaces)
            // Пустое поле не стирает настройку: её могли задать не здесь.
            if !value.isEmpty && value != old { Git.run(["config", "--global", key, value], in: NSHomeDirectory()) }
        }
        close()
    }
}
