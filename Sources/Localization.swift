import Foundation

/// Sprache der Oberfläche. „System“ folgt der Sprache von macOS.
enum Language: String, CaseIterable {
    case system, german = "de", english = "en"

    var title: String {
        switch self {
        case .system: return L10n.s("Wie macOS", "Same as macOS")
        case .german: return "Deutsch"
        case .english: return "English"
        }
    }
}

/// Zweisprachige Texte: Deutsch und Englisch stehen direkt nebeneinander im Code.
enum L10n {
    nonisolated(unsafe) static var language: Language = .system

    static var isGerman: Bool {
        switch language {
        case .german: return true
        case .english: return false
        case .system: return Locale.preferredLanguages.first?.hasPrefix("de") ?? false
        }
    }

    /// Deutsch oder Englisch, je nach eingestellter Sprache.
    static func s(_ german: String, _ english: String) -> String {
        isGerman ? german : english
    }
}
