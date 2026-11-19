import AppKit

/// Выбор версии: HEAD, ветка, метка или фиксация. Общая часть диалогов переключения, ветки, метки, слияния.
final class RefChooser: NSObject, NSComboBoxDelegate, NSTextFieldDelegate {
    let view = NSGridView(numberOfColumns: 2, rows: 0)
    private var radios: [NSButton] = []
    private let branches: NSComboBox
    private let tags: NSComboBox
    private let commit = UI.field(placeholder: "SHA-1")
    private let remoteBranches: [String]
    private let hasHead: Bool
    var onChange: (() -> Void)?

    /// - Parameter preset: хеш, с которым диалог открыт из журнала.
    init(repo: String, allowHead: Bool, preset: String? = nil) {
        hasHead = allowHead
        let local = Git.localBranches(repo)
        remoteBranches = Git.remoteBranches(repo)
        let current = Git.currentBranch(repo)
        branches = UI.combo(local + remoteBranches, value: local.first { $0 != current || allowHead } ?? remoteBranches.first ?? "")
        let tagNames = Git.tags(repo)
        tags = UI.combo(tagNames, value: tagNames.first ?? "")
        super.init()
        view.rowSpacing = 6
        view.columnSpacing = 8
        view.rowAlignment = .firstBaseline
        view.translatesAutoresizingMaskIntoConstraints = false
        func radio(_ title: String) -> NSButton {
            let button = NSButton(radioButtonWithTitle: title, target: self, action: #selector(pick(_:)))
            radios.append(button)
            return button
        }
        if allowHead { view.addRow(with: [radio("HEAD"), NSGridCell.emptyContentView]) }
        view.addRow(with: [radio(L.t("Ветка", "Branch")), branches])
        view.addRow(with: [radio(L.t("Метка", "Tag")), tags])
        view.addRow(with: [radio(L.t("Фиксация", "Commit")), commit])
        branches.delegate = self
        tags.delegate = self
        if let preset {
            commit.stringValue = preset
            radios.last?.state = .on
        } else {
            radios.first?.state = .on
        }
        sync()
    }

    private enum Mode { case head, branch, tag, commit }

    private var mode: Mode {
        let index = radios.firstIndex { $0.state == .on } ?? 0
        let modes: [Mode] = hasHead ? [.head, .branch, .tag, .commit] : [.branch, .tag, .commit]
        return modes[index]
    }

    /// Выбранная версия; nil — поле пустое.
    var ref: String? {
        let value: String
        switch mode {
        case .head: return "HEAD"
        case .branch: value = branches.stringValue
        case .tag: value = tags.stringValue
        case .commit: value = commit.stringValue
        }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Выбрана ветка с сервера — тогда её имя («origin/x»).
    var remoteBranch: String? {
        guard mode == .branch, let ref, remoteBranches.contains(ref) else { return nil }
        return ref
    }

    @objc private func pick(_ sender: NSButton) {
        sync()
        onChange?()
    }

    private func sync() {
        branches.isEnabled = mode == .branch
        tags.isEnabled = mode == .tag
        commit.isEnabled = mode == .commit
    }

    func comboBoxSelectionDidChange(_ notification: Notification) {
        // Значение combo обновляется после этого события.
        DispatchQueue.main.async { [weak self] in self?.onChange?() }
    }

    func controlTextDidChange(_ obj: Notification) { onChange?() }
}

/// Диалог-форма: поля, «ОК» с названием действия, «Отмена». По «ОК» запускает команды git в окне хода.
class FormDialog: ToolWindow {
    let repo: String
    let form = Form()
    private let name: String

    init(repo: String, name: String) {
        self.repo = repo
        self.name = name
        super.init(title: ToolWindow.title(repo, name), size: NSSize(width: 460, height: 200), resizable: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Вызвать в конце init наследника, когда форма заполнена.
    func finish(ok: String? = nil) {
        install(form.grid, buttons: [ClosureButton(ok ?? "OK", key: "\r") { [weak self] in self?.submit() }, cancelButton])
    }

    /// Команды git для выполнения; nil — ввод неполон (наследник сам показал, что не так).
    func steps() -> [[String]]? { nil }

    /// Папка, в которой запускать команды.
    var workDir: String { repo }

    private func submit() {
        guard let steps = steps() else { return }
        let dir = workDir
        close()
        ProgressController.run(title: name, dir: dir, steps: steps)
    }

    func required(_ value: String, _ what: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            UI.alert(L.t("Не заполнено: \(what)", "Missing: \(what)"))
            return nil
        }
        return trimmed
    }
}

final class PushDialog: FormDialog {
    private var local: NSComboBox!
    private let remoteBranch = UI.field(placeholder: L.t("как локальная", "same as local"))
    private var remote: NSPopUpButton!
    private let force = UI.check(L.t("Принудительно, если на сервере нет чужих изменений (--force-with-lease)", "Force with lease"))
    private let forceAny = UI.check(L.t("Принудительно, затирая и чужие изменения (--force)", "Force"))
    private let tags = UI.check(L.t("Вместе с метками", "Include Tags"))
    private let setUpstream = UI.check(L.t("Запомнить ветку сервера для отслеживания", "Set upstream/track remote branch"))

    init(repo: String) {
        super.init(repo: repo, name: L.t("Отправить", "Push"))
        let upstream = Git.upstream(repo)
        let remotes = Git.remotes(repo)
        local = UI.combo(Git.localBranches(repo), value: Git.currentBranch(repo) ?? "")
        remote = UI.popup(remotes, selected: upstream?.remote ?? "origin")
        remoteBranch.stringValue = upstream?.branch ?? ""
        setUpstream.state = upstream == nil ? .on : .off
        form.section(L.t("Что отправить", "Ref"))
        form.row(L.t("Локальная ветка:", "Local:"), local)
        form.row(L.t("Ветка на сервере:", "Remote:"), remoteBranch)
        form.section(L.t("Куда", "Destination"))
        form.row(L.t("Сервер:", "Remote:"), remote)
        form.section(L.t("Параметры", "Options"))
        form.wide(force)
        form.wide(forceAny)
        form.wide(tags)
        form.wide(setUpstream)
        finish()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func steps() -> [[String]]? {
        guard let remoteName = remote.titleOfSelectedItem else {
            UI.alert(L.t("У хранилища нет серверов.", "This repository has no remotes."),
                     info: L.t("Добавьте сервер: git remote add origin <адрес>.", "Add one first: git remote add origin <url>."))
            return nil
        }
        guard let branch = required(local.stringValue, L.t("локальная ветка", "local branch")) else { return nil }
        var args = ["push", "--progress"]
        if forceAny.state == .on {
            guard UI.confirm(L.t("Отправить принудительно?", "Force push?"),
                             info: L.t("Фиксации на сервере, которых нет у вас, будут потеряны.", "Commits on the remote that you do not have will be lost."),
                             ok: L.t("Отправить принудительно", "Force Push")) else { return nil }
            args.append("--force")
        } else if force.state == .on {
            args.append("--force-with-lease")
        }
        if tags.state == .on { args.append("--tags") }
        if setUpstream.state == .on { args.append("-u") }
        let target = remoteBranch.stringValue.trimmingCharacters(in: .whitespaces)
        args += [remoteName, target.isEmpty || target == branch ? branch : "\(branch):\(target)"]
        return [args]
    }
}

final class PullDialog: FormDialog {
    private var remote: NSPopUpButton!
    private var branch: NSComboBox!
    private let rebase = UI.check(L.t("Перенести свои фиксации поверх (rebase)", "Rebase"))
    private let ffOnly = UI.check(L.t("Только перемотка (--ff-only)", "Fast Forward Only"))
    private let prune = UI.check(L.t("Убрать ветки, удалённые на сервере (--prune)", "Prune"))
    private let tags = UI.check(L.t("Получить метки", "Tags"))

    init(repo: String) {
        super.init(repo: repo, name: L.t("Получить", "Pull"))
        let upstream = Git.upstream(repo)
        let remotes = Git.remotes(repo)
        let chosen = upstream?.remote ?? (remotes.contains("origin") ? "origin" : remotes.first ?? "")
        remote = UI.popup(remotes, selected: chosen)
        let names = Git.remoteBranches(repo).filter { $0.hasPrefix(chosen + "/") }.map { String($0.dropFirst(chosen.count + 1)) }
        branch = UI.combo(names, value: upstream?.branch ?? Git.currentBranch(repo) ?? "")
        form.row(L.t("Сервер:", "Remote:"), remote)
        form.row(L.t("Ветка на сервере:", "Remote Branch:"), branch)
        form.section(L.t("Параметры", "Options"))
        form.wide(rebase)
        form.wide(ffOnly)
        form.wide(prune)
        form.wide(tags)
        finish()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func steps() -> [[String]]? {
        guard let remoteName = remote.titleOfSelectedItem else {
            UI.alert(L.t("У хранилища нет серверов.", "This repository has no remotes."))
            return nil
        }
        guard let name = required(branch.stringValue, L.t("ветка на сервере", "remote branch")) else { return nil }
        var args = ["pull", "--progress"]
        // Без явного выбора git отказывается сливать разошедшиеся ветки.
        if ffOnly.state == .on { args.append("--ff-only") } else { args.append(rebase.state == .on ? "--rebase" : "--no-rebase") }
        if prune.state == .on { args.append("--prune") }
        if tags.state == .on { args.append("--tags") }
        return [args + [remoteName, name]]
    }
}

final class FetchDialog: FormDialog {
    private var remote: NSPopUpButton!
    private let prune = UI.check(L.t("Убрать ветки, удалённые на сервере (--prune)", "Prune"), on: true)
    private let tags = UI.check(L.t("Получить метки", "Tags"))

    init(repo: String) {
        super.init(repo: repo, name: L.t("Извлечь", "Fetch"))
        let remotes = Git.remotes(repo)
        remote = UI.popup([L.t("Все серверы", "All remotes")] + remotes, selected: remotes.count == 1 ? remotes[0] : nil)
        form.row(L.t("Сервер:", "Remote:"), remote)
        form.wide(prune)
        form.wide(tags)
        finish()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func steps() -> [[String]]? {
        var args = ["fetch", "--progress"]
        if prune.state == .on { args.append("--prune") }
        if tags.state == .on { args.append("--tags") }
        args.append(remote.indexOfSelectedItem == 0 ? "--all" : remote.titleOfSelectedItem ?? "--all")
        return [args]
    }
}

final class SwitchDialog: FormDialog {
    private var chooser: RefChooser!
    private let create = UI.check(L.t("Создать новую ветку:", "Create New Branch"))
    private let name = UI.field(width: 220)
    private let track = UI.check(L.t("Следить за веткой сервера", "Track"))
    private let force = UI.check(L.t("Затереть изменения рабочей копии (--force)", "Overwrite working tree changes (force)"))

    init(repo: String, preset: String? = nil) {
        super.init(repo: repo, name: L.t("Переключить / Извлечь", "Switch/Checkout"))
        chooser = RefChooser(repo: repo, allowHead: false, preset: preset)
        chooser.onChange = { [weak self] in self?.suggest() }
        form.section(L.t("Переключиться на", "Switch To"))
        form.wide(chooser.view)
        form.section(L.t("Параметры", "Option"))
        form.grid.addRow(with: [create, name])
        form.wide(track)
        form.wide(force)
        finish()
        suggest()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Ветку сервера нельзя занять напрямую — предлагаем свою с тем же именем, следящую за ней.
    private func suggest() {
        if let remote = chooser.remoteBranch, let slash = remote.firstIndex(of: "/") {
            create.state = .on
            track.state = .on
            name.stringValue = String(remote[remote.index(after: slash)...])
        } else if track.state == .on {
            create.state = .off
            track.state = .off
            name.stringValue = ""
        }
    }

    override func steps() -> [[String]]? {
        guard let ref = chooser.ref else {
            UI.alert(L.t("Не выбрана версия.", "No version is selected."))
            return nil
        }
        var args = ["checkout"]
        if force.state == .on { args.append("-f") }
        if create.state == .on {
            guard let branch = required(name.stringValue, L.t("имя новой ветки", "new branch name")) else { return nil }
            args += ["-b", branch]
            if track.state == .on { args.append("--track") }
        }
        return [args + [ref]]
    }
}

final class BranchDialog: FormDialog {
    private var chooser: RefChooser!
    private let name = UI.field()
    private let track = UI.check(L.t("Следить за исходной веткой", "Track"))
    private let force = UI.check(L.t("Переставить, если ветка уже есть", "Force"))
    private let switchTo = UI.check(L.t("Переключиться на новую ветку", "Switch to new branch"))

    init(repo: String, preset: String? = nil) {
        super.init(repo: repo, name: L.t("Создать ветку", "Create Branch"))
        chooser = RefChooser(repo: repo, allowHead: true, preset: preset)
        form.row(L.t("Имя ветки:", "Branch"), name)
        form.section(L.t("От чего", "Base On"))
        form.wide(chooser.view)
        form.section(L.t("Параметры", "Options"))
        form.wide(track)
        form.wide(force)
        form.wide(switchTo)
        finish()
        window?.initialFirstResponder = name
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func steps() -> [[String]]? {
        guard let branch = required(name.stringValue, L.t("имя ветки", "branch name")), let base = chooser.ref else { return nil }
        let tracking = track.state == .on ? ["--track"] : []
        if switchTo.state == .on {
            return [["checkout", force.state == .on ? "-B" : "-b", branch] + tracking + [base]]
        }
        return [["branch"] + (force.state == .on ? ["-f"] : []) + tracking + [branch, base]]
    }
}

final class TagDialog: FormDialog {
    private var chooser: RefChooser!
    private let name = UI.field()
    private let message = UI.field(placeholder: L.t("пусто — простая метка, без сообщения", "empty — a lightweight tag"))
    private let force = UI.check(L.t("Переставить, если метка уже есть", "Force"))

    init(repo: String, preset: String? = nil) {
        super.init(repo: repo, name: L.t("Создать метку", "Create Tag"))
        chooser = RefChooser(repo: repo, allowHead: true, preset: preset)
        form.row(L.t("Метка:", "Tag:"), name)
        form.section(L.t("На чём", "Base On"))
        form.wide(chooser.view)
        form.section(L.t("Параметры", "Options"))
        form.row(L.t("Сообщение:", "Message"), message)
        form.wide(force)
        finish()
        window?.initialFirstResponder = name
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func steps() -> [[String]]? {
        guard let tag = required(name.stringValue, L.t("имя метки", "tag name")), let base = chooser.ref else { return nil }
        var args = ["tag"]
        if force.state == .on { args.append("-f") }
        let text = message.stringValue.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty { args += ["-a", "-m", text] }
        return [args + [tag, base]]
    }
}

final class MergeDialog: FormDialog {
    private var chooser: RefChooser!
    private let squash = UI.check(L.t("Одной фиксацией (--squash)", "Squash"))
    private let noFF = UI.check(L.t("Всегда создавать фиксацию слияния (--no-ff)", "No Fast Forward"))
    private let noCommit = UI.check(L.t("Не фиксировать (--no-commit)", "No Commit"))
    private let message = UI.field(placeholder: L.t("пусто — сообщение по умолчанию", "empty — the default message"))

    init(repo: String) {
        super.init(repo: repo, name: L.t("Слить", "Merge"))
        chooser = RefChooser(repo: repo, allowHead: false)
        form.section(L.t("Слить в «\(Git.headName(repo))» из", "From"))
        form.wide(chooser.view)
        form.section(L.t("Параметры", "Option"))
        form.wide(squash)
        form.wide(noFF)
        form.wide(noCommit)
        form.row(L.t("Сообщение слияния:", "Merge Message"), message)
        finish()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func steps() -> [[String]]? {
        guard let ref = chooser.ref else {
            UI.alert(L.t("Не выбрана версия.", "No version is selected."))
            return nil
        }
        var args = ["merge"]
        if squash.state == .on { args.append("--squash") }
        if noFF.state == .on { args.append("--no-ff") }
        if noCommit.state == .on { args.append("--no-commit") }
        let text = message.stringValue.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty { args += ["-m", text] }
        return [args + [ref]]
    }
}

final class ResetDialog: FormDialog {
    private let commit: Commit
    private var modes: [NSButton] = []

    init(repo: String, commit: Commit) {
        self.commit = commit
        super.init(repo: repo, name: L.t("Сброс", "Reset"))
        form.wide(UI.label(L.t("Сбросить «\(Git.headName(repo))» на:", "Current branch: \(Git.headName(repo))")))
        form.wide(UI.label("\(commit.hash.prefix(8))  \(commit.subject)", bold: true))
        form.section(L.t("Вид сброса", "Reset Type"))
        let titles = [
            L.t("Мягкий: рабочая копия и индекс остаются", "Soft: Leave working tree and index untouched"),
            L.t("Смешанный: рабочая копия остаётся, индекс сбрасывается", "Mixed: Leave working tree untouched, reset index"),
            L.t("Жёсткий: сбросить всё, изменения рабочей копии пропадут", "Hard: Reset working tree and index (discard all local changes)"),
        ]
        let group = UI.column(titles.map { title in
            let radio = NSButton(radioButtonWithTitle: title, target: self, action: #selector(pick))
            modes.append(radio)
            return radio
        }, spacing: 6)
        modes[1].state = .on
        form.wide(group)
        finish()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func pick() {}

    override func steps() -> [[String]]? {
        let index = modes.firstIndex { $0.state == .on } ?? 1
        if index == 2, !UI.confirm(L.t("Жёсткий сброс: несохранённые изменения пропадут.", "Hard reset: uncommitted changes will be lost."),
                                   info: L.t("Отменить это нельзя.", "This cannot be undone."), ok: L.t("Сбросить", "Reset")) {
            return nil
        }
        return [["reset", ["--soft", "--mixed", "--hard"][index], commit.hash]]
    }
}

final class StashDialog: FormDialog {
    private let message = UI.field(placeholder: L.t("необязательно", "optional"))
    private let untracked = UI.check(L.t("Вместе с файлами не под версией", "include untracked"))

    init(repo: String) {
        super.init(repo: repo, name: L.t("Спрятать изменения", "Stash"))
        form.row(L.t("Сообщение:", "Stash Message"), message)
        form.wide(untracked)
        finish()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func steps() -> [[String]]? {
        var args = ["stash", "push"]
        if untracked.state == .on { args.append("-u") }
        let text = message.stringValue.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty { args += ["-m", text] }
        return [args]
    }
}

/// Переименовать файл или папку под версией (git mv).
final class RenameDialog: FormDialog {
    private let path: String
    private let name: NSTextField

    /// - Parameter path: путь относительно корня.
    init(repo: String, path: String) {
        self.path = path
        name = UI.field((path as NSString).lastPathComponent, width: 320)
        super.init(repo: repo, name: L.t("Переименование", "Rename"))
        form.wide(UI.label(path, bold: true))
        form.row(L.t("Новое имя:", "New name:"), name)
        finish()
        window?.initialFirstResponder = name
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func steps() -> [[String]]? {
        guard let newName = required(name.stringValue, L.t("новое имя", "new name")) else { return nil }
        guard !newName.contains("/") else {
            UI.alert(L.t("Имя не может содержать «/».", "The name cannot contain “/”."))
            return nil
        }
        let folder = (path as NSString).deletingLastPathComponent
        let target = folder.isEmpty ? newName : folder + "/" + newName
        guard target != path else { return nil }
        return [["mv", "--", path, target]]
    }
}

/// Удалить из хранилища (git rm): с диска тоже либо только из-под версии.
final class RemoveDialog: FormDialog {
    private let paths: [String]
    private let keep = UI.check(L.t("Оставить файлы на диске (убрать только из-под версии)", "Keep the files on disk (remove from version control only)"))

    init(repo: String, paths: [String]) {
        self.paths = paths
        super.init(repo: repo, name: L.t("Удаление", "Delete"))
        form.wide(UI.label(L.t("Удалить из хранилища (\(paths.count)):", "Delete from the repository (\(paths.count)):")))
        let shown = paths.prefix(10).joined(separator: "\n") + (paths.count > 10 ? "\n…" : "")
        let list = UI.label(shown, bold: true)
        list.maximumNumberOfLines = 11
        list.lineBreakMode = .byTruncatingMiddle
        form.wide(list)
        form.wide(keep)
        form.wide(UI.label(L.t("Удаление войдёт в следующую фиксацию.", "The deletion goes into the next commit."), color: .secondaryLabelColor))
        finish(ok: L.t("Удалить", "Delete"))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func steps() -> [[String]]? {
        [["rm", "-r"] + (keep.state == .on ? ["--cached"] : []) + ["--"] + paths]
    }
}

final class CloneDialog: FormDialog, NSTextFieldDelegate {
    private let parent: String
    private let url = UI.field(width: 360)
    private let directory = UI.field(width: 360)
    private let branch = UI.field(placeholder: L.t("ветка по умолчанию", "the default branch"), width: 200)
    private let depth = UI.field(placeholder: L.t("вся история", "full history"), width: 200)
    private let recursive = UI.check(L.t("С подмодулями (--recursive)", "Recursive"))
    /// Папку подставляем по адресу, пока человек не ввёл свою.
    private var directoryEdited = false

    init(parent: String) {
        self.parent = parent
        super.init(repo: parent, name: L.t("Клонирование", "Git clone"))
        if let pasted = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           pasted.count < 300, !pasted.contains("\n"),
           pasted.hasPrefix("http") || pasted.hasPrefix("git@") || pasted.hasPrefix("ssh://") {
            url.stringValue = pasted
        }
        url.delegate = self
        directory.delegate = self
        let browse = ClosureButton(L.t("Обзор…", "Browse...")) { [weak self] in self?.browse() }
        form.row("URL:", url)
        form.row(L.t("Папка:", "Directory:"), UI.row([directory, browse]))
        form.row(L.t("Ветка:", "Branch"), branch)
        form.row(L.t("Глубина:", "Depth"), depth)
        form.wide(recursive)
        finish()
        suggestDirectory()
        window?.initialFirstResponder = url
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var workDir: String { parent }

    func controlTextDidChange(_ obj: Notification) {
        if (obj.object as? NSTextField) === directory {
            directoryEdited = true
        } else {
            suggestDirectory()
        }
    }

    private func suggestDirectory() {
        guard !directoryEdited else { return }
        var name = url.stringValue.trimmingCharacters(in: .whitespaces)
        while name.hasSuffix("/") { name.removeLast() }
        name = name.components(separatedBy: CharacterSet(charactersIn: "/:")).last ?? ""
        if name.hasSuffix(".git") { name.removeLast(4) }
        directory.stringValue = name.isEmpty ? parent : parent + "/" + name
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: parent)
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        // Выбрана папка-родитель: имя хранилища из адреса остаётся.
        let name = directory.stringValue == parent ? "" : (directory.stringValue as NSString).lastPathComponent
        directory.stringValue = name.isEmpty ? chosen.path : chosen.path + "/" + name
        directoryEdited = true
    }

    override func steps() -> [[String]]? {
        guard let source = required(url.stringValue, "URL"),
              let target = required(directory.stringValue, L.t("папка", "directory")) else { return nil }
        var args = ["clone", "--progress"]
        if recursive.state == .on { args.append("--recursive") }
        let branchName = branch.stringValue.trimmingCharacters(in: .whitespaces)
        if !branchName.isEmpty { args += ["-b", branchName] }
        let depthValue = depth.stringValue.trimmingCharacters(in: .whitespaces)
        if !depthValue.isEmpty {
            guard let number = Int(depthValue), number > 0 else {
                UI.alert(L.t("Глубина — целое число больше нуля.", "Depth must be a positive number."))
                return nil
            }
            args += ["--depth", String(number)]
        }
        return [args + ["--", source, (target as NSString).expandingTildeInPath]]
    }
}
