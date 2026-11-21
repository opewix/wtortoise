import AppKit

/// Кнопка с замыканием вместо target/action.
final class ClosureButton: WinButton {
    private var handler: (() -> Void)?

    convenience init(_ title: String, key: String = "", handler: @escaping () -> Void) {
        self.init(title: title, target: nil, action: nil)
        target = self
        action = #selector(fire)
        self.handler = handler
        keyEquivalent = key
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(greaterThanOrEqualToConstant: 75).isActive = true
    }

    @objc private func fire() { handler?() }
}

final class ClosureMenuItem: NSMenuItem {
    private var handler: (() -> Void)?

    convenience init(_ title: String, glyph: Glyph? = nil, enabled: Bool = true, handler: @escaping () -> Void) {
        self.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        self.handler = handler
        image = glyph?.image()
        if !enabled { action = nil }
    }

    @objc private func fire() { handler?() }
}

enum UI {
    static func label(_ text: String, bold: Bool = false, color: NSColor = .labelColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = bold ? Win.boldFont : Win.font
        label.textColor = color
        label.lineBreakMode = .byTruncatingMiddle
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    static func field(_ value: String = "", placeholder: String = "", width: CGFloat = 280) -> NSTextField {
        let field = WinField(string: value)
        field.applyWinLook()
        field.placeholderString = placeholder
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(greaterThanOrEqualToConstant: width).isActive = true
        return field
    }

    static func combo(_ items: [String], value: String = "", width: CGFloat = 280) -> NSComboBox {
        let combo = WinCombo()
        combo.addItems(withObjectValues: items)
        combo.stringValue = value
        combo.completes = true
        combo.numberOfVisibleItems = 14
        combo.font = Win.font
        combo.bezelStyle = .squareBezel
        combo.isButtonBordered = false
        combo.focusRingType = .none
        combo.translatesAutoresizingMaskIntoConstraints = false
        combo.widthAnchor.constraint(greaterThanOrEqualToConstant: width).isActive = true
        return combo
    }

    static func popup(_ items: [String], selected: String? = nil) -> NSPopUpButton {
        let popup = WinPopUp()
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.addItems(withTitles: items)
        if let selected, items.contains(selected) { popup.selectItem(withTitle: selected) }
        return popup
    }

    static func check(_ title: String, on: Bool = false) -> NSButton {
        WinCheck(title, on: on)
    }

    static func row(_ views: [NSView], spacing: CGFloat = 8) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.distribution = .fill
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    static func column(_ views: [NSView], spacing: CGFloat = 8) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.distribution = .fill
        stack.alignment = .leading
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    /// Пустышка, занимающая свободное место в ряду.
    static func spacer() -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(.init(1), for: .horizontal)
        view.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        return view
    }

    static func textView(editable: Bool, mono: Bool = false) -> (NSScrollView, NSTextView) {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .white
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        text.minSize = .zero
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        scroll.documentView = text
        text.isEditable = editable
        text.isRichText = false
        text.allowsUndo = true
        text.font = mono ? Win.monoFont : Win.font
        text.textColor = Win.text
        text.backgroundColor = .white
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.isAutomaticTextReplacementEnabled = false
        text.textContainerInset = NSSize(width: 2, height: 4)
        UI.winBorder(scroll)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        return (scroll, text)
    }

    /// Рамка списков и полей Windows: одна точка серо-синего цвета вместо объёмной рамки macOS.
    /// Саму линию рисует `WinScrollView` поверх рамки macOS, которая оставляет для неё место.
    static func winBorder(_ scroll: NSScrollView) {
        scroll.borderType = .lineBorder
    }

    /// Таблица с колонками; `flex` — номер колонки, которая растягивается вместе с окном.
    static func table(_ columns: [(id: String, title: String, width: CGFloat)], flex: Int = 0) -> (NSScrollView, NSTableView) {
        let table = WinTableView()
        for (index, spec) in columns.enumerated() {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(spec.id))
            column.title = spec.title
            // Свою ячейку заголовка не ставим: с ней строки списка пропадают при отрисовке окна в картинку.
            // Родной заголовок macOS и так белый с тонкими разделителями — меняем только шрифт.
            column.headerCell.attributedStringValue = NSAttributedString(string: spec.title, attributes: Win.attributes())
            column.width = spec.width
            column.minWidth = 30
            column.resizingMask = index == flex ? [.autoresizingMask, .userResizingMask] : .userResizingMask
            table.addTableColumn(column)
        }
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.rowHeight = Win.rowHeight
        table.style = .plain
        table.intercellSpacing = NSSize(width: 4, height: 0)
        table.backgroundColor = .white
        // Выделение рисует сама таблица (голубая плашка Windows), а не строки macOS.
        table.selectionHighlightStyle = .none
        table.usesAlternatingRowBackgroundColors = false
        table.allowsMultipleSelection = true
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .white
        UI.winBorder(scroll)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        return (scroll, table)
    }

    /// Ячейка с текстом для таблицы.
    static func textCell(_ text: String, color: NSColor = .labelColor, alignment: NSTextAlignment = .left) -> NSTableCellView {
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: text)
        label.font = Win.font
        label.textColor = color
        label.alignment = alignment
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        cell.textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    static func alert(_ message: String, info: String = "", style: NSAlert.Style = .warning) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        alert.alertStyle = style
        alert.runModal()
    }

    static func confirm(_ message: String, info: String = "", ok: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        alert.addButton(withTitle: ok)
        alert.addButton(withTitle: L.t("Отмена", "Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Путь с `~` вместо домашней папки — для заголовков.
    static func short(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}

/// Форма диалога: строки «подпись — поле», собранные в группы с рамкой и заголовком, как в окнах TortoiseGit.
final class Form {
    /// Всё содержимое формы — его и ставят в окно.
    let view = UI.column([], spacing: 8)
    /// Сетка текущей группы: строки добавляются в неё.
    private(set) var grid: NSGridView

    init() {
        grid = Form.makeGrid()
        view.addArrangedSubview(grid)
        grid.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
    }

    private static func makeGrid() -> NSGridView {
        let grid = NSGridView(numberOfColumns: 2, rows: 0)
        grid.rowSpacing = 7
        grid.columnSpacing = 8
        grid.rowAlignment = .firstBaseline
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.column(at: 1).xPlacement = .fill
        return grid
    }

    func row(_ label: String, _ view: NSView) {
        let title = UI.label(label)
        // Подпись не сжимается в «…», а поле или список занимает всю оставшуюся ширину.
        title.setContentCompressionResistancePriority(.required, for: .horizontal)
        title.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentHuggingPriority(.init(1), for: .horizontal)
        grid.addRow(with: [title, view])
    }

    /// Строка на всю ширину группы.
    func wide(_ view: NSView) {
        let row = grid.addRow(with: [view, NSGridCell.emptyContentView])
        row.mergeCells(in: NSRange(location: 0, length: 2))
        row.rowAlignment = .none
    }

    /// Начать группу с рамкой; следующие строки идут в неё.
    func section(_ title: String) {
        // Пустую сетку перед первой группой убираем, чтобы не оставалось зазора.
        if grid.numberOfRows == 0 { grid.removeFromSuperview() }
        grid = Form.makeGrid()
        let box = WinGroupBox(title, content: grid)
        view.addArrangedSubview(box)
        box.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
    }

    /// Закончить группу: следующие строки идут под рамкой, без неё.
    func plain() {
        grid = Form.makeGrid()
        view.addArrangedSubview(grid)
        grid.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
    }
}

/// Окно команды. Не модальное: каждая команда живёт в своём окне, как отдельные окна TortoiseGit.
class ToolWindow: NSWindowController, NSWindowDelegate {
    private(set) static var live: [ToolWindow] = []
    private let fitsContent: Bool
    private var observer: NSObjectProtocol?

    init(title: String, size: NSSize, resizable: Bool = true) {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if resizable { style.insert(.resizable) }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        // Окна светлые и серые, как диалоги Windows, при любой теме macOS.
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = Win.face
        window.contentView = WinFaceView()
        fitsContent = !resizable
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    static func title(_ path: String, _ name: String) -> String {
        "\(UI.short(path)) - \(name) - WTortoise"
    }

    /// Раскладка окна: содержимое, под ним ряд кнопок (слева `leading`, справа `buttons`).
    func install(_ content: NSView, buttons: [NSView], leading: [NSView] = []) {
        guard let root = window?.contentView else { return }
        content.translatesAutoresizingMaskIntoConstraints = false
        let bar = UI.row(leading + [UI.spacer()] + buttons, spacing: 7)
        // Растягивается содержимое, а не ряд кнопок.
        bar.setHuggingPriority(.required, for: .vertical)
        root.addSubview(content)
        root.addSubview(bar)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: root.topAnchor, constant: 11),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 11),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -11),
            bar.topAnchor.constraint(equalTo: content.bottomAnchor, constant: 11),
            bar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 11),
            bar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -11),
            bar.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -11),
        ])
        if fitsContent {
            root.layoutSubtreeIfNeeded()
            window?.setContentSize(root.fittingSize)
        }
    }

    func present() {
        guard let window else { return }
        ToolWindow.live.append(self)
        if Snapshot.active {
            window.setFrameOrigin(NSPoint(x: -6000, y: 100))
            window.orderFront(nil)
            return
        }
        window.center()
        // Несколько окон подряд не ложатся ровно друг на друга.
        let shift = CGFloat((ToolWindow.live.count - 1) % 6) * 24
        window.setFrameOrigin(NSPoint(x: window.frame.minX + shift, y: window.frame.minY - shift))
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Перечитывать окно, когда хранилище меняется.
    func watch(_ repo: String, _ refresh: @escaping () -> Void) {
        observer = NotificationCenter.default.addObserver(forName: Git.changed, object: nil, queue: .main) { note in
            if (note.object as? String) == repo { refresh() }
        }
    }

    func windowWillClose(_ notification: Notification) {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        ToolWindow.live.removeAll { $0 === self }
    }

    var cancelButton: ClosureButton {
        ClosureButton(L.t("Отмена", "Cancel"), key: "\u{1b}") { [weak self] in self?.close() }
    }

    var okButton: ClosureButton {
        ClosureButton("OK", key: "\r") { [weak self] in self?.close() }
    }

    var helpButton: ClosureButton {
        ClosureButton(L.t("Справка", "Help")) { NSWorkspace.shared.open(URL(string: "https://github.com/opewix/wtortoise#readme")!) }
    }

    var closeButton: ClosureButton {
        ClosureButton(L.t("Закрыть", "Close"), key: "\u{1b}") { [weak self] in self?.close() }
    }
}
