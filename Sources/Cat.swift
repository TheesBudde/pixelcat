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

// MARK: - Spielsachen

/// Wollknäuel mit einfacher Physik: Schwerkraft, Abprallen, Rollreibung.
@MainActor
final class Ball {
    /// Mitte des Knäuels in Bildschirmpunkten
    var x: CGFloat
    /// Höhe der Unterkante über dem Boden
    var y: CGFloat = 0
    var vx: CGFloat = 0
    var vy: CGFloat = 0
    var isHeld = false
    private(set) var rolled: CGFloat = 0

    init(x: CGFloat) { self.x = x }

    func update(dt: Double, minX: CGFloat, maxX: CGFloat, maxY: CGFloat, unit: CGFloat) {
        guard !isHeld else { return }
        let t = CGFloat(dt)
        vy -= 1600 * unit * t
        x += vx * t
        y += vy * t
        if y <= 0 {
            y = 0
            vy = vy < -80 * unit ? -vy * 0.45 : 0
            vx *= pow(0.3, t)
            if abs(vx) < 4 * unit { vx = 0 }
        }
        if y > maxY { y = maxY; vy = min(vy, 0) }
        if x < minX { x = minX; vx = abs(vx) * 0.6 }
        if x > maxX { x = maxX; vx = -abs(vx) * 0.6 }
        rolled += vx * t
    }
}

@MainActor
final class Bowl {
    let x: CGFloat
    /// 1 = voll, 0 = leer
    var food = 1.0
    var emptyFor = 0.0

    init(x: CGFloat) { self.x = x }
}

// MARK: - Verhalten

/// Zustandsautomat: herumlaufen → hinsetzen → hinlegen → schlafen → aufwachen → …
/// Dazu: erschrecken, gestreichelt werden, fressen, mit dem Knäuel spielen, Pomodoro.
@MainActor
final class CatBrain {
    enum Phase {
        case standing, walking, fleeing, sittingDown, lyingDown, sleeping, wakingUp, startled, petted
        case stretching, yawning, grooming, headWashing, backRolling, eating, chasing, batting, watching
    }

    enum Mode {
        case normal
        /// Pomodoro-Fokus: schläft fest und lässt sich nicht aufscheuchen
        case focus
        /// Pomodoro-Pause: wach und unterwegs
        case focusBreak
    }

    private enum Goal { case wander, bowl, center }

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

    var mode: Mode = .normal {
        didSet { if mode != oldValue { modeChanged(from: oldValue) } }
    }
    var ball: Ball?
    var bowl: Bowl?

    private var goal: Goal = .wander
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
    private var rolledThisNap = false
    private var reminderPending = false
    /// Strecken und Gähnen gehören zur Pausen-Erinnerung in der Bildschirmmitte
    private var breakRoutine = false
    private var chaseMoving = false
    private var batsUntilRest = Int.random(in: 6...12)

    private var unit: CGFloat { scale / 3 }
    private var temperament: Temperament { .at(clock()) }
    private var center: CGFloat { x + CGFloat(Layout.canvasWidth) / 2 * scale }
    var isBeingPetted: Bool { phase == .petted }

    // MARK: Von außen

    func update(dt: Double) {
        phaseTime += dt
        animTime += dt
        updateBlink(dt)
        updateTail(dt)
        x = clampX(x)

        switch phase {
        case .walking, .fleeing:
            let step = speed * CGFloat(dt)
            if abs(targetX - x) <= step {
                x = targetX
                arrived()
            } else {
                x += targetX > x ? step : -step
            }
        case .chasing:
            updateChase(dt)
        case .petted:
            timeSinceStroke += dt
            if timeSinceStroke > 1.2 { pettingStopped() }
        case .eating:
            bowl?.food = max(0, 1 - phaseTime / phaseDuration)
            if phaseTime >= phaseDuration { phaseFinished() }
        case .watching:
            if let ball {
                if abs(ball.x - center) > 4 * scale { facingRight = ball.x > center }
                if ball.isHeld {
                    phaseTime = 0
                    phaseDuration = 0.4
                }
            }
            if phaseTime >= phaseDuration { phaseFinished() }
        default:
            if phaseTime >= phaseDuration { phaseFinished() }
        }
    }

    func startle() {
        guard mode != .focus, phase != .startled, phase != .fleeing else { return }
        goal = .wander
        enter(.startled, for: 0.45)
    }

    func goToSleep() {
        guard ![.sleeping, .lyingDown, .sittingDown, .backRolling].contains(phase) else { return }
        walksBeforeNap = 0
        goal = .wander
        enter(.sittingDown, for: 1.0)
    }

    /// Wird aufgerufen, solange die Maus über die Katze streicht.
    func stroke() {
        timeSinceStroke = 0
        guard phase != .petted, phase != .startled, phase != .fleeing else { return }
        pettedWhileLying = mode == .focus
            || [.sittingDown, .lyingDown, .sleeping, .wakingUp, .backRolling].contains(phase)
        goal = .wander
        enter(.petted)
    }

    /// Napf hingestellt oder Knäuel ausgepackt: Die Katze wird aufmerksam.
    func noticeSomething() {
        guard mode != .focus else { return }
        switch phase {
        case .sleeping, .lyingDown, .backRolling:
            enter(.wakingUp, for: 1.2)
        case .standing, .walking, .sittingDown, .grooming, .headWashing, .watching,
             .yawning, .stretching, .chasing, .batting:
            goal = .wander
            enter(.standing, for: 0.3)
        default:
            break // erschrocken, gestreichelt oder am Fressen: danach geht's weiter
        }
    }

    /// Pausen-Erinnerung: zur Bildschirmmitte laufen und sich strecken.
    func remindToTakeBreak() {
        guard mode == .normal else { return }
        reminderPending = true
        noticeSomething()
    }

    // MARK: Ablauf

    private func enter(_ newPhase: Phase, for duration: Double = 0) {
        phase = newPhase
        phaseTime = 0
        phaseDuration = duration
        animTime = 0
    }

    private func phaseFinished() {
        switch phase {
        case .standing:
            decideNext()
        case .sittingDown:
            rolledThisNap = false
            enter(.lyingDown, for: .random(in: 2.5...4.5))
        case .lyingDown:
            if mode != .focus, !rolledThisNap, Double.random(in: 0..<1) < 0.3 {
                rolledThisNap = true
                enter(.backRolling, for: .random(in: 4...8))
            } else {
                enter(.sleeping, for: sleepDuration())
            }
        case .backRolling:
            enter(.lyingDown, for: .random(in: 1.5...3))
        case .sleeping:
            if mode == .focus {
                enter(.sleeping, for: .infinity)
            } else {
                enter(.wakingUp, for: 1.6)
            }
        case .wakingUp:
            walksBeforeNap = temperament.walks.randomElement() ?? 1
            if mode == .focusBreak || Double.random(in: 0..<1) < 0.7 {
                enter(.stretching, for: 1.8)
            } else {
                enter(.standing, for: .random(in: 0.5...1.2))
            }
        case .stretching:
            if breakRoutine || Double.random(in: 0..<1) < 0.6 {
                enter(.yawning, for: 1.3)
            } else {
                enter(.standing, for: .random(in: 0.4...1.0))
            }
        case .yawning:
            if breakRoutine {
                breakRoutine = false
                enter(.watching, for: .random(in: 4...6))
            } else {
                enter(.standing, for: .random(in: 0.4...1.0))
            }
        case .grooming, .headWashing, .watching:
            enter(.standing, for: .random(in: 0.3...0.8))
        case .eating:
            enter(.grooming, for: .random(in: 3...5))
        case .batting:
            batBall()
            batsUntilRest -= 1
            if batsUntilRest <= 0 {
                batsUntilRest = .random(in: 6...12)
                enter(Bool.random() ? .grooming : .headWashing, for: .random(in: 3...5))
            } else if Double.random(in: 0..<1) < 0.25 {
                enter(.watching, for: .random(in: 1.5...3))
            } else {
                enter(.standing, for: .random(in: 0.2...0.7))
            }
        case .startled:
            startFleeing()
        case .walking, .fleeing, .petted, .chasing:
            break
        }
    }

    /// Was als Nächstes? Wird aus dem Stehen heraus entschieden.
    private func decideNext() {
        if mode == .focus {
            enter(.sittingDown, for: 1.0)
        } else if let bowl, bowl.food > 0 {
            walk(mouthTo: bowl.x, goal: .bowl, speed: 70 * unit)
        } else if reminderPending {
            reminderPending = false
            goal = .center
            walk(to: (minX + maxX) / 2, speed: 60 * unit)
        } else if ball != nil {
            enter(.chasing)
        } else if mode == .focusBreak || walksBeforeNap > 0 {
            startWalking()
        } else {
            enter(.sittingDown, for: .random(in: 1.0...1.8))
        }
    }

    private func arrived() {
        if phase == .fleeing {
            walksBeforeNap = temperament.walksAfterFleeing.randomElement() ?? 0
            // Nachts direkt wieder hinsetzen, tagsüber erst kurz verschnaufen
            enter(.standing, for: walksBeforeNap > 0 ? .random(in: 1.0...2.0) : .random(in: 0.3...0.6))
            return
        }
        let reachedGoal = goal
        goal = .wander
        switch reachedGoal {
        case .bowl:
            if let bowl, bowl.food > 0 {
                facingRight = bowl.x > center
                enter(.eating, for: 7)
            } else {
                enter(.standing, for: 0.5)
            }
        case .center:
            breakRoutine = true
            enter(.stretching, for: 2.2)
        case .wander:
            walksBeforeNap -= 1
            if Double.random(in: 0..<1) < 0.2 {
                // Zwischendurch putzen
                enter(Bool.random() ? .grooming : .headWashing, for: .random(in: 3...6))
            } else {
                enter(.standing, for: walksBeforeNap > 0 ? .random(in: 0.4...2.5) : .random(in: 0.3...0.8))
            }
        }
    }

    private func pettingStopped() {
        if pettedWhileLying {
            // Zufrieden wieder einkuscheln
            enter(.lyingDown, for: .random(in: 3...6))
        } else {
            enter(.standing, for: .random(in: 0.8...1.6))
        }
    }

    private func modeChanged(from oldMode: Mode) {
        switch mode {
        case .focus:
            goal = .wander
            reminderPending = false
            breakRoutine = false
            switch phase {
            case .sleeping: phaseDuration = .infinity
            case .lyingDown, .sittingDown, .startled, .fleeing: break // landet ohnehin im Schlaf
            case .backRolling: enter(.lyingDown, for: 1.5)
            case .petted: pettedWhileLying = true
            default: enter(.sittingDown, for: 1.0)
            }
        case .focusBreak:
            if [.sleeping, .lyingDown, .sittingDown, .backRolling].contains(phase) {
                enter(.wakingUp, for: 1.4)
            }
        case .normal:
            if phase == .sleeping, phaseDuration.isInfinite {
                phaseDuration = phaseTime + .random(in: temperament.sleep)
            }
            if oldMode == .focusBreak {
                walksBeforeNap = temperament.walks.randomElement() ?? 1
            }
        }
    }

    private func sleepDuration() -> Double {
        mode == .focus ? .infinity : .random(in: temperament.sleep)
    }

    // MARK: Laufen

    private func clampX(_ value: CGFloat) -> CGFloat {
        min(max(value, minX), maxX)
    }

    private func walk(to windowX: CGFloat, speed: CGFloat) {
        targetX = clampX(windowX)
        self.speed = speed
        facingRight = targetX >= x
        enter(.walking)
    }

    /// Läuft so, dass das Maul am Ende genau über `screenX` ist.
    private func walk(mouthTo screenX: CGFloat, goal: Goal, speed: CGFloat) {
        let dir: CGFloat = screenX >= center ? 1 : -1
        self.goal = goal
        walk(to: screenX - (16 + 8 * dir) * scale, speed: speed)
        facingRight = dir > 0
    }

    private func startWalking() {
        guard maxX > minX else { return }
        var target = x
        for _ in 0..<10 {
            target = .random(in: minX...maxX)
            if abs(target - x) > 60 * unit { break }
        }
        let maxDistance = 450 * unit
        goal = .wander
        walk(to: min(max(target, x - maxDistance), x + maxDistance),
             speed: .random(in: temperament.walkSpeed) * unit)
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

    // MARK: Spielen

    private func updateChase(_ dt: Double) {
        guard let ball else {
            enter(.standing, for: 0.4)
            return
        }
        if ball.isHeld {
            enter(.watching, for: 0.4)
            return
        }
        if abs(ball.x - center) > 4 * scale { facingRight = ball.x > center }
        let dir: CGFloat = facingRight ? 1 : -1
        // Steht so, dass das Knäuel direkt vor der Tatze liegt
        let desired = clampX(ball.x - (16 + 12 * dir) * scale)
        let distance = desired - x
        let reachable = ball.y < 4 * unit && abs(ball.vx) < 150 * unit
        if abs(distance) < 3 * scale, reachable {
            enter(.batting, for: 0.35)
            return
        }
        let chaseSpeed = (abs(distance) > 90 * unit ? 150 : 70) * unit
        let step = min(abs(distance), chaseSpeed * CGFloat(dt))
        x += distance > 0 ? step : -step
        chaseMoving = step > 0.05
        speed = chaseSpeed
    }

    private func batBall() {
        guard let ball, abs(ball.x - center) < 20 * scale, Double.random(in: 0..<1) < 0.85 else { return }
        let dir: CGFloat = facingRight ? 1 : -1
        ball.vx = dir * .random(in: 160...360) * unit
        ball.vy = .random(in: 60...320) * unit
    }

    // MARK: Kleinigkeiten

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

    // MARK: Aussehen

    var look: CatLook {
        var look = CatLook(sprite: Frames.stand, facingRight: facingRight)
        let blinking = blinkLeft > 0
        let tailUp = tailLeft > 0
        func alternate(_ a: Sprite, _ b: Sprite, every seconds: Double) -> Sprite {
            Int(animTime / seconds) % 2 == 0 ? a : b
        }

        switch phase {
        case .standing:
            look.sprite = blinking ? Frames.standBlink : Frames.stand
        case .walking:
            if speed > 100 * unit {
                look.sprite = alternate(Frames.walkA, Frames.walkB, every: 0.08)
            } else {
                let cycle = [Frames.walkA, Frames.stand, Frames.walkB, Frames.stand]
                look.sprite = cycle[Int(animTime / 0.14) % cycle.count]
            }
        case .fleeing:
            look.sprite = alternate(Frames.walkA, Frames.walkB, every: 0.08)
        case .chasing:
            if !chaseMoving {
                look.sprite = blinking ? Frames.standBlink : Frames.stand
            } else if speed > 100 * unit {
                look.sprite = alternate(Frames.walkA, Frames.walkB, every: 0.07)
            } else {
                let cycle = [Frames.walkA, Frames.stand, Frames.walkB, Frames.stand]
                look.sprite = cycle[Int(animTime / 0.11) % cycle.count]
            }
        case .sittingDown, .watching:
            look.sprite = blinking ? Frames.sitBlink : Frames.sit
        case .lyingDown:
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
            if pettedWhileLying {
                look.sprite = alternate(Frames.petLie, Frames.petLieNuzzle, every: 0.4)
            } else {
                look.sprite = alternate(Frames.petStand, Frames.petStandTall, every: 0.4)
            }
        case .stretching:
            look.sprite = Frames.stretch
        case .yawning:
            look.sprite = phaseTime < 0.25 || phaseTime > phaseDuration - 0.25 ? Frames.sitBlink : Frames.yawn
        case .grooming:
            look.sprite = alternate(Frames.groomA, Frames.groomB, every: 0.3)
        case .headWashing:
            look.sprite = alternate(Frames.headWashA, Frames.headWashB, every: 0.35)
        case .backRolling:
            look.sprite = alternate(Frames.rollA, Frames.rollB, every: 0.5)
        case .eating:
            look.sprite = alternate(Frames.eatA, Frames.eatB, every: 0.25)
        case .batting:
            look.sprite = Frames.bat
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
        look.sprite.draw(in: ctx, x: CGFloat(Layout.margin), y: CGFloat(look.hop), scale: scale,
                         colors: coat.colors)
    }
}
