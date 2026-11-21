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
        let headTitle = "HEAD (\(Git.headName(repo)))"
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
            let button = WinRadio(title, target: self, action: #selector(pick(_:)))
            radios.append(button)
            return button
        }
        if allowHead { view.addRow(with: [radio(headTitle), NSGridCell.emptyContentView]) }
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
        form.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 430).isActive = true
        install(form.view, buttons: [ClosureButton(ok ?? "OK", key: "\r") { [weak self] in self?.submit() }, cancelButton, helpButton])
    }

    /// Команды git для выполнения; nil — ввод неполон (наследник сам показал, что не так).
    func steps() -> [[String]]? { nil }

    /// Папка, в которой запускать команды.
    var workDir: String { repo }

    private func submit() {
        guard let steps = steps() else { return }
        let dir = workDir
        // Сначала окно хода, потом закрываем это: программа выходит, когда окон не осталось.
        ProgressController.run(title: name, dir: dir, steps: steps)
        close()
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
    private var remoteBranch: NSComboBox!
    private var remote: NSPopUpButton!
    private let allBranches = UI.check(L.t("Отправить все ветки", "Push all branches"))
    private let force = UI.check(L.t("известные изменения", "known changes"))
    private let forceAny = UI.check(L.t("неизвестные изменения", "unknown changes"))
    private let tags = UI.check(L.t("Вместе с метками", "Include Tags"))
    private let setUpstream = UI.check(L.t("Запомнить ветку сервера для отслеживания", "Set upstream/track remote branch"))

    init(repo: String) {
        super.init(repo: repo, name: L.t("Отправить", "Push"))
        let upstream = Git.upstream(repo)
        let remotes = Git.remotes(repo)
        let chosen = upstream?.remote ?? (remotes.contains("origin") ? "origin" : remotes.first ?? "")
        let current = Git.currentBranch(repo) ?? ""
        local = UI.combo(Git.localBranches(repo), value: current)
        let names = Git.remoteBranches(repo).filter { $0.hasPrefix(chosen + "/") }.map { String($0.dropFirst(chosen.count + 1)) }
        remoteBranch = UI.combo(names, value: upstream?.branch ?? current)
        remote = UI.popup(remotes, selected: chosen)
        setUpstream.state = upstream == nil ? .on : .off
        allBranches.target = self
        allBranches.action = #selector(allChanged)
        form.section(L.t("Что отправить", "Ref"))
        form.wide(allBranches)
        form.row(L.t("Локальная:", "Local:"), local)
        form.row(L.t("На сервере:", "Remote:"), remoteBranch)
        form.section(L.t("Куда", "Destination"))
        form.row(L.t("Сервер:", "Remote:"), remote)
        form.section(L.t("Параметры", "Options"))
        // «Force: May discard» — известные изменения (--force-with-lease) или любые (--force).
        form.wide(UI.row([UI.label(L.t("Принудительно: могут пропасть", "Force: May discard")), UI.spacer(), force, UI.spacer(), forceAny, UI.spacer()]))
        form.wide(tags)
        form.wide(setUpstream)
        finish()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func allChanged() {
        local.isEnabled = allBranches.state != .on
        remoteBranch.isEnabled = allBranches.state != .on
    }

    override func steps() -> [[String]]? {
        guard let remoteName = remote.titleOfSelectedItem else {
            UI.alert(L.t("У хранилища нет серверов.", "This repository has no remotes."),
                     info: L.t("Добавьте сервер: git remote add origin <адрес>.", "Add one first: git remote add origin <url>."))
            return nil
        }
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
        if allBranches.state == .on { return [args + ["--all", remoteName]] }
        guard let branch = required(local.stringValue, L.t("локальная ветка", "local branch")) else { return nil }
        let target = remoteBranch.stringValue.trimmingCharacters(in: .whitespaces)
        args += [remoteName, target.isEmpty || target == branch ? branch : "\(branch):\(target)"]
        return [args]
    }
}

/// Общая раскладка окон Pull и Fetch: сервер и ветка, параметры слияния (у Fetch недоступны), метки и очистка.
class RemoteDialog: FormDialog {
    var remote: NSPopUpButton!
    var branch: NSComboBox!
    let squash = UI.check(L.t("Одной фиксацией", "Squash"))
    let noCommit = UI.check(L.t("Не фиксировать", "No Commit"))
    let noFF = UI.check(L.t("Без перемотки", "No Fast Forward"))
    let ffOnly = UI.check(L.t("Только перемотка", "Fast Forward Only"))
    let tags = UI.check(L.t("Метки", "Tags"))
    let prune = UI.check(L.t("Убрать удалённые на сервере", "Prune"))
    let rebase = UI.check(L.t("Перенести свои фиксации поверх (rebase)", "Launch Rebase After Fetch"))

    init(repo: String, name: String, merging: Bool) {
        super.init(repo: repo, name: name)
        let upstream = Git.upstream(repo)
        let remotes = Git.remotes(repo)
        let chosen = upstream?.remote ?? (remotes.contains("origin") ? "origin" : remotes.first ?? "")
        remote = UI.popup(remotes, selected: chosen)
        let names = Git.remoteBranches(repo).filter { $0.hasPrefix(chosen + "/") }.map { String($0.dropFirst(chosen.count + 1)) }
        branch = UI.combo(names, value: upstream?.branch ?? Git.currentBranch(repo) ?? "")
        branch.isEnabled = merging
        for box in [squash, noCommit, noFF, ffOnly] { box.isEnabled = merging }
        form.section(L.t("Сервер", "Remote"))
        form.row(L.t("Сервер:", "Remote:"), remote)
        form.row(L.t("Ветка на сервере:", "Remote Branch:"), branch)
        form.section(L.t("Параметры", "Options"))
        form.grid.addRow(with: [squash, noCommit])
        form.grid.addRow(with: [noFF, ffOnly])
        form.grid.addRow(with: [tags, NSGridCell.emptyContentView])
        form.grid.addRow(with: [prune, NSGridCell.emptyContentView])
        // Два столбца флажков, как в оригинале: правый начинается с середины группы.
        form.grid.column(at: 0).width = 200
        form.grid.column(at: 1).xPlacement = .leading
        form.plain()
        form.wide(rebase)
        finish()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

final class PullDialog: RemoteDialog {
    init(repo: String) {
        super.init(repo: repo, name: L.t("Получить", "Pull"), merging: true)
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
        if squash.state == .on { args.append("--squash") }
        if noCommit.state == .on { args.append("--no-commit") }
        if noFF.state == .on && ffOnly.state != .on { args.append("--no-ff") }
        if prune.state == .on { args.append("--prune") }
        if tags.state == .on { args.append("--tags") }
        return [args + [remoteName, name]]
    }
}

final class FetchDialog: RemoteDialog {
    init(repo: String) {
        super.init(repo: repo, name: L.t("Извлечь", "Fetch"), merging: false)
        prune.state = .on
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func steps() -> [[String]]? {
        var args = ["fetch", "--progress"]
        if prune.state == .on { args.append("--prune") }
        if tags.state == .on { args.append("--tags") }
        args.append(remote.titleOfSelectedItem ?? "--all")
        var steps = [args]
        // «Launch Rebase After Fetch»: после получения переносим свои фиксации поверх ветки сервера.
        if rebase.state == .on, let remoteName = remote.titleOfSelectedItem, !branch.stringValue.isEmpty {
            steps.append(["rebase", "\(remoteName)/\(branch.stringValue)"])
        }
        return steps
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
        form.section(L.t("Имя", "Name"))
        form.row(L.t("Ветка", "Branch"), name)
        form.section(L.t("От чего", "Base On"))
        form.wide(chooser.view)
        form.section(L.t("Параметры", "Options"))
        form.wide(UI.row([track, UI.spacer(), force, UI.spacer(), switchTo]))
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
    private let message = UI.field(width: 400)
    private let force = UI.check(L.t("Переставить, если метка уже есть", "Force"))

    init(repo: String, preset: String? = nil) {
        super.init(repo: repo, name: L.t("Создать метку", "Create Tag"))
        chooser = RefChooser(repo: repo, allowHead: true, preset: preset)
        form.section(L.t("Имя", "Name"))
        form.row(L.t("Метка", "Tag"), name)
        form.section(L.t("На чём", "Base On"))
        form.wide(chooser.view)
        form.section(L.t("Параметры", "Options"))
        form.wide(force)
        form.section(L.t("Сообщение", "Message"))
        form.wide(message)
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
    private let ffOnly = UI.check(L.t("Только перемотка", "Fast Forward Only"))
    private let message = UI.field(placeholder: "<Auto Generated by Git>", width: 400)

    init(repo: String) {
        super.init(repo: repo, name: L.t("Слить", "Merge"))
        chooser = RefChooser(repo: repo, allowHead: false)
        form.section(L.t("Слить в «\(Git.headName(repo))» из", "From"))
        form.wide(chooser.view)
        form.section(L.t("Параметры", "Option"))
        form.grid.addRow(with: [squash, ffOnly])
        form.grid.addRow(with: [noFF, NSGridCell.emptyContentView])
        form.grid.addRow(with: [noCommit, NSGridCell.emptyContentView])
        form.section(L.t("Сообщение слияния", "Merge Message"))
        form.wide(message)
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
        if ffOnly.state == .on { args.append("--ff-only") } else if noFF.state == .on { args.append("--no-ff") }
        if noCommit.state == .on { args.append("--no-commit") }
        let text = message.stringValue.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty { args += ["-m", text] }
        return [args + [ref]]
    }
}

final class ResetDialog: FormDialog {
    private var chooser: RefChooser!
    private var modes: [NSButton] = []

    /// - Parameter commit: версия из журнала; без неё версию выбирают в окне.
    init(repo: String, commit: Commit? = nil) {
        super.init(repo: repo, name: L.t("Сброс", "Reset"))
        chooser = RefChooser(repo: repo, allowHead: true, preset: commit?.hash)
        form.wide(UI.label(L.t("Текущая ветка: \(Git.headName(repo))", "Current Branch: \(Git.headName(repo))")))
        form.section(L.t("Сбросить на", "Reset To This"))
        form.wide(chooser.view)
        form.section(L.t("Вид сброса", "Reset Type"))
        let titles = [
            L.t("Мягкий: рабочая копия и индекс остаются", "Soft: Leave working tree and index untouched"),
            L.t("Смешанный: рабочая копия остаётся, индекс сбрасывается", "Mixed: Leave working tree untouched, reset index"),
            L.t("Жёсткий: сбросить всё, изменения рабочей копии пропадут", "Hard: Reset working tree and index (discard all local changes)"),
        ]
        let group = UI.column(titles.map { title in
            let radio = WinRadio(title, target: self, action: #selector(pick))
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
        guard let ref = chooser.ref else {
            UI.alert(L.t("Не выбрана версия.", "No version is selected."))
            return nil
        }
        let index = modes.firstIndex { $0.state == .on } ?? 1
        if index == 2, !UI.confirm(L.t("Жёсткий сброс: несохранённые изменения пропадут.", "Hard reset: uncommitted changes will be lost."),
                                   info: L.t("Отменить это нельзя.", "This cannot be undone."), ok: L.t("Сбросить", "Reset")) {
            return nil
        }
        return [["reset", ["--soft", "--mixed", "--hard"][index], ref]]
    }
}

/// «Clean up»: удалить из рабочей копии файлы, которых нет под версией.
final class CleanupDialog: FormDialog {
    private let specs: [String]
    private var kinds: [NSButton] = []
    private let directories = UI.check(L.t("Удалять и папки не под версией", "Remove untracked directories"), on: true)
    private let dryRun = UI.check(L.t("Пробный прогон: только показать", "Dry run"), on: true)

    init(repo: String, specs: [String]) {
        self.specs = specs
        super.init(repo: repo, name: L.t("Очистка", "Clean"))
        form.section(L.t("Что удалять", "Clean Type"))
        let titles = [
            L.t("Все файлы не под версией", "Clean all untracked files"),
            L.t("Не под версией, кроме игнорируемых", "Clean only non-ignore untracked files"),
            L.t("Только игнорируемые", "Clean only ignored files"),
        ]
        form.wide(UI.column(titles.map { title in
            let radio = WinRadio(title, target: self, action: #selector(pick))
            kinds.append(radio)
            return radio
        }, spacing: 6))
        kinds[1].state = .on
        form.section(L.t("Параметры", "Options"))
        form.wide(directories)
        form.wide(dryRun)
        finish()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func pick() {}

    override func steps() -> [[String]]? {
        let kind = kinds.firstIndex { $0.state == .on } ?? 1
        var args = ["clean"]
        if dryRun.state == .on {
            args.append("-n")
        } else {
            // Файлы удаляются мимо Корзины — спрашиваем.
            guard UI.confirm(L.t("Удалить файлы не под версией?", "Delete the untracked files?"),
                             info: L.t("Они удаляются сразу, мимо Корзины. Отменить это нельзя.",
                                       "They are deleted at once, not moved to the Trash. This cannot be undone."),
                             ok: L.t("Удалить", "Delete")) else { return nil }
            args.append("-f")
        }
        if directories.state == .on { args.append("-d") }
        if kind == 0 { args.append("-x") }
        if kind == 2 { args.append("-X") }
        return [args + ["--"] + specs]
    }
}

final class StashDialog: FormDialog {
    private let message = UI.field(width: 400)
    private let untracked = UI.check(L.t("Вместе с файлами не под версией", "include untracked"))
    private let all = UI.check(L.t("И с игнорируемыми (--all)", "--all"))

    init(repo: String) {
        super.init(repo: repo, name: L.t("Спрятать изменения", "Stash"))
        form.section(L.t("Сообщение", "Stash Message"))
        form.wide(message)
        form.section(L.t("Параметры", "Options"))
        form.wide(untracked)
        form.wide(all)
        finish()
        window?.initialFirstResponder = message
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func steps() -> [[String]]? {
        var args = ["stash", "push"]
        if all.state == .on { args.append("--all") } else if untracked.state == .on { args.append("-u") }
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
    private let branch = UI.field(width: 110)
    private let depth = UI.field("1", width: 50)
    private let origin = UI.field(width: 110)
    private let depthOn = UI.check(L.t("Глубина", "Depth"))
    private let branchOn = UI.check(L.t("Ветка", "Branch"))
    private let originOn = UI.check(L.t("Имя сервера", "Origin Name"))
    private let recursive = UI.check(L.t("С подмодулями", "Recursive"))
    private let bare = UI.check(L.t("Без рабочей копии (bare)", "Clone into Bare Repo"))
    private let noCheckout = UI.check(L.t("Не извлекать файлы", "No Checkout"))
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
        form.section(L.t("Клонировать существующее хранилище", "Clone Existing Repository"))
        form.row("URL:", url)
        form.row(L.t("Папка:", "Directory:"), UI.row([directory, browse]))
        form.wide(UI.row([depthOn, depth, recursive, UI.spacer(), bare, UI.spacer(), noCheckout], spacing: 10))
        form.wide(UI.row([branchOn, branch, UI.spacer(), originOn, origin, UI.spacer()], spacing: 10))
        for box in [depthOn, branchOn, originOn] {
            box.target = self
            box.action = #selector(optionsChanged)
        }
        optionsChanged()
        finish()
        suggestDirectory()
        window?.initialFirstResponder = url
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var workDir: String { parent }

    /// Поля глубины, ветки и имени сервера доступны, только когда стоит их флажок.
    @objc private func optionsChanged() {
        depth.isEnabled = depthOn.state == .on
        branch.isEnabled = branchOn.state == .on
        origin.isEnabled = originOn.state == .on
    }

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
        if bare.state == .on { args.append("--bare") }
        if noCheckout.state == .on { args.append("--no-checkout") }
        let branchName = branch.stringValue.trimmingCharacters(in: .whitespaces)
        if branchOn.state == .on, !branchName.isEmpty { args += ["-b", branchName] }
        let originName = origin.stringValue.trimmingCharacters(in: .whitespaces)
        if originOn.state == .on, !originName.isEmpty { args += ["-o", originName] }
        let depthValue = depth.stringValue.trimmingCharacters(in: .whitespaces)
        if depthOn.state == .on {
            guard let number = Int(depthValue), number > 0 else {
                UI.alert(L.t("Глубина — целое число больше нуля.", "Depth must be a positive number."))
                return nil
            }
            args += ["--depth", String(number)]
        }
        return [args + ["--", source, (target as NSString).expandingTildeInPath]]
    }
}

/// «Синхронизация»: получить, извлечь и отправить из одного окна. Окно остаётся открытым между командами.
/// Раскладка — как у Git Synchronization в TortoiseGit: ветки и сервер, список входящих и исходящих фиксаций, кнопки.
final class SyncDialog: ToolWindow, NSTableViewDataSource, NSTableViewDelegate {
    private let repo: String
    private var local: NSComboBox!
    private var remote: NSPopUpButton!
    private var remoteBranch: NSComboBox!
    private let force = UI.check(L.t("Принудительно", "Force"))
    private let state = UI.label("")
    private let hasUpstream: Bool
    private var table: NSTableView!
    private var incoming: [Commit] = []
    private var outgoing: [Commit] = []
    private var showsIncoming = false
    private var inTab: ClosureButton!
    private var outTab: ClosureButton!
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    init(repo: String) {
        self.repo = repo
        let upstream = Git.upstream(repo)
        hasUpstream = upstream != nil
        super.init(title: ToolWindow.title(repo, L.t("Синхронизация", "Git Synchronization")), size: NSSize(width: 700, height: 470))
        let remotes = Git.remotes(repo)
        let chosen = upstream?.remote ?? (remotes.contains("origin") ? "origin" : remotes.first ?? "")
        let current = Git.currentBranch(repo) ?? ""
        local = UI.combo(Git.localBranches(repo), value: current, width: 150)
        let names = Git.remoteBranches(repo).filter { $0.hasPrefix(chosen + "/") }.map { String($0.dropFirst(chosen.count + 1)) }
        remoteBranch = UI.combo(names, value: upstream?.branch ?? current, width: 180)
        remote = UI.popup(remotes, selected: chosen)
        remote.setContentHuggingPriority(.init(1), for: .horizontal)
        for control in [local!, remoteBranch!, remote!] as [NSControl] {
            control.target = self
            control.action = #selector(refresh)
        }

        let branches = UI.row([UI.label(L.t("Локальная ветка:", "Local Branch:")), local, UI.spacer(),
                               UI.label(L.t("Ветка на сервере:", "Remote Branch:")), remoteBranch])
        let server = UI.row([UI.label(L.t("Сервер:", "Remote URL:")), remote])
        let options = UI.row([force, UI.spacer()])
        let head = UI.column([branches, server, options], spacing: 7)
        for view in [branches, server, options] { view.widthAnchor.constraint(equalTo: head.widthAnchor).isActive = true }
        let top = WinGroupBox("", content: head)

        let (scroll, table) = UI.table([
            ("sha", "SHA-1", 80), ("message", L.t("Сообщение", "Message"), 330),
            ("author", L.t("Автор", "Author"), 130), ("date", L.t("Дата", "Date"), 140),
        ], flex: 1)
        self.table = table
        table.dataSource = self
        table.delegate = self
        table.allowsMultipleSelection = false

        // Закладки под списком: какие фиксации показывать.
        func tab(_ title: String, incoming: Bool) -> ClosureButton {
            let button = ClosureButton(title) { [weak self] in
                self?.showsIncoming = incoming
                self?.refresh()
            }
            button.look = .link
            button.constraints.forEach { $0.isActive = false }
            return button
        }
        inTab = tab(L.t("Входящие", "In Commits"), incoming: true)
        outTab = tab(L.t("Исходящие", "Out Commits"), incoming: false)
        let tabs = UI.row([inTab, outTab, UI.spacer()], spacing: 14)

        let pull = WinSplitButton([
            (L.t("Получить", "Pull"), { [weak self] in self?.pull(rebase: false) }),
            (L.t("Извлечь", "Fetch"), { [weak self] in self?.fetch(rebase: false) }),
            (L.t("Извлечь и перенести", "Fetch & Rebase"), { [weak self] in self?.fetch(rebase: true) }),
        ])
        let push = WinSplitButton([
            (L.t("Отправить", "Push"), { [weak self] in self?.push(tags: false) }),
            (L.t("Отправить метки", "Push tags"), { [weak self] in self?.push(tags: true) }),
        ])
        let showLog = ClosureButton(Command.log.title) { [repo] in LogController(repo: repo, specs: []).present() }
        let commit = ClosureButton(L.t("Фиксация", "Commit")) { [repo] in CommitController(repo: repo, specs: []).present() }
        let stash = ClosureButton(Command.stashSave.title) { [repo] in StashDialog(repo: repo).present() }
        for button in [showLog, commit, stash] { button.widthAnchor.constraint(greaterThanOrEqualToConstant: 124).isActive = true }
        let actions = UI.row([pull, push, UI.spacer()])
        let content = UI.column([top, scroll, tabs, actions, UI.row([showLog, commit, stash, UI.spacer()])], spacing: 8)
        for view in [top, scroll, tabs, actions] as [NSView] { view.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true }
        for view in [top, tabs, actions] as [NSView] { view.setContentHuggingPriority(.required, for: .vertical) }
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true

        install(content, buttons: [closeButton, helpButton], leading: [state])
        watch(repo) { [weak self] in self?.refresh() }
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Сервер, локальная ветка и ветка на сервере; nil — чего-то не хватает (о чём уже сказано).
    private func target() -> (remote: String, local: String, branch: String)? {
        guard let remoteName = remote.titleOfSelectedItem else {
            UI.alert(L.t("У хранилища нет серверов.", "This repository has no remotes."),
                     info: L.t("Добавьте сервер: git remote add origin <адрес>.", "Add one first: git remote add origin <url>."))
            return nil
        }
        let branch = local.stringValue.trimmingCharacters(in: .whitespaces)
        guard !branch.isEmpty else {
            UI.alert(L.t("Не заполнено: локальная ветка", "Missing: local branch"))
            return nil
        }
        let other = remoteBranch.stringValue.trimmingCharacters(in: .whitespaces)
        return (remoteName, branch, other.isEmpty ? branch : other)
    }

    private func pull(rebase: Bool) {
        guard let t = target() else { return }
        // Без явного выбора git отказывается сливать разошедшиеся ветки.
        ProgressController.run(title: Command.pull.plainTitle, dir: repo,
                               steps: [["pull", "--progress", rebase ? "--rebase" : "--no-rebase", t.remote, t.branch]])
    }

    private func fetch(rebase: Bool) {
        guard let t = target() else { return }
        var steps = [["fetch", "--progress", "--prune", t.remote]]
        if rebase { steps.append(["rebase", "\(t.remote)/\(t.branch)"]) }
        ProgressController.run(title: Command.fetch.plainTitle, dir: repo, steps: steps)
    }

    private func push(tags: Bool) {
        guard let t = target() else { return }
        var args = ["push", "--progress"]
        if force.state == .on {
            guard UI.confirm(L.t("Отправить принудительно?", "Force push?"),
                             info: L.t("Фиксации на сервере, которых нет у вас, будут потеряны.", "Commits on the remote that you do not have will be lost."),
                             ok: L.t("Отправить принудительно", "Force Push")) else { return }
            args.append("--force")
        }
        if tags { args.append("--tags") }
        // Ветка ещё ни за чем не следит — запоминаем, куда отправили.
        if !hasUpstream { args.append("-u") }
        ProgressController.run(title: Command.push.plainTitle, dir: repo,
                               steps: [args + [t.remote, t.local == t.branch ? t.local : "\(t.local):\(t.branch)"]])
    }

    /// Входящие и исходящие фиксации — по тому, что известно после последнего Fetch.
    @objc private func refresh() {
        inTab.linkBold = showsIncoming
        outTab.linkBold = !showsIncoming
        guard let remoteName = remote.titleOfSelectedItem else {
            state.stringValue = L.t("У хранилища нет серверов.", "This repository has no remotes.")
            return
        }
        let branch = local.stringValue.trimmingCharacters(in: .whitespaces)
        let other = remoteBranch.stringValue.trimmingCharacters(in: .whitespaces)
        let tracking = "\(remoteName)/\(other.isEmpty ? branch : other)"
        guard Git.run(["rev-parse", "--verify", "-q", tracking], in: repo).ok else {
            incoming = []
            outgoing = []
            table.reloadData()
            state.stringValue = L.t("Ветки \(tracking) у вас ещё нет: её создаст Push или покажет Fetch.",
                                    "\"\(tracking)\" is not known here yet: Push creates it, Fetch finds it.")
            return
        }
        outgoing = Git.log(repo, all: false, specs: [], limit: 500, range: "\(tracking)..\(branch)")
        incoming = Git.log(repo, all: false, specs: [], limit: 500, range: "\(branch)..\(tracking)")
        table.reloadData()
        state.stringValue = L.t("К отправке: \(outgoing.count), к получению: \(incoming.count) — «\(tracking)»",
                                "\(outgoing.count) commits ahead, \(incoming.count) behind \"\(tracking)\"")
    }

    private var shown: [Commit] { showsIncoming ? incoming : outgoing }

    func numberOfRows(in tableView: NSTableView) -> Int { shown.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let commit = shown[row]
        switch tableColumn?.identifier.rawValue {
        case "sha": return UI.textCell(String(commit.hash.prefix(8)) + "...")
        case "message": return UI.textCell(commit.subject)
        case "author": return UI.textCell(commit.author)
        case "date": return UI.textCell(dateFormatter.string(from: commit.date))
        default: return nil
        }
    }
}

/// «Stash List»: спрятанные изменения — посмотреть, достать, применить, удалить.
final class StashListController: ToolWindow, NSTableViewDataSource, NSTableViewDelegate {
    private let repo: String
    private var table: NSTableView!
    private var entries: [(ref: String, date: String, message: String)] = []

    init(repo: String) {
        self.repo = repo
        super.init(title: ToolWindow.title(repo, L.t("Спрятанное", "Stash List")), size: NSSize(width: 640, height: 320))
        let (scroll, table) = UI.table([
            ("ref", L.t("Запись", "Reference"), 90), ("date", L.t("Дата", "Date"), 140), ("message", L.t("Сообщение", "Message"), 360),
        ], flex: 2)
        self.table = table
        table.allowsMultipleSelection = false
        table.dataSource = self
        table.delegate = self
        func act(_ title: String, _ args: [String], confirm: String? = nil) -> ClosureButton {
            ClosureButton(title) { [weak self] in
                guard let self, self.table.selectedRow >= 0 else { return NSSound.beep() }
                let ref = self.entries[self.table.selectedRow].ref
                if let confirm, !UI.confirm(confirm, info: ref, ok: title) { return }
                ProgressController.run(title: title, dir: self.repo, steps: [args + [ref]])
            }
        }
        install(scroll, buttons: [closeButton], leading: [
            act(L.t("Показать", "Show"), ["stash", "show", "-p"]),
            act(L.t("Применить", "Stash Apply"), ["stash", "apply"]),
            act(L.t("Достать", "Stash Pop"), ["stash", "pop"]),
            act(L.t("Удалить", "Delete"), ["stash", "drop"], confirm: L.t("Удалить спрятанное?", "Delete this stash?")),
        ])
        watch(repo) { [weak self] in self?.reload() }
        reload()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func reload() {
        entries = Git.run(["stash", "list", "--format=%gd%x1f%ci%x1f%gs"], in: repo).lines.compactMap { line in
            let parts = line.components(separatedBy: "\u{1f}")
            guard parts.count == 3 else { return nil }
            return (parts[0], String(parts[1].prefix(19)), parts[2])
        }
        table.reloadData()
        if !entries.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = entries[row]
        switch tableColumn?.identifier.rawValue {
        case "ref": return UI.textCell(entry.ref)
        case "date": return UI.textCell(entry.date)
        default: return UI.textCell(entry.message)
        }
    }
}

/// «Resolve»: конфликтные файлы и способы их уладить.
final class ResolveController: ToolWindow, NSTableViewDataSource, NSTableViewDelegate {
    private let repo: String
    private var table: NSTableView!
    private var files: [FileChange] = []

    init(repo: String) {
        self.repo = repo
        super.init(title: ToolWindow.title(repo, L.t("Конфликты", "Resolve")), size: NSSize(width: 640, height: 340))
        let (scroll, table) = UI.table([("path", L.t("Путь", "Path"), 460), ("status", L.t("Состояние", "Status"), 120)])
        self.table = table
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(openFile)
        func act(_ title: String, _ steps: @escaping ([String]) -> [[String]]) -> ClosureButton {
            ClosureButton(title) { [weak self] in
                guard let self else { return }
                let paths = self.table.selectedRowIndexes.map { self.files[$0].path }
                guard !paths.isEmpty else { return NSSound.beep() }
                ProgressController.run(title: title, dir: self.repo, steps: steps(paths))
            }
        }
        let hint = UI.label(L.t("Двойной щелчок открывает файл в редакторе. Уладив, отметьте его «Resolved».",
                                "Double-click opens the file in your editor. When done, mark it Resolved."), color: .secondaryLabelColor)
        let content = UI.column([scroll, hint])
        scroll.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        install(content, buttons: [closeButton], leading: [
            act(L.t("Улажен", "Resolved")) { [["add", "--"] + $0] },
            act(L.t("Взять свой", "Resolve conflict using 'mine'")) { [["checkout", "--ours", "--"] + $0, ["add", "--"] + $0] },
            act(L.t("Взять чужой", "Resolve conflict using 'theirs'")) { [["checkout", "--theirs", "--"] + $0, ["add", "--"] + $0] },
            ClosureButton(L.t("Прервать слияние", "Abort Merge")) { [repo] in
                guard Git.isMerging(repo) else {
                    return UI.alert(L.t("Слияние сейчас не идёт.", "No merge is in progress."), style: .informational)
                }
                guard UI.confirm(L.t("Прервать слияние?", "Abort the merge?"),
                                 info: L.t("Рабочая копия вернётся к состоянию до слияния.", "The working tree goes back to the state before the merge."),
                                 ok: L.t("Прервать", "Abort Merge")) else { return }
                ProgressController.run(title: "Abort Merge", dir: repo, steps: [["merge", "--abort"]])
            },
        ])
        watch(repo) { [weak self] in self?.reload() }
        reload()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func reload() {
        files = Git.status(repo).filter { $0.kind == .conflicted }
        table.reloadData()
    }

    @objc private func openFile() {
        let row = table.clickedRow
        guard row >= 0 else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: repo + "/" + files[row].path))
    }

    func numberOfRows(in tableView: NSTableView) -> Int { files.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let file = files[row]
        return UI.textCell(tableColumn?.identifier.rawValue == "path" ? file.path : file.statusText, color: file.color)
    }
}

/// «Ignore»: как и куда записать правило игнорирования.
final class IgnoreDialog: FormDialog {
    private let paths: [String]
    private let byExtension: Bool
    private var types: [NSButton] = []
    private var targets: [NSButton] = []

    init(repo: String, paths: [String], byExtension: Bool) {
        self.paths = paths
        self.byExtension = byExtension
        super.init(repo: repo, name: L.t("Игнорировать", "Ignore"))
        func radios(_ titles: [String], into list: inout [NSButton], action: Selector) -> NSView {
            UI.column(titles.map { title in
                let radio = WinRadio(title, target: self, action: action)
                list.append(radio)
                return radio
            }, spacing: 6)
        }
        form.section(L.t("Как", "Ignore Type"))
        form.wide(radios([
            L.t("Только в папке, где лежит", "Ignore item(s) only in containing folder(s)"),
            L.t("Во всех папках", "Ignore item(s) recursively"),
        ], into: &types, action: #selector(pickType)))
        form.section(L.t("Куда записать", "Ignore File"))
        form.wide(radios([
            L.t(".gitignore в корне хранилища", ".gitignore in the repository root"),
            L.t(".gitignore в папке, где лежит", ".gitignore in the containing directories of the items"),
            L.t(".git/info/exclude (только у вас)", ".git/info/exclude"),
        ], into: &targets, action: #selector(pickTarget)))
        types[0].state = .on
        targets[0].state = .on
        finish()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func pickType() {}
    @objc private func pickTarget() {}

    /// Правила пишем сами, без git: это правка текстового файла.
    override func steps() -> [[String]]? {
        let recursive = types[1].state == .on
        let target = targets.firstIndex { $0.state == .on } ?? 0
        var additions: [String: [String]] = [:]
        for path in paths {
            let folder = (path as NSString).deletingLastPathComponent
            let name = byExtension ? "*." + (path as NSString).pathExtension : (path as NSString).lastPathComponent
            guard name != "*." else { continue }
            let file: String, rule: String
            if target == 1 {
                // В .gitignore самой папки правило пишется относительно неё.
                file = repo + (folder.isEmpty ? "" : "/" + folder) + "/.gitignore"
                rule = recursive ? name : "/" + name
            } else {
                file = repo + (target == 0 ? "/.gitignore" : "/.git/info/exclude")
                rule = recursive ? name : "/" + (folder.isEmpty ? "" : folder + "/") + name
            }
            if !(additions[file] ?? []).contains(rule) { additions[file, default: []].append(rule) }
        }
        for (file, rules) in additions {
            var text = (try? String(contentsOfFile: file, encoding: .utf8)) ?? ""
            let existing = Set(text.components(separatedBy: "\n"))
            let fresh = rules.filter { !existing.contains($0) }
            guard !fresh.isEmpty else { continue }
            if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
            text += fresh.joined(separator: "\n") + "\n"
            do {
                try text.write(toFile: file, atomically: true, encoding: .utf8)
            } catch {
                UI.alert(error.localizedDescription)
                return nil
            }
        }
        NotificationCenter.default.post(name: Git.changed, object: repo)
        close()
        return nil
    }
}

/// «Rebase»: перенести фиксации текущей ветки поверх другой версии.
final class RebaseDialog: FormDialog {
    private var chooser: RefChooser!
    private let force = UI.check(L.t("Переносить, даже если ветка уже поверх", "Force Rebase"))
    private let autostash = UI.check(L.t("Спрятать и вернуть несохранённые изменения", "Autostash"))

    init(repo: String) {
        super.init(repo: repo, name: L.t("Перенос", "Rebase"))
        chooser = RefChooser(repo: repo, allowHead: false)
        form.wide(UI.label(L.t("Ветка: \(Git.headName(repo))", "Branch: \(Git.headName(repo))")))
        form.section(L.t("Поверх чего", "UpStream"))
        form.wide(chooser.view)
        form.section(L.t("Параметры", "Options"))
        form.wide(force)
        form.wide(autostash)
        finish(ok: L.t("Начать перенос", "Start Rebase"))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func steps() -> [[String]]? {
        guard let ref = chooser.ref else {
            UI.alert(L.t("Не выбрана версия.", "No version is selected."))
            return nil
        }
        var args = ["rebase"]
        if force.state == .on { args.append("--force-rebase") }
        if autostash.state == .on { args.append("--autostash") }
        return [args + [ref]]
    }
}

/// «Export»: содержимое выбранной версии одним zip-файлом, без истории.
final class ExportDialog: FormDialog {
    private var chooser: RefChooser!
    private let file: NSTextField

    init(repo: String) {
        file = UI.field((repo as NSString).deletingLastPathComponent + "/" + (repo as NSString).lastPathComponent + ".zip", width: 360)
        super.init(repo: repo, name: L.t("Экспорт", "Export"))
        chooser = RefChooser(repo: repo, allowHead: true)
        let browse = ClosureButton("...") { [weak self] in self?.browse() }
        browse.constraints.forEach { $0.isActive = false }
        browse.widthAnchor.constraint(equalToConstant: 28).isActive = true
        form.section(L.t("Куда", "Export To"))
        form.row(L.t("Файл zip:", "Zip File:"), UI.row([file, browse]))
        form.section(L.t("Какую версию", "Base On"))
        form.wide(chooser.view)
        finish()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func browse() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = (file.stringValue as NSString).lastPathComponent
        panel.directoryURL = URL(fileURLWithPath: (file.stringValue as NSString).deletingLastPathComponent)
        if panel.runModal() == .OK, let url = panel.url { file.stringValue = url.path }
    }

    override func steps() -> [[String]]? {
        guard let target = required(file.stringValue, L.t("файл zip", "zip file")), let ref = chooser.ref else { return nil }
        return [["archive", "--format=zip", "-o", (target as NSString).expandingTildeInPath, ref]]
    }
}
