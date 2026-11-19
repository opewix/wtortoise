import AppKit

/// Строка файла и фиксация, которая её последней меняла.
struct BlameLine {
    let hash: String
    let author: String
    let date: Date
    let summary: String
    let number: Int
    let text: String
    /// Первая строка подряд идущего куска одной фиксации — на ней пишем хеш и автора.
    var startsBlock = true
    /// Чётность куска — для чередования фона.
    var band = false

    var isUncommitted: Bool { hash.allSatisfy { $0 == "0" } }
}

extension Git {
    static func blame(_ repo: String, path: String) -> (lines: [BlameLine], error: String) {
        let out = run(["blame", "--line-porcelain", "--", path], in: repo)
        guard out.ok else { return ([], out.err) }
        var lines: [BlameLine] = []
        var hash = "", author = "", summary = "", time: TimeInterval = 0, number = 0
        for raw in out.out.components(separatedBy: "\n") {
            if raw.hasPrefix("\t") {
                var line = BlameLine(hash: hash, author: author, date: Date(timeIntervalSince1970: time), summary: summary,
                                     number: number, text: String(raw.dropFirst()).replacingOccurrences(of: "\t", with: "    "))
                if let last = lines.last {
                    line.startsBlock = last.hash != hash
                    line.band = line.startsBlock ? !last.band : last.band
                }
                lines.append(line)
            } else if raw.hasPrefix("author ") {
                author = String(raw.dropFirst(7))
            } else if raw.hasPrefix("author-time ") {
                time = TimeInterval(raw.dropFirst(12)) ?? 0
            } else if raw.hasPrefix("summary ") {
                summary = String(raw.dropFirst(8))
            } else {
                // Заголовок записи: «хеш строка-в-исходном строка-в-итоговом [число строк]».
                let parts = raw.split(separator: " ")
                if parts.count >= 3, parts[0].count >= 40, let final = Int(parts[2]) {
                    hash = String(parts[0])
                    number = final
                }
            }
        }
        return (lines, "")
    }
}

/// «Авторы строк»: кто и когда последним менял каждую строку файла.
final class BlameController: ToolWindow, NSTableViewDataSource, NSTableViewDelegate {
    private let repo: String
    private let lines: [BlameLine]
    private var table: NSTableView!
    private let summary = UI.label("", color: .secondaryLabelColor)
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter
    }()

    static func open(repo: String, path: String) {
        let result = Git.blame(repo, path: path)
        guard !result.lines.isEmpty else {
            return UI.alert(L.t("Не удалось получить авторов строк.", "Could not get the blame."),
                            info: result.error.isEmpty ? path : result.error)
        }
        BlameController(repo: repo, path: path, lines: result.lines).present()
    }

    private init(repo: String, path: String, lines: [BlameLine]) {
        self.repo = repo
        self.lines = lines
        super.init(title: "\(path) - \(L.t("Авторы строк", "Blame")) - WTortoise", size: NSSize(width: 1040, height: 680))
        let (scroll, table) = UI.table([
            ("rev", L.t("Версия", "Revision"), 72), ("author", L.t("Автор", "Author"), 130),
            ("date", L.t("Дата", "Date"), 80), ("line", "#", 44), ("text", path, 660),
        ], flex: 4)
        self.table = table
        table.allowsMultipleSelection = false
        table.rowHeight = 17
        table.intercellSpacing = NSSize(width: 6, height: 0)
        table.dataSource = self
        table.delegate = self
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem(L.t("Скопировать SHA-1", "Copy SHA-1 to clipboard")) { [weak self] in
            guard let self, self.table.clickedRow >= 0 else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(self.lines[self.table.clickedRow].hash, forType: .string)
        })
        menu.addItem(ClosureMenuItem(L.t("Показать журнал файла", "Show log of the file"), glyph: .log) {
            LogController(repo: repo, specs: [path]).present()
        })
        table.menu = menu
        install(scroll, buttons: [closeButton], leading: [summary])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func numberOfRows(in tableView: NSTableView) -> Int { lines.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let line = lines[row]
        let mono = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let cell: NSTableCellView
        switch tableColumn?.identifier.rawValue {
        case "rev":
            cell = UI.textCell(line.startsBlock ? (line.isUncommitted ? "—" : String(line.hash.prefix(8))) : "", color: NSColor(hex: 0x0032A0))
            cell.textField?.font = mono
        case "author":
            cell = UI.textCell(line.startsBlock ? (line.isUncommitted ? L.t("не зафиксировано", "not committed") : line.author) : "")
        case "date":
            cell = UI.textCell(line.startsBlock && !line.isUncommitted ? dateFormatter.string(from: line.date) : "", color: .secondaryLabelColor)
        case "line":
            cell = UI.textCell(String(line.number), color: .secondaryLabelColor, alignment: .right)
            cell.textField?.font = mono
        default:
            cell = UI.textCell(line.text)
            cell.textField?.font = mono
        }
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = BandRowView()
        view.band = lines[row].band
        return view
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard table.selectedRow >= 0 else { return summary.stringValue = "" }
        let line = lines[table.selectedRow]
        summary.stringValue = line.isUncommitted ? L.t("Строка ещё не зафиксирована", "This line is not committed yet")
            : "\(line.hash.prefix(8))  \(line.author):  \(line.summary)"
    }
}

/// Строка таблицы с фоном через кусок — видно, где кончается одна фиксация и начинается другая.
private final class BandRowView: NSTableRowView {
    var band = false

    override func drawBackground(in dirtyRect: NSRect) {
        (band ? NSColor(hex: 0xEEF3FA) : NSColor.white).setFill()
        dirtyRect.fill()
    }
}
