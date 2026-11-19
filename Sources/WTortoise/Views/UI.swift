import AppKit

/// Кнопка с замыканием вместо target/action.
final class ClosureButton: NSButton {
    private var handler: (() -> Void)?

    convenience init(_ title: String, key: String = "", handler: @escaping () -> Void) {
        self.init(title: title, target: nil, action: nil)
        target = self
        action = #selector(fire)
        self.handler = handler
        keyEquivalent = key
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(greaterThanOrEqualToConstant: 86).isActive = true
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
        label.font = bold ? .boldSystemFont(ofSize: 12) : .systemFont(ofSize: 12)
        label.textColor = color
        label.lineBreakMode = .byTruncatingMiddle
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    static func field(_ value: String = "", placeholder: String = "", width: CGFloat = 280) -> NSTextField {
        let field = NSTextField(string: value)
        field.placeholderString = placeholder
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(greaterThanOrEqualToConstant: width).isActive = true
        return field
    }

    static func combo(_ items: [String], value: String = "", width: CGFloat = 280) -> NSComboBox {
        let combo = NSComboBox()
        combo.addItems(withObjectValues: items)
        combo.stringValue = value
        combo.completes = true
        combo.numberOfVisibleItems = 14
        combo.translatesAutoresizingMaskIntoConstraints = false
        combo.widthAnchor.constraint(greaterThanOrEqualToConstant: width).isActive = true
        return combo
    }

    static func popup(_ items: [String], selected: String? = nil) -> NSPopUpButton {
        let popup = NSPopUpButton()
        popup.addItems(withTitles: items)
        if let selected, items.contains(selected) { popup.selectItem(withTitle: selected) }
        return popup
    }

    static func check(_ title: String, on: Bool = false) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        button.state = on ? .on : .off
        return button
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
        let scroll = NSTextView.scrollableTextView()
        let text = scroll.documentView as! NSTextView
        text.isEditable = editable
        text.isRichText = false
        text.allowsUndo = true
        text.font = mono ? .monospacedSystemFont(ofSize: 11, weight: .regular) : .systemFont(ofSize: 12)
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.isAutomaticTextReplacementEnabled = false
        text.textContainerInset = NSSize(width: 2, height: 4)
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        return (scroll, text)
    }

    /// Таблица с колонками; `flex` — номер колонки, которая растягивается вместе с окном.
    static func table(_ columns: [(id: String, title: String, width: CGFloat)], flex: Int = 0) -> (NSScrollView, NSTableView) {
        let table = NSTableView()
        for (index, spec) in columns.enumerated() {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(spec.id))
            column.title = spec.title
            column.width = spec.width
            column.minWidth = 30
            column.resizingMask = index == flex ? [.autoresizingMask, .userResizingMask] : .userResizingMask
            table.addTableColumn(column)
        }
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.rowHeight = 20
        table.style = .plain
        table.usesAlternatingRowBackgroundColors = false
        table.allowsMultipleSelection = true
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        return (scroll, table)
    }

    /// Ячейка с текстом для таблицы.
    static func textCell(_ text: String, color: NSColor = .labelColor, alignment: NSTextAlignment = .left) -> NSTableCellView {
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: text)
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

/// Форма «подпись — поле» для диалогов.
final class Form {
    let grid = NSGridView(numberOfColumns: 2, rows: 0)

    init() {
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.rowAlignment = .firstBaseline
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.column(at: 1).xPlacement = .fill
    }

    func row(_ label: String, _ view: NSView) {
        grid.addRow(with: [UI.label(label), view])
    }

    /// Строка на всю ширину формы.
    func wide(_ view: NSView) {
        let row = grid.addRow(with: [view, NSGridCell.emptyContentView])
        row.mergeCells(in: NSRange(location: 0, length: 2))
        row.rowAlignment = .none
    }

    func section(_ title: String) {
        wide(UI.label(title, bold: true))
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
        let bar = UI.row(leading + [UI.spacer()] + buttons)
        // Растягивается содержимое, а не ряд кнопок.
        bar.setHuggingPriority(.required, for: .vertical)
        root.addSubview(content)
        root.addSubview(bar)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            bar.topAnchor.constraint(equalTo: content.bottomAnchor, constant: 12),
            bar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            bar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            bar.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
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

    var closeButton: ClosureButton {
        ClosureButton(L.t("Закрыть", "Close"), key: "\u{1b}") { [weak self] in self?.close() }
    }
}
