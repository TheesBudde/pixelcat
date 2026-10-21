import AppKit

/// Randloses, durchsichtiges Fenster, das über allen anderen schwebt und auf allen Spaces bleibt.
@MainActor
func makeOverlayPanel() -> NSPanel {
    let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    return panel
}

// MARK: - Napf und Knäuel

/// Zeigt ein einzelnes Pixelbild (Napf oder Knäuel) in einem eigenen kleinen Fenster.
@MainActor
final class PropView: NSView {
    var sprite: Sprite? {
        didSet { if sprite !== oldValue { needsDisplay = true } }
    }
    var scale: CGFloat = 3 {
        didSet { needsDisplay = true }
    }
    var onMouseDown: ((NSPoint) -> Void)?
    var onMouseDragged: ((NSPoint) -> Void)?
    var onMouseUp: ((NSPoint) -> Void)?

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var spriteOrigin: CGPoint {
        guard let sprite else { return .zero }
        let columns = Int(bounds.width / scale)
        return CGPoint(x: CGFloat((columns - sprite.width) / 2), y: 0)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard onMouseDown != nil, let sprite else { return nil }
        let p = convert(point, from: superview)
        let col = Int(floor(p.x / scale - spriteOrigin.x))
        let row = sprite.height - 1 - Int(floor(p.y / scale))
        for dy in -1...1 {
            for dx in -1...1 where sprite.pixel(col + dx, row + dy) != "." {
                return self
            }
        }
        return nil
    }

    override func mouseDown(with event: NSEvent) { onMouseDown?(NSEvent.mouseLocation) }
    override func mouseDragged(with event: NSEvent) { onMouseDragged?(NSEvent.mouseLocation) }
    override func mouseUp(with event: NSEvent) { onMouseUp?(NSEvent.mouseLocation) }

    override func draw(_ dirtyRect: NSRect) {
        guard let sprite, let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        ctx.setShouldAntialias(false)
        sprite.draw(in: ctx, x: spriteOrigin.x, y: spriteOrigin.y, scale: scale, colors: PropColors.colors)
    }
}

@MainActor
final class PropWindow {
    let panel = makeOverlayPanel()
    let view = PropView()
    private let columns: Int
    private let rows: Int

    var scale: CGFloat {
        didSet { resize() }
    }

    init(columns: Int, rows: Int, scale: CGFloat) {
        self.columns = columns
        self.rows = rows
        self.scale = scale
        panel.contentView = view
        resize()
    }

    private func resize() {
        let size = NSSize(width: CGFloat(columns) * scale, height: CGFloat(rows) * scale)
        panel.setContentSize(size)
        view.frame = NSRect(origin: .zero, size: size)
        view.scale = scale
    }

    func place(centerX: CGFloat, bottom: CGFloat) {
        panel.setFrameOrigin(NSPoint(x: (centerX - panel.frame.width / 2).rounded(), y: bottom.rounded()))
    }
}

// MARK: - Pomodoro

struct Pomodoro {
    enum Stage { case focus, rest }

    static let focusLength: TimeInterval = 25 * 60
    static let restLength: TimeInterval = 5 * 60

    var stage: Stage
    var ends: Date

    static func startFocus(at now: Date) -> Pomodoro {
        Pomodoro(stage: .focus, ends: now.addingTimeInterval(focusLength))
    }

    /// Text für die Menüleiste, z. B. "24:13" oder "Pause 4:12".
    func label(at now: Date) -> String {
        let left = max(0, Int(ends.timeIntervalSince(now).rounded(.up)))
        let time = String(format: "%d:%02d", left / 60, left % 60)
        return stage == .focus ? time : "Pause \(time)"
    }
}

// MARK: - Steuerung

/// Hält alles zusammen: Katze, Napf, Knäuel, Pomodoro und Pausen-Erinnerung.
/// Ein Takt 30-mal pro Sekunde bewegt alles und zeichnet neu.
@MainActor
final class CatController {
    private let panel = makeOverlayPanel()
    private let view = CatView()
    private let brain = CatBrain()
    private var timer: Timer?
    private var lastTick = CACurrentMediaTime()
    private var lastMouse = NSEvent.mouseLocation
    /// Wie weit die Maus schon über die Katze gestrichen ist
    private var strokeDistance: CGFloat = 0
    private(set) var isVisible = false

    private var bowl: Bowl?
    private var bowlWindow: PropWindow?
    private var ball: Ball?
    private var ballWindow: PropWindow?
    private var dragOffset = CGPoint.zero
    private var lastDrag: (point: NSPoint, time: CFTimeInterval)?
    private var dragVelocity = CGVector.zero

    private(set) var pomodoro: Pomodoro?
    private var nextReminder = Date.distantFuture
    private var perchRefresh = 0.0
    private var statusText: String?
    /// Meldet Änderungen des Texts neben dem Menüleisten-Symbol (nil = kein Text).
    var onStatusChange: ((String?) -> Void)?

    var scale: CGFloat {
        didSet { applyScale() }
    }

    var coat: Coat {
        didSet { view.coat = coat }
    }

    var breakReminders = false {
        didSet { if breakReminders != oldValue { scheduleReminder() } }
    }

    /// Kletter-Modus: Die Katze darf auf offene Fenster.
    var climbing: Bool {
        get { brain.climbingEnabled }
        set {
            if newValue { brain.setPerches(findPerches()) }
            brain.climbingEnabled = newValue
        }
    }

    /// Miauen bei Pomodoro-Wechsel und Pausen-Erinnerung
    var sounds = true

    var isPlaying: Bool { ball != nil }
    var isInFocus: Bool { pomodoro?.stage == .focus }

    /// Zum Vorführen: immer Nachmittag (aktive Katze) und viel Klettern.
    func enableDemo() {
        let afternoon = Calendar.current.date(bySettingHour: 15, minute: 0, second: 0, of: Date()) ?? Date()
        brain.clock = { afternoon }
        brain.adventurousness = 2.2
    }

    init(scale: CGFloat, coat: Coat) {
        self.scale = scale
        self.coat = coat
        view.coat = coat
        panel.contentView = view
        view.onClick = { [weak self] in self?.brain.startle() }
        applyScale()

        // Der Takt läuft immer, damit der Pomodoro auch bei ausgeblendeter Katze weiterzählt.
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: Ein- und Ausblenden

    func show() {
        guard !isVisible else { return }
        isVisible = true
        updateBounds()
        if brain.x == 0 {
            brain.x = .random(in: brain.minX...max(brain.minX, brain.maxX))
        }
        tick()
        bowlWindow?.panel.orderFrontRegardless()
        panel.orderFrontRegardless()
        ballWindow?.panel.orderFrontRegardless()
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        panel.orderOut(nil)
        bowlWindow?.panel.orderOut(nil)
        ballWindow?.panel.orderOut(nil)
    }

    // MARK: Menüaktionen

    func startle() { brain.startle() }
    func goToSleep() { brain.goToSleep() }

    func feed() {
        guard let frame = screen?.frame, !isInFocus else { return }
        if let bowl, bowl.food > 0 { return }
        // Irgendwo ins mittlere Drittel bis Fünftel, nicht direkt unter die Katze
        var x = frame.minX
        for _ in 0..<10 {
            x = .random(in: frame.minX + frame.width * 0.15...frame.maxX - frame.width * 0.15)
            if abs(x - catCenter) > 150 { break }
        }
        removeBowl()
        let bowl = Bowl(x: x)
        let window = PropWindow(columns: 14, rows: 6, scale: scale)
        self.bowl = bowl
        bowlWindow = window
        brain.bowl = bowl
        if isVisible {
            window.panel.orderFrontRegardless()
            panel.orderFrontRegardless()
        }
        brain.noticeSomething()
    }

    func setPlaying(_ playing: Bool) {
        if playing {
            guard ball == nil, !isInFocus, let frame = screen?.frame else { return }
            // Das Knäuel kommt von oben hereingefallen, ein Stück neben der Katze
            let side: CGFloat = catCenter < frame.midX ? 1 : -1
            let ball = Ball(x: min(max(catCenter + side * 160 * scale / 3, frame.minX + 40), frame.maxX - 40))
            ball.y = 120 * scale / 3
            let window = PropWindow(columns: 9, rows: 9, scale: scale)
            window.view.onMouseDown = { [weak self] p in self?.grabBall(at: p) }
            window.view.onMouseDragged = { [weak self] p in self?.dragBall(to: p) }
            window.view.onMouseUp = { [weak self] _ in self?.releaseBall() }
            self.ball = ball
            ballWindow = window
            brain.ball = ball
            if isVisible { window.panel.orderFrontRegardless() }
            brain.noticeSomething()
        } else {
            ballWindow?.panel.orderOut(nil)
            ballWindow = nil
            ball = nil
            brain.ball = nil
        }
    }

    func startPomodoro() {
        pomodoro = .startFocus(at: Date())
        setPlaying(false)
        removeBowl()
        brain.mode = .focus
        updateStatusText()
    }

    func stopPomodoro() {
        pomodoro = nil
        brain.mode = .normal
        scheduleReminder()
        updateStatusText()
    }

    // MARK: Knäuel ziehen und werfen

    private func grabBall(at point: NSPoint) {
        guard let ball else { return }
        ball.isHeld = true
        dragOffset = CGPoint(x: ball.x - point.x, y: ground + ball.y - point.y)
        lastDrag = (point, CACurrentMediaTime())
        dragVelocity = .zero
    }

    private func dragBall(to point: NSPoint) {
        guard let ball else { return }
        let now = CACurrentMediaTime()
        if let last = lastDrag, now > last.time {
            let dt = CGFloat(now - last.time)
            // geglättet, damit der Wurf nicht von einem einzelnen Ruckler abhängt
            dragVelocity.dx = dragVelocity.dx * 0.5 + (point.x - last.point.x) / dt * 0.5
            dragVelocity.dy = dragVelocity.dy * 0.5 + (point.y - last.point.y) / dt * 0.5
        }
        lastDrag = (point, now)
        ball.x = point.x + dragOffset.x
        ball.y = max(0, point.y + dragOffset.y - ground)
    }

    private func releaseBall() {
        guard let ball else { return }
        let limit = 1400 * scale / 3
        ball.isHeld = false
        ball.vx = max(-limit, min(limit, dragVelocity.dx))
        ball.vy = max(-limit, min(limit, dragVelocity.dy))
        lastDrag = nil
    }

    // MARK: Takt

    /// Der Hauptbildschirm (der mit der Menüleiste).
    private var screen: NSScreen? { NSScreen.screens.first }
    private var ground: CGFloat { screen?.visibleFrame.minY ?? 0 }
    private var catCenter: CGFloat { brain.x + CGFloat(Layout.canvasWidth) / 2 * scale }

    private func applyScale() {
        let size = NSSize(width: CGFloat(Layout.canvasWidth) * scale,
                          height: CGFloat(Layout.canvasHeight) * scale)
        panel.setContentSize(size)
        view.frame = NSRect(origin: .zero, size: size)
        view.scale = scale
        brain.scale = scale
        bowlWindow?.scale = scale
        ballWindow?.scale = scale
        updateBounds()
    }

    private func updateBounds() {
        guard let frame = screen?.frame else { return }
        brain.minX = frame.minX - CGFloat(Layout.margin) * scale
        brain.maxX = frame.maxX - CGFloat(Layout.canvasWidth - Layout.margin) * scale
    }

    private func removeBowl() {
        bowlWindow?.panel.orderOut(nil)
        bowlWindow = nil
        bowl = nil
        brain.bowl = nil
    }

    private func scheduleReminder() {
        nextReminder = breakReminders ? Date().addingTimeInterval(.random(in: 45...55) * 60) : .distantFuture
    }

    /// Streicheln: Die Maus bewegt sich über der Katze, ohne zu klicken.
    /// Die Mausposition wird einfach abgefragt – dafür braucht es keine Sonderrechte.
    private func checkStroking() {
        let mouse = NSEvent.mouseLocation
        defer { lastMouse = mouse }
        let origin = panel.frame.origin
        let local = NSPoint(x: mouse.x - origin.x, y: mouse.y - origin.y)
        guard isVisible, NSEvent.pressedMouseButtons == 0, view.isCat(at: local) else {
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

    /// Sichtbare Oberkanten der offenen Fenster auf dem Hauptbildschirm.
    /// Die Fensterpositionen liefert macOS ohne Sonderrechte (nur Titel wären geschützt).
    /// Ist ein Fenster im Vollbild oder in Split View, gibt es nichts zum Klettern.
    private func findPerches() -> [Perch] {
        guard let screen,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        let frame = screen.frame
        let ownPID = ProcessInfo.processInfo.processIdentifier

        // von vorne nach hinten, in Bildschirmkoordinaten (y von unten)
        var windows: [(id: Int, rect: CGRect)] = []
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? pid_t) != ownPID,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.1,
                  let id = info[kCGWindowNumber as String] as? Int,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo)
            else { continue }
            let rect = CGRect(x: bounds.minX, y: frame.maxY - bounds.maxY, width: bounds.width, height: bounds.height)
            guard rect.width >= 120, rect.height >= 80, rect.intersects(frame) else { continue }
            if rect.height >= frame.height - 2 { return [] } // Vollbild oder Split View
            windows.append((id, rect))
        }
        return Self.perches(on: windows, frame: frame, visible: screen.visibleFrame, scale: scale)
    }

    /// Die Fenster kommen von vorne nach hinten sortiert.
    static func perches(on windows: [(id: Int, rect: CGRect)], frame: CGRect, visible: CGRect,
                        scale: CGFloat) -> [Perch] {
        var perches: [Perch] = []
        for (index, window) in windows.enumerated() {
            let top = window.rect.maxY
            guard top < visible.maxY - 18 * scale, top > visible.minY + 20 * scale else { continue }
            // Was von der Oberkante nicht von Fenstern weiter vorne verdeckt ist
            var segments = [(max(window.rect.minX, frame.minX), min(window.rect.maxX, frame.maxX))]
            for front in windows[..<index]
            where front.rect.minY <= top + 8 * scale && front.rect.maxY >= top {
                segments = segments.flatMap { segment -> [(CGFloat, CGFloat)] in
                    let (a, b) = segment
                    guard front.rect.maxX > a, front.rect.minX < b else { return [segment] }
                    return [(a, front.rect.minX), (front.rect.maxX, b)].filter { $0.1 - $0.0 > 1 }
                }
            }
            guard let longest = segments.max(by: { $0.1 - $0.0 < $1.1 - $1.0 }),
                  longest.1 - longest.0 >= 30 * scale
            else { continue }
            perches.append(Perch(id: window.id, y: top, minX: longest.0, maxX: longest.1,
                                 left: window.rect.minX, right: window.rect.maxX, bottom: window.rect.minY))
        }
        return perches
    }

    private func updatePomodoro(now: Date) {
        guard var pomodoro, now >= pomodoro.ends else { return }
        switch pomodoro.stage {
        case .focus:
            // Fokuszeit vorbei: aufwachen, strecken, Pause machen
            pomodoro = Pomodoro(stage: .rest, ends: now.addingTimeInterval(Pomodoro.restLength))
            brain.mode = .focusBreak
            if sounds { Meow.play(.breakStarts) }
        case .rest:
            pomodoro = .startFocus(at: now)
            setPlaying(false)
            removeBowl()
            brain.mode = .focus
            if sounds { Meow.play(.backToWork) }
        }
        self.pomodoro = pomodoro
    }

    private func updateStatusText() {
        let text = pomodoro?.label(at: Date())
        if text != statusText {
            statusText = text
            onStatusChange?(text)
        }
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastTick, 0.1)
        lastTick = now
        let date = Date()

        updateBounds()
        brain.dockY = ground
        perchRefresh -= dt
        if perchRefresh <= 0, brain.climbingEnabled || brain.isOnWindow {
            perchRefresh = 0.2
            brain.setPerches(findPerches())
        }
        updatePomodoro(now: date)
        updateStatusText()
        if pomodoro == nil, date >= nextReminder {
            brain.remindToTakeBreak()
            if sounds { Meow.play(.reminder) }
            scheduleReminder()
        }

        checkStroking()
        brain.update(dt: dt)

        if let ball, let frame = screen?.visibleFrame {
            let radius = 4 * scale
            ball.update(dt: dt, minX: frame.minX + radius, maxX: frame.maxX - radius,
                        maxY: frame.height - 9 * scale, unit: scale / 3)
        }
        if let bowl, bowl.food <= 0, brain.phase != .eating {
            bowl.emptyFor += dt
            if bowl.emptyFor > 12 { removeBowl() }
        }

        guard isVisible else { return }

        // visibleFrame endet unten an der Oberkante des Docks – genau da läuft die Katze
        panel.setFrameOrigin(NSPoint(x: brain.x.rounded(), y: brain.y.rounded()))
        let look = brain.look
        if look != view.look { view.look = look }

        if let bowl, let bowlWindow {
            bowlWindow.view.sprite = bowl.food > 0.5 ? Frames.bowlFull
                : bowl.food > 0 ? Frames.bowlHalf : Frames.bowlEmpty
            bowlWindow.place(centerX: bowl.x, bottom: ground)
        }
        if let ball, let ballWindow {
            ballWindow.view.sprite = Int(ball.rolled / (3 * scale)) % 2 == 0 ? Frames.yarnA : Frames.yarnB
            ballWindow.place(centerX: ball.x, bottom: ground + ball.y)
        }
    }
}
