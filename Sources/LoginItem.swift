import Foundation
import ServiceManagement

/// Mit dem Mac starten: Pixelcat als Anmeldeobjekt eintragen oder austragen.
/// macOS selbst merkt sich die Wahl (Systemeinstellungen › Allgemein › Anmeldeobjekte), deshalb steht sie nicht in
/// den Einstellungen und wird jedes Mal frisch gefragt.
@MainActor
enum LoginItem {
    /// Nur in der echten App (mit Bundle), nicht in Tests und Vorschauen
    static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    static var isEnabled: Bool {
        isAvailable && SMAppService.mainApp.status == .enabled
    }

    /// Eingetragen, aber macOS wartet noch auf die Erlaubnis in den Systemeinstellungen
    static var needsApproval: Bool {
        isAvailable && SMAppService.mainApp.status == .requiresApproval
    }

    /// Ein- oder austragen. Gibt zurück, ob es geklappt hat.
    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        guard isAvailable else { return false }
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled { try service.register() }
            } else if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            }
            return true
        } catch {
            NSLog("Pixelcat: Anmeldeobjekt konnte nicht geändert werden: \(error.localizedDescription)")
            return false
        }
    }

    /// Die passende Seite der Systemeinstellungen öffnen
    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
