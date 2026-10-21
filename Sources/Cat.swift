import AppKit

/// Maße der Zeichenfläche in Katzenpixeln. Links und rechts bleibt Platz für "Zzz" und "!".
enum Layout {
    static let canvasWidth = 40
    static let canvasHeight = 36
    static let margin = 8
}

/// Was gerade zu sehen ist.
struct CatLook: Equatable {
    var sprite: Sprite
    var facingRight: Bool
    var hop = 0
    var zCount = 0
    var showBang = false

    static func == (a: CatLook, b: CatLook) -> Bool {
        a.sprite === b.sprite && a.facingRight == b.facingRight && a.hop == b.hop
            && a.zCount == b.zCount && a.showBang == b.showBang
    }
}

// MARK: - Verhalten

/// Zustandsautomat: herumlaufen → hinsetzen → hinlegen → schlafen → aufwachen → …
/// Ein Klick unterbricht alles: erschrecken → wegrennen → wieder beruhigen.
@MainActor
final class CatBrain {
    enum Phase { case standing, walking, fleeing, sittingDown, lyingDown, sleeping, wakingUp, startled }

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

    private var targetX: CGFloat = 0
    private var speed: CGFloat = 40
    private var facingRight = Bool.random()
    private var walksBeforeNap = Int.random(in: 2...4)
    private var blinkCountdown = 3.0
    private var blinkLeft = 0.0

    private var unit: CGFloat { scale / 3 }

    func update(dt: Double) {
        phaseTime += dt
        animTime += dt
        updateBlink(dt)
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
        default:
            if phaseTime >= phaseDuration { phaseFinished() }
        }
    }

    func startle() {
        guard phase != .startled, phase != .fleeing else { return }
        enter(.startled, for: 0.75)
    }

    func goToSleep() {
        guard phase != .sleeping, phase != .lyingDown, phase != .sittingDown else { return }
        walksBeforeNap = 0
        enter(.sittingDown, for: 1.0)
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
            enter(.sleeping, for: .random(in: 45...150))
        case .sleeping:
            enter(.wakingUp, for: 1.6)
        case .wakingUp:
            walksBeforeNap = .random(in: 1...3)
            enter(.standing, for: .random(in: 0.5...1.2))
        case .startled:
            startFleeing()
        case .walking, .fleeing:
            break
        }
    }

    private func arrived() {
        if phase == .fleeing {
            // Erst mal verschnaufen, dann noch ein bisschen bummeln und wieder hinlegen
            walksBeforeNap = .random(in: 1...2)
            enter(.standing, for: .random(in: 1.0...2.0))
            return
        }
        walksBeforeNap -= 1
        enter(.standing, for: walksBeforeNap > 0 ? .random(in: 0.4...2.5) : .random(in: 0.3...0.8))
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
        speed = .random(in: 28...48) * unit
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

        let distance = CGFloat.random(in: 180...420) * unit
        targetX = right ? min(x + distance, maxX) : max(x - distance, minX)
        speed = 230 * unit
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

    var look: CatLook {
        var look = CatLook(sprite: Frames.stand, facingRight: facingRight)
        let blinking = blinkLeft > 0

        switch phase {
        case .standing:
            look.sprite = blinking ? Frames.standBlink : Frames.stand
        case .walking:
            let cycle = [Frames.walkA, Frames.stand, Frames.walkB, Frames.stand]
            look.sprite = cycle[Int(animTime / 0.14) % cycle.count]
        case .fleeing:
            look.sprite = Int(animTime / 0.07) % 2 == 0 ? Frames.walkA : Frames.walkB
        case .sittingDown:
            look.sprite = blinking ? Frames.sitBlink : Frames.sit
        case .lyingDown:
            // Gegen Ende werden die Augen schwer
            let sleepy = phaseTime > phaseDuration * 0.65
            look.sprite = blinking || sleepy ? Frames.lieBlink : Frames.lie
        case .sleeping:
            look.sprite = Int(animTime / 1.1) % 2 == 0 ? Frames.sleepA : Frames.sleepB
            look.zCount = Int(animTime.truncatingRemainder(dividingBy: 3.2) / 0.8)
        case .wakingUp:
            if phaseTime < 0.7 {
                look.sprite = Frames.lie
            } else {
                look.sprite = blinking ? Frames.sitBlink : Frames.sit
            }
        case .startled:
            look.sprite = Frames.startled
            let t = min(phaseTime / 0.45, 1)
            look.hop = Int((sin(t * .pi) * 7).rounded())
            look.showBang = true
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

    private func isCat(at point: NSPoint) -> Bool {
        guard let look else { return false }
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

        ctx.saveGState()
        if !look.facingRight {
            ctx.translateBy(x: bounds.width, y: 0)
            ctx.scaleBy(x: -1, y: 1)
        }
        look.sprite.draw(in: ctx, x: CGFloat(Layout.margin), y: CGFloat(look.hop), scale: scale)
        ctx.restoreGState()

        // Einblendungen werden nicht gespiegelt – nur ihre Position wandert mit dem Kopf
        let zPositions = [(20, 9), (23, 14), (26, 19)]
        for (zx, zy) in zPositions.prefix(look.zCount) {
            drawOverlay(Frames.zGlyph, catX: zx, y: zy, look: look, in: ctx)
        }
        if look.showBang {
            drawOverlay(Frames.bang, catX: 16, y: look.sprite.height + look.hop + 1, look: look, in: ctx)
        }
    }

    private func drawOverlay(_ glyph: Sprite, catX: Int, y: Int, look: CatLook, in ctx: CGContext) {
        var x = Layout.margin + catX
        if !look.facingRight { x = Layout.canvasWidth - x - glyph.width }
        glyph.draw(in: ctx, x: CGFloat(x), y: CGFloat(y), scale: scale)
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
    private(set) var isVisible = false

    var scale: CGFloat {
        didSet { applyScale() }
    }

    init(scale: CGFloat) {
        self.scale = scale
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

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastTick, 0.1)
        lastTick = now

        updateBounds()
        brain.update(dt: dt)

        // visibleFrame endet unten an der Oberkante des Docks – genau da läuft die Katze
        let ground = screen?.visibleFrame.minY ?? 0
        panel.setFrameOrigin(NSPoint(x: brain.x.rounded(), y: ground))

        let look = brain.look
        if look != view.look { view.look = look }
    }
}
