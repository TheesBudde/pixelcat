import AppKit

/// Erzeugt PNG-Bilder: das App-Symbol (für build.sh) und eine Vorschau aller Posen.
enum Exporter {
    static func exportIconSet(to directory: String) throws {
        let dir = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            for factor in [1, 2] {
                let suffix = factor == 2 ? "@2x" : ""
                let data = try png(width: base * factor, height: base * factor) { ctx in
                    drawIcon(in: ctx, size: CGFloat(base * factor))
                }
                try data.write(to: dir.appendingPathComponent("icon_\(base)x\(base)\(suffix).png"))
            }
        }
    }

    /// Alle Posen in allen Fellfarben (eine Zeile pro Farbe) plus das Menüleisten-Symbol.
    static func exportPreview(to path: String) throws {
        let scale: CGFloat = 5
        let cell = 28
        let frames = Frames.all
        let width = (frames.count * cell + 2) * Int(scale)
        let height = (Coat.allCases.count * cell + 24) * Int(scale)
        let data = try png(width: width, height: height) { ctx in
            ctx.setFillColor(CGColor(gray: 0.45, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            for (row, coat) in Coat.allCases.reversed().enumerated() {
                for (col, sprite) in frames.enumerated() {
                    sprite.draw(in: ctx, x: CGFloat(col * cell + 2), y: CGFloat(row * cell + 24 + 2),
                                scale: scale, coat: coat)
                }
            }
            // Menüleisten-Symbol in 1×, 2× und groß, auf hellem und dunklem Grund
            let icon = Frames.menuBarIcon()
            for (i, (factor, dark)) in [(1.0, false), (2.0, false), (6.0, false), (1.0, true), (2.0, true), (6.0, true)].enumerated() {
                let box = CGRect(x: 10 + CGFloat(i) * 150 * scale / 5, y: 10, width: 20 * factor + 16, height: 16 * factor + 16)
                ctx.setFillColor(dark ? CGColor(gray: 0.15, alpha: 1) : CGColor(gray: 0.93, alpha: 1))
                ctx.fill(box)
                let tinted = NSImage(size: icon.size, flipped: false) { rect in
                    icon.draw(in: rect)
                    (dark ? NSColor.white : NSColor.black).set()
                    rect.fill(using: .sourceAtop)
                    return true
                }
                var rect = CGRect(x: box.minX + 8, y: box.minY + 8, width: 20 * factor, height: 16 * factor)
                if let cg = tinted.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
                    ctx.interpolationQuality = .high
                    ctx.draw(cg, in: CGRect(x: box.minX + 8, y: box.minY + 8, width: 20 * factor, height: 16 * factor))
                }
            }
        }
        try data.write(to: URL(fileURLWithPath: path))
    }

    private static func drawIcon(in ctx: CGContext, size: CGFloat) {
        // Abgerundetes Quadrat im Stil der macOS-Symbole
        let inset = size * 0.1
        let rect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
        let path = CGPath(roundedRect: rect, cornerWidth: rect.width * 0.225,
                          cornerHeight: rect.width * 0.225, transform: nil)
        ctx.addPath(path)
        ctx.clip()
        let colors = [CGColor(srgbRed: 0.55, green: 0.78, blue: 0.95, alpha: 1),
                      CGColor(srgbRed: 0.85, green: 0.93, blue: 1.0, alpha: 1)] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                     colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: rect.minY),
                                   end: CGPoint(x: 0, y: rect.maxY), options: [])
        }
        // Boden, auf dem die Katze sitzt
        let groundHeight = rect.height * 0.26
        ctx.setFillColor(CGColor(srgbRed: 0.42, green: 0.36, blue: 0.52, alpha: 1))
        ctx.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: groundHeight))

        let sprite = Frames.sit
        var scale = rect.width * 0.62 / CGFloat(sprite.width)
        if scale >= 2 { scale = scale.rounded(.down) }
        let originX = (size - CGFloat(sprite.width) * scale) / 2 / scale
        let originY = (rect.minY + groundHeight) / scale
        sprite.draw(in: ctx, x: originX, y: originY, scale: scale, coat: .black)
    }

    private static func png(width: Int, height: Int, draw: (CGContext) -> Void) throws -> Data {
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw CocoaError(.fileWriteUnknown) }
        ctx.setShouldAntialias(false)
        ctx.interpolationQuality = .none
        // Damit NSImage-Zeichnungen (Menüleisten-Symbol) in diesen Kontext gehen
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        draw(ctx)
        guard let image = ctx.makeImage(),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { throw CocoaError(.fileWriteUnknown) }
        return data
    }
}
