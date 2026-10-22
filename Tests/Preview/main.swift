import AppKit

// Rendert Pixelbilder zur Sichtprüfung nach build/preview/ – Aufruf: ./preview.sh
MainActor.assumeIsolated {
    _ = NSApplication.shared
    let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/preview"

    /// Mehrere Bilder nebeneinander auf grauem Grund
    @MainActor func sheet(_ name: String, _ items: [(Sprite, [Character: CGColor])], scale: CGFloat = 4) {
        let gap: CGFloat = 6
        let width = items.reduce(gap) { $0 + CGFloat($1.0.width) * scale + gap }
        let height = (items.map { CGFloat($0.0.height) }.max() ?? 1) * scale + 2 * gap
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
        ctx.setFillColor(gray: 0.55, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        var x = gap
        for (sprite, colors) in items {
            sprite.draw(in: ctx, x: x / scale, y: gap / scale, scale: scale, colors: colors)
            x += CGFloat(sprite.width) * scale + gap
        }
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
    }

    let bubbles = ["Pause", "Trinken", "Feierabend", "Mama anrufen", "Steuererklärung bis Freitag abgeben!",
                   "Größe: 1/2 – (ok?) & 100%", String(repeating: "Ganz langer Text ", count: 6)]
    for (i, text) in bubbles.enumerated() {
        sheet("blase-\(i)", [(BubbleFrames(text: text).whole, BubbleFrames.colors)])
    }
    sheet("schrift", ["ABCDEFGHIJKLM", "NOPQRSTUVWXYZ", "ÄÖÜ ß 0123456789", ".,!?:;-+'\"()/&%#@=*_…"]
        .map { (BubbleFrames(text: $0).whole, BubbleFrames.colors) })
    sheet("trinken", [(Frames.drinkA, Coat.orange.colors), (Frames.drinkB, Coat.orange.colors),
                      (Frames.drinkA, Coat.black.colors), (Frames.drinkA, Coat.gray.colors),
                      (Frames.waterFullA, PropColors.colors), (Frames.waterFullB, PropColors.colors),
                      (Frames.waterHalf, PropColors.colors), (Frames.waterEmpty, PropColors.colors)], scale: 6)
    print("Vorschau in \(out)")
}
