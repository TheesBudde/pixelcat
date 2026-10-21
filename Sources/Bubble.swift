import AppKit

/// Gedankenblase über der Katze, wenn sie an eine Pause erinnert („PAUSE“ bzw. „BREAK“).
/// Sie folgt dem Kopf und platzt mit einer kleinen Animation – beim Klick oder wenn die Pause vorbei ist.
@MainActor
final class ThoughtBubble {
    /// Wann die Pause vorbei ist und die Blase von selbst platzt
    let ends: Date
    private let window: PropWindow
    private let frames: BubbleFrames
    /// Zeit seit Beginn des Platzens (nil = noch ganz)
    private(set) var popTime: Double?
    private static let popLength = 0.4

    var isPopping: Bool { popTime != nil }
    var isGone: Bool { (popTime ?? 0) >= Self.popLength }

    init(text: String, ends: Date, scale: CGFloat) {
        self.ends = ends
        frames = BubbleFrames(text: text)
        window = PropWindow(columns: frames.width, rows: frames.height, scale: scale)
        window.view.colors = BubbleFrames.colors
        window.view.sprite = frames.whole
        window.view.onMouseDown = { [weak self] _ in self?.pop() }
    }

    func pop() {
        if popTime == nil { popTime = 0 }
    }

    var scale: CGFloat {
        get { window.scale }
        set { window.scale = newValue }
    }

    /// Jeden Takt: Bild wählen und über den Kopf der Katze setzen (nil = Katze gerade nicht zu sehen).
    func update(dt: Double, head: CGPoint?) {
        if let time = popTime {
            popTime = time + dt
            let t = time + dt
            window.view.sprite = t < 0.08 ? frames.flash : t < 0.2 ? frames.puffs : frames.dust
        }
        guard let head, !isGone else {
            window.panel.orderOut(nil)
            return
        }
        // Die Gedankenpunkte unten in der Mitte zeigen auf den Kopf
        window.place(centerX: head.x, bottom: head.y)
        if !window.panel.isVisible { window.panel.orderFrontRegardless() }
    }

    func remove() {
        window.panel.orderOut(nil)
    }
}

/// Die Bilder der Blase: ganz, kurz aufgeblitzt, in Wölkchen zerplatzt, verpufft.
/// Alle gleich groß, damit nichts springt.
struct BubbleFrames {
    let whole: Sprite
    let flash: Sprite
    let puffs: Sprite
    let dust: Sprite
    let width: Int
    let height: Int

    /// "K" Umriss, "W" Wolke, "g" Schatten, "T" Schrift
    static let colors = rgbPalette(["K": 0x2B1D16, "W": 0xFFFFFF, "g": 0xE4DED6, "T": 0x2B1D16])

    /// Kleine Pixelschrift, 5 × 5
    private static let font: [Character: [String]] = [
        "A": [".###.", "#...#", "#####", "#...#", "#...#"],
        "B": ["####.", "#...#", "####.", "#...#", "####."],
        "E": ["#####", "#....", "####.", "#....", "#####"],
        "K": ["#...#", "#..#.", "###..", "#..#.", "#...#"],
        "P": ["####.", "#...#", "####.", "#....", "#...."],
        "R": ["####.", "#...#", "####.", "#..#.", "#...#"],
        "S": [".####", "#....", ".###.", "....#", "####."],
        "U": ["#...#", "#...#", "#...#", "#...#", ".###."],
    ]

    init(text: String) {
        let letters = text.uppercased().compactMap { Self.font[$0] }
        let textWidth = max(1, letters.count * 6 - 1)
        // Wolke: Körper plus Beulen oben, unten und an den Seiten
        let cloudW = textWidth + 10, cloudH = 13
        let w = cloudW + 8, h = cloudH + 9      // Rand für die Platz-Wölkchen, unten Platz für die Punkte
        width = w
        height = h
        let ox = 4, oy = 2                       // Lage der Wolke im Bild

        var mask = [[Bool]](repeating: [Bool](repeating: false, count: w), count: h)
        func circle(_ cx: Double, _ cy: Double, _ r: Double) {
            for y in 0..<h { for x in 0..<w where (Double(x) - cx) * (Double(x) - cx) + (Double(y) - cy) * (Double(y) - cy) <= r * r {
                mask[y][x] = true
            } }
        }
        // Körper
        for y in (oy + 3)...(oy + cloudH - 4) { for x in (ox + 2)...(ox + cloudW - 3) { mask[y][x] = true } }
        // Beulen
        var bx = Double(ox) + 4.5
        while bx < Double(ox + cloudW) - 3 {
            circle(bx, Double(oy) + 3.6, 3.3)
            circle(bx + 3, Double(oy + cloudH) - 4.2, 2.8)
            bx += 6.5
        }
        circle(Double(ox) + 2.8, Double(oy) + Double(cloudH) / 2 - 0.5, 3.4)
        circle(Double(ox + cloudW) - 3.4, Double(oy) + Double(cloudH) / 2 - 0.5, 3.4)

        // Gedankenpunkte zum Kopf (unten in der Mitte)
        let mid = w / 2
        var dots = [(Int, Int)]()
        // ein größerer Punkt unter der Wolke, ein kleiner näher am Kopf
        for (x, y) in [(mid - 1, h - 5), (mid, h - 5), (mid + 1, h - 5), (mid - 1, h - 4), (mid, h - 4), (mid + 1, h - 4),
                       (mid + 1, h - 2)] { dots.append((x, y)) }

        func grid(fill: Character, text: Bool, shade: Bool) -> [[Character]] {
            var g = [[Character]](repeating: [Character](repeating: ".", count: w), count: h)
            for y in 0..<h { for x in 0..<w where mask[y][x] {
                g[y][x] = shade && (y + 1 >= h || !mask[y + 1][x] || (y + 2 < h && !mask[y + 2][x])) ? "g" : fill
            } }
            for (x, y) in dots { g[y][x] = fill }
            // Umriss
            var out = g
            for y in 0..<h { for x in 0..<w where g[y][x] == "." {
                let near = [(0, 1), (0, -1), (1, 0), (-1, 0)].contains { dx, dy in
                    let nx = x + dx, ny = y + dy
                    return nx >= 0 && ny >= 0 && nx < w && ny < h && g[ny][nx] != "."
                }
                if near { out[y][x] = "K" }
            } }
            if text {
                let tx = ox + (cloudW - textWidth) / 2, ty = oy + (cloudH - 5) / 2
                for (i, letter) in letters.enumerated() {
                    for (row, line) in letter.enumerated() {
                        for (col, c) in line.enumerated() where c == "#" { out[ty + row][tx + i * 6 + col] = "T" }
                    }
                }
            }
            return out
        }
        func sprite(_ g: [[Character]]) -> Sprite { Sprite(g.map { String($0) }) }

        whole = sprite(grid(fill: "W", text: true, shade: true))
        flash = sprite(grid(fill: "W", text: false, shade: false))

        // Zerplatzt: kleine Wölkchen rund um die Mitte der Wolke, dann nur noch Pünktchen weiter außen
        let cx = Double(ox) + Double(cloudW) / 2, cy = Double(oy) + Double(cloudH) / 2
        func burst(radiusX: Double, radiusY: Double, size: Int) -> Sprite {
            var g = [[Character]](repeating: [Character](repeating: ".", count: w), count: h)
            for i in 0..<8 {
                let a = Double(i) / 8 * 2 * .pi + 0.3
                let px = Int((cx + cos(a) * radiusX).rounded()), py = Int((cy + sin(a) * radiusY).rounded())
                for dy in 0..<size { for dx in 0..<size {
                    let x = px + dx - size / 2, y = py + dy - size / 2
                    if x >= 0, y >= 0, x < w, y < h { g[y][x] = size > 1 ? "W" : "K" }
                } }
            }
            // Wölkchen bekommen einen Umriss
            if size > 1 {
                var out = g
                for y in 0..<h { for x in 0..<w where g[y][x] == "." {
                    if [(0, 1), (0, -1), (1, 0), (-1, 0)].contains(where: { dx, dy in
                        let nx = x + dx, ny = y + dy
                        return nx >= 0 && ny >= 0 && nx < w && ny < h && g[ny][nx] == "W"
                    }) { out[y][x] = "K" }
                } }
                g = out
            }
            return sprite(g)
        }
        puffs = burst(radiusX: Double(cloudW) * 0.42, radiusY: Double(cloudH) * 0.45, size: 3)
        dust = burst(radiusX: Double(cloudW) * 0.55, radiusY: Double(cloudH) * 0.62, size: 1)
    }
}
