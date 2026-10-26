import AppKit

/// Maße der Zeichenfläche in Katzenpixeln. Links und rechts bleibt etwas Luft,
/// oben genug Platz für die hochkant kletternde Katze.
enum Layout {
    static let canvasWidth = 32
    static let canvasHeight = 26
    static let margin = 4
    /// Wo die hochkant gedrehten Kletterbilder stehen
    static let climbX = 8
}

/// Was gerade zu sehen ist.
struct CatLook: Equatable {
    var sprite: Sprite
    var facingRight: Bool
    var hop = 0
    var drawX = Layout.margin

    static func == (a: CatLook, b: CatLook) -> Bool {
        a.sprite === b.sprite && a.facingRight == b.facingRight && a.hop == b.hop && a.drawX == b.drawX
    }
}

/// Sichtbarer Teil einer Fensteroberkante, auf dem die Katze laufen kann.
/// Alle Werte in Bildschirmpunkten, y zählt von unten.
struct Perch: Equatable {
    /// Fensternummer – bleibt gleich, solange das Fenster existiert
    let id: Int
    /// Höhe der Oberkante
    let y: CGFloat
    /// begehbarer, nicht verdeckter Abschnitt der Oberkante
    let minX: CGFloat
    let maxX: CGFloat
    /// Fensterränder, an denen die Katze hoch- und runterklettert
    let left: CGFloat
    let right: CGFloat
    let bottom: CGFloat
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

    /// Fokus aktiv: wenig unterwegs, lange Nickerchen
    static let calm = Temperament(walks: 0...2, sleep: 120...400, walkSpeed: 22...34,
                                  fleeDistance: 60...140, fleeSpeed: 130, walksAfterFleeing: 0...1)

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
    /// Wassernapf (Trink-Erinnerung) statt Futter
    let water: Bool
    /// 1 = voll, 0 = leer
    var food = 1.0
    var emptyFor = 0.0

    init(x: CGFloat, water: Bool = false) {
        self.x = x
        self.water = water
    }
}

// MARK: - Verhalten

/// Zustandsautomat: herumlaufen → hinsetzen → hinlegen → schlafen → aufwachen → …
/// Dazu: erschrecken, gestreichelt werden, fressen, spielen, Pomodoro und auf Fenster klettern.
@MainActor
final class CatBrain {
    enum Phase {
        case standing, walking, fleeing, sittingDown, lyingDown, sleeping, wakingUp, startled, petted
        case stretching, yawning, grooming, headWashing, backRolling, eating, chasing, batting, watching
        /// Aus dem Wassernapf schlabbern
        case drinking
        /// Augenpause: von hinten auf dem Fensterbrett sitzen und hinausschauen
        case gazing
        /// Sitzen und mit langsamem Blinzeln anschauen
        case slowBlinking
        /// Hinlegen, auf den Rücken rollen, mit den Pfoten zappeln, wieder aufstehen
        case wriggling
        case climbingUp, climbingDown, jumping, falling
        /// Anschleichen an den Mauszeiger, Hinterteil wackeln – dann Sprung
        case stalking
        /// Boden fällt weg (Vollbild): Vorderpfote ausstrecken, dann hinunterhopsen
        case reachingDown
        /// Boden steigt (zurück vom Vollbild): ducken, dann aufs Dock hinaufspringen
        case reachingUp
        /// Ins Körbchen im Dock steigen, im Kreis drehen, hinlegen – und auf Körbchengröße schrumpfen
        case enteringBasket
        /// Umgekehrt: wachsen, aufstehen, aufs Dock hinaufspringen
        case leavingBasket
        /// Auf Streifzug: außerhalb des Bildschirms
        case away
        /// Geführte Pause: eine Übung vormachen (strecken, Buckel, atmen …)
        case exercising
    }

    enum Mode {
        case normal
        /// Pomodoro-Fokus: schläft fest und lässt sich nicht aufscheuchen
        case focus
        /// Pomodoro-Pause: wach und unterwegs
        case focusBreak
    }

    /// Kletterweg an einer Fensterseite
    private struct Wall {
        let perchID: Int
        /// true: linke Fensterseite – die Wand ist rechts von der Katze
        let wallOnRight: Bool
    }

    private enum Landing {
        case dock
        case perch(Int)
        case wall(Wall)
        /// hinter dem Dock verschwinden – sie liegt jetzt im Körbchen
        case basket
    }

    private struct Jump {
        let fromX, fromY, toX, toY: CGFloat
        let duration: Double
        let arc: CGFloat
        let landing: Landing
    }

    private enum Goal {
        case wander, bowl, center
        /// zum Fenster der Augenpause
        case lookout
        /// Streifzug: aus dem Bild hinaus bzw. zurück aufs Dock
        case exit, comeBack
        /// Zum Nachbarbildschirm hinüberlaufen (true = links)
        case otherScreen(Bool)
        /// zum Körbchen im Dock laufen und hineinhüpfen
        case intoBasket
        case climbUp(Wall)
        case climbDown(Wall)
        /// Am Ziel abspringen – die Landestelle steht als Mitte der Katze (Bildschirm-x) drin
        case jump(toCenter: CGFloat, toY: CGFloat, landing: Landing)
    }

    private(set) var phase: Phase = .standing
    private var phaseTime = 0.0
    private var phaseDuration = 1.0
    private var animTime = 0.0

    /// Linke untere Ecke des Fensters in Bildschirmpunkten.
    var x: CGFloat = 0
    var y: CGFloat = 0
    /// Grenzen auf dem Dock (für die linke Fensterkante) und Höhe der Dock-Oberkante.
    var minX: CGFloat = 0
    var maxX: CGFloat = 800
    var dockY: CGFloat = 0
    /// Punkte pro Katzenpixel; das Tempo wächst mit, damit es bei jeder Größe gleich wirkt.
    var scale: CGFloat = 3
    /// Austauschbar, damit sich Tag und Nacht testen lassen.
    var clock: () -> Date = Date.init
    /// Wie oft sie zu Nachbarfenstern springt (1 = normal; der Demo-Modus dreht auf)
    var adventurousness = 1.0

    var mode: Mode = .normal {
        didSet { if mode != oldValue { modeChanged(from: oldValue) } }
    }
    var ball: Ball?
    /// Vogel, der umherfliegt, während niemand am Rechner ist
    var bird: Bird?
    /// Geführte Pause: welche Übung sie gerade vormacht (nil = keine)
    var exercise: Exercise? {
        didSet {
            guard exercise != oldValue else { return }
            if phase == .exercising {
                phaseTime = 0
                animTime = 0
            } else if exercise != nil, oldValue == nil, !isAirborne, !isAboveDock,
                      [.standing, .walking, .sittingDown, .lyingDown, .sleeping, .grooming, .headWashing, .yawning,
                       .watching, .slowBlinking].contains(phase) {
                if case .exit = goal { return } // geht gerade hinaus – kommt die Pause, kommt sie zurück
                enter(.standing, for: 0.2) // gleich anfangen
            }
        }
    }
    private var exerciseDirection: CGFloat = 1
    /// Nach dem Hereinkommen erst ein paarmal nach links und rechts schauen
    var peeksLeft = 0
    /// Nach dem Vogel schnell wieder hinaus bzw. zurück ins Körbchen
    var hurryOut = false
    var bowl: Bowl?
    var climbingEnabled = false {
        didSet {
            if !climbingEnabled {
                leaveWindows()
            } else if !oldValue, !roaming {
                headForWindows()
            }
        }
    }
    private(set) var perches: [Perch] = []

    /// Streifzug: Die Katze ist draußen unterwegs und schaut nur zu Pausen vorbei.
    var roaming = false {
        didSet {
            guard roaming != oldValue else { return }
            if roaming {
                visitTimeLeft = 0
                leaveScreen()
            } else {
                returnToScreen()
            }
        }
    }
    /// Restzeit eines Pausenbesuchs (unendlich: bis die Pomodoro-Pause vorbei ist)
    private var visitTimeLeft = 0.0
    /// Der Besuch gilt einer kleinen Erinnerung (trinken, Fenster, Aufgabe) – nicht der Pause in der Mitte
    private var visitIsErrand = false
    /// Wie lange sie am Wassernapf trinkt (Sekunden)
    var drinkLength = 25.0
    /// Augenpause: Mitte des Fensters (Bildschirm-x), solange es dasteht und sie noch nicht hinausgeschaut hat
    var lookout: CGFloat?
    /// Wie lange sie hinausschaut (Sekunden)
    var gazeLength = 25.0
    /// Meldet, dass sie genug hinausgeschaut hat – dann verschwindet das Fenster
    var onLookoutDone: (() -> Void)?
    private var isVisiting: Bool { visitTimeLeft > 0 }
    /// Läuft gerade aus dem Bild hinaus oder herein – dann gelten die Bildschirmgrenzen nicht
    private var offscreenAllowed = false
    var isAway: Bool { phase == .away }
    /// Im Streifzug und gerade kein Pausenbesuch
    var isOutAndAbout: Bool { roaming && !isVisiting }
    private var mayClimb: Bool { climbingEnabled && !roaming }

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
    /// Schritt in der Aufmerksamkeits-Schleife (strecken → blinzeln → rekeln → blinzeln → …)
    private var attentionStep = 0

    /// Dauer des Streck-Ablaufs – überall gleich
    private static let stretchLength = 2.8

    /// Auf welchem Fenster sie steht – nil heißt: auf dem Dock
    private var perchID: Int?
    private var wall: Wall?
    private var jump: Jump?
    private var fallSpeed: CGFloat = 0

    private var unit: CGFloat { scale / 3 }
    private var temperament: Temperament { calm ? .calm : .at(clock()) }

    // MARK: Eingänge von außen

    /// Fokus aktiv: ruhiger, schläft mehr
    var calm = false
    /// Länge einer Pause (Erinnerung, Streifzug-Besuch) in Sekunden
    var breakVisitLength: Double = 5 * 60
    /// Mauszeiger jagen erlaubt?
    var chaseEnabled = true
    /// Mauszeiger nahe am unteren Rand: Position und wie lange er schon ruht (nil = woanders)
    var cursor: (x: CGFloat, y: CGFloat, idle: Double)?
    /// Gibt es links/rechts einen Bildschirm, auf den sie hinüberlaufen darf?
    var neighborLeft = false
    var neighborRight = false
    /// Sie ist zum Nachbarbildschirm hinausgelaufen (true = links) – der Controller wechselt dann den Bildschirm
    var screenSwitchRequest: Bool?
    /// Braucht gerade flüssige 30 Bilder pro Sekunde (sonst darf der Takt sparen)
    var needsSmoothMotion: Bool {
        [.walking, .fleeing, .chasing, .jumping, .falling, .climbingUp, .climbingDown, .stalking, .startled, .batting,
         .reachingDown, .reachingUp, .enteringBasket, .leavingBasket]
            .contains(phase) || (phase == .exercising && exercise == .walk)
    }

    /// Während Videocalls: keine Pausenbesuche, sie bleibt draußen
    var suppressVisits = false {
        didSet {
            guard suppressVisits != oldValue else { return }
            if suppressVisits {
                visitTimeLeft = 0
                leaveScreen()
            } else if roaming, awaitingAcknowledgement || mode == .focusBreak {
                // Call vorbei, aber gerade wäre Pause: jetzt vorbeikommen
                startVisit(for: .infinity)
            }
        }
    }

    private var stalkWiggle = 0.0
    private var pounceFollowUp = false
    /// Nicht pausenlos nach dem Vogel springen
    private var pounceCooldown = 0.0
    /// Auf dem Weg zum Körbchen: wann sie zuletzt nachgesehen hat, wo es steht
    private var basketCheck = 0.0

    /// Körbchen-Modus: Statt hinauszulaufen, hüpft sie ins Körbchen im Dock (Bildschirm-x der Körbchenmitte).
    var basketX: CGFloat?
    /// Ist das Körbchen von hier aus erreichbar (Dock unten auf ihrem Bildschirm, kein Vollbild)?
    var useBasket = false
    /// Sucht das Körbchen im Dock (setzt `basketX` und `basketFloorY`) – nur wenn sie es gleich braucht
    var locateBasket: (() -> Void)?
    /// Steht das Dock links oder rechts, geht sie zu dieser Seite hinaus und kommt dort wieder herein
    var dockSideIsLeft: Bool?
    /// Wie lange sie im Korb noch wartet, bevor sie herausklettert (0 = sofort). Ohne Bedienungshilfen kennt sie
    /// die Stelle nur aus den Dock-Einstellungen – und die speichert das Dock erst kurz nach dem Verschieben.
    var emergeDelay = 0.0
    /// Herausklettern ist angefragt; danach geht es mit `then` weiter
    private var pendingEmerge: (wait: Double, then: () -> Void)?
    /// Wo die Pfoten im Körbchen stehen (innerhalb des Docks)
    var basketFloorY: CGFloat?
    /// Steht gerade vor dem Dock (beim Hinein- und Heraussteigen)
    var isAboveDock: Bool { phase == .enteringBasket || phase == .leavingBasket }
    /// Liegt sie (auch) im Dock-Symbol? Schon in den letzten Augenblicken des Hineinlegens und noch beim
    /// Aufwachen – dann liegt das gleiche Bild genau darüber, und beim Wechsel blitzt nichts.
    var isInBasketPicture: Bool {
        isAway || (phase == .enteringBasket && phaseTime >= 2.85) || (phase == .leavingBasket && phaseTime < 0.3)
    }
    /// Wie weit sie auf Körbchengröße geschrumpft ist (0 = normal, 1 = so klein wie im Dock-Symbol)
    var basketShrink: CGFloat {
        switch phase {
        case .enteringBasket: return CGFloat(min(1, max(0, phaseTime / 0.6)))         // erst schrumpfen …
        case .leavingBasket: return CGFloat(min(1, max(0, 1 - (phaseTime - 1.2) / 0.5))) // … zuletzt wachsen
        default: return 0
        }
    }
    /// Höhe des Bodens beim letzten Takt – ändert sie sich (Vollbild), steigt sie hinunter bzw. hinauf
    private var lastDockY: CGFloat?
    /// Was nach dem Heraushüpfen aus dem Körbchen passieren soll
    private var afterHop: (() -> Void)?
    private var center: CGFloat { x + CGFloat(Layout.canvasWidth) / 2 * scale }
    private var currentPerch: Perch? { perchID.flatMap(perch) }
    private var isAirborne: Bool {
        [.climbingUp, .climbingDown, .jumping, .falling, .reachingDown, .reachingUp, .enteringBasket, .leavingBasket]
            .contains(phase)
    }
    var isBeingPetted: Bool { phase == .petted }

    /// Abgelaufener Timer: Sie wartet in der Mitte, bis man sie streichelt oder anklickt.
    private(set) var awaitingAcknowledgement = false
    /// Meldet, dass sie quittiert wurde
    var onAcknowledged: (() -> Void)?
    /// Meldet das Strecken zu Beginn einer Pause – dann miaut sie
    var onBreakStretch: (() -> Void)?
    var isOnWindow: Bool { perchID != nil || isAirborne }

    private func perch(_ id: Int) -> Perch? { perches.first { $0.id == id } }

    // MARK: Von außen

    func update(dt: Double) {
        phaseTime += dt
        animTime += dt
        updateBlink(dt)
        updateTail(dt)
        if isVisiting {
            visitTimeLeft -= dt
            if visitTimeLeft <= 0 { leaveScreen() }
        }
        if let pending = pendingEmerge {
            if phase != .away {
                pendingEmerge = nil
            } else if pending.wait - dt > 0 {
                pendingEmerge = (pending.wait - dt, pending.then)
            } else if roaming, suppressVisits || (!isVisiting && !awaitingAcknowledgement && mode != .focusBreak) {
                pendingEmerge = nil // inzwischen gibt es keinen Grund mehr herauszukommen
            } else {
                finishEmerge(pending.then)
            }
        }
        // Boden hat sich verschoben (Vollbild an/aus): nicht springen lassen, sondern hinunter-/hinaufsteigen
        if let last = lastDockY, abs(dockY - last) > 3 * unit, perchID == nil, !isAirborne, phase != .away {
            beginGroundChange(from: last)
        }
        lastDockY = dockY
        // Auf dem Weg zum Körbchen kam das Vollbild: dann seitlich hinaus wie im Streifzug
        if case .intoBasket = goal, phase == .walking {
            if !useBasket || basketX == nil {
                leaveScreen()
            } else {
                // Unterwegs jede Sekunde nachsehen – wird das Körbchen im Dock verschoben, läuft sie zur neuen Stelle
                basketCheck += dt
                if basketCheck >= 1 {
                    basketCheck = 0
                    locateBasket?()
                    if let basketX { targetX = clampX(basketX - CGFloat(Layout.canvasWidth) / 2 * scale) }
                    facingRight = targetX >= x
                }
            }
        }
        if !isAirborne {
            if let perch = currentPerch {
                y = perch.y
            } else {
                perchID = nil
                y = dockY
            }
            x = clampX(x)
        }

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
        case .climbingUp, .climbingDown:
            updateClimb(dt)
        case .jumping:
            updateJump()
        case .stalking:
            updateStalk(dt)
        case .exercising:
            updateExercise(dt)
        case .enteringBasket, .leavingBasket:
            updateBasketMove()
        case .falling:
            updateFall(dt)
        case .petted:
            timeSinceStroke += dt
            if timeSinceStroke > 1.2 { pettingStopped() }
        case .eating:
            bowl?.food = max(0, 1 - phaseTime / phaseDuration)
            if phaseTime >= phaseDuration { phaseFinished() }
        case .drinking:
            // Der Wasserstand sinkt ein wenig – ganz leer wird der Napf nicht
            bowl?.food = max(0.35, 1 - 0.65 * phaseTime / phaseDuration)
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

    /// Neue Fensterkanten. Bewegt sich das Fenster unter der Katze, bewegt sie sich mit;
    /// verschwindet es oder wird ihre Stelle verdeckt, fällt sie herunter.
    func setPerches(_ newPerches: [Perch]) {
        let old = perches
        perches = newPerches
        guard let id = perchID ?? wall?.perchID else { return }
        guard let now = perch(id) else {
            if perchID != nil || wall != nil { startFalling() }
            return
        }
        if let before = old.first(where: { $0.id == id }), !isAirborne {
            x += now.left - before.left
        }
        if perchID != nil, !isAirborne,
           center < now.minX - 2 * scale || center > now.maxX + 2 * scale {
            startFalling()
        }
    }

    func startle() {
        guard mode != .focus, phase != .away, !isAboveDock, phase != .startled, phase != .fleeing, phase != .jumping,
              phase != .falling else {
            return
        }
        if phase == .climbingUp || phase == .climbingDown {
            startFalling()
            return
        }
        goal = .wander
        enter(.startled, for: 0.45)
    }

    func goToSleep() {
        guard !isAirborne, phase != .away, ![.sleeping, .lyingDown, .sittingDown, .backRolling].contains(phase) else { return }
        walksBeforeNap = 0
        goal = .wander
        enter(.sittingDown, for: 1.0)
    }

    /// Klick auf die Katze: Wartet sie auf Quittung, freut sie sich – sonst erschrickt sie.
    func clicked() {
        // Beim Hinein- und Herausklettern nicht erschrecken – sie ist gerade klein und halb im Korb
        if isAboveDock {
            acknowledge()
            return
        }
        if awaitingAcknowledgement {
            acknowledge()
            stroke()
        } else {
            startle()
        }
    }

    /// Streicheln oder Klick beendet den abgelaufenen Timer.
    func acknowledge() {
        guard awaitingAcknowledgement else { return }
        awaitingAcknowledgement = false
        reminderPending = false
        if roaming { visitTimeLeft = 0 } // danach geht sie wieder hinaus
        onAcknowledged?()
    }

    /// Wird aufgerufen, solange die Maus über die Katze streicht.
    func stroke() {
        if awaitingAcknowledgement { acknowledge() }
        timeSinceStroke = 0
        guard !isAirborne, phase != .away, phase != .petted, phase != .startled, phase != .fleeing else { return }
        pettedWhileLying = mode == .focus
            || [.sittingDown, .lyingDown, .sleeping, .wakingUp, .backRolling, .wriggling].contains(phase)
        goal = .wander
        enter(.petted)
    }

    /// Napf hingestellt oder Knäuel ausgepackt: Die Katze wird aufmerksam.
    func noticeSomething() {
        guard mode != .focus else { return }
        switch phase {
        case .sleeping, .lyingDown, .backRolling, .wriggling:
            enter(.wakingUp, for: 1.2)
        case .standing, .walking, .sittingDown, .grooming, .headWashing, .watching,
             .yawning, .stretching, .chasing, .batting, .slowBlinking, .stalking:
            goal = .wander
            enter(.standing, for: 0.3)
        default:
            break // erschrocken, gestreichelt, beim Fressen oder Klettern: danach geht's weiter
        }
    }

    /// Pausen-Erinnerung: zur Bildschirmmitte laufen und sich strecken.
    func remindToTakeBreak() {
        guard mode == .normal else { return }
        callToCenter()
    }

    /// Pause angenommen (Daumen hoch): Sie freut sich – zufrieden blinzeln und anschmiegen wie beim Streicheln.
    func rejoice() {
        guard !isAirborne, phase != .away, !isAboveDock else { return }
        timeSinceStroke = -0.8 // etwas länger als ein kurzes Streicheln
        pettedWhileLying = false
        goal = .wander
        enter(.petted)
    }

    /// Pause abgelehnt (Daumen runter): nicht mehr in die Mitte, im Streifzug bzw. Korb gleich wieder zurück.
    /// Angeklickt mitten in einer Erinnerung: aufhören – nicht weitertrinken, nicht weiter hinausschauen
    /// (sie beendet es so, wie sie es sonst auch tut: Schnäuzchen putzen bzw. recken)
    func stopErrand() {
        lookout = nil
        switch goal {
        case .lookout, .bowl, .center: goal = .wander
        default: break
        }
        if phase == .gazing {
            enter(.stretching, for: Self.stretchLength)
        } else if phase == .drinking {
            enter(.headWashing, for: .random(in: 2...3))
        }
    }

    func declineBreak() {
        reminderPending = false
        breakRoutine = false
        if case .center = goal { goal = .wander }
        if roaming, isVisiting, !visitIsErrand {
            visitTimeLeft = 0
            if !isAirborne, phase != .away { leaveScreen() }
        }
    }

    /// Zeit für eine Pause (Erinnerung, abgelaufener Timer): aufwachen, in die Bildschirmmitte
    /// laufen, strecken und gähnen. Im Streifzug kommt sie dafür 5 Minuten herein.
    /// `untilAcknowledged`: Sie bleibt in der Mitte, bis man sie streichelt oder anklickt.
    /// `visitLength`: Im Streifzug so lange bleiben (sonst so lang wie eine Pause).
    func callToCenter(untilAcknowledged: Bool = false, visitLength: Double? = nil) {
        if untilAcknowledged { awaitingAcknowledgement = true }
        if roaming {
            if untilAcknowledged || !isVisiting {
                startVisit(for: untilAcknowledged ? .infinity : visitLength ?? breakVisitLength)
            }
            return
        }
        reminderPending = true
        if mode == .focus { return } // schläft weiter; der Aufruf kommt mit der Pause
        noticeSomething()
    }

    // MARK: Ablauf

    private func enter(_ newPhase: Phase, for duration: Double = 0) {
        if newPhase == .stretching, breakRoutine || mode == .focusBreak { onBreakStretch?() }
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
            if !reminderPending, mode == .focusBreak || Double.random(in: 0..<1) < 0.7 {
                // (soll sie in die Mitte, streckt sie sich erst dort)
                enter(.stretching, for: Self.stretchLength)
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
        case .grooming, .headWashing, .watching, .slowBlinking, .wriggling:
            enter(.standing, for: .random(in: 0.3...0.8))
        case .eating:
            enter(.grooming, for: .random(in: 3...5))
        case .gazing:
            lookout = nil
            onLookoutDone?()
            facingRight = Bool.random()
            enter(.stretching, for: Self.stretchLength) // nach dem Hinausschauen recken
        case .drinking:
            bowl?.food = 0 // fertig getrunken – der Napf wird weggeräumt
            enter(.headWashing, for: .random(in: 3...4)) // Schnäuzchen putzen
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
            if perchID != nil {
                // Auf dem Fenster erschreckt: runterspringen
                jumpDown(quick: true)
            } else {
                startFleeing()
            }
        case .reachingDown, .reachingUp:
            let dir: CGFloat = facingRight ? 1 : -1
            startJump(toX: clampX(x + dir * 14 * unit), toY: dockY, landing: .dock,
                      arc: phase == .reachingDown ? 8 * unit : nil)
        case .walking, .fleeing, .petted, .chasing, .climbingUp, .climbingDown, .jumping, .falling, .away, .stalking,
             .enteringBasket, .leavingBasket, .exercising:
            break
        }
    }

    /// Was als Nächstes? Wird aus dem Stehen heraus entschieden.
    private func decideNext() {
        if isOutAndAbout {
            leaveScreen()
            return
        }
        let needsDock = (bowl?.food ?? 0) > 0 || lookout != nil || reminderPending || ball != nil
            || awaitingAcknowledgement || bird.map { !$0.isLeaving } == true || exercise != nil
        if mode == .focus {
            enter(.sittingDown, for: 1.0) // schläft auch gern oben auf einem Fenster
        } else if perchID != nil, needsDock || !mayClimb {
            leaveWindows()
        } else if awaitingAcknowledgement, !reminderPending {
            waitAtCenter()
        } else if let bowl, bowl.food > 0 {
            walk(mouthTo: bowl.x, goal: .bowl, speed: 70 * unit)
        } else if let lookout {
            goal = .lookout
            walk(to: lookout - CGFloat(Layout.canvasWidth) / 2 * scale, speed: 60 * unit)
        } else if reminderPending {
            reminderPending = false
            goal = .center
            walk(to: (minX + maxX) / 2, speed: 60 * unit)
        } else if exercise != nil, mode != .focus {
            // Geführte Pause: in die Mitte, dann vormachen
            let middle = (minX + maxX) / 2
            if abs(x - middle) > 40 * unit {
                goal = .wander
                walk(to: middle, speed: 70 * unit)
            } else {
                enter(.exercising)
            }
        } else if let bird, !bird.isLeaving {
            if peeksLeft > 0 {
                // Noch etwas verlegen: erst nach links und rechts schauen
                peeksLeft -= 1
                facingRight.toggle()
                enter(.standing, for: .random(in: 0.7...1.1))
            } else {
                enter(.chasing)
            }
        } else if ball != nil {
            enter(.chasing)
        } else if canChaseCursor, let cursor, cursor.idle > 2, abs(cursor.x - center) < 600 * unit,
                  Double.random(in: 0..<1) < 0.7 {
            startStalking(cursor)
        } else if mode == .focusBreak || isVisiting || walksBeforeNap > 0 {
            if mayClimb, climbingStep() { return }
            if !isVisiting, perchID == nil, bowl == nil, mode == .normal, neighborLeft || neighborRight,
               Double.random(in: 0..<1) < 0.07 {
                goToOtherScreen()
                return
            }
            startWalking()
        } else if mayClimb, perchID == nil, climbOntoWindow() {
            // Fürs Nickerchen lieber hinauf aufs Fenster
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
                if bowl.water {
                    enter(.drinking, for: drinkLength)
                } else {
                    enter(.eating, for: 7)
                }
            } else {
                enter(.standing, for: 0.5)
            }
        case .center:
            offscreenAllowed = false
            breakRoutine = true
            enter(.stretching, for: Self.stretchLength)
        case .lookout:
            if let lookout, abs(center - lookout) < 4 * scale {
                enter(.gazing, for: gazeLength)
            } else {
                enter(.standing, for: 0.3) // Fenster weg oder nicht ganz angekommen: neu entscheiden
            }
        case .exit:
            enter(.away, for: .infinity)
        case .intoBasket:
            // Inzwischen Vollbild (kein Dock, kein Körbchen)? Dann nicht ins Leere steigen, sondern hinaus
            guard useBasket, basketX != nil else { return leaveScreen() }
            // Noch einmal nachsehen: Wurde der Korb gerade erst verschoben, dorthin weiterlaufen
            locateBasket?()
            if let basketX, abs(clampX(basketX - CGFloat(Layout.canvasWidth) / 2 * scale) - x) > 2 * unit {
                walk(to: basketX - CGFloat(Layout.canvasWidth) / 2 * scale, speed: 60 * unit)
                return
            }
            guard useBasket, basketX != nil else { return leaveScreen() }
            // ins Körbchen steigen und es sich gemütlich machen
            enter(.enteringBasket, for: 3.3)
        case .otherScreen(let left):
            enter(.away, for: .infinity)
            screenSwitchRequest = left
        case .comeBack:
            offscreenAllowed = false
            enter(.standing, for: .random(in: 0.5...1.2))
        case .wander:
            walksBeforeNap -= 1
            if Double.random(in: 0..<1) < 0.2 {
                // Zwischendurch putzen
                enter(Bool.random() ? .grooming : .headWashing, for: .random(in: 3...6))
            } else {
                enter(.standing, for: walksBeforeNap > 0 ? .random(in: 0.4...2.5) : .random(in: 0.3...0.8))
            }
        case .climbUp(let wall):
            startClimbingUp(wall)
        case .climbDown(let wall):
            startClimbingDown(wall)
        case .jump(let toCenter, let toY, let landing):
            startJump(toX: toCenter - CGFloat(Layout.canvasWidth) / 2 * scale, toY: toY, landing: landing)
        }
    }

    private func pettingStopped() {
        if isOutAndAbout {
            // Streifzug: nach dem Streicheln wieder hinaus statt einzuschlafen
            enter(.standing, for: .random(in: 0.5...1.0))
        } else if pettedWhileLying {
            // Zufrieden wieder einkuscheln
            enter(.lyingDown, for: .random(in: 3...6))
        } else {
            enter(.standing, for: .random(in: 0.8...1.6))
        }
    }

    private func modeChanged(from oldMode: Mode) {
        if roaming {
            // Im Streifzug: Pause = Besuch in der Bildschirmmitte, sonst draußen
            if mode == .focusBreak {
                startVisit(for: .infinity)
            } else if mode == .focus || visitTimeLeft.isInfinite {
                visitTimeLeft = 0
                leaveScreen()
            }
            return
        }
        switch mode {
        case .focus:
            goal = .wander
            reminderPending = false
            breakRoutine = false
            switch phase {
            case .sleeping: phaseDuration = .infinity
            case .lyingDown, .sittingDown, .startled, .fleeing: break // landet ohnehin im Schlaf
            case .climbingUp, .climbingDown, .jumping, .falling: break // erst ankommen
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

    /// Wo die linke Fensterkante sein darf, damit die Katze auf ihrem Untergrund bleibt.
    private var walkRange: ClosedRange<CGFloat> {
        let half = CGFloat(Layout.canvasWidth) / 2 * scale
        if let perch = currentPerch {
            let low = perch.minX + 9 * scale - half
            return low...max(low, perch.maxX - 9 * scale - half)
        }
        return minX...max(minX, maxX)
    }

    private func clampX(_ value: CGFloat) -> CGFloat {
        guard !offscreenAllowed else { return value }
        return min(max(value, walkRange.lowerBound), walkRange.upperBound)
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
        var range = walkRange
        if isVisiting {
            // Beim Pausenbesuch bleibt sie in der Bildschirmmitte
            let middle = (minX + maxX) / 2, span = (maxX - minX) * 0.2
            range = max(range.lowerBound, middle - span)...min(range.upperBound, middle + span)
        }
        guard range.upperBound > range.lowerBound + 10 else {
            enter(.standing, for: 1)
            walksBeforeNap -= 1
            return
        }
        var target = x
        for _ in 0..<10 {
            target = .random(in: range)
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

    /// Wartet in der Bildschirmmitte auf Streicheln und sucht dabei dezent Aufmerksamkeit:
    /// strecken → anschauen und langsam blinzeln → auf dem Rücken rekeln → blinzeln → …
    private func waitAtCenter() {
        let middle = (minX + maxX) / 2
        if abs(x - middle) > 40 * unit {
            goal = .center
            walk(to: middle, speed: 50 * unit)
            return
        }
        attentionStep += 1
        switch attentionStep % 4 {
        case 1:
            if Double.random(in: 0..<1) < 0.4 { facingRight.toggle() } // mal in die andere Richtung
            enter(.stretching, for: Self.stretchLength)
        case 3:
            enter(.wriggling, for: .random(in: 4...5.5))
        default:
            enter(.slowBlinking, for: .random(in: 3...4.5))
        }
    }

    // MARK: Streifzug

    /// Linke Fensterkante, bei der die Katze ganz außerhalb des Bildes ist.
    private func offscreenX(left: Bool) -> CGFloat {
        left ? minX - 26 * scale : maxX + 26 * scale
    }

    /// Beim Programmstart im Streifzug: gleich draußen sein.
    /// Nach der Einrichtung: Sie ist gerade aus dem Fenster aufs Dock gesprungen und steht jetzt hier.
    /// Danach geht es weiter wie eingestellt (in den Korb, auf Streifzug oder einfach dableiben).
    func arrive(centerX: CGFloat) {
        jump = nil
        perchID = nil
        wall = nil
        afterHop = nil
        pendingEmerge = nil
        offscreenAllowed = false
        visitTimeLeft = 0
        goal = .wander
        x = clampX(centerX - CGFloat(Layout.canvasWidth) / 2 * scale)
        y = dockY
        enter(.standing, for: 0.8)
    }

    func startOutside() {
        offscreenAllowed = true
        x = offscreenX(left: true)
        enter(.away, for: .infinity)
    }

    /// Zum nächsten Bildschirmrand hinauslaufen.
    private func leaveScreen() {
        guard phase != .away, !isAirborne else { return } // in der Luft: nach der Landung
        if case .exit = goal, phase == .walking { return }
        if perchID != nil {
            leaveWindows()
            return
        }
        switch phase {
        case .sleeping, .lyingDown, .backRolling, .wriggling:
            enter(.wakingUp, for: 1.0)
            return
        case .startled, .fleeing:
            return // erst zu Ende rennen
        default:
            break
        }
        if useBasket, case .intoBasket = goal, phase == .walking { return }
        if basketReady(), let basketX {
            goal = .intoBasket
            basketCheck = 0
            walk(to: basketX - CGFloat(Layout.canvasWidth) / 2 * scale, speed: (hurryOut ? 120 : 60) * unit)
            hurryOut = false
            return
        }
        var toLeft = x < (minX + maxX) / 2
        // Lieber zu einer Seite ohne Nachbarbildschirm – sonst sähe man sie dort auftauchen
        if toLeft, neighborLeft, !neighborRight { toLeft = false }
        if !toLeft, neighborRight, !neighborLeft { toLeft = true }
        if let dockSideIsLeft { toLeft = dockSideIsLeft } // zum Körbchen im seitlichen Dock
        offscreenAllowed = true
        goal = .exit
        walk(to: offscreenX(left: toLeft), speed: (hurryOut ? 130 : 70) * unit)
        hurryOut = false
    }

    /// Streifzug beendet: von der Seite zurück aufs Dock.
    private func returnToScreen() {
        // Mitten im Hinein- oder Herausklettern: erst fertig klettern (danach wird es nachgeholt)
        if phase == .enteringBasket || phase == .leavingBasket { return }
        visitTimeLeft = 0
        var isLeaving = phase == .away
        if case .exit = goal { isLeaving = true }
        if case .intoBasket = goal { isLeaving = true }
        guard isLeaving else { return }
        walksBeforeNap = temperament.walks.randomElement() ?? 1
        let wander = { [unowned self] in
            goal = .comeBack
            walk(to: .random(in: minX...max(minX, maxX)), speed: .random(in: temperament.walkSpeed) * unit)
        }
        if phase == .away {
            if useBasket {
                requestEmerge(then: wander)
                return
            }
            x = offscreenX(left: entrySideIsLeft())
        }
        wander()
    }

    /// Pausenbesuch: von der Seite herein, in die Mitte, strecken und gähnen – und eine Weile bleiben.
    private func startVisit(for duration: Double) {
        guard !suppressVisits else { return }
        visitTimeLeft = duration
        visitIsErrand = false
        reminderPending = false
        guard !isAirborne, perchID == nil else { return }
        let toCenter = { [unowned self] in
            offscreenAllowed = true
            goal = .center
            walk(to: (minX + maxX) / 2, speed: 65 * unit)
        }
        if phase == .away {
            if useBasket {
                requestEmerge(then: toCenter)
                return
            }
            x = offscreenX(left: entrySideIsLeft())
        }
        toCenter()
    }

    /// Kleiner Besuch für eine Erinnerung (trinken, Fenster, Aufgabe): Sie kommt herein und kümmert sich
    /// um das, was da ist (Napf, Fenster) – nicht in die Bildschirmmitte wie zur Pause.
    func startErrandVisit(for duration: Double) {
        guard roaming, !suppressVisits else { return }
        if isVisiting, !visitIsErrand { return } // gerade ohnehin Pause – dabei wird es mit erledigt
        visitTimeLeft = duration
        visitIsErrand = true
        reminderPending = false
        guard !isAirborne, perchID == nil else { return }
        let comeIn = { [unowned self] in
            offscreenAllowed = true
            goal = .comeBack
            let middle = (minX + maxX) / 2, span = (maxX - minX) * 0.2
            walk(to: .random(in: middle - span...middle + span), speed: 60 * unit)
        }
        switch phase {
        case .away:
            if useBasket {
                requestEmerge(then: comeIn)
                return
            }
            x = offscreenX(left: entrySideIsLeft())
            comeIn()
        case .walking:
            // War auf dem Weg hinaus: umdrehen
            goal = .wander
            enter(.standing, for: 0.3)
        default:
            break
        }
    }

    /// Die Erinnerung ist erledigt: Im Streifzug geht sie danach wieder.
    func endErrandVisit() {
        guard visitIsErrand else { return }
        visitIsErrand = false
        visitTimeLeft = 0
    }

    /// Aus dem Körbchen kommen – wenn nötig erst nach kurzem Warten, damit sie die Stelle sicher kennt.
    private func requestEmerge(then next: @escaping () -> Void) {
        if emergeDelay <= 0 { return finishEmerge(next) }
        if pendingEmerge == nil { pendingEmerge = (emergeDelay, next) } else { pendingEmerge?.then = next }
    }

    private func finishEmerge(_ next: @escaping () -> Void) {
        pendingEmerge = nil
        if basketReady() {
            emergeFromBasket(then: next)
        } else {
            // Korb nicht (mehr) zu finden: von der Seite herein
            x = offscreenX(left: entrySideIsLeft())
            next()
        }
    }

    /// Körbchen erreichbar? Dann genau jetzt nachsehen, wo es im Dock sitzt.
    private func basketReady() -> Bool {
        guard useBasket else { return false }
        locateBasket?()
        return basketX != nil
    }

    /// Aus dem Körbchen klettern: von hinter dem Dock hinaufspringen, dann weiter.
    private func emergeFromBasket(then next: @escaping () -> Void) {
        guard let basketX else { return next() }
        let half = CGFloat(Layout.canvasWidth) / 2 * scale
        perchID = nil
        offscreenAllowed = false
        x = clampX(basketX - half)
        y = dockY - 30 * scale
        lastDockY = dockY
        y = basketFloorY ?? dockY - 20 * unit
        afterHop = next
        facingRight = basketX < (minX + maxX) / 2 + half
        enter(.leavingBasket, for: 1.7)
    }

    /// Hinein: auf Körbchengröße schrumpfen, Pfote ausstrecken, hineinsteigen, im Kreis drehen, setzen, hinlegen.
    /// Heraus: aufsetzen, aufstehen, aufs Dock hüpfen – und erst dort wieder wachsen.
    private func updateBasketMove() {
        let floor = basketFloorY ?? dockY - 20 * unit
        let t = phaseTime
        if phase == .enteringBasket {
            switch t {
            case ..<1.0:
                y = dockY
            case ..<1.4:
                let u = CGFloat((t - 1.0) / 0.4)
                y = dockY + (floor - dockY) * u + 4 * unit * 4 * u * (1 - u)
            default:
                y = floor
            }
            if phaseTime >= phaseDuration {
                facingRight = true // liegt im Dock-Symbol mit dem Kopf nach rechts
                enter(.away, for: .infinity)
                settledInBasket()
            }
        } else {
            switch t {
            case ..<0.75:
                y = floor
            case ..<1.2:
                let u = CGFloat((t - 0.75) / 0.45)
                y = floor + (dockY - floor) * u + 8 * unit * 4 * u * (1 - u)
                x = clampX(x + (facingRight ? 1 : -1) * 12 * unit / 14)
            default:
                y = dockY
            }
            if phaseTime >= phaseDuration {
                y = dockY
                let next = afterHop
                afterHop = nil
                if roaming, suppressVisits || (!isVisiting && !awaitingAcknowledgement && mode != .focusBreak) {
                    // Während des Herauskletterns war die Pause schon wieder vorbei (oder ein Videocall begann): zurück
                    enter(.standing, for: 0.3)
                    leaveScreen()
                } else if let next {
                    next()
                } else {
                    enter(.standing, for: 0.5)
                }
            }
        }
    }

    /// Gerade fertig hineingelegt: Was in diesen Sekunden passiert ist (Pause, Timer, Erinnerung,
    /// Katzenkorb aus), wird jetzt nachgeholt – sonst bliebe sie liegen.
    private func settledInBasket() {
        if !roaming {
            returnToScreen()
        } else if isVisiting {
            if visitIsErrand { startErrandVisit(for: visitTimeLeft) } else { startVisit(for: visitTimeLeft) }
        } else if mode == .focusBreak || awaitingAcknowledgement {
            startVisit(for: .infinity)
        }
    }

    /// Der Boden ist woanders (Vollbild an/aus): erst Pfote ausstrecken bzw. ducken, dann hinüber.
    private func beginGroundChange(from oldGround: CGFloat) {
        y = oldGround
        goal = .wander
        enter(dockY < oldGround ? .reachingDown : .reachingUp, for: dockY < oldGround ? 0.55 : 0.35)
    }

    /// Von welcher Seite sie hereinkommt: wenn möglich von einer Seite ohne Nachbarbildschirm.
    private func entrySideIsLeft() -> Bool {
        if let dockSideIsLeft { return dockSideIsLeft }
        if neighborLeft != neighborRight { return neighborRight }
        return Bool.random()
    }

    // MARK: Mehrere Bildschirme

    private func goToOtherScreen() {
        let left: Bool
        if neighborLeft, neighborRight { left = Bool.random() } else { left = neighborLeft }
        offscreenAllowed = true
        goal = .otherScreen(left)
        walk(to: offscreenX(left: left), speed: .random(in: temperament.walkSpeed) * unit)
    }

    /// Nach dem Bildschirmwechsel: von der Seite (des neuen Bildschirms) hereinlaufen.
    func arriveFromSide(left: Bool) {
        perchID = nil
        lastDockY = nil // anderer Bildschirm, anderer Boden – kein Hinuntersteigen
        offscreenAllowed = true
        x = offscreenX(left: left)
        y = dockY
        goal = .comeBack
        let into = CGFloat.random(in: 120...400) * unit
        walk(to: left ? minX + into : maxX - into, speed: .random(in: temperament.walkSpeed) * unit)
    }

    // MARK: Mauszeiger jagen

    private var canChaseCursor: Bool {
        chaseEnabled && !roaming && !calm && perchID == nil && mode != .focus && !awaitingAcknowledgement
    }

    private func startStalking(_ cursor: (x: CGFloat, y: CGFloat, idle: Double)) {
        facingRight = cursor.x > center
        stalkWiggle = 0
        goal = .wander
        enter(.stalking)
    }

    /// Langsam anschleichen, kurz mit dem Hinterteil wackeln, dann auf den Mauszeiger springen.
    /// Bewegt sich die Maus, ist die Jagd vorbei.
    private func updateStalk(_ dt: Double) {
        guard let cursor, cursor.idle > 0.2 else {
            stalkWiggle = 0
            enter(.watching, for: .random(in: 1.5...3))
            return
        }
        let dir: CGFloat = cursor.x > center ? 1 : -1
        let desired = clampX(cursor.x - dir * 60 * unit - CGFloat(Layout.canvasWidth) / 2 * scale)
        if stalkWiggle == 0, abs(desired - x) > 2 {
            facingRight = dir > 0
            let step = min(abs(desired - x), 22 * unit * CGFloat(dt))
            x += desired > x ? step : -step
            return
        }
        stalkWiggle += dt
        if stalkWiggle > 0.9 {
            stalkWiggle = 0
            pounceFollowUp = true
            // Pfote landet genau unter dem Zeiger; der Bogen reicht bis auf Zeigerhöhe
            let target = cursor.x - CGFloat(Layout.canvasWidth) / 2 * scale - dir * 8 * scale
            startJump(toX: clampX(target), toY: dockY, landing: .dock,
                      arc: max(25 * unit, cursor.y - dockY - 6 * scale))
        }
    }

    // MARK: Klettern

    /// Wo das Fenster der Katze stehen muss, damit ihre Pfoten die Wand berühren.
    private func climbX(wallX: CGFloat, wallOnRight: Bool) -> CGFloat {
        wallOnRight ? wallX - 23 * scale : wallX - 9 * scale
    }

    private func wallX(_ wall: Wall, _ perch: Perch) -> CGFloat {
        wall.wallOnRight ? perch.left : perch.right
    }

    /// Im Kletter-Modus zieht es sie nach oben: Vom Dock klettert sie hinauf, sobald ein Fenster
    /// erreichbar ist. Oben bleibt sie meist, springt mal zum Nachbarfenster und kommt nur selten herunter.
    private func climbingStep() -> Bool {
        guard let perch = currentPerch else { return climbOntoWindow() }
        if Double.random(in: 0..<1) < min(0.9, 0.3 * adventurousness), jumpToNeighbor(from: perch) { return true }
        if Double.random(in: 0..<1) < 0.06 {
            leaveWindows()
            return true
        }
        return false
    }

    /// Kletter-Modus eingeschaltet: Ist sie wach und unten, macht sie sich gleich auf den Weg.
    private func headForWindows() {
        guard perchID == nil,
              [.standing, .walking, .sittingDown, .grooming, .headWashing, .watching].contains(phase)
        else { return }
        goal = .wander
        enter(.standing, for: 0.3)
    }

    /// Wie hoch sie an einer Fensterseite hinaufspringt, um sich festzukrallen.
    private var wallReach: CGFloat { 220 * unit }

    /// Vom Dock aus: an einer Fensterseite hochklettern oder direkt hinaufspringen.
    private func climbOntoWindow() -> Bool {
        var options: [() -> Void] = []
        let half = CGFloat(Layout.canvasWidth) / 2 * scale
        for perch in perches where perch.y - dockY > 40 * unit {
            // Die Fensterseite reicht bis (fast) aufs Dock: dort hochklettern
            if perch.bottom - dockY <= wallReach {
                let standLeft = perch.left - 10 * scale - half
                if perch.minX <= perch.left + 2, (minX...maxX).contains(standLeft) {
                    options.append { [unowned self] in
                        goal = .climbUp(Wall(perchID: perch.id, wallOnRight: true))
                        walk(to: standLeft, speed: .random(in: temperament.walkSpeed) * unit)
                    }
                }
                let standRight = perch.right + 10 * scale - half
                if perch.maxX >= perch.right - 2, (minX...maxX).contains(standRight) {
                    options.append { [unowned self] in
                        goal = .climbUp(Wall(perchID: perch.id, wallOnRight: false))
                        walk(to: standRight, speed: .random(in: temperament.walkSpeed) * unit)
                    }
                }
            }
            // Niedriges Fenster: einfach hinaufspringen
            if perch.y - dockY <= 200 * unit, perch.maxX - perch.minX > 30 * scale {
                let fromLeft = Bool.random()
                let landing = fromLeft ? perch.minX + 13 * scale : perch.maxX - 13 * scale
                let takeoff = landing + (fromLeft ? -55 : 55) * unit
                if (minX...maxX).contains(takeoff - half) {
                    options.append { [unowned self] in
                        goal = .jump(toCenter: landing, toY: perch.y, landing: .perch(perch.id))
                        walk(to: takeoff - half, speed: .random(in: temperament.walkSpeed) * unit)
                    }
                }
            }
        }
        guard let option = options.randomElement() else { return false }
        option()
        return true
    }

    /// Auf ein anderes Fenster in Sprungweite hüpfen.
    private func jumpToNeighbor(from perch: Perch) -> Bool {
        var options: [() -> Void] = []
        for other in perches where other.id != perch.id && other.maxX - other.minX > 30 * scale {
            let dy = other.y - perch.y
            guard dy <= 170 * unit, dy >= -450 * unit else { continue }
            let takeoff: CGFloat
            let landing: CGFloat
            if other.minX > perch.maxX - 12 * scale {
                // liegt rechts daneben
                guard other.minX - perch.maxX <= 260 * unit else { continue }
                takeoff = perch.maxX - 11 * scale
                landing = other.minX + 13 * scale
            } else if other.maxX < perch.minX + 12 * scale {
                // liegt links daneben
                guard perch.minX - other.maxX <= 260 * unit else { continue }
                takeoff = perch.minX + 11 * scale
                landing = other.maxX - 13 * scale
            } else {
                // darüber oder darunter
                guard abs(dy) > 30 * unit else { continue }
                let low = max(perch.minX, other.minX) + 13 * scale
                let high = min(perch.maxX, other.maxX) - 13 * scale
                guard high > low else { continue }
                takeoff = .random(in: low...high)
                landing = takeoff + .random(in: -30...30) * unit
            }
            options.append { [unowned self] in
                goal = .jump(toCenter: landing, toY: other.y, landing: .perch(other.id))
                walk(to: takeoff - CGFloat(Layout.canvasWidth) / 2 * scale,
                     speed: .random(in: temperament.walkSpeed) * unit)
            }
        }
        guard let option = options.randomElement() else { return false }
        option()
        return true
    }

    /// Vom Fenster zurück aufs Dock: an der Seite runterklettern oder runterspringen.
    private func leaveWindows() {
        switch phase {
        case .climbingUp:
            if let wall { startClimbingDown(wall) }
            return
        case .climbingDown, .jumping, .falling:
            return
        default:
            break
        }
        guard let perch = currentPerch else { return }
        let toLeft = center - perch.minX < perch.maxX - center
        let canClimb = perch.bottom - dockY <= wallReach
            && (toLeft ? perch.minX <= perch.left + 2 : perch.maxX >= perch.right - 2)
        if canClimb, Double.random(in: 0..<1) < 0.5 {
            let edge = toLeft ? perch.left + 10 * scale : perch.right - 10 * scale
            goal = .climbDown(Wall(perchID: perch.id, wallOnRight: toLeft))
            walk(to: edge - CGFloat(Layout.canvasWidth) / 2 * scale, speed: 45 * unit)
        } else {
            jumpDown(quick: !climbingEnabled)
        }
    }

    private func jumpDown(quick: Bool) {
        guard let perch = currentPerch else { return }
        let toLeft = center - perch.minX < perch.maxX - center
        let landingCenter = toLeft ? perch.minX - 25 * unit : perch.maxX + 25 * unit
        let half = CGFloat(Layout.canvasWidth) / 2 * scale
        if quick {
            // gleich von hier aus
            startJump(toX: center + (toLeft ? -50 : 50) * unit - half, toY: dockY, landing: .dock)
        } else {
            let edge = toLeft ? perch.minX + 11 * scale : perch.maxX - 11 * scale
            goal = .jump(toCenter: landingCenter, toY: dockY, landing: .dock)
            walk(to: edge - half, speed: 45 * unit)
        }
    }

    private func startClimbingUp(_ wall: Wall) {
        guard let perch = perch(wall.perchID) else {
            enter(.standing, for: 0.5)
            return
        }
        let wallX = wallX(wall, perch)
        let climbX = climbX(wallX: wallX, wallOnRight: wall.wallOnRight)
        if perch.bottom > dockY + 6 * unit {
            // Fenster endet etwas über dem Dock: hinspringen und festkrallen
            startJump(toX: climbX, toY: perch.bottom + 2 * unit, landing: .wall(wall))
        } else {
            self.wall = wall
            perchID = nil
            x = climbX
            enter(.climbingUp)
        }
    }

    private func startClimbingDown(_ wall: Wall) {
        guard let perch = perch(wall.perchID) else {
            startFalling()
            return
        }
        self.wall = wall
        perchID = nil
        x = climbX(wallX: wallX(wall, perch), wallOnRight: wall.wallOnRight)
        y = min(y, perch.y - 24 * scale)
        enter(.climbingDown)
    }

    private func updateClimb(_ dt: Double) {
        guard let wall, let perch = perch(wall.perchID) else {
            startFalling()
            return
        }
        let wallX = wallX(wall, perch)
        x = climbX(wallX: wallX, wallOnRight: wall.wallOnRight)
        let step = 45 * unit * CGFloat(dt)
        if phase == .climbingUp {
            y += step
            if y + 24 * scale >= perch.y {
                // oben angekommen: hochziehen und aufs Fenster treten
                self.wall = nil
                perchID = perch.id
                y = perch.y
                facingRight = wall.wallOnRight
                let edge = wall.wallOnRight ? perch.left + 11 * scale : perch.right - 11 * scale
                x = clampX(edge - CGFloat(Layout.canvasWidth) / 2 * scale)
                enter(.standing, for: .random(in: 0.5...1.2))
            }
        } else {
            y -= step
            let bottom = max(perch.bottom, dockY)
            if y <= bottom {
                self.wall = nil
                if bottom > dockY + 4 * unit {
                    startFalling()
                } else {
                    y = dockY
                    facingRight = !wall.wallOnRight
                    let foot = wall.wallOnRight ? wallX - 12 * scale : wallX + 12 * scale
                    x = foot - CGFloat(Layout.canvasWidth) / 2 * scale
                    enter(.standing, for: .random(in: 0.4...1.0))
                }
            }
        }
    }

    private func startJump(toX: CGFloat, toY: CGFloat, landing: Landing, arc customArc: CGFloat? = nil) {
        let dx = toX - x, dy = toY - y
        let distance = hypot(dx, dy)
        jump = Jump(fromX: x, fromY: y, toX: toX, toY: toY,
                    duration: min(0.9, 0.35 + Double(distance / (900 * unit))),
                    arc: customArc ?? max(0, dy) / 2 + 25 * unit, landing: landing)
        if abs(dx) > 2 { facingRight = dx > 0 }
        perchID = nil
        wall = nil
        enter(.jumping)
    }

    private func updateJump() {
        guard let jump else {
            startFalling()
            return
        }
        let t = CGFloat(min(phaseTime / jump.duration, 1))
        x = jump.fromX + (jump.toX - jump.fromX) * t
        y = jump.fromY + (jump.toY - jump.fromY) * t + jump.arc * 4 * t * (1 - t)
        guard t >= 1 else { return }
        self.jump = nil
        switch jump.landing {
        case .basket:
            enter(.away, for: .infinity)
        case .dock:
            y = dockY
            if let next = afterHop {
                // aus dem Körbchen heraus: weiter mit dem, was anstand
                afterHop = nil
                next()
            } else if pounceFollowUp {
                // gelandet auf dem Mauszeiger: mit der Tatze draufhauen
                pounceFollowUp = false
                enter(.batting, for: 0.4)
            } else {
                enter(.standing, for: .random(in: 0.3...0.7))
            }
        case .perch(let id):
            if let perch = perch(id), center >= perch.minX, center <= perch.maxX {
                perchID = id
                y = perch.y
                x = clampX(x)
                enter(.standing, for: .random(in: 0.4...0.9))
            } else {
                startFalling()
            }
        case .wall(let wall):
            if perch(wall.perchID) != nil {
                self.wall = wall
                enter(.climbingUp)
            } else {
                startFalling()
            }
        }
    }

    private func startFalling() {
        perchID = nil
        wall = nil
        jump = nil
        fallSpeed = 0
        enter(.falling)
    }

    private func updateFall(_ dt: Double) {
        fallSpeed += 1500 * unit * CGFloat(dt)
        let newY = y - fallSpeed * CGFloat(dt)
        // Landet auf der höchsten Fläche, die sie beim Fallen passiert
        let landingPerch = perches
            .filter { $0.y <= y && $0.y >= newY && center >= $0.minX + 6 * scale && center <= $0.maxX - 6 * scale }
            .max { $0.y < $1.y }
        if let landingPerch {
            perchID = landingPerch.id
            y = landingPerch.y
            enter(.standing, for: .random(in: 0.4...0.8))
        } else if newY <= dockY {
            y = dockY
            x = min(max(x, minX), maxX)
            enter(.standing, for: .random(in: 0.4...0.8))
        } else {
            y = newY
        }
    }

    // MARK: Spielen

    private func updateChase(_ dt: Double) {
        if let bird {
            updateBirdChase(dt, bird)
            return
        }
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

    /// Übung vormachen; beim Gehen ein paar Schritte hin und her um die Mitte
    private func updateExercise(_ dt: Double) {
        guard let exercise else {
            enter(.standing, for: 0.4)
            return
        }
        guard exercise == .walk else { return }
        let middle = (minX + maxX) / 2
        let target = middle + exerciseDirection * 45 * unit
        let step = 35 * unit * CGFloat(dt)
        if abs(target - x) <= step {
            exerciseDirection = -exerciseDirection
        } else {
            facingRight = target > x
            x += target > x ? step : -step
        }
    }

    /// Dem Vogel hinterher: unter ihn laufen, nach ihm schlagen, wenn er tief fliegt, und springen,
    /// wenn er etwas höher ist. Fliegt er zu hoch, wartet sie darunter.
    private func updateBirdChase(_ dt: Double, _ bird: Bird) {
        guard !bird.isLeaving else {
            enter(.standing, for: 0.5)
            return
        }
        pounceCooldown -= dt
        if abs(bird.x - center) > 4 * scale { facingRight = bird.x > center }
        let dir: CGFloat = facingRight ? 1 : -1
        let desired = clampX(bird.x - CGFloat(Layout.canvasWidth) / 2 * scale - dir * 6 * scale)
        let distance = desired - x
        let height = bird.y - dockY
        if abs(distance) < 10 * scale, pounceCooldown <= 0 {
            if height < 30 * unit {
                pounceCooldown = .random(in: 0.6...1.2)
                bird.dodge(after: 0.15)
                enter(.batting, for: 0.35)
                return
            }
            if height < 150 * unit {
                pounceCooldown = .random(in: 1.6...3.0)
                bird.dodge(after: 0.25)
                pounceFollowUp = true
                startJump(toX: clampX(x + dir * 14 * scale), toY: dockY, landing: .dock,
                          arc: max(25 * unit, height - 6 * scale))
                return
            }
        }
        let chaseSpeed = (abs(distance) > 90 * unit ? 130 : 70) * unit
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

    /// Streck-Ablauf: vorne absenken → tief strecken und wippen → aufrichten → Hinterbein nach hinten.
    private func stretchFrame() -> Sprite {
        let t = phaseTime, end = phaseDuration
        switch t {
        case ..<0.35: return Frames.stretchHalf
        case ..<(end - 0.8):
            return Int((t - 0.35) / 0.42) % 2 == 0 ? Frames.stretchBowA : Frames.stretchBowB
        case ..<(end - 0.5): return Frames.stretchHalf
        default: return Frames.stretchHind
        }
    }

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
            look.sprite = stretchFrame()
        case .slowBlinking:
            // Langes, langsames Blinzeln in der Mitte – Katzensprache für „ich mag dich“
            let t = phaseTime / phaseDuration
            look.sprite = t > 0.35 && t < 0.62 ? Frames.sitBlink : Frames.sit
        case .wriggling:
            // Hinlegen, rekeln (auf dem Rücken, Pfoten zappeln), wieder auf den Bauch
            if phaseTime < 0.5 || phaseTime > phaseDuration - 0.5 {
                look.sprite = Frames.lieBlink
            } else {
                look.sprite = alternate(Frames.rollA, Frames.rollB, every: 0.3)
            }
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
        case .drinking:
            look.sprite = alternate(Frames.drinkA, Frames.drinkB, every: 0.22)
        case .gazing:
            // Von hinten, mitten auf dem Fensterbrett; der Schwanz zuckt ab und zu
            look.sprite = animTime.truncatingRemainder(dividingBy: 5) > 4.2 ? Frames.sitBackB : Frames.sitBackA
            look.facingRight = true
            look.drawX = (Layout.canvasWidth - look.sprite.width) / 2
            look.hop = LookoutArt.sillTop
        case .batting:
            look.sprite = Frames.bat
        case .climbingUp:
            // Bild zeigt Pfoten rechts – gespiegelt, wenn die Wand links ist
            look.sprite = alternate(Frames.climbUpA, Frames.climbUpB, every: 0.16)
            look.facingRight = wall?.wallOnRight ?? true
            look.drawX = Layout.climbX
        case .climbingDown:
            // Bild zeigt Pfoten links – gespiegelt, wenn die Wand rechts ist
            look.sprite = alternate(Frames.climbDownA, Frames.climbDownB, every: 0.16)
            look.facingRight = !(wall?.wallOnRight ?? false)
            look.drawX = Layout.climbX
        case .enteringBasket:
            let t = phaseTime
            switch t {
            case ..<0.6: look.sprite = Frames.stand                       // schrumpft auf Körbchengröße
            case ..<1.0: look.sprite = Frames.bat                         // Pfote tastet ins Körbchen
            case ..<1.4: look.sprite = Frames.walkB                       // hineinsteigen
            case ..<2.2:                                                  // im Kreis drehen
                look.sprite = Int(t / 0.13) % 4 == 0 ? Frames.walkA : Frames.walkB
                look.facingRight = Int((t - 1.4) / 0.27) % 2 == 0 ? facingRight : !facingRight
            case ..<2.55: look.sprite = Frames.sit; look.facingRight = true   // so wie im Dock-Symbol
            case ..<2.85: look.sprite = Frames.lie; look.facingRight = true
            default: look.sprite = Frames.sleepA; look.facingRight = true
            }
        case .leavingBasket:
            let t = phaseTime
            switch t {
            case ..<0.3: look.sprite = Frames.lie; look.facingRight = true // klein im Körbchen aufwachen, wie im Symbol
            case ..<0.55: look.sprite = Frames.sit
            case ..<0.75: look.sprite = Frames.stand
            case ..<1.2: look.sprite = Frames.walkA                       // hinaus aufs Dock hüpfen
            default: look.sprite = Frames.stand                           // und dort wieder wachsen
            }
        case .reachingDown:
            look.sprite = Frames.bat         // Vorderpfote tastet nach unten
        case .reachingUp:
            look.sprite = Frames.crouch      // ducken, gleich geht's hinauf
        case .exercising:
            let t = phaseTime
            switch exercise {
            case .stretchUp:
                look.sprite = t.truncatingRemainder(dividingBy: 3.2) < 1.0 ? Frames.stand : Frames.exerciseUp
            case .arch:
                look.sprite = t.truncatingRemainder(dividingBy: 3.0) < 1.2 ? Frames.stand : Frames.exerciseArch
            case .lookAround:
                look.sprite = blinking ? Frames.sitBlink : Frames.sit
                look.facingRight = Int(t / 1.8) % 2 == 0
            case .breathe:
                look.sprite = t.truncatingRemainder(dividingBy: 4) < 2 ? Frames.sitBreathIn : Frames.sitBlink
            case .bow:
                look.sprite = alternate(Frames.stretchBowA, Frames.stretchBowB, every: 0.9)
            case .blink:
                look.sprite = t.truncatingRemainder(dividingBy: 1.6) < 0.3 ? Frames.sitBlink : Frames.sit
            case .walk:
                let cycle = [Frames.walkA, Frames.stand, Frames.walkB, Frames.stand]
                look.sprite = cycle[Int(animTime / 0.16) % cycle.count]
            case nil:
                look.sprite = Frames.stand
            }
        case .stalking:
            look.sprite = Frames.crouch
            // vor dem Sprung wackelt das Hinterteil
            if stalkWiggle > 0 { look.hop = Int(animTime / 0.09) % 2 }
        case .jumping, .falling, .away:
            look.sprite = Frames.walkA
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
    /// Verkleidung auf dem Kopf (Weihnachtsmütze, Partyhut, Zylinder …) oder nil
    var accessory: Sprite? {
        didSet { if accessory !== oldValue { needsDisplay = true } }
    }
    /// So viele Pixel tiefer als sonst sitzt die Verkleidung (z. B. Schlafmaske auf der Stirn)
    var accessoryDrop = 0 {
        didSet { if accessoryDrop != oldValue { needsDisplay = true } }
    }
    /// Etwas am Hals (Fliege) oder nil
    var collar: Sprite? {
        didSet { if collar !== oldValue { needsDisplay = true } }
    }
    var onClick: (() -> Void)?
    /// Vorderer Rand des Körbchens (Lage in Bildpixeln) – beim Hinein- und Heraussteigen
    var basketFront: CGPoint? {
        didSet { if basketFront != oldValue { needsDisplay = true } }
    }

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
        let sx = px - look.drawX
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
        look.sprite.draw(in: ctx, x: CGFloat(look.drawX), y: CGFloat(look.hop), scale: scale,
                         colors: coat.colors)
        // Hut zwischen die Ohren setzen (nur wenn der Kopf aufrecht ist)
        if let accessory, let ears = look.sprite.earAnchor {
            let x = look.drawX + ears.center - accessory.width / 2
            let y = look.hop + look.sprite.height - 1 - ears.row - accessoryDrop
            accessory.draw(in: ctx, x: CGFloat(x), y: CGFloat(y), scale: scale, colors: Frames.accessoryColors)
        }
        // Fliege direkt unter dem Maul (oberste Zeile an der Ankerstelle)
        if let collar, let neck = look.sprite.collarAnchor {
            let x = look.drawX + neck.center - collar.width / 2
            let y = look.hop + look.sprite.height - neck.row - collar.height
            collar.draw(in: ctx, x: CGFloat(x), y: CGFloat(y), scale: scale, colors: Frames.accessoryColors)
        }
        ctx.restoreGState()
        if let front = basketFront {
            BasketArt.shared.front.draw(in: ctx, x: front.x, y: front.y, scale: scale, colors: BasketArt.colors)
        }
    }
}
