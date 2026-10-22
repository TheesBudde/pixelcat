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

    print(failed == 0 ? "\nAlle Szenarien bestanden." : "\n\(failed) Szenario(s) fehlgeschlagen.")
    exit(failed == 0 ? 0 : 1)
}
