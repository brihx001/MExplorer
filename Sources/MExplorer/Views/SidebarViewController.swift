import AppKit

/// Volet de navigation : arborescence complete facon Windows 11
/// (Acces rapide, iCloud, Ce Mac, Emplacements, Tags) avec expansion paresseuse.
final class SidebarViewController: NSViewController {

    private let model: WindowModel
    private let outlineView = NSOutlineView()
    private let scrollView = NSScrollView()
    private var roots: [SidebarNode] = []
    private var observers: [NSObjectProtocol] = []
    private var isSyncingSelection = false

    init(model: WindowModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supporte") }

    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

    // MARK: - Cycle de vie

    override func loadView() {
        let container = NSView()

        outlineView.headerView = nil
        outlineView.style = .sourceList
        outlineView.floatsGroupRows = false
        outlineView.rowSizeStyle = .default
        outlineView.indentationPerLevel = 14
        outlineView.autosaveExpandedItems = false
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.doubleAction = #selector(doubleClicked)
        outlineView.menu = buildMenu()
        outlineView.registerForDraggedTypes([.fileURL, .string])
        outlineView.setDraggingSourceOperationMask([.copy, .move, .link], forLocal: false)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        // Le volet n'est pas sous la barre de titre : les marges automatiques
        // de la source list masqueraient la premiere ligne.
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        self.view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        rebuild()
        SidebarCatalog.refreshVolumes()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: SidebarCatalog.volumesChanged, object: nil, queue: .main) { [weak self] _ in
            self?.rebuild()
        })
        observers.append(center.addObserver(forName: SidebarNode.expandabilityChanged, object: nil, queue: .main) { [weak self] _ in
            self?.scheduleExpandabilityRefresh()
        })
        observers.append(center.addObserver(forName: DisplayNameCache.changed, object: nil, queue: .main) { [weak self] _ in
            self?.scheduleExpandabilityRefresh()
        })
        observers.append(center.addObserver(forName: AppSettings.favoritesChanged, object: nil, queue: .main) { [weak self] _ in
            self?.rebuild()
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { _ in SidebarCatalog.refreshVolumes() })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { _ in SidebarCatalog.refreshVolumes() })
    }

    private var expandabilityRefresh: DispatchWorkItem?

    /// Les sondes d'expansion arrivent par paquets : un seul rechargement suffit.
    private func scheduleExpandabilityRefresh() {
        expandabilityRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let selected = self.outlineView.selectedRow
            self.outlineView.reloadData()
            if selected >= 0 && selected < self.outlineView.numberOfRows {
                self.isSyncingSelection = true
                self.outlineView.selectRowIndexes(IndexSet(integer: selected), byExtendingSelection: false)
                self.isSyncingSelection = false
            }
        }
        expandabilityRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    // MARK: - Construction de l'arbre

    func rebuild() {
        let expandedPaths = Set(expandedNodePaths())
        roots = makeRoots()
        outlineView.reloadData()
        for root in roots { outlineView.expandItem(root) }
        restoreExpansion(expandedPaths)
        syncSelection(to: model.activeTab.location)
    }

    private func makeRoots() -> [SidebarNode] {
        var result: [SidebarNode] = []

        // Acces rapide
        let quick = SidebarNode(kind: .header, title: "Acces rapide", symbol: "star")
        quick.children = AppSettings.shared.favoritePaths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map { url in
                let node = SidebarNode(folderAt: url, kind: .favorite)
                node.parent = quick
                return node
            }
        result.append(quick)

        // iCloud
        if let icloud = SidebarCatalog.iCloudDrive {
            let header = SidebarNode(kind: .header, title: "iCloud", symbol: "icloud")
            let node = SidebarNode(folderAt: icloud, title: "iCloud Drive")
            node.parent = header
            header.children = [node]
            result.append(header)
        }

        // Ce Mac : arborescence reelle a partir du dossier personnel
        let thisMac = SidebarNode(kind: .header, title: "Ce Mac", symbol: "desktopcomputer")
        var macChildren: [SidebarNode] = []
        let homeNode = SidebarNode(folderAt: SidebarCatalog.home)
        homeNode.parent = thisMac
        macChildren.append(homeNode)
        let appsNode = SidebarNode(folderAt: SidebarCatalog.applications, title: "Applications")
        appsNode.parent = thisMac
        macChildren.append(appsNode)
        let rootNode = SidebarNode(folderAt: URL(fileURLWithPath: "/"), title: "Macintosh HD")
        rootNode.parent = thisMac
        macChildren.append(rootNode)
        thisMac.children = macChildren
        result.append(thisMac)

        // Emplacements (volumes montes)
        let volumes = SidebarCatalog.mountedVolumes()
        if !volumes.isEmpty {
            let header = SidebarNode(kind: .header, title: "Emplacements", symbol: "externaldrive")
            header.children = volumes.map { item in
                let node = SidebarNode(kind: .volume,
                                       title: item.displayName,
                                       symbol: SidebarCatalog.symbol(for: item.url),
                                       location: .folder(item.url),
                                       url: item.url)
                node.parent = header
                return node
            }
            result.append(header)
        }

        // Tags
        let tagsHeader = SidebarNode(kind: .header, title: "Tags", symbol: "tag")
        tagsHeader.children = TagManager.knownTags.map { name in
            let node = SidebarNode(kind: .tag, title: name, symbol: "circle.fill", location: .tag(name))
            node.parent = tagsHeader
            return node
        }
        result.append(tagsHeader)

        // Divers
        let others = SidebarNode(kind: .header, title: "Divers", symbol: "ellipsis.circle")
        var otherChildren: [SidebarNode] = [
            SidebarNode(kind: .special, title: "Recents", symbol: "clock", location: .recents)
        ]
        if let trash = SidebarCatalog.trash {
            let node = SidebarNode(kind: .special, title: "Corbeille", symbol: "trash",
                                   location: .folder(trash), url: trash)
            otherChildren.append(node)
        }
        otherChildren.forEach { $0.parent = others }
        others.children = otherChildren
        result.append(others)

        return result
    }

    // MARK: - Expansion / selection

    private func expandedNodePaths() -> [String] {
        var paths: [String] = []
        for row in 0..<outlineView.numberOfRows {
            if let node = outlineView.item(atRow: row) as? SidebarNode,
               outlineView.isItemExpanded(node) {
                paths.append(nodeKey(node))
            }
        }
        return paths
    }

    private func restoreExpansion(_ keys: Set<String>) {
        var row = 0
        while row < outlineView.numberOfRows {
            if let node = outlineView.item(atRow: row) as? SidebarNode,
               keys.contains(nodeKey(node)) {
                outlineView.expandItem(node)
            }
            row += 1
        }
    }

    private func nodeKey(_ node: SidebarNode) -> String {
        node.url?.path ?? "\(node.kind)|\(node.title)"
    }

    /// Selectionne (et deplie) le noeud correspondant a l'emplacement courant.
    func syncSelection(to location: Location) {
        guard let url = location.folderURL else {
            if case .tag(let name) = location {
                selectRow(where: { $0.kind == .tag && $0.title == name })
            }
            return
        }
        if let row = rowForURL(url) {
            select(row: row)
            return
        }
        // Deplie progressivement depuis les racines pour atteindre l'URL.
        guard revealPath(url) else { return }
        if let row = rowForURL(url) { select(row: row) }
    }

    @discardableResult
    private func revealPath(_ url: URL) -> Bool {
        let target = url.standardizedFileURL.path
        var progressed = true
        var guardCount = 0
        while progressed && guardCount < 40 {
            guardCount += 1
            progressed = false
            for row in 0..<outlineView.numberOfRows {
                guard let node = outlineView.item(atRow: row) as? SidebarNode,
                      let nodeURL = node.url else { continue }
                let nodePath = nodeURL.standardizedFileURL.path
                if nodePath == target { return true }
                if target.hasPrefix(nodePath == "/" ? "/" : nodePath + "/"),
                   !outlineView.isItemExpanded(node) {
                    outlineView.expandItem(node)
                    progressed = true
                    break
                }
            }
        }
        return rowForURL(url) != nil
    }

    private func rowForURL(_ url: URL) -> Int? {
        let target = url.standardizedFileURL.path
        for row in 0..<outlineView.numberOfRows {
            if let node = outlineView.item(atRow: row) as? SidebarNode,
               node.url?.standardizedFileURL.path == target {
                return row
            }
        }
        return nil
    }

    private func selectRow(where predicate: (SidebarNode) -> Bool) {
        for row in 0..<outlineView.numberOfRows {
            if let node = outlineView.item(atRow: row) as? SidebarNode, predicate(node) {
                select(row: row)
                return
            }
        }
    }

    private func select(row: Int) {
        isSyncingSelection = true
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        outlineView.scrollRowToVisible(row)
        isSyncingSelection = false
    }

    // MARK: - Actions

    @objc private func doubleClicked() {
        guard let node = clickedOrSelectedNode(), let location = node.location else { return }
        model.newTab(at: location)
    }

    private func clickedOrSelectedNode() -> SidebarNode? {
        let row = outlineView.clickedRow >= 0 ? outlineView.clickedRow : outlineView.selectedRow
        guard row >= 0 else { return nil }
        return outlineView.item(atRow: row) as? SidebarNode
    }

    // MARK: - Menu contextuel

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        return menu
    }

    @objc private func menuOpenInNewTab() {
        guard let node = clickedOrSelectedNode(), let location = node.location else { return }
        model.newTab(at: location)
    }

    @objc private func menuOpenInNewWindow() {
        guard let node = clickedOrSelectedNode(), let location = node.location else { return }
        WindowManager.shared.openWindow(at: location)
    }

    @objc private func menuAddToFavorites() {
        guard let url = clickedOrSelectedNode()?.url else { return }
        AppSettings.shared.addFavorite(url)
    }

    @objc private func menuRemoveFromFavorites() {
        guard let url = clickedOrSelectedNode()?.url else { return }
        AppSettings.shared.removeFavorite(url)
    }

    @objc private func menuEject() {
        guard let url = clickedOrSelectedNode()?.url else { return }
        model.eject(url)
    }

    @objc private func menuRevealInFinder() {
        guard let url = clickedOrSelectedNode()?.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func menuGrantAccess() {
        guard let url = clickedOrSelectedNode()?.url else { return }
        model.requestAccess(for: url)
        rebuild()
    }

    @objc private func menuRefresh() {
        SidebarNode.flushSubdirectoryCache()
        if let node = clickedOrSelectedNode() {
            node.invalidateChildren()
            outlineView.reloadItem(node, reloadChildren: true)
        } else {
            rebuild()
        }
    }
}

// MARK: - NSMenuDelegate

extension SidebarViewController: NSMenuDelegate {

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let node = clickedOrSelectedNode(), !node.isHeader else { return }

        menu.addItem(withTitle: "Ouvrir dans un nouvel onglet", action: #selector(menuOpenInNewTab), keyEquivalent: "")
        menu.addItem(withTitle: "Ouvrir dans une nouvelle fenetre", action: #selector(menuOpenInNewWindow), keyEquivalent: "")
        menu.addItem(.separator())

        if node.kind == .favorite {
            menu.addItem(withTitle: "Retirer de l'acces rapide", action: #selector(menuRemoveFromFavorites), keyEquivalent: "")
        } else if node.url != nil {
            menu.addItem(withTitle: "Ajouter a l'acces rapide", action: #selector(menuAddToFavorites), keyEquivalent: "")
        }

        if node.kind == .volume, let url = node.url,
           (try? url.resourceValues(forKeys: [.volumeIsEjectableKey]))?.volumeIsEjectable == true {
            menu.addItem(withTitle: "Ejecter", action: #selector(menuEject), keyEquivalent: "")
        }

        if let url = node.url, !AccessManager.shared.canList(url) {
            menu.addItem(.separator())
            menu.addItem(withTitle: "Autoriser l'acces...", action: #selector(menuGrantAccess), keyEquivalent: "")
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: "Actualiser", action: #selector(menuRefresh), keyEquivalent: "")
        menu.addItem(withTitle: "Afficher dans le Finder", action: #selector(menuRevealInFinder), keyEquivalent: "")

        for item in menu.items { item.target = self }
    }
}

// MARK: - Source de donnees

extension SidebarViewController: NSOutlineViewDataSource {

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = item as? SidebarNode else { return roots.count }
        if node.children == nil { node.loadChildrenIfNeeded() }
        return node.children?.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let node = item as? SidebarNode else { return roots[index] }
        if node.children == nil { node.loadChildrenIfNeeded() }
        return node.children![index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? SidebarNode else { return false }
        if let children = node.children { return !children.isEmpty }
        return node.isExpandable
    }

    func outlineView(_ outlineView: NSOutlineView, shouldExpandItem item: Any) -> Bool {
        (item as? SidebarNode)?.loadChildrenIfNeeded()
        return true
    }

    // MARK: Glisser-deposer

    func outlineView(_ outlineView: NSOutlineView,
                     validateDrop info: NSDraggingInfo,
                     proposedItem item: Any?,
                     proposedChildIndex index: Int) -> NSDragOperation {
        guard let node = item as? SidebarNode, let url = node.url, node.kind != .header else { return [] }
        guard FileClipboard.shared.pasteboardURLsIn(info.draggingPasteboard).isEmpty == false else { return [] }
        _ = url
        return info.draggingSourceOperationMask.contains(.move) ? .move : .copy
    }

    func outlineView(_ outlineView: NSOutlineView,
                     acceptDrop info: NSDraggingInfo,
                     item: Any?,
                     childIndex index: Int) -> Bool {
        guard let node = item as? SidebarNode, let destination = node.url else { return false }
        let urls = FileClipboard.shared.pasteboardURLsIn(info.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        let move = NSEvent.modifierFlags.contains(.command) || info.draggingSourceOperationMask.contains(.move)
        FileOperations.shared.drop(urls, into: destination, kind: move ? .move : .copy,
                                   undoManager: model.undoManager) { [weak self] _, error in
            if let error { self?.model.present(error) }
        }
        return true
    }
}

// MARK: - Delegue

extension SidebarViewController: NSOutlineViewDelegate {

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        (item as? SidebarNode)?.isHeader ?? false
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        guard let node = item as? SidebarNode else { return false }
        return !node.isHeader && node.location != nil
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? SidebarNode else { return nil }

        let identifier = NSUserInterfaceItemIdentifier(node.isHeader ? "header" : "row")
        let cell = (outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView)
            ?? SidebarCell(isHeader: node.isHeader, identifier: identifier)

        cell.textField?.stringValue = node.title
        if node.isHeader {
            cell.imageView?.image = nil
        } else if node.kind == .tag {
            let color = SidebarCatalog.color(forTag: node.title) ?? .systemGray
            cell.imageView?.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(paletteColors: [color]))
            cell.imageView?.contentTintColor = color
        } else {
            cell.imageView?.image = NSImage(systemSymbolName: node.symbol, accessibilityDescription: nil)
            cell.imageView?.contentTintColor = nil
        }
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !isSyncingSelection else { return }
        let row = outlineView.selectedRow
        guard row >= 0,
              let node = outlineView.item(atRow: row) as? SidebarNode,
              let location = node.location else { return }

        if NSEvent.modifierFlags.contains(.command) {
            model.newTab(at: location)
        } else {
            model.go(to: location)
        }
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        ((item as? SidebarNode)?.isHeader ?? false) ? 22 : 24
    }
}

/// Cellule simple icone + libelle.
private final class SidebarCell: NSTableCellView {

    init(isHeader: Bool, identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        let label = NSTextField(labelWithString: "")
        label.font = isHeader
            ? .systemFont(ofSize: 11, weight: .semibold)
            : .systemFont(ofSize: 13)
        label.textColor = isHeader ? .secondaryLabelColor : .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        textField = label

        if isHeader {
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
                label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
                label.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        } else {
            let icon = NSImageView()
            icon.symbolConfiguration = .init(pointSize: 13, weight: .regular)
            icon.translatesAutoresizingMaskIntoConstraints = false
            addSubview(icon)
            imageView = icon
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
                icon.centerYAnchor.constraint(equalTo: centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 18),
                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
                label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
                label.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supporte") }
}
