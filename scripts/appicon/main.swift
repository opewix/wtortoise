// Рисует значок программы в .iconset для iconutil: черепаха на голубой плитке с веткой графа.
// См. scripts/bundle.sh. Собирается вместе с Sources/WTortoise/Shared/Glyphs.swift — черепаха оттуда.
import AppKit

// Плитка по сетке значков macOS: холст 1024, отступ 100, сторона 824, радиус 185,4. Только такую форму
// macOS 26 показывает во весь скруглённый квадрат; иную сажает на серую подложку и уменьшает.
let tileRect = NSRect(x: 100, y: 100, width: 824, height: 824)
let tile = NSBezierPath(roundedRect: tileRect, xRadius: 185.4, yRadius: 185.4)

func drawIcon() {
    let r = tileRect
    NSGradient(starting: NSColor(hex: 0xBFE3FF), ending: NSColor(hex: 0x4E9BE6))!.draw(in: NSBezierPath(rect: r), angle: -90)
    // Земля.
    let ground = NSBezierPath()
    ground.move(to: NSPoint(x: r.minX, y: r.minY + r.height * 0.26))
    ground.curve(to: NSPoint(x: r.maxX, y: r.minY + r.height * 0.22),
                 controlPoint1: NSPoint(x: r.minX + r.width * 0.35, y: r.minY + r.height * 0.34),
                 controlPoint2: NSPoint(x: r.minX + r.width * 0.7, y: r.minY + r.height * 0.16))
    ground.line(to: NSPoint(x: r.maxX, y: r.minY))
    ground.line(to: NSPoint(x: r.minX, y: r.minY))
    ground.close()
    NSGradient(starting: NSColor(hex: 0xE9D9A6), ending: NSColor(hex: 0xC9B076))!.draw(in: ground, angle: -90)
    // Ветка графа: два узла и ответвление — в верхнем левом углу.
    let line = NSBezierPath()
    line.move(to: NSPoint(x: r.minX + 150, y: r.maxY - 330))
    line.line(to: NSPoint(x: r.minX + 150, y: r.maxY - 110))
    line.move(to: NSPoint(x: r.minX + 150, y: r.maxY - 290))
    line.curve(to: NSPoint(x: r.minX + 290, y: r.maxY - 150),
               controlPoint1: NSPoint(x: r.minX + 150, y: r.maxY - 200), controlPoint2: NSPoint(x: r.minX + 290, y: r.maxY - 240))
    line.lineWidth = 26
    line.lineCapStyle = .round
    NSColor(white: 1, alpha: 0.9).setStroke()
    line.stroke()
    for (x, y, color) in [(150.0, 110.0, 0xD43A2F), (150.0, 330.0, 0xD43A2F), (290.0, 150.0, 0x2E9E3F)] {
        let dot = NSBezierPath(ovalIn: NSRect(x: r.minX + x - 40, y: r.maxY - y - 40, width: 80, height: 80))
        NSColor.white.setFill()
        dot.fill()
        NSColor(hex: color).setFill()
        NSBezierPath(ovalIn: NSRect(x: r.minX + x - 26, y: r.maxY - y - 26, width: 52, height: 52)).fill()
    }
    Glyph.drawTortoise(in: NSRect(x: r.minX + 150, y: r.minY + 120, width: 600, height: 460))
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = base * scale
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let scaleTo = NSAffineTransform()
        scaleTo.scale(by: CGFloat(pixels) / 1024)
        scaleTo.concat()
        tile.addClip()
        drawIcon()
        NSGraphicsContext.restoreGraphicsState()
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
    }
}
