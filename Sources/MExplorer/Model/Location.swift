import AppKit

/// Ce qu'un onglet peut afficher. Un dossier dans la majorite des cas, mais aussi
/// une recherche, un tag ou la page L("Ce Mac") (equivalent de "Ce PC" de Windows).
enum Location: Hashable {
    case folder(URL)
    case search(text: String, scope: URL?)
    case tag(String)
    case recents
    case thisMac

    var folderURL: URL? { if case .folder(let u) = self { return u }; return nil }

    /// Le meme emplacement, lien resolu.
    ///
    /// `contentsOfDirectory(at:)` ne suit pas les liens : sur un lien
    /// symbolique vers un dossier, elle repond ENOTDIR et le dossier parait
    /// vide. C'est le cas du dossier OneDrive pose dans le dossier personnel,
    /// qui n'est qu'un lien vers `~/Library/CloudStorage`. Le Finder montre lui
    /// aussi le chemin reel.
    var resolved: Location {
        guard case .folder(let url) = self else { return self }
        return .folder(Self.resolveFolder(url))
    }

    /// Dossier vise par `url`, en resolvant lien symbolique et alias.
    /// Rend `url` telle quelle si c'est deja un dossier, ou si la cible n'en
    /// est pas un : mieux vaut l'erreur d'origine qu'un detour inattendu.
    static func resolveFolder(_ url: URL) -> URL {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isAliasFileKey]
        let values = try? url.resourceValues(forKeys: keys)
        guard values?.isDirectory != true else { return url }

        if values?.isAliasFile == true,
           let target = try? URL(resolvingAliasFileAt: url, options: [.withoutUI]),
           isDirectory(target) {
            return target
        }
        let resolved = url.resolvingSymlinksInPath()
        if resolved != url, isDirectory(resolved) { return resolved }
        return url
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    var isFolder: Bool { folderURL != nil }

    var title: String {
        switch self {
        case .folder(let url):
            if url.path == "/" { return "Macintosh HD" }
            return DisplayNameCache.shared.name(for: url)
        case .search(let text, let scope):
            let base = text.isEmpty ? L("Recherche") : "\"\(text)\""
            if let scope { return L("%@ dans %@", base, scope.lastPathComponent) }
            return L("%@ sur ce Mac", base)
        case .tag(let t): return t
        case .recents: return L("Recents")
        case .thisMac: return L("Ce Mac")
        }
    }

    var symbol: String {
        switch self {
        case .folder(let url): return SidebarCatalog.symbol(for: url)
        case .search: return "magnifyingglass"
        case .tag: return "tag"
        case .recents: return "clock"
        case .thisMac: return "desktopcomputer"
        }
    }

    /// Chemin affiche dans la barre d'adresse.
    var addressPath: String {
        switch self {
        case .folder(let url): return url.path
        case .search(let text, let scope):
            let base = L("Resultats de la recherche pour \"%@\"", text)
            return base + (scope.map { L(" dans %@", $0.lastPathComponent) } ?? "")
        case .tag(let t): return L("Tag : %@", t)
        case .recents: return L("Recents")
        case .thisMac: return L("Ce Mac")
        }
    }
}
