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
        switch self {
        case .commit:
            arrow(up: true, green, from: 5, to: 14.5)
            stroke([(2.5, 5.5), (2.5, 2), (13.5, 2), (13.5, 5.5)], gray, 1.5)
        case .push:
            arrow(up: true, red, from: 2, to: 11.5)
            stroke([(3, 14), (13, 14)], gray, 1.6)
        case .pull:
            arrow(up: false, blue, from: 4.5, to: 14)
            stroke([(3, 2), (13, 2)], gray, 1.6)
        case .fetch:
            arrow(up: false, blue, from: 4.5, to: 14, hollow: true)
            stroke([(3, 2), (13, 2)], gray, 1.6)
        case .diff:
            box(1.5, 2.5, 5.5, 11, fill: NSColor(hex: 0xFFE0C0), stroke: orange)
            box(9, 2.5, 5.5, 11, fill: NSColor(hex: 0xFFFFB0), stroke: NSColor(hex: 0xB89A10))
        case .log:
            for y in [12.5, 8, 3.5] as [CGFloat] {
                dot(3, y, 1.5, blue)
                stroke([(6.5, y), (14, y)], gray, 1.5)
            }
        case .status:
            ring(6.5, 9.5, 4, blue, 1.8)
            stroke([(9.5, 6.5), (14, 2)], gray, 2.2)
        case .add:
            stroke([(8, 2.5), (8, 13.5)], blue, 2.6)
            stroke([(2.5, 8), (13.5, 8)], blue, 2.6)
        case .revert:
            let arc = NSBezierPath()
            arc.appendArc(withCenter: NSPoint(x: 8, y: 7), radius: 5, startAngle: 200, endAngle: 60, clockwise: true)
            arc.lineWidth = 2
            arc.lineCapStyle = .round
            orange.setStroke()
            arc.stroke()
            fill([(1.2, 9.2), (6.6, 9.4), (3.6, 13.8)], orange)
        case .switchBranch:
            stroke([(2, 11), (12, 11)], green, 1.8)
            fill([(14.5, 11), (10.5, 14), (10.5, 8)], green)
            stroke([(14, 5), (4, 5)], blue, 1.8)
            fill([(1.5, 5), (5.5, 8), (5.5, 2)], blue)
        case .merge:
            stroke([(4, 13), (4, 3)], gray, 1.5)
            stroke([(12, 13), (12, 10), (4, 5)], gray, 1.5)
            dot(4, 13, 2, blue); dot(12, 13, 2, green); dot(4, 3, 2, blue)
        case .branch:
            stroke([(4, 3), (4, 13)], gray, 1.5)
            stroke([(4, 6), (12, 9), (12, 13)], gray, 1.5)
            dot(4, 3, 2, blue); dot(4, 13, 2, blue); dot(12, 13, 2, green)
        case .tag:
            let shape: [(CGFloat, CGFloat)] = [(2, 14), (8.5, 14), (14.5, 8), (8, 1.5), (2, 7.5)]
            fill(shape, yellow)
            stroke(shape, NSColor(hex: 0x9C7A12), 1.2, close: true)
            dot(5, 11, 1.3, .white)
        case .stash:
            box(2, 2, 12, 7, fill: NSColor(hex: 0xE8D9B5), stroke: NSColor(hex: 0x8A6D2F))
            arrow(up: false, gray, from: 6.5, to: 15)
        case .stashPop:
            box(2, 2, 12, 7, fill: NSColor(hex: 0xE8D9B5), stroke: NSColor(hex: 0x8A6D2F))
            arrow(up: true, green, from: 5.5, to: 15)
        case .clone:
            box(2, 5, 8, 9.5, fill: .white, stroke: gray)
            box(6, 1.5, 8, 9.5, fill: NSColor(hex: 0xDCE9FB), stroke: blue)
        case .initRepo:
            box(2, 2, 9.5, 12, fill: .white, stroke: gray)
            stroke([(11.5, 2.5), (11.5, 8.5)], green, 2.2)
            stroke([(8.5, 5.5), (14.5, 5.5)], green, 2.2)
        case .settings:
            for i in 0..<8 {
                let a = CGFloat(i) * .pi / 4
                stroke([(8 + cos(a) * 4, 8 + sin(a) * 4), (8 + cos(a) * 6.3, 8 + sin(a) * 6.3)], gray, 2.4)
            }
            ring(8, 8, 3.6, gray, 2.4)
        case .about:
            dot(8, 8, 6.5, blue)
            dot(8, 11.6, 1.1, .white)
            stroke([(8, 9), (8, 4.5)], .white, 1.9)
        case .blame:
            for (y, color) in [(12.5, blue), (8, green), (3.5, orange)] as [(CGFloat, NSColor)] {
                box(1.5, y - 1.5, 4, 3, fill: color, stroke: nil)
                stroke([(7.5, y), (14, y)], gray, 1.5)
            }
        case .rename:
            box(1.5, 5, 13, 6, fill: .white, stroke: gray)
            stroke([(5, 2.5), (5, 13.5)], blue, 1.6)
            stroke([(3.5, 13.5), (6.5, 13.5)], blue, 1.4)
            stroke([(3.5, 2.5), (6.5, 2.5)], blue, 1.4)
        case .remove:
            stroke([(3.5, 3.5), (12.5, 12.5)], red, 2.6)
            stroke([(3.5, 12.5), (12.5, 3.5)], red, 2.6)
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
