import AppKit

/// Две колонки «было / стало» с общей прокруткой. Рисует только видимые строки.
final class DiffView: NSView {
    var rows: [DiffRow] = [] {
        didSet {
            longest = rows.reduce(0) { max($0, $1.left?.text.count ?? 0, $1.right?.text.count ?? 0) }
            resize()
        }
    }

    private let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private(set) lazy var lineHeight: CGFloat = ceil(font.ascender - font.descender + font.leading) + 2
    private lazy var charWidth: CGFloat = ("0" as NSString).size(withAttributes: [.font: font]).width
    private let gutter: CGFloat = 46
    private var longest = 0
    /// Сдвиг текста по горизонтали — общий для обеих колонок.
    private var offset: CGFloat = 0

    // Цвета как в TortoiseGitMerge: убранное — оранжевым, добавленное — жёлтым, пустое место — серым.
    private let removedColor = NSColor(hex: 0xFFD9B8), addedColor = NSColor(hex: 0xFFFFA8)
    private let emptyColor = NSColor(hex: 0xECECEC), gutterColor = NSColor(hex: 0xF3F3F3)
    // Изменённая часть строки — темнее остального.
    private let removedInline = NSColor(hex: 0xFFAE78), addedInline = NSColor(hex: 0xF2DC3A)

    /// Отличающаяся середина пары строк: общие начало и конец отбрасываются.
    private func inlineRange(_ a: String, _ b: String, isLeft: Bool) -> Range<Int>? {
        let left = Array(a), right = Array(b)
        var prefix = 0
        while prefix < left.count, prefix < right.count, left[prefix] == right[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < left.count - prefix, suffix < right.count - prefix,
              left[left.count - 1 - suffix] == right[right.count - 1 - suffix] { suffix += 1 }
        // Строки целиком разные — подсвечивать нечего, вся строка и так цветная.
        guard prefix + suffix > 0 else { return nil }
        let own = isLeft ? left : right
        let range = prefix..<(own.count - suffix)
        return range.isEmpty ? nil : range
    }

    override var isFlipped: Bool { true }

    func resize() {
        let height = max(CGFloat(rows.count) * lineHeight, enclosingScrollView?.contentSize.height ?? 0)
        setFrameSize(NSSize(width: enclosingScrollView?.contentSize.width ?? frame.width, height: height))
        needsDisplay = true
    }

    /// Первые строки участков с отличиями.
    var blocks: [Int] {
        rows.indices.filter { rows[$0].kind != .same && ($0 == 0 || rows[$0 - 1].kind == .same) }
    }

    var firstVisibleRow: Int { Int(visibleRect.minY / lineHeight) }

    func scroll(toRow row: Int) {
        let y = max(0, CGFloat(row) * lineHeight - visibleRect.height / 3)
        scroll(NSPoint(x: 0, y: min(y, max(0, frame.height - visibleRect.height))))
    }

    override func scrollWheel(with event: NSEvent) {
        let dx = event.scrollingDeltaX != 0 ? event.scrollingDeltaX : (event.modifierFlags.contains(.shift) ? event.scrollingDeltaY : 0)
        if abs(dx) > abs(event.scrollingDeltaY) || event.modifierFlags.contains(.shift) {
            let half = bounds.width / 2 - gutter
            let limit = max(0, CGFloat(longest) * charWidth + 12 - half)
            offset = min(max(0, offset - dx * (event.hasPreciseScrollingDeltas ? 1 : 8)), limit)
            needsDisplay = true
        } else {
            super.scrollWheel(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        dirtyRect.fill()
        guard !rows.isEmpty else { return }
        let half = floor(bounds.width / 2)
        let first = max(0, Int(dirtyRect.minY / lineHeight))
        let last = min(rows.count - 1, Int(dirtyRect.maxY / lineHeight))
        guard first <= last else { return }
        let textAttributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let numberStyle = NSMutableParagraphStyle()
        numberStyle.alignment = .right
        let numberAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor(hex: 0x808080), .paragraphStyle: numberStyle,
        ]

        for index in first...last {
            let row = rows[index]
            let y = CGFloat(index) * lineHeight
            for (side, x) in [(row.left, CGFloat(0)), (row.right, half)] {
                let isLeft = x == 0
                let background: NSColor
                if side == nil {
                    background = emptyColor
                } else {
                    switch row.kind {
                    case .same: background = .white
                    case .changed: background = isLeft ? removedColor : addedColor
                    case .removed: background = removedColor
                    case .added: background = addedColor
                    }
                }
                let cell = NSRect(x: x + gutter, y: y, width: half - gutter, height: lineHeight)
                background.setFill()
                cell.fill()
                gutterColor.setFill()
                NSRect(x: x, y: y, width: gutter, height: lineHeight).fill()
                guard let side else { continue }
                if row.kind == .changed, let other = isLeft ? row.right : row.left,
                   let range = isLeft ? inlineRange(side.text, other.text, isLeft: true) : inlineRange(other.text, side.text, isLeft: false) {
                    NSGraphicsContext.saveGraphicsState()
                    cell.clip()
                    (isLeft ? removedInline : addedInline).setFill()
                    NSRect(x: cell.minX + 4 - offset + CGFloat(range.lowerBound) * charWidth, y: y,
                           width: CGFloat(range.count) * charWidth, height: lineHeight).fill()
                    NSGraphicsContext.restoreGraphicsState()
                }
                (String(side.number) as NSString).draw(in: NSRect(x: x, y: y + 2, width: gutter - 6, height: lineHeight),
                                                       withAttributes: numberAttributes)
                NSGraphicsContext.saveGraphicsState()
                cell.clip()
                (side.text as NSString).draw(at: NSPoint(x: cell.minX + 4 - offset, y: y + 1), withAttributes: textAttributes)
                NSGraphicsContext.restoreGraphicsState()
            }
        }
        NSColor(hex: 0xB0B0B0).setFill()
        NSRect(x: half - 0.5, y: dirtyRect.minY, width: 1, height: dirtyRect.height).fill()
    }
}

/// Окно сравнения одного файла.
final class DiffController: ToolWindow {
    private let view = DiffView()
    private let scroll = NSScrollView()

    /// Рабочая копия против последней фиксации.
    static func openWorking(repo: String, file: FileChange) {
        let args: [String]
        if file.kind == .untracked {
            args = ["diff", "--no-index", "-U100000", "--", "/dev/null", file.path]
        } else if Git.hasHead(repo) {
            args = ["diff", "-U100000", "-M", "HEAD", "--"] + file.pathspecs
        } else {
            args = ["diff", "-U100000", "--cached", "--"] + file.pathspecs
        }
        open(repo: repo, path: file.path, args: args,
             left: L.t("Базовая версия", "Base"), right: L.t("Рабочая копия", "Working tree"))
    }

    /// Файл в фиксации против её первого родителя.
    static func openCommit(repo: String, commit: Commit, file: CommitFile) {
        let base = commit.parents.first ?? Git.emptyTree
        let paths = file.oldPath.map { [$0, file.path] } ?? [file.path]
        open(repo: repo, path: file.path, args: ["diff", "-U100000", "-M", base, commit.hash, "--"] + paths,
             left: String(base.prefix(8)), right: String(commit.hash.prefix(8)))
    }

    private static func open(repo: String, path: String, args: [String], left: String, right: String) {
        let output = Git.run(args, in: repo)
        let parsed = DiffParser.parse(output.out)
        if parsed.binary {
            return UI.alert(L.t("Двоичный файл", "Binary file"), info: L.t("«\(path)» — двоичный, построчно не сравнивается.",
                                                                            "“\(path)” is binary and cannot be compared line by line."), style: .informational)
        }
        if parsed.rows.isEmpty {
            return UI.alert(L.t("Отличий нет", "No differences"),
                            info: output.err.isEmpty ? path : output.err, style: .informational)
        }
        DiffController(path: path, rows: parsed.rows, left: left, right: right, repo: repo).present()
    }

    private init(path: String, rows: [DiffRow], left: String, right: String, repo: String) {
        super.init(title: "\(path) - \(L.t("Сравнение", "Diff")) - WTortoise", size: NSSize(width: 1040, height: 680))
        scroll.documentView = view
        view.autoresizingMask = [.width]
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(resized), name: NSView.frameDidChangeNotification,
                                               object: scroll.contentView)
        let leftLabel = UI.label("\(path) : \(left)", bold: true), rightLabel = UI.label("\(path) : \(right)", bold: true)
        let header = UI.row([leftLabel, rightLabel], spacing: 0)
        header.distribution = .fillEqually
        let content = UI.column([header, scroll], spacing: 6)
        header.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        scroll.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true

        let changes = rows.filter { $0.kind != .same }.count
        let summary = UI.label(L.t("Строк с отличиями: \(changes). Сдвиг по горизонтали — Shift и колесо.",
                                   "\(changes) changed line(s). Shift + wheel scrolls sideways."), color: .secondaryLabelColor)
        let previous = ClosureButton(L.t("▲ Предыдущее отличие", "▲ Previous difference")) { [weak self] in self?.jump(-1) }
        previous.keyEquivalent = String(UnicodeScalar(NSF7FunctionKey)!)
        previous.keyEquivalentModifierMask = []
        let next = ClosureButton(L.t("▼ Следующее отличие", "▼ Next difference")) { [weak self] in self?.jump(1) }
        next.keyEquivalent = String(UnicodeScalar(NSF8FunctionKey)!)
        next.keyEquivalentModifierMask = []
        install(content, buttons: [closeButton], leading: [previous, next, summary])
        view.rows = rows
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.view.resize()
            if let first = self.view.blocks.first { self.view.scroll(toRow: first) }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func resized() { view.resize() }

    private func jump(_ direction: Int) {
        let blocks = view.blocks
        // Текущим считаем участок на трети высоты окна — туда же `scroll(toRow:)` ставит найденный.
        let current = view.firstVisibleRow + Int(view.visibleRect.height / 3 / view.lineHeight)
        let target = direction > 0 ? blocks.first { $0 > current + 1 } : blocks.last { $0 < current - 1 }
        if let target { view.scroll(toRow: target) } else { NSSound.beep() }
    }
}
