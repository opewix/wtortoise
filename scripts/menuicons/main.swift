// Сохраняет значки команд в PNG: <папка>/<команда>.png и app.png — см. scripts/bundle.sh.
// Их берут другие программы (WExplorer), чтобы показать в своём меню те же значки, что и в Finder.
// Имя файла — имя команды из ссылки `wtortoise://<команда>`.
import AppKit

func save(_ glyph: Glyph, as name: String, to directory: URL) {
    let pixels = 64
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    glyph.image(CGFloat(pixels)).draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png"))
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for command in Command.allCases { save(command.glyph, as: command.rawValue, to: out) }
save(.app, as: "app", to: out)
