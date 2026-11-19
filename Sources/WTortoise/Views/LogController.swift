import AppKit

private let laneColors: [NSColor] = [0x000000, 0xD43A2F, 0x2F6FD4, 0x2E9E3F, 0xB04BC4, 0xE08A1E, 0x16A5A5, 0x8A6D2F].map { NSColor(hex: $0) }
private let laneWidth: CGFloat = 12

/// Ячейка графа: дорожки и узел фиксации.
private final class GraphCell: NSView {
    var row: GraphRow?

    override func draw(_ dirtyRect: NSRect) {
        guard let row else { return }
        func x(_ lane: Int) -> CGFloat { CGFloat(lane) * laneWidth + laneWidth / 2 + 2 }
        let mid = bounds.midY, top = bounds.maxY, bottom = bounds.minY
        func line(_ from: NSPoint, _ to: NSPoint, lane: Int) {
            let path = NSBezierPath()
            path.move(to: from)
            path.line(to: to)
            path.lineWidth = 1.5
            laneColors[lane % laneColors.count].setStroke()
            path.stroke()
        }
        let node = NSPoint(x: x(row.column), y: mid)
        for lane in row.through { line(NSPoint(x: x(lane), y: top), NSPoint(x: x(lane), y: bottom), lane: lane) }
        for lane in row.joins { line(NSPoint(x: x(lane), y: top), node, lane: lane) }
        for lane in row.forks { line(node, NSPoint(x: x(lane), y: bottom), lane: lane) }
        let dot = NSBezierPath(ovalIn: NSRect(x: node.x - 3.5, y: node.y - 3.5, width: 7, height: 7))
        laneColors[row.column % laneColors.count].setFill()
        dot.fill()
        NSColor.white.setStroke()
        dot.lineWidth = 1
        dot.stroke()
    }
}

/// Ячейка сообщения: ярлыки веток и меток, за ними — первая строка сообщения.
private final class MessageCell: NSTableCellView {
    var commit: Commit?

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let commit else { return }
        var x: CGFloat = 2
        let font = NSFont.systemFont(ofSize: 11)
        for ref in commit.refs {
            // Цвета ярлыков как в TortoiseGit: текущая ветка — красная, своя — зелёная, чужая — персиковая, метка — жёлтая.
            var name = ref
            var color = NSColor(hex: 0xBFF0B8)
            if ref.hasPrefix("HEAD -> ") {
                name = String(ref.dropFirst(8))
                color = NSColor(hex: 0xFF9A9A)
            } else if ref == "HEAD" {
                color = NSColor(hex: 0xFF9A9A)
            } else if ref.hasPrefix("tag: ") {
                name = String(ref.dropFirst(5))
                color = NSColor(hex: 0xFFF08A)
            } else if ref.contains("/") {
                color = NSColor(hex: 0xFFDDB0)
            }
            let text = name as NSString
            let size = text.size(withAttributes: [.font: font])
            let rect = NSRect(x: x, y: bounds.midY - 8, width: size.width + 8, height: 16)
            guard rect.maxX < bounds.width - 20 else { break }
            let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
            color.setFill()
            path.fill()
            NSColor(white: 0, alpha: 0.35).setStroke()
            path.lineWidth = 0.5
            path.stroke()
            text.draw(at: NSPoint(x: rect.minX + 4, y: rect.midY - size.height / 2),
                      withAttributes: [.font: font, .foregroundColor: NSColor.black])
            x = rect.maxX + 4
        }
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let color: NSColor = backgroundStyle == .emphasized ? .white : .labelColor
        (commit.subject as NSString).draw(in: NSRect(x: x, y: bounds.midY - 8, width: max(0, bounds.width - x - 2), height: 16),
                                          withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: color, .paragraphStyle: style])
    }
}

/// Журнал: граф фиксаций, под ним сообщение и файлы выбранной.
final class LogController: ToolWindow, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate, NSSearchFieldDelegate {
    private static let limit = 3000
    private let repo: String
    private let specs: [String]
    private var all: [Commit] = []
    private var commits: [Commit] = []
    private var graph: [GraphRow] = []
    private var files: [CommitFile] = []
    private var commitTable: NSTableView!
    private var fileTable: NSTableView!
    private var details: NSTextView!
    private let search = NSSearchField()
    private let allBranches = UI.check(L.t("Все ветки", "All Branches"))
    private let countLabel = UI.label("", color: .secondaryLabelColor)
    private let split = NSSplitView()
    private var loadID = 0
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    init(repo: String, specs: [String]) {
        self.repo = repo
        self.specs = specs
        let scope = specs.isEmpty ? repo : repo + "/" + specs[0]
        super.init(title: ToolWindow.title(scope, L.t("Журнал", "Log Messages")), size: NSSize(width: 980, height: 700))

        let (commitScroll, commitTable) = UI.table([
            ("graph", L.t("Граф", "Graph"), 90), ("message", L.t("Сообщение", "Message"), 520),
            ("author", L.t("Автор", "Author"), 150), ("date", L.t("Дата", "Date"), 130),
        ], flex: 1)
        commitTable.allowsMultipleSelection = false
        commitTable.intercellSpacing = NSSize(width: 6, height: 0)
        let (fileScroll, fileTable) = UI.table([
            ("path", L.t("Путь", "Path"), 600), ("status", L.t("Действие", "Status"), 140),
        ])
        fileTable.allowsMultipleSelection = false
        let (detailScroll, details) = UI.textView(editable: false)
        self.commitTable = commitTable
        self.fileTable = fileTable
        self.details = details
        for table in [commitTable, fileTable] {
            table.dataSource = self
            table.delegate = self
        }
        fileTable.target = self
        fileTable.doubleAction = #selector(openFileDiff)
        let menu = NSMenu()
        menu.delegate = self
        commitTable.menu = menu

        split.isVertical = false
        split.dividerStyle = .thin
        split.translatesAutoresizingMaskIntoConstraints = false
        for view in [commitScroll, detailScroll, fileScroll] {
            split.addArrangedSubview(view)
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true
        }
        split.setContentHuggingPriority(.init(1), for: .vertical)
        // Удержание размера слабее перетаскивания разделителя (490), иначе разделители не двигаются.
        // У всех трёх оно одинаковое: разделитель меняет две соседние панели, окно — все три поровну.
        split.setHoldingPriority(.init(260), forSubviewAt: 0)
        split.setHoldingPriority(.init(260), forSubviewAt: 1)
        split.setHoldingPriority(.init(260), forSubviewAt: 2)

        search.placeholderString = L.t("Поиск по сообщению, автору, хешу", "Filter by message, author, SHA-1")
        search.delegate = self
        search.translatesAutoresizingMaskIntoConstraints = false
        let content = UI.column([search, split])
        search.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        split.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        allBranches.target = self
        allBranches.action = #selector(reload)

        install(content, buttons: [ClosureButton(L.t("Обновить", "Refresh")) { [weak self] in self?.reload() }, okButton],
                leading: [allBranches, countLabel])
        watch(repo) { [weak self] in self?.reload() }
        reload()
        // Начальные высоты нижних панелей. Нужны только для первой раскладки: дальше размеры держит сам
        // разделитель, а оставшись, эти ограничения возвращали бы панели на место после перетаскивания.
        let initial = [(detailScroll, CGFloat(130)), (fileScroll, CGFloat(170))].map { view, height in
            let preferred = view.heightAnchor.constraint(equalToConstant: height)
            preferred.priority = NSLayoutConstraint.Priority(300)
            preferred.isActive = true
            return preferred
        }
        DispatchQueue.main.async { [split] in
            split.window?.layoutIfNeeded()
            let heights = split.arrangedSubviews.map(\.frame.height)
            NSLayoutConstraint.deactivate(initial)
            guard heights.count == 3 else { return }
            split.setPosition(heights[0], ofDividerAt: 0)
            split.setPosition(heights[0] + split.dividerThickness + heights[1], ofDividerAt: 1)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Загрузка

    @objc private func reload() {
        let repo = self.repo, specs = self.specs, all = allBranches.state == .on
        loadID += 1
        let id = loadID
        let selected = commitTable.selectedRow >= 0 ? commits[commitTable.selectedRow].hash : nil
        Git.background({ Git.log(repo, all: all, specs: specs, limit: LogController.limit) }) { [weak self] commits in
            guard let self, id == self.loadID else { return }
            self.all = commits
            self.applyFilter(select: selected)
        }
    }

    private func applyFilter(select: String? = nil) {
        let query = search.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        if query.isEmpty {
            commits = all
            // При отборе по пути родители в выдаче не подряд — граф был бы обманом.
            graph = specs.isEmpty ? Git.graph(commits) : []
        } else {
            commits = all.filter {
                $0.subject.lowercased().contains(query) || $0.author.lowercased().contains(query) || $0.hash.hasPrefix(query)
            }
            graph = []
        }
        let lanes = graph.prefix(400).map(\.width).max() ?? 1
        commitTable.tableColumns[0].width = min(220, max(40, CGFloat(lanes) * laneWidth + 8))
        commitTable.reloadData()
        countLabel.stringValue = all.count >= LogController.limit
            ? L.t("Показаны первые \(commits.count) фиксаций", "Showing the first \(commits.count) commits")
            : L.t("Фиксаций: \(commits.count)", "\(commits.count) commit(s)")
        let row = select.flatMap { hash in commits.firstIndex { $0.hash == hash } } ?? (commits.isEmpty ? -1 : 0)
        if row >= 0 { commitTable.selectRowIndexes([row], byExtendingSelection: false) }
        showDetails()
    }

    func controlTextDidChange(_ obj: Notification) {
        applyFilter()
    }

    private var selectedCommit: Commit? {
        let row = commitTable.selectedRow
        return row >= 0 && row < commits.count ? commits[row] : nil
    }

    private func showDetails() {
        guard let commit = selectedCommit else {
            details.string = ""
            files = []
            fileTable.reloadData()
            return
        }
        let repo = self.repo
        Git.background({
            (Git.run(["show", "-s", "--format=%B", commit.hash], in: repo).trimmed, Git.files(of: commit, in: repo))
        }) { [weak self] body, files in
            guard let self, self.selectedCommit?.hash == commit.hash else { return }
            self.details.string = "SHA-1: \(commit.hash)\n\(commit.author) <\(commit.email)>, \(self.dateFormatter.string(from: commit.date))\n\n\(body)"
            self.files = files
            self.fileTable.reloadData()
        }
    }

    // MARK: Таблицы

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === commitTable ? commits.count : files.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = tableColumn?.identifier.rawValue
        if tableView === fileTable {
            let file = files[row]
            let path = file.oldPath.map { "\($0) → \(file.path)" } ?? file.path
            return UI.textCell(id == "path" ? path : file.statusText, color: file.color)
        }
        let commit = commits[row]
        switch id {
        case "graph":
            let cell = GraphCell()
            cell.row = row < graph.count ? graph[row] : nil
            return cell
        case "message":
            let cell = MessageCell()
            cell.commit = commit
            return cell
        case "author": return UI.textCell(commit.author)
        case "date": return UI.textCell(dateFormatter.string(from: commit.date))
        default: return nil
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if (notification.object as? NSTableView) === commitTable { showDetails() }
    }

    @objc private func openFileDiff() {
        let row = fileTable.clickedRow
        guard row >= 0, let commit = selectedCommit else { return }
        DiffController.openCommit(repo: repo, commit: commit, file: files[row])
    }

    // MARK: Меню фиксации

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = commitTable.clickedRow
        guard row >= 0 else { return }
        let commit = commits[row], repo = self.repo
        let short = String(commit.hash.prefix(8))
        menu.addItem(ClosureMenuItem(L.t("Переключиться на эту версию…", "Switch/Checkout to this..."), glyph: .switchBranch) {
            SwitchDialog(repo: repo, preset: commit.hash).present()
        })
        menu.addItem(ClosureMenuItem(L.t("Создать ветку от этой версии…", "Create Branch at this version..."), glyph: .branch) {
            BranchDialog(repo: repo, preset: commit.hash).present()
        })
        menu.addItem(ClosureMenuItem(L.t("Создать метку на этой версии…", "Create Tag at this version..."), glyph: .tag) {
            TagDialog(repo: repo, preset: commit.hash).present()
        })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(L.t("Сбросить «\(Git.headName(repo))» на эту версию…", "Reset \"\(Git.headName(repo))\" to this..."), glyph: .revert) {
            ResetDialog(repo: repo, commit: commit).present()
        })
        menu.addItem(ClosureMenuItem(L.t("Отменить изменения этой фиксации", "Revert change by this commit")) {
            guard UI.confirm(L.t("Отменить изменения фиксации \(short)?", "Revert the change made by \(short)?"),
                             info: L.t("Будет создана новая фиксация, обратная этой.\n\n", "A new commit that undoes it will be created.\n\n") + commit.subject,
                             ok: L.t("Отменить изменения", "Revert")) else { return }
            ProgressController.run(title: "Revert", dir: repo, steps: [["revert", "--no-edit", commit.hash]])
        })
        menu.addItem(ClosureMenuItem(L.t("Перенести эту фиксацию сюда (cherry-pick)", "Cherry Pick this commit...")) {
            ProgressController.run(title: "Cherry Pick", dir: repo, steps: [["cherry-pick", commit.hash]])
        })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(L.t("Скопировать SHA-1", "Copy SHA-1 to clipboard")) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(commit.hash, forType: .string)
        })
    }
}
