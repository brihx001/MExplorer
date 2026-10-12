import Foundation

/// Calcul des tailles de dossiers en tache de fond, pour la colonne "Taille"
/// du mode Details.
///
/// Un dossier n'a pas de taille sur le disque : il faut parcourir son contenu.
/// Le parcours est donc fait hors du thread principal, un dossier a la fois
/// (parcourir plusieurs arborescences en parallele sature le disque sans rien
/// accelerer), et les resultats sont publies au fur et a mesure.
final class FolderSizeCalculator {

    static let shared = FolderSizeCalculator()

    /// Postee, avec anti-rebond, quand de nouvelles tailles sont disponibles.
    static let didUpdate = Notification.Name("com.jerome.mexplorer.folderSizesDidUpdate")

    /// Au-dela, on renonce : l'utilisateur n'attend pas la taille de 2000 dossiers.
    private static let maxQueued = 2000

    private struct Entry {
        let size: Int64
        /// Date de modification du dossier au moment du calcul, pour invalider.
        let stamp: Date?
    }

    private struct Job {
        let url: URL
        let stamp: Date?
    }

    private var cache: [String: Entry] = [:]
    private var pending: [Job] = []
    private var running = false
    private var generation = 0
    private var flush: DispatchWorkItem?
    private let worker = DispatchQueue(label: "com.jerome.mexplorer.foldersizes", qos: .utility)

    private init() {}

    /// Nombre de dossiers restant a calculer, pour la barre d'etat.
    private(set) var remaining = 0

    var isRunning: Bool { running || !pending.isEmpty }

    // MARK: - Lecture

    /// Taille connue, ou nil si elle n'a pas encore ete calculee ou si le
    /// dossier a change depuis.
    func cachedSize(for url: URL, modified: Date?) -> Int64? {
        guard let entry = cache[url.standardizedFileURL.path] else { return nil }
        guard entry.stamp == modified else { return nil }
        return entry.size
    }

    // MARK: - Planification

    /// Programme le calcul des dossiers indiques.
    ///
    /// La file en attente est remplacee : seule la vue affichee compte, et une
    /// navigation ne doit pas laisser l'app calculer l'ancien dossier.
    func request(_ folders: [(url: URL, modified: Date?)]) {
        generation &+= 1
        pending.removeAll()

        let jobs = folders
            .filter { cachedSize(for: $0.url, modified: $0.modified) == nil }
            .prefix(Self.maxQueued)
            .map { Job(url: $0.url.standardizedFileURL, stamp: $0.modified) }

        pending = Array(jobs)
        remaining = pending.count
        pump()
    }

    /// Abandonne les calculs en attente (navigation, changement de mode).
    func cancel() {
        generation &+= 1
        pending.removeAll()
        remaining = 0
    }

    /// Oublie les tailles memorisees (actualisation explicite).
    func flushCache() {
        cache.removeAll()
    }

    // MARK: - Execution

    private func pump() {
        guard !running, !pending.isEmpty else {
            if pending.isEmpty { remaining = 0 }
            return
        }
        let job = pending.removeFirst()
        remaining = pending.count + 1
        running = true
        let token = generation

        worker.async { [weak self] in
            let size = Self.measure(job.url) { [weak self] in
                guard let self else { return true }
                return token != self.generation
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.running = false
                guard token == self.generation else { return }
                if let size {
                    self.cache[job.url.path] = Entry(size: size, stamp: job.stamp)
                    self.scheduleNotification()
                }
                self.pump()
            }
        }
    }

    /// Retourne nil si le calcul a ete annule en cours de route.
    private static func measure(_ url: URL, cancelled: @escaping () -> Bool) -> Int64? {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        var counter = 0
        for case let child as URL in enumerator {
            counter += 1
            if counter % 256 == 0 && cancelled() { return nil }
            guard let values = try? child.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }

    /// Les dossiers se terminent par paquets : un seul rafraichissement suffit.
    private func scheduleNotification() {
        flush?.cancel()
        let work = DispatchWorkItem { NotificationCenter.default.post(name: Self.didUpdate, object: nil) }
        flush = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
}
