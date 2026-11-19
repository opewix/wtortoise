import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var launched = false
    private var pending: [URL] = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Окна в духе Windows — светлые при любой теме системы.
        NSApp.appearance = NSAppearance(named: .aqua)
        NSApp.mainMenu = Menus.build()
    }

    /// Ссылки `wtortoise://команда?path=…` от расширения Finder и папки, брошенные на значок.
    func application(_ application: NSApplication, open urls: [URL]) {
        if launched { urls.forEach(handle) } else { pending += urls }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        launched = true
        if let directory = Snapshot.directory {
            Snapshot.run(into: directory, path: argument("-path") ?? FileManager.default.currentDirectoryPath)
            return
        }
        let urls = pending
        pending = []
        urls.forEach(handle)
        if let name = argument("-command"), let command = Command(rawValue: name) {
            Dispatcher.run(command, paths: arguments("-path"))
        }
        // Команда могла закончиться сообщением без окна — тогда показываем главное окно, а не висим пустыми.
        if ToolWindow.live.isEmpty { HomeController.show(path: arguments("-path").first) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { HomeController.show(path: nil) }
        return true
    }

    private func handle(_ url: URL) {
        if let (command, paths) = Command.parse(url) {
            Dispatcher.run(command, paths: paths)
        } else if url.isFileURL {
            HomeController.show(path: url.path)
        }
    }

    private func arguments(_ key: String) -> [String] {
        let args = CommandLine.arguments
        return args.indices.filter { args[$0] == key && $0 + 1 < args.count }.map { args[$0 + 1] }
    }

    private func argument(_ key: String) -> String? { arguments(key).first }
}

/// Запуск команды для путей: находит хранилище и открывает нужное окно.
enum Dispatcher {
    static func run(_ command: Command, paths rawPaths: [String]) {
        let paths = rawPaths.map(Git.real)
        let target = paths.first ?? NSHomeDirectory()
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: target, isDirectory: &isDir)
        let dir = exists && isDir.boolValue ? target : (target as NSString).deletingLastPathComponent

        switch command {
        case .settings: return SettingsController.show()
        case .about: return About.show()
        case .clone: return CloneDialog(parent: dir).present()
        case .initRepo: return createRepository(in: dir)
        default: break
        }

        guard let repo = Git.root(of: target) else {
            return UI.alert(L.t("Это не рабочая копия Git.", "This is not a Git working tree."), info: UI.short(target))
        }
        // Пути относительно корня; сам корень — «всё хранилище».
        let specs = paths.map { RepoPath.relative($0, to: repo) }.filter { !$0.isEmpty }
        let whole = specs.count < paths.count || paths.isEmpty

        switch command {
        case .commit: CommitController(repo: repo, specs: whole ? [] : specs).present()
        case .status: StatusController(repo: repo, specs: whole ? [] : specs).present()
        case .log: LogController(repo: repo, specs: whole ? [] : specs).present()
        case .add: FilePickController(repo: repo, specs: whole ? [] : specs, mode: .add).present()
        case .revert: FilePickController(repo: repo, specs: whole ? [] : specs, mode: .revert).present()
        case .diff:
            let changes = Git.status(repo, specs: whole ? [] : specs)
            if !whole, specs.count == 1, !isDir.boolValue {
                if let change = changes.first {
                    DiffController.openWorking(repo: repo, file: change)
                } else {
                    UI.alert(L.t("Файл не изменён.", "The file has no changes."), info: specs[0], style: .informational)
                }
            } else {
                StatusController(repo: repo, specs: whole ? [] : specs).present()
            }
        case .blame:
            guard !whole, specs.count == 1, !isDir.boolValue else {
                return UI.alert(L.t("Авторы строк показываются для одного файла.", "Blame works on a single file."))
            }
            BlameController.open(repo: repo, path: specs[0])
        case .rename:
            guard !whole, specs.count == 1 else {
                return UI.alert(L.t("Выберите один файл или папку внутри рабочей копии.", "Select a single file or folder inside the working tree."))
            }
            RenameDialog(repo: repo, path: specs[0]).present()
        case .remove:
            guard !whole else {
                return UI.alert(L.t("Выберите файлы или папки внутри рабочей копии.", "Select files or folders inside the working tree."))
            }
            RemoveDialog(repo: repo, paths: specs).present()
        case .push: PushDialog(repo: repo).present()
        case .pull: PullDialog(repo: repo).present()
        case .fetch: FetchDialog(repo: repo).present()
        case .switchBranch: SwitchDialog(repo: repo).present()
        case .merge: MergeDialog(repo: repo).present()
        case .branch: BranchDialog(repo: repo).present()
        case .tag: TagDialog(repo: repo).present()
        case .stashSave: StashDialog(repo: repo).present()
        case .stashPop:
            ProgressController.run(title: L.t("Достать спрятанное", "Stash Pop"), dir: repo, steps: [["stash", "pop"]])
        case .settings, .about, .clone, .initRepo: break
        }
    }

    private static func createRepository(in dir: String) {
        if let existing = Git.root(of: dir), existing == dir {
            return UI.alert(L.t("Здесь уже есть хранилище Git.", "There is already a Git repository here."), info: UI.short(dir))
        }
        guard UI.confirm(L.t("Создать хранилище Git в этой папке?", "Create a Git repository in this folder?"),
                         info: UI.short(dir), ok: L.t("Создать", "Create")) else { return }
        ProgressController.run(title: L.t("Создание хранилища", "Create repository"), dir: dir, steps: [["init"]])
    }
}

/// Вопрос от git или ssh: пароль, фраза ключа, подтверждение узла.
enum Askpass {
    static func run(prompt: String) -> Never {
        app.setActivationPolicy(.accessory)
        let lower = prompt.lowercased()
        let alert = NSAlert()
        alert.messageText = "WTortoise"
        alert.informativeText = prompt
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: L.t("Отмена", "Cancel"))
        // «Вы уверены, что хотите подключиться (yes/no)?» — ответ словом, а не тайный ввод.
        let secret = !(lower.contains("yes/no") || lower.contains("username"))
        let field: NSTextField = secret ? NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
                                        : NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        app.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { exit(1) }
        print(field.stringValue)
        exit(0)
    }
}

enum About {
    static func show() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let git = Git.run(["--version"], in: NSHomeDirectory()).trimmed
        let alert = NSAlert()
        alert.icon = Glyph.app.image(64)
        alert.messageText = "WTortoise \(version)"
        alert.informativeText = L.t(
            "Git из контекстного меню Finder, в духе TortoiseGit.\n\n\(git)\n\(Git.executable)\n\nНезависимый проект, не связан с TortoiseGit.",
            "Git from the Finder context menu, in the spirit of TortoiseGit.\n\n\(git)\n\(Git.executable)\n\nAn independent project, not affiliated with TortoiseGit.")
        alert.runModal()
    }
}
