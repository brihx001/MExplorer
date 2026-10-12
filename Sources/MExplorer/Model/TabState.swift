import AppKit
import Combine

/// Etat complet d'un onglet : emplacement courant, historique, contenu, tri, selection.
final class TabState: NSObject, ObservableObject, Identifiable {

    let id = UUID()

    // MARK: - Publie

    @Published private(set) var location: Location
    @Published private(set) var title: String = ""
    /// Occupation du volume du dossier courant.
    @Published private(set) var volumeUsage: VolumeUsage?
    /// Taille cumulee des elements affiches.
    @Published private(set) var displayedSize: Int64 = 0
    /// Vrai si des tailles de dossiers manquent encore au total ci-dessus.
    @Published private(set) var displayedSizeIsPartial = false
    @Published private(set) var items: [FileItem] = [] { didSet { reindex() } }
    @Published private(set) var rows: [ListRow] = []
    @Published private(set) var isLoading = false
    /// Vrai tant que des tailles de dossiers restent a calculer.
    @Published private(set) var isMeasuringFolders = false
    @Published private(set) var loadError: DirectoryLoadError?
    @Published var settings: FolderViewSettings
    @Published var filterText: String = "" { didSet { if filterText != oldValue { rebuildRows() } } }
    @Published var selectedURLs: [URL] = []
    @Published private(set) var collapsedGroups: Set<String> = []

    /// Notifie les vues AppKit qu'il faut recharger (les @Published ne suffisent pas cote NSTableView).
    var onRowsChanged: (() -> Void)?
    /// Demande a la vue de restaurer la selection apres un rechargement.
    var onRequestSelection: (([URL]) -> Void)?

    // MARK: - Historique

    private(set) var history: [Location] = []
    private(set) var historyIndex: Int = -1

    var canGoBack: Bool { historyIndex > 0 }
    var canGoForward: Bool { historyIndex >= 0 && historyIndex < history.count - 1 }
    var canGoUp: Bool {
        guard let url = location.folderURL else { return false }
        return url.path != "/" && url.pathComponents.count > 1
    }

    // MARK: - Interne

    private var loadToken = 0
    /// Dernier dossier dont le contenu a ete demande, pour distinguer un
    /// changement de repertoire d'un simple rafraichissement.
    private var requestedFolder: URL?
    private var nameObserver: NSObjectProtocol?
    private var sizeObserver: NSObjectProtocol?
    private var hiddenObserver: NSObjectProtocol?
    private var watcher: DirectoryWatcher?
    private var search: SpotlightSearch?
    private var sizeToken = 0

    // MARK: - Init

    /// `loadsImmediately: false` cree un onglet inerte, utilise uniquement
    /// comme repli transitoire par WindowModel.
    init(location: Location, loadsImmediately: Bool = true) {
        self.location = location
        self.title = location.title
        self.settings = location.folderURL.map { FolderSettingsStore.shared.settings(for: $0) }
            ?? FolderSettingsStore.shared.defaults
        super.init()
        pushHistory(location)
        updateFreeSpace()
        nameObserver = NotificationCenter.default.addObserver(
            forName: DisplayNameCache.changed, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let refreshed = self.location.title
            if refreshed != self.title { self.title = refreshed }
        }
        sizeObserver = NotificationCenter.default.addObserver(
            forName: FolderSizeCalculator.didUpdate, object: nil, queue: .main
        ) { [weak self] _ in
            self?.applyFolderSizes()
        }
        hiddenObserver = NotificationCenter.default.addObserver(
            forName: AppSettings.hiddenItemsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.reload()
        }
        if loadsImmediately { load() }
    }

    deinit {
        watcher?.stop()
        search?.stop()
        if let nameObserver { NotificationCenter.default.removeObserver(nameObserver) }
        if let sizeObserver { NotificationCenter.default.removeObserver(sizeObserver) }
        if let hiddenObserver { NotificationCenter.default.removeObserver(hiddenObserver) }
    }

    // MARK: - Navigation

    func go(to newLocation: Location, addToHistory: Bool = true) {
        guard newLocation != location else { reload(); return }
        persistSettings()
        location = newLocation
        title = newLocation.title
        updateFreeSpace()
        settings = newLocation.folderURL.map { FolderSettingsStore.shared.settings(for: $0) }
            ?? FolderSettingsStore.shared.defaults
        filterText = ""
        collapsedGroups.removeAll()
        selectedURLs = []
        if addToHistory { pushHistory(newLocation) }
        load()
    }

    func open(_ url: URL) { go(to: .folder(url.standardizedFileURL)) }

    func goBack() {
        guard canGoBack else { return }
        historyIndex -= 1
        go(to: history[historyIndex], addToHistory: false)
    }

    func goForward() {
        guard canGoForward else { return }
        historyIndex += 1
        go(to: history[historyIndex], addToHistory: false)
    }

    func goUp() {
        guard let url = location.folderURL, canGoUp else { return }
        go(to: .folder(url.deletingLastPathComponent().standardizedFileURL))
    }

    /// Liste de l'historique recent pour le menu deroulant du bouton Precedent.
    func backEntries() -> [(index: Int, location: Location)] {
        guard historyIndex > 0 else { return [] }
        return (0..<historyIndex).reversed().map { ($0, history[$0]) }
    }

    func forwardEntries() -> [(index: Int, location: Location)] {
        guard historyIndex >= 0, historyIndex < history.count - 1 else { return [] }
        return ((historyIndex + 1)..<history.count).map { ($0, history[$0]) }
    }

    func goToHistoryIndex(_ index: Int) {
        guard history.indices.contains(index) else { return }
        historyIndex = index
        go(to: history[index], addToHistory: false)
    }

    private func pushHistory(_ loc: Location) {
        if historyIndex >= 0 && historyIndex < history.count - 1 {
            history.removeSubrange((historyIndex + 1)...)
        }
        history.append(loc)
        if history.count > 100 {
            history.removeFirst(history.count - 100)
        }
        historyIndex = history.count - 1
    }

    // MARK: - Chargement

    func reload() {
        load(preservingSelection: true)
    }

    private func load(preservingSelection: Bool = false) {
        // Sur un volume lent (partage reseau), le listing peut mettre plusieurs
        // secondes : on vide la liste des que le dossier change, sinon la barre
        // d'etat decrirait encore le dossier precedent. Ce vidage previent les
        // vues, donc il doit avoir lieu avant la prise du jeton : un
        // rechargement declenche en cascade garde ainsi un jeton coherent.
        if case .folder(let url) = location {
            if requestedFolder != url {
                requestedFolder = url
                if !items.isEmpty {
                    items = []
                    rebuildRows()
                }
            }
        } else {
            requestedFolder = nil
        }

        loadToken &+= 1
        let token = loadToken
        loadError = nil
        search?.stop()
        search = nil
        watcher?.stop()
        watcher = nil
        let previousSelection = preservingSelection ? selectedURLs : []

        switch location {
        case .folder(let url):
            isLoading = true
            startWatching(url)
            DirectoryLister.list(url, showHidden: AppSettings.shared.showHiddenItems, token: token) { [weak self] t, result in
                guard let self, t == self.loadToken else { return }
                self.isLoading = false
                switch result {
                case .success(let items):
                    self.items = items
                    self.rebuildRows()
                    self.loadDeferredMetadata(for: items, token: t)
                    self.requestFolderSizes()
                    if !previousSelection.isEmpty { self.onRequestSelection?(previousSelection) }
                case .failure(let error):
                    self.items = []
                    self.rows = []
                    self.loadError = error
                    self.onRowsChanged?()
                }
            }

        case .thisMac:
            isLoading = true
            items = SidebarCatalog.mountedVolumes()
            rebuildRows()
            SidebarCatalog.refreshVolumes { [weak self] volumes in
                guard let self, token == self.loadToken else { return }
                // FileItem lit des metadonnees potentiellement lentes (TCC) :
                // jamais sur le thread principal.
                DispatchQueue.global(qos: .userInitiated).async {
                    let quick = SidebarCatalog.quickAccessDefaults.map { FileItem(url: $0) }
                    DispatchQueue.main.async {
                        guard token == self.loadToken else { return }
                        self.isLoading = false
                        self.items = volumes + quick
                        self.rebuildRows()
                    }
                }
            }

        case .recents:
            isLoading = true
            let s = SpotlightSearch(onUpdate: { [weak self] found in
                guard let self, token == self.loadToken else { return }
                self.items = found
                self.rebuildRows()
            }, onFinish: { [weak self] in
                guard let self, token == self.loadToken else { return }
                self.isLoading = false
            })
            search = s
            s.start(text: "", scope: nil, includeContent: false)
            loadRecents(token: token)

        case .search(let text, let scope):
            isLoading = true
            items = []
            rebuildRows()
            let s = SpotlightSearch(onUpdate: { [weak self] found in
                guard let self, token == self.loadToken else { return }
                self.items = found
                self.rebuildRows()
            }, onFinish: { [weak self] in
                guard let self, token == self.loadToken else { return }
                self.isLoading = false
            })
            search = s
            s.start(text: text, scope: scope, includeContent: true)

        case .tag(let name):
            isLoading = true
            items = []
            rebuildRows()
            TagManager.itemsWithTag(name) { [weak self] found in
                guard let self, token == self.loadToken else { return }
                self.isLoading = false
                self.items = found
                self.rebuildRows()
            }
        }
    }

    private func loadRecents(token: Int) {
        DispatchQueue.global(qos: .userInitiated).async {
            let cutoff = Date().addingTimeInterval(-30 * 86_400)
            var found: [FileItem] = []
            for root in [SidebarCatalog.home] {
                guard let e = FileManager.default.enumerator(
                    at: root, includingPropertiesForKeys: FileItem.resourceKeys,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants],
                    errorHandler: { _, _ in true }) else { continue }
                for case let url as URL in e {
                    guard let v = try? url.resourceValues(forKeys: Set(FileItem.resourceKeys)) else { continue }
                    if v.isDirectory == true { continue }
                    if let d = v.contentModificationDate, d > cutoff {
                        found.append(FileItem(url: url, values: v))
                    }
                    if found.count > 800 { break }
                }
            }
            let sorted = found.sorted { ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast) }
            DispatchQueue.main.async { [weak self] in
                guard let self, token == self.loadToken else { return }
                self.isLoading = false
                self.items = Array(sorted.prefix(500))
                self.rebuildRows()
            }
        }
    }

    /// Seconde passe : tags, labels et noms localises sont lus hors du
    /// chargement principal pour ne pas retarder l'affichage.
    private func loadDeferredMetadata(for items: [FileItem], token: Int) {
        guard items.count <= 3000, !items.isEmpty else { return }
        let directories = items.filter { $0.isNavigableContainer }

        DispatchQueue.global(qos: .utility).async {
            var tagged: [(FileItem, [String], Int)] = []
            for item in items {
                guard let v = try? item.url.resourceValues(forKeys: [.tagNamesKey, .labelNumberKey]) else { continue }
                let tags = v.tagNames ?? []
                let label = v.labelNumber ?? 0
                if !tags.isEmpty || label != 0 { tagged.append((item, tags, label)) }
            }
            if !tagged.isEmpty {
                DispatchQueue.main.async { [weak self] in
                    guard let self, token == self.loadToken else { return }
                    for (item, tags, label) in tagged {
                        item.tagNames = tags
                        item.labelNumber = label
                    }
                    self.onRowsChanged?()
                }
            }

            // Seuls les dossiers portent un nom localise different du nom brut
            // (Desktop -> Bureau). Au-dela de 300, on n'en vaut pas le cout.
            guard directories.count <= 300 else { return }
            var renamed: [(FileItem, String)] = []
            for item in directories {
                guard let name = try? item.url.resourceValues(forKeys: [.localizedNameKey]).localizedName,
                      !name.isEmpty, name != item.displayName else { continue }
                renamed.append((item, name))
            }
            guard !renamed.isEmpty else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, token == self.loadToken else { return }
                for (item, name) in renamed { item.displayName = name }
                self.rebuildRows()
            }
        }
    }

    // MARK: - Taille des dossiers

    /// Vrai si la colonne Taille est affichee et doit montrer la taille reelle
    /// des dossiers.
    private var wantsFolderSizes: Bool {
        settings.viewMode == .details
            && settings.calculateFolderSizes
            && settings.visibleColumns.contains(.size)
    }

    /// Lance (ou arrete) le calcul des tailles pour le contenu affiche.
    func requestFolderSizes() {
        guard wantsFolderSizes else {
            if isMeasuringFolders {
                FolderSizeCalculator.shared.cancel()
                isMeasuringFolders = false
            }
            return
        }
        let folders = items.filter { $0.isDirectory }
        applyFolderSizes()
        guard !folders.isEmpty else {
            // Sans cela, quitter un dossier charge de sous-dossiers pour un
            // dossier qui n'en a aucun laisserait l'ancienne file tourner.
            FolderSizeCalculator.shared.cancel()
            isMeasuringFolders = false
            return
        }
        FolderSizeCalculator.shared.request(folders.map { ($0.url, $0.modificationDate) })
        isMeasuringFolders = FolderSizeCalculator.shared.isRunning
    }

    /// Reporte les tailles connues sur les elements affiches.
    private func applyFolderSizes() {
        var changed = false
        for item in items where item.isDirectory {
            let size = FolderSizeCalculator.shared.cachedSize(for: item.url, modified: item.modificationDate)
            if item.computedFolderSize != size {
                item.computedFolderSize = size
                changed = true
            }
        }
        isMeasuringFolders = FolderSizeCalculator.shared.isRunning
        guard changed else { return }
        // Le tri par taille doit suivre les valeurs qui arrivent.
        if settings.sortKey == .size {
            rebuildRows()
        } else {
            recomputeDisplayedSize()
            onRowsChanged?()
        }
    }

    private func startWatching(_ url: URL) {
        let w = DirectoryWatcher { [weak self] in self?.reload() }
        w.watch(url)
        watcher = w
    }

    // MARK: - Tri / regroupement / filtre

    func rebuildRows() {
        var visible = items
        if !AppSettings.shared.showHiddenItems && !location.isFolder {
            visible = visible.filter { !$0.isHidden }
        }
        let needle = filterText.trimmingCharacters(in: .whitespaces)
        if !needle.isEmpty {
            visible = visible.filter { $0.displayName.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
        rows = Arranger.rows(from: visible, settings: settings, collapsedGroups: collapsedGroups)
        recomputeDisplayedSize()
        onRowsChanged?()
    }

    func update(_ mutate: (inout FolderViewSettings) -> Void) {
        var s = settings
        mutate(&s)
        settings = s
        persistSettings()
        rebuildRows()
        requestFolderSizes()
    }

    /// Change le tri, en inversant le sens si la meme colonne est reselectionnee.
    func toggleSort(_ key: SortKey) {
        var s = settings
        if s.sortKey == key { s.ascending.toggle() } else { s.sortKey = key; s.ascending = true }
        settings = s
        persistSettings()
        rebuildRows()
    }

    /// Le reglage est global : toutes les fenetres et tous les onglets
    /// se rechargent (voir AppSettings.hiddenItemsChanged).
    func setShowHidden(_ value: Bool) {
        AppSettings.shared.showHiddenItems = value
    }

    var showsHiddenItems: Bool { AppSettings.shared.showHiddenItems }

    func toggleGroup(_ key: String) {
        if collapsedGroups.contains(key) { collapsedGroups.remove(key) } else { collapsedGroups.insert(key) }
        rebuildRows()
    }

    private func persistSettings() {
        if let url = location.folderURL {
            FolderSettingsStore.shared.store(settings, for: url)
        }
    }

    // MARK: - Selection

    /// Index reconstruit a chaque chargement : `selectedItems` est lu a chaque
    /// rendu de la barre de commandes, il ne doit rien recalculer.
    private var itemsByURL: [URL: FileItem] = [:]

    private func reindex() {
        itemsByURL = Dictionary(items.map { ($0.url, $0) }, uniquingKeysWith: { a, _ in a })
        // Un element supprime ou renomme ne doit pas rester "selectionne" :
        // la barre d'etat annoncerait une selection fantome et les commandes
        // viseraient un chemin qui n'existe plus.
        let surviving = selectedURLs.filter { itemsByURL[$0] != nil }
        if surviving.count != selectedURLs.count { selectedURLs = surviving }
    }

    var selectedItems: [FileItem] { selectedURLs.compactMap { itemsByURL[$0] } }

    var hasSelection: Bool { !selectedURLs.isEmpty }

    func item(at url: URL) -> FileItem? { itemsByURL[url] }
    /// Occupation du volume, lue hors du thread principal : sur un volume
    /// reseau ou endormi, la lecture peut prendre plusieurs secondes.
    private func updateFreeSpace() {
        guard let url = location.folderURL else { volumeUsage = nil; return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let usage = VolumeUsage.read(for: url)
            DispatchQueue.main.async { self?.volumeUsage = usage }
        }
    }

    /// Taille cumulee des elements affiches, pour la barre d'etat.
    ///
    /// Les dossiers dont la taille n'est pas encore calculee sont comptes pour
    /// zero et signales par `displayedSizeIsPartial`.
    private func recomputeDisplayedSize() {
        var total: Int64 = 0
        var partial = false
        for row in rows {
            guard let item = row.item else { continue }
            if let size = item.effectiveSize { total += size } else { partial = true }
        }
        if total != displayedSize { displayedSize = total }
        if partial != displayedSizeIsPartial { displayedSizeIsPartial = partial }
    }

    func selectAll() {
        selectedURLs = rows.compactMap { $0.item?.url }
        onRequestSelection?(selectedURLs)
    }

    // MARK: - Taille de dossier a la demande

    func computeSize(for item: FileItem, completion: @escaping (Int64) -> Void) {
        sizeToken &+= 1
        let token = sizeToken
        DirectoryLister.folderSize(item.url, cancelled: { [weak self] in self?.sizeToken != token }) { size in
            item.computedFolderSize = size
            completion(size)
        }
    }
}
