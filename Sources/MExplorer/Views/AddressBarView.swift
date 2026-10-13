import SwiftUI
import AppKit

/// Barre d'adresse : navigation, fil d'Ariane cliquable (avec menus de sous-dossiers),
/// bascule en champ texte editable, et champ de recherche.
struct AddressBarView: View {

    @ObservedObject var model: WindowModel
    /// Redessine la vue quand la langue (ou un reglage global) change.
    @ObservedObject private var appSettings = AppSettings.shared
    @ObservedObject private var names = DisplayNameCache.shared
    @ObservedObject private var subfolders = SubfolderCache.shared
    @State private var editedPath: String = ""
    @FocusState private var pathFieldFocused: Bool
    @FocusState private var searchFocused: Bool

    private var tab: TabState { model.activeTab }

    var body: some View {
        HStack(spacing: 6) {
            navButton("chevron.left", enabled: tab.canGoBack, help: L("Precedent (Cmd [)")) { tab.goBack() }
                .contextMenu { historyMenu(entries: tab.backEntries()) }
            navButton("chevron.right", enabled: tab.canGoForward, help: L("Suivant (Cmd ])")) { tab.goForward() }
                .contextMenu { historyMenu(entries: tab.forwardEntries()) }
            navButton("chevron.up", enabled: tab.canGoUp, help: L("Dossier parent (Cmd Haut)")) { tab.goUp() }
            navButton("arrow.clockwise", enabled: true, help: L("Actualiser (Cmd R)")) { tab.reload() }

            addressField

            searchField
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
        .onChange(of: model.isAddressBarEditing) { _, editing in
            guard editing else { return }
            editedPath = tab.location.folderURL?.path ?? ""
            // Le champ de saisie n'existe qu'une fois la bascule faite : lui
            // demander le focus tout de suite laisse la saisie partir dans le
            // champ de recherche.
            DispatchQueue.main.async { pathFieldFocused = true }
        }
        .onChange(of: model.focusSearchToken) { _, _ in
            model.isAddressBarEditing = false
            DispatchQueue.main.async { searchFocused = true }
        }
    }

    // MARK: - Boutons de navigation

    private func navButton(_ symbol: String, enabled: Bool, help: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 24)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .help(help)
    }

    @ViewBuilder
    private func historyMenu(entries: [(index: Int, location: Location)]) -> some View {
        ForEach(entries.prefix(15), id: \.index) { entry in
            Button(entry.location.title) { tab.goToHistoryIndex(entry.index) }
        }
    }

    // MARK: - Fil d'Ariane / champ editable

    @ViewBuilder
    private var addressField: some View {
        ZStack {
            if model.isAddressBarEditing {
                TextField(L("Chemin"), text: $editedPath)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($pathFieldFocused)
                    .onSubmit { commitPath() }
                    .onExitCommand { model.isAddressBarEditing = false }
                    .padding(.horizontal, 8)
            } else {
                breadcrumb
            }
        }
        .frame(height: 24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private var breadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                Image(systemName: tab.location.symbol)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 7)
                    .padding(.trailing, 5)

                if let url = tab.location.folderURL {
                    ForEach(Array(Breadcrumb.segments(for: url).enumerated()), id: \.offset) { _, segment in
                        Button(segment.title) { tab.open(segment.url) }
                            .buttonStyle(.plain)
                            .font(.system(size: 12))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)

                        Menu {
                            // SwiftUI construit le contenu d'un menu a chaque rendu :
                            // il ne doit donc jamais lire le disque ici.
                            if let children = subfolders.children(of: segment.url) {
                                if children.isEmpty {
                                    Text(L("Aucun sous-dossier"))
                                } else {
                                    ForEach(children, id: \.self) { child in
                                        Button(child.lastPathComponent) { tab.open(child) }
                                    }
                                }
                            } else {
                                Text(L("Chargement..."))
                            }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .frame(width: 16)
                    }
                } else {
                    Text(tab.location.addressPath)
                        .font(.system(size: 12))
                        .padding(.horizontal, 4)
                }
                Spacer(minLength: 0)
            }
            .frame(height: 24)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.isAddressBarEditing = true }
        .help(L("Cliquer pour saisir un chemin (Cmd L)"))
    }

    private func commitPath() {
        let expanded = (editedPath as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded).standardizedFileURL
        model.isAddressBarEditing = false
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
            if isDir.boolValue { tab.open(url) } else { NSWorkspace.shared.open(url) }
        } else {
            model.requestAccess(for: url)
        }
    }

    // MARK: - Recherche

    private var searchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField(searchPlaceholder, text: $model.searchFieldText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($searchFocused)
                .onSubmit { model.runSearch(model.searchFieldText) }
                .onChange(of: model.searchFieldText) { _, value in
                    if tab.location.isFolder { tab.filterText = value }
                }
            if !model.searchFieldText.isEmpty {
                Button {
                    model.searchFieldText = ""
                    tab.filterText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 7)
        .frame(width: 230, height: 24)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private var searchPlaceholder: String {
        guard let url = tab.location.folderURL else { return L("Rechercher") }
        let name = names.name(for: url)
        return name.isEmpty ? L("Rechercher") : L("Rechercher dans %@", name)
    }
}

enum Breadcrumb {

    struct Segment: Hashable {
        let title: String
        let url: URL
    }

    static func segments(for url: URL) -> [Segment] {
        var result: [Segment] = []
        var current = url.standardizedFileURL
        while true {
            let name = current.path == "/" ? "Macintosh HD" : DisplayNameCache.shared.name(for: current)
            result.append(Segment(title: name.isEmpty ? "/" : name, url: current))
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent == current || current.path == "/" { break }
            current = parent
        }
        return result.reversed()
    }

    /// Sous-dossiers immediats, pour le menu du chevron (limite volontairement).
    /// A n'appeler que depuis SubfolderCache, hors du thread principal.
    static func subfolders(of url: URL) -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return [] }
        return contents
            .filter { u in
                let v = try? u.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
                return v?.isDirectory == true && v?.isPackage != true
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .prefix(60)
            .map { $0 }
    }
}


/// Cache asynchrone des sous-dossiers, pour les menus du fil d'Ariane.
final class SubfolderCache: ObservableObject {

    static let shared = SubfolderCache()

    @Published private(set) var version = 0

    private var cache: [String: [URL]] = [:]
    private var pending = Set<String>()
    private let queue = DispatchQueue(label: "com.jerome.mexplorer.subfolders", qos: .utility)

    private init() {}

    /// nil tant que la lecture n'a pas abouti ; la vue affiche alors "Chargement...".
    func children(of url: URL) -> [URL]? {
        let path = url.standardizedFileURL.path
        if let cached = cache[path] { return cached }
        guard !pending.contains(path) else { return nil }
        pending.insert(path)
        queue.async { [weak self] in
            let result = Breadcrumb.subfolders(of: url)
            DispatchQueue.main.async {
                guard let self else { return }
                self.pending.remove(path)
                self.cache[path] = result
                self.version &+= 1
            }
        }
        return nil
    }

    func invalidate() {
        cache.removeAll()
        version &+= 1
    }
}
