import AppKit
import Quartz

/// Vue "Details" / "Liste" : NSTableView multi-colonnes, triable, regroupable,
/// avec renommage en place, glisser-deposer et menu contextuel.
final class FileListViewController: NSViewController, FileAreaController {

    private let model: WindowModel
    private let tableView = FileTableView()
    private let scrollView = NSScrollView()
    private var rows: [ListRow] = []
    private var isApplyingSelection = false
    private var renameTargetURL: URL?
    private let slowRename = SlowClickRenamer()
    /// Elements du glissement en cours, pour savoir quoi mettre a la corbeille
    /// si le depot se fait sur la Corbeille du Dock.
    private var draggedURLs: [URL] = []
    /// Vrai pendant la reconstruction des colonnes : les notifications de
    /// redimensionnement emises a ce moment ne sont pas des gestes utilisateur.
    private var isRebuildingColumns = false
    /// Vrai pendant la synchronisation du tri : evite de reboucler sur le delegue.
    private var isApplyingSort = false

    /// Signature des colonnes actuellement en place. Reconstruire les colonnes
    /// a chaque changement de reglage effacait `sortDescriptors` (verifie :
    /// `removeTableColumn` les supprime), donc un second clic sur un en-tete
    /// re-appliquait le prototype ascendant au lieu d'inverser le sens.
    private struct ColumnLayout: Equatable {
        let tabID: UUID
        let locationKey: String
        let columns: [ColumnID]
        let showsHeader: Bool
    }
    private var appliedLayout: ColumnLayout?

    weak var tab: TabState?

    init(model: WindowModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supporte") }

    // MARK: - Vue

    override func loadView() {
        tableView.allowsMultipleSelection = true
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.allowsColumnSelection = false
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.style = .fullWidth
        tableView.gridStyleMask = []
        tableView.rowHeight = 24
        tableView.intercellSpacing = NSSize(width: 6, height: 0)
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(singleClicked)
        tableView.doubleAction = #selector(doubleClicked)
        tableView.onKeyDown = { [weak self] event in self?.handleKey(event) ?? false }
        tableView.onMenuForRow = { [weak self] _ in self?.contextMenu() }
        tableView.registerForDraggedTypes([.fileURL])
        // `.delete` est l'operation que reclame la Corbeille du Dock : sans
        // elle, y lacher un fichier ne declenche rien.
        tableView.setDraggingSourceOperationMask([.copy, .move, .link, .delete], forLocal: false)
        tableView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        view = scrollView
        rebuildColumns()

        tableView.onInterrupt = { [weak self] in self?.slowRename.cancel() }
        tableView.onSlowClick = { [weak self] row, column in
            self?.scheduleSlowRename(row: row, column: column)
        }
        tableView.onMiddleClick = { [weak self] row in
            guard let self, let item = self.rows[safe: row]?.item else { return }
            self.model.openInNewTabIfFolder(item)
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(columnDidResize(_:)),
            name: NSTableView.columnDidResizeNotification, object: tableView)
        NotificationCenter.default.addObserver(
            self, selector: #selector(languageDidChange),
            name: L10n.changed, object: nil)
    }

    @objc private func languageDidChange() {
        refreshColumnTitles()
        tableView.reloadData()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    /// Memorise la largeur des colonnes par dossier (comme l'Explorateur Windows).
    @objc private func columnDidResize(_ note: Notification) {
        guard !isRebuildingColumns, let tab, tab.location.isFolder else { return }
        guard note.userInfo?["NSOldWidth"] != nil else { return }
        var widths = tab.settings.columnWidths
        for column in tableView.tableColumns {
            widths[column.identifier.rawValue] = Double(column.width)
        }
        guard widths != tab.settings.columnWidths else { return }
        tab.settings.columnWidths = widths
        FolderSettingsStore.shared.store(tab.settings, for: tab.location.folderURL ?? SidebarCatalog.home)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(tableView)
    }

    // MARK: - FileAreaController

    func attach(tab: TabState) {
        self.tab = tab
        rebuildColumns()
        reloadContent()
    }

    func reloadContent() {
        slowRename.cancel()
        rows = tab?.rows ?? []
        // Les bandes alternees derriere un dossier vide font croire a un contenu.
        tableView.usesAlternatingRowBackgroundColors = !rows.isEmpty
        tableView.reloadData()
        applySelection(tab?.selectedURLs ?? [])
        applySortState()
    }

    func applySelection(_ urls: [URL]) {
        let set = Set(urls.map(\.path))
        var indexes = IndexSet()
        for (index, row) in rows.enumerated() {
            if let item = row.item, set.contains(item.url.path) { indexes.insert(index) }
        }
        isApplyingSelection = true
        tableView.selectRowIndexes(indexes, byExtendingSelection: false)
        isApplyingSelection = false
        if let first = indexes.first { tableView.scrollRowToVisible(first) }
    }

    /// Le renommage n'est arme que sur la colonne du nom, et seulement si
    /// l'element clique est toujours le seul selectionne quand le delai expire.
    private func scheduleSlowRename(row: Int, column: Int) {
        guard rows.indices.contains(row), let url = rows[row].item?.url,
              tableView.tableColumns.indices.contains(column),
              tableView.tableColumns[column].identifier.rawValue == ColumnID.name.rawValue
        else { return }
        slowRename.schedule { [weak self] in
            guard let self,
                  self.tableView.selectedRowIndexes.count == 1,
                  let selected = self.tableView.selectedRowIndexes.first,
                  self.rows.indices.contains(selected),
                  self.rows[selected].item?.url == url else { return }
            self.beginRename(url)
        }
    }

    func beginRename(_ url: URL) {
        guard let index = rows.firstIndex(where: { $0.item?.url == url }) else {
            renameTargetURL = url
            return
        }
        guard let nameColumn = tableView.tableColumns.firstIndex(where: { $0.identifier.rawValue == ColumnID.name.rawValue })
        else { return }
        tableView.scrollRowToVisible(index)
        guard let cell = tableView.view(atColumn: nameColumn, row: index, makeIfNecessary: true) as? FileNameCell
        else { return }
        cell.beginEditing()
    }

    func frameOnScreen(for url: URL) -> NSRect? {
        guard let index = rows.firstIndex(where: { $0.item?.url == url }) else { return nil }
        let rect = tableView.rect(ofRow: index)
        guard let window = tableView.window else { return nil }
        let inWindow = tableView.convert(rect, to: nil)
        return window.convertToScreen(inWindow)
    }

    func focus() { view.window?.makeFirstResponder(tableView) }

    // MARK: - Colonnes

    /// Ajuste une colonne au plus large de ses contenus, comme un double-clic
    /// sur un separateur dans un tableur.
    ///
    /// Les lignes sont mesurees toutes, jusqu'a une borne : au-dela, le gain de
    /// precision ne vaut pas l'attente, et les elements suivants sont de toute
    /// facon hors de vue.
    private func autoFitColumn(at index: Int) {
        guard tableView.tableColumns.indices.contains(index) else { return }
        let column = tableView.tableColumns[index]
        guard let columnID = ColumnID(rawValue: column.identifier.rawValue) else { return }

        let headerFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
        var width = textWidth(column.title, font: headerFont) + 20   // tri + marges

        let cellFont = NSFont.systemFont(ofSize: columnID == .name ? 13 : 12)
        for row in rows.prefix(5000) {
            guard let item = row.item else { continue }
            var candidate = textWidth(text(for: item, column: columnID), font: cellFont) + 10
            if columnID == .name {
                // icone (2 + 18 + 6) puis une pastille par tag (3 + 8)
                candidate += 26 + CGFloat(min(item.tagNames.count, 4)) * 11
            }
            width = max(width, candidate)
        }

        // Poser la largeur suffit a la memoriser : NSTableView emet alors
        // columnDidResize, que l'on ecoute deja pour cela.
        column.width = min(max(width.rounded(.up), column.minWidth), column.maxWidth)
    }

    private func textWidth(_ text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    /// Reecrit les en-tetes sans toucher aux colonnes : un changement de langue
    /// ne modifie pas la composition, donc `rebuildColumns` ne ferait rien.
    func refreshColumnTitles() {
        for column in tableView.tableColumns {
            if let id = ColumnID(rawValue: column.identifier.rawValue) {
                column.title = id.title
            }
        }
        tableView.headerView?.needsDisplay = true
    }

    func rebuildColumns() {
        guard let tab else { return }
        let settings = tab.settings
        let wanted: [ColumnID] = settings.viewMode == .list ? [.name] : settings.visibleColumns
        let layout = ColumnLayout(tabID: tab.id,
                                  locationKey: tab.location.addressPath,
                                  columns: wanted,
                                  showsHeader: settings.viewMode != .list)

        // Le jeu de colonnes n'a pas bouge : surtout ne pas les recreer, cela
        // perdrait le tri en cours et les largeurs ajustees par l'utilisateur.
        guard layout != appliedLayout else {
            applySortState()
            return
        }

        isRebuildingColumns = true
        defer {
            // Les notifications de layout arrivent apres le tour de boucle courant.
            DispatchQueue.main.async { [weak self] in self?.isRebuildingColumns = false }
        }

        for column in tableView.tableColumns { tableView.removeTableColumn(column) }

        for id in wanted {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id.rawValue))
            column.title = id.title
            column.width = settings.columnWidths[id.rawValue].map { CGFloat($0) } ?? id.defaultWidth
            column.minWidth = 60
            column.maxWidth = 900
            if let sortKey = SortKey(column: id) {
                column.sortDescriptorPrototype = NSSortDescriptor(key: sortKey.rawValue, ascending: true)
            }
            tableView.addTableColumn(column)
        }

        if layout.showsHeader {
            let header = FileTableHeaderView()
            header.onAutoFit = { [weak self] index in self?.autoFitColumn(at: index) }
            tableView.headerView = header
        } else {
            tableView.headerView = nil
        }
        tableView.headerView?.menu = headerMenu()
        tableView.rowHeight = 24
        appliedLayout = layout
        applySortState()
    }

    /// Aligne le tri de la table sur les reglages de l'onglet, pour que le clic
    /// suivant sur le meme en-tete inverse le sens au lieu de repartir a zero.
    private func applySortState() {
        guard let tab else { return }
        let settings = tab.settings
        let descriptor = NSSortDescriptor(key: settings.sortKey.rawValue, ascending: settings.ascending)

        if tableView.sortDescriptors.first != descriptor {
            isApplyingSort = true
            tableView.sortDescriptors = [descriptor]
            isApplyingSort = false
        }

        let sortColumn = tableView.tableColumns.first {
            $0.identifier.rawValue == settings.sortKey.column.rawValue
        }
        tableView.highlightedTableColumn = sortColumn
        let indicator = NSImage(named: settings.ascending ? "NSAscendingSortIndicator"
                                                          : "NSDescendingSortIndicator")
        for column in tableView.tableColumns {
            tableView.setIndicatorImage(column === sortColumn ? indicator : nil, in: column)
        }
    }

    private func headerMenu() -> NSMenu {
        let menu = NSMenu()
        guard let tab else { return menu }
        for id in ColumnID.allCases {
            let item = menu.addBlockItem(id.title) {
                tab.update { s in
                    if s.visibleColumns.contains(id) {
                        if id != .name { s.visibleColumns.removeAll { $0 == id } }
                    } else {
                        s.visibleColumns.append(id)
                    }
                }
            }
            // Etat evalue a l'ouverture du menu : les colonnes peuvent avoir
            // change depuis sa construction.
            item.stateProvider = { tab.settings.visibleColumns.contains(id) }
            if id == .name { item.isEnabled = false }
        }
        return menu
    }

    // MARK: - Actions

    @objc private func singleClicked() {
        let row = tableView.clickedRow
        guard row >= 0 else { return }
        if let group = rows[row].group { tab?.toggleGroup(group.key); return }
        guard AppSettings.shared.singleClickToOpen,
              NSEvent.modifierFlags.intersection([.command, .shift, .option]).isEmpty else { return }
        model.activate(selectedItems())
    }

    @objc private func doubleClicked() {
        let row = tableView.clickedRow
        guard row >= 0 else { return }
        if let group = rows[row].group { tab?.toggleGroup(group.key); return }
        model.activate(selectedItems())
    }

    private func selectedItems() -> [FileItem] {
        tableView.selectedRowIndexes.compactMap { rows[$0].item }
    }

    private func contextMenu() -> NSMenu {
        FileContextMenu.build(for: selectedItems(), model: model, anchorView: tableView)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard let chars = event.charactersIgnoringModifiers, let first = chars.unicodeScalars.first else { return false }

        switch Int(first.value) {
        case 0x20: // espace : Coup d'oeil
            if flags.isEmpty {
                model.toggleQuickLook()
                return true
            }
        case NSCarriageReturnCharacter, NSEnterCharacter:
            if flags.isEmpty {
                model.activate(selectedItems())
                return true
            }
        case NSDeleteCharacter, NSBackspaceCharacter, NSDeleteFunctionKey:
            if flags.contains(.shift) {
                model.deleteSelectionPermanently()
            } else {
                model.trashSelection()
            }
            return true
        case NSF2FunctionKey:
            model.beginRenameSelection()
            return true
        case NSF5FunctionKey:
            tab?.reload()
            return true
        case NSUpArrowFunctionKey where flags.contains(.command):
            tab?.goUp()
            return true
        case NSDownArrowFunctionKey where flags.contains(.command):
            model.activate(selectedItems())
            return true
        case NSLeftArrowFunctionKey where flags.contains(.option) || flags.contains(.command):
            tab?.goBack()
            return true
        case NSRightArrowFunctionKey where flags.contains(.option) || flags.contains(.command):
            tab?.goForward()
            return true
        default:
            break
        }
        return false
    }
}

// MARK: - Source de donnees

extension FileListViewController: NSTableViewDataSource {

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard !isApplyingSort, !isRebuildingColumns,
              let descriptor = tableView.sortDescriptors.first,
              let key = descriptor.key,
              let sortKey = SortKey(rawValue: key),
              let tab else { return }
        tab.update { s in
            s.sortKey = sortKey
            s.ascending = descriptor.ascending
        }
    }

    // MARK: Glisser-deposer

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        rows[row].item?.url as NSURL?
    }

    func tableView(_ tableView: NSTableView,
                   draggingSession session: NSDraggingSession,
                   willBeginAt screenPoint: NSPoint,
                   forRowIndexes rowIndexes: IndexSet) {
        draggedURLs = rowIndexes.compactMap { rows[$0].item?.url }
    }

    func tableView(_ tableView: NSTableView,
                   draggingSession session: NSDraggingSession,
                   endedAt screenPoint: NSPoint,
                   operation: NSDragOperation) {
        let urls = draggedURLs
        draggedURLs = []
        // La Corbeille du Dock repond `.delete` : a nous de mettre a la corbeille.
        guard operation == .delete, !urls.isEmpty else { return }
        FileOperations.shared.trash(urls, undoManager: model.undoManager) { [weak self] _, error in
            if let error { self?.model.present(error) }
        }
    }

    func tableView(_ tableView: NSTableView,
                   validateDrop info: NSDraggingInfo,
                   proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard tab?.location.isFolder == true else { return [] }
        let urls = FileClipboard.shared.pasteboardURLsIn(info.draggingPasteboard)
        guard !urls.isEmpty else { return [] }

        if dropOperation == .on, rows.indices.contains(row), let item = rows[row].item, item.isNavigableContainer {
            return dragOperation(for: info)
        }
        tableView.setDropRow(-1, dropOperation: .on)
        return dragOperation(for: info)
    }

    func tableView(_ tableView: NSTableView,
                   acceptDrop info: NSDraggingInfo,
                   row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        let urls = FileClipboard.shared.pasteboardURLsIn(info.draggingPasteboard)
        guard !urls.isEmpty else { return false }

        var destination = tab?.location.folderURL
        if dropOperation == .on, rows.indices.contains(row), let item = rows[row].item, item.isNavigableContainer {
            destination = item.url
        }
        guard let destination else { return false }

        let flags = NSEvent.modifierFlags
        let kind: FileOperations.TransferKind
        if flags.contains(.option) {
            kind = .copy
        } else if flags.contains(.command) || sameVolume(urls, destination) {
            kind = .move
        } else {
            kind = .copy
        }
        FileOperations.shared.drop(urls, into: destination, kind: kind, undoManager: model.undoManager)
        return true
    }

    private func dragOperation(for info: NSDraggingInfo) -> NSDragOperation {
        let flags = NSEvent.modifierFlags
        if flags.contains(.option) { return .copy }
        if flags.contains(.command) { return .move }
        return info.draggingSourceOperationMask.contains(.move) ? .move : .copy
    }

    /// Le Finder deplace au sein d'un meme volume et copie entre volumes ; on reprend la regle.
    private func sameVolume(_ urls: [URL], _ destination: URL) -> Bool {
        guard let first = urls.first,
              let a = try? first.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier,
              let b = try? destination.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
        else { return false }
        return a.isEqual(b)
    }
}

// MARK: - Delegue

extension FileListViewController: NSTableViewDelegate {

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        rows[row].group != nil
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        rows[row].item != nil
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        rows[row].group != nil ? 26 : 24
    }

    func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
        rows[row].item?.displayName
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if let group = rows[row].group {
            let id = NSUserInterfaceItemIdentifier("group")
            let cell = (tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView)
                ?? GroupHeaderCell(identifier: id)
            let collapsed = tab?.collapsedGroups.contains(group.key) ?? false
            cell.textField?.stringValue = "\(collapsed ? "\u{25B6}" : "\u{25BC}")  \(group.title)  (\(group.count))"
            return cell
        }

        guard let item = rows[row].item,
              let columnID = tableColumn.flatMap({ ColumnID(rawValue: $0.identifier.rawValue) })
        else { return nil }

        if columnID == .name {
            let id = NSUserInterfaceItemIdentifier("name")
            let cell = (tableView.makeView(withIdentifier: id, owner: self) as? FileNameCell)
                ?? FileNameCell(identifier: id)
            cell.configure(with: item, delegate: self)
            cell.alphaValue = FileClipboard.shared.isMarkedForCut(item.url) ? 0.45 : 1
            return cell
        }

        let id = NSUserInterfaceItemIdentifier("text")
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView)
            ?? PlainTextCell(identifier: id)
        cell.textField?.alignment = columnID.isRightAligned ? .right : .left
        cell.textField?.stringValue = text(for: item, column: columnID)
        cell.alphaValue = FileClipboard.shared.isMarkedForCut(item.url) ? 0.45 : 1
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isApplyingSelection, let tab else { return }
        tab.selectedURLs = tableView.selectedRowIndexes.compactMap { rows[$0].item?.url }
        QuickLookCoordinator.shared.updateIfVisible(urls: tab.selectedURLs)
    }

    private func text(for item: FileItem, column: ColumnID) -> String {
        switch column {
        case .name: return item.displayName
        case .dateModified: return Fmt.date(item.modificationDate)
        case .dateCreated: return Fmt.date(item.creationDate)
        case .dateAdded: return Fmt.date(item.addedDate)
        case .kind: return item.kindDescription
        case .size:
            // Comme dans l'Explorateur, un dossier n'affiche pas de taille
            // tant qu'elle n'a pas ete calculee a la demande.
            if item.isDirectory { return item.computedFolderSize.map { Fmt.size($0) } ?? "" }
            return Fmt.size(item.byteSize)
        case .tags: return item.tagNames.joined(separator: ", ")
        case .fileExtension: return item.fileExtension
        case .path: return item.url.deletingLastPathComponent().path
        case .cloud: return cloudText(for: item)
        }
    }

    /// Etat iCloud, lu a la demande et seulement si la colonne est affichee.
    ///
    /// Ces deux clefs coutaient a elles seules les deux tiers du chargement
    /// d'un dossier de 5 200 elements : elles restent hors du jeu de clefs
    /// lu en masse, et ne sont interrogees que pour les lignes dessinees.
    private func cloudText(for item: FileItem) -> String {
        let state = item.cloudState
        guard state.isUbiquitous else { return "" }
        switch state.status {
        case .current?: return L("Telecharge")
        case .downloaded?: return L("Telecharge")
        case .notDownloaded?: return L("Dans iCloud")
        default: return L("Dans iCloud")
        }
    }
}

// MARK: - Renommage en place

extension FileListViewController: NSTextFieldDelegate {

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        let row = tableView.row(for: field)
        guard rows.indices.contains(row), let item = rows[row].item else { return }
        let newName = field.stringValue
        (field.superview as? FileNameCell)?.endEditing()
        guard newName != item.displayName, !newName.isEmpty else {
            field.stringValue = item.displayName
            return
        }
        model.rename(item.url, to: newName)
    }
}

// MARK: - Cellules

/// En-tete de tableau qui ajuste une colonne au double-clic sur son separateur,
/// comme un tableur. NSTableHeaderView n'y reagit pas de lui-meme.
final class FileTableHeaderView: NSTableHeaderView {

    var onAutoFit: ((Int) -> Void)?

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2, let column = dividerColumn(at: event) {
            onAutoFit?(column)
            return
        }
        super.mouseDown(with: event)
    }

    /// Colonne dont le bord droit se trouve sous le pointeur, a trois points pres.
    private func dividerColumn(at event: NSEvent) -> Int? {
        guard let table = tableView else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        for index in 0..<table.numberOfColumns {
            if abs(point.x - headerRect(ofColumn: index).maxX) <= 3 { return index }
        }
        return nil
    }
}

/// Cellule "Nom" : icone + libelle editable + pastilles de tags.
final class FileNameCell: NSTableCellView {

    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let tagStack = NSStackView()
    private var currentURL: URL?

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        imageView = icon

        label.font = .systemFont(ofSize: 13)
        label.lineBreakMode = .byTruncatingMiddle
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        label.focusRingType = .none
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        textField = label

        tagStack.orientation = .horizontal
        tagStack.spacing = 3
        tagStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tagStack)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),

            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),

            tagStack.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 6),
            tagStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            tagStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4)
        ])
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supporte") }

    /// Passe le libelle en edition. `isSelectable` doit etre remis a vrai :
    /// NSTextField remet `isEditable` a faux des qu'un champ cesse d'etre
    /// selectionnable, et le champ ne pouvait alors plus prendre le focus.
    func beginEditing() {
        label.isSelectable = true
        label.isEditable = true
        window?.makeFirstResponder(label)
        label.currentEditor()?.selectAll(nil)
    }

    func endEditing() {
        label.isEditable = false
        label.isSelectable = false
    }

    func configure(with item: FileItem, delegate: NSTextFieldDelegate) {
        currentURL = item.url
        icon.image = IconCache.shared.icon(for: item)
        label.stringValue = displayName(for: item)
        label.delegate = delegate
        // Hors renommage, le libelle n'est ni editable ni selectionnable :
        // un champ selectionnable intercepterait les clics de la ligne.
        label.isEditable = false
        label.isSelectable = false
        label.textColor = item.isHidden ? .secondaryLabelColor : .labelColor

        tagStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for tag in item.tagNames.prefix(4) {
            let dot = NSView()
            dot.wantsLayer = true
            dot.layer?.backgroundColor = (SidebarCatalog.color(forTag: tag) ?? .systemGray).cgColor
            dot.layer?.cornerRadius = 4
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 8).isActive = true
            dot.toolTip = tag
            tagStack.addArrangedSubview(dot)
        }
    }

    private func displayName(for item: FileItem) -> String {
        guard !AppSettings.shared.showFileExtensions,
              !item.isNavigableContainer,
              !item.fileExtension.isEmpty
        else { return item.displayName }
        return item.url.deletingPathExtension().lastPathComponent
    }
}

final class PlainTextCell: NSTableCellView {
    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) non supporte") }
}

final class GroupHeaderCell: NSTableCellView {
    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) non supporte") }
}
