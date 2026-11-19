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

    /// - Parameters:
    ///   - extra: кнопки, доступные после успеха (например «Отправить…» после фиксации).
    ///   - onFinish: вызывается один раз, когда все команды отработали или одна упала.
    @discardableResult
    static func run(title: String, dir: String, steps: [[String]], extra: [(String, () -> Void)] = [],
                    onFinish: ((Bool) -> Void)? = nil) -> ProgressController {
        let controller = ProgressController(title: title, dir: dir, steps: steps, extra: extra, onFinish: onFinish)
        controller.present()
        controller.next()
        return controller
    }

    private init(title: String, dir: String, steps: [[String]], extra: [(String, () -> Void)], onFinish: ((Bool) -> Void)?) {
        self.dir = dir
        self.steps = steps
        self.onFinish = onFinish
        let (scroll, text) = UI.textView(editable: false, mono: true)
        self.text = text
        super.init(title: ToolWindow.title(dir, title), size: NSSize(width: 640, height: 380))
        bar.style = .bar
        bar.isIndeterminate = true
        bar.translatesAutoresizingMaskIntoConstraints = false
        let content = UI.column([scroll, bar])
        scroll.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        bar.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        closeControl = ClosureButton(L.t("Прервать", "Abort"), key: "\u{1b}") { [weak self] in self?.closeOrAbort() }
        extraButtons = extra.map { title, action in
            let button = ClosureButton(title) { [weak self] in
                self?.close()
                action()
            }
            button.isEnabled = false
            return button
        }
        install(content, buttons: extraButtons + [closeControl])
        bar.startAnimation(nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func next() {
        guard !steps.isEmpty else { return finish(status: 0) }
        let args = steps.removeFirst()
        started = Date()
        running = true
        append("git " + args.map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ") + "\n",
               color: .labelColor, bold: true)
        let task = GitTask()
        self.task = task
        task.start(args, in: dir, onOutput: { [weak self] chunk in self?.feed(chunk) }, onExit: { [weak self] status in
            guard let self else { return }
            self.running = false
            self.endLine()
            if status == 0 {
                let ms = Int(Date().timeIntervalSince(self.started) * 1000)
                self.append(L.t("Успешно (\(ms) мс)\n\n", "Success (\(ms) ms)\n\n"), color: NSColor(hex: 0x0032A0), bold: false)
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
        } else {
            extraButtons.forEach { $0.isEnabled = true }
        }
        NotificationCenter.default.post(name: Git.changed, object: dir)
        onFinish?(status == 0)
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
