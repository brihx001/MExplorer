import AppKit
import Combine

/// Preferences globales de l'application.
final class AppSettings: ObservableObject {

    static let shared = AppSettings()
    private let d = UserDefaults.standard

    private init() {}

    /// Lecture avec valeur par defaut explicite.
    ///
    /// `register(defaults:)` ne convient pas ici : les proprietes stockees sont
    /// initialisees avant le corps de `init`, donc avant l'enregistrement, et
    /// toutes les options seraient parties a `false`.
    private static func flag(_ key: String, _ defaultValue: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? defaultValue
    }

    @Published var showFileExtensions: Bool = AppSettings.flag("showFileExtensions", true) {
        didSet { d.set(showFileExtensions, forKey: "showFileExtensions") }
    }
    @Published var singleClickToOpen: Bool = AppSettings.flag("singleClickToOpen", false) {
        didSet { d.set(singleClickToOpen, forKey: "singleClickToOpen") }
    }
    @Published var confirmPermanentDelete: Bool = AppSettings.flag("confirmPermanentDelete", true) {
        didSet { d.set(confirmPermanentDelete, forKey: "confirmPermanentDelete") }
    }
    @Published var openFoldersInNewTab: Bool = AppSettings.flag("openFoldersInNewTab", false) {
        didSet { d.set(openFoldersInNewTab, forKey: "openFoldersInNewTab") }
    }

    // Visibilite des volets : memorisee comme dans l'Explorateur.
    var showSidebar: Bool {
        get { Self.flag("showSidebar", true) }
        set { d.set(newValue, forKey: "showSidebar") }
    }
    var showDetailsPane: Bool {
        get { d.bool(forKey: "showDetailsPane") }
        set { d.set(newValue, forKey: "showDetailsPane") }
    }
    var showPreviewPane: Bool {
        get { d.bool(forKey: "showPreviewPane") }
        set { d.set(newValue, forKey: "showPreviewPane") }
    }

    /// Composition de la barre de commandes.
    ///
    /// Un identifiant inconnu est ignore et les elements non retirables sont
    /// toujours presents : une version qui en ajouterait ne doit ni perdre le
    /// reglage ni laisser une barre inutilisable.
    var commandBarItems: [CommandBarItem] {
        get {
            guard let stored = d.stringArray(forKey: "commandBarItems") else { return CommandBarItem.defaults }
            var items = stored.compactMap { CommandBarItem(rawValue: $0) }
            for item in CommandBarItem.allCases where !item.isRemovable && !items.contains(item) {
                items.append(item)
            }
            return items.isEmpty ? CommandBarItem.defaults : items
        }
        set {
            d.set(newValue.map(\.rawValue), forKey: "commandBarItems")
            objectWillChange.send()
            NotificationCenter.default.post(name: Self.commandBarChanged, object: nil)
        }
    }

    static let commandBarChanged = Notification.Name("com.jerome.mexplorer.commandBarChanged")

    func resetCommandBar() { commandBarItems = CommandBarItem.defaults }

    /// Dossiers vises recemment par « Deplacer vers » ou « Copier vers »,
    /// du plus recent au plus ancien. Dix suffisent : au-dela, le sous-menu
    /// devient une liste a lire plutot qu'un raccourci.
    var recentDestinations: [String] {
        get { d.stringArray(forKey: "recentDestinations") ?? [] }
        set { d.set(Array(newValue.prefix(10)), forKey: "recentDestinations") }
    }

    func rememberDestination(_ url: URL) {
        let path = url.standardizedFileURL.path
        var list = recentDestinations.filter { $0 != path }
        list.insert(path, at: 0)
        recentDestinations = list
    }

    /// Dernier motif de selection saisi, repropose au prochain appel : on
    /// affine rarement du premier coup.
    var lastSelectionPattern: String {
        get { d.string(forKey: "lastSelectionPattern") ?? "" }
        set { d.set(newValue, forKey: "lastSelectionPattern") }
    }

    /// L'utilisateur a demande a ne plus voir la proposition d'acces au disque.
    var skipDiskAccessPrompt: Bool {
        get { Self.flag("skipDiskAccessPrompt", false) }
        set { d.set(newValue, forKey: "skipDiskAccessPrompt") }
    }

    /// Session restauree au lancement : une liste de chemins par fenetre.
    ///
    /// Les listes sont aplaties pour UserDefaults, qui ne stocke pas de
    /// tableau de tableaux de maniere lisible : une chaine vide separe deux
    /// fenetres. Un chemin etant toujours absolu, il ne peut pas etre vide.
    var lastSessionWindows: [[String]] {
        get {
            let flat = d.stringArray(forKey: "lastSessionWindows") ?? []
            if flat.isEmpty {
                // Reprise de l'ancien reglage, qui ne gardait qu'une fenetre.
                let legacy = d.stringArray(forKey: "lastSessionPaths") ?? []
                return legacy.isEmpty ? [] : [legacy]
            }
            var windows: [[String]] = []
            var current: [String] = []
            for entry in flat {
                if entry.isEmpty {
                    windows.append(current)
                    current = []
                } else {
                    current.append(entry)
                }
            }
            if !current.isEmpty { windows.append(current) }
            return windows
        }
        set {
            var flat: [String] = []
            for (index, window) in newValue.enumerated() {
                if index > 0 { flat.append("") }
                flat.append(contentsOf: window)
            }
            d.set(flat, forKey: "lastSessionWindows")
        }
    }

    /// Nombre de visites par dossier, pour la section « Dossiers frequents ».
    ///
    /// Les compteurs sont divises par deux quand le total s'emballe : un
    /// dossier tres visite il y a six mois ne doit pas rester en tete pour
    /// toujours.
    var folderVisits: [String: Int] {
        get { (d.dictionary(forKey: "folderVisits") as? [String: Int]) ?? [:] }
        set { d.set(newValue, forKey: "folderVisits") }
    }

    func recordVisit(_ url: URL) {
        let path = url.standardizedFileURL.path
        // Le dossier personnel et la racine faussent le classement : on y
        // passe pour aller ailleurs.
        guard path != SidebarCatalog.home.path, path != "/" else { return }
        var visits = folderVisits
        visits[path, default: 0] += 1
        if visits.values.reduce(0, +) > 2000 {
            visits = visits.compactMapValues { $0 / 2 }.filter { $0.value > 0 }
        }
        let before = frequentFolders()
        folderVisits = visits
        // La barre laterale n'est refaite que si le classement a bouge :
        // la rebatir a chaque navigation replierait l'arborescence.
        if frequentFolders() != before {
            NotificationCenter.default.post(name: Self.favoritesChanged, object: nil)
        }
    }

    /// Les dossiers les plus visites qui existent encore et ne sont pas deja
    /// en acces rapide.
    func frequentFolders(limit: Int = 6) -> [URL] {
        let favorites = Set(favoritePaths)
        return folderVisits
            .filter { $0.value >= 3 && !favorites.contains($0.key) }
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .lazy
            .map { URL(fileURLWithPath: $0.key) }
            .filter { url in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                    && isDirectory.boolValue
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Favoris de la barre laterale (Acces rapide).
    var favoritePaths: [String] {
        get {
            if let stored = d.stringArray(forKey: "favoritePaths") { return stored }
            return SidebarCatalog.quickAccessDefaults.map(\.path)
        }
        set { d.set(newValue, forKey: "favoritePaths") }
    }

    /// `index` place le favori a cet endroit de la liste (depot entre deux
    /// lignes de l'acces rapide) ; nil l'ajoute a la fin.
    func addFavorite(_ url: URL, at index: Int? = nil) {
        var list = favoritePaths
        guard !list.contains(url.path) else { return }
        if let index, index >= 0, index <= list.count {
            list.insert(url.path, at: index)
        } else {
            list.append(url.path)
        }
        favoritePaths = list
        NotificationCenter.default.post(name: Self.favoritesChanged, object: nil)
    }

    /// Les Applications ont rejoint les favoris par defaut apres coup : une
    /// liste deja enregistree ne les aurait jamais vues. On les y ajoute une
    /// seule fois, juste apres le dossier personnel.
    func addApplicationsFavoriteOnce() {
        let key = "didAddApplicationsFavorite"
        guard !d.bool(forKey: key) else { return }
        d.set(true, forKey: key)
        guard d.stringArray(forKey: "favoritePaths") != nil else { return }
        addFavorite(SidebarCatalog.applications, at: 1)
    }

    func removeFavorite(_ url: URL) {
        favoritePaths = favoritePaths.filter { $0 != url.path }
        NotificationCenter.default.post(name: Self.favoritesChanged, object: nil)
    }

    func moveFavorite(from: Int, to: Int) {
        var list = favoritePaths
        guard list.indices.contains(from) else { return }
        let item = list.remove(at: from)
        list.insert(item, at: min(to, list.count))
        favoritePaths = list
        NotificationCenter.default.post(name: Self.favoritesChanged, object: nil)
    }

    static let favoritesChanged = Notification.Name("com.jerome.mexplorer.favoritesChanged")

    /// Affichage des elements masques. Volontairement global et non par
    /// dossier : c'est la convention du Finder comme de l'Explorateur, et un
    /// reglage par dossier donne l'impression que l'option ne tient pas.
    static let hiddenItemsChanged = Notification.Name("com.jerome.mexplorer.hiddenItemsChanged")

    @Published var showHiddenItems: Bool = AppSettings.flag("showHiddenItems", false) {
        didSet {
            guard showHiddenItems != oldValue else { return }
            d.set(showHiddenItems, forKey: "showHiddenItems")
            NotificationCenter.default.post(name: Self.hiddenItemsChanged, object: nil)
        }
    }

    func toggleHiddenItems() { showHiddenItems.toggle() }

    // MARK: - Langue

    /// Langue de l'interface. `system` suit la langue du Mac.
    @Published var language: AppLanguage = AppSettings.storedLanguage {
        didSet {
            guard language != oldValue else { return }
            d.set(language.rawValue, forKey: "language")
            L10n.apply(language)
        }
    }

    // MARK: - Theme

    /// Apparence de l'application. `system` suit le reglage de macOS.
    @Published var theme: AppTheme = AppSettings.storedTheme {
        didSet {
            guard theme != oldValue else { return }
            d.set(theme.rawValue, forKey: "theme")
            theme.apply()
        }
    }

    private static var storedTheme: AppTheme {
        UserDefaults.standard.string(forKey: "theme")
            .flatMap(AppTheme.init(rawValue:)) ?? .system
    }

    private static var storedLanguage: AppLanguage {
        UserDefaults.standard.string(forKey: "language")
            .flatMap(AppLanguage.init(rawValue:)) ?? .system
    }
}

