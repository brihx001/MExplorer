import AppKit

/// Noeud de l'arborescence laterale. Les enfants des dossiers sont charges
/// paresseusement a la premiere expansion.
final class SidebarNode: NSObject {

    enum Kind { case header, favorite, folder, volume, tag, special }

    let kind: Kind
    let symbol: String
    let location: Location?
    let url: URL?
    weak var parent: SidebarNode?

    /// nil tant que le contenu n'a pas ete lu.
    var children: [SidebarNode]?
    var isLoading = false
    /// Volume amovible : la ligne affiche alors un bouton d'ejection.
    var isEjectable = false
    /// En-tete "Acces rapide" : accepte le depot de dossiers a mettre en favori.
    var isQuickAccess = false
    /// En-tete d'une arborescence reelle ("Ce Mac", "Emplacements") : c'est la
    /// qu'un dossier est revele, pas dans les raccourcis de l'acces rapide.
    var isRealTree = false

    /// Vrai si le noeud se trouve sous l'en-tete "Acces rapide".
    var isUnderQuickAccess: Bool {
        var node: SidebarNode? = self
        while let current = node {
            if current.isQuickAccess { return true }
            node = current.parent
        }
        return false
    }

    /// Titre fixe (en-tetes, tags, noms imposes). Pour un dossier sans titre
    /// impose, le libelle est relu a chaque affichage depuis DisplayNameCache :
    /// reconstruire l'arbre a chaque nom resolu declenchait une boucle de
    /// rafraichissement.
    private let fixedTitle: String?

    var title: String {
        if let fixedTitle { return fixedTitle }
        guard let url else { return "" }
        return DisplayNameCache.shared.name(for: url)
    }

    init(kind: Kind, title: String?, symbol: String, location: Location? = nil, url: URL? = nil) {
        self.kind = kind
        self.fixedTitle = title
        self.symbol = symbol
        self.location = location
        self.url = url
        super.init()
    }

    convenience init(folderAt url: URL, kind: Kind = .folder, title: String? = nil) {
        self.init(kind: kind,
                  title: title,
                  symbol: SidebarCatalog.symbol(for: url),
                  location: .folder(url),
                  url: url)
    }

    var isHeader: Bool { kind == .header }

    var isExpandable: Bool {
        switch kind {
        case .header: return true
        case .favorite, .folder, .volume: return url.map { Self.hasSubdirectories($0) } ?? false
        case .tag, .special: return false
        }
    }

    /// Charge les sous-dossiers (appel synchrone, volontairement borne).
    func loadChildrenIfNeeded() {
        guard children == nil else { return }
        guard let url, kind != .header else { children = children ?? []; return }
        children = Self.subfolders(of: url).map { child in
            let node = SidebarNode(folderAt: child)
            node.parent = self
            return node
        }
    }

    /// Relit le dossier et fusionne avec les noeuds existants : ceux qui sont
    /// toujours la sont conserves tels quels, pour que NSOutlineView garde leur
    /// etat deplie. Renvoie vrai si la liste a change.
    @discardableResult
    func refreshChildren() -> Bool {
        guard let url, kind != .header else { return false }
        let previous = children ?? []
        var byPath: [String: SidebarNode] = [:]
        for node in previous {
            if let u = node.url { byPath[u.standardizedFileURL.path] = node }
        }

        var merged: [SidebarNode] = []
        for child in Self.subfolders(of: url) {
            if let existing = byPath[child.standardizedFileURL.path] {
                merged.append(existing)
            } else {
                let node = SidebarNode(folderAt: child)
                node.parent = self
                merged.append(node)
            }
        }

        let changed = merged.count != previous.count
            || zip(merged, previous).contains { $0 !== $1 }
        children = merged
        Self.noteSubdirectories(url, found: !merged.isEmpty)
        return changed
    }

    func invalidateChildren() {
        children = nil
    }

    /// Sous-dossiers visibles, tries comme le Finder.
    private static func subfolders(of url: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )) ?? []
        return contents.filter { child in
            let v = try? child.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            return v?.isDirectory == true && v?.isPackage != true
        }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    // MARK: - Detection de sous-dossiers (asynchrone)

    static let expandabilityChanged = Notification.Name("com.jerome.mexplorer.expandabilityChanged")

    private static var subdirCache: [String: Bool] = [:]
    private static var probing = Set<String>()

    /// Enumerer un dossier peut bloquer (volume reseau, montage virtuel) :
    /// on repond de facon optimiste et on corrige des que la sonde de fond repond.
    static func hasSubdirectories(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        if let cached = subdirCache[path] { return cached }
        guard !probing.contains(path) else { return true }

        // Les volumes non locaux ne sont jamais sondes : trop risque.
        if let local = try? url.resourceValues(forKeys: [.volumeIsLocalKey]).volumeIsLocal, local == false {
            subdirCache[path] = true
            return true
        }

        probing.insert(path)
        DispatchQueue.global(qos: .utility).async {
            let found = probe(url)
            DispatchQueue.main.async {
                subdirCache[path] = found
                probing.remove(path)
                NotificationCenter.default.post(name: expandabilityChanged, object: path)
            }
        }
        return true
    }

    private static func probe(_ url: URL) -> Bool {
        guard let iterator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants],
            errorHandler: { _, _ in false }
        ) else { return false }

        var scanned = 0
        for case let child as URL in iterator {
            scanned += 1
            let v = try? child.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            if v?.isDirectory == true && v?.isPackage != true { return true }
            if scanned > 400 { break }
        }
        return false
    }

    /// Met a jour le cache d'expansion apres une lecture reelle du dossier :
    /// un dossier qui vient de recevoir son premier sous-dossier doit devenir
    /// depliable sans attendre une nouvelle sonde.
    static func noteSubdirectories(_ url: URL, found: Bool) {
        subdirCache[url.standardizedFileURL.path] = found
    }

    static func flushSubdirectoryCache() {
        subdirCache.removeAll()
        probing.removeAll()
    }
}
