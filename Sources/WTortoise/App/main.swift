import AppKit

let app = NSApplication.shared

// `-askpass <вопрос>`: нас вызвал git или ssh, чтобы спросить пароль. Ответ — в stdout.
if let index = CommandLine.arguments.firstIndex(of: "-askpass") {
    let prompt = index + 1 < CommandLine.arguments.count ? CommandLine.arguments[index + 1] : ""
    Askpass.run(prompt: prompt)
}

let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
