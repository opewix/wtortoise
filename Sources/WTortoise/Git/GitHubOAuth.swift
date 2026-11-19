import Foundation

/// Вход на GitHub через браузер («device flow»): программа получает код, человек вводит его на github.com
/// и разрешает доступ, GitHub выдаёт токен. Пароль и токен руками вводить не нужно.
///
/// Нужен идентификатор приложения OAuth, зарегистрированного на GitHub с включённым Device Flow
/// (Settings → Developer settings → OAuth Apps). Он не секрет и вшивается в программу.
enum GitHubOAuth {
    /// Идентификатор приложения WTortoise на GitHub. Пусто — входа через браузер нет, только имя и токен.
    private static let builtInClientID = "Ov23liqiq5md7as9GPUi"

    static var clientID: String {
        let custom = UserDefaults.standard.string(forKey: "githubClientID") ?? ""
        return custom.isEmpty ? builtInClientID : custom
    }

    static func isAvailable(for server: String) -> Bool {
        !clientID.isEmpty && URL(string: server)?.host?.lowercased() == "github.com"
    }

    struct Device {
        let deviceCode: String
        /// Код, который человек вводит на сайте.
        let userCode: String
        let verificationURL: URL
        let interval: TimeInterval
        let expires: Date
    }

    struct Failure: LocalizedError {
        let text: String
        var errorDescription: String? { text }
    }

    /// Шаг 1: попросить код. `repo` — чтение и запись хранилищ, `workflow` — отправка файлов GitHub Actions.
    static func requestCode(completion: @escaping (Result<Device, Error>) -> Void) {
        post("https://github.com/login/device/code", ["client_id": clientID, "scope": "repo workflow"]) { result in
            completion(result.flatMap { json in
                guard let device = json["device_code"] as? String, let user = json["user_code"] as? String,
                      let url = (json["verification_uri"] as? String).flatMap(URL.init(string:)) else {
                    return .failure(Failure(text: describe(json)))
                }
                return .success(Device(deviceCode: device, userCode: user, verificationURL: url,
                                       interval: (json["interval"] as? Double) ?? 5,
                                       expires: Date().addingTimeInterval((json["expires_in"] as? Double) ?? 900)))
            })
        }
    }

    /// Шаг 2: ждать, пока человек разрешит доступ на сайте. `alive` — окно ещё открыто; закрыли — перестаём.
    static func waitForToken(_ device: Device, alive: @escaping () -> Bool,
                             completion: @escaping (Result<String, Error>) -> Void) {
        func attempt(after interval: TimeInterval) {
            DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
                guard alive() else { return }
                guard Date() < device.expires else {
                    return completion(.failure(Failure(text: L.t("Время на вход истекло. Попробуйте ещё раз.",
                                                                 "The sign-in timed out. Try again."))))
                }
                post("https://github.com/login/oauth/access_token", [
                    "client_id": clientID, "device_code": device.deviceCode,
                    "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                ]) { result in
                    guard alive() else { return }
                    switch result {
                    case .failure(let error): completion(.failure(error))
                    case .success(let json):
                        if let token = json["access_token"] as? String { return completion(.success(token)) }
                        switch json["error"] as? String {
                        case "authorization_pending": attempt(after: interval)
                        // GitHub просит спрашивать реже.
                        case "slow_down": attempt(after: ((json["interval"] as? Double) ?? interval + 5))
                        default: completion(.failure(Failure(text: describe(json))))
                        }
                    }
                }
            }
        }
        attempt(after: device.interval)
    }

    /// Шаг 3: имя учётной записи, которой выдан токен.
    static func userName(token: String, completion: @escaping (Result<String, Error>) -> Void) {
        var request = URLRequest(url: URL(string: "https://api.github.com/user")!)
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        send(request) { result in
            completion(result.flatMap { json in
                (json["login"] as? String).map { .success($0) } ?? .failure(Failure(text: describe(json)))
            })
        }
    }

    private static func post(_ url: String, _ fields: [String: String], completion: @escaping (Result<[String: Any], Error>) -> Void) {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        var body = URLComponents()
        body.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = body.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        send(request, completion: completion)
    }

    private static func send(_ request: URLRequest, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        var request = request
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("WTortoise", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, _, error in
            let result: Result<[String: Any], Error>
            if let error {
                result = .failure(error)
            } else if let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                result = .success(json)
            } else {
                result = .failure(Failure(text: L.t("GitHub ответил непонятно.", "Unexpected answer from GitHub.")))
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    private static func describe(_ json: [String: Any]) -> String {
        (json["error_description"] as? String) ?? (json["message"] as? String) ?? (json["error"] as? String)
            ?? L.t("GitHub отказал во входе.", "GitHub refused the sign-in.")
    }
}
