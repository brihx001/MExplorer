import Foundation

/// Memorise les reglages d'affichage par dossier (equivalent des .DS_Store du Finder,
/// mais stockes dans les preferences de l'app pour rester compatible sandbox).
final class FolderSettingsStore {

    static let shared = FolderSettingsStore()

    private static let perFolderKey = "com.jerome.mexplorer.folderSettings"
    private static let globalKey = "com.jerome.mexplorer.defaultFolderSettings"

    private var cache: [String: FolderViewSettings] = [:]
    private var dirty = false

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.perFolderKey),
           let decoded = try? JSONDecoder().decode([String: FolderViewSettings].self, from: data) {
            cache = decoded
        }
    }

    /// Reglages par defaut appliques aux dossiers jamais personnalises.
    var defaults: FolderViewSettings {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.globalKey),
                  let decoded = try? JSONDecoder().decode(FolderViewSettings.self, from: data)
            else { return .default }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: Self.globalKey)
            }
        }
    }

    func settings(for url: URL) -> FolderViewSettings {
        cache[url.standardizedFileURL.path] ?? defaults
    }

    func store(_ settings: FolderViewSettings, for url: URL) {
        cache[url.standardizedFileURL.path] = settings
        scheduleFlush()
    }

    /// Applique les reglages courants a tous les dossiers (bouton "Appliquer a tous les dossiers").
    func applyToAllFolders(_ settings: FolderViewSettings) {
        defaults = settings
        cache.removeAll()
        scheduleFlush()
    }

    func reset(for url: URL) {
        cache.removeValue(forKey: url.standardizedFileURL.path)
        scheduleFlush()
    }

    private func scheduleFlush() {
        guard !dirty else { return }
        dirty = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            self.dirty = false
            if let data = try? JSONEncoder().encode(self.cache) {
                UserDefaults.standard.set(data, forKey: Self.perFolderKey)
            }
        }
    }
}
