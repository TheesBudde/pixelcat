import Foundation

/// Kleine Pixelschrift für die Gedankenblasen: Großbuchstaben, Umlaute, Ziffern und Satzzeichen,
/// 5 Pixel hoch, unterschiedlich breit. Text wird in Großbuchstaben geschrieben und bei Bedarf umgebrochen.
enum PixelFont {
    static let height = 5
    /// Abstand zwischen zwei Zeichen und zwischen zwei Zeilen
    static let letterGap = 1
    static let lineGap = 2

    private static let glyphs: [Character: [String]] = [
        "A": [".###.", "#...#", "#####", "#...#", "#...#"],
        "B": ["####.", "#...#", "####.", "#...#", "####."],
        "C": [".####", "#....", "#....", "#....", ".####"],
        "D": ["####.", "#...#", "#...#", "#...#", "####."],
        "E": ["#####", "#....", "####.", "#....", "#####"],
        "F": ["#####", "#....", "####.", "#....", "#...."],
        "G": [".####", "#....", "#.###", "#...#", ".###."],
        "H": ["#...#", "#...#", "#####", "#...#", "#...#"],
        "I": ["###", ".#.", ".#.", ".#.", "###"],
        "J": ["..###", "...#.", "...#.", "#..#.", ".##.."],
        "K": ["#...#", "#..#.", "###..", "#..#.", "#...#"],
        "L": ["#....", "#....", "#....", "#....", "#####"],
        "M": ["#...#", "##.##", "#.#.#", "#...#", "#...#"],
        "N": ["#...#", "##..#", "#.#.#", "#..##", "#...#"],
        "O": [".###.", "#...#", "#...#", "#...#", ".###."],
        "P": ["####.", "#...#", "####.", "#....", "#...."],
        "Q": [".###.", "#...#", "#.#.#", "#..#.", ".##.#"],
        "R": ["####.", "#...#", "####.", "#..#.", "#...#"],
        "S": [".####", "#....", ".###.", "....#", "####."],
        "T": ["#####", "..#..", "..#..", "..#..", "..#.."],
        "U": ["#...#", "#...#", "#...#", "#...#", ".###."],
        "V": ["#...#", "#...#", "#...#", ".#.#.", "..#.."],
        "W": ["#...#", "#...#", "#.#.#", "##.##", "#...#"],
        "X": ["#...#", ".#.#.", "..#..", ".#.#.", "#...#"],
        "Y": ["#...#", ".#.#.", "..#..", "..#..", "..#.."],
        "Z": ["#####", "...#.", "..#..", ".#...", "#####"],
        // Umlaute: Die Punkte stehen eine Zeile über dem Buchstaben (im Zeilenabstand)
        "Ä": [".#.#.", ".###.", "#...#", "#####", "#...#", "#...#"],
        "Ö": [".#.#.", ".###.", "#...#", "#...#", "#...#", ".###."],
        "Ü": [".#.#.", "#...#", "#...#", "#...#", "#...#", ".###."],
        "0": [".###.", "#..##", "#.#.#", "##..#", ".###."],
        "1": [".#.", "##.", ".#.", ".#.", "###"],
        "2": ["####.", "....#", ".###.", "#....", "#####"],
        "3": ["####.", "....#", ".###.", "....#", "####."],
        "4": ["#...#", "#...#", "#####", "....#", "....#"],
        "5": ["#####", "#....", "####.", "....#", "####."],
        "6": [".###.", "#....", "####.", "#...#", ".###."],
        "7": ["#####", "....#", "...#.", "..#..", "..#.."],
        "8": [".###.", "#...#", ".###.", "#...#", ".###."],
        "9": [".###.", "#...#", ".####", "....#", ".###."],
        " ": ["...", "...", "...", "...", "..."],
        ".": [".", ".", ".", ".", "#"],
        ",": ["..", "..", "..", ".#", "#."],
        "!": ["#", "#", "#", ".", "#"],
        "?": [".###.", "#...#", "..##.", ".....", "..#.."],
        ":": [".", "#", ".", "#", "."],
        ";": ["..", ".#", "..", ".#", "#."],
        "-": ["...", "...", "###", "...", "..."],
        "+": ["...", ".#.", "###", ".#.", "..."],
        "'": ["#", "#", ".", ".", "."],
        "\"": ["#.#", "#.#", "...", "...", "..."],
        "(": [".#", "#.", "#.", "#.", ".#"],
        ")": ["#.", ".#", ".#", ".#", "#."],
        "/": ["....#", "...#.", "..#..", ".#...", "#...."],
        "&": [".##..", "#..#.", ".##.#", "#..#.", ".##.#"],
        "%": ["#...#", "...#.", "..#..", ".#...", "#...#"],
        "#": [".#.#.", "#####", ".#.#.", "#####", ".#.#."],
        "@": [".###.", "#.###", "#.#.#", "#.##.", ".###."],
        "=": ["...", "###", "...", "###", "..."],
        "*": ["#.#", ".#.", "#.#", "...", "..."],
        "_": ["....", "....", "....", "....", "####"],
        "…": ["....", "....", "....", "....", "#.#.#"],
    ]

    /// Was es nicht gibt, wird ersetzt (ß → SS, typografische Zeichen → einfache); Unbekanntes fällt weg.
    static func normalized(_ text: String) -> String {
        var result = ""
        for character in text.uppercased() {
            switch character {
            case "ß", "ẞ": result += "SS"
            case "„", "“", "”": result += "\""
            case "‚", "‘", "’": result += "'"
            case "–", "—": result += "-"
            case "\n", "\t": result += " "
            default:
                if glyphs[character] != nil { result.append(character) }
            }
        }
        return result
    }

    static func glyph(_ character: Character) -> [String]? { glyphs[character] }

    /// Wie viele Zeilen ein Zeichen über die Zeile hinausragt (Umlautpunkte)
    static func ascent(of character: Character) -> Int { max(0, (glyphs[character]?.count ?? height) - height) }

    static func width(of character: Character) -> Int { glyphs[character]?.first?.count ?? 0 }

    /// Breite einer Zeile in Pixeln
    static func width(of line: String) -> Int {
        guard !line.isEmpty else { return 0 }
        return line.reduce(0) { $0 + width(of: $1) } + (line.count - 1) * letterGap
    }

    /// Bricht den Text in Zeilen von höchstens `maxWidth` Pixeln um – an Leerzeichen, zu lange Wörter mitten drin.
    /// Mehr als `maxLines` Zeilen werden mit „…“ abgeschnitten.
    static func lines(_ text: String, maxWidth: Int, maxLines: Int) -> [String] {
        let words = normalized(text).split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var lines: [String] = []
        var current = ""
        func push() {
            if !current.isEmpty { lines.append(current) }
            current = ""
        }
        for var word in words {
            // Zu lange Wörter zerteilen
            while width(of: word) > maxWidth {
                push()
                var piece = ""
                for character in word {
                    if width(of: piece + String(character)) > maxWidth { break }
                    piece.append(character)
                }
                lines.append(piece)
                word.removeFirst(piece.count)
            }
            let candidate = current.isEmpty ? word : current + " " + word
            if width(of: candidate) <= maxWidth {
                current = candidate
            } else {
                push()
                current = word
            }
        }
        push()
        if lines.count > maxLines {
            lines = Array(lines.prefix(maxLines))
            var last = lines[maxLines - 1]
            while !last.isEmpty, width(of: last + "…") > maxWidth { last.removeLast() }
            lines[maxLines - 1] = last.trimmingCharacters(in: .whitespaces) + "…"
        }
        return lines
    }
}
