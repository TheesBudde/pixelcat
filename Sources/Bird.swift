import AppKit

/// Ein kleiner Vogel, der umherfliegt, während niemand am Rechner ist. Er zieht in Bahnen über den Bildschirm,
/// streift mal tief über das Dock und flattert hoch, wenn die Katze nach ihm schnappt. Kommt jemand zurück,
/// fliegt er davon.
@MainActor
final class Bird {
    /// Mitte des Vogels (x) und Unterkante (y) in Bildschirmpunkten
    private(set) var x: CGFloat
    private(set) var y: CGFloat
    private(set) var isLeaving = false
    private(set) var isGone = false
    /// Für das Flattern der Flügel
    private(set) var flap: Double = 0
    var facingRight: Bool { vx >= 0 }

    private var vx: CGFloat = 0
    private var vy: CGFloat = 0
    private var target: CGPoint
    private var startledFor: Double = 0
    private var dodgeIn: Double?
    var random: () -> Double = { Double.random(in: 0..<1) }

    init(x: CGFloat, y: CGFloat) {
        self.x = x
        self.y = y
        target = CGPoint(x: x, y: y)
    }

    /// `ground`: Oberkante des Docks, dort steht die Katze
    func update(dt: Double, minX: CGFloat, maxX: CGFloat, ground: CGFloat, top: CGFloat, unit: CGFloat) {
        flap += dt
        startledFor = max(0, startledFor - dt)
        if let wait = dodgeIn {
            dodgeIn = wait - dt
            if wait - dt <= 0 {
                dodgeIn = nil
                flutterUp(minX: minX, maxX: maxX, ground: ground, unit: unit)
            }
        }
        if isLeaving {
            target = CGPoint(x: x < (minX + maxX) / 2 ? minX - 300 * unit : maxX + 300 * unit, y: top + 120 * unit)
        } else if hypot(target.x - x, target.y - y) < 14 * unit {
            pickTarget(minX: minX, maxX: maxX, ground: ground, unit: unit)
        }
        // Sanft lenken: Er schwenkt in Bögen statt im Zickzack
        let dx = target.x - x, dy = target.y - y
        let distance = max(1, hypot(dx, dy))
        let speed: CGFloat = (isLeaving ? 280 : startledFor > 0 ? 230 : 120) * unit
        let turn = CGFloat(min(1, (startledFor > 0 || isLeaving ? 4.0 : 1.8) * dt))
        vx += (dx / distance * speed - vx) * turn
        vy += (dy / distance * speed - vy) * turn
        x += vx * CGFloat(dt)
        y += vy * CGFloat(dt)
        y = max(y, ground + 6 * unit)
        if isLeaving, x < minX - 60 * unit || x > maxX + 60 * unit || y > top + 40 * unit { isGone = true }
    }

    /// Die Katze schnappt nach ihm: kurz darauf flattert er erschrocken hoch
    func dodge(after delay: Double = 0.2) {
        guard !isLeaving, dodgeIn == nil, startledFor <= 0 else { return }
        dodgeIn = delay
    }

    /// Jemand ist zurück: davonfliegen
    func leave() {
        isLeaving = true
    }

    private func flutterUp(minX: CGFloat, maxX: CGFloat, ground: CGFloat, unit: CGFloat) {
        startledFor = 1.2
        let side: CGFloat = random() < 0.5 ? -1 : 1
        let tx = x + side * (150 + 150 * CGFloat(random())) * unit
        target = CGPoint(x: min(max(tx, minX + 40 * unit), maxX - 40 * unit),
                         y: ground + (170 + 70 * CGFloat(random())) * unit)
    }

    /// Nächstes Ziel: meist ein Stück über der Katze, manchmal tief über dem Dock
    private func pickTarget(minX: CGFloat, maxX: CGFloat, ground: CGFloat, unit: CGFloat) {
        let margin = 50 * unit
        var tx = x
        for _ in 0..<6 {
            tx = minX + margin + CGFloat(random()) * max(1, maxX - minX - 2 * margin)
            if abs(tx - x) > 140 * unit { break }
        }
        let low = random() < 0.3
        let height = low ? 14 + 16 * CGFloat(random()) : 45 + 95 * CGFloat(random())
        target = CGPoint(x: tx, y: ground + height * unit)
    }
}

@MainActor
enum BirdArt {
    static let colors = rgbPalette([
        "K": 0x2B1D16, // Umriss
        "B": 0x4F86D9, // Kopf und Rücken
        "W": 0x2F5FA8, // Flügel
        "b": 0xF3D25C, // Bauch
        "Y": 0xF29A38, // Schnabel
        "E": 0xFFFFFF, // Glanz im Auge
    ])

    static let width = 14
    static let height = 11

    /// Flügel oben
    static let up = Sprite([
        "...KK.........",
        "...KWK........",
        "...KWWK..KKK..",
        "....KWWKKBBBK.",
        "KK...KWKBBKBKY",
        "KBK..KWBBBBBK.",
        ".KBKKBBbbbbbK.",
        "..KBBBBbbbbbK.",
        "...KBBbbbbbK..",
        "....KKbbbKK...",
        "......KKK.....",
    ])

    /// Flügel unten
    static let down = Sprite([
        "..............",
        "..............",
        ".........KKK..",
        "........KBBBK.",
        "KK.....KBBKBKY",
        "KBK...KBBBBBK.",
        ".KBKKBBbbbbbK.",
        "..KBWWWWbbbbK.",
        "...KWWWWWbbK..",
        "....KWWWKKK...",
        ".....KKK......",
    ])

    static func frame(_ bird: Bird) -> Sprite {
        let sprite = Int(bird.flap / 0.11) % 2 == 0 ? up : down
        return bird.facingRight ? sprite : mirrored(sprite)
    }

    private static var mirrorCache: [ObjectIdentifier: Sprite] = [:]

    private static func mirrored(_ sprite: Sprite) -> Sprite {
        if let cached = mirrorCache[ObjectIdentifier(sprite)] { return cached }
        let rows = (0..<sprite.height).map { row in
            String((0..<sprite.width).reversed().map { sprite.pixel($0, row) })
        }
        let result = Sprite(rows)
        mirrorCache[ObjectIdentifier(sprite)] = result
        return result
    }
}
