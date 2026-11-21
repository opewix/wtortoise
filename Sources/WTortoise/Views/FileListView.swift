import AppKit

/// Список изменённых файлов: фиксация, проверка изменений, добавление, отмена изменений.
final class FileListView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    let repo: String
    private let checkable: Bool
    private let table: NSTableView
    private(set) var files: [FileChange] = []
    private var stats: [String: (added: Int, removed: Int)] = [:]
    private(set) var checked: Set<String> = []
    var onCheckedChange: (() -> Void)?
    /// Строки таблицы: заголовки групп («Modified Files», «Not Versioned Files») и файлы под ними.
    private enum Row {
        case header(String)
        case file(Int)
    }
    private var rows: [Row] = []
    /// Пункт «Commit...» в меню строки — в окне проверки изменений.
    var commitFromMenu = false
    private let modifiedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy HH:mm:ss"
        return formatter
    }()

    /// - Parameters:
    ///   - lines: столбцы «Lines added / removed» (в окнах Revert и Add их нет).
    ///   - lastModified: столбец «Last Modified» — в окне проверки изменений.
    init(repo: String, checkable: Bool, lines: Bool = true, lastModified: Bool = false) {
        self.repo = repo
        self.checkable = checkable
        var columns: [(id: String, title: String, width: CGFloat)] = [
            ("path", L.t("Путь", "Path"), lines ? 330 : 400),
            ("ext", L.t("Расширение", "Extension"), 76),
            ("status", L.t("Состояние", "Status"), 90),
        ]
        if lines {
            columns += [("added", L.t("Строк добавлено", "Lines added"), 86), ("removed", L.t("Строк убрано", "Lines removed"), 96)]
        }
        if lastModified { columns.append(("modified", L.t("Изменён", "Last Modified"), 130)) }
        let (scroll, table) = UI.table(columns)
        table.floatsGroupRows = false
        self.table = table
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(openDiff)
        let menu = NSMenu()
        menu.delegate = self
        table.menu = menu
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Показать файлы; `check` решает, какие отметить (только для новых в списке — отметки человека сохраняются).
    func show(_ files: [FileChange], stats: [String: (added: Int, removed: Int)] = [:], check: (FileChange) -> Bool) {
        let known = Set(self.files.map(\.path))
        let present = Set(files.map(\.path))
        checked = checked.intersection(present)
        for file in files where !known.contains(file.path) && check(file) { checked.insert(file.path) }
        self.files = files
        self.stats = stats
        // Сначала файлы под версией, потом не под версией — каждая группа под своим заголовком.
        rows = []
        let versioned = files.indices.filter { files[$0].kind != .untracked }
        let unversioned = files.indices.filter { files[$0].kind == .untracked }
        if !versioned.isEmpty { rows += [.header(L.t("Изменённые файлы", "Modified Files"))] + versioned.map(Row.file) }
        if !unversioned.isEmpty { rows += [.header(L.t("Файлы не под версией", "Not Versioned Files"))] + unversioned.map(Row.file) }
        table.reloadData()
        onCheckedChange?()
    }

    private func file(at row: Int) -> FileChange? {
        guard row >= 0, row < rows.count, case .file(let index) = rows[row] else { return nil }
        return files[index]
    }

    /// Значок файла по его типу; у папки — значок папки.
    private func icon(for file: FileChange) -> NSImage {
        let path = repo + "/" + file.path
        var isDir: ObjCBool = false
        let image: NSImage
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
            image = NSWorkspace.shared.icon(forFile: path)
        } else {
            image = NSWorkspace.shared.icon(forFileType: (file.path as NSString).pathExtension)
        }
        image.size = NSSize(width: 16, height: 16)
        return image
    }

    var checkedFiles: [FileChange] { files.filter { checked.contains($0.path) } }

    func setChecked(_ predicate: (FileChange) -> Bool) {
        checked = Set(files.filter(predicate).map(\.path))
        table.reloadData()
        onCheckedChange?()
    }

    // MARK: Таблица

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        if case .header = rows[row] { return true }
        return false
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { file(at: row) != nil }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        // Строка-заголовок без серой подложки macOS: фон списка белый.
        guard case .header = rows[row] else { return nil }
        return GroupRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        // Заголовок группы — одна ячейка на всю ширину: таблица спрашивает её без столбца.
        if case .header(let title) = rows[row] { return tableColumn == nil ? GroupHeaderView(title) : nil }
        guard let file = file(at: row) else { return nil }
        switch tableColumn?.identifier.rawValue {
        case "path":
            let title = file.oldPath.map { "\($0) → \(file.path)" } ?? file.path
            let cell = UI.textCell(title, color: file.color)
            guard let label = cell.textField else { return cell }
            label.lineBreakMode = .byTruncatingMiddle
            let picture = NSImageView(image: icon(for: file))
            picture.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(picture)
            // Подпись сдвигаем вправо от значка: прежнее ограничение левого края снимаем.
            cell.constraints.filter { $0.firstItem === label && $0.firstAttribute == .leading }.forEach { $0.isActive = false }
            var left = cell.leadingAnchor
            var gap: CGFloat = 4
            if checkable {
                // Галочка — отдельная кнопка без подписи: она срабатывает только от щелчка по ней самой.
                // Щелчок по названию выделяет строку, двойной — открывает сравнение.
                let box = WinCheck("", on: checked.contains(file.path))
                box.target = self
                box.action = #selector(toggle(_:))
                cell.addSubview(box)
                NSLayoutConstraint.activate([
                    box.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                    box.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    box.widthAnchor.constraint(equalToConstant: 13),
                ])
                left = box.trailingAnchor
                gap = 5
            }
            NSLayoutConstraint.activate([
                picture.leadingAnchor.constraint(equalTo: left, constant: gap),
                picture.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                picture.widthAnchor.constraint(equalToConstant: 16), picture.heightAnchor.constraint(equalToConstant: 16),
                label.leadingAnchor.constraint(equalTo: picture.trailingAnchor, constant: 3),
            ])
            return cell
        case "ext": return UI.textCell(file.ext, color: file.color)
        case "status": return UI.textCell(file.statusText, color: file.color)
        case "added": return UI.textCell(stats[file.path].map { String($0.added) } ?? "", color: file.color, alignment: .right)
        case "removed": return UI.textCell(stats[file.path].map { String($0.removed) } ?? "", color: file.color, alignment: .right)
        case "modified":
            let date = (try? FileManager.default.attributesOfItem(atPath: repo + "/" + file.path))?[.modificationDate] as? Date
            return UI.textCell(date.map(modifiedFormatter.string) ?? "", color: file.color)
        default: return nil
        }
    }

    @objc private func toggle(_ sender: NSButton) {
        let row = table.row(for: sender)
        guard row >= 0 else { return }
        // Отметка на выделенной строке меняет все выделенные, как в TortoiseGit.
        let rows = table.selectedRowIndexes.contains(row) ? Array(table.selectedRowIndexes) : [row]
        for r in rows {
            guard let path = file(at: r)?.path else { continue }
            if sender.state == .on { checked.insert(path) } else { checked.remove(path) }
        }
        if rows.count > 1 {
            let selection = table.selectedRowIndexes
            table.reloadData()
            table.selectRowIndexes(selection, byExtendingSelection: false)
        }
        onCheckedChange?()
    }

    @objc private func openDiff() {
        guard let file = file(at: table.clickedRow) else { return }
        DiffController.openWorking(repo: repo, file: file)
    }

    // MARK: Контекстное меню

    private var targets: [FileChange] {
        let row = table.clickedRow
        guard row >= 0 else { return [] }
        let rows = table.selectedRowIndexes.contains(row) ? Array(table.selectedRowIndexes) : [row]
        return rows.compactMap { file(at: $0) }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let targets = self.targets
        guard let first = targets.first else { return }
        let repo = self.repo
        menu.addItem(ClosureMenuItem(L.t("Сравнить с базой", "Compare with base"), glyph: .diff) {
            DiffController.openWorking(repo: repo, file: first)
        })
        if first.kind != .untracked {
            menu.addItem(ClosureMenuItem(L.t("Показать изменения единой правкой", "Show changes as unified diff"), glyph: .diff) {
                PatchWindow(repo: repo, text: Git.run(["diff", "HEAD", "--"] + first.pathspecs, in: repo).out).present()
            })
        }
        menu.addItem(.separator())
        if commitFromMenu {
            let paths = targets.map(\.path)
            menu.addItem(ClosureMenuItem(Command.commit.title, glyph: .commit) {
                CommitController(repo: repo, specs: paths).present()
            })
        }
        // Журнал — у файла под версией; у переименованного история идёт от прежнего имени.
        if first.kind != .untracked {
            menu.addItem(ClosureMenuItem(Command.log.title, glyph: .log) {
                LogController(repo: repo, specs: [first.kind == .added ? first.path : (first.oldPath ?? first.path)]).present()
            })
            if first.kind != .added && first.kind != .deleted {
                menu.addItem(ClosureMenuItem(Command.blame.title, glyph: .blame) {
                    BlameController.open(repo: repo, path: first.path)
                })
            }
        }
        menu.addItem(.separator())
        let revertable = targets.filter { $0.kind != .untracked }
        if !revertable.isEmpty {
            menu.addItem(ClosureMenuItem(L.t("Убрать изменения…", "Revert..."), glyph: .revert) {
                let names = revertable.prefix(8).map(\.path).joined(separator: "\n") + (revertable.count > 8 ? "\n…" : "")
                guard UI.confirm(L.t("Убрать изменения в файлах (\(revertable.count))?", "Revert changes in \(revertable.count) file(s)?"),
                                 info: L.t("Файлы вернутся к последней фиксации. Отменить это нельзя.\n\n",
                                           "The files go back to the last commit. This cannot be undone.\n\n") + names,
                                 ok: L.t("Убрать изменения", "Revert")) else { return }
                ProgressController.run(title: L.t("Убрать изменения", "Revert"), dir: repo, steps: Git.revertSteps(revertable))
            })
        }
        let untracked = targets.filter { $0.kind == .untracked }.map(\.path)
        if !untracked.isEmpty {
            menu.addItem(ClosureMenuItem(L.t("Добавить", "Add"), glyph: .add) {
                Git.run(["add", "--"] + untracked, in: repo)
                NotificationCenter.default.post(name: Git.changed, object: repo)
            })
            // Как в оригинале: подменю «по имени» и «по расширению», затем окно с выбором файла .gitignore.
            let ignore = NSMenuItem(title: L.t("Добавить в список игнорируемых", "Add to ignore list"), action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            let names = untracked.map { ($0 as NSString).lastPathComponent }
            submenu.addItem(ClosureMenuItem(names.count == 1 ? names[0] : L.t("Игнорировать \(names.count) по именам", "Ignore \(names.count) items by name")) {
                IgnoreDialog(repo: repo, paths: untracked, byExtension: false).present()
            })
            let extensions = Set(untracked.map { ($0 as NSString).pathExtension }.filter { !$0.isEmpty })
            if !extensions.isEmpty {
                submenu.addItem(ClosureMenuItem(extensions.sorted().map { "*." + $0 }.joined(separator: ", ")) {
                    IgnoreDialog(repo: repo, paths: untracked, byExtension: true).present()
                })
            }
            ignore.submenu = submenu
            menu.addItem(ignore)
        }
        let conflicted = targets.filter { $0.kind == .conflicted }.map(\.path)
        if !conflicted.isEmpty {
            menu.addItem(ClosureMenuItem(L.t("Пометить как улаженный", "Resolved")) {
                Git.run(["add", "--"] + conflicted, in: repo)
                NotificationCenter.default.post(name: Git.changed, object: repo)
            })
        }
        menu.addItem(.separator())
        let urls = targets.map { URL(fileURLWithPath: repo + "/" + $0.path) }
        menu.addItem(ClosureMenuItem(L.t("Открыть", "Open")) {
            urls.forEach { NSWorkspace.shared.open($0) }
        })
        menu.addItem(ClosureMenuItem(L.t("Показать в Finder", "Explore to")) {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        })
        menu.addItem(ClosureMenuItem(L.t("Скопировать путь", "Copy paths to clipboard")) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
        })
    }
}

/// Строка-заголовок группы: без подложки, которой macOS выделяет такие строки.
private final class GroupRowView: NSTableRowView {
    override func drawBackground(in dirtyRect: NSRect) {
        NSColor.white.setFill()
        dirtyRect.fill()
    }
}

/// Заголовок группы файлов, как в списках TortoiseGit: синяя надпись и тонкая линия до правого края.
private final class GroupHeaderView: NSView {
    private let title: String

    init(_ title: String) {
        self.title = title
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ dirtyRect: NSRect) {
        let text = NSAttributedString(string: title, attributes: Win.attributes(NSColor(hex: 0x1E3287)))
        let size = text.size()
        text.draw(at: NSPoint(x: 12, y: ((bounds.height - size.height) / 2).rounded()))
        NSColor(hex: 0xC8D3E8).setFill()
        NSRect(x: 12 + size.width + 6, y: bounds.midY.rounded(), width: max(0, bounds.width - size.width - 30), height: 1).fill()
    }
}
