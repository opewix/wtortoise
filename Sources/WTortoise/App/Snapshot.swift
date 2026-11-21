import AppKit

/// `WTortoise -snapshot <папка> -path <рабочая копия>`: рисует окна программы в PNG и выходит.
/// Для README и проверки вида без разрешения на запись экрана.
enum Snapshot {
    static var directory: String? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "-snapshot"), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    static var active: Bool { directory != nil }

    static func run(into directory: String, path: String) {
        guard let repo = Git.root(of: path) else {
            print("Not a git working tree: \(path)")
            exit(1)
        }
        var windows: [(String, ToolWindow)] = []
        func add(_ name: String, _ window: ToolWindow) {
            window.present()
            windows.append((name, window))
        }
        add("commit", CommitController(repo: repo, specs: []))
        add("log", LogController(repo: repo, specs: []))
        add("status", StatusController(repo: repo, specs: []))
        add("revert", FilePickController(repo: repo, specs: [], mode: .revert))
        add("reset", ResetDialog(repo: repo))
        add("refbrowse", RefBrowserController(repo: repo))
        add("reflog", RefLogController(repo: repo))
        add("cleanup", CleanupDialog(repo: repo, specs: []))
        add("stashlist", StashListController(repo: repo))
        add("resolve", ResolveController(repo: repo))
        add("push", PushDialog(repo: repo))
        add("sync", SyncDialog(repo: repo))
        add("switch", SwitchDialog(repo: repo))
        add("branch", BranchDialog(repo: repo))
        add("pull", PullDialog(repo: repo))
        add("fetch", FetchDialog(repo: repo))
        add("tag", TagDialog(repo: repo))
        add("merge", MergeDialog(repo: repo))
        add("stash", StashDialog(repo: repo))
        add("remove", RemoveDialog(repo: repo, paths: ["README.md", "user.swift"]))
        let blameStart = ToolWindow.live.count
        BlameController.open(repo: repo, path: "README.md")
        if ToolWindow.live.count > blameStart, let blame = ToolWindow.live.last { windows.append(("blame", blame)) }
        add("login", LoginDialog(server: "https://github.com", repo: repo) { _, _ in })
        add("clone", CloneDialog(parent: (repo as NSString).deletingLastPathComponent))
        let before = ToolWindow.live.count
        if let change = Git.status(repo).first(where: { $0.kind == .modified }) {
            DiffController.openWorking(repo: repo, file: change)
        }
        if ToolWindow.live.count > before, let diff = ToolWindow.live.last { windows.append(("diff", diff)) }
        // Окно хода — на безвредных командах, которые только читают.
        windows.append(("progress", ProgressController.run(title: L.t("Ход выполнения", "Git Command Progress"), dir: repo,
                                                           steps: [["status", "--short", "--branch"], ["log", "--oneline", "-n", "3"]])))
        HomeController.show(path: repo)
        if let home = ToolWindow.live.last { windows.append(("home", home)) }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            for (name, controller) in windows {
                guard let window = controller.window else { continue }
                save(window, to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
            }
            exit(0)
        }
    }

    private static func save(_ window: NSWindow, to url: URL) {
        guard let view = window.contentView else { return }
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
        print("Saved \(url.path)")
    }
}
