import AppKit
import Combine

/// Modele d'une fenetre : la collection d'onglets, l'onglet actif, les panneaux,
/// et le point d'entree unique de toutes les commandes de l'interface.
final class WindowModel: ObservableObject {

    @Published private(set) var tabs: [TabState] = []
    @Published private(set) var selectedTabIndex: Int = 0
    @Published var showDetailsPane = AppSettings.shared.showDetailsPane {
        didSet { AppSettings.shared.showDetailsPane = showDetailsPane }
    }
    @Published var showPreviewPane = AppSettings.shared.showPreviewPane {
        didSet { AppSettings.shared.showPreviewPane = showPreviewPane }
    }
    @Published var showSidebar = AppSettings.shared.showSidebar {
        didSet { AppSettings.shared.showSidebar = showSidebar }
    }
    @Published var isAddressBarEditing = false
    @Published var searchFieldText = ""
    /// Incremente pour demander le focus clavier au champ de recherche (Cmd F).
    @Published var focusSearchToken = 0

    weak var window: NSWindow?

    /// Notifie les controleurs AppKit d'un changement d'onglet actif.
    var onActiveTabChanged: ((TabState) -> Void)?
    /// Demande a la vue liste de passer un element en edition de nom.
    var onBeginRename: ((URL) -> Void)?
    /// Demande le focus clavier sur la liste de fichiers.
    var onFocusFileList: (() -> Void)?

    private var tabObserver: AnyCancellable?
    private var notificationObservers: [NSObjectProtocol] = []

    /// Le repli n'est atteint que pendant le bref instant ou une fenetre perd
    /// son dernier onglet au profit d'une autre fenetre, juste avant de se
    /// fermer : sans lui, l'interface lirait un tableau vide.
    private lazy var fallbackTab = TabState(location: .folder(SidebarCatalog.home), loadsImmediately: false)

    var activeTab: TabState {
        guard !tabs.isEmpty else { return fallbackTab }
        return tabs[min(max(selectedTabIndex, 0), tabs.count - 1)]
    }
    var undoManager: UndoManager? { window?.undoManager }

    // MARK: - Init

    init(initial: Location = .folder(SidebarCatalog.home)) {
        tabs = [TabState(location: initial)]
        setUp()
    }

    /// Fenetre creee pour accueillir un onglet detache d'une autre fenetre.
    init(adopting tab: TabState) {
        tabs = [tab]
        setUp()
    }

    private func setUp() {
        observeActiveTab()
        let center = NotificationCenter.default
        notificationObservers.append(center.addObserver(
            forName: FileOperations.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.tabs.forEach { $0.reload() }
        })
    }

    deinit { notificationObservers.forEach { NotificationCenter.default.removeObserver($0) } }

    private func observeActiveTab() {
        tabObserver = activeTab.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
        onActiveTabChanged?(activeTab)
    }

    // MARK: - Onglets

    @discardableResult
    func newTab(at location: Location? = nil, select: Bool = true) -> TabState {
        let target = location ?? .folder(activeTab.location.folderURL ?? SidebarCatalog.home)
        let tab = TabState(location: target)
        tabs.insert(tab, at: selectedTabIndex + 1)
        if select { selectTab(at: selectedTabIndex + 1) } else { objectWillChange.send() }
        return tab
    }

    func duplicateTab() {
        newTab(at: activeTab.location)
    }

    func closeTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        guard tabs.count > 1 else {
            window?.performClose(nil)
            return
        }
        tabs.remove(at: index)
        selectTab(at: min(index, tabs.count - 1))
    }

    func closeActiveTab() { closeTab(at: selectedTabIndex) }

    func closeOtherTabs() {
        let keep = activeTab
        tabs = [keep]
        selectTab(at: 0)
    }

    func closeTabsToTheRight() {
        guard selectedTabIndex < tabs.count - 1 else { return }
        tabs.removeSubrange((selectedTabIndex + 1)...)
        objectWillChange.send()
    }

    func selectTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        selectedTabIndex = index
        observeActiveTab()
        onActiveTabChanged?(activeTab)
    }

    func selectNextTab() { selectTab(at: (selectedTabIndex + 1) % tabs.count) }
    func selectPreviousTab() { selectTab(at: (selectedTabIndex - 1 + tabs.count) % tabs.count) }

    // MARK: - Deplacement entre fenetres

    /// Retire un onglet sans le fermer : il poursuit sa vie dans une autre
    /// fenetre, avec son historique et ses reglages.
    func release(_ tab: TabState) {
        guard let index = tabs.firstIndex(where: { $0 === tab }) else { return }
        tabs.remove(at: index)
        if tabs.isEmpty {
            // Plus rien a montrer : la fenetre se ferme.
            DispatchQueue.main.async { [weak self] in self?.window?.performClose(nil) }
            return
        }
        selectTab(at: min(index, tabs.count - 1))
    }

    /// Accueille un onglet venu d'une autre fenetre.
    func adopt(_ tab: TabState, from source: WindowModel, at index: Int) {
        guard source !== self, !tabs.contains(where: { $0 === tab }) else { return }
        let position = min(max(index, 0), tabs.count)
        tabs.insert(tab, at: position)
        source.release(tab)
        selectTab(at: position)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: false)
    }

    /// Detache l'onglet actif vers une nouvelle fenetre.
    func moveTabToNewWindow(at index: Int) {
        guard tabs.indices.contains(index), tabs.count > 1 else { return }
        WindowManager.shared.openWindow(adopting: tabs[index], from: self)
    }

    func moveTab(from: Int, to: Int) {
        guard tabs.indices.contains(from), to >= 0, to <= tabs.count else { return }
        let active = activeTab
        let tab = tabs.remove(at: from)
        tabs.insert(tab, at: min(to, tabs.count))
        if let idx = tabs.firstIndex(where: { $0 === active }) { selectedTabIndex = idx }
        objectWillChange.send()
    }

    // MARK: - Navigation

    func go(to location: Location) { activeTab.go(to: location) }
    func open(_ url: URL) { activeTab.open(url) }

    func openInNewTab(_ url: URL) { newTab(at: .folder(url), select: true) }

    /// Clic molette : ouvre un dossier dans un nouvel onglet, sans rien faire
    /// sur un fichier. Les liens et alias sont resolus comme a l'ouverture.
    func openInNewTabIfFolder(_ item: FileItem) {
        guard let url = folderTarget(of: item) else { return }
        openInNewTab(url)
    }

    func openInNewWindow(_ url: URL) {
        WindowManager.shared.openWindow(at: .folder(url))
    }

    func focusSearch() { focusSearchToken &+= 1 }

    /// Double-clic / Entree : ouvre les dossiers dans l'onglet, lance les fichiers.
    func activate(_ items: [FileItem]) {
        guard !items.isEmpty else { return }
        if items.count == 1, let single = items.first, let url = folderTarget(of: single) {
            if AppSettings.shared.openFoldersInNewTab { openInNewTab(url) } else { open(url) }
            return
        }
        for item in items {
            if let folder = folderTarget(of: item) {
                openInNewTab(folder)
            } else {
                NSWorkspace.shared.open(item.url)
            }
        }
    }

    private func resolveIfAlias(_ item: FileItem) -> URL {
        guard item.isAliasFile || item.isSymbolicLink else { return item.url }
        if let resolved = try? URL(resolvingAliasFileAt: item.url, options: [.withoutUI]) { return resolved }
        return item.url.resolvingSymlinksInPath()
    }

    /// Dossier a ouvrir pour cet element, en resolvant alias et liens.
    /// nil si ce n'en est pas un : l'element part alors au Finder.
    private func folderTarget(of item: FileItem) -> URL? {
        if item.isNavigableContainer { return resolveIfAlias(item) }
        guard item.isAliasFile || item.isSymbolicLink else { return nil }
        let resolved = resolveIfAlias(item)
        guard resolved != item.url,
              let v = try? resolved.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        else { return nil }
        return (v.isDirectory == true && v.isPackage != true) ? resolved : nil
    }

    // MARK: - Recherche

    func runSearch(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        activeTab.go(to: .search(text: trimmed, scope: activeTab.location.folderURL))
    }

    // MARK: - Commandes fichiers

    var selection: [FileItem] { activeTab.selectedItems }
    var selectionURLs: [URL] { activeTab.selectedURLs }
    var hasSelection: Bool { activeTab.hasSelection }
    var selectionCount: Int { activeTab.selectedURLs.count }
    var currentFolder: URL? { activeTab.location.folderURL }

    func copySelection() { FileClipboard.shared.copy(selectionURLs) }
    func cutSelection() { FileClipboard.shared.cut(selectionURLs) }
    func copySelectionPaths() { FileClipboard.shared.copyPaths(selectionURLs) }

    func paste() {
        guard let folder = currentFolder else { return }
        FileClipboard.shared.paste(into: folder, undoManager: undoManager) { [weak self] _, error in
            if let error { self?.present(error) }
        }
    }

    func pasteShortcut() {
        guard let folder = currentFolder else { return }
        _ = FileClipboard.shared.pasteAsAlias(into: folder, undoManager: undoManager)
    }

    func trashSelection() {
        let urls = selectionURLs
        guard !urls.isEmpty else { return }
        FileOperations.shared.trash(urls, undoManager: undoManager) { [weak self] _, error in
            if let error { self?.present(error) }
        }
    }

    func deleteSelectionPermanently() {
        let urls = selectionURLs
        guard !urls.isEmpty, let window else { return }
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = urls.count == 1
            ? L("Supprimer definitivement \"%@\" ?", urls[0].lastPathComponent)
            : L("Supprimer definitivement ces %d elements ?", urls.count)
        alert.informativeText = L("Cette action est irreversible. Les elements ne passeront pas par la corbeille.")
        alert.addButton(withTitle: L("Supprimer"))
        alert.addButton(withTitle: L("Annuler", context: "bouton"))
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            FileOperations.shared.deletePermanently(urls) { error in
                if let error { self?.present(error) }
            }
        }
    }

    func duplicateSelection() {
        FileOperations.shared.duplicate(selectionURLs, undoManager: undoManager) { [weak self] _, error in
            if let error { self?.present(error) }
        }
    }

    func makeAliasForSelection() {
        guard let folder = currentFolder else { return }
        _ = FileOperations.shared.makeAliases(for: selectionURLs, in: folder, undoManager: undoManager)
    }

    func compressSelection() {
        guard let folder = currentFolder, !selectionURLs.isEmpty else { return }
        FileOperations.shared.compress(selectionURLs, in: folder) { [weak self] _, error in
            if let error { self?.present(error) }
        }
    }

    func newFolder() {
        guard let folder = currentFolder else { return }
        do {
            let url = try FileOperations.shared.newFolder(in: folder, undoManager: undoManager)
            activeTab.reload()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.activeTab.selectedURLs = [url]
                self?.onBeginRename?(url)
            }
        } catch { present(error) }
    }

    func newFile(named name: String, contents: Data = Data()) {
        guard let folder = currentFolder else { return }
        do {
            let url = try FileOperations.shared.newFile(in: folder, name: name, contents: contents,
                                                        undoManager: undoManager)
            activeTab.reload()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.activeTab.selectedURLs = [url]
                self?.onBeginRename?(url)
            }
        } catch { present(error) }
    }

    func beginRenameSelection() {
        guard let url = selectionURLs.first else { return }
        onBeginRename?(url)
    }

    func rename(_ url: URL, to newName: String) {
        do {
            let newURL = try FileOperations.shared.rename(url, to: newName, undoManager: undoManager)
            activeTab.reload()
            activeTab.selectedURLs = [newURL]
        } catch { present(error) }
    }

    func revealInFinder() {
        let urls = selectionURLs
        if urls.isEmpty, let folder = currentFolder {
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
    }

    func openWith(application: URL) {
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open(selectionURLs, withApplicationAt: application,
                                configuration: config, completionHandler: nil)
    }

    func share(from view: NSView) {
        let urls = selectionURLs
        guard !urls.isEmpty else { return }
        let picker = NSSharingServicePicker(items: urls)
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    /// Vue servant d'ancre a la feuille de partage (fournie par la zone de fichiers).
    var shareAnchorProvider: (() -> NSView?)?

    func shareSelection() {
        guard let anchor = shareAnchorProvider?() ?? window?.contentView else { return }
        share(from: anchor)
    }

    // MARK: - Fenetres d'informations

    func showInfoWindow() {
        let urls = selectionURLs
        guard !urls.isEmpty else { showFolderInfoWindow(); return }
        InfoWindowController.show(for: urls, model: self)
    }

    func showFolderInfoWindow() {
        guard let folder = currentFolder else { return }
        InfoWindowController.show(for: [folder], model: self)
    }

    func toggleQuickLook() {
        let urls = selectionURLs
        guard !urls.isEmpty else { return }
        QuickLookCoordinator.shared.toggle(urls: urls)
    }

    // MARK: - Tags

    func promptForNewTag() {
        let alert = NSAlert()
        alert.messageText = L("Nouveau tag")
        alert.informativeText = L("Nom du tag a appliquer a la selection.")
        alert.addButton(withTitle: L("Appliquer"))
        alert.addButton(withTitle: L("Annuler", context: "bouton"))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        let run: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            self?.toggleTag(name)
        }
        if let window, window.isVisible {
            alert.beginSheetModal(for: window, completionHandler: run)
        } else {
            run(alert.runModal())
        }
    }

    func toggleTag(_ tag: String) {
        if let error = TagManager.toggle(tag: tag, on: selectionURLs) { present(error) }
        activeTab.reload()
    }

    func emptyTrash() {
        guard let window else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("Vider la corbeille ?")
        alert.informativeText = L("Les elements seront supprimes definitivement.")
        alert.addButton(withTitle: L("Vider"))
        alert.addButton(withTitle: L("Annuler", context: "bouton"))
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            FileOperations.shared.emptyTrash { error in
                if let error { self?.present(error) }
            }
        }
    }

    func eject(_ url: URL) {
        do { try NSWorkspace.shared.unmountAndEjectDevice(at: url) }
        catch { present(error) }
    }

    // MARK: - Acces sandbox

    /// Demande a l'utilisateur d'autoriser un dossier auquel l'app n'a pas acces.
    func requestAccess(for url: URL) {
        let granted = AccessManager.shared.requestAccess(
            to: url,
            message: L("MExplorer fonctionne dans le bac a sable macOS. Selectionnez \"%@\" (ou un dossier parent) pour autoriser son affichage.", url.lastPathComponent),
            window: window
        )
        if granted != nil { activeTab.reload() }
    }

    // MARK: - Erreurs

    func present(_ error: Error) {
        let alert = NSAlert(error: error)
        if let window, window.isVisible {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }
}
