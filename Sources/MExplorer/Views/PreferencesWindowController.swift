import AppKit
import SwiftUI

final class PreferencesWindowController: NSWindowController {

    private static var shared: PreferencesWindowController?

    static func show() {
        if let shared {
            shared.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = PreferencesWindowController()
        shared = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Reglages"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: PreferencesView())
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supporte") }
}

private struct PreferencesView: View {

    @ObservedObject private var settings = AppSettings.shared
    @State private var roots: [URL] = AccessManager.shared.grantedRoots

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gear") }
            access.tabItem { Label("Acces", systemImage: "lock.open") }
        }
        .padding(14)
        .frame(width: 480, height: 400)
    }

    private var general: some View {
        Form {
            Toggle("Afficher les extensions de noms de fichiers", isOn: $settings.showFileExtensions)
            Toggle("Ouvrir d'un seul clic", isOn: $settings.singleClickToOpen)
            Toggle("Ouvrir les dossiers dans un nouvel onglet", isOn: $settings.openFoldersInNewTab)
            Toggle("Confirmer les suppressions definitives", isOn: $settings.confirmPermanentDelete)
            Divider()
            Button("Reinitialiser les reglages d'affichage des dossiers") {
                FolderSettingsStore.shared.applyToAllFolders(.default)
            }
        }
        .padding(.top, 8)
    }

    private var access: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dossiers autorises")
                .font(.system(size: 12, weight: .semibold))
            Text("MExplorer est sandboxe : seuls les dossiers listes ici (et leurs sous-dossiers) sont accessibles entre deux lancements.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            List {
                ForEach(roots, id: \.self) { url in
                    HStack {
                        Image(systemName: "folder")
                        Text(url.path).font(.system(size: 11)).lineLimit(1).truncationMode(.head)
                        Spacer()
                        Button("Retirer") {
                            AccessManager.shared.revoke(url)
                            roots = AccessManager.shared.grantedRoots
                        }
                        .controlSize(.small)
                    }
                }
            }
            .frame(minHeight: 180)

            HStack {
                Button("Ajouter un dossier...") {
                    if AccessManager.shared.requestAccess(
                        to: SidebarCatalog.home,
                        message: "Choisissez un dossier a autoriser durablement.",
                        window: NSApp.keyWindow) != nil {
                        roots = AccessManager.shared.grantedRoots
                    }
                }
                Spacer()
            }
        }
        .padding(.top, 8)
    }
}
