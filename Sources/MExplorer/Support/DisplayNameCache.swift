import AppKit
import Combine

/// Resolution des noms localises de dossiers.
///
/// `URLResourceValues.localizedName` passe par LaunchServices, qui interroge le
/// bac a sable et TCC. Sur les dossiers proteges (Bureau, Documents,
/// Telechargements, Musique, Films) l'appel bloque jusqu'a dix secondes tant
/// qu'aucune decision TCC n'est enregistree. Il ne doit donc jamais etre fait
/// sur le thread principal : on rend immediatement le nom brut, on resout en
/// tache de fond, et on previent l'interface quand le vrai nom arrive.
final class DisplayNameCache: ObservableObject {

    static let shared = DisplayNameCache()

    /// Incremente a chaque lot resolu ; les vues SwiftUI s'y abonnent.
    @Published private(set) var version = 0

    /// Poste apres chaque lot resolu, pour les vues AppKit.
    static let changed = Notification.Name("com.jerome.mexplorer.displayNamesChanged")

    private static let defaultsKey = "com.jerome.mexplorer.displayNames"
    private var cache: [String: String] = [:]
    private var persistPending = false
    private var pending = Set<String>()
    private let queue = DispatchQueue(label: "com.jerome.mexplorer.displayNames", qos: .utility)
    private var flush: DispatchWorkItem?

    private init() {
        // Le cout est paye une fois : on le conserve entre les lancements.
        cache = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:]
    }

    private func persistLater() {
        guard !persistPending else { return }
        persistPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            self.persistPending = false
            UserDefaults.standard.set(self.cache, forKey: Self.defaultsKey)
        }
    }

    /// Nom affichable tout de suite : le nom localise s'il est deja connu,
    /// sinon le nom de fichier, avec une resolution lancee en arriere-plan.
    func name(for url: URL) -> String {
        let path = url.standardizedFileURL.path
        if let cached = cache[path] { return cached }
        resolve(url, path: path)
        let raw = url.lastPathComponent
        return raw.isEmpty ? path : raw
    }

    /// Nom deja resolu, sans declencher de resolution.
    func cachedName(for url: URL) -> String? {
        cache[url.standardizedFileURL.path]
    }

    private func resolve(_ url: URL, path: String) {
        guard !pending.contains(path) else { return }
        pending.insert(path)
        queue.async { [weak self] in
            let resolved = (try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName)
                ?? url.lastPathComponent
            DispatchQueue.main.async {
                guard let self else { return }
                self.pending.remove(path)
                guard self.cache[path] != resolved else { return }
                self.cache[path] = resolved
                self.persistLater()
                self.scheduleNotification()
            }
        }
    }

    /// Les resolutions arrivent par paquets : un seul rafraichissement suffit.
    private func scheduleNotification() {
        flush?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.version &+= 1
            NotificationCenter.default.post(name: Self.changed, object: nil)
        }
        flush = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }
}
