import AppKit

/// Gestion des autorisations d'acces sous sandbox App Store.
///
/// Dans le sandbox, l'app ne voit que son conteneur. Chaque dossier que
/// l'utilisateur designe via un NSOpenPanel devient accessible, et un
/// security-scoped bookmark permet de retrouver cet acces aux lancements suivants.
final class AccessManager {

    static let shared = AccessManager()

    private static let defaultsKey = "com.jerome.mexplorer.bookmarks"

    /// Racines actuellement ouvertes en acces securise.
    private(set) var grantedRoots: [URL] = []
    private var startedURLs: [URL] = []

    private init() {}

    // MARK: - Cycle de vie

    /// A appeler une fois au demarrage, avant toute lecture de dossier.
    func restoreAll() {
        guard let stored = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: Data] else { return }
        var refreshed: [String: Data] = [:]

        for (path, data) in stored {
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data,
                                     options: [.withSecurityScope],
                                     relativeTo: nil,
                                     bookmarkDataIsStale: &stale) else { continue }
            guard url.startAccessingSecurityScopedResource() else { continue }
            startedURLs.append(url)
            grantedRoots.append(url)

            if stale, let fresh = try? url.bookmarkData(options: [.withSecurityScope],
                                                       includingResourceValuesForKeys: nil,
                                                       relativeTo: nil) {
                refreshed[url.path] = fresh
            } else {
                refreshed[path] = data
            }
        }
        UserDefaults.standard.set(refreshed, forKey: Self.defaultsKey)
        normalizeRoots()
    }

    func releaseAll() {
        for url in startedURLs { url.stopAccessingSecurityScopedResource() }
        startedURLs.removeAll()
    }

    // MARK: - Interrogation

    /// Vrai si `url` est couverte par une racine autorisee ou par le conteneur de l'app.
    func isCovered(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        if path.hasPrefix(NSHomeDirectory()) { return true }   // conteneur sandbox de l'app
        for root in grantedRoots {
            let rootPath = root.standardizedFileURL.path
            if path == rootPath || path.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/") {
                return true
            }
        }
        return false
    }

    /// Vrai si le contenu du dossier est reellement lisible maintenant.
    func canList(_ url: URL) -> Bool {
        guard let handle = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil,
            options: [.skipsSubdirectoryDescendants]
        ) else { return false }
        _ = handle
        return true
    }

    /// Vrai si une racine autorisee couvre la totalite du volume de demarrage.
    var hasWholeDiskAccess: Bool {
        grantedRoots.contains { $0.standardizedFileURL.path == "/" }
    }

    // MARK: - Octroi

    /// Demande l'acces a l'ensemble du disque.
    ///
    /// Dans le bac a sable, « tout le disque » se traduit par une autorisation
    /// sur la racine du volume, conservee par un security-scoped bookmark. Les
    /// dossiers proteges par TCC (Bureau, Documents, Telechargements, Photos)
    /// restent soumis a leur propre autorisation, demandee par macOS au premier
    /// acces.
    @discardableResult
    func requestWholeDisk(window: NSWindow? = nil) -> URL? {
        requestAccess(
            to: URL(fileURLWithPath: "/"),
            message: L("Choisissez le disque de demarrage pour autoriser MExplorer a le lire en entier."),
            window: window
        )
    }

    /// Ouvre le panneau systeme pour que l'utilisateur autorise un dossier.
    /// Retourne l'URL autorisee, ou nil si annule.
    @discardableResult
    func requestAccess(to suggested: URL?, message: String, window: NSWindow? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.message = message
        panel.prompt = L("Autoriser")
        panel.title = L("Autoriser l'acces")
        if let suggested { panel.directoryURL = suggested }

        let response: NSApplication.ModalResponse
        if let window, window.isVisible {
            // runModal reste plus fiable qu'une feuille ici : l'appelant attend le resultat.
            response = panel.runModal()
        } else {
            response = panel.runModal()
        }
        guard response == .OK, let url = panel.url else { return nil }
        register(url)
        return url
    }

    /// Enregistre une URL deja obtenue via un panneau (drag&drop, ouverture de document...).
    func register(_ url: URL) {
        guard let data = try? url.bookmarkData(options: [.withSecurityScope],
                                               includingResourceValuesForKeys: nil,
                                               relativeTo: nil) else { return }
        var stored = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: Data] ?? [:]
        stored[url.standardizedFileURL.path] = data
        UserDefaults.standard.set(stored, forKey: Self.defaultsKey)

        if url.startAccessingSecurityScopedResource() {
            startedURLs.append(url)
        }
        grantedRoots.append(url)
        normalizeRoots()
    }

    func revoke(_ url: URL) {
        var stored = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: Data] ?? [:]
        stored.removeValue(forKey: url.standardizedFileURL.path)
        UserDefaults.standard.set(stored, forKey: Self.defaultsKey)
        grantedRoots.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        if let idx = startedURLs.firstIndex(where: { $0.standardizedFileURL == url.standardizedFileURL }) {
            startedURLs[idx].stopAccessingSecurityScopedResource()
            startedURLs.remove(at: idx)
        }
    }

    /// Supprime les racines redondantes (contenues dans une autre) et les doublons.
    private func normalizeRoots() {
        var unique: [URL] = []
        for root in grantedRoots.sorted(by: { $0.path.count < $1.path.count }) {
            // La racine du volume est un cas a part : son chemin se termine
            // deja par une barre oblique, « / » + « / » ne prefixe rien.
            let covered = unique.contains { parent in
                if parent.path == "/" { return true }
                return root.path == parent.path || root.path.hasPrefix(parent.path + "/")
            }
            if covered { continue }
            unique.append(root)
        }
        grantedRoots = unique
    }
}
