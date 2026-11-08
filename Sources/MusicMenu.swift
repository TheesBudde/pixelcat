import AppKit

/// Die Zeile „Lo-Fi-Musik“ ganz oben im Menü: Ein Klick schaltet die Musik an oder aus, rechts der Pfeil zum
/// Untermenü (Beats, Spotify, Apple Music, Baukasten). Ein gewöhnlicher Menüpunkt kann nicht beides, deshalb
/// zeichnet sie sich selbst – so ähnlich wie die anderen Einträge.
@MainActor
final class MusicMenuRowView: NSView {
    var title = "" { didSet { needsDisplay = true } }
    var isOn = false { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?

    /// Wie hoch eine Menüzeile ist: Seit macOS 26 sind Menüs etwas größer
    static var height: CGFloat {
        if #available(macOS 26, *) { return 24 }
        return 22
    }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: Self.height))
    }

    /// Breite fest vorgeben: Zeilen mit eigener Ansicht bekommen von macOS nicht automatisch die Breite des Menüs
    func fit(to menu: NSMenu) {
        setFrameSize(NSSize(width: 1, height: Self.height))
        let font = NSFont.menuFont(ofSize: 0)
        let own = (title as NSString).size(withAttributes: [.font: font]).width + 50 + 40
        let width = max(240, ceil(max(own, menu.size.width)))
        setFrameSize(NSSize(width: width, height: Self.height))
        needsDisplay = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private var highlighted: Bool { enclosingMenuItem?.isHighlighted ?? false }

    override func draw(_ dirtyRect: NSRect) {
        let textColor: NSColor = highlighted ? .selectedMenuItemTextColor : .labelColor
        if highlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 0), xRadius: 4, yRadius: 4).fill()
        }
        if isOn { symbol("checkmark", color: textColor, pointSize: 11, weight: .bold, at: 11) }
        symbol(isOn ? "music.note" : "music.note", color: textColor, pointSize: 13, weight: .regular, at: 27)
        let font = NSFont.menuFont(ofSize: 0)
        let text = NSAttributedString(string: title, attributes: [.font: font, .foregroundColor: textColor])
        let size = text.size()
        let maxWidth = bounds.width - 50 - 28
        text.draw(with: NSRect(x: 50, y: (bounds.height - size.height) / 2, width: maxWidth, height: size.height),
                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        symbol("chevron.right", color: highlighted ? textColor : .secondaryLabelColor, pointSize: 11, weight: .semibold,
               at: bounds.width - 24)
    }

    private func symbol(_ name: String, color: NSColor, pointSize: CGFloat, weight: NSFont.Weight, at x: CGFloat) {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return }
        let size = image.size
        image.draw(in: NSRect(x: x, y: (bounds.height - size.height) / 2, width: size.width, height: size.height))
    }

    /// Klick auf die Zeile (nicht nur Darüberfahren): Musik an oder aus, das Menü geht zu
    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        // Ein Klick auf den Pfeil öffnet nur das Untermenü
        if point.x > bounds.width - 34 { return }
        enclosingMenuItem?.menu?.cancelTracking()
        onClick?()
    }

    override func accessibilityRole() -> NSAccessibility.Role? { .menuItem }
    override func accessibilityLabel() -> String? { title }
    override func isAccessibilityElement() -> Bool { true }
}
