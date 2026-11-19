import AppKit

enum Menus {
    static func build() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(ClosureMenuItem(L.t("О программе WTortoise", "About WTortoise")) { About.show() })
        appMenu.addItem(.separator())
        let settings = ClosureMenuItem(L.t("Настройки…", "Settings...")) { SettingsController.show() }
        settings.keyEquivalent = ","
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L.t("Скрыть WTortoise", "Hide WTortoise"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: L.t("Завершить WTortoise", "Quit WTortoise"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        add(appMenu, to: main)

        // Меню «Правка» нужно, чтобы в полях работали ⌘C, ⌘V, ⌘Z.
        let edit = NSMenu(title: L.t("Правка", "Edit"))
        edit.addItem(withTitle: L.t("Отменить", "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: L.t("Повторить", "Redo"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: L.t("Вырезать", "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: L.t("Скопировать", "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: L.t("Вставить", "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: L.t("Выделить всё", "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        add(edit, to: main)

        let window = NSMenu(title: L.t("Окно", "Window"))
        window.addItem(withTitle: L.t("Закрыть", "Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: L.t("Свернуть", "Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        add(window, to: main)
        NSApp.windowsMenu = window
        return main
    }

    private static func add(_ menu: NSMenu, to main: NSMenu) {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        main.addItem(item)
    }
}
