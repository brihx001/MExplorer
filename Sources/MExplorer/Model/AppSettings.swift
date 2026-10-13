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

    /// L'utilisateur a demande a ne plus voir la proposition d'acces au disque.
    var skipDiskAccessPrompt: Bool {
        get { Self.flag("skipDiskAccessPrompt", false) }
        set { d.set(newValue, forKey: "skipDiskAccessPrompt") }
    }

    /// Session restauree au lancement : liste des chemins ouverts par onglet.
    var lastSessionPaths: [String] {
        get { d.stringArray(forKey: "lastSessionPaths") ?? [] }
        set { d.set(newValue, forKey: "lastSessionPaths") }
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

    var showHiddenItems: Bool {
        get { d.bool(forKey: "showHiddenItems") }
        set {
            guard newValue != showHiddenItems else { return }
            d.set(newValue, forKey: "showHiddenItems")
            NotificationCenter.default.post(name: Self.hiddenItemsChanged, object: nil)
        }
    }

    func toggleHiddenItems() { showHiddenItems.toggle() }
}
