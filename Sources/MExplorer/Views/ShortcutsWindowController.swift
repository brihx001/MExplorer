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
        window.title = L("Raccourcis clavier")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ShortcutsView())
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supporte") }
}

private struct ShortcutsView: View {

    private let groups: [(String, [(String, String)])] = [
        (L("Navigation"), [
            (L("Precedent"), L("Cmd [")),
            (L("Suivant"), L("Cmd ]")),
            (L("Dossier parent"), L("Cmd Haut")),
            (L("Ouvrir la selection"), L("Entree ou Cmd Bas")),
            (L("Saisir un chemin"), L("Cmd L")),
            (L("Actualiser"), L("Cmd R ou F5"))
        ]),
        (L("Onglets et fenetres"), [
            (L("Nouvel onglet"), L("Cmd T")),
            (L("Fermer l'onglet"), L("Cmd W")),
            (L("Onglet suivant / precedent"), L("Cmd Alt Droite / Gauche")),
            (L("Nouvelle fenetre"), L("Cmd N"))
        ]),
        (L("Fichiers"), [
            (L("Couper / Copier / Coller"), L("Cmd X / C / V")),
            (L("Copier le chemin"), L("Cmd Alt Maj C")),
            (L("Renommer"), L("F2")),
            (L("Nouveau dossier"), L("Cmd Maj N")),
            (L("Corbeille"), L("Suppr ou Cmd Suppr")),
            (L("Suppression definitive"), L("Maj Suppr")),
            (L("Dupliquer"), L("Cmd D")),
            (L("Coup d'oeil"), L("Espace")),
            (L("Informations"), L("Cmd I")),
            (L("Annuler"), L("Cmd Z"))
        ]),
        (L("Affichage"), [
            (L("Modes d'affichage"), L("Cmd 1 a Cmd 8")),
            (L("Volet de navigation"), L("Cmd Ctrl S")),
            (L("Volet de details"), L("Cmd Maj P")),
            (L("Elements masques"), L("Cmd Maj ."))
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
