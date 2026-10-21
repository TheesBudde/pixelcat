import AppKit

/// Maße der Zeichenfläche in Katzenpixeln. Links und rechts bleibt etwas Luft.
enum Layout {
    static let canvasWidth = 32
    static let canvasHeight = 22
    static let margin = 4
}

/// Was gerade zu sehen ist.
struct CatLook: Equatable {
    var sprite: Sprite
    var facingRight: Bool
    var hop = 0

    static func == (a: CatLook, b: CatLook) -> Bool {
        a.sprite === b.sprite && a.facingRight == b.facingRight && a.hop == b.hop
    }
}

// MARK: - Tageszeit

/// Wie aktiv die Katze ist – hängt von der Uhrzeit ab.
struct Temperament {
    /// Wie viele Runden sie dreht, bevor sie sich hinlegt
    var walks: ClosedRange<Int>
    /// Wie lange sie schläft, bevor sie von selbst aufsteht (Sekunden)
    var sleep: ClosedRange<Double>
    var walkSpeed: ClosedRange<CGFloat>
    var fleeDistance: ClosedRange<CGFloat>
    var fleeSpeed: CGFloat
    /// Wie viele Runden sie nach dem Aufscheuchen noch dreht
    var walksAfterFleeing: ClosedRange<Int>

    static func at(_ date: Date) -> Temperament {
        switch Calendar.current.component(.hour, from: date) {
        case 9..<19: // Tag: unternehmungslustig, kurze Nickerchen
            return Temperament(walks: 3...6, sleep: 15...50, walkSpeed: 32...50,
                               fleeDistance: 140...320, fleeSpeed: 190, walksAfterFleeing: 1...3)
        case 6..<9, 19..<23: // Morgen und Abend: gemütlich
            return Temperament(walks: 2...4, sleep: 40...120, walkSpeed: 26...42,
                               fleeDistance: 100...220, fleeSpeed: 160, walksAfterFleeing: 1...2)
        default: // Nacht: schläft lange und legt sich nach dem Aufscheuchen sofort wieder hin
            return Temperament(walks: 0...1, sleep: 300...900, walkSpeed: 20...30,
                               fleeDistance: 30...80, fleeSpeed: 110, walksAfterFleeing: 0...0)
        }
    }
}

// MARK: - Verhalten

/// Zustandsautomat: herumlaufen → hinsetzen → hinlegen → schlafen → aufwachen → …
/// Klick: erschrecken → ein Stück weglaufen. Streicheln: genießen und anschmiegen.
@MainActor
final class CatBrain {
    enum Phase { case standing, walking, fleeing, sittingDown, lyingDown, sleeping, wakingUp, startled, petted }

    private(set) var phase: Phase = .standing
    private var phaseTime = 0.0
    private var phaseDuration = 1.0
    private var animTime = 0.0

    /// Linke Kante des Fensters in Bildschirmpunkten.
    var x: CGFloat = 0
    var minX: CGFloat = 0
    var maxX: CGFloat = 800
    /// Punkte pro Katzenpixel; das Tempo wächst mit, damit es bei jeder Größe gleich wirkt.
    var scale: CGFloat = 3
    /// Austauschbar, damit sich Tag und Nacht testen lassen.
    var clock: () -> Date = Date.init

    private var targetX: CGFloat = 0
    private var speed: CGFloat = 40
    private var facingRight = Bool.random()
    private lazy var walksBeforeNap = temperament.walks.randomElement() ?? 1
    private var blinkCountdown = 3.0
    private var blinkLeft = 0.0
    private var tailCountdown = 3.0
    private var tailLeft = 0.0
    private var timeSinceStroke = 0.0
    private var pettedWhileLying = false

    private var unit: CGFloat { scale / 3 }
    private var temperament: Temperament { .at(clock()) }
    var isBeingPetted: Bool { phase == .petted }

    func update(dt: Double) {
        phaseTime += dt
        animTime += dt
        updateBlink(dt)
        updateTail(dt)
        x = min(max(x, minX), maxX)

        switch phase {
        case .walking, .fleeing:
            let step = speed * CGFloat(dt)
            if abs(targetX - x) <= step {
                x = targetX
                arrived()
            } else {
                x += targetX > x ? step : -step
            }
        case .petted:
            timeSinceStroke += dt
            if timeSinceStroke > 1.2 { pettingStopped() }
        default:
            if phaseTime >= phaseDuration { phaseFinished() }
        }
    }

    func startle() {
        guard phase != .startled, phase != .fleeing else { return }
        enter(.startled, for: 0.45)
    }

    func goToSleep() {
        guard phase != .sleeping, phase != .lyingDown, phase != .sittingDown else { return }
        walksBeforeNap = 0
        enter(.sittingDown, for: 1.0)
    }

    /// Wird aufgerufen, solange die Maus über die Katze streicht.
    func stroke() {
        timeSinceStroke = 0
        guard phase != .petted, phase != .startled, phase != .fleeing else { return }
        pettedWhileLying = [.sittingDown, .lyingDown, .sleeping, .wakingUp].contains(phase)
        enter(.petted)
    }

    private func enter(_ newPhase: Phase, for duration: Double = 0) {
        phase = newPhase
        phaseTime = 0
        phaseDuration = duration
        animTime = 0
    }

    private func phaseFinished() {
        switch phase {
        case .standing:
            if walksBeforeNap > 0 {
                startWalking()
            } else {
                enter(.sittingDown, for: .random(in: 1.0...1.8))
            }
        case .sittingDown:
            enter(.lyingDown, for: .random(in: 2.5...4.5))
        case .lyingDown:
            enter(.sleeping, for: .random(in: temperament.sleep))
        case .sleeping:
            enter(.wakingUp, for: 1.6)
        case .wakingUp:
            walksBeforeNap = temperament.walks.randomElement() ?? 1
            enter(.standing, for: .random(in: 0.5...1.2))
        case .startled:
            startFleeing()
        case .walking, .fleeing, .petted:
            break
        }
    }

    private func arrived() {
        if phase == .fleeing {
            walksBeforeNap = temperament.walksAfterFleeing.randomElement() ?? 0
            // Nachts direkt wieder hinsetzen, tagsüber erst kurz verschnaufen
            enter(.standing, for: walksBeforeNap > 0 ? .random(in: 1.0...2.0) : .random(in: 0.3...0.6))
            return
        }
        walksBeforeNap -= 1
        enter(.standing, for: walksBeforeNap > 0 ? .random(in: 0.4...2.5) : .random(in: 0.3...0.8))
    }

    private func pettingStopped() {
        if pettedWhileLying {
            // Zufrieden wieder einkuscheln
            enter(.lyingDown, for: .random(in: 3...6))
        } else {
            enter(.standing, for: .random(in: 0.8...1.6))
        }
    }

    private func startWalking() {
        guard maxX > minX else { return }
        var target = x
        for _ in 0..<10 {
            target = .random(in: minX...maxX)
            if abs(target - x) > 60 * unit { break }
        }
        let maxDistance = 450 * unit
        targetX = min(max(target, x - maxDistance), x + maxDistance)
        speed = .random(in: temperament.walkSpeed) * unit
        facingRight = targetX >= x
        enter(.walking)
    }

    private func startFleeing() {
        let roomRight = maxX - x
        let roomLeft = x - minX
        // Meist dahin, wo mehr Platz ist – aber nicht immer
        var right = roomRight > roomLeft
        if Double.random(in: 0..<1) < 0.25 { right.toggle() }
        if (right ? roomRight : roomLeft) < 40 * unit { right.toggle() }

        let distance = CGFloat.random(in: temperament.fleeDistance) * unit
        targetX = right ? min(x + distance, maxX) : max(x - distance, minX)
        speed = temperament.fleeSpeed * unit
        facingRight = right
        enter(.fleeing)
    }

    private func updateBlink(_ dt: Double) {
        if blinkLeft > 0 {
            blinkLeft -= dt
            return
        }
        blinkCountdown -= dt
        if blinkCountdown <= 0 {
            blinkLeft = 0.15
            blinkCountdown = .random(in: 2...6)
        }
    }

    /// Im Liegen hebt sie ab und zu ruhig die Schwanzspitze.
    private func updateTail(_ dt: Double) {
        if tailLeft > 0 {
            tailLeft -= dt
            return
        }
        tailCountdown -= dt
        if tailCountdown <= 0 {
            tailLeft = .random(in: 0.7...1.3)
            tailCountdown = .random(in: 2.5...7)
        }
    }

    var look: CatLook {
        var look = CatLook(sprite: Frames.stand, facingRight: facingRight)
        let blinking = blinkLeft > 0
        let tailUp = tailLeft > 0

        switch phase {
        case .standing:
            look.sprite = blinking ? Frames.standBlink : Frames.stand
        case .walking:
            let cycle = [Frames.walkA, Frames.stand, Frames.walkB, Frames.stand]
            look.sprite = cycle[Int(animTime / 0.14) % cycle.count]
        case .fleeing:
            look.sprite = Int(animTime / 0.08) % 2 == 0 ? Frames.walkA : Frames.walkB
        case .sittingDown:
            look.sprite = blinking ? Frames.sitBlink : Frames.sit
        case .lyingDown:
            // Gegen Ende werden die Augen schwer
            let eyesClosed = blinking || phaseTime > phaseDuration * 0.65
            if eyesClosed {
                look.sprite = tailUp ? Frames.lieBlinkTailUp : Frames.lieBlink
            } else {
                look.sprite = tailUp ? Frames.lieTailUp : Frames.lie
            }
        case .sleeping:
            if Int(animTime / 1.1) % 2 == 0 {
                look.sprite = tailUp ? Frames.sleepATailUp : Frames.sleepA
            } else {
                look.sprite = tailUp ? Frames.sleepBTailUp : Frames.sleepB
            }
        case .wakingUp:
            if phaseTime < 0.7 {
                look.sprite = Frames.lie
            } else {
                look.sprite = blinking ? Frames.sitBlink : Frames.sit
            }
        case .startled:
            // Kurz zusammenzucken: Buckel und ein kleiner Hüpfer
            look.sprite = Frames.startled
            let t = min(phaseTime / 0.3, 1)
            look.hop = Int((sin(t * .pi) * 3).rounded())
        case .petted:
            // Schmiegt sich im Takt gegen die Hand
            let up = Int(animTime / 0.4) % 2 == 1
            if pettedWhileLying {
                look.sprite = up ? Frames.petLieNuzzle : Frames.petLie
            } else {
                look.sprite = up ? Frames.petStandTall : Frames.petStand
            }
        }
        return look
    }
}

// MARK: - Darstellung

@MainActor
final class CatView: NSView {
    var look: CatLook? {
        didSet { needsDisplay = true }
    }
    var scale: CGFloat = 3 {
        didSet { needsDisplay = true }
    }
    var coat: Coat = .black {
        didSet { needsDisplay = true }
    }
    var onClick: (() -> Void)?

    override var isOpaque: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    /// Nur Klicks auf die Katze selbst zählen, nicht auf die durchsichtige Fläche drumherum.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        return isCat(at: p) ? self : nil
    }

    func isCat(at point: NSPoint) -> Bool {
        guard let look, bounds.contains(point) else { return false }
        var px = Int(floor(point.x / scale))
        if !look.facingRight { px = Layout.canvasWidth - 1 - px }
        let sx = px - Layout.margin
        let row = look.sprite.height - 1 - (Int(floor(point.y / scale)) - look.hop)
        // etwas großzügig, damit auch Lücken zwischen den Beinen treffen
        for dy in -1...1 {
            for dx in -1...1 where look.sprite.pixel(sx + dx, row + dy) != "." {
                return true
            }
        }
        return false
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let look, let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        ctx.setShouldAntialias(false)
        if !look.facingRight {
            ctx.translateBy(x: bounds.width, y: 0)
            ctx.scaleBy(x: -1, y: 1)
        }
        look.sprite.draw(in: ctx, x: CGFloat(Layout.margin), y: CGFloat(look.hop), scale: scale, coat: coat)
    }
}

// MARK: - Fenster

/// Ein randloses, durchsichtiges Fenster, das mit der Katze über die Oberkante des Docks wandert.
@MainActor
final class CatController {
    private let panel: NSPanel
    private let view = CatView()
    private let brain = CatBrain()
    private var timer: Timer?
    private var lastTick = CACurrentMediaTime()
    private var placed = false
    private var lastMouse = NSEvent.mouseLocation
    /// Wie weit die Maus schon über die Katze gestrichen ist
    private var strokeDistance: CGFloat = 0
    private(set) var isVisible = false

    var scale: CGFloat {
        didSet { applyScale() }
    }

    var coat: Coat {
        didSet { view.coat = coat }
    }

    init(scale: CGFloat, coat: Coat) {
        self.scale = scale
        self.coat = coat
        view.coat = coat
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = view
        view.onClick = { [weak self] in self?.brain.startle() }
        applyScale()
    }

    func show() {
        guard !isVisible else { return }
        isVisible = true
        updateBounds()
        if !placed {
            brain.x = .random(in: brain.minX...max(brain.minX, brain.maxX))
            placed = true
        }
        lastTick = CACurrentMediaTime()
        tick()
        panel.orderFrontRegardless()

        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        timer?.invalidate()
        timer = nil
        panel.orderOut(nil)
    }

    func startle() { brain.startle() }
    func goToSleep() { brain.goToSleep() }

    /// Der Hauptbildschirm (der mit der Menüleiste).
    private var screen: NSScreen? { NSScreen.screens.first }

    private func applyScale() {
        let size = NSSize(width: CGFloat(Layout.canvasWidth) * scale,
                          height: CGFloat(Layout.canvasHeight) * scale)
        panel.setContentSize(size)
        view.frame = NSRect(origin: .zero, size: size)
        view.scale = scale
        brain.scale = scale
        if isVisible {
            updateBounds()
            tick()
        }
    }

    private func updateBounds() {
        guard let frame = screen?.frame else { return }
        brain.minX = frame.minX - CGFloat(Layout.margin) * scale
        brain.maxX = frame.maxX - CGFloat(Layout.canvasWidth - Layout.margin) * scale
    }

    /// Streicheln: Die Maus bewegt sich über der Katze, ohne zu klicken.
    /// Die Mausposition wird einfach abgefragt – dafür braucht es keine Sonderrechte.
    private func checkStroking() {
        let mouse = NSEvent.mouseLocation
        defer { lastMouse = mouse }
        let origin = panel.frame.origin
        let local = NSPoint(x: mouse.x - origin.x, y: mouse.y - origin.y)
        guard NSEvent.pressedMouseButtons == 0, view.isCat(at: local) else {
            strokeDistance = 0
            return
        }
        let moved = hypot(mouse.x - lastMouse.x, mouse.y - lastMouse.y)
        guard moved > 0.5 else { return }
        strokeDistance += moved
        if strokeDistance > 25 * scale / 3 || brain.isBeingPetted {
            brain.stroke()
        }
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastTick, 0.1)
        lastTick = now

        updateBounds()
        checkStroking()
        brain.update(dt: dt)

        // visibleFrame endet unten an der Oberkante des Docks – genau da läuft die Katze
        let ground = screen?.visibleFrame.minY ?? 0
        panel.setFrameOrigin(NSPoint(x: brain.x.rounded(), y: ground))

        let look = brain.look
        if look != view.look { view.look = look }
    }
}
