import Foundation

/// Recherche Spotlight en direct (NSMetadataQuery), avec resultats incrementaux.
final class SpotlightSearch {

    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private let onUpdate: ([FileItem]) -> Void
    private let onFinish: () -> Void

    init(onUpdate: @escaping ([FileItem]) -> Void, onFinish: @escaping () -> Void) {
        self.onUpdate = onUpdate
        self.onFinish = onFinish
    }

    deinit { stop() }

    /// `scope` limite la recherche a un dossier ; nil = tout ce qui est indexe et accessible.
    func start(text: String, scope: URL?, includeContent: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { stop(); return }

        let escaped = trimmed.replacingOccurrences(of: "\"", with: "\\\"")

        // La syntaxe des requetes Spotlight n'est pas celle de NSPredicate :
        // la comparaison s'ecrit `==` avec des jokers dans la chaine et les
        // modificateurs colles a la fin. `LIKE[cd]` est accepte sans erreur
        // par `NSPredicate(fromMetadataQueryString:)` mais ne correspond a
        // rien : la recherche par nom ne rendait jamais le moindre resultat.
        // Mesure : « *licence* » dans le dossier Telechargements rend 47
        // fichiers avec `==`, aucun avec `LIKE`.
        var format = "(kMDItemFSName == \"*\(escaped)*\"cd)"
        if includeContent {
            format += " || (kMDItemDisplayName == \"*\(escaped)*\"cd)"
            // Sur le contenu, un joker de tete interdit a Spotlight de se
            // servir de son index : il parcourt alors les fichiers un a un et
            // la recherche ne se termine pas sur une grande arborescence.
            // « mot* » designe un debut de mot, ce que l'index sait repondre.
            format += " || (kMDItemTextContent == \"\(escaped)*\"cd)"
        }
        run(format,
            scopes: scope.map { [$0] } ?? [NSMetadataQueryLocalComputerScope],
            sort: [NSSortDescriptor(key: NSMetadataItemFSNameKey, ascending: true)])
    }

    /// Elements ouverts ou modifies dans les `days` derniers jours.
    /// L'index Spotlight repond en une fraction de seconde la ou une
    /// enumeration recursive du dossier personnel prend plusieurs minutes.
    func startRecents(within days: Int, scope: URL) {
        let seconds = max(1, days) * 86_400
        let format = "(kMDItemLastUsedDate >= $time.now(-\(seconds)))"
            + " || (kMDItemFSContentChangeDate >= $time.now(-\(seconds)))"
        run(format,
            scopes: [scope],
            sort: [NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)])
    }

    private func run(_ format: String, scopes: [Any], sort: [NSSortDescriptor]) {
        stop()
        generation &+= 1
        let q = NSMetadataQuery()
        q.predicate = NSPredicate(fromMetadataQueryString: format)
        q.searchScopes = scopes
        q.sortDescriptors = sort
        q.notificationBatchingInterval = 0.4

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .NSMetadataQueryDidUpdate, object: q, queue: .main) { [weak self] _ in
            self?.publish(q)
        })
        observers.append(center.addObserver(forName: .NSMetadataQueryGatheringProgress, object: q, queue: .main) { [weak self] _ in
            self?.publish(q)
        })
        observers.append(center.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: q, queue: .main) { [weak self] _ in
            self?.publish(q)
            self?.onFinish()
        })

        query = q
        q.start()
    }

    func stop() {
        generation &+= 1
        isBuilding = false
        needsRebuild = false
        query?.stop()
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers.removeAll()
        query = nil
    }

    /// Au-dela, la liste cesse d'etre consultable et le cout de construction
    /// l'emporte sur l'interet.
    private static let maxResults = 2000

    private let builder = DispatchQueue(label: "com.jerome.mexplorer.search", qos: .userInitiated)
    private var isBuilding = false
    private var needsRebuild = false
    /// Incrementee a chaque depart et a chaque arret : une construction partie
    /// avant ne publie plus rien.
    private var generation = 0

    /// Publie les resultats courants.
    ///
    /// Appelee a chaque lot de la recherche, toutes les 0,4 seconde. Elle
    /// construisait jusqu'ici les elements sur le thread principal, avec le jeu
    /// de clefs complet : `localizedName` passe par LaunchServices, qui
    /// interroge TCC, et coute jusqu'a plusieurs secondes sur un dossier
    /// protege. Une recherche sur une grande arborescence figeait donc la
    /// fenetre, au point qu'on ne pouvait plus ni revenir en arriere ni
    /// changer de dossier.
    private func publish(_ q: NSMetadataQuery) {
        // Une seule construction a la fois : les lots arrivent plus vite
        // qu'ils ne se traitent, et les empiler ne montrerait rien de plus.
        guard !isBuilding else { needsRebuild = true; return }
        isBuilding = true

        // Seuls les chemins sont releves ici : NSMetadataQuery ne se consulte
        // que sur le thread principal. Le reste part en tache de fond.
        q.disableUpdates()
        let count = min(q.resultCount, Self.maxResults)
        var paths: [String] = []
        paths.reserveCapacity(count)
        for index in 0..<count {
            guard let item = q.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String
            else { continue }
            paths.append(path)
        }
        q.enableUpdates()

        let generation = self.generation
        builder.async { [weak self] in
            // Le meme jeu de clefs que le chargement d'un dossier, degraisse
            // pour les memes raisons mesurees.
            let keys = Set(FileItem.listingKeys)
            let items = paths.map { path -> FileItem in
                let url = URL(fileURLWithPath: path)
                return FileItem(url: url, values: try? url.resourceValues(forKeys: keys))
            }
            DispatchQueue.main.async {
                guard let self, generation == self.generation else { return }
                self.isBuilding = false
                self.onUpdate(items)
                if self.needsRebuild, let query = self.query {
                    self.needsRebuild = false
                    self.publish(query)
                }
            }
        }
    }
}
