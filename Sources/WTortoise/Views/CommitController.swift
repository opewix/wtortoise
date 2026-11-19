import AppKit

/// Кнопка-ссылка в строке «Отметить: Все, Ничего…».
private func link(_ title: String, _ handler: @escaping () -> Void) -> NSButton {
    let button = ClosureButton(title, handler: handler)
    button.isBordered = false
    button.attributedTitle = NSAttributedString(string: title, attributes: [
        .foregroundColor: NSColor(hex: 0x0645AD), .underlineStyle: NSUnderlineStyle.single.rawValue,
        .font: NSFont.systemFont(ofSize: 12),
    ])
    button.constraints.forEach { $0.isActive = false }
    return button
}

/// Окно фиксации: сообщение и список изменённых файлов с отметками.
final class CommitController: ToolWindow {
    private let repo: String
    private let specs: [String]
    private let list: FileListView
    private let message: NSTextView
    private let amend = UI.check(L.t("Исправить последнюю фиксацию", "Amend Last Commit"))
    private let showUnversioned = UI.check(L.t("Показывать файлы не под версией", "Show Unversioned Files"), on: Settings.showUnversioned)
    private let branchLabel = UI.label("", bold: true)
    private let countLabel = UI.label("", color: .secondaryLabelColor)
    private var all: [FileChange] = []

    init(repo: String, specs: [String]) {
        self.repo = repo
        self.specs = specs
        list = FileListView(repo: repo, checkable: true)
        let (messageScroll, message) = UI.textView(editable: true)
        self.message = message
        super.init(title: ToolWindow.title(repo, L.t("Фиксация", "Commit")), size: NSSize(width: 780, height: 620))

        let top = UI.row([UI.label(L.t("Фиксация в:", "Commit to:")), branchLabel, UI.spacer()])
        let checks = UI.row([
            UI.label(L.t("Отметить:", "Check:")),
            link(L.t("Все", "All")) { [weak self] in self?.list.setChecked { _ in true } },
            link(L.t("Ничего", "None")) { [weak self] in self?.list.setChecked { _ in false } },
            link(L.t("Не под версией", "Unversioned")) { [weak self] in self?.list.setChecked { $0.kind == .untracked } },
            link(L.t("Под версией", "Versioned")) { [weak self] in self?.list.setChecked { $0.kind != .untracked } },
            link(L.t("Добавленные", "Added")) { [weak self] in self?.list.setChecked { $0.kind == .added } },
            link(L.t("Удалённые", "Deleted")) { [weak self] in self?.list.setChecked { $0.kind == .deleted } },
            link(L.t("Изменённые", "Modified")) { [weak self] in self?.list.setChecked { $0.kind == .modified } },
            UI.spacer(),
        ], spacing: 10)
        let bottom = UI.row([showUnversioned, UI.spacer(), countLabel])
        let content = UI.column([
            top, UI.label(L.t("Сообщение:", "Message:")), messageScroll, amend,
            UI.label(L.t("Изменения (двойной щелчок по файлу — сравнение):", "Changes made (double-click on file for diff):")),
            checks, list, bottom,
        ])
        for view in [top, messageScroll, checks, list, bottom] as [NSView] {
            view.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
        messageScroll.heightAnchor.constraint(equalToConstant: 120).isActive = true
        list.heightAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true

        amend.target = self
        amend.action = #selector(amendChanged)
        showUnversioned.target = self
        showUnversioned.action = #selector(unversionedChanged)
        list.onCheckedChange = { [weak self] in self?.updateCount() }

        install(content, buttons: [
            ClosureButton(L.t("Зафиксировать", "Commit"), key: "\r") { [weak self] in self?.commit(push: false) },
            ClosureButton(L.t("Зафиксировать и отправить", "Commit & Push")) { [weak self] in self?.commit(push: true) },
            cancelButton,
        ])
        window?.initialFirstResponder = message
        watch(repo) { [weak self] in self?.reload() }
        reload()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func reload() {
        branchLabel.stringValue = Git.headName(repo)
        all = Git.status(repo, specs: specs)
        apply(stats: Git.numstat(repo))
    }

    private func apply(stats: [String: (added: Int, removed: Int)]? = nil) {
        let visible = showUnversioned.state == .on ? all : all.filter { $0.kind != .untracked }
        list.show(visible, stats: stats ?? Git.numstat(repo)) { $0.kind != .untracked }
    }

    private func updateCount() {
        countLabel.stringValue = L.t("Отмечено файлов: \(list.checked.count) из \(list.files.count)",
                                     "\(list.checked.count) files selected, \(list.files.count) files total")
    }

    @objc private func unversionedChanged() {
        Settings.showUnversioned = showUnversioned.state == .on
        apply()
    }

    @objc private func amendChanged() {
        guard amend.state == .on, message.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        message.string = Git.run(["log", "-1", "--format=%B"], in: repo).trimmed
    }

    private func commit(push: Bool) {
        let text = message.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let files = list.checkedFiles
        let isAmend = amend.state == .on
        guard !text.isEmpty else {
            return UI.alert(L.t("Введите сообщение фиксации.", "Please enter a commit message."))
        }
        guard !files.isEmpty || isAmend else {
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
        var commit = ["commit", "-F", messageFile.path]
        if isAmend { commit.append("--amend") }
        let paths = files.flatMap(\.pathspecs)
        if Git.isMerging(repo) {
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

        let repo = self.repo
        close()
        ProgressController.run(
            title: L.t("Фиксация", "Commit"), dir: repo, steps: steps,
            extra: push ? [] : [(L.t("Отправить…", "Push..."), { PushDialog(repo: repo).present() })],
            onFinish: { ok in
                try? FileManager.default.removeItem(at: messageFile)
                if ok && push { PushDialog(repo: repo).present() }
            })
    }
}

/// «Проверить изменения»: что изменено в рабочей копии.
final class StatusController: ToolWindow {
    private let repo: String
    private let specs: [String]
    private let list: FileListView
    private let summary = UI.label("", color: .secondaryLabelColor)

    init(repo: String, specs: [String]) {
        self.repo = repo
        self.specs = specs
        list = FileListView(repo: repo, checkable: false)
        super.init(title: ToolWindow.title(repo, L.t("Рабочая копия", "Working Tree")), size: NSSize(width: 760, height: 460))
        install(list, buttons: [
            ClosureButton(L.t("Фиксация…", "Commit")) { [repo, specs] in CommitController(repo: repo, specs: specs).present() },
            ClosureButton(L.t("Обновить", "Refresh")) { [weak self] in self?.reload() },
            okButton,
        ], leading: [summary])
        watch(repo) { [weak self] in self?.reload() }
        reload()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func reload() {
        let files = Git.status(repo, specs: specs)
        list.show(files, stats: Git.numstat(repo)) { _ in false }
        let branch = Git.headName(repo)
        summary.stringValue = files.isEmpty
            ? L.t("\(branch): изменений нет", "\(branch): no changes")
            : L.t("\(branch): изменённых файлов — \(files.count)", "\(branch): \(files.count) changed file(s)")
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
        list = FileListView(repo: repo, checkable: true)
        let name = mode == .add ? L.t("Добавить", "Add") : L.t("Убрать изменения", "Revert")
        super.init(title: ToolWindow.title(repo, name), size: NSSize(width: 720, height: 420))
        let all = UI.check(L.t("Отметить / снять все", "Select/deselect all"), on: true)
        all.target = self
        all.action = #selector(toggleAll(_:))
        let hint = UI.label(mode == .add ? ""
            : L.t("Отмеченные файлы вернутся к последней фиксации. Отменить это нельзя.",
                  "The checked files go back to the last commit. This cannot be undone."))
        let content = UI.column(mode == .add ? [list] : [hint, list])
        list.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        install(content, buttons: [ClosureButton("OK", key: "\r") { [weak self] in self?.perform() }, cancelButton], leading: [all])
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
        let repo = self.repo
        close()
        ProgressController.run(title: title, dir: repo, steps: steps)
    }
}
