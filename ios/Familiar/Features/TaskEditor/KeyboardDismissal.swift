import SwiftUI

/// Schließt die Tastatur, sobald ein Blatt zu verschwinden beginnt – auch beim Wegziehen mit dem Finger.
///
/// Ohne das lässt SwiftUI die Tastatur stehen, bis das Blatt ganz abgebaut ist: Gemessen blieb sie nach dem
/// Wegwischen von „Neue Aufgabe“ rund 1,9 s über der Aufgabenliste und der Tab-Leiste stehen. Die Tastatur
/// fährt jetzt gemeinsam mit dem Blatt nach unten, wie in Apples eigenen Apps.
private struct EndEditingWhenDisappearing: UIViewControllerRepresentable {
    final class Controller: UIViewController {
        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            view.window?.endEditing(true)
        }
    }

    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}
}

extension View {
    /// Siehe ``EndEditingWhenDisappearing``: für Blätter mit Texteingabe.
    func endsEditingWhenDisappearing() -> some View {
        background { EndEditingWhenDisappearing().frame(width: 0, height: 0).accessibilityHidden(true) }
    }
}

extension View {
    /// Unterdrückt die Vorschläge über der Tastatur, die iOS aus dem Adressbuch macht (eigene Telefonnummern
    /// bei „Titel“): Ein leerer Inhaltstyp schaltet die automatische Feld-Erkennung für dieses Feld ab.
    func noContactSuggestions() -> some View {
        textContentType(UITextContentType(rawValue: ""))
    }
}
