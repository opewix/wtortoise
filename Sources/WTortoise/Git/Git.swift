import Foundation

/// Запуск git. Вся работа с хранилищем идёт через сам git — так поведение совпадает с командной строкой.
enum Git {
    /// Хранилище изменилось (object — путь корня): окна перечитывают состояние.
    static let changed = Notification.Name("WTortoiseRepoChanged")
    static let emptyTree = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"

    static var executable: String {
        let custom = Settings.gitPath
        if !custom.isEmpty, FileManager.default.isExecutableFile(atPath: custom) { return custom }
        return detected
    }

    static let detected: String = ["/opt/homebrew/bin/git", "/usr/local/bin/git", "/usr/bin/git"]
        .first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/bin/git"

    private static let prefix = ["-c", "core.quotepath=false", "-c", "color.ui=false"]

    static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        // Вопросы git и ssh (пароль, отпечаток узла) задаёт наше окно, а не терминал, которого нет.
        env["GIT_TERMINAL_PROMPT"] = "0"
        if let askpass = Bundle.main.path(forResource: "askpass", ofType: "sh") {
            env["GIT_ASKPASS"] = askpass
            env["SSH_ASKPASS"] = askpass
            env["SSH_ASKPASS_REQUIRE"] = "prefer"
        }
        // Редактор сообщений не открываем: слияние и отмена берут сообщение по умолчанию.
        env["GIT_EDITOR"] = "true"
        return env
    }

    static func real(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    static func root(of path: String) -> String? {
        RepoPath.root(of: real(path))
    }

    struct Output {
        let status: Int32
        let out: String
        let err: String
        var ok: Bool { status == 0 }
        var trimmed: String { out.trimmingCharacters(in: .whitespacesAndNewlines) }
        var lines: [String] { out.split(separator: "\n").map(String.init) }
        /// Записи вывода с `-z`.
        var records: [String] { out.split(separator: "\0", omittingEmptySubsequences: false).map(String.init) }
    }

    static func makeProcess(_ args: [String], in dir: String, login: Login? = nil) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        var env = environment
        var config = prefix
        if let login {
            // Сохранённые пароли не спрашиваем (пустое значение сбрасывает список помощников): они и привели
            // к отказу. Имя и пароль отдаёт git наш askpass из окружения — в аргументах их не видно.
            config += ["-c", "credential.helper=", "-c", "credential.username=" + login.user]
            env["WTORTOISE_USERNAME"] = login.user
            env["WTORTOISE_PASSWORD"] = login.password
        }
        process.arguments = config + args
        process.currentDirectoryURL = URL(fileURLWithPath: dir)
        process.environment = env
        process.standardInput = FileHandle.nullDevice
        return process
    }

    /// Запустить и дождаться. Для коротких запросов; долгие команды идут через `GitTask`.
    @discardableResult
    static func run(_ args: [String], in dir: String, input: String? = nil) -> Output {
        let process = makeProcess(args, in: dir)
        if let input {
            let stdin = Pipe()
            process.standardInput = stdin
            stdin.fileHandleForWriting.write(Data(input.utf8))
            stdin.fileHandleForWriting.closeFile()
        }
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        // Конца ждём семафором, а не `waitUntilExit`: тот крутит цикл событий, и посреди запроса срабатывало
        // отложенное «закрыто последнее окно» — программа выходила, не успев показать следующее окно.
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do { try process.run() } catch {
            return Output(status: -1, out: "", err: error.localizedDescription)
        }
        // stderr читаем в соседнем потоке: иначе полный буфер одного канала остановит git.
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errData = err.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        exited.wait()
        return Output(status: process.terminationStatus, out: String(decoding: outData, as: UTF8.self),
                      err: String(decoding: errData, as: UTF8.self))
    }

    static func background<T>(_ work: @escaping () -> T, then: @escaping (T) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let value = work()
            DispatchQueue.main.async { then(value) }
        }
    }

    // MARK: Сведения о хранилище

    static func currentBranch(_ repo: String) -> String? {
        let out = run(["symbolic-ref", "--short", "-q", "HEAD"], in: repo)
        return out.ok && !out.trimmed.isEmpty ? out.trimmed : nil
    }

    /// Название того, на чём стоит HEAD: ветка либо короткий хеш.
    static func headName(_ repo: String) -> String {
        if let branch = currentBranch(repo) { return branch }
        let hash = run(["rev-parse", "--short", "HEAD"], in: repo)
        return hash.ok ? hash.trimmed : L.t("(нет фиксаций)", "(no commits)")
    }

    static func hasHead(_ repo: String) -> Bool {
        run(["rev-parse", "--verify", "-q", "HEAD"], in: repo).ok
    }

    static func localBranches(_ repo: String) -> [String] {
        run(["for-each-ref", "--format=%(refname:short)", "refs/heads"], in: repo).lines
    }

    static func remoteBranches(_ repo: String) -> [String] {
        run(["for-each-ref", "--format=%(refname:short)", "refs/remotes"], in: repo).lines
            .filter { !$0.hasSuffix("/HEAD") && $0.contains("/") }
    }

    static func tags(_ repo: String) -> [String] {
        run(["tag", "--sort=-creatordate"], in: repo).lines
    }

    static func remotes(_ repo: String) -> [String] {
        run(["remote"], in: repo).lines
    }

    /// Ветка, за которой следит текущая: (remote, ветка на нём).
    static func upstream(_ repo: String) -> (remote: String, branch: String)? {
        let out = run(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"], in: repo)
        guard out.ok else { return nil }
        let full = out.trimmed
        for remote in remotes(repo).sorted(by: { $0.count > $1.count }) where full.hasPrefix(remote + "/") {
            return (remote, String(full.dropFirst(remote.count + 1)))
        }
        return nil
    }

    static func isMerging(_ repo: String) -> Bool {
        FileManager.default.fileExists(atPath: RepoPath.gitDir(root: repo) + "/MERGE_HEAD")
    }

    static func config(_ key: String, global: Bool = true, in dir: String = NSHomeDirectory()) -> String {
        run(["config"] + (global ? ["--global"] : []) + ["--get", key], in: dir).trimmed
    }
}

/// Долгая команда git с выводом по мере работы (push, pull, clone…).
final class GitTask {
    private var process: Process?

    func start(_ args: [String], in dir: String, login: Login? = nil,
               onOutput: @escaping (String) -> Void, onExit: @escaping (Int32) -> Void) {
        let process = Git.makeProcess(args, in: dir, login: login)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { h in
            let data = h.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async { onOutput(text) }
        }
        process.terminationHandler = { p in
            handle.readabilityHandler = nil
            let rest = String(decoding: handle.readDataToEndOfFile(), as: UTF8.self)
            DispatchQueue.main.async {
                if !rest.isEmpty { onOutput(rest) }
                onExit(p.terminationStatus)
            }
        }
        do {
            try process.run()
            self.process = process
        } catch {
            handle.readabilityHandler = nil
            onOutput(error.localizedDescription + "\n")
            onExit(-1)
        }
    }

    func cancel() {
        process?.terminate()
    }
}

/// Имя и пароль для сервера, введённые человеком после отказа в доступе.
struct Login {
    let user: String
    let password: String

    /// Адрес сервера (`https://узел`), если вывод git говорит об отказе в доступе по HTTP; иначе nil.
    /// Для ssh окно входа не поможет — там ключи, а не пароль.
    static func deniedServer(in output: String) -> String? {
        let lower = output.lowercased()
        let signs = ["error: 403", "error: 401", "authentication failed", "could not read username",
                     "could not read password", "repository not found", "permission to "]
        guard signs.contains(where: lower.contains) else { return nil }
        guard let range = output.range(of: #"https?://[^/'\s]+"#, options: .regularExpression) else { return nil }
        var server = String(output[range])
        // «https://имя@узел» — имя в адрес сервера не входит.
        if let at = server.lastIndex(of: "@"), let slashes = server.range(of: "://") {
            server = String(server[..<slashes.upperBound]) + String(server[server.index(after: at)...])
        }
        return server
    }

    /// Запомнить вход для этого хранилища: пароль — в связку ключей macOS, а в настройки хранилища —
    /// имя и то, что пароль для этого сервера брать из связки, а не у помощников из общих настроек.
    func remember(server: String, repo: String) {
        guard let url = URL(string: server), let scheme = url.scheme, let host = url.host else { return }
        let key = "credential.\(server)"
        Git.run(["config", "--local", "--replace-all", key + ".helper", ""], in: repo)
        Git.run(["config", "--local", "--add", key + ".helper", "osxkeychain"], in: repo)
        Git.run(["config", "--local", key + ".username", user], in: repo)
        let port = url.port.map { ":\($0)" } ?? ""
        Git.run(["credential", "approve"], in: repo,
                input: "protocol=\(scheme)\nhost=\(host)\(port)\nusername=\(user)\npassword=\(password)\n\n")
    }
}

/// Настройки в UserDefaults.
enum Settings {
    private static let defaults = UserDefaults.standard

    /// Путь к git; пусто — найти самим.
    static var gitPath: String {
        get { defaults.string(forKey: "gitPath") ?? "" }
        set { defaults.set(newValue, forKey: "gitPath") }
    }

    static var showUnversioned: Bool {
        get { defaults.object(forKey: "showUnversioned") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showUnversioned") }
    }
}
