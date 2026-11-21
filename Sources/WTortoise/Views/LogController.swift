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
        let font = Win.font
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
        let color = Win.text
        (commit.subject as NSString).draw(in: NSRect(x: x, y: bounds.midY - 8, width: max(0, bounds.width - x - 2), height: 16),
                                          withAttributes: [.font: Win.font, .foregroundColor: color, .paragraphStyle: style])
    }
}

/// Столбец Actions: значки того, что фиксация делала с файлами, — изменяла, добавляла, удаляла, переименовывала.
private final class ActionsCell: NSView {
    var actions: Set<Character> = []

    override func draw(_ dirtyRect: NSRect) {
        var x: CGFloat = 3
        let y = bounds.midY - 6
        func disc(_ color: NSColor) -> NSRect {
            let rect = NSRect(x: x, y: y, width: 12, height: 12)
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
            x += 15
            return rect
        }
        func stroke(_ points: [NSPoint], _ width: CGFloat = 1.8) {
            let path = NSBezierPath()
            path.move(to: points[0])
            points.dropFirst().forEach(path.line)
            path.lineWidth = width
            path.lineCapStyle = .round
            NSColor.white.setStroke()
            path.stroke()
        }
        if actions.contains("M") {
            let r = disc(NSColor(hex: 0xD43A2F))
            stroke([NSPoint(x: r.midX, y: r.maxY - 2.6), NSPoint(x: r.midX, y: r.midY - 0.4)])
            stroke([NSPoint(x: r.midX, y: r.minY + 2.6), NSPoint(x: r.midX, y: r.minY + 2.5)])
        }
        if actions.contains("A") {
            let r = disc(NSColor(hex: 0x2F6FD4))
            stroke([NSPoint(x: r.minX + 2.8, y: r.midY), NSPoint(x: r.maxX - 2.8, y: r.midY)])
            stroke([NSPoint(x: r.midX, y: r.minY + 2.8), NSPoint(x: r.midX, y: r.maxY - 2.8)])
        }
        if actions.contains("D") {
            let r = disc(NSColor(hex: 0x8A1F1F))
            stroke([NSPoint(x: r.minX + 3.4, y: r.minY + 3.4), NSPoint(x: r.maxX - 3.4, y: r.maxY - 3.4)])
            stroke([NSPoint(x: r.minX + 3.4, y: r.maxY - 3.4), NSPoint(x: r.maxX - 3.4, y: r.minY + 3.4)])
        }
        if actions.contains("R") {
            let r = disc(NSColor(hex: 0x7A4BC4))
            stroke([NSPoint(x: r.minX + 2.8, y: r.midY), NSPoint(x: r.maxX - 3, y: r.midY)], 1.5)
            stroke([NSPoint(x: r.maxX - 5, y: r.midY + 2.2), NSPoint(x: r.maxX - 2.8, y: r.midY), NSPoint(x: r.maxX - 5, y: r.midY - 2.2)], 1.5)
        }
    }
}

/// Поле даты Windows: белая рамка, дата цифрами и уголок справа.
private final class WinDateBox: NSView {
    let picker = NSDatePicker()

    init(target: AnyObject, action: Selector) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        picker.datePickerStyle = .textField
        picker.datePickerElements = .yearMonthDay
        picker.isBordered = false
        picker.isBezeled = false
        picker.drawsBackground = false
        picker.font = Win.font
        // Дата как в оригинале: 2026-11-21.
        picker.locale = Locale(identifier: "sv_SE")
        picker.target = target
        picker.action = action
        picker.translatesAutoresizingMaskIntoConstraints = false
        addSubview(picker)
        NSLayoutConstraint.activate([
            picker.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            picker.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthAnchor.constraint(equalToConstant: 104), heightAnchor.constraint(equalToConstant: Win.buttonHeight),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ dirtyRect: NSRect) {
        Win.box(bounds, fill: .white, border: Win.fieldBorder)
        // Вид не перевёрнут: уголок остриём вниз рисуем со своими координатами.
        let path = NSBezierPath()
        let cx = bounds.maxX - 10, cy = bounds.midY
        path.move(to: NSPoint(x: cx - 3.5, y: cy + 1.5))
        path.line(to: NSPoint(x: cx, y: cy - 2))
        path.line(to: NSPoint(x: cx + 3.5, y: cy + 1.5))
        path.lineWidth = 1.2
        Win.text.setStroke()
        path.stroke()
    }
}

/// Журнал: граф фиксаций, под ним сообщение и файлы выбранной. Раскладка — как в окне Log Messages у TortoiseGit.
final class LogController: ToolWindow, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate, NSTextFieldDelegate {
    private static let limit = 3000
    private let repo: String
    private let specs: [String]
    private var all: [Commit] = []
    private var commits: [Commit] = []
    private var graph: [GraphRow] = []
    private var allFiles: [CommitFile] = []
    private var files: [CommitFile] = []
    private var stats: [String: (added: Int, removed: Int)] = [:]
    private var commitTable: NSTableView!
    private var fileTable: NSTableView!
    private var details: NSTextView!
    private let search = UI.field(placeholder: L.t("Поиск: сообщение, автор, SHA-1", "Messages, authors, SHA-1"), width: 150)
    private let filterPaths = UI.field(placeholder: L.t("Отбор по путям", "Filter paths"), width: 260)
    private let allBranches = UI.check(L.t("Все ветки", "All Branches"))
    private let wholeProject = UI.check(L.t("Показать весь проект", "Show Whole Project"))
    private let statusLabel = UI.label("")
    private let jump = UI.popup(["Author Email", "Parent 1", "Parent 2"])
    private var fromBox: WinDateBox!
    private var toBox: WinDateBox!
    /// Даты заданы человеком — после перечитывания журнала не сбрасываем их на весь диапазон.
    private var datesTouched = false
    private var firstParent = false
    private var noMerges = false
    private var showTags = true, showLocal = true, showRemote = true
    private let split = NSSplitView()
    private var loadID = 0
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    init(repo: String, specs: [String]) {
        self.repo = repo
        self.specs = specs
        let scope = specs.isEmpty ? repo : repo + "/" + specs[0]
        super.init(title: ToolWindow.title(scope, L.t("Журнал", "Log Messages")), size: NSSize(width: 980, height: 700))

        let (commitScroll, commitTable) = UI.table([
            ("graph", L.t("Граф", "Graph"), 90), ("sha", "SHA-1", 72), ("actions", L.t("Действия", "Actions"), 62),
            ("message", L.t("Сообщение", "Message"), 420), ("author", L.t("Автор", "Author"), 140), ("date", L.t("Дата", "Date"), 150),
        ], flex: 3)
        commitTable.allowsMultipleSelection = false
        let (fileScroll, fileTable) = UI.table([
            ("path", L.t("Путь", "Path"), 420), ("ext", L.t("Расширение", "Extension"), 80), ("status", L.t("Состояние", "Status"), 90),
            ("added", L.t("Строк добавлено", "Lines added"), 100), ("removed", L.t("Строк убрано", "Lines removed"), 110),
        ])
        fileTable.allowsMultipleSelection = false
        let (detailScroll, details) = UI.textView(editable: false, mono: true)
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
        let fileMenu = NSMenu()
        fileMenu.delegate = self
        fileTable.menu = fileMenu

        // Верхняя строка: ветка, диапазон дат, поиск, переход между фиксациями.
        let branch = UI.label(Git.headName(repo), color: Win.link)
        fromBox = WinDateBox(target: self, action: #selector(datesChanged))
        toBox = WinDateBox(target: self, action: #selector(datesChanged))
        search.delegate = self
        filterPaths.delegate = self
        let up = ClosureButton("▲") { [weak self] in self?.jump(by: -1) }
        let down = ClosureButton("▼") { [weak self] in self?.jump(by: 1) }
        for button in [up, down] {
            button.constraints.forEach { $0.isActive = false }
            button.widthAnchor.constraint(equalToConstant: 24).isActive = true
        }
        // Поиск не растягивается: свободное место — между веткой и датами, как в оригинале.
        search.widthAnchor.constraint(equalToConstant: 190).isActive = true
        let topBar = UI.row([branch, UI.spacer(), UI.label(L.t("С:", "From:")), fromBox, UI.label(L.t("По:", "To:")), toBox,
                             search, jump, up, down], spacing: 6)

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

        // Под списками: строка состояния, слева флажки, посередине отбор по путям, справа Help.
        statusLabel.lineBreakMode = .byTruncatingTail
        wholeProject.state = .on
        wholeProject.isEnabled = !specs.isEmpty
        for box in [allBranches, wholeProject] {
            box.target = self
            box.action = #selector(reload)
        }
        let checks = UI.column([wholeProject, allBranches], spacing: 5)
        let help = ClosureButton(L.t("Справка", "Help")) { NSWorkspace.shared.open(URL(string: "https://github.com/opewix/wtortoise#readme")!) }
        let under = UI.row([checks, UI.spacer(), filterPaths, UI.spacer(), help], spacing: 8)
        under.alignment = .top
        let content = UI.column([topBar, split, statusLabel, under], spacing: 6)
        // Растягиваются списки, а не строки вокруг них.
        for view in [topBar, under] { view.setHuggingPriority(.required, for: .vertical) }
        checks.setHuggingPriority(.required, for: .vertical)
        statusLabel.setContentHuggingPriority(.required, for: .vertical)
        for view in [topBar, split, statusLabel, under] as [NSView] {
            view.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }

        let refresh = ClosureButton(L.t("Обновить", "Refresh")) { [weak self] in self?.reload() }
        let statistics = ClosureButton(L.t("Статистика", "Statistics")) { [weak self] in self?.showStatistics() }
        let walk = WinSplitButton(menuTitle: L.t("Обход", "Walk Behaviour")) { [weak self] in self?.walkItems() ?? [] }
        let view = WinSplitButton(menuTitle: L.t("Вид", "View")) { [weak self] in self?.viewItems() ?? [] }
        for button in [refresh, statistics] { button.widthAnchor.constraint(greaterThanOrEqualToConstant: 110).isActive = true }
        install(content, buttons: [okButton], leading: [refresh, statistics, walk, view])
        watch(repo) { [weak self] in self?.reload() }
        reload()
        // Начальные высоты нижних панелей. Нужны только для первой раскладки: дальше размеры держит сам
        // разделитель, а оставшись, эти ограничения возвращали бы панели на место после перетаскивания.
        let initial = [(detailScroll, CGFloat(120)), (fileScroll, CGFloat(120))].map { view, height in
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
        let repo = self.repo, all = allBranches.state == .on
        // «Show Whole Project» снимает отбор по папке или файлу, на которых открыт журнал.
        let specs = wholeProject.state == .on && wholeProject.isEnabled ? [] : self.specs
        let firstParent = self.firstParent, noMerges = self.noMerges
        loadID += 1
        let id = loadID
        let selected = selectedCommit?.hash
        Git.background({
            Git.log(repo, all: all, specs: specs, limit: LogController.limit, firstParent: firstParent, noMerges: noMerges)
        }) { [weak self] commits in
            guard let self, id == self.loadID else { return }
            self.all = commits
            if !self.datesTouched, let newest = commits.map(\.date).max(), let oldest = commits.map(\.date).min() {
                self.fromBox.picker.dateValue = oldest
                self.toBox.picker.dateValue = newest
            }
            self.applyFilter(select: selected)
        }
    }

    @objc private func datesChanged() {
        datesTouched = true
        applyFilter(select: selectedCommit?.hash)
    }

    /// Журнал показан целиком и по порядку — только тогда граф честен.
    private var unfiltered: Bool { commits.count == all.count }

    private func applyFilter(select: String? = nil) {
        let query = search.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        let calendar = Calendar.current
        let from = calendar.startOfDay(for: fromBox.picker.dateValue)
        let to = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: toBox.picker.dateValue)) ?? .distantFuture
        commits = all.filter { commit in
            guard !datesTouched || (commit.date >= from && commit.date < to) else { return false }
            return query.isEmpty || commit.subject.lowercased().contains(query) || commit.author.lowercased().contains(query)
                || commit.email.lowercased().contains(query) || commit.hash.hasPrefix(query)
        }
        // При отборе родители в выдаче не подряд — граф был бы обманом.
        let pathFiltered = !(wholeProject.state == .on) && !specs.isEmpty
        graph = unfiltered && !pathFiltered && !noMerges ? Git.graph(commits) : []
        let lanes = graph.prefix(400).map(\.width).max() ?? 1
        commitTable.tableColumns[0].width = min(220, max(40, CGFloat(lanes) * laneWidth + 8))
        commitTable.reloadData()
        let row = select.flatMap { hash in commits.firstIndex { $0.hash == hash } } ?? (commits.isEmpty ? -1 : 0)
        if row >= 0 { commitTable.selectRowIndexes([row], byExtendingSelection: false) }
        showDetails()
    }

    func controlTextDidChange(_ obj: Notification) {
        if (obj.object as? NSTextField) === filterPaths {
            applyPathFilter()
        } else {
            applyFilter(select: selectedCommit?.hash)
        }
    }

    private var selectedCommit: Commit? {
        let row = commitTable?.selectedRow ?? -1
        return row >= 0 && row < commits.count ? commits[row] : nil
    }

    private func showDetails() {
        updateStatus()
        guard let commit = selectedCommit else {
            details.string = ""
            allFiles = []
            applyPathFilter()
            return
        }
        let repo = self.repo
        Git.background({
            (Git.run(["show", "-s", "--format=%B", commit.hash], in: repo).trimmed, Git.files(of: commit, in: repo),
             Git.numstat(of: commit, in: repo))
        }) { [weak self] body, files, stats in
            guard let self, self.selectedCommit?.hash == commit.hash else { return }
            // Как в оригинале: SHA-1, пустая строка, тема жирным со звёздочкой, затем остальной текст.
            let lines = body.components(separatedBy: "\n")
            let text = NSMutableAttributedString(string: "SHA-1: \(commit.hash)\n\n", attributes: [.font: Win.monoFont, .foregroundColor: Win.text])
            let bold = NSFontManager.shared.convert(Win.monoFont, toHaveTrait: .boldFontMask)
            text.append(NSAttributedString(string: "* " + (lines.first ?? ""), attributes: [.font: bold, .foregroundColor: Win.text]))
            let rest = lines.dropFirst().joined(separator: "\n")
            if !rest.isEmpty {
                text.append(NSAttributedString(string: "\n" + rest, attributes: [.font: Win.monoFont, .foregroundColor: Win.text]))
            }
            self.details.textStorage?.setAttributedString(text)
            self.allFiles = files
            self.stats = stats
            self.applyPathFilter()
        }
    }

    private func applyPathFilter() {
        let query = filterPaths.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        files = query.isEmpty ? allFiles : allFiles.filter { $0.path.lowercased().contains(query) }
        fileTable.reloadData()
        updateStatus()
    }

    /// Строка состояния под списками — тем же текстом, что в оригинале.
    private func updateStatus() {
        guard let first = commits.first, let last = commits.last else {
            statusLabel.stringValue = L.t("Фиксаций нет", "Showing 0 revision(s)")
            return
        }
        let selected = commitTable.selectedRow >= 0 ? 1 : 0
        let added = files.reduce(0) { $0 + (stats[$1.path]?.added ?? 0) }
        let removed = files.reduce(0) { $0 + (stats[$1.path]?.removed ?? 0) }
        let fromHash = String(last.hash.prefix(7)), toHash = String(first.hash.prefix(7))
        statusLabel.stringValue = L.t(
            "Показано фиксаций: \(commits.count), с \(fromHash) по \(toHash) — выбрано: \(selected), файлов: \(files.count); строк: \(added)(+) \(removed)(-)",
            "Showing \(commits.count) revision(s), from revision \(fromHash) to revision \(toHash) - \(selected) revision(s) selected, \(files.count) file(s); line: \(added)(+) \(removed)(-)")
    }

    // MARK: Переход между фиксациями

    /// Стрелки справа вверху: к соседней фиксации того же автора либо к родителю и обратно к потомку.
    private func jump(by step: Int) {
        guard let current = selectedCommit, let row = commits.firstIndex(where: { $0.hash == current.hash }) else { return }
        var target: Int?
        switch jump.indexOfSelectedItem {
        case 0:
            let range = step > 0 ? Array(commits.indices.dropFirst(row + 1)) : Array(commits.indices.prefix(row).reversed())
            target = range.first { commits[$0].email == current.email }
        default:
            let parent = jump.indexOfSelectedItem - 1
            if step > 0 {
                guard parent < current.parents.count else { return NSSound.beep() }
                target = commits.firstIndex { $0.hash == current.parents[parent] }
            } else {
                target = commits.prefix(row).lastIndex { $0.parents.count > parent && $0.parents[parent] == current.hash }
            }
        }
        guard let target else { return NSSound.beep() }
        commitTable.selectRowIndexes([target], byExtendingSelection: false)
        commitTable.scrollRowToVisible(target)
    }

    // MARK: Кнопки внизу

    private func toggleItem(_ title: String, _ on: Bool, _ flip: @escaping () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title, handler: flip)
        item.state = on ? .on : .off
        return item
    }

    private func walkItems() -> [NSMenuItem] {
        [toggleItem(L.t("Только первый родитель", "First Parent"), firstParent) { [weak self] in
            self?.firstParent.toggle()
            self?.reload()
        }, toggleItem(L.t("Без слияний", "No merges"), noMerges) { [weak self] in
            self?.noMerges.toggle()
            self?.reload()
        }]
    }

    private func viewItems() -> [NSMenuItem] {
        let labels = NSMenuItem(title: L.t("Ярлыки", "Labels"), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.addItem(toggleItem(L.t("Метки", "Tags"), showTags) { [weak self] in
            self?.showTags.toggle()
            self?.commitTable.reloadData()
        })
        submenu.addItem(toggleItem(L.t("Свои ветки", "Local branches"), showLocal) { [weak self] in
            self?.showLocal.toggle()
            self?.commitTable.reloadData()
        })
        submenu.addItem(toggleItem(L.t("Ветки серверов", "Remote branches"), showRemote) { [weak self] in
            self?.showRemote.toggle()
            self?.commitTable.reloadData()
        })
        labels.submenu = submenu
        return [labels]
    }

    /// Ярлыки фиксации с учётом того, что включено в «View → Labels».
    private func visibleRefs(_ commit: Commit) -> [String] {
        commit.refs.filter { ref in
            if ref.hasPrefix("tag: ") { return showTags }
            if ref.hasPrefix("HEAD") { return showLocal }
            return ref.contains("/") && Git.remotes(repo).contains(where: { ref.hasPrefix($0 + "/") }) ? showRemote : showLocal
        }
    }

    private func showStatistics() {
        var byAuthor: [String: Int] = [:]
        for commit in commits { byAuthor[commit.author, default: 0] += 1 }
        let width = byAuthor.keys.map(\.count).max() ?? 10
        var text = L.t("Фиксаций: \(commits.count), авторов: \(byAuthor.count)\n\n", "Commits: \(commits.count), authors: \(byAuthor.count)\n\n")
        for (author, count) in byAuthor.sorted(by: { $0.value > $1.value }) {
            text += author.padding(toLength: width + 2, withPad: " ", startingAt: 0) + String(count) + "\n"
        }
        StatisticsWindow(repo: repo, text: text).present()
    }

    // MARK: Таблицы

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === commitTable ? commits.count : files.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = tableColumn?.identifier.rawValue
        if tableView === fileTable {
            let file = files[row]
            switch id {
            case "path": return UI.textCell(file.oldPath.map { "\($0) → \(file.path)" } ?? file.path, color: file.color)
            case "ext": return UI.textCell(file.ext, color: file.color)
            case "status": return UI.textCell(file.statusText, color: file.color)
            case "added": return UI.textCell(stats[file.path].map { String($0.added) } ?? "", color: file.color, alignment: .right)
            case "removed": return UI.textCell(stats[file.path].map { String($0.removed) } ?? "", color: file.color, alignment: .right)
            default: return nil
            }
        }
        var commit = commits[row]
        switch id {
        case "graph":
            let cell = GraphCell()
            cell.row = row < graph.count ? graph[row] : nil
            return cell
        case "sha": return UI.textCell(String(commit.hash.prefix(8)) + "...")
        case "actions":
            let cell = ActionsCell()
            cell.actions = commit.actions
            return cell
        case "message":
            let cell = MessageCell()
            commit = Commit(hash: commit.hash, parents: commit.parents, author: commit.author, email: commit.email,
                            date: commit.date, refs: visibleRefs(commit), subject: commit.subject)
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

    // MARK: Меню

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if menu === fileTable.menu { return fileMenu(menu) }
        let row = commitTable.clickedRow
        guard row >= 0 else { return }
        let commit = commits[row], repo = self.repo
        let short = String(commit.hash.prefix(8))
        menu.addItem(ClosureMenuItem(L.t("Сравнить с рабочей копией", "Compare with working tree"), glyph: .diff) {
            PatchWindow(repo: repo, text: Git.run(["diff", commit.hash], in: repo).out).present()
        })
        menu.addItem(ClosureMenuItem(L.t("Показать изменения единой правкой", "Show changes as unified diff"), glyph: .diff) {
            PatchWindow(repo: repo, text: Git.run(["show", "--format=", commit.hash], in: repo).out).present()
        })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(L.t("Сбросить «\(Git.headName(repo))» на эту версию…", "Reset \"\(Git.headName(repo))\" to this..."), glyph: .revert) {
            ResetDialog(repo: repo, commit: commit).present()
        })
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
        menu.addItem(ClosureMenuItem(L.t("Скопировать сообщение", "Copy log message to clipboard")) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(Git.run(["show", "-s", "--format=%B", commit.hash], in: repo).trimmed, forType: .string)
        })
    }

    /// Меню файла в нижней панели.
    private func fileMenu(_ menu: NSMenu) {
        let row = fileTable.clickedRow
        guard row >= 0, row < files.count, let commit = selectedCommit else { return }
        let file = files[row], repo = self.repo
        menu.addItem(ClosureMenuItem(L.t("Сравнить с базой", "Compare with base"), glyph: .diff) {
            DiffController.openCommit(repo: repo, commit: commit, file: file)
        })
        menu.addItem(ClosureMenuItem(Command.log.title, glyph: .log) {
            LogController(repo: repo, specs: [file.path]).present()
        })
        if file.status.first != "D" {
            menu.addItem(ClosureMenuItem(Command.blame.title, glyph: .blame) {
                BlameController.open(repo: repo, path: file.path)
            })
        }
        menu.addItem(.separator())
        let url = URL(fileURLWithPath: repo + "/" + file.path)
        menu.addItem(ClosureMenuItem(L.t("Открыть", "Open")) { NSWorkspace.shared.open(url) })
        menu.addItem(ClosureMenuItem(L.t("Показать в Finder", "Explore to")) { NSWorkspace.shared.activateFileViewerSelecting([url]) })
        menu.addItem(ClosureMenuItem(L.t("Скопировать путь", "Copy paths to clipboard")) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.path, forType: .string)
        })
    }
}

/// Окно «Statistics»: сколько фиксаций у каждого автора в показанном журнале.
final class StatisticsWindow: ToolWindow {
    init(repo: String, text: String) {
        super.init(title: ToolWindow.title(repo, L.t("Статистика", "Statistics")), size: NSSize(width: 460, height: 360))
        let (scroll, view) = UI.textView(editable: false, mono: true)
        view.string = text
        install(scroll, buttons: [closeButton])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
