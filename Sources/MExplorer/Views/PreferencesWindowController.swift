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
        window.title = L("Reglages")
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
            general.tabItem { Label(L("General"), systemImage: "gear") }
            access.tabItem { Label(L("Acces"), systemImage: "lock.open") }
        }
        .padding(14)
        .frame(width: 480, height: 400)
    }

    private var general: some View {
        Form {
            Picker(L("Langue"), selection: $settings.language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.title).tag(language)
                }
            }
            Text(L("Un changement de langue s'applique immediatement aux menus et aux panneaux ; quelques libelles deja affiches suivent au prochain lancement."))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Picker(L("Theme"), selection: $settings.theme) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.title).tag(theme)
                }
            }
            Divider()
            Toggle(L("Afficher les elements masques"), isOn: $settings.showHiddenItems)
            Toggle(L("Afficher les extensions de noms de fichiers"), isOn: $settings.showFileExtensions)
            Toggle(L("Ouvrir d'un seul clic"), isOn: $settings.singleClickToOpen)
            Toggle(L("Ouvrir les dossiers dans un nouvel onglet"), isOn: $settings.openFoldersInNewTab)
            Toggle(L("Confirmer les suppressions definitives"), isOn: $settings.confirmPermanentDelete)
            Divider()
            Button(L("Reinitialiser les reglages d'affichage des dossiers")) {
                FolderSettingsStore.shared.applyToAllFolders(.default)
            }
        }
        .padding(.top, 8)
    }

    private var access: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Dossiers autorises"))
                .font(.system(size: 12, weight: .semibold))
            Text(L("MExplorer est sandboxe : seuls les dossiers listes ici (et leurs sous-dossiers) sont accessibles entre deux lancements."))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            List {
                ForEach(roots, id: \.self) { url in
                    HStack {
                        Image(systemName: "folder")
                        Text(url.path).font(.system(size: 11)).lineLimit(1).truncationMode(.head)
                        Spacer()
                        Button(L("Retirer")) {
                            AccessManager.shared.revoke(url)
                            roots = AccessManager.shared.grantedRoots
                        }
                        .controlSize(.small)
                    }
                }
            }
            .frame(minHeight: 180)

            HStack {
                Button(L("Ajouter un dossier...")) {
                    if AccessManager.shared.requestAccess(
                        to: SidebarCatalog.home,
                        message: L("Choisissez un dossier a autoriser durablement."),
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
