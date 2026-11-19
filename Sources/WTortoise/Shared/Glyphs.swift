import AppKit

extension NSColor {
    convenience init(hex: Int, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

private let green = NSColor(hex: 0x2E9E3F), red = NSColor(hex: 0xD43A2F), blue = NSColor(hex: 0x2F6FD4)
private let orange = NSColor(hex: 0xE08A1E), gray = NSColor(hex: 0x5A6472), yellow = NSColor(hex: 0xF2C230)

private func path(_ points: [(CGFloat, CGFloat)], close: Bool = false) -> NSBezierPath {
    let p = NSBezierPath()
    for (i, pt) in points.enumerated() {
        let point = NSPoint(x: pt.0, y: pt.1)
        if i == 0 { p.move(to: point) } else { p.line(to: point) }
    }
    if close { p.close() }
    p.lineCapStyle = .round
    p.lineJoinStyle = .round
    return p
}

private func stroke(_ points: [(CGFloat, CGFloat)], _ color: NSColor, _ width: CGFloat = 1.6, close: Bool = false) {
    let p = path(points, close: close)
    p.lineWidth = width
    color.setStroke()
    p.stroke()
}

private func fill(_ points: [(CGFloat, CGFloat)], _ color: NSColor) {
    color.setFill()
    path(points, close: true).fill()
}

private func dot(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ color: NSColor) {
    color.setFill()
    NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: r * 2, height: r * 2)).fill()
}

private func ring(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ color: NSColor, _ width: CGFloat = 1.5) {
    let p = NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    p.lineWidth = width
    color.setStroke()
    p.stroke()
}

private func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, fill: NSColor?, stroke: NSColor?) {
    let p = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: 1, yRadius: 1)
    if let fill { fill.setFill(); p.fill() }
    if let stroke { stroke.setStroke(); p.lineWidth = 1.2; p.stroke() }
}

private func curve(_ from: (CGFloat, CGFloat), _ c1: (CGFloat, CGFloat), _ c2: (CGFloat, CGFloat), _ to: (CGFloat, CGFloat),
                   _ color: NSColor, _ width: CGFloat) {
    let p = NSBezierPath()
    p.move(to: NSPoint(x: from.0, y: from.1))
    p.curve(to: NSPoint(x: to.0, y: to.1), controlPoint1: NSPoint(x: c1.0, y: c1.1), controlPoint2: NSPoint(x: c2.0, y: c2.1))
    p.lineWidth = width
    p.lineCapStyle = .round
    color.setStroke()
    p.stroke()
}

/// Жёлтый «бочонок» — хранилище.
private func cylinder(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
    let e = w * 0.34, edge = NSColor(hex: 0xB58E00)
    let body = NSBezierPath()
    body.move(to: NSPoint(x: x, y: y + h - e / 2))
    body.line(to: NSPoint(x: x, y: y + e / 2))
    body.curve(to: NSPoint(x: x + w, y: y + e / 2), controlPoint1: NSPoint(x: x, y: y - e * 0.17), controlPoint2: NSPoint(x: x + w, y: y - e * 0.17))
    body.line(to: NSPoint(x: x + w, y: y + h - e / 2))
    body.close()
    NSGradient(colors: [NSColor(hex: 0xE2B400), NSColor(hex: 0xFFE861), NSColor(hex: 0xE8BC00)])?.draw(in: body, angle: 0)
    edge.setStroke()
    body.lineWidth = 0.6
    body.stroke()
    let top = NSBezierPath(ovalIn: NSRect(x: x, y: y + h - e, width: w, height: e))
    NSColor(hex: 0xFFF08A).setFill()
    top.fill()
    top.lineWidth = 0.6
    top.stroke()
    if h > 5 {
        let band = NSBezierPath()
        band.move(to: NSPoint(x: x, y: y + h * 0.48))
        band.curve(to: NSPoint(x: x + w, y: y + h * 0.48), controlPoint1: NSPoint(x: x, y: y + h * 0.48 - e * 0.67),
                   controlPoint2: NSPoint(x: x + w, y: y + h * 0.48 - e * 0.67))
        band.lineWidth = 0.5
        band.stroke()
    }
}

/// Серый шкафчик с ящиками — рабочая копия.
private func cabinet(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
    box(x, y, w, h, fill: NSColor(hex: 0xD3D8DE), stroke: NSColor(hex: 0x6F7780))
    let drawer = h / 3
    for i in 0..<3 {
        let dy = y + CGFloat(i) * drawer
        box(x + 1, dy + 1, w - 2, drawer - 1.4, fill: NSColor(hex: 0xF1F3F5), stroke: nil)
        stroke([(x + w / 2 - 1, dy + drawer / 2 + 0.2), (x + w / 2 + 1, dy + drawer / 2 + 0.2)], NSColor(hex: 0x6F7780), 0.8)
    }
}

private func star(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ color: NSColor) {
    var points: [(CGFloat, CGFloat)] = []
    for i in 0..<10 {
        let a = CGFloat.pi / 2 + CGFloat(i) * .pi / 5, radius = i % 2 == 0 ? r : r * 0.45
        points.append((cx + cos(a) * radius, cy + sin(a) * radius))
    }
    fill(points, color)
    stroke(points, NSColor(white: 0, alpha: 0.25), 0.4, close: true)
}

/// Синий лоток — «спрятанное».
private func tray() {
    let tone = NSColor(hex: 0x3A7BE0)
    fill([(1.2, 7), (4.6, 7), (5.6, 5), (10.4, 5), (11.4, 7), (14.8, 7), (14.8, 1.2), (1.2, 1.2)], tone)
    stroke([(1.6, 7), (4, 11.2)], tone, 1.1)
    stroke([(14.4, 7), (12, 11.2)], tone, 1.1)
}

/// Стрелка вверх или вниз по центру значка.
private func arrow(up: Bool, _ color: NSColor, x: CGFloat = 8, from: CGFloat = 3.5, to: CGFloat = 13, hollow: Bool = false) {
    let tip = up ? to : from, tail = up ? from : to, d: CGFloat = up ? -1 : 1
    let head: [(CGFloat, CGFloat)] = [(x, tip), (x - 4, tip + d * 4.5), (x + 4, tip + d * 4.5)]
    if hollow {
        stroke(head, color, 1.4, close: true)
        stroke([(x, tip + d * 4.5), (x, tail)], color, 1.6)
    } else {
        fill(head, color)
        stroke([(x, tip + d * 3), (x, tail)], color, 2.2)
    }
}

/// Значки команд. Рисуются кодом на сетке 16×16 (ось Y вверх); чужой графики в программе нет.
enum Glyph: String {
    case commit, pull, fetch, push, diff, log, status, add, revert, switchBranch, merge, branch, tag
    case stash, stashPop, clone, initRepo, settings, about, app, blame, rename, remove

    func image(_ size: CGFloat = 16) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let scale = NSAffineTransform()
            scale.scale(by: size / 16)
            scale.concat()
            self.draw()
            return true
        }
    }

    private func draw() {
        let navy = NSColor(hex: 0x2850C8), leaf = NSColor(hex: 0x3FA63A)
        switch self {
        case .commit:
            // Зелёная стрелка, заворачивающая вправо.
            curve((4, 2.2), (4, 8), (6, 10), (10.5, 10), leaf, 3.4)
            fill([(9.8, 14.6), (15.4, 10), (9.8, 5.4)], leaf)
        case .pull:
            // Зелёная стрелка вниз к хранилищу.
            cylinder(9.5, 1, 6, 6.5)
            curve((12.5, 14), (7.5, 14), (5.8, 11), (5.8, 7.5), leaf, 3)
            fill([(1.4, 8), (10.2, 8), (5.8, 2.2)], leaf)
        case .fetch:
            curve((13, 13.6), (8.5, 13.6), (7, 10.5), (7, 7.5), leaf, 3.2)
            fill([(2.4, 8), (11.6, 8), (7, 1.6)], leaf)
        case .push:
            curve((3, 2.4), (7.5, 2.4), (9, 5.5), (9, 8.5), red, 3.2)
            fill([(4.4, 8), (13.6, 8), (9, 14.4)], red)
        case .diff:
            // Два скрещённых «пластыря».
            for angle in [45, -45] as [CGFloat] {
                NSGraphicsContext.saveGraphicsState()
                let turn = NSAffineTransform()
                turn.translateX(by: 8, yBy: 8)
                turn.rotate(byDegrees: angle)
                turn.concat()
                let bar = NSBezierPath(roundedRect: NSRect(x: -7.2, y: -2.6, width: 14.4, height: 5.2), xRadius: 1.2, yRadius: 1.2)
                NSColor(hex: 0xB4EFA0).setFill()
                bar.fill()
                NSColor(hex: 0x2E8B2E).setStroke()
                bar.lineWidth = 0.9
                bar.stroke()
                NSGraphicsContext.restoreGraphicsState()
            }
            for (x, y) in [(8, 9.3), (8, 6.7), (6.7, 8), (9.3, 8)] as [(CGFloat, CGFloat)] { dot(x, y, 0.75, .white) }
        case .log:
            // Три строки журнала с «бусинами» правок.
            let dark = NSColor(hex: 0x555B63)
            for (y, blocks) in [(12.6, [(2.5, 3.5), (7.2, 2.4), (10.8, 2.4)]), (8, [(5, 3.5), (9.8, 2.4)]),
                                (3.4, [(2.5, 2.4), (6.2, 3.5), (10.8, 2.4)])] as [(CGFloat, [(CGFloat, CGFloat)])] {
                stroke([(1, y), (15, y)], dark, 0.9)
                for (x, w) in blocks { box(x, y - 1.4, w, 2.8, fill: dark, stroke: nil) }
            }
        case .status:
            cabinet(1, 5.5, 6.5, 9.5)
            stroke([(9.5, 13), (15, 13)], NSColor(hex: 0x1F5A8A), 1.6)
            stroke([(9.5, 10.4), (15, 10.4)], NSColor(hex: 0x1F5A8A), 1.6)
            cylinder(9, 1, 6.2, 7)
        case .blame:
            for (y, color) in [(12.5, blue), (8, green), (3.5, orange)] as [(CGFloat, NSColor)] {
                box(1.5, y - 1.5, 4, 3, fill: color, stroke: nil)
                stroke([(7.5, y), (14, y)], gray, 1.5)
            }
        case .add:
            stroke([(8, 2.2), (8, 13.8)], NSColor(hex: 0x3B6FD8), 3.6)
            stroke([(2.2, 8), (13.8, 8)], NSColor(hex: 0x3B6FD8), 3.6)
        case .revert:
            // Синяя стрелка «назад».
            curve((10.5, 1.8), (15, 6), (13, 12), (7, 11.2), navy, 2.8)
            fill([(1.2, 10.4), (8, 15.2), (7.6, 6.6)], navy)
        case .rename:
            // Карандаш остриём вниз-влево.
            fill([(3.4, 5.6), (5.6, 3.4), (12.4, 10.2), (10.2, 12.4)], NSColor(hex: 0xF08A24))
            fill([(4.5, 4.5), (5.6, 3.4), (12.4, 10.2), (11.3, 11.3)], NSColor(hex: 0xD8641A))
            fill([(1.6, 1.6), (3.4, 5.6), (5.6, 3.4)], NSColor(hex: 0xF3D7A8))
            fill([(1.6, 1.6), (2.4, 3.4), (3.4, 2.4)], NSColor(hex: 0x333333))
            fill([(10.2, 12.4), (12.4, 10.2), (14.4, 12.2), (12.2, 14.4)], NSColor(hex: 0xB9BEC6))
        case .remove:
            curve((2.5, 13.5), (6, 11), (10, 6), (13, 2.5), red, 2.8)
            curve((13.5, 13.5), (10, 11.5), (5.5, 7), (3, 2.8), red, 2.8)
        case .switchBranch:
            cylinder(1, 8, 6.2, 7)
            cabinet(9, 1, 6, 9)
            curve((5.5, 9.5), (7.5, 10.5), (9.5, 10.5), (11, 11.8), leaf, 1.8)
            fill([(9.6, 13.6), (13.4, 11.2), (10.2, 9.4)], leaf)
        case .merge:
            stroke([(3, 14.2), (8, 9.2), (13, 14.2)], navy, 2.4)
            stroke([(8, 9.2), (8, 5)], navy, 2.4)
            fill([(4.2, 6), (11.8, 6), (8, 1.2)], navy)
        case .branch:
            stroke([(4.8, 1.2), (4.8, 11.5)], navy, 2.2)
            fill([(1.6, 10.6), (8, 10.6), (4.8, 15.2)], navy)
            stroke([(4.8, 4.2), (10.4, 9.8)], navy, 2.2)
            star(12, 11.8, 3.6, NSColor(hex: 0xF29A2E))
        case .tag:
            let shape: [(CGFloat, CGFloat)] = [(2, 14), (8.5, 14), (14.5, 8), (8, 1.5), (2, 7.5)]
            fill(shape, yellow)
            stroke(shape, NSColor(hex: 0x9C7A12), 1.2, close: true)
            dot(5, 11, 1.3, .white)
        case .stash:
            tray()
            stroke([(8, 15), (8, 9)], NSColor(hex: 0x2F6FD4), 1.5)
            stroke([(5.4, 11.2), (8, 8.6), (10.6, 11.2)], NSColor(hex: 0x2F6FD4), 1.5)
        case .stashPop:
            tray()
            stroke([(8, 8.6), (8, 15)], NSColor(hex: 0x2F6FD4), 1.5)
            stroke([(5.4, 12.6), (8, 15.2), (10.6, 12.6)], NSColor(hex: 0x2F6FD4), 1.5)
        case .clone:
            cylinder(1, 8.5, 6.2, 6.5)
            cylinder(8.8, 1, 6.2, 6.5)
            curve((6.5, 13.2), (10.5, 13.6), (12, 12), (12, 10), leaf, 1.9)
            fill([(9.4, 10.6), (14.6, 10.6), (12, 7.4)], leaf)
        case .initRepo:
            cylinder(1.5, 1, 10.5, 12)
            star(11.6, 11.8, 3.9, NSColor(hex: 0xE2533F))
        case .settings:
            // Гаечный ключ.
            let steel = NSColor(hex: 0x8D949C)
            stroke([(3.6, 3.6), (10, 10)], steel, 3.2)
            dot(11.2, 11.2, 3.7, steel)
            fill([(11.2, 11.2), (16, 13.2), (13.2, 16)], .white)
            dot(3.4, 3.4, 0.8, .white)
        case .about:
            let bubble = NSBezierPath(ovalIn: NSRect(x: 1.2, y: 4, width: 13.6, height: 11))
            bubble.move(to: NSPoint(x: 4.5, y: 5.4))
            bubble.line(to: NSPoint(x: 3.2, y: 1.2))
            bubble.line(to: NSPoint(x: 8.2, y: 4.4))
            NSGradient(starting: NSColor(hex: 0xF4F9FF), ending: NSColor(hex: 0xBBD6F7))?.draw(in: bubble, angle: -90)
            NSColor(hex: 0x5B8FD9).setStroke()
            bubble.lineWidth = 0.9
            bubble.stroke()
            dot(8.3, 12.2, 1.1, navy)
            stroke([(8, 9.8), (8, 6.4)], navy, 1.9)
        case .app:
            Glyph.drawTortoise(in: NSRect(x: 0.5, y: 1.5, width: 15, height: 13))
        }
    }

    /// Черепаха: панцирь куполом, голова и лапы. Она же — на значке программы.
    static func drawTortoise(in r: NSRect) {
        let skin = NSColor(hex: 0x8FBF4A), shellDark = NSColor(hex: 0x2F7D32), shellLight = NSColor(hex: 0x58B85C)
        func x(_ f: CGFloat) -> CGFloat { r.minX + r.width * f }
        func y(_ f: CGFloat) -> CGFloat { r.minY + r.height * f }
        skin.setFill()
        for leg in [0.2, 0.62] as [CGFloat] {
            NSBezierPath(roundedRect: NSRect(x: x(leg), y: y(0.04), width: r.width * 0.15, height: r.height * 0.3),
                         xRadius: r.width * 0.05, yRadius: r.width * 0.05).fill()
        }
        NSBezierPath(ovalIn: NSRect(x: x(0.74), y: y(0.3), width: r.width * 0.26, height: r.height * 0.34)).fill()
        fill([(x(0.0), y(0.22)), (x(0.14), y(0.36)), (x(0.14), y(0.22))], skin)
        let shell = NSBezierPath()
        shell.move(to: NSPoint(x: x(0.08), y: y(0.24)))
        shell.curve(to: NSPoint(x: x(0.84), y: y(0.24)), controlPoint1: NSPoint(x: x(0.1), y: y(1.2)),
                    controlPoint2: NSPoint(x: x(0.82), y: y(1.2)))
        shell.close()
        NSGradient(starting: shellLight, ending: shellDark)?.draw(in: shell, angle: -90)
        shellDark.setStroke()
        shell.lineWidth = max(0.5, r.width * 0.035)
        shell.stroke()
        let plate = NSBezierPath()
        plate.move(to: NSPoint(x: x(0.34), y: y(0.26)))
        plate.line(to: NSPoint(x: x(0.28), y: y(0.6)))
        plate.line(to: NSPoint(x: x(0.46), y: y(0.86)))
        plate.line(to: NSPoint(x: x(0.64), y: y(0.6)))
        plate.line(to: NSPoint(x: x(0.58), y: y(0.26)))
        plate.lineWidth = max(0.4, r.width * 0.028)
        NSColor(hex: 0x1F5C24, alpha: 0.75).setStroke()
        plate.stroke()
        dot(x(0.9), y(0.52), max(0.4, r.width * 0.022), NSColor(hex: 0x1B2B12))
    }
}

/// Значок состояния поверх файла в Finder и в списках.
enum Badge: String, CaseIterable {
    case normal, modified, added, conflicted

    var label: String {
        switch self {
        case .normal: return L.t("Без изменений", "Unchanged")
        case .modified: return L.t("Изменён", "Modified")
        case .added: return L.t("Добавлен", "Added")
        case .conflicted: return L.t("Конфликт", "Conflicted")
        }
    }

    func image(_ size: CGFloat = 64) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let scale = NSAffineTransform()
            scale.scale(by: size / 16)
            scale.concat()
            switch self {
            case .normal:
                dot(8, 8, 7, .white); dot(8, 8, 6.2, green)
                stroke([(4.6, 8.2), (7.1, 5.6), (11.5, 10.8)], .white, 2)
            case .modified:
                dot(8, 8, 7, .white); dot(8, 8, 6.2, red)
                stroke([(8, 11.6), (8, 7.4)], .white, 2.2)
                dot(8, 4.6, 1.2, .white)
            case .added:
                dot(8, 8, 7, .white); dot(8, 8, 6.2, blue)
                stroke([(8, 4.4), (8, 11.6)], .white, 2.1)
                stroke([(4.4, 8), (11.6, 8)], .white, 2.1)
            case .conflicted:
                fill([(8, 15), (0.8, 2), (15.2, 2)], .white)
                fill([(8, 13.4), (2.4, 2.9), (13.6, 2.9)], yellow)
                stroke([(8, 10.4), (8, 7)], NSColor(hex: 0x3A2E00), 1.8)
                dot(8, 4.7, 1, NSColor(hex: 0x3A2E00))
            }
            return true
        }
    }
}
