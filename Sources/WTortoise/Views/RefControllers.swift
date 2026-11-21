import AppKit

/// «Browse References»: слева виды ссылок, справа ветки или метки выбранного вида.
final class RefBrowserController: ToolWindow, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate, NSTextFieldDelegate {
    private struct Ref {
        let full: String
        let name: String
        let date: String
        let subject: String
        let upstream: String
    }

    private let repo: String
    private var kindTable: NSTableView!
    private var refTable: NSTableView!
    private let filter = UI.field(placeholder: L.t("Отбор", "Filter"), width: 200)
    /// Виды ссылок: подпись и начало полного имени.
    private var kinds: [(title: String, prefix: String)] = []
    private var all: [Ref] = []
    private var shown: [Ref] = []

    init(repo: String) {
        self.repo = repo
        super.init(title: ToolWindow.title(repo, L.t("Ветки и метки", "Browse references")), size: NSSize(width: 860, height: 460))
        let (kindScroll, kindTable) = UI.table([("kind", L.t("Ссылки", "Refs"), 150)])
        let (refScroll, refTable) = UI.table([
            ("name", L.t("Имя", "Name"), 190), ("date", L.t("Дата последней фиксации", "Date Last Commit"), 140),
            ("subject", L.t("Последняя фиксация", "Last Commit"), 230), ("upstream", L.t("Следит за", "Tracked from"), 110),
        ], flex: 2)
        self.kindTable = kindTable
        self.refTable = refTable
        kindTable.headerView = nil
        kindTable.allowsMultipleSelection = false
        for table in [kindTable, refTable] {
            table.dataSource = self
            table.delegate = self
        }
        refTable.target = self
        refTable.doubleAction = #selector(showLog)
        let menu = NSMenu()
        menu.delegate = self
        refTable.menu = menu
        filter.delegate = self

        kindScroll.widthAnchor.constraint(equalToConstant: 170).isActive = true
        let panes = UI.row([kindScroll, refScroll])
        let top = UI.row([UI.spacer(), filter])
        let content = UI.column([top, panes])
        for view in [top, panes] { view.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true }
        top.setHuggingPriority(.required, for: .vertical)
        install(content, buttons: [okButton, cancelButton, helpButton])
        watch(repo) { [weak self] in self?.reload() }
        reload()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func reload() {
        let format = "%(refname)%1f%(refname:short)%1f%(committerdate:iso)%1f%(subject)%1f%(upstream:short)"
        all = Git.run(["for-each-ref", "--format=" + format, "refs/heads", "refs/remotes", "refs/tags"], in: repo).lines.compactMap { line in
            let parts = line.components(separatedBy: "\u{1f}")
            guard parts.count == 5, !parts[0].hasSuffix("/HEAD") else { return nil }
            return Ref(full: parts[0], name: parts[1], date: String(parts[2].prefix(19)), subject: parts[3], upstream: parts[4])
        }
        let selected = kindTable.selectedRow
        kinds = [("heads", "refs/heads/")] + Git.remotes(repo).map { ("remotes/" + $0, "refs/remotes/\($0)/") } + [("tags", "refs/tags/")]
        kindTable.reloadData()
        kindTable.selectRowIndexes([selected >= 0 && selected < kinds.count ? selected : 0], byExtendingSelection: false)
        applyFilter()
    }

    private func applyFilter() {
        let row = kindTable.selectedRow
        let prefix = row >= 0 && row < kinds.count ? kinds[row].prefix : "refs/heads/"
        let query = filter.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        shown = all.filter { $0.full.hasPrefix(prefix) && (query.isEmpty || $0.name.lowercased().contains(query)) }
        refTable.reloadData()
    }

    func controlTextDidChange(_ obj: Notification) { applyFilter() }

    func numberOfRows(in tableView: NSTableView) -> Int { tableView === kindTable ? kinds.count : shown.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === kindTable { return UI.textCell(kinds[row].title) }
        let ref = shown[row]
        let current = ref.full == "refs/heads/" + (Git.currentBranch(repo) ?? "")
        switch tableColumn?.identifier.rawValue {
        case "name":
            let cell = UI.textCell(ref.name)
            if current { cell.textField?.font = Win.boldFont }
            return cell
        case "date": return UI.textCell(ref.date)
        case "subject": return UI.textCell(ref.subject)
        default: return UI.textCell(ref.upstream)
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if (notification.object as? NSTableView) === kindTable { applyFilter() }
    }

    private var clicked: Ref? {
        let row = refTable.clickedRow >= 0 ? refTable.clickedRow : refTable.selectedRow
        return row >= 0 && row < shown.count ? shown[row] : nil
    }

    @objc private func showLog() {
        guard let ref = clicked else { return }
        PatchWindow(repo: repo, text: Git.run(["log", "--graph", "--decorate", "--date=short", "-n", "300",
                                               "--format=%h %ad %an  %s%d", ref.full], in: repo).out).present()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let ref = clicked else { return }
        let repo = self.repo
        let isBranch = ref.full.hasPrefix("refs/heads/"), isTag = ref.full.hasPrefix("refs/tags/")
        menu.addItem(ClosureMenuItem(Command.log.title, glyph: .log) { [weak self] in self?.showLog() })
        menu.addItem(ClosureMenuItem(L.t("Сравнить с рабочей копией", "Compare with working tree"), glyph: .diff) {
            PatchWindow(repo: repo, text: Git.run(["diff", ref.full], in: repo).out).present()
        })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(L.t("Переключиться на эту ссылку…", "Switch to this Ref..."), glyph: .switchBranch) {
            SwitchDialog(repo: repo, preset: ref.name).present()
        })
        menu.addItem(ClosureMenuItem(L.t("Слить в текущую ветку…", "Merge to \"\(Git.headName(repo))\"..."), glyph: .merge) {
            guard UI.confirm(L.t("Слить «\(ref.name)» в «\(Git.headName(repo))»?", "Merge \"\(ref.name)\" into \"\(Git.headName(repo))\"?"),
                             ok: L.t("Слить", "Merge")) else { return }
            ProgressController.run(title: "Merge", dir: repo, steps: [["merge", ref.full]])
        })
        menu.addItem(.separator())
        if isBranch {
            menu.addItem(ClosureMenuItem(L.t("Переименовать…", "Rename"), glyph: .rename) { [weak self] in self?.rename(ref) })
        }
        if isBranch || isTag {
            let title = isBranch ? L.t("Удалить ветку", "Delete branch") : L.t("Удалить метку", "Delete tag")
            menu.addItem(ClosureMenuItem(title, glyph: .remove) {
                guard UI.confirm(L.t("Удалить «\(ref.name)»?", "Delete \"\(ref.name)\"?"),
                                 info: isBranch ? L.t("Фиксации, которых нет в других ветках, станут недоступны.",
                                                      "Commits that are in no other branch will become unreachable.") : "",
                                 ok: L.t("Удалить", "Delete")) else { return }
                ProgressController.run(title: title, dir: repo, steps: [isBranch ? ["branch", "-D", ref.name] : ["tag", "-d", ref.name]])
            })
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(L.t("Скопировать имя", "Copy ref names")) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(ref.name, forType: .string)
        })
    }

    private func rename(_ ref: Ref) {
        let alert = NSAlert()
        alert.messageText = L.t("Новое имя ветки «\(ref.name)»", "New name for branch \"\(ref.name)\"")
        let field = NSTextField(string: ref.name)
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: L.t("Отмена", "Cancel"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let fresh = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !fresh.isEmpty, fresh != ref.name else { return }
        ProgressController.run(title: "Rename", dir: repo, steps: [["branch", "-m", ref.name, fresh]])
    }
}

/// «Show Reflog»: где побывала HEAD — чтобы вернуть потерянную фиксацию.
final class RefLogController: ToolWindow, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    private let repo: String
    private var table: NSTableView!
    private var entries: [(hash: String, ref: String, date: String, action: String)] = []

    init(repo: String) {
        self.repo = repo
        super.init(title: ToolWindow.title(repo, L.t("Журнал ссылок", "RefLog")), size: NSSize(width: 820, height: 420))
        let (scroll, table) = UI.table([
            ("hash", "SHA-1", 80), ("ref", L.t("Ссылка", "Ref"), 90), ("date", L.t("Дата", "Date"), 140),
            ("action", L.t("Действие и сообщение", "Action / Message"), 460),
        ], flex: 3)
        self.table = table
        table.allowsMultipleSelection = false
        table.dataSource = self
        table.delegate = self
        let menu = NSMenu()
        menu.delegate = self
        table.menu = menu
        install(scroll, buttons: [okButton, helpButton])
        watch(repo) { [weak self] in self?.reload() }
        reload()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func reload() {
        entries = Git.run(["reflog", "-n", "1000", "--format=%H%x1f%gd%x1f%ci%x1f%gs"], in: repo).lines.compactMap { line in
            let parts = line.components(separatedBy: "\u{1f}")
            guard parts.count == 4 else { return nil }
            return (parts[0], parts[1], String(parts[2].prefix(19)), parts[3])
        }
        table.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = entries[row]
        switch tableColumn?.identifier.rawValue {
        case "hash": return UI.textCell(String(entry.hash.prefix(8)) + "...")
        case "ref": return UI.textCell(entry.ref)
        case "date": return UI.textCell(entry.date)
        default: return UI.textCell(entry.action)
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = table.clickedRow
        guard row >= 0 else { return }
        let entry = entries[row], repo = self.repo
        menu.addItem(ClosureMenuItem(L.t("Переключиться на эту версию…", "Switch/Checkout to this..."), glyph: .switchBranch) {
            SwitchDialog(repo: repo, preset: entry.hash).present()
        })
        menu.addItem(ClosureMenuItem(L.t("Создать ветку от этой версии…", "Create Branch at this version..."), glyph: .branch) {
            BranchDialog(repo: repo, preset: entry.hash).present()
        })
        menu.addItem(ClosureMenuItem(L.t("Сбросить «\(Git.headName(repo))» на эту версию…", "Reset \"\(Git.headName(repo))\" to this..."), glyph: .revert) {
            let commit = Commit(hash: entry.hash, parents: [], author: "", email: "", date: Date(), refs: [], subject: entry.action)
            ResetDialog(repo: repo, commit: commit).present()
        })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(L.t("Скопировать SHA-1", "Copy SHA-1 to clipboard")) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(entry.hash, forType: .string)
        })
    }
}
