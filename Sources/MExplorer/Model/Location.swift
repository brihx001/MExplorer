import AppKit

/// Ce qu'un onglet peut afficher. Un dossier dans la majorite des cas, mais aussi
/// une recherche, un tag ou la page "Ce Mac" (equivalent de "Ce PC" de Windows).
enum Location: Hashable {
    case folder(URL)
    case search(text: String, scope: URL?)
    case tag(String)
    case recents
    case thisMac

    var folderURL: URL? { if case .folder(let u) = self { return u }; return nil }

    var isFolder: Bool { folderURL != nil }

    var title: String {
        switch self {
        case .folder(let url):
            if url.path == "/" { return "Macintosh HD" }
            return DisplayNameCache.shared.name(for: url)
        case .search(let text, let scope):
            let base = text.isEmpty ? "Recherche" : "\"\(text)\""
            if let scope { return "\(base) dans \(scope.lastPathComponent)" }
            return "\(base) sur ce Mac"
        case .tag(let t): return t
        case .recents: return "Recents"
        case .thisMac: return "Ce Mac"
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
            return "Resultats de la recherche pour \"\(text)\"" + (scope.map { " dans \($0.lastPathComponent)" } ?? "")
        case .tag(let t): return "Tag : \(t)"
        case .recents: return "Recents"
        case .thisMac: return "Ce Mac"
        }
    }
}
