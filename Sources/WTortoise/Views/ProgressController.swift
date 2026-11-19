import AppKit

/// «Ход выполнения команды Git»: запускает команды по очереди и показывает их вывод.
final class ProgressController: ToolWindow {
    private let dir: String
    private var steps: [[String]]
    private let onFinish: ((Bool) -> Void)?
    private let text: NSTextView
    private let bar = NSProgressIndicator()
    private var closeControl: ClosureButton!
    private var extraButtons: [ClosureButton] = []
    private var task: GitTask?
    private var started = Date()
    /// Начало текущей строки вывода: `\r` от git переписывает её, а не добавляет новую.
    private var lineStart = 0
    private var line = ""
    private var returned = false
    private var running = false
    private let name: String
    private let login: Login?
    /// Выполняемая команда и её вывод — чтобы распознать отказ в доступе и повторить её после входа.
    private var current: [String] = []
    private var output = ""
    private var signInButton: ClosureButton!

    /// - Parameters:
    ///   - extra: кнопки, доступные после успеха (например «Отправить…» после фиксации).
    ///   - onFinish: вызывается один раз, когда все команды отработали или одна упала.
    @discardableResult
    static func run(title: String, dir: String, steps: [[String]], extra: [(String, () -> Void)] = [],
                    login: Login? = nil, onFinish: ((Bool) -> Void)? = nil) -> ProgressController {
        let controller = ProgressController(title: title, dir: dir, steps: steps, extra: extra, login: login, onFinish: onFinish)
        controller.present()
        controller.next()
        return controller
    }

    private init(title: String, dir: String, steps: [[String]], extra: [(String, () -> Void)], login: Login?,
                 onFinish: ((Bool) -> Void)?) {
        self.name = title
        self.login = login
        self.dir = dir
        self.steps = steps
        self.onFinish = onFinish
        let (scroll, text) = UI.textView(editable: false, mono: true)
        self.text = text
        super.init(title: ToolWindow.title(dir, L.t("Ход выполнения команды Git", "Git Command Progress")), size: NSSize(width: 640, height: 380))
        bar.style = .bar
        bar.isIndeterminate = true
        bar.translatesAutoresizingMaskIntoConstraints = false
        let content = UI.column([scroll, bar])
        scroll.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        bar.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        closeControl = ClosureButton(L.t("Прервать", "Abort"), key: "\u{1b}") { [weak self] in self?.closeOrAbort() }
        extraButtons = extra.map { title, action in
            let button = ClosureButton(title) { [weak self] in
                // Сначала следующее окно, потом закрываем это: программа выходит, когда окон не осталось.
                action()
                self?.close()
            }
            button.isEnabled = false
            return button
        }
        // Появляется, только если сервер отказал в доступе.
        signInButton = ClosureButton(L.t("Войти…", "Sign in...")) { [weak self] in self?.signIn() }
        signInButton.isHidden = true
        install(content, buttons: [signInButton] + extraButtons + [closeControl])
        bar.startAnimation(nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func next() {
        guard !steps.isEmpty else { return finish(status: 0) }
        let args = steps.removeFirst()
        started = Date()
        running = true
        current = args
        output = ""
        append("git " + args.map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ") + "\n",
               color: .labelColor, bold: true)
        let task = GitTask()
        self.task = task
        task.start(args, in: dir, login: login, onOutput: { [weak self] chunk in self?.feed(chunk) }, onExit: { [weak self] status in
            guard let self else { return }
            self.running = false
            self.endLine()
            if status == 0 {
                let ms = Int(Date().timeIntervalSince(self.started) * 1000)
                let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
                self.append(L.t("Успешно (\(ms) мс @ \(stamp))\n\n", "Success (\(ms) ms @ \(stamp))\n\n"), color: NSColor(hex: 0x0032A0), bold: false)
                self.next()
            } else {
                self.finish(status: status)
            }
        })
    }

    private func finish(status: Int32) {
        bar.stopAnimation(nil)
        bar.isHidden = true
        closeControl.title = L.t("Закрыть", "Close")
        closeControl.keyEquivalent = "\r"
        if status != 0 {
            append(L.t("git завершился с ошибкой (код \(status))\n", "git did not exit cleanly (exit code \(status))\n"),
                   color: NSColor(hex: 0xD00000), bold: true)
            if let server = Login.deniedServer(in: output) {
                append(L.t("Сервер \(server) отказал в доступе. Нажмите «Войти…», чтобы войти под другим именем.\n",
                           "\(server) denied access. Press \"Sign in...\" to log in with another account.\n"),
                       color: .labelColor, bold: false)
                signInButton.isHidden = false
            }
        } else {
            extraButtons.forEach { $0.isEnabled = true }
        }
        NotificationCenter.default.post(name: Git.changed, object: dir)
        onFinish?(status == 0)
    }

    /// Спросить имя и пароль и повторить упавшую команду (и те, что шли за ней) уже с ними.
    private func signIn() {
        guard let server = Login.deniedServer(in: output) else { return }
        let steps = [current] + self.steps
        let name = self.name, dir = self.dir
        LoginDialog(server: server, repo: dir) { [weak self] login, remember in
            ProgressController.run(title: name, dir: dir, steps: steps, login: login) { ok in
                // Запоминаем только то, с чем сервер пустил.
                if ok && remember { login.remember(server: server, repo: dir) }
            }
            self?.close()
        }.present()
    }

    private func closeOrAbort() {
        if running {
            steps = []
            task?.cancel()
        } else {
            close()
        }
    }

    override func windowWillClose(_ notification: Notification) {
        if running {
            steps = []
            task?.cancel()
        }
        super.windowWillClose(notification)
    }

    // MARK: Вывод

    private func feed(_ chunk: String) {
        output += chunk
        for ch in chunk {
            if ch == "\n" || ch == "\r\n" {
                endLine()
            } else if ch == "\r" {
                returned = true
            } else {
                if returned {
                    line = ""
                    returned = false
                }
                line.append(ch)
            }
        }
        render()
    }

    private func render() {
        guard let storage = text.textStorage else { return }
        storage.replaceCharacters(in: NSRange(location: lineStart, length: storage.length - lineStart),
                                  with: NSAttributedString(string: line, attributes: attributes(.labelColor, bold: false)))
        text.scrollToEndOfDocument(nil)
    }

    private func endLine() {
        guard !line.isEmpty || returned else { return }
        returned = false
        line.append("\n")
        render()
        line = ""
        lineStart = text.textStorage?.length ?? 0
    }

    private func append(_ string: String, color: NSColor, bold: Bool) {
        guard let storage = text.textStorage else { return }
        storage.append(NSAttributedString(string: string, attributes: attributes(color, bold: bold)))
        lineStart = storage.length
        text.scrollToEndOfDocument(nil)
    }

    private func attributes(_ color: NSColor, bold: Bool) -> [NSAttributedString.Key: Any] {
        [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: bold ? .semibold : .regular), .foregroundColor: color]
    }
}

/// «Вход на сервер»: имя и пароль после отказа в доступе.
final class LoginDialog: ToolWindow {
    private let user: NSTextField
    private let password = NSSecureTextField()
    private let rememberBox = UI.check(L.t("Запомнить для этого хранилища", "Remember for this repository"), on: true)
    private let onLogin: (Login, Bool) -> Void

    init(server: String, repo: String, onLogin: @escaping (Login, Bool) -> Void) {
        self.onLogin = onLogin
        user = UI.field(Git.run(["config", "--get", "credential.\(server).username"], in: repo).trimmed)
        super.init(title: "\(server) - \(L.t("Вход", "Sign in")) - WTortoise", size: NSSize(width: 460, height: 200), resizable: false)
        password.translatesAutoresizingMaskIntoConstraints = false
        password.widthAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
        let form = Form()
        form.row(L.t("Имя пользователя:", "Username:"), user)
        form.row(L.t("Пароль или токен:", "Password or token:"), password)
        let hint = UI.label(L.t("GitHub, GitLab и Bitbucket вместо пароля принимают токен доступа (personal access token).",
                                "GitHub, GitLab and Bitbucket take a personal access token in place of the password."),
                            color: .secondaryLabelColor)
        hint.lineBreakMode = .byWordWrapping
        hint.maximumNumberOfLines = 0
        hint.preferredMaxLayoutWidth = 420
        form.wide(hint)
        form.wide(rememberBox)
        install(form.grid, buttons: [ClosureButton("OK", key: "\r") { [weak self] in self?.submit() }, cancelButton])
        window?.initialFirstResponder = user.stringValue.isEmpty ? user : password
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func submit() {
        let name = user.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !password.stringValue.isEmpty else {
            UI.alert(L.t("Введите имя пользователя и пароль или токен.", "Enter the username and the password or token."))
            return
        }
        onLogin(Login(user: name, password: password.stringValue), rememberBox.state == .on)
        close()
    }
}
