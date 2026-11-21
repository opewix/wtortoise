import AppKit

/// Вид окон как у TortoiseGit в Windows 10: цвета, шрифт и элементы, нарисованные кодом.
/// Родные элементы macOS здесь не годятся — цель в том, чтобы окно совпадало с оригиналом.
enum Win {
    static let face = NSColor(hex: 0xF0F0F0)
    static let buttonFill = NSColor(hex: 0xE1E1E1)
    static let buttonBorder = NSColor(hex: 0xADADAD)
    static let hotFill = NSColor(hex: 0xE5F1FB)
    static let hotBorder = NSColor(hex: 0x0078D7)
    static let pressedFill = NSColor(hex: 0xCCE4F7)
    static let pressedBorder = NSColor(hex: 0x005499)
    static let disabledFill = NSColor(hex: 0xCCCCCC)
    static let disabledBorder = NSColor(hex: 0xBFBFBF)
    static let disabledText = NSColor(hex: 0x838383)
    static let fieldBorder = NSColor(hex: 0x7A7A7A)
    static let listBorder = NSColor(hex: 0x828790)
    static let groupBorder = NSColor(hex: 0xDCDCDC)
    static let headerLine = NSColor(hex: 0xE5E5E5)
    static let selection = NSColor(hex: 0xCCE8FF)
    static let selectionBorder = NSColor(hex: 0x99D1FF)
    static let selectionInactive = NSColor(hex: 0xD9D9D9)
    static let text = NSColor.black
    static let link = NSColor(hex: 0x0066CC)

    static let buttonHeight: CGFloat = 23
    static let rowHeight: CGFloat = 19

    /// Segoe UI, если человек поставил его сам; иначе Tahoma — она входит в macOS и ближе всего к Windows.
    private static let family: String? = ["Segoe UI", "Tahoma"].first {
        NSFontManager.shared.font(withFamily: $0, traits: [], weight: 5, size: 12) != nil
    }
    private static let size: CGFloat = family == "Segoe UI" ? 12 : 11

    static let font: NSFont = make(bold: false)
    static let boldFont: NSFont = make(bold: true)
    /// Шрифт сообщения фиксации и вывода git — моноширинный, как Consolas в оригинале.
    static let monoFont: NSFont = NSFont(name: "Menlo", size: 11) ?? .monospacedSystemFont(ofSize: 11, weight: .regular)

    private static func make(bold: Bool) -> NSFont {
        family.flatMap {
            NSFontManager.shared.font(withFamily: $0, traits: bold ? .boldFontMask : [], weight: bold ? 9 : 5, size: size)
        } ?? (bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size))
    }

    static func attributes(_ color: NSColor = text, bold: Bool = false) -> [NSAttributedString.Key: Any] {
        [.font: bold ? boldFont : font, .foregroundColor: color]
    }

    /// Прямоугольник с рамкой ровно в одну точку.
    static func box(_ rect: NSRect, fill: NSColor?, border: NSColor, width: CGFloat = 1) {
        if let fill {
            fill.setFill()
            rect.fill()
        }
        border.setStroke()
        let path = NSBezierPath(rect: rect.insetBy(dx: width / 2, dy: width / 2))
        path.lineWidth = width
        path.stroke()
    }

    /// Уголок раскрывающегося списка, остриём вниз. Элементы управления перевёрнуты: ось Y идёт вниз.
    static func chevron(in rect: NSRect, color: NSColor) {
        let path = NSBezierPath()
        let cx = rect.midX, cy = rect.midY
        path.move(to: NSPoint(x: cx - 3.5, y: cy - 1.5))
        path.line(to: NSPoint(x: cx, y: cy + 2))
        path.line(to: NSPoint(x: cx + 3.5, y: cy - 1.5))
        path.lineWidth = 1.2
        color.setStroke()
        path.stroke()
    }

    /// Сплошной треугольник вниз — у кнопки с выпадающей частью.
    static func triangle(in rect: NSRect, color: NSColor) {
        let path = NSBezierPath()
        let cx = rect.midX, cy = rect.midY
        path.move(to: NSPoint(x: cx - 3.5, y: cy - 2))
        path.line(to: NSPoint(x: cx + 3.5, y: cy - 2))
        path.line(to: NSPoint(x: cx, y: cy + 2))
        path.close()
        color.setFill()
        path.fill()
    }
}

/// Кнопка Windows 10: серая с рамкой, голубая под указателем, синяя рамка у кнопки по умолчанию.
class WinButton: NSButton {
    enum Look { case push, link }
    var look: Look = .push { didSet { needsDisplay = true; invalidateIntrinsicContentSize() } }
    /// Цвет и жирность слова-ссылки (`look == .link`).
    var linkColor: NSColor = Win.text { didSet { needsDisplay = true } }
    var linkBold = true { didSet { needsDisplay = true; invalidateIntrinsicContentSize() } }
    /// Рисовать справа треугольник раскрытия (кнопка открывает меню).
    var showsArrow = false
    private var hovered = false
    private var area: NSTrackingArea?

    override var intrinsicContentSize: NSSize {
        if look == .link {
            return NSSize(width: ceil((title as NSString).size(withAttributes: Win.attributes(bold: linkBold)).width) + 2, height: 16)
        }
        let width = ceil((title as NSString).size(withAttributes: Win.attributes()).width)
        return NSSize(width: width + 22 + (showsArrow ? 12 : 0) + (image == nil ? 0 : 20), height: Win.buttonHeight)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let fresh = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(fresh)
        area = fresh
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        if look == .link {
            let text = NSAttributedString(string: title, attributes: Win.attributes(isEnabled ? linkColor : Win.disabledText, bold: linkBold))
            text.draw(at: NSPoint(x: 1, y: ((bounds.height - text.size().height) / 2).rounded()))
            return
        }
        let pressed = isHighlighted
        let isDefault = keyEquivalent == "\r"
        if !isEnabled {
            Win.box(bounds, fill: Win.disabledFill, border: Win.disabledBorder)
        } else if pressed {
            Win.box(bounds, fill: Win.pressedFill, border: Win.pressedBorder)
        } else if hovered {
            Win.box(bounds, fill: Win.hotFill, border: Win.hotBorder)
        } else {
            Win.box(bounds, fill: Win.buttonFill, border: isDefault ? Win.hotBorder : Win.buttonBorder, width: isDefault ? 2 : 1)
        }
        let color = isEnabled ? Win.text : Win.disabledText
        let text = NSAttributedString(string: title, attributes: Win.attributes(color))
        let size = text.size()
        let arrow: CGFloat = showsArrow ? 12 : 0
        // Значок, если он есть, стоит слева от подписи и центрируется вместе с ней.
        let icon: CGFloat = image == nil ? 0 : 20
        let x = ((bounds.width - arrow - size.width - icon) / 2).rounded()
        if let image {
            image.draw(in: NSRect(x: x, y: ((bounds.height - 16) / 2).rounded(), width: 16, height: 16), from: .zero,
                       operation: .sourceOver, fraction: isEnabled ? 1 : 0.4, respectFlipped: true, hints: nil)
        }
        text.draw(at: NSPoint(x: x + icon, y: ((bounds.height - size.height) / 2).rounded()))
        if showsArrow {
            Win.triangle(in: title.isEmpty ? bounds : NSRect(x: bounds.maxX - 18, y: 0, width: 12, height: bounds.height), color: color)
        }
    }
}

/// Флажок Windows 10: белый квадрат 13×13 с чёрной галочкой.
final class WinCheck: NSButton {
    convenience init(_ title: String, on: Bool = false) {
        self.init(frame: .zero)
        setButtonType(.switch)
        self.title = title
        state = on ? .on : .off
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.defaultHigh, for: .horizontal)
    }

    override var intrinsicContentSize: NSSize {
        guard !title.isEmpty else { return NSSize(width: 13, height: 15) }
        return NSSize(width: 18 + ceil((title as NSString).size(withAttributes: Win.attributes()).width) + 2, height: 17)
    }

    override func draw(_ dirtyRect: NSRect) {
        let box = NSRect(x: 0, y: ((bounds.height - 13) / 2).rounded(), width: 13, height: 13)
        let ink = isEnabled ? NSColor(hex: 0x333333) : NSColor(hex: 0xBCBCBC)
        Win.box(box, fill: isHighlighted ? Win.pressedFill : (isEnabled ? .white : NSColor(hex: 0xE6E6E6)), border: ink)
        if state == .on {
            let mark = NSBezierPath()
            mark.move(to: NSPoint(x: box.minX + 3, y: box.midY))
            mark.line(to: NSPoint(x: box.minX + 5.5, y: box.maxY - 3.5))
            mark.line(to: NSPoint(x: box.maxX - 2.5, y: box.minY + 3))
            mark.lineWidth = 1.5
            ink.setStroke()
            mark.stroke()
        } else if state == .mixed {
            ink.setFill()
            box.insetBy(dx: 3, dy: 3).fill()
        }
        guard !title.isEmpty else { return }
        let text = NSAttributedString(string: title, attributes: Win.attributes(isEnabled ? Win.text : Win.disabledText))
        text.draw(at: NSPoint(x: 18, y: ((bounds.height - text.size().height) / 2).rounded()))
    }
}

/// Переключатель Windows 10: белый кружок с чёрной точкой.
final class WinRadio: NSButton {
    convenience init(_ title: String, target: AnyObject?, action: Selector?) {
        self.init(frame: .zero)
        setButtonType(.radio)
        self.title = title
        self.target = target
        self.action = action
        translatesAutoresizingMaskIntoConstraints = false
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 18 + ceil((title as NSString).size(withAttributes: Win.attributes()).width) + 2, height: 17)
    }

    override func draw(_ dirtyRect: NSRect) {
        let ring = NSRect(x: 0.5, y: ((bounds.height - 12) / 2).rounded() + 0.5, width: 12, height: 12)
        let ink = isEnabled ? NSColor(hex: 0x333333) : NSColor(hex: 0xBCBCBC)
        (isHighlighted ? Win.pressedFill : NSColor.white).setFill()
        let circle = NSBezierPath(ovalIn: ring)
        circle.fill()
        ink.setStroke()
        circle.stroke()
        if state == .on {
            ink.setFill()
            NSBezierPath(ovalIn: ring.insetBy(dx: 3, dy: 3)).fill()
        }
        let text = NSAttributedString(string: title, attributes: Win.attributes(isEnabled ? Win.text : Win.disabledText))
        text.draw(at: NSPoint(x: 18, y: ((bounds.height - text.size().height) / 2).rounded()))
    }
}

/// Выпадающий список Windows 10: серая кнопка с уголком справа.
final class WinPopUp: NSPopUpButton {
    private var hovered = false
    private var area: NSTrackingArea?

    override var intrinsicContentSize: NSSize {
        let widest = itemTitles.map { ceil(($0 as NSString).size(withAttributes: Win.attributes()).width) }.max() ?? 40
        return NSSize(width: max(widest + 34, 80), height: Win.buttonHeight)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let fresh = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(fresh)
        area = fresh
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        if !isEnabled {
            Win.box(bounds, fill: Win.disabledFill, border: Win.disabledBorder)
        } else if hovered {
            Win.box(bounds, fill: Win.hotFill, border: Win.hotBorder)
        } else {
            Win.box(bounds, fill: Win.buttonFill, border: Win.buttonBorder)
        }
        let color = isEnabled ? Win.text : Win.disabledText
        let shown = pullsDown ? (itemArray.first?.title ?? "") : (titleOfSelectedItem ?? "")
        let text = NSAttributedString(string: shown, attributes: Win.attributes(color))
        let clip = NSRect(x: 6, y: 0, width: bounds.width - 26, height: bounds.height)
        NSGraphicsContext.saveGraphicsState()
        clip.clip()
        text.draw(at: NSPoint(x: 6, y: ((bounds.height - text.size().height) / 2).rounded()))
        NSGraphicsContext.restoreGraphicsState()
        Win.chevron(in: NSRect(x: bounds.maxX - 20, y: 0, width: 18, height: bounds.height), color: color)
    }
}

/// Поле ввода Windows 10: белое, рамка в одну точку, синяя в фокусе.
final class WinFieldCell: NSTextFieldCell {
    private func inset(_ rect: NSRect) -> NSRect {
        let height = ceil(cellSize(forBounds: NSRect(x: 0, y: 0, width: 10_000, height: 10_000)).height)
        return NSRect(x: rect.minX + 4, y: rect.minY + ((rect.height - height) / 2).rounded(), width: rect.width - 8, height: height)
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect { super.drawingRect(forBounds: inset(rect)) }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: inset(rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?,
                         start selStart: Int, length selLength: Int) {
        super.select(withFrame: inset(rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
}

final class WinField: NSTextField {
    override class var cellClass: AnyClass? {
        get { WinFieldCell.self }
        set {}
    }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: Win.buttonHeight) }

    func applyWinLook() {
        isBezeled = false
        isBordered = false
        drawsBackground = false
        focusRingType = .none
        font = Win.font
        textColor = Win.text
        usesSingleLineMode = true
        lineBreakMode = .byTruncatingTail
        cell?.isScrollable = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let focused = window?.firstResponder === currentEditor() && currentEditor() != nil
        Win.box(bounds, fill: isEnabled ? .white : Win.face, border: focused ? Win.hotBorder : Win.fieldBorder)
        super.draw(dirtyRect)
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        needsDisplay = true
        return result
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        needsDisplay = true
    }
}

/// Поле со списком Windows 10: белое поле с рамкой и уголком справа.
final class WinCombo: NSComboBox {
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: Win.buttonHeight) }

    override func draw(_ dirtyRect: NSRect) {
        Win.box(bounds, fill: isEnabled ? .white : Win.face, border: Win.fieldBorder)
        super.draw(dirtyRect)
        // Стрелки macOS закрываем своим уголком.
        let button = NSRect(x: bounds.maxX - 19, y: 1, width: 18, height: bounds.height - 2)
        (isEnabled ? NSColor.white : Win.face).setFill()
        button.fill()
        Win.chevron(in: button, color: isEnabled ? Win.text : Win.disabledText)
    }
}

/// Подложка окна: серый фон диалогов Windows.
final class WinFaceView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        Win.face.setFill()
        dirtyRect.fill()
    }
}

/// Группа с рамкой и заголовком в разрыве верхней линии — «Message», «Changes made».
final class WinGroupBox: NSView {
    private let title: String

    init(_ title: String, content: NSView) {
        self.title = title
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor, constant: title.isEmpty ? 9 : 20),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ dirtyRect: NSRect) {
        let top: CGFloat = title.isEmpty ? 0 : 7
        Win.box(NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - top), fill: nil, border: Win.groupBorder)
        guard !title.isEmpty else { return }
        let text = NSAttributedString(string: title, attributes: Win.attributes())
        let size = text.size()
        Win.face.setFill()
        NSRect(x: 7, y: bounds.height - size.height - 1, width: size.width + 4, height: size.height + 1).fill()
        text.draw(at: NSPoint(x: 9, y: bounds.height - size.height))
    }
}

/// Плашка выделения строки: лежит под ячейками в каждой строке списка.
private final class WinSelectionView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        guard let row = superview as? NSTableRowView, row.isSelected else { return }
        let active = (row.superview as? NSTableView).map { $0.window?.firstResponder === $0 } ?? false
        Win.box(bounds, fill: active ? Win.selection : Win.selectionInactive, border: active ? Win.selectionBorder : Win.selectionInactive)
    }
}

/// Список Windows 10: выделение голубой плашкой с рамкой, текст при этом остаётся своего цвета.
/// Методы рисования таблицы не переопределяем: с ними AppKit рисует её по-старому и закрашивает соседей.
final class WinTableView: NSTableView {
    override func didAdd(_ rowView: NSTableRowView, forRow row: Int) {
        super.didAdd(rowView, forRow: row)
        guard !rowView.subviews.contains(where: { $0 is WinSelectionView }) else { return }
        let plate = WinSelectionView(frame: rowView.bounds)
        plate.autoresizingMask = [.width, .height]
        rowView.addSubview(plate, positioned: .below, relativeTo: nil)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSTableView.selectionDidChangeNotification, object: self)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshSelection),
                                               name: NSTableView.selectionDidChangeNotification, object: self)
    }

    @objc private func refreshSelection() {
        enumerateAvailableRowViews { rowView, _ in
            rowView.subviews.first { $0 is WinSelectionView }?.needsDisplay = true
        }
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        refreshSelection()
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        refreshSelection()
        return result
    }
}

/// Кнопка с выпадающей частью, как «Commit ▼» в оригинале: слева действие, справа — выбор другого.
final class WinSplitButton: NSView {
    private let main = WinButton(frame: .zero)
    private let arrow = WinButton(frame: .zero)
    private var choices: [(title: String, action: () -> Void)]
    private var current = 0

    /// Первый вариант — действие по умолчанию. Выбор из списка выполняет вариант и оставляет его на кнопке.
    init(_ choices: [(title: String, action: () -> Void)], key: String = "") {
        self.choices = choices
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        for button in [main, arrow] {
            button.translatesAutoresizingMaskIntoConstraints = false
            button.target = self
            addSubview(button)
        }
        main.title = choices[0].title
        main.keyEquivalent = key
        main.action = #selector(run)
        arrow.title = ""
        arrow.showsArrow = true
        arrow.action = #selector(showChoices)
        NSLayoutConstraint.activate([
            main.leadingAnchor.constraint(equalTo: leadingAnchor), main.topAnchor.constraint(equalTo: topAnchor),
            main.bottomAnchor.constraint(equalTo: bottomAnchor),
            main.widthAnchor.constraint(greaterThanOrEqualToConstant: 96),
            // Общая граница: рамки двух частей сливаются в одну линию.
            arrow.leadingAnchor.constraint(equalTo: main.trailingAnchor, constant: -1),
            arrow.trailingAnchor.constraint(equalTo: trailingAnchor), arrow.topAnchor.constraint(equalTo: topAnchor),
            arrow.bottomAnchor.constraint(equalTo: bottomAnchor), arrow.widthAnchor.constraint(equalToConstant: 19),
            heightAnchor.constraint(equalToConstant: Win.buttonHeight),
        ])
    }

    /// Кнопка, обе части которой открывают меню («Walk Behaviour ▼»). Пункты строятся при каждом открытии.
    convenience init(menuTitle: String, items: @escaping () -> [NSMenuItem]) {
        self.init([(menuTitle, {})])
        menuItems = items
        main.action = #selector(showChoices)
    }

    private var menuItems: (() -> [NSMenuItem])?

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func run() { choices[current].action() }

    @objc private func showChoices() {
        let menu = NSMenu()
        if let menuItems {
            menuItems().forEach(menu.addItem)
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -2), in: self)
            return
        }
        for (index, choice) in choices.enumerated() {
            menu.addItem(ClosureMenuItem(choice.title) { [weak self] in
                guard let self else { return }
                self.current = index
                self.main.title = choice.title
                choice.action()
            })
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -2), in: self)
    }
}

/// Полоса хода Windows 10: серая рамка, зелёная заливка. Пока идёт работа — бегущий отрезок, в конце — целиком.
final class WinProgressBar: NSView {
    enum State { case running, done, failed }
    var state: State = .running {
        didSet {
            if state != .running { timer?.invalidate() }
            needsDisplay = true
        }
    }
    private var phase: CGFloat = 0
    private var timer: Timer?

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 22).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        timer?.invalidate()
        guard window != nil, state == .running else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.phase = (self.phase + 0.012).truncatingRemainder(dividingBy: 1.3)
            self.needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        Win.box(bounds, fill: NSColor(hex: 0xE6E6E6), border: NSColor(hex: 0xBCBCBC))
        let inner = bounds.insetBy(dx: 1, dy: 1)
        switch state {
        case .done:
            NSColor(hex: 0x06B025).setFill()
            inner.fill()
        case .failed:
            NSColor(hex: 0xDA2626).setFill()
            inner.fill()
        case .running:
            let width = inner.width * 0.3
            let x = inner.minX + (phase - 0.3) * inner.width
            NSColor(hex: 0x06B025).setFill()
            NSRect(x: x, y: inner.minY, width: width, height: inner.height).intersection(inner).fill()
        }
    }
}
