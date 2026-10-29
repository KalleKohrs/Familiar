import Foundation

/// Kleines Protokoll auf dem Gerät für Vorgänge, die ohne geöffnete App laufen (Abhaken in der Live Activity,
/// Geräte-Anmeldung für Mitteilungen). Es liegt im App-Group-Container und wird nie übertragen.
/// In Testversionen (Xcode, TestFlight) zeigt das Profil es an; so lässt sich nachvollziehen, was passiert ist,
/// ohne dass das iPhone mit dem Mac verbunden ist. Es enthält keine Aufgabentitel und keine Namen.
public enum FamiliarDiagnostics {
    private static let fileName = "diagnose.txt"
    private static let maxLines = 80

    private static var fileURL: URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "FamiliarAppGroup") as? String,
              !group.isEmpty,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            return nil
        }
        return container.appending(path: fileName)
    }

    /// Hängt eine Zeile mit Uhrzeit und Prozessname an (App oder Widget-Extension).
    public static func record(_ message: String) {
        guard let url = fileURL else { return }
        let time = Date.now.formatted(.dateTime.day().month().hour().minute().second())
        let process = ProcessInfo.processInfo.processName
        let line = "\(time) [\(process)] \(message)"
        var lines = lines(at: url)
        lines.append(line)
        if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
        try? Data(lines.joined(separator: "\n").utf8).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Alle Zeilen, neueste zuletzt.
    public static func lines() -> [String] {
        guard let url = fileURL else { return [] }
        return lines(at: url)
    }

    public static func clear() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func lines(at url: URL) -> [String] {
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }
}
