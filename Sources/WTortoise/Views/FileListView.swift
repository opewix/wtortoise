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

    init(repo: String, checkable: Bool) {
        self.repo = repo
        self.checkable = checkable
        let (scroll, table) = UI.table([
            ("path", L.t("Путь", "Path"), 380),
            ("ext", L.t("Расширение", "Extension"), 80),
            ("status", L.t("Состояние", "Status"), 110),
            ("added", L.t("Строк добавлено", "Lines added"), 100),
            ("removed", L.t("Строк убрано", "Lines removed"), 100),
        ])
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
        table.reloadData()
        onCheckedChange?()
    }

    var checkedFiles: [FileChange] { files.filter { checked.contains($0.path) } }

    func setChecked(_ predicate: (FileChange) -> Bool) {
        checked = Set(files.filter(predicate).map(\.path))
        table.reloadData()
        onCheckedChange?()
    }

    // MARK: Таблица

    func numberOfRows(in tableView: NSTableView) -> Int { files.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let file = files[row]
        switch tableColumn?.identifier.rawValue {
        case "path":
            let title = file.oldPath.map { "\($0) → \(file.path)" } ?? file.path
            guard checkable else { return UI.textCell(title, color: file.color) }
            // Галочка — отдельная кнопка без подписи: она срабатывает только от щелчка по ней самой.
            // Щелчок по названию выделяет строку, двойной — открывает сравнение.
            let cell = UI.textCell(title, color: file.color)
            let box = WinCheck("", on: checked.contains(file.path))
            box.target = self
            box.action = #selector(toggle(_:))
            cell.addSubview(box)
            if let label = cell.textField {
                label.lineBreakMode = .byTruncatingMiddle
                // Подпись сдвигаем вправо от галочки: прежнее ограничение левого края снимаем.
                cell.constraints.filter { $0.firstItem === label && $0.firstAttribute == .leading }.forEach { $0.isActive = false }
                label.leadingAnchor.constraint(equalTo: box.trailingAnchor, constant: 4).isActive = true
            }
            NSLayoutConstraint.activate([
                box.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                box.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                box.widthAnchor.constraint(equalToConstant: 13),
            ])
            return cell
        case "ext": return UI.textCell(file.ext, color: file.color)
        case "status": return UI.textCell(file.statusText, color: file.color)
        case "added": return UI.textCell(stats[file.path].map { String($0.added) } ?? "", color: file.color, alignment: .right)
        case "removed": return UI.textCell(stats[file.path].map { String($0.removed) } ?? "", color: file.color, alignment: .right)
        default: return nil
        }
    }

    @objc private func toggle(_ sender: NSButton) {
        let row = table.row(for: sender)
        guard row >= 0 else { return }
        // Отметка на выделенной строке меняет все выделенные, как в TortoiseGit.
        let rows = table.selectedRowIndexes.contains(row) ? Array(table.selectedRowIndexes) : [row]
        for r in rows {
            if sender.state == .on { checked.insert(files[r].path) } else { checked.remove(files[r].path) }
        }
        if rows.count > 1 {
            let selection = table.selectedRowIndexes
            table.reloadData()
            table.selectRowIndexes(selection, byExtendingSelection: false)
        }
        onCheckedChange?()
    }

    @objc private func openDiff() {
        let row = table.clickedRow
        guard row >= 0 else { return }
        DiffController.openWorking(repo: repo, file: files[row])
    }

    // MARK: Контекстное меню

    private var targets: [FileChange] {
        let row = table.clickedRow
        guard row >= 0 else { return [] }
        let rows = table.selectedRowIndexes.contains(row) ? Array(table.selectedRowIndexes) : [row]
        return rows.map { files[$0] }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let targets = self.targets
        guard let first = targets.first else { return }
        let repo = self.repo
        menu.addItem(ClosureMenuItem(L.t("Сравнить с базой", "Compare with base"), glyph: .diff) {
            DiffController.openWorking(repo: repo, file: first)
        })
        // Журнал — у файла под версией; у переименованного история идёт от прежнего имени.
        if first.kind != .untracked {
            menu.addItem(ClosureMenuItem(Command.log.title, glyph: .log) {
                LogController(repo: repo, specs: [first.kind == .added ? first.path : (first.oldPath ?? first.path)]).present()
            })
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
            menu.addItem(ClosureMenuItem(L.t("Добавить в список игнорируемых", "Add to ignore list")) {
                let ignore = repo + "/.gitignore"
                var text = (try? String(contentsOfFile: ignore, encoding: .utf8)) ?? ""
                if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
                text += untracked.map { "/" + $0 }.joined(separator: "\n") + "\n"
                try? text.write(toFile: ignore, atomically: true, encoding: .utf8)
                NotificationCenter.default.post(name: Git.changed, object: repo)
            })
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
