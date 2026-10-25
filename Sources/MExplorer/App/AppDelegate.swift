import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Les acces sandbox doivent etre restaures avant toute lecture de dossier.
        // Avant toute construction d'interface : les menus et les fenetres
        // lisent leurs libelles a l'instant ou ils sont crees.
        L10n.apply(AppSettings.shared.language)
        AppSettings.shared.theme.apply()
        AppSettings.shared.addApplicationsFavoriteOnce()
        // Les menus sont construits une fois : il faut les refaire quand la
        // langue change.
        NotificationCenter.default.addObserver(forName: L10n.changed, object: nil, queue: .main) { _ in
            MainMenu.install()
        }
        AccessManager.shared.restoreAll()

        MainMenu.install()
        restoreSession()
        NSApp.activate(ignoringOtherApps: true)
        requestDiskAccessIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        saveSession()
        AccessManager.shared.releaseAll()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { WindowManager.shared.openWindow() }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            AccessManager.shared.register(url)
            WindowManager.shared.openWindow(at: .folder(isDir.boolValue ? url : url.deletingLastPathComponent()))
        }
    }

    // MARK: - Session

    /// Reouvre toutes les fenetres de la session precedente, chacune avec ses
    /// onglets. Les dossiers disparus entre deux lancements sont ecartes, et
    /// une fenetre qui n'en garderait aucun n'est pas rouverte.
    private func restoreSession() {
        let windows = AppSettings.shared.lastSessionWindows
            .map { paths in
                paths.map { URL(fileURLWithPath: $0) }
                    .filter { FileManager.default.fileExists(atPath: $0.path) }
            }
            .filter { !$0.isEmpty }

        guard !windows.isEmpty else {
            WindowManager.shared.openWindow(at: .folder(SidebarCatalog.home))
            promptForInitialAccessIfNeeded()
            return
        }
        for urls in windows {
            let controller = WindowManager.shared.openWindow(at: .folder(urls[0]))
            for url in urls.dropFirst() {
                controller.model.newTab(at: .folder(url), select: false)
            }
            controller.model.selectTab(at: 0)
        }
        promptForInitialAccessIfNeeded()
    }

    private func saveSession() {
        let windows = WindowManager.shared.controllers.map { controller in
            controller.model.tabs.compactMap { $0.location.folderURL?.path }
        }
        AppSettings.shared.lastSessionWindows = windows.filter { !$0.isEmpty }
    }

    /// Propose, au lancement, d'autoriser l'ensemble du disque.
    ///
    /// La demande n'apparait que si la racine n'est pas deja autorisee, et
    /// l'utilisateur peut la refuser definitivement.
    private func requestDiskAccessIfNeeded() {
        guard !AccessManager.shared.hasWholeDiskAccess,
              !AppSettings.shared.skipDiskAccessPrompt else { return }

        // Apres l'affichage de la fenetre, pour que l'alerte ne precede pas l'app.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            let alert = NSAlert()
            alert.messageText = L("Autoriser MExplorer a lire tout le disque")
            alert.informativeText = [
                L("MExplorer fonctionne dans le bac a sable macOS : il ne voit que les dossiers que vous lui designez."),
                L("Choisissez le disque de demarrage dans la fenetre suivante pour lui donner acces a l'ensemble du disque. L'autorisation est conservee d'un lancement a l'autre."),
                L("Les dossiers proteges par macOS (Bureau, Documents, Telechargements) feront l'objet d'une demande separee au premier acces.")
            ].joined(separator: "\n\n")
            alert.addButton(withTitle: L("Choisir le disque..."))
            alert.addButton(withTitle: L("Plus tard"))
            alert.addButton(withTitle: L("Ne plus demander"))

            let window = WindowManager.shared.controllers.first?.window
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                if AccessManager.shared.requestWholeDisk(window: window) != nil {
                    WindowManager.shared.controllers.forEach { controller in
                        controller.model.tabs.forEach { $0.reload() }
                    }
                }
            case .alertThirdButtonReturn:
                AppSettings.shared.skipDiskAccessPrompt = true
            default:
                break
            }
        }
    }

    /// Sans autorisation, la zone de fichiers affiche elle-meme le bouton
    /// "Autoriser l'acces" : pas de dialogue bloquant au lancement.
    private func promptForInitialAccessIfNeeded() {
        guard AccessManager.shared.grantedRoots.isEmpty,
              !AccessManager.shared.canList(SidebarCatalog.home) else { return }
        NSLog("MExplorer: aucun dossier autorise, l'utilisateur doit en designer un.")
    }
}
