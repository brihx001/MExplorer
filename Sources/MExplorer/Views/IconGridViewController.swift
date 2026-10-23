import AppKit
import Quartz

/// Modes "icones", "mosaiques" et "contenu" : NSCollectionView avec vignettes
/// Quick Look, selection au lasso et regroupement en sections.
final class IconGridViewController: NSViewController, FileAreaController {

    private let model: WindowModel
    private let collectionView = FileCollectionView()
    private let scrollView = NSScrollView()
    private var sections: [(header: GroupSection?, items: [FileItem])] = []
    private var isApplyingSelection = false
    /// NSCollectionView n'honore pas l'enregistrement par classe pour un item
    /// sans nib : on cree et recycle les cellules nous-memes.
    private var itemPool: [FileGridItem] = []
    private var draggedURLs: [URL] = []
    /// Un seul objet de layout, mute en place : reassigner `collectionViewLayout`
    /// efface les classes enregistrees pour les vues supplementaires.
    private let flowLayout = NSCollectionViewFlowLayout()

    weak var tab: TabState?

    init(model: WindowModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supporte") }

    override func loadView() {
        flowLayout.minimumInteritemSpacing = 8
        flowLayout.minimumLineSpacing = 8
        flowLayout.sectionInset = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        flowLayout.itemSize = ViewMode.largeIcons.cellSize
        collectionView.collectionViewLayout = flowLayout

        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.allowsEmptySelection = true
        collectionView.backgroundColors = [.clear]
        collectionView.register(GridSectionHeader.self,
                                forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
                                withIdentifier: GridSectionHeader.identifier)
        collectionView.registerForDraggedTypes([.fileURL])
        // `.delete` : voir FileListViewController, meme raison (Corbeille du Dock).
        collectionView.setDraggingSourceOperationMask([.copy, .move, .link, .delete], forLocal: false)
        collectionView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        collectionView.onKeyDown = { [weak self] event in self?.handleKey(event) ?? false }
        collectionView.onContextMenu = { [weak self] in self?.contextMenu() }
        collectionView.onInterrupt = { [weak self] in self?.slowRename.cancel() }
        collectionView.onSlowClick = { [weak self] path, point in
            self?.scheduleSlowRename(at: path, windowPoint: point)
        }
        collectionView.onMiddleClick = { [weak self] path in
            guard let self,
                  let item = self.sections[safe: path.section]?.items[safe: path.item] else { return }
            self.model.openInNewTabIfFolder(item)
        }

        let click = NSClickGestureRecognizer(target: self, action: #selector(doubleClicked(_:)))
        click.numberOfClicksRequired = 2
        click.delaysPrimaryMouseButtonEvents = false
        collectionView.addGestureRecognizer(click)

        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .controlBackgroundColor

        view = scrollView
        applyLayout()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(collectionView)
    }

    // MARK: - FileAreaController

    func attach(tab: TabState) {
        self.tab = tab
        IconCache.shared.cancelPendingThumbnails()
        applyLayout()
        reloadContent()
    }

    func rebuildColumns() { applyLayout() }

    func reloadContent() {
        slowRename.cancel()
        sections = buildSections()
        collectionView.reloadData()
        applySelection(tab?.selectedURLs ?? [])
    }

    func applySelection(_ urls: [URL]) {
        let set = Set(urls.map(\.path))
        var paths = Set<IndexPath>()
        for (s, section) in sections.enumerated() {
            for (i, item) in section.items.enumerated() where set.contains(item.url.path) {
                paths.insert(IndexPath(item: i, section: s))
            }
        }
        isApplyingSelection = true
        collectionView.selectionIndexPaths = paths
        isApplyingSelection = false
    }

    private let slowRename = SlowClickRenamer()

    private func scheduleSlowRename(at path: IndexPath, windowPoint: NSPoint) {
        guard let item = collectionView.item(at: path) as? FileGridItem,
              item.isInsideName(windowPoint: windowPoint),
              let url = sections[safe: path.section]?.items[safe: path.item]?.url else { return }
        slowRename.schedule { [weak self] in
            guard let self, let current = self.indexPath(for: url),
                  self.collectionView.selectionIndexPaths == [current] else { return }
            self.beginRename(url)
        }
    }

    func beginRename(_ url: URL) {
        guard let path = indexPath(for: url),
              let item = collectionView.item(at: path) as? FileGridItem else { return }
        item.beginEditing { [weak self] newName in
            self?.model.rename(url, to: newName)
        }
    }

    func frameOnScreen(for url: URL) -> NSRect? {
        guard let path = indexPath(for: url),
              let item = collectionView.item(at: path),
              let window = collectionView.window else { return nil }
        let rect = item.view.convert(item.view.bounds, to: nil)
        return window.convertToScreen(rect)
    }

    func focus() { view.window?.makeFirstResponder(collectionView) }

    // MARK: - Mise en page

    private func applyLayout() {
        let mode = tab?.settings.viewMode ?? .largeIcons
        var size = mode.cellSize
        // Le mode "Contenu" occupe toute la largeur disponible.
        if mode == .content || mode == .smallIcons {
            let width = max(200, collectionView.bounds.width - 24)
            size.width = mode == .content ? width : min(size.width, width)
        }
        flowLayout.itemSize = size
        flowLayout.headerReferenceSize = (tab?.settings.groupKey ?? .none) != .none
            ? NSSize(width: 0, height: 24)
            : .zero
        flowLayout.invalidateLayout()
    }

    private func buildSections() -> [(GroupSection?, [FileItem])] {
        guard let rows = tab?.rows else { return [] }
        var result: [(GroupSection?, [FileItem])] = []
        var currentHeader: GroupSection?
        var currentItems: [FileItem] = []
        var started = false

        for row in rows {
            switch row {
            case .group(let g):
                if started { result.append((currentHeader, currentItems)) }
                currentHeader = g
                currentItems = []
                started = true
            case .item(let item):
                currentItems.append(item)
                started = true
            }
        }
        if started { result.append((currentHeader, currentItems)) }
        return result
    }

    private func indexPath(for url: URL) -> IndexPath? {
        for (s, section) in sections.enumerated() {
            if let i = section.items.firstIndex(where: { $0.url == url }) {
                return IndexPath(item: i, section: s)
            }
        }
        return nil
    }

    private func selectedItems() -> [FileItem] {
        collectionView.selectionIndexPaths.compactMap { path in
            sections[safe: path.section]?.items[safe: path.item]
        }
    }

    // MARK: - Actions

    @objc private func doubleClicked(_ recognizer: NSClickGestureRecognizer) {
        let point = recognizer.location(in: collectionView)
        guard collectionView.indexPathForItem(at: point) != nil else { return }
        model.activate(selectedItems())
    }

    private func contextMenu() -> NSMenu {
        FileContextMenu.build(for: selectedItems(), model: model, anchorView: collectionView)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard let chars = event.charactersIgnoringModifiers, let first = chars.unicodeScalars.first else { return false }
        switch Int(first.value) {
        case 0x20 where flags.isEmpty:
            model.toggleQuickLook(); return true
        case NSCarriageReturnCharacter, NSEnterCharacter:
            model.activate(selectedItems()); return true
        case NSDeleteCharacter, NSBackspaceCharacter, NSDeleteFunctionKey:
            if flags.contains(.shift) { model.deleteSelectionPermanently() } else { model.trashSelection() }
            return true
        case NSF2FunctionKey:
            model.beginRenameSelection(); return true
        case NSUpArrowFunctionKey where flags.contains(.command):
            tab?.goUp(); return true
        case NSDownArrowFunctionKey where flags.contains(.command):
            model.activate(selectedItems()); return true
        default: return false
        }
    }
}

// MARK: - Source de donnees

extension IconGridViewController: NSCollectionViewDataSource {

    func numberOfSections(in collectionView: NSCollectionView) -> Int { sections.count }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        sections[section].items.count
    }

    func collectionView(_ collectionView: NSCollectionView,
                        itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = itemPool.popLast() ?? FileGridItem()
        let file = sections[indexPath.section].items[indexPath.item]
        item.configure(with: file, mode: tab?.settings.viewMode ?? .largeIcons)
        return item
    }

    func collectionView(_ collectionView: NSCollectionView,
                        viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind,
                        at indexPath: IndexPath) -> NSView {
        // Les vues supplementaires doivent imperativement venir de makeSupplementaryView.
        let view = collectionView.makeSupplementaryView(ofKind: kind,
                                                        withIdentifier: GridSectionHeader.identifier,
                                                        for: indexPath)
        if let header = view as? GridSectionHeader {
            header.label.stringValue = sections[safe: indexPath.section]?.header
                .map { "\($0.title)  (\($0.count))" } ?? ""
        }
        return view
    }
}

// MARK: - Delegue

extension IconGridViewController: NSCollectionViewDelegate {

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        publishSelection()
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        publishSelection()
    }

    func collectionView(_ collectionView: NSCollectionView,
                        didEndDisplaying item: NSCollectionViewItem,
                        forRepresentedObjectAt indexPath: IndexPath) {
        guard let grid = item as? FileGridItem, itemPool.count < 60 else { return }
        grid.prepareForReuse()
        itemPool.append(grid)
    }

    private func publishSelection() {
        guard !isApplyingSelection, let tab else { return }
        tab.selectedURLs = selectedItems().map(\.url)
        QuickLookCoordinator.shared.updateIfVisible(urls: tab.selectedURLs)
    }

    func collectionView(_ collectionView: NSCollectionView,
                        pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        sections[safe: indexPath.section]?.items[safe: indexPath.item]?.url as NSURL?
    }

    func collectionView(_ collectionView: NSCollectionView,
                        draggingSession session: NSDraggingSession,
                        willBeginAt screenPoint: NSPoint,
                        forItemsAt indexPaths: Set<IndexPath>) {
        draggedURLs = indexPaths.compactMap {
            sections[safe: $0.section]?.items[safe: $0.item]?.url
        }
    }

    func collectionView(_ collectionView: NSCollectionView,
                        draggingSession session: NSDraggingSession,
                        endedAt screenPoint: NSPoint,
                        dragOperation operation: NSDragOperation) {
        let urls = draggedURLs
        draggedURLs = []
        guard operation == .delete, !urls.isEmpty else { return }
        FileOperations.shared.trash(urls, undoManager: model.undoManager) { [weak self] _, error in
            if let error { self?.model.present(error) }
        }
    }

    func collectionView(_ collectionView: NSCollectionView,
                        validateDrop draggingInfo: NSDraggingInfo,
                        proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
                        dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
        guard tab?.location.isFolder == true,
              !FileClipboard.shared.pasteboardURLsIn(draggingInfo.draggingPasteboard).isEmpty else { return [] }
        return NSEvent.modifierFlags.contains(.option) ? .copy : .move
    }

    func collectionView(_ collectionView: NSCollectionView,
                        acceptDrop draggingInfo: NSDraggingInfo,
                        indexPath: IndexPath,
                        dropOperation: NSCollectionView.DropOperation) -> Bool {
        let urls = FileClipboard.shared.pasteboardURLsIn(draggingInfo.draggingPasteboard)
        guard !urls.isEmpty else { return false }

        var destination = tab?.location.folderURL
        if dropOperation == .on,
           let target = sections[safe: indexPath.section]?.items[safe: indexPath.item],
           target.isNavigableContainer {
            destination = target.url
        }
        guard let destination else { return false }
        let copy = NSEvent.modifierFlags.contains(.option)
        FileOperations.shared.drop(urls, into: destination, kind: copy ? .copy : .move,
                                   undoManager: model.undoManager)
        return true
    }
}

// MARK: - Vues

final class FileCollectionView: NSCollectionView {
    var onKeyDown: ((NSEvent) -> Bool)?
    var onContextMenu: (() -> NSMenu?)?
    /// Clic simple sur un element deja seul selectionne : candidat au
    /// renommage par deux clics lents (element, point en coordonnees fenetre).
    var onSlowClick: ((IndexPath, NSPoint) -> Void)?
    var onInterrupt: (() -> Void)?
    /// Clic molette sur un element : ouverture dans un nouvel onglet.
    var onMiddleClick: ((IndexPath) -> Void)?

    override func otherMouseUp(with event: NSEvent) {
        guard event.buttonNumber == 2 else { super.otherMouseUp(with: event); return }
        onInterrupt?()
        if let path = indexPathForItem(at: convert(event.locationInWindow, from: nil)) {
            onMiddleClick?(path)
        }
    }

    override func keyDown(with event: NSEvent) {
        onInterrupt?()
        if onKeyDown?(event) == true { return }
        super.keyDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        onInterrupt?()
        super.scrollWheel(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        onInterrupt?()
        let path = indexPathForItem(at: convert(event.locationInWindow, from: nil))
        let aloneBefore = path.map { selectionIndexPaths == [$0] } ?? false
        let origin = NSEvent.mouseLocation

        super.mouseDown(with: event)

        guard let path,
              SlowClickRenamer.qualifies(event: event, wasAloneSelected: aloneBefore, mouseOrigin: origin),
              selectionIndexPaths == [path] else { return }
        onSlowClick?(path, event.locationInWindow)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        onInterrupt?()
        let point = convert(event.locationInWindow, from: nil)
        if let path = indexPathForItem(at: point), !selectionIndexPaths.contains(path) {
            selectionIndexPaths = [path]
            delegate?.collectionView?(self, didSelectItemsAt: [path])
        } else if indexPathForItem(at: point) == nil {
            let previous = selectionIndexPaths
            selectionIndexPaths = []
            if !previous.isEmpty { delegate?.collectionView?(self, didDeselectItemsAt: previous) }
        }
        return onContextMenu?()
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        QuickLookCoordinator.shared.attach(to: panel)
    }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        QuickLookCoordinator.shared.detach(from: panel)
    }
}

final class FileGridItem: NSCollectionViewItem, NSTextFieldDelegate {

    static let identifier = NSUserInterfaceItemIdentifier("FileGridItem")

    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")
    private let background = NSView()
    private var currentURL: URL?
    private var renameHandler: ((String) -> Void)?

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true

        background.wantsLayer = true
        background.layer?.cornerRadius = 6
        background.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(background)

        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(icon)

        label.alignment = .center
        label.font = .systemFont(ofSize: 12)
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 2
        label.isBordered = false
        label.drawsBackground = false
        label.delegate = self
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        subtitle.alignment = .center
        subtitle.font = .systemFont(ofSize: 10)
        subtitle.textColor = .secondaryLabelColor
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(subtitle)

        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
            background.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -2),
            background.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
            background.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2)
        ])
        self.view = container
        self.imageView = icon
        self.textField = label
        buildConstraintSets()
    }

    private var gridConstraints: [NSLayoutConstraint] = []
    private var rowConstraints: [NSLayoutConstraint] = []
    private var iconWidth: NSLayoutConstraint!
    private var iconHeight: NSLayoutConstraint!
    private var usingRowLayout = false

    /// Les jeux de contraintes sont crees une seule fois puis simplement
    /// (des)actives : les recreer a chaque reutilisation de cellule empilait
    /// des contraintes contradictoires.
    private func buildConstraintSets() {
        guard gridConstraints.isEmpty else { return }

        iconWidth = icon.widthAnchor.constraint(equalToConstant: 96)
        iconHeight = icon.heightAnchor.constraint(equalToConstant: 96)
        NSLayoutConstraint.activate([iconWidth, iconHeight])

        gridConstraints = [
            icon.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            icon.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            label.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 5),
            subtitle.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 1),
            subtitle.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ]
        rowConstraints = [
            icon.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            subtitle.leadingAnchor.constraint(equalTo: label.leadingAnchor),
            subtitle.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 1)
        ]
        NSLayoutConstraint.activate(gridConstraints)
        usingRowLayout = false
    }

    private func useRowLayout(_ wantsRow: Bool) {
        buildConstraintSets()
        guard wantsRow != usingRowLayout else { return }
        NSLayoutConstraint.deactivate(wantsRow ? gridConstraints : rowConstraints)
        NSLayoutConstraint.activate(wantsRow ? rowConstraints : gridConstraints)
        usingRowLayout = wantsRow
    }

    func configure(with item: FileItem, mode: ViewMode) {
        currentURL = item.url
        let side = mode.iconSide
        let rowLayout = (mode == .tiles || mode == .content || mode == .smallIcons)

        useRowLayout(rowLayout)
        iconWidth.constant = side
        iconHeight.constant = side

        label.alignment = rowLayout ? .left : .center
        label.stringValue = item.displayName
        label.isEditable = false

        switch mode {
        case .tiles:
            subtitle.stringValue = "\(item.kindDescription)  -  \(Fmt.size(item.effectiveSize))"
            subtitle.isHidden = false
        case .content:
            subtitle.stringValue = "\(Fmt.date(item.modificationDate))  -  \(Fmt.size(item.effectiveSize))"
            subtitle.isHidden = false
        default:
            subtitle.stringValue = ""
            subtitle.isHidden = true
        }

        icon.image = IconCache.shared.icon(for: item)
        icon.alphaValue = FileClipboard.shared.isMarkedForCut(item.url) ? 0.45 : 1

        if side >= 48, item.supportsThumbnail {
            let url = item.url
            let scale = view.window?.backingScaleFactor ?? 2
            if let cached = IconCache.shared.cachedThumbnail(for: url, side: side) {
                icon.image = cached
            } else {
                IconCache.shared.thumbnail(for: url, side: side, scale: scale) { [weak self] image in
                    guard let self, self.currentURL == url else { return }
                    self.icon.image = image
                }
            }
        }
        updateHighlight()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        currentURL = nil
        renameHandler = nil
        label.isEditable = false
        isSelected = false
    }

    /// Comme le Finder, seul un clic sur le nom arme le renommage.
    func isInsideName(windowPoint: NSPoint) -> Bool {
        label.bounds.contains(label.convert(windowPoint, from: nil))
    }

    func beginEditing(_ handler: @escaping (String) -> Void) {
        renameHandler = handler
        label.isEditable = true
        label.isSelectable = true
        view.window?.makeFirstResponder(label)
        label.currentEditor()?.selectAll(nil)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        label.isEditable = false
        guard let handler = renameHandler else { return }
        renameHandler = nil
        handler(label.stringValue)
    }

    override var isSelected: Bool { didSet { updateHighlight() } }
    override var highlightState: NSCollectionViewItem.HighlightState { didSet { updateHighlight() } }

    private func updateHighlight() {
        let selected = isSelected || highlightState == .forSelection
        background.layer?.backgroundColor = selected
            ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.85).cgColor
            : NSColor.clear.cgColor
        label.textColor = selected ? .alternateSelectedControlTextColor : .labelColor
    }
}

final class GridSectionHeader: NSView, NSCollectionViewElement {
    static let identifier = NSUserInterfaceItemIdentifier("GridSectionHeader")
    let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) non supporte") }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
