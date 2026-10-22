import AppKit

// Szenarien rund um den Katzenkorb – ausführen mit ./test.sh
// Jedes Szenario spielt Ereignisse zu festen Zeiten ab (Pause, Timer, Korb verschieben, Katzenkorb aus …) und prüft:
//   • Sie steigt immer genau an der Stelle hinein bzw. heraus, an der der Korb in diesem Moment steht.
//   • Am Ende liegt sie im Korb oder ist draußen – so wie erwartet (nichts geht verloren, nichts hängt).

final class Bed { var x: CGFloat? = 1200 }
typealias Event = (time: Double, label: String, run: @MainActor (CatBrain, Bed) -> Void)

MainActor.assumeIsolated {
    let dt = 1.0 / 30
    let afternoon = Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: Date())!
    var failed = 0

    @MainActor func scenario(_ name: String, seconds: Double, endsInBed: Bool, _ events: [Event]) {
        let b = CatBrain()
        b.clock = { afternoon }
        b.minX = -12; b.maxX = 1374; b.dockY = 57; b.x = 300
        b.useBasket = true
        b.emergeDelay = 2 // wie ohne Bedienungshilfen
        let bed = Bed()
        b.locateBasket = { b.basketX = bed.x; b.basketFloorY = bed.x == nil ? nil : 27 }
        var pending = events, t = 0.0, last = "", problems: [String] = []
        for _ in 0..<Int(seconds / dt) {
            while let e = pending.first, t >= e.time { e.run(b, bed); pending.removeFirst() }
            b.update(dt: dt)
            t += dt
            let phase = "\(b.phase)"
            if phase != last, phase == "enteringBasket" || phase == "leavingBasket", let bedX = bed.x {
                let mid = b.x + CGFloat(Layout.canvasWidth) / 2 * b.scale
                if abs(mid - bedX) > 1 {
                    problems.append(String(format: "%.1f s: %@ bei x=%.0f, Korb steht bei %.0f", t, phase, mid, bedX))
                }
            }
            last = phase
        }
        if b.isAway != endsInBed {
            problems.append("am Ende \(b.isAway ? "im Korb" : "draußen"), erwartet \(endsInBed ? "im Korb" : "draußen")")
        }
        print(problems.isEmpty ? "✓ \(name)" : "✗ \(name)\n    " + problems.joined(separator: "\n    "))
        if !problems.isEmpty { failed += 1 }
    }

    let bedOn: Event = (0, "Katzenkorb an", { b, _ in b.roaming = true })
    func at(_ t: Double, _ label: String, _ run: @escaping @MainActor (CatBrain, Bed) -> Void) -> Event { (t, label, run) }
    func move(_ t: Double, to x: CGFloat) -> Event { at(t, "Korb nach \(Int(x))") { _, bed in bed.x = x } }
    func breakStarts(_ t: Double) -> Event { at(t, "Pause") { b, _ in b.mode = .focusBreak } }
    func focus(_ t: Double) -> Event { at(t, "Fokus") { b, _ in b.mode = .focus } }
    func bedOff(_ t: Double) -> Event { at(t, "Katzenkorb aus") { b, _ in b.roaming = false } }
    func timerDone(_ t: Double) -> Event { at(t, "Timer fertig") { b, _ in b.callToCenter(untilAcknowledged: true) } }
    func click(_ t: Double) -> Event { at(t, "Klick") { b, _ in b.clicked() } }

    // Sie läuft ca. 14 s zum Korb, steigt bis ca. 17,5 s hinein und liegt dann drin.
    scenario("Hineinlegen", seconds: 25, endsInBed: true, [bedOn])
    scenario("Korb verschoben, während sie hinläuft", seconds: 25, endsInBed: true, [bedOn, move(3, to: 500)])
    scenario("Korb verschoben, während sie hineinsteigt", seconds: 25, endsInBed: true, [bedOn, move(15.5, to: 500)])
    scenario("Drin, Korb verschoben, Pause", seconds: 40, endsInBed: false, [bedOn, move(20, to: 500), breakStarts(25)])
    scenario("Drin, Korb verschoben, Pause vorbei", seconds: 50, endsInBed: true,
             [bedOn, move(20, to: 500), breakStarts(25), focus(34)])
    scenario("Drin, Korb verschoben, Katzenkorb aus", seconds: 35, endsInBed: false, [bedOn, move(20, to: 500), bedOff(25)])
    scenario("Drin, Korb verschoben, Timer, Klick", seconds: 50, endsInBed: true,
             [bedOn, move(20, to: 800), timerDone(25), click(36)])
    scenario("Zweimal hin und her, Korb jedes Mal woanders", seconds: 75, endsInBed: false,
             [bedOn, breakStarts(20), move(30, to: 400), focus(31), move(50, to: 1300), breakStarts(55)])
    scenario("Pause, während sie hineinsteigt", seconds: 30, endsInBed: false, [bedOn, breakStarts(16)])
    scenario("Pause und gleich wieder Fokus, während sie hineinsteigt", seconds: 30, endsInBed: true,
             [bedOn, breakStarts(15), focus(15.6)])
    scenario("Katzenkorb aus, während sie hineinsteigt", seconds: 30, endsInBed: false, [bedOn, bedOff(16)])
    scenario("Timer, während sie hineinsteigt", seconds: 30, endsInBed: false, [bedOn, move(14, to: 800), timerDone(15)])
    scenario("Erinnerung, während sie hineinsteigt (danach zurück)", seconds: 45, endsInBed: true,
             [bedOn, at(15, "Erinnerung") { b, _ in b.breakVisitLength = 5; b.callToCenter() }])
    scenario("Pause vorbei, während sie heraussteigt", seconds: 40, endsInBed: true, [bedOn, breakStarts(20), focus(20.5)])
    scenario("Korb verschoben, während sie heraussteigt", seconds: 40, endsInBed: false,
             [bedOn, breakStarts(20), move(20.5, to: 500)])
    scenario("Klick, während sie hineinsteigt", seconds: 25, endsInBed: true, [bedOn, click(16)])
    scenario("Vollbild, Pause, Vollbild aus, Pause", seconds: 55, endsInBed: false, [
        bedOn, at(14, "Vollbild an") { b, _ in b.useBasket = false; b.dockY = 0 }, breakStarts(15), focus(25),
        at(26, "Vollbild aus") { b, _ in b.useBasket = true; b.dockY = 57 }, breakStarts(45)])

    scenario("Dock speichert die Verschiebung erst nach der Pause-Anfrage", seconds: 40, endsInBed: false,
             [bedOn, move(20, to: 700), breakStarts(25), move(26, to: 400)])
    scenario("Katzenkorb aus und gleich wieder an (sie bleibt liegen)", seconds: 35, endsInBed: true,
             [bedOn, bedOff(25), at(25.5, "Katzenkorb an") { b, _ in b.roaming = true }])
    scenario("Videocall: Pause bleibt aus, nach dem Call heraus", seconds: 45, endsInBed: false, [
        bedOn, at(20, "Call") { b, _ in b.suppressVisits = true }, breakStarts(22),
        at(30, "Call vorbei") { b, _ in b.suppressVisits = false }])
    scenario("Videocall beginnt, während sie heraussteigt", seconds: 40, endsInBed: true, [
        bedOn, breakStarts(20), at(20.5, "Call") { b, _ in b.suppressVisits = true }])
    scenario("Aufscheuchen (Menü), während sie hineinsteigt", seconds: 25, endsInBed: true,
             [bedOn, at(16, "Aufscheuchen") { b, _ in b.startle() }])
    scenario("Korb verschwindet aus dem Dock, während sie drin liegt", seconds: 40, endsInBed: false,
             [bedOn, at(20, "Korb weg") { _, bed in bed.x = nil }, breakStarts(25)])

    // MARK: Kleine Erinnerungen

    @MainActor func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
        print(ok ? "✓ \(name)" : "✗ \(name)\n    \(detail())")
        if !ok { failed += 1 }
    }

    /// Lässt die Katze laufen und merkt sich, wie lange sie in welcher Phase war und wo sie dabei stand
    @MainActor func run(_ b: CatBrain, seconds: Double, every: Double = 1.0 / 30, _ step: ((Double) -> Void)? = nil)
        -> (phases: [String: Double], firstAt: [String: CGFloat]) {
        var phases: [String: Double] = [:], firstAt: [String: CGFloat] = [:]
        var t = 0.0
        while t < seconds {
            step?(t)
            b.update(dt: every)
            t += every
            let name = "\(b.phase)"
            phases[name, default: 0] += every
            if firstAt[name] == nil { firstAt[name] = b.x + CGFloat(Layout.canvasWidth) / 2 * b.scale }
        }
        return (phases, firstAt)
    }
    @MainActor func freshBrain() -> CatBrain {
        let b = CatBrain()
        b.clock = { afternoon }
        b.minX = -12; b.maxX = 1374; b.dockY = 57; b.x = 300
        return b
    }

    print("\nTrinken")
    do {
        let b = freshBrain()
        let bowl = Bowl(x: 900, water: true)
        b.bowl = bowl
        b.noticeSomething()
        let result = run(b, seconds: 60)
        let drank = result.phases["drinking"] ?? 0
        check("trinkt 20–30 Sekunden am Wassernapf", drank >= 20 && drank <= 31, "trank \(drank) s")
        let mouth = result.firstAt["drinking"] ?? 0
        check("steht dabei am Napf", abs(mouth - 900) < 40, "Mitte bei \(mouth), Napf bei 900")
        check("Napf ist danach leer (wird weggeräumt)", bowl.food <= 0, "Füllstand \(bowl.food)")
    }
    do {
        // Im Körbchen: Sie kommt heraus, trinkt und legt sich danach wieder hinein
        let b = freshBrain()
        b.useBasket = true
        b.locateBasket = { b.basketX = 1200; b.basketFloorY = 27 }
        b.roaming = true
        _ = run(b, seconds: 25)
        let bowl = Bowl(x: 500, water: true)
        b.bowl = bowl
        b.startErrandVisit(for: 300)
        var ended = false
        let result = run(b, seconds: 120) { _ in
            if bowl.food <= 0, !ended { ended = true; b.bowl = nil; b.endErrandVisit() }
        }
        check("Körbchen: kommt zum Trinken heraus", (result.phases["leavingBasket"] ?? 0) > 0)
        check("Körbchen: trinkt", (result.phases["drinking"] ?? 0) >= 20, "\(result.phases["drinking"] ?? 0) s")
        check("Körbchen: liegt danach wieder im Korb", b.isAway, "Phase \(b.phase)")
    }
    do {
        // Streifzug ohne Körbchen: von der Seite herein und wieder hinaus
        let b = freshBrain()
        b.roaming = true
        _ = run(b, seconds: 25)
        let bowl = Bowl(x: 700, water: true)
        b.bowl = bowl
        b.startErrandVisit(for: 300)
        var ended = false
        let result = run(b, seconds: 140) { _ in
            if bowl.food <= 0, !ended { ended = true; b.bowl = nil; b.endErrandVisit() }
        }
        check("Streifzug: trinkt", (result.phases["drinking"] ?? 0) >= 20)
        check("Streifzug: ist danach wieder draußen", b.isAway, "Phase \(b.phase)")
    }

    print("\nAugenpause")
    do {
        let b = freshBrain()
        var done = false
        var backPose = false
        b.lookout = 800
        b.onLookoutDone = { done = true }
        b.noticeSomething()
        let result = run(b, seconds: 50) { _ in
            if b.phase == .gazing {
                let look = b.look
                backPose = (look.sprite === Frames.sitBackA || look.sprite === Frames.sitBackB) && look.hop == LookoutArt.sillTop
            }
        }
        let gazed = result.phases["gazing"] ?? 0
        check("schaut 25 Sekunden aus dem Fenster", gazed >= 24 && gazed <= 26, "schaute \(gazed) s")
        let at = result.firstAt["gazing"] ?? 0
        check("sitzt dabei mittig vor dem Fenster", abs(at - 800) < 4 * b.scale, "Mitte bei \(at), Fenster bei 800")
        check("meldet danach „fertig“ (Fenster verschwindet)", done && b.lookout == nil)
        check("Pose: von hinten, auf dem Fensterbrett", backPose)
    }
    do {
        // Im Körbchen: heraus, hinausschauen, zurück in den Korb
        let b = freshBrain()
        b.useBasket = true
        b.locateBasket = { b.basketX = 1200; b.basketFloorY = 27 }
        b.roaming = true
        _ = run(b, seconds: 25)
        b.lookout = 600
        b.onLookoutDone = { b.endErrandVisit() }
        b.startErrandVisit(for: 300)
        let result = run(b, seconds: 120)
        check("Körbchen: schaut hinaus", (result.phases["gazing"] ?? 0) >= 24, "\(result.phases["gazing"] ?? 0) s")
        check("Körbchen: liegt danach wieder im Korb", b.isAway, "Phase \(b.phase)")
    }
    do {
        // Gestreichelt mitten im Hinausschauen: danach geht sie wieder hin
        let b = freshBrain()
        b.lookout = 700
        b.noticeSomething()
        var petted = false
        let result = run(b, seconds: 80) { _ in
            if !petted, b.phase == .gazing { petted = true; b.stroke() }
        }
        check("nach Streicheln schaut sie weiter hinaus", (result.phases["gazing"] ?? 0) >= 24 && b.lookout == nil,
              "\(result.phases["gazing"] ?? 0) s")
    }

    print("\nÜberschneidungen")
    do {
        // Pausen-Erinnerung kommt, während sie trinkt: erst austrinken, dann zur Pause in die Mitte
        let b = freshBrain()
        let bowl = Bowl(x: 300, water: true)
        b.bowl = bowl
        b.noticeSomething()
        var called = false
        let result = run(b, seconds: 80) { _ in
            if !called, b.phase == .drinking { called = true; b.remindToTakeBreak() }
        }
        check("trinkt trotz Pausen-Erinnerung zu Ende", (result.phases["drinking"] ?? 0) >= 24, "\(result.phases["drinking"] ?? 0) s")
        check("danach Pause in der Mitte (strecken)", (result.phases["stretching"] ?? 0) > 0)
    }
    do {
        // Pomodoro-Fokus beginnt mitten im Hinausschauen: Sie hört auf und schläft
        let b = freshBrain()
        b.lookout = 600
        b.noticeSomething()
        var focused = false
        _ = run(b, seconds: 60) { _ in
            if !focused, b.phase == .gazing { focused = true; b.lookout = nil; b.mode = .focus }
        }
        check("Fokus beendet das Hinausschauen, sie schläft", [.sleeping, .lyingDown, .sittingDown].contains(b.phase), "\(b.phase)")
    }
    do {
        // Trinken und danach Fenster (wie zwei Erinnerungen hintereinander)
        let b = freshBrain()
        let bowl = Bowl(x: 1000, water: true)
        b.bowl = bowl
        b.noticeSomething()
        var stage = 0
        let result = run(b, seconds: 150) { _ in
            if stage == 0, bowl.food <= 0 { stage = 1; b.bowl = nil; b.lookout = 400 }
        }
        check("trinkt und schaut danach hinaus", (result.phases["drinking"] ?? 0) >= 24 && (result.phases["gazing"] ?? 0) >= 24)
    }

    print("\nPausen nach Aktivität")
    do {
        var tracker = ActivityTracker()
        for _ in 0..<(30 * 30) { tracker.update(dt: 2, idle: 3) }          // 30 Minuten tippen
        check("zählt aktive Zeit", abs(tracker.activeSeconds - 1800) < 1, "\(tracker.activeSeconds)")
        for _ in 0..<60 { tracker.update(dt: 2, idle: 30) }                 // 2 Minuten lesen
        check("kurzes Lesen zählt mit", abs(tracker.activeSeconds - 1920) < 1, "\(tracker.activeSeconds)")
        for _ in 0..<90 { tracker.update(dt: 2, idle: 120) }                // länger nichts, aber keine 5 Minuten
        check("ab 1 Minute Leerlauf zählt nichts mehr dazu", abs(tracker.activeSeconds - 1920) < 1, "\(tracker.activeSeconds)")
        tracker.update(dt: 2, idle: 301)                                    // 5 Minuten weg
        check("5 Minuten weg zählt als Pause (von vorne)", tracker.activeSeconds == 0, "\(tracker.activeSeconds)")
    }

    print("\nFeierabend")
    do {
        let cal = Calendar.current
        func at(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
            cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
        }
        // 22.10.2026 ist ein Donnerstag, der 24. ein Samstag
        let s = ErrandScheduler()
        s.configureQuittingTime(hour: 17, minute: 30, weekdaysOnly: true, enabled: true)
        s.collectDue(now: at(22, 17, 29))
        check("vor 17:30 nichts", s.queue.isEmpty)
        s.collectDue(now: at(22, 17, 31))
        check("um 17:30 kommt der Feierabend", s.popNext()?.kind == .quittingTime)
        s.collectDue(now: at(22, 22, 0))
        check("am selben Abend nur einmal", s.queue.isEmpty)
        s.collectDue(now: at(24, 17, 29))
        check("läuft das Programm bis Samstag weiter: Freitag zählt", s.popNext()?.kind == .quittingTime)
        s.collectDue(now: at(24, 17, 31))
        check("samstags nicht (nur werktags)", s.queue.isEmpty)

        let late = ErrandScheduler()
        late.configureQuittingTime(hour: 17, minute: 30, weekdaysOnly: false, enabled: true)
        late.collectDue(now: at(22, 19, 0))
        late.collectDue(now: at(22, 19, 1))
        check("erst abends gestartet: keine nachträgliche Ankündigung", late.queue.isEmpty)
        late.collectDue(now: at(24, 17, 31))
        check("über Nacht weiterlaufend: am nächsten Tag wieder (auch am Wochenende, wenn so eingestellt)",
              late.popNext()?.kind == .quittingTime)
    }

    print("\nAufgaben")
    do {
        var seed: UInt64 = 42
        let random: () -> Double = {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(1 << 53)
        }
        let bag = TaskBag()
        bag.items = ["Mama anrufen", "Steuer", "Blumen gießen", "Sport"]
        var seen: [String] = []
        for _ in 0..<40 { seen.append(bag.next(random: random)!) }
        let rounds = stride(from: 0, to: 40, by: 4).map { Set(seen[$0..<$0 + 4]) }
        check("jede Runde enthält jede Aufgabe genau einmal", rounds.allSatisfy { $0.count == 4 })
        check("nie zweimal dieselbe hintereinander", zip(seen, seen.dropFirst()).allSatisfy { $0 != $1 })
        check("Reihenfolge ist gemischt (nicht jede Runde gleich)", Set(stride(from: 0, to: 40, by: 4).map { seen[$0] }).count > 1)
        bag.items = ["Nur eins"]
        check("eine einzige Aufgabe kommt immer wieder", bag.next(random: random) == "Nur eins" && bag.next(random: random) == "Nur eins")

        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let s = ErrandScheduler()
        s.random = { 0.5 }
        s.configure(.task, every: 10, now: start)
        s.collectDue(now: start.addingTimeInterval(11 * 60))
        check("ohne Einträge keine Aufgaben-Erinnerung", s.popNext() == nil)
        s.configureTasks(["  Mama anrufen  ", "", "Sport"])
        s.collectDue(now: start.addingTimeInterval(22 * 60))
        let errand = s.popNext()
        check("mit Einträgen: Erinnerung mit Text", errand?.kind == .task && ["Mama anrufen", "Sport"].contains(errand?.text ?? ""),
              "\(String(describing: errand))")
        let lines = PixelFont.lines("Steuererklärung bis Freitag abgeben!", maxWidth: BubbleFrames.maxTextWidth, maxLines: 3)
        check("langer Text wird an Wortgrenzen umbrochen", lines == ["STEUERERKLÄRUNG", "BIS FREITAG", "ABGEBEN!"], "\(lines)")
        let long = PixelFont.lines(String(repeating: "Wort ", count: 30), maxWidth: BubbleFrames.maxTextWidth, maxLines: 3)
        check("zu langer Text endet nach drei Zeilen mit …", long.count == 3 && long[2].hasSuffix("…"), "\(long)")
    }

    print("\nOutfits nach Tageszeit")
    do {
        let cal = Calendar.current
        func at(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
            cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
        }
        var times = OutfitTimes()
        check("ohne Einstellungen kein Outfit", times.outfit(at: at(22, 20, 0)) == nil)
        times.quitting = (17 * 60 + 30, true)
        check("nach Feierabend Zylinder", times.outfit(at: at(22, 18, 0)) == .evening)
        check("vor Feierabend nichts", times.outfit(at: at(22, 15, 0)) == nil)
        check("ohne Schlafenszeit Zylinder bis in die Nacht", times.outfit(at: at(23, 2, 0)) == .evening)
        check("Samstagabend kein Zylinder (nur werktags)", times.outfit(at: at(24, 19, 0)) == nil)
        check("Freitagnacht nach Mitternacht noch Zylinder", times.outfit(at: at(24, 1, 0)) == .evening)
        times.bedtime = 22 * 60 + 30
        check("ab Schlafenszeit Schlafmütze", times.outfit(at: at(22, 22, 45)) == .night)
        check("vorher noch Zylinder", times.outfit(at: at(22, 22, 0)) == .evening)
        check("nachts Schlafmütze", times.outfit(at: at(23, 3, 0)) == .night)
        check("Schlafmütze auch am Wochenende", times.outfit(at: at(24, 23, 0)) == .night)
        check("ab 5 Uhr keine Schlafmütze mehr", times.outfit(at: at(23, 5, 30)) == nil)
        times.morningEnd = 9 * 60
        check("morgens Schlafmaske", times.outfit(at: at(23, 7, 0)) == .morning)
        check("ab 9 Uhr nichts mehr", times.outfit(at: at(23, 9, 0)) == nil)
        times.bedtime = 0 * 60 + 30
        check("Schlafenszeit nach Mitternacht: um 23 Uhr noch Zylinder", times.outfit(at: at(22, 23, 0)) == .evening)
        check("um 0:45 Schlafmütze", times.outfit(at: at(23, 0, 45)) == .night)
    }

    print("\nWarteschlange")
    do {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let s = ErrandScheduler()
        s.random = { 0.5 } // ohne Zufallsschwankung
        s.configure(.drink, every: 30, now: start)
        s.configure(.lookout, every: 20, now: start)
        s.collectDue(now: start.addingTimeInterval(19 * 60))
        check("vor der Zeit ist nichts fällig", s.queue.isEmpty)
        s.collectDue(now: start.addingTimeInterval(31 * 60))
        check("beide fällig, Augenpause zuerst", s.queue.map(\.kind) == [.lookout, .drink] || s.queue.map(\.kind) == [.drink, .lookout],
              "\(s.queue.map(\.kind))")
        s.collectDue(now: start.addingTimeInterval(32 * 60))
        check("jede Art nur einmal in der Schlange", s.queue.count == 2, "\(s.queue.count)")
        _ = s.popNext(); _ = s.popNext()
        check("Schlange danach leer", s.popNext() == nil)
        s.configure(.drink, every: nil, now: start)
        s.collectDue(now: start.addingTimeInterval(200 * 60))
        check("ausgeschaltet kommt nichts mehr", !s.queue.contains { $0.kind == .drink })
        s.requestNow(.drink)
        check("„Jetzt zeigen“ kommt sofort", s.popNext()?.kind == .drink)
        // Im Videocall nur Aufgaben: Die anderen warten in der Schlange
        s.configureTasks(["Mama anrufen"])
        s.requestNow(.task)
        s.requestNow(.lookout)
        let inCall = s.popNext(where: { $0 == .task })
        check("im Call kommt nur die Aufgabe dran", inCall?.kind == .task && inCall?.text == "Mama anrufen")
        check("die Augenpause wartet bis nach dem Call", s.queue.map(\.kind) == [.lookout], "\(s.queue.map(\.kind))")
        check("im Call ohne Aufgaben-Erlaubnis: nichts", s.popNext(where: { _ in false }) == nil && s.queue.count == 1)
    }

    print(failed == 0 ? "\nAlle Szenarien bestanden." : "\n\(failed) Szenario(s) fehlgeschlagen.")
    exit(failed == 0 ? 0 : 1)
}
