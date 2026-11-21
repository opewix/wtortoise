import AppKit

/// Слово-ссылка в строке «Check: All None…» — жирный текст без рамки, серый, когда отмечать нечего.
private func link(_ title: String, _ handler: @escaping () -> Void) -> ClosureButton {
    let button = ClosureButton(title, handler: handler)
    button.look = .link
    button.constraints.forEach { $0.isActive = false }
    return button
}

/// Окно фиксации: сообщение и список изменённых файлов с отметками.
final class CommitController: ToolWindow, NSTextViewDelegate {
    private let repo: String
    private let specs: [String]
    private let list: FileListView
    private let message: NSTextView
    private let amend = UI.check(L.t("Исправить последнюю фиксацию", "Amend Last Commit"))
    private let wholeProject = UI.check(L.t("Показать весь проект", "Show Whole Project"))
    private let newBranch = UI.check(L.t("новая ветка", "new branch"))
    private let newBranchName = UI.field(placeholder: L.t("имя ветки", "branch name"), width: 180)
    private let split = NSSplitView()
    private var keyMonitor: Any?
    private let showUnversioned = UI.check(L.t("Показывать файлы не под версией", "Show Unversioned Files"), on: Settings.showUnversioned)
    private let branchLabel = UI.label("", bold: true)
    private let countLabel = UI.label("", color: .secondaryLabelColor)
    private var all: [FileChange] = []
    private let setAuthorDate = UI.check(L.t("Задать дату автора", "Set author date"))
    private let authorDate = UI.field(width: 150)
    private let setAuthor = UI.check(L.t("Задать автора", "Set author"))
    private let author = UI.field(placeholder: "Name <email>", width: 220)
    private let messageOnly = UI.check(L.t("Только сообщение", "Message only"))
    private let caretLabel = UI.label("", color: Win.text)
    /// Ссылки «Check:» с условием, по которому каждая отмечает файлы; условие же решает, активна ли ссылка.
    private var checkLinks: [(button: ClosureButton, match: (FileChange) -> Bool)] = []

    init(repo: String, specs: [String]) {
        self.repo = repo
        self.specs = specs
        list = FileListView(repo: repo, checkable: true)
        let (messageScroll, message) = UI.textView(editable: true)
        self.message = message
        super.init(title: ToolWindow.title(repo, L.t("Фиксация", "Commit")), size: NSSize(width: 780, height: 620))

        newBranchName.isHidden = true
        // Раскладка — как в окне Commit у TortoiseGit: строка ветки, группа «Message», группа «Changes made»,
        // под ними два флажка и ряд кнопок.
        branchLabel.font = Win.font
        newBranchName.isHidden = true
        let top = UI.row([UI.label(L.t("Фиксация в:", "Commit to:")), branchLabel, newBranch, newBranchName, UI.spacer()], spacing: 12)

        // Сообщение — моноширинным шрифтом; орфография встроенная в macOS.
        message.font = Win.monoFont
        message.isContinuousSpellCheckingEnabled = true
        message.isGrammarCheckingEnabled = false
        message.delegate = self
        caretLabel.alignment = .right
        for field in [authorDate, author] { field.isHidden = true }
        let signOff = ClosureButton(L.t("Добавить Signed-off-by", "Add Signed-off-by")) { [weak self] in self?.addSignedOffBy() }
        signOff.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        let caretRow = UI.row([UI.spacer(), caretLabel])
        let dateRow = UI.row([setAuthorDate, authorDate, UI.spacer()])
        let authorRow = UI.row([setAuthor, author, UI.spacer(), signOff])
        let messageBox = UI.column([messageScroll, caretRow, amend, dateRow, authorRow], spacing: 6)
        for view in [messageScroll, caretRow, dateRow, authorRow] as [NSView] {
            view.widthAnchor.constraint(equalTo: messageBox.widthAnchor).isActive = true
        }
        let messageGroup = WinGroupBox(L.t("Сообщение:", "Message:"), content: messageBox)

        func check(_ title: String, _ match: @escaping (FileChange) -> Bool) -> ClosureButton {
            let button = link(title) { [weak self] in self?.list.setChecked(match) }
            checkLinks.append((button, match))
            return button
        }
        let submodules = link(L.t("Подмодули", "Submodules")) {}
        submodules.isEnabled = false
        let checks = UI.row([
            UI.label(L.t("Отметить:", "Check:")),
            check(L.t("Все", "All")) { _ in true },
            link(L.t("Ничего", "None")) { [weak self] in self?.list.setChecked { _ in false } },
            check(L.t("Не под версией", "Unversioned")) { $0.kind == .untracked },
            check(L.t("Под версией", "Versioned")) { $0.kind != .untracked },
            check(L.t("Добавленные", "Added")) { $0.kind == .added },
            check(L.t("Удалённые", "Deleted")) { $0.kind == .deleted },
            check(L.t("Изменённые", "Modified")) { $0.kind == .modified },
            check(L.t("Файлы", "Files")) { _ in true },
            submodules,
            UI.spacer(),
        ], spacing: 7)
        // Подмодули программа не разбирает: флажок на месте, но недоступен.
        let noSubmodules = UI.check(L.t("Не отмечать подмодули сами", "Do not autoselect submodules"), on: true)
        noSubmodules.isEnabled = false
        let viewPatch = link(L.t("Показать правку>>", "View Patch>>")) { [weak self] in self?.viewPatch() }
        viewPatch.linkColor = Win.link
        viewPatch.linkBold = false
        let underList = UI.row([showUnversioned, UI.spacer(), countLabel])
        let underList2 = UI.row([noSubmodules, UI.spacer(), viewPatch])
        let changesBox = UI.column([checks, list, underList, underList2], spacing: 6)
        for view in [checks, list, underList, underList2] as [NSView] {
            view.widthAnchor.constraint(equalTo: changesBox.widthAnchor).isActive = true
        }
        let changesGroup = WinGroupBox(L.t("Изменения (двойной щелчок по файлу — сравнение):", "Changes made (double-click on file for diff):"),
                                       content: changesBox)

        // Граница между группами перетаскивается, как в оригинале.
        let upper = UI.column([top, messageGroup], spacing: 6)
        let lower = UI.column([changesGroup, wholeProject], spacing: 6)
        upper.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 3, right: 0)
        lower.edgeInsets = NSEdgeInsets(top: 3, left: 0, bottom: 0, right: 0)
        top.widthAnchor.constraint(equalTo: upper.widthAnchor).isActive = true
        messageGroup.widthAnchor.constraint(equalTo: upper.widthAnchor).isActive = true
        changesGroup.widthAnchor.constraint(equalTo: lower.widthAnchor).isActive = true
        messageScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
        list.heightAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true
        split.isVertical = false
        split.dividerStyle = .thin
        split.translatesAutoresizingMaskIntoConstraints = false
        split.addArrangedSubview(upper)
        split.addArrangedSubview(lower)
        // Удержание слабее перетаскивания границы (490); при смене размера окна растёт список, а не сообщение.
        split.setHoldingPriority(.init(260), forSubviewAt: 0)
        split.setHoldingPriority(.init(250), forSubviewAt: 1)
        let content = split
        // Начальная высота верхней панели — только для первой раскладки, дальше её держит разделитель.
        let initial = upper.heightAnchor.constraint(equalToConstant: 215)
        initial.priority = NSLayoutConstraint.Priority(300)
        initial.isActive = true
        DispatchQueue.main.async { [split] in
            split.window?.layoutIfNeeded()
            let height = split.arrangedSubviews.first?.frame.height ?? 215
            initial.isActive = false
            split.setPosition(height, ofDividerAt: 0)
        }

        amend.target = self
        amend.action = #selector(amendChanged)
        showUnversioned.target = self
        showUnversioned.action = #selector(unversionedChanged)
        wholeProject.state = Settings.wholeProject(repo) || specs.isEmpty ? .on : .off
        // Окно открыто на всём хранилище — флажок стоит и недоступен, как в оригинале.
        wholeProject.isEnabled = !specs.isEmpty
        wholeProject.target = self
        wholeProject.action = #selector(wholeProjectChanged)
        newBranch.target = self
        newBranch.action = #selector(newBranchChanged)
        for box in [setAuthorDate, setAuthor, messageOnly] {
            box.target = self
            box.action = #selector(optionChanged(_:))
        }
        list.onCheckedChange = { [weak self] in self?.updateCount() }
        updateCaret()

        install(content, buttons: [
            WinSplitButton([
                (L.t("Зафиксировать", "Commit"), { [weak self] in self?.commit(push: false) }),
                (L.t("Зафиксировать и продолжить", "ReCommit"), { [weak self] in self?.commit(push: false, stay: true) }),
                (L.t("Зафиксировать и отправить", "Commit & push"), { [weak self] in self?.commit(push: true) }),
            ], key: "\r"),
            cancelButton,
            ClosureButton(L.t("Справка", "Help")) { NSWorkspace.shared.open(URL(string: "https://github.com/opewix/wtortoise#readme")!) },
        ], leading: [messageOnly])
        window?.initialFirstResponder = message
        // ⌘↩ и ⌃↩ фиксируют прямо из поля сообщения, где обычный ↩ — новая строка.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window, event.keyCode == 36 || event.keyCode == 76,
                  !event.modifierFlags.intersection([.command, .control]).isEmpty else { return event }
            self.commit(push: false)
            return nil
        }
        watch(repo) { [weak self] in self?.reload() }
        reload()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func windowWillClose(_ notification: Notification) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        super.windowWillClose(notification)
    }

    private func reload() {
        branchLabel.stringValue = Git.headName(repo)
        all = Git.status(repo, specs: wholeProject.state == .on ? [] : specs)
        apply(stats: Git.numstat(repo))
    }

    private func apply(stats: [String: (added: Int, removed: Int)]? = nil) {
        let visible = showUnversioned.state == .on ? all : all.filter { $0.kind != .untracked }
        list.show(visible, stats: stats ?? Git.numstat(repo)) { $0.kind != .untracked }
    }

    /// Недавние сообщения и список файлов — в контекстном меню поля сообщения, как в оригинале.
    func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
        menu.insertItem(.separator(), at: 0)
        menu.insertItem(ClosureMenuItem(L.t("Вставить список файлов", "Paste filename list")) { [weak self] in self?.pasteFilenames() }, at: 0)
        let recent = NSMenuItem(title: L.t("Вставить недавнее сообщение", "Paste Recent messages"), action: nil, keyEquivalent: "")
        let messages = Settings.recentMessages(repo)
        if !messages.isEmpty {
            let submenu = NSMenu()
            for text in messages {
                let first = text.split(separator: "\n").first.map(String.init) ?? text
                submenu.addItem(ClosureMenuItem(first.count > 70 ? String(first.prefix(70)) + "…" : first) { [weak self] in
                    self?.message.string = text
                    self?.updateCaret()
                })
            }
            recent.submenu = submenu
        }
        menu.insertItem(recent, at: 0)
        return menu
    }

    func textViewDidChangeSelection(_ notification: Notification) { updateCaret() }

    /// «строка/столбец» курсора под полем сообщения.
    private func updateCaret() {
        let text = message.string as NSString
        let location = min(message.selectedRange().location, text.length)
        let before = text.substring(to: location)
        let line = before.components(separatedBy: "\n").count
        let column = location - (before as NSString).range(of: "\n", options: .backwards).upperBound(orZero: true) + 1
        caretLabel.stringValue = "\(line)/\(column)"
    }

    @objc private func optionChanged(_ sender: NSButton) {
        authorDate.isHidden = setAuthorDate.state != .on
        author.isHidden = setAuthor.state != .on
        if sender === setAuthorDate, setAuthorDate.state == .on, authorDate.stringValue.isEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            authorDate.stringValue = formatter.string(from: Date())
        }
        if sender === setAuthor, setAuthor.state == .on, author.stringValue.isEmpty {
            let name = Git.run(["config", "user.name"], in: repo).trimmed, email = Git.run(["config", "user.email"], in: repo).trimmed
            if !name.isEmpty { author.stringValue = "\(name) <\(email)>" }
        }
        // «Только сообщение»: файлы в фиксацию не идут, список недоступен.
        list.alphaValue = messageOnly.state == .on ? 0.45 : 1
    }

    /// Правка отмеченных файлов одним текстом, как «View Patch>>».
    private func viewPatch() {
        let files = list.checkedFiles.filter { $0.kind != .untracked }
        guard !files.isEmpty else {
            return UI.alert(L.t("Не отмечено ни одного файла под версией.", "No versioned files are selected."), style: .informational)
        }
        let diff = Git.run(["diff", "HEAD", "--"] + files.flatMap(\.pathspecs), in: repo).out
        PatchWindow(repo: repo, text: diff).present()
    }

    private func updateCount() {
        for item in checkLinks { item.button.isEnabled = list.files.contains(where: item.match) }
        countLabel.stringValue = L.t("Отмечено файлов: \(list.checked.count) из \(list.files.count)",
                                     "\(list.checked.count) files selected, \(list.files.count) files total")
    }

    @objc private func unversionedChanged() {
        Settings.showUnversioned = showUnversioned.state == .on
        apply()
    }

    @objc private func wholeProjectChanged() {
        Settings.setWholeProject(wholeProject.state == .on, for: repo)
        reload()
    }

    @objc private func newBranchChanged() {
        newBranchName.isHidden = newBranch.state != .on
        if newBranch.state == .on { window?.makeFirstResponder(newBranchName) }
    }

    /// Дописывает в конец сообщения «Signed-off-by: Имя <почта>» из настроек git; повторно не добавляет.
    private func addSignedOffBy() {
        let name = Git.run(["config", "user.name"], in: repo).trimmed
        let email = Git.run(["config", "user.email"], in: repo).trimmed
        guard !name.isEmpty, !email.isEmpty else {
            return UI.alert(L.t("В настройках git не заданы имя и почта.", "User name and email are not set in the git config."),
                            info: "git config --global user.name …\ngit config --global user.email …")
        }
        let line = "Signed-off-by: \(name) <\(email)>"
        let text = message.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.contains(line) else { return }
        // Перед первой такой строкой — пустая; следующие подписи идут вплотную.
        let lastLine = text.split(separator: "\n").last.map(String.init) ?? ""
        message.string = text.isEmpty ? "\n\n" + line : text + (lastLine.hasPrefix("Signed-off-by:") ? "\n" : "\n\n") + line
    }

    /// Вставляет в сообщение пути отмеченных файлов, по одному в строке.
    private func pasteFilenames() {
        let names = list.checkedFiles.map(\.path).joined(separator: "\n")
        guard !names.isEmpty else { return }
        message.insertText(names + "\n", replacementRange: message.selectedRange())
    }

    @objc private func amendChanged() {
        guard amend.state == .on, message.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        message.string = Git.run(["log", "-1", "--format=%B"], in: repo).trimmed
    }

    /// - Parameter stay: «ReCommit» — окно остаётся открытым для следующей фиксации.
    private func commit(push: Bool, stay: Bool = false) {
        let text = message.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let files = list.checkedFiles
        let isAmend = amend.state == .on
        guard !text.isEmpty else {
            return UI.alert(L.t("Введите сообщение фиксации.", "Please enter a commit message."))
        }
        let onlyMessage = messageOnly.state == .on
        if onlyMessage && !isAmend && !Git.run(["diff", "--cached", "--quiet"], in: repo).ok {
            return UI.alert(L.t("В индексе git уже лежат изменения.", "There are staged changes in the git index."),
                            info: L.t("Фиксация «только сообщение» захватила бы и их. Снимите флажок или уберите их из индекса.",
                                      "A message-only commit would take them too. Clear the box or unstage them first."))
        }
        guard !files.isEmpty || isAmend || onlyMessage else {
            return UI.alert(L.t("Не отмечено ни одного файла.", "No files are selected."),
                            info: L.t("Отметьте файлы, которые войдут в фиксацию.", "Check the files to include in the commit."))
        }
        let messageFile = FileManager.default.temporaryDirectory.appendingPathComponent("wtortoise-commit-\(UUID().uuidString).txt")
        do {
            try (text + "\n").write(to: messageFile, atomically: true, encoding: .utf8)
        } catch {
            return UI.alert(error.localizedDescription)
        }

        var steps: [[String]] = []
        if newBranch.state == .on {
            let name = newBranchName.stringValue.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else {
                return UI.alert(L.t("Введите имя новой ветки.", "Please enter a name for the new branch."))
            }
            // Ветка создаётся от текущей, изменения рабочей копии переходят на неё.
            steps.append(["checkout", "-b", name])
        }
        Settings.remember(message: text, for: repo)
        var commit = ["commit", "-F", messageFile.path]
        if isAmend { commit.append("--amend") }
        if setAuthorDate.state == .on, !authorDate.stringValue.trimmingCharacters(in: .whitespaces).isEmpty {
            commit.append("--date=" + authorDate.stringValue.trimmingCharacters(in: .whitespaces))
        }
        if setAuthor.state == .on, !author.stringValue.trimmingCharacters(in: .whitespaces).isEmpty {
            commit.append("--author=" + author.stringValue.trimmingCharacters(in: .whitespaces))
        }
        let paths = onlyMessage ? [] : files.flatMap(\.pathspecs)
        if onlyMessage {
            // Только сообщение: при исправлении — прежнее содержимое с новым текстом, иначе пустая фиксация.
            commit.append(isAmend ? "--only" : "--allow-empty")
        } else if Git.isMerging(repo) {
            // Посреди слияния git не берёт фиксацию «только этих путей»: кладём отмеченное в индекс целиком.
            if !paths.isEmpty { steps.append(["add", "--"] + paths) }
        } else {
            let untracked = files.filter { $0.kind == .untracked }.map(\.path)
            if !untracked.isEmpty { steps.append(["add", "--"] + untracked) }
            // В фиксацию идут только отмеченные файлы, что бы ни лежало в индексе.
            commit.append("--only")
            if !paths.isEmpty { commit += ["--"] + paths }
        }
        steps.append(commit)

        let repo = self.repo, specs = self.specs
        let run = { [weak self] in
            ProgressController.run(
                title: L.t("Фиксация", "Commit"), dir: repo, steps: steps,
                extra: push || stay ? [] : [
                    (L.t("Ещё фиксация", "ReCommit"), { CommitController(repo: repo, specs: specs).present() }),
                    (L.t("Отправить…", "Push..."), { PushDialog(repo: repo).present() }),
                ],
                onFinish: { ok in
                    try? FileManager.default.removeItem(at: messageFile)
                    if ok && push { PushDialog(repo: repo).present() }
                    guard ok, stay, let self else { return }
                    // Готово к следующей фиксации: чистое сообщение, список перечитан слежением за хранилищем.
                    self.message.string = ""
                    self.amend.state = .off
                    self.newBranch.state = .off
                    self.newBranchName.stringValue = ""
                    self.newBranchName.isHidden = true
                })
        }
        // Сначала окно хода, потом закрываем это: программа выходит, когда окон не осталось.
        run()
        if !stay { close() }
    }
}

/// «Проверить изменения»: что изменено в рабочей копии. Раскладка — как у окна Working Tree в TortoiseGit.
final class StatusController: ToolWindow {
    private let repo: String
    private let specs: [String]
    private let list: FileListView
    private let summary = UI.label("")
    private let showUnversioned = UI.check(L.t("Показывать файлы не под версией", "Show unversioned files"), on: true)
    private let showFlagged = UI.check(L.t("Показывать файлы с флагом «не следить»", "Show ignore local changes flagged files"))
    private let showIgnored = UI.check(L.t("Показывать игнорируемые", "Show ignored files"))
    private let showStaged = UI.check(L.t("Показывать всё из индекса", "Show all staged files"), on: true)
    private let wholeProject = UI.check(L.t("Показать весь проект", "Show Whole Project"))
    private var all: [FileChange] = []

    init(repo: String, specs: [String]) {
        self.repo = repo
        self.specs = specs
        list = FileListView(repo: repo, checkable: false, lastModified: true)
        list.commitFromMenu = true
        super.init(title: ToolWindow.title(repo, L.t("Рабочая копия", "Working Tree")), size: NSSize(width: 900, height: 480))

        // Флажки, которых программа не поддерживает, стоят на месте, но недоступны.
        for box in [showFlagged, showIgnored, showStaged] { box.isEnabled = false }
        wholeProject.state = specs.isEmpty ? .on : .off
        wholeProject.isEnabled = !specs.isEmpty
        for box in [showUnversioned, wholeProject] {
            box.target = self
            box.action = #selector(reload)
        }
        summary.lineBreakMode = .byWordWrapping
        summary.maximumNumberOfLines = 2
        summary.preferredMaxLayoutWidth = 380
        let checks = UI.column([showUnversioned, showFlagged, showIgnored, showStaged, wholeProject], spacing: 3)
        let under = UI.row([checks, UI.spacer(), summary])
        under.alignment = .top
        let content = UI.column([list, under], spacing: 6)
        list.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        under.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        under.setHuggingPriority(.required, for: .vertical)
        checks.setHuggingPriority(.required, for: .vertical)
        // Столбец флажков не сжимается: уступает список.
        checks.setClippingResistancePriority(.required, for: .vertical)
        under.setClippingResistancePriority(.required, for: .vertical)
        for box in checks.arrangedSubviews { box.setContentCompressionResistancePriority(.required, for: .vertical) }

        let save = ClosureButton(L.t("Сохранить единой правкой", "Save unified diff")) { [weak self] in self?.saveDiff() }
        let stash = WinSplitButton([
            (L.t("Спрятать", "Stash"), { [repo] in StashDialog(repo: repo).present() }),
            (Command.stashPop.title, { [repo] in
                ProgressController.run(title: Command.stashPop.title, dir: repo, steps: [["stash", "pop"]])
            }),
        ])
        let commit = ClosureButton(L.t("Фиксация", "Commit")) { [weak self] in
            guard let self else { return }
            CommitController(repo: self.repo, specs: self.wholeProject.state == .on ? [] : self.specs).present()
        }
        let refresh = ClosureButton(L.t("Обновить", "Refresh")) { [weak self] in self?.reload() }
        save.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        for button in [commit, refresh] { button.widthAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true }
        install(content, buttons: [save, stash, commit, refresh, okButton])
        watch(repo) { [weak self] in self?.reload() }
        reload()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func reload() {
        all = Git.status(repo, specs: wholeProject.state == .on ? [] : specs)
        let stats = Git.numstat(repo)
        let shown = showUnversioned.state == .on ? all : all.filter { $0.kind != .untracked }
        list.show(shown, stats: stats) { _ in false }
        func count(_ kind: FileChange.Kind) -> Int { all.filter { $0.kind == kind }.count }
        let added = shown.reduce(0) { $0 + (stats[$1.path]?.added ?? 0) }
        let removed = shown.reduce(0) { $0 + (stats[$1.path]?.removed ?? 0) }
        // Тот же текст, что в оригинале справа под списком.
        summary.stringValue = L.t(
            "строк: \(added)(+) \(removed)(-) файлов: не под версией=\(count(.untracked)), изменено=\(count(.modified) + count(.renamed)), добавлено=\(count(.added)), удалено=\(count(.deleted)), конфликтов=\(count(.conflicted))",
            "line: \(added)(+) \(removed)(-) files: non-versioned=\(count(.untracked)), modified=\(count(.modified) + count(.renamed)), added=\(count(.added)), deleted=\(count(.deleted)), conflicted=\(count(.conflicted))")
    }

    /// «Save unified diff»: все изменения под версией одной правкой в файл.
    private func saveDiff() {
        let diff = Git.run(["diff", "HEAD", "--"] + (wholeProject.state == .on ? [] : specs), in: repo).out
        guard !diff.isEmpty else {
            return UI.alert(L.t("Изменений под версией нет.", "There are no versioned changes."), style: .informational)
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "changes.patch"
        panel.directoryURL = URL(fileURLWithPath: repo)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try diff.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            UI.alert(error.localizedDescription)
        }
    }
}

/// «Добавить…» и «Убрать изменения…»: список файлов с отметками и одна кнопка.
final class FilePickController: ToolWindow {
    enum Mode { case add, revert }

    private let repo: String
    private let specs: [String]
    private let mode: Mode
    private let list: FileListView

    init(repo: String, specs: [String], mode: Mode) {
        self.repo = repo
        self.specs = specs
        self.mode = mode
        // Как в оригинале: список без столбцов строк, под ним «Select/deselect all», ряд OK / Cancel / Help.
        list = FileListView(repo: repo, checkable: true, lines: false)
        let name = mode == .add ? L.t("Добавить", "Add") : L.t("Убрать изменения", "Revert")
        super.init(title: ToolWindow.title(repo, name), size: NSSize(width: 560, height: 420))
        let all = UI.check(L.t("Отметить / снять все", "Select/deselect all"), on: true)
        all.target = self
        all.action = #selector(toggleAll(_:))
        let content = UI.column([list, all], spacing: 9)
        list.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        install(content, buttons: [ClosureButton("OK", key: "\r") { [weak self] in self?.perform() }, cancelButton, helpButton])
        watch(repo) { [weak self] in self?.reload() }
        reload()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func reload() {
        let files = Git.status(repo, specs: specs).filter { ($0.kind == .untracked) == (mode == .add) }
        list.show(files, stats: mode == .revert ? Git.numstat(repo) : [:]) { _ in true }
    }

    @objc private func toggleAll(_ sender: NSButton) {
        let on = sender.state == .on
        list.setChecked { _ in on }
    }

    private func perform() {
        let files = list.checkedFiles
        guard !files.isEmpty else { return UI.alert(L.t("Не отмечено ни одного файла.", "No files are selected.")) }
        let steps = mode == .add ? [["add", "--"] + files.map(\.path)] : Git.revertSteps(files)
        let title = mode == .add ? L.t("Добавить", "Add") : L.t("Убрать изменения", "Revert")
        // Отмена изменений необратима — спрашиваем, раз в самом окне предупреждения нет (как и в оригинале).
        if mode == .revert, !UI.confirm(L.t("Убрать изменения в файлах (\(files.count))?", "Revert changes in \(files.count) file(s)?"),
                                         info: L.t("Файлы вернутся к последней фиксации. Отменить это нельзя.",
                                                   "The files go back to the last commit. This cannot be undone."),
                                         ok: L.t("Убрать изменения", "Revert")) {
            return
        }
        // Сначала окно хода, потом закрываем это: программа выходит, когда окон не осталось.
        ProgressController.run(title: title, dir: repo, steps: steps)
        close()
    }
}

private extension NSRange {
    /// Конец найденного диапазона; не найдено — ноль (курсор в первой строке).
    func upperBound(orZero: Bool) -> Int { location == NSNotFound ? 0 : location + length }
}

/// Окно с текстом правки («View Patch»).
final class PatchWindow: ToolWindow {
    init(repo: String, text: String) {
        super.init(title: ToolWindow.title(repo, L.t("Правка", "Patch")), size: NSSize(width: 760, height: 520))
        let (scroll, view) = UI.textView(editable: false, mono: true)
        view.string = text
        install(scroll, buttons: [closeButton])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
