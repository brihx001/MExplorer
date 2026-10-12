import AppKit
import SwiftUI

final class ShortcutsWindowController: NSWindowController {

    private static var shared: ShortcutsWindowController?

    static func show() {
        if let shared {
            shared.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = ShortcutsWindowController()
        shared = controller
        controller.showWindow(nil)
    }

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Raccourcis clavier"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ShortcutsView())
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supporte") }
}

private struct ShortcutsView: View {

    private let groups: [(String, [(String, String)])] = [
        ("Navigation", [
            ("Precedent", "Cmd ["),
            ("Suivant", "Cmd ]"),
            ("Dossier parent", "Cmd Haut"),
            ("Ouvrir la selection", "Entree ou Cmd Bas"),
            ("Saisir un chemin", "Cmd L"),
            ("Actualiser", "Cmd R ou F5")
        ]),
        ("Onglets et fenetres", [
            ("Nouvel onglet", "Cmd T"),
            ("Fermer l'onglet", "Cmd W"),
            ("Onglet suivant / precedent", "Cmd Alt Droite / Gauche"),
            ("Nouvelle fenetre", "Cmd N")
        ]),
        ("Fichiers", [
            ("Couper / Copier / Coller", "Cmd X / C / V"),
            ("Copier le chemin", "Cmd Alt Maj C"),
            ("Renommer", "F2"),
            ("Nouveau dossier", "Cmd Maj N"),
            ("Corbeille", "Suppr ou Cmd Suppr"),
            ("Suppression definitive", "Maj Suppr"),
            ("Dupliquer", "Cmd D"),
            ("Coup d'oeil", "Espace"),
            ("Informations", "Cmd I"),
            ("Annuler", "Cmd Z")
        ]),
        ("Affichage", [
            ("Modes d'affichage", "Cmd 1 a Cmd 8"),
            ("Volet de navigation", "Cmd Ctrl S"),
            ("Volet de details", "Cmd Maj P"),
            ("Elements masques", "Cmd Maj .")
        ])
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(groups, id: \.0) { group in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(group.0.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        ForEach(group.1, id: \.0) { row in
                            HStack {
                                Text(row.0).font(.system(size: 12))
                                Spacer()
                                Text(row.1)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(18)
        }
    }
}
