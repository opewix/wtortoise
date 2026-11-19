import AppKit

/// Изменённый файл рабочей копии: строка `git status --porcelain`.
struct FileChange: Hashable {
    enum Kind { case modified, added, deleted, renamed, untracked, conflicted }

    var path: String
    var oldPath: String?
    /// Состояние в индексе и в рабочей копии, как их печатает git.
    var x: Character
    var y: Character

    var kind: Kind {
        if x == "?" { return .untracked }
        if x == "U" || y == "U" || (x == "A" && y == "A") || (x == "D" && y == "D") { return .conflicted }
        if x == "R" { return .renamed }
        if x == "A" { return .added }
        if x == "D" || y == "D" { return .deleted }
        return .modified
    }

    var statusText: String {
        switch kind {
        case .modified: return L.t("Изменён", "Modified")
        case .added: return L.t("Добавлен", "Added")
        case .deleted: return L.t("Удалён", "Deleted")
        case .renamed: return L.t("Переименован", "Renamed")
        case .untracked: return L.t("Не под версией", "Unknown")
        case .conflicted: return L.t("Конфликт", "Conflicted")
        }
    }

    /// Цвета строк как в TortoiseGit: изменён — синий, добавлен — лиловый, удалён — бордовый.
    var color: NSColor {
        switch kind {
        case .modified, .renamed: return NSColor(hex: 0x0032A0)
        case .added: return NSColor(hex: 0x640064)
        case .deleted: return NSColor(hex: 0x640000)
        case .untracked: return .labelColor
        case .conflicted: return NSColor(hex: 0xD00000)
        }
    }

    var ext: String {
        let e = (path as NSString).pathExtension
        return e.isEmpty ? "" : "." + e
    }

    /// Пути для команд git: у переименованного — оба.
    var pathspecs: [String] { oldPath.map { [$0, path] } ?? [path] }
}

extension Git {
    /// Изменения рабочей копии; `specs` — ограничить путями относительно корня.
    static func status(_ repo: String, specs: [String] = []) -> [FileChange] {
        let records = run(["status", "--porcelain", "-z", "-uall", "--"] + specs, in: repo).records
        var result: [FileChange] = []
        var index = 0
        while index < records.count {
            let record = records[index]
            index += 1
            guard record.count > 3 else { continue }
            let chars = Array(record)
            var change = FileChange(path: String(chars[3...]), oldPath: nil, x: chars[0], y: chars[1])
            if (change.x == "R" || change.x == "C"), index < records.count {
                change.oldPath = records[index]
                index += 1
            }
            result.append(change)
        }
        return result.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// Добавлено и убрано строк по файлам относительно HEAD.
    static func numstat(_ repo: String) -> [String: (added: Int, removed: Int)] {
        guard hasHead(repo) else { return [:] }
        let records = run(["diff", "HEAD", "--numstat", "-z", "-M"], in: repo).records
        var result: [String: (Int, Int)] = [:]
        var index = 0
        while index < records.count {
            let parts = records[index].split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            index += 1
            guard parts.count == 3 else { continue }
            var path = String(parts[2])
            if path.isEmpty, index + 1 < records.count {
                path = records[index + 1]
                index += 2
            }
            result[path] = (Int(parts[0]) ?? 0, Int(parts[1]) ?? 0)
        }
        return result
    }

    /// Команды, возвращающие файлы к состоянию HEAD. Файлы не под версией не трогаем.
    static func revertSteps(_ files: [FileChange]) -> [[String]] {
        var steps: [[String]] = []
        let added = files.filter { $0.kind == .added }.map(\.path)
        if !added.isEmpty { steps.append(["rm", "--cached", "-f", "-q", "--"] + added) }
        for file in files where file.kind == .renamed {
            guard let old = file.oldPath else { continue }
            steps.append(["reset", "-q", "HEAD", "--", old, file.path])
            steps.append(["checkout", "--", old])
        }
        let rest = files.filter { [.modified, .deleted, .conflicted].contains($0.kind) }.map(\.path)
        if !rest.isEmpty { steps.append(["checkout", "HEAD", "--"] + rest) }
        return steps
    }
}

// MARK: Журнал

struct Commit {
    let hash: String
    let parents: [String]
    let author: String
    let email: String
    let date: Date
    let refs: [String]
    let subject: String
}

/// Как строка журнала рисует граф: дорожки — столбцы слева направо.
struct GraphRow {
    var column = 0
    /// Дорожки, идущие мимо сверху вниз.
    var through: [Int] = []
    /// Дорожки, приходящие сверху в узел.
    var joins: [Int] = []
    /// Дорожки, уходящие из узла вниз, к родителям.
    var forks: [Int] = []
    var width: Int { (through + joins + forks + [column]).max()! + 1 }
}

/// Файл, изменённый фиксацией.
struct CommitFile {
    let status: String
    let path: String
    let oldPath: String?

    var statusText: String {
        switch status.first {
        case "A": return L.t("Добавлен", "Added")
        case "D": return L.t("Удалён", "Deleted")
        case "R": return L.t("Переименован", "Renamed")
        case "C": return L.t("Скопирован", "Copied")
        default: return L.t("Изменён", "Modified")
        }
    }

    var color: NSColor {
        switch status.first {
        case "A": return NSColor(hex: 0x640064)
        case "D": return NSColor(hex: 0x640000)
        default: return NSColor(hex: 0x0032A0)
        }
    }
}

extension Git {
    static func log(_ repo: String, all: Bool, specs: [String], limit: Int) -> [Commit] {
        var args = ["log", "--date-order", "-n", String(limit),
                    "--pretty=format:%H%x1f%P%x1f%an%x1f%ae%x1f%at%x1f%D%x1f%s%x1e"]
        if all { args.append("--all") }
        args.append("--")
        args += specs
        let out = run(args, in: repo)
        return out.out.split(separator: "\u{1e}").compactMap { record in
            let fields = record.trimmingCharacters(in: .newlines)
                .split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 7 else { return nil }
            return Commit(hash: fields[0], parents: fields[1].split(separator: " ").map(String.init),
                          author: fields[2], email: fields[3],
                          date: Date(timeIntervalSince1970: TimeInterval(fields[4]) ?? 0),
                          refs: fields[5].isEmpty ? [] : fields[5].components(separatedBy: ", "),
                          subject: fields[6])
        }
    }

    /// Раскладка графа: каждая дорожка ждёт своего следующего коммита.
    static func graph(_ commits: [Commit]) -> [GraphRow] {
        var lanes: [String?] = []
        func freeLane() -> Int {
            if let free = lanes.firstIndex(where: { $0 == nil }) { return free }
            lanes.append(nil)
            return lanes.count - 1
        }
        var rows: [GraphRow] = []
        rows.reserveCapacity(commits.count)
        for commit in commits {
            var row = GraphRow()
            row.joins = lanes.indices.filter { lanes[$0] == commit.hash }
            row.column = row.joins.first ?? freeLane()
            for lane in row.joins { lanes[lane] = nil }
            row.through = lanes.indices.filter { lanes[$0] != nil }
            for (index, parent) in commit.parents.enumerated() {
                if let existing = lanes.firstIndex(where: { $0 == parent }) {
                    row.forks.append(existing)
                } else {
                    let lane = index == 0 ? row.column : freeLane()
                    lanes[lane] = parent
                    row.forks.append(lane)
                }
            }
            while let last = lanes.last, last == nil { lanes.removeLast() }
            rows.append(row)
        }
        return rows
    }

    /// Файлы фиксации (относительно первого родителя).
    static func files(of commit: Commit, in repo: String) -> [CommitFile] {
        let base = commit.parents.first ?? emptyTree
        let records = run(["diff", "--name-status", "-z", "-M", base, commit.hash], in: repo).records
        var result: [CommitFile] = []
        var index = 0
        while index + 1 < records.count {
            let status = records[index]
            guard !status.isEmpty else { break }
            if status.hasPrefix("R") || status.hasPrefix("C"), index + 2 < records.count {
                result.append(CommitFile(status: status, path: records[index + 2], oldPath: records[index + 1]))
                index += 3
            } else {
                result.append(CommitFile(status: status, path: records[index + 1], oldPath: nil))
                index += 2
            }
        }
        return result
    }
}

// MARK: Сравнение

/// Строка окна сравнения: слева было, справа стало.
struct DiffRow {
    enum Kind { case same, changed, removed, added }
    var left: (number: Int, text: String)?
    var right: (number: Int, text: String)?
    var kind: Kind
}

enum DiffParser {
    /// Разбирает вывод `git diff` одного файла (с полным контекстом) в строки «было / стало».
    static func parse(_ text: String) -> (rows: [DiffRow], binary: Bool) {
        var rows: [DiffRow] = []
        var minus: [(Int, String)] = [], plus: [(Int, String)] = []
        var leftNo = 0, rightNo = 0
        var inHunk = false, binary = false, files = 0

        func flush() {
            for i in 0..<max(minus.count, plus.count) {
                let l = i < minus.count ? minus[i] : nil, r = i < plus.count ? plus[i] : nil
                rows.append(DiffRow(left: l.map { (number: $0.0, text: $0.1) }, right: r.map { (number: $0.0, text: $0.1) },
                                    kind: l != nil && r != nil ? .changed : (l != nil ? .removed : .added)))
            }
            minus = []
            plus = []
        }

        let lines = text.components(separatedBy: "\n")
        for (index, raw) in lines.enumerated() {
            let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
            if line.hasPrefix("diff --git ") {
                files += 1
                if files > 1 { break }
                inHunk = false
                continue
            }
            if line.hasPrefix("@@") {
                flush()
                let parts = line.split(separator: " ")
                if parts.count >= 3 {
                    leftNo = Int(parts[1].dropFirst().split(separator: ",")[0]) ?? 1
                    rightNo = Int(parts[2].dropFirst().split(separator: ",")[0]) ?? 1
                }
                inHunk = true
                continue
            }
            guard inHunk else {
                if line.hasPrefix("Binary files ") || line.hasPrefix("GIT binary patch") { binary = true }
                continue
            }
            let body = String(line.dropFirst()).replacingOccurrences(of: "\t", with: "    ")
            switch line.first {
            case "-":
                minus.append((leftNo, body))
                leftNo += 1
            case "+":
                plus.append((rightNo, body))
                rightNo += 1
            case "\\":
                continue
            case " ", nil:
                if line.isEmpty && index == lines.count - 1 { continue }
                flush()
                rows.append(DiffRow(left: (leftNo, body), right: (rightNo, body), kind: .same))
                leftNo += 1
                rightNo += 1
            default:
                continue
            }
        }
        flush()
        return (rows, binary)
    }
}
