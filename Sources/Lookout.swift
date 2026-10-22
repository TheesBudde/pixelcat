import AppKit

/// Fenster für die Augenpause: Holzrahmen mit Sprossen, draußen Himmel, Sonne, Hügel und eine Wolke,
/// die langsam vorbeizieht. Die Katze sitzt davor auf dem Fensterbrett und schaut hinaus.
@MainActor
enum LookoutArt {
    static let colors = rgbPalette([
        "K": 0x2B1D16, // Umriss
        "D": 0x7A4B2A, // Rahmen, dunkel
        "d": 0xA8703F, // Rahmen, hell
        "S": 0x8FCBF2, // Himmel
        "s": 0xBFE3F8, // Himmel, zum Horizont hin heller
        "C": 0xFFFFFF, // Wolke
        "c": 0xDDEBF5, // Wolke, Schatten
        "Y": 0xF7D154, // Sonne
        "G": 0x7DB95B, // Hügel
        "g": 0x5C9A42, // Hügel, dunkel
        "L": 0xC28C57, // Fensterbrett
        "l": 0x8C5E34, // Fensterbrett, Schatten
    ])

    static let width = 30
    static let height = 28
    /// Zeile (von oben), in der das Fensterbrett beginnt
    private static let sillRow = height - 5
    /// So hoch steht die Oberkante des Fensterbretts (in Pixeln über dem Boden) – darauf sitzt die Katze
    static let sillTop = height - sillRow

    /// Bilder mit der Wolke an verschiedenen Stellen – im Wechsel zieht sie vorbei
    static let frames: [Sprite] = (0..<13).map { make(cloudAt: -4 + $0 * 2) }

    private static func make(cloudAt cloudX: Int) -> Sprite {
        let w = width, h = height
        var g = [[Character]](repeating: [Character](repeating: ".", count: w), count: h)
        // Glas: Himmel, unten heller
        let glass = (x: 4...(w - 5), y: 3...(sillRow - 2))
        let middle = (glass.y.lowerBound + glass.y.upperBound) / 2
        for y in glass.y { for x in glass.x { g[y][x] = y > middle + 2 ? "s" : "S" } }
        // Sonne oben rechts
        let sun = w - 9
        for (x, y) in [(sun, 4), (sun + 1, 4), (sun - 1, 5), (sun, 5), (sun + 1, 5), (sun + 2, 5), (sun, 6), (sun + 1, 6)] {
            g[y][x] = "Y"
        }
        // Wolke (zieht nach rechts), nur innerhalb des Glases
        let cloud = [".CCC..", "CCCCCC", ".cccc."]
        for (row, line) in cloud.enumerated() {
            for (col, c) in line.enumerated() where c != "." {
                let x = glass.x.lowerBound + cloudX + col, y = 5 + row
                if glass.x.contains(x) { g[y][x] = c }
            }
        }
        // Hügel am Horizont
        for x in glass.x {
            let top = glass.y.upperBound - 3 - Int((2.2 * sin(Double(x) * 0.45)).rounded())
            for y in top...glass.y.upperBound { g[y][x] = y == top ? "G" : "g" }
        }
        // Rahmen: außen Umriss, dann dunkel, innen hell; Sprossen in der Mitte
        for y in 0...(sillRow - 1) {
            for x in 1...(w - 2) where !(glass.x.contains(x) && glass.y.contains(y)) {
                let outer = x == 1 || x == w - 2 || y == 0
                let dark = x == 2 || x == w - 3 || y == 1 || y == sillRow - 1
                g[y][x] = outer ? "K" : dark ? "D" : "d"
            }
        }
        for y in glass.y { g[y][w / 2 - 1] = "d"; g[y][w / 2] = "D" }
        for x in glass.x { g[middle][x] = "d" }
        // Fensterbrett, ein Stück breiter als der Rahmen
        for x in 0..<w {
            g[sillRow][x] = (x == 0 || x == w - 1) ? "K" : "L"
            g[sillRow + 1][x] = (x == 0 || x == w - 1) ? "K" : "l"
            g[sillRow + 2][x] = "K"
        }
        // Darunter ein Stück Wand mit Schatten, damit es nicht in der Luft hängt
        for x in 2..<(w - 2) {
            g[sillRow + 3][x] = x == 2 || x == w - 3 ? "K" : "l"
            g[sillRow + 4][x] = "K"
        }
        return Sprite(g.map { String($0) })
    }
}
