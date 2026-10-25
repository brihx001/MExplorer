import AppKit

/// Enregistrement et relecture de la session : quelles fenetres, quels
/// onglets, et ou chaque fenetre se trouvait.
enum SessionStore {

    struct WindowState {
        let urls: [URL]
        /// nil quand aucun cadre n'a ete enregistre, ou qu'il n'est plus
        /// atteignable sur les ecrans actuels.
        let frame: NSRect?
    }

    // MARK: - Ecriture

    /// Vrai une fois la session ecrite a l'extinction.
    ///
    /// Les fenetres se ferment ensuite une a une, et chacune reenregistrerait
    /// la session : la derniere la reduirait a elle seule, perdant les autres.
    private static var isSealed = false

    /// Fige la session : plus rien ne l'ecrira.
    static func seal() { isSealed = true }

    /// Note l'etat des fenetres ouvertes.
    ///
    /// Appele a la fermeture de chaque fenetre autant qu'a l'extinction : la
    /// derniere fenetre fermee fait quitter l'application, et
    /// `applicationWillTerminate` ne trouverait alors plus rien a enregistrer.
    /// Une liste vide n'ecrase jamais la precedente, pour cette raison meme.
    ///
    /// `closing` est la fenetre en train de se fermer. Elle est ecartee tant
    /// qu'il en reste d'autres : elle ne fera pas partie de la prochaine
    /// session. Si c'est la derniere, elle est au contraire la seule chose a
    /// garder, l'application s'arretant avec elle.
    static func save(closing: BrowserWindowController? = nil) {
        guard !isSealed else { return }
        var controllers = WindowManager.shared.controllers
        if let closing, controllers.count > 1 {
            controllers.removeAll { $0 === closing }
        }
        var paths: [[String]] = []
        var frames: [String] = []
        for controller in controllers {
            let tabs = controller.model.tabs.compactMap { $0.location.folderURL?.path }
            guard !tabs.isEmpty else { continue }
            paths.append(tabs)
            frames.append(controller.window.map { NSStringFromRect($0.frame) } ?? "")
        }
        guard !paths.isEmpty else { return }
        AppSettings.shared.lastSessionWindows = paths
        AppSettings.shared.lastSessionFrames = frames
    }

    // MARK: - Lecture

    /// Les fenetres a rouvrir. Les dossiers disparus entre deux lancements
    /// sont ecartes, et une fenetre qui n'en garderait aucun est oubliee.
    static func restore() -> [WindowState] {
        let stored = AppSettings.shared.lastSessionWindows
        let frames = AppSettings.shared.lastSessionFrames

        return stored.enumerated().compactMap { index, paths in
            let urls = paths.map { URL(fileURLWithPath: $0) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
            guard !urls.isEmpty else { return nil }
            let text = index < frames.count ? frames[index] : ""
            return WindowState(urls: urls, frame: frame(from: text))
        }
    }

    private static func frame(from text: String) -> NSRect? {
        guard !text.isEmpty else { return nil }
        let rect = NSRectFromString(text)
        guard rect.width > 0, rect.height > 0 else { return nil }
        return rect
    }

    /// Vrai si une part suffisante de la barre de titre tombe sur un ecran.
    ///
    /// Un ecran debranche depuis, ou une resolution changee, peut rendre le
    /// cadre inatteignable : mieux vaut replacer la fenetre que la laisser
    /// hors de vue, sans prise pour la ramener.
    static func isReachable(_ frame: NSRect) -> Bool {
        let titleBar = NSRect(x: frame.minX, y: frame.maxY - 28, width: frame.width, height: 28)
        return NSScreen.screens.contains { screen in
            let shown = screen.visibleFrame.intersection(titleBar)
            return shown.width >= 80 && shown.height >= 8
        }
    }
}
