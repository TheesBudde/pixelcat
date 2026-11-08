import Foundation

/// Was gerade los ist: kein Call, ein Videocall (Kamera oder Mikrofon) oder ein geteilter Bildschirm
enum CallSituation: Equatable {
    case none, call, screenSharing

    init(_ reason: CallDetector.Reason?) {
        switch reason {
        case nil: self = .none
        case .screenSharing: self = .screenSharing
        case .camera, .microphone: self = .call
        }
    }
}

/// Einstellungen › Videocalls: Was eine Erinnerung im Call tut
enum CallHandling: String, CaseIterable {
    /// Im Call als stille Blase am Dock zeigen
    case show
    /// Bis nach dem Call warten, dann nachholen
    case later
    /// Weglassen
    case skip
}

/// Einstellungen › Videocalls: Für jede Erinnerung einzeln, ob sie im Call kommt, danach kommt oder wegfällt.
/// Was im Call kommt, erscheint nur als stille Blase am Dock: ohne Katze, ohne Napf oder Fenster, ohne Ton.
struct CallPolicy: Equatable {
    enum Decision: Equatable {
        /// Kein Call: wie immer
        case normal
        /// Im Call: nur die Blase am Dock
        case quiet
        /// Wartet bis nach dem Call
        case later
        /// Fällt weg
        case skip
    }

    /// Videocalls und Bildschirmfreigabe erkennen (sonst ist im Call alles wie immer)
    var detect = true
    /// Pro Erinnerung (fehlt eine, wartet sie bis danach)
    var handling: [ErrandKind: CallHandling] = [:]
    /// „Zeigen“ gilt auch, während der Bildschirm geteilt wird (dann sehen es die anderen)
    var duringScreenSharing = false

    /// Diese Erinnerungen lassen sich einstellen (der Vogel nicht: Wer im Call ist, ist ja da)
    static let selectable: [ErrandKind] = [.task, .drink, .lookout, .quittingTime, .motivation]

    func handling(for kind: ErrandKind) -> CallHandling { handling[kind] ?? .later }

    mutating func set(_ value: CallHandling, for kind: ErrandKind) { handling[kind] = value }

    func decision(for kind: ErrandKind, in situation: CallSituation) -> Decision {
        guard detect, situation != .none else { return .normal }
        if kind == .bird { return .skip }
        switch handling(for: kind) {
        case .show: return situation == .call || duringScreenSharing ? .quiet : .later
        case .later: return .later
        case .skip: return .skip
        }
    }
}
