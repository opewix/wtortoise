import Cocoa
import FinderSync
import os

private let logger = Logger(subsystem: "dev.oleg.wtortoise.finder", category: "status")

/// Расширение Finder: контекстное меню WTortoise и значки состояния на файлах рабочих копий.
/// Само ничего не меняет: команды открывают приложение ссылкой `wtortoise://…`.
@objc(FinderSync)
final class FinderSync: FIFinderSync {
    private let statuses = StatusCache()

    override init() {
        super.init()
        let controller = FIFinderSyncController.default()
        // Следим за всем диском: рабочая копия может лежать где угодно.
        controller.directoryURLs = [URL(fileURLWithPath: "/")]
        for badge in Badge.allCases {
            controller.setBadgeImage(badge.image(128), label: badge.label, forBadgeIdentifier: badge.rawValue)
        }
    }

    // MARK: Значки

    override func beginObservingDirectory(at url: URL) {
        statuses.invalidate(containing: url.path)
    }

    override func requestBadgeIdentifier(for url: URL) {
        statuses.badge(for: url.path) { badge in
            guard let badge else { return }
            FIFinderSyncController.default().setBadgeIdentifier(badge.rawValue, for: url)
        }
    }

    // MARK: Меню

    override var toolbarItemName: String { "WTortoise" }
    override var toolbarItemToolTip: String { L.t("Команды Git для этой папки", "Git commands for this folder") }
    override var toolbarItemImage: NSImage { Glyph.app.image(18) }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "")
        guard let target = targets().first else { return menu }
        let submenu = NSMenu(title: "WTortoise")

        if let root = RepoPath.root(of: target) {
            // Как в TortoiseGit: три частые команды — прямо в меню, остальное — в группе.
            let branch = RepoPath.branch(root: root) ?? "HEAD"
            menu.addItem(item(.pull, title: Command.pull.topLevelTitle))
            menu.addItem(item(.fetch, title: Command.fetch.topLevelTitle))
            menu.addItem(item(.commit, title: Command.commitTitle(branch: branch)))
            for (index, group) in Command.submenuGroups.enumerated() {
                if index > 0 { submenu.addItem(.separator()) }
                group.forEach { submenu.addItem(item($0)) }
            }
        } else {
            menu.addItem(item(.clone, title: Command.clone.topLevelTitle))
            menu.addItem(item(.initRepo, title: Command.initRepo.topLevelTitle))
            submenu.addItem(item(.settings))
            submenu.addItem(item(.about))
        }
        let parent = NSMenuItem(title: "WTortoise", action: nil, keyEquivalent: "")
        parent.image = Glyph.app.image()
        parent.submenu = submenu
        menu.addItem(parent)
        return menu
    }

    private func item(_ command: Command, title: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title ?? command.title, action: #selector(runCommand(_:)), keyEquivalent: "")
        item.target = self
        item.tag = command.tag
        item.image = command.glyph.image()
        return item
    }

    /// Выбранное в Finder, а если ничего не выбрано — открытая папка.
    private func targets() -> [String] {
        let controller = FIFinderSyncController.default()
        if let selected = controller.selectedItemURLs(), !selected.isEmpty { return selected.map(\.path) }
        return controller.targetedURL().map { [$0.path] } ?? []
    }

    @objc private func runCommand(_ sender: NSMenuItem) {
        // Finder отдаёт копию пункта меню: от нашего остаются заголовок и tag.
        guard let command = Command.with(tag: sender.tag) ?? Command.allCases.first(where: { $0.title == sender.title }) else { return }
        NSWorkspace.shared.open(command.url(paths: targets()))
    }
}

/// Состояние файлов рабочих копий для значков. Читает `git status`, держит ответ несколько секунд.
final class StatusCache {
    private struct Entry {
        var time: Date
        var changed: [String: Badge] = [:]
        var changedDirs: Set<String> = []
        /// Не под версией и игнорируемые: значка нет. Папки — с «/» на конце.
        var excluded: [String] = []
    }

    private var entries: [String: Entry] = [:]
    private let queue = DispatchQueue(label: "dev.oleg.wtortoise.finder.status")
    private let lifetime: TimeInterval = 4

    private static let git: String? = [
        "/Library/Developer/CommandLineTools/usr/bin/git", "/Applications/Xcode.app/Contents/Developer/usr/bin/git",
        "/opt/homebrew/bin/git", "/usr/local/bin/git", "/usr/bin/git",
    ].first { FileManager.default.isExecutableFile(atPath: $0) }

    func invalidate(containing path: String) {
        queue.async {
            if let root = RepoPath.root(of: path) { self.entries[root] = nil }
        }
    }

    func badge(for path: String, completion: @escaping (Badge?) -> Void) {
        queue.async {
            let badge = self.lookup(path)
            DispatchQueue.main.async { completion(badge) }
        }
    }

    private func lookup(_ path: String) -> Badge? {
        guard let root = RepoPath.root(of: path) else { return nil }
        let relative = RepoPath.relative(path, to: root)
        if relative == ".git" || relative.hasPrefix(".git/") { return nil }
        var entry = entries[root]
        if entry == nil || Date().timeIntervalSince(entry!.time) > lifetime {
            guard let fresh = load(root) else { return nil }
            entries[root] = fresh
            entry = fresh
        }
        guard let entry else { return nil }
        if relative.isEmpty { return entry.changed.isEmpty ? .normal : .modified }
        for excluded in entry.excluded {
            if excluded.hasSuffix("/") ? (relative + "/").hasPrefix(excluded) : relative == excluded { return nil }
        }
        if let badge = entry.changed[relative] { return badge }
        return entry.changedDirs.contains(relative) ? .modified : .normal
    }

    private func load(_ root: String) -> Entry? {
        guard let git = StatusCache.git else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: git)
        // --no-optional-locks: только читаем, индекс не трогаем — расширение живёт в песочнице.
        process.arguments = ["--no-optional-locks", "-c", "core.quotepath=false", "-C", root,
                             "status", "--porcelain", "-z", "-unormal", "--ignored"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch {
            logger.error("git did not start: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            logger.error("git status exited with \(process.terminationStatus) in \(root, privacy: .public)")
            return nil
        }

        var entry = Entry(time: Date())
        let records = String(decoding: data, as: UTF8.self).split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
        var index = 0
        while index < records.count {
            let record = records[index]
            index += 1
            guard record.count > 3 else { continue }
            let chars = Array(record)
            let x = chars[0], y = chars[1], path = String(chars[3...])
            if x == "R" || x == "C" { index += 1 }
            if x == "?" || x == "!" {
                entry.excluded.append(path)
                continue
            }
            let badge: Badge
            if x == "U" || y == "U" || (x == "A" && y == "A") || (x == "D" && y == "D") {
                badge = .conflicted
            } else if x == "A" {
                badge = .added
            } else {
                badge = .modified
            }
            entry.changed[path] = badge
            var dir = (path as NSString).deletingLastPathComponent
            while !dir.isEmpty {
                entry.changedDirs.insert(dir)
                dir = (dir as NSString).deletingLastPathComponent
            }
        }
        // Смотреть: log stream --level debug --predicate 'subsystem == "dev.oleg.wtortoise.finder"'
        logger.debug("status \(root, privacy: .public): changed \(entry.changed.count), excluded \(entry.excluded.count)")
        return entry
    }
}
