import AppKit
import SwiftUI
import Combine

/// Contenu de la fenetre : barre de commandes, barre d'adresse, split
/// (navigation | fichiers | details) et barre d'etat.
final class BrowserViewController: NSViewController {

    let model: WindowModel

    private let splitVC = NSSplitViewController()
    private var sidebarVC: SidebarViewController!
    private let fileAreaVC = FileAreaContainerViewController()
    private var detailsVC: NSViewController!

    private var sidebarItem: NSSplitViewItem!
    private var mainItem: NSSplitViewItem!
    private var inspectorItem: NSSplitViewItem!

    private var commandHost: NSHostingView<CommandBarView>!
    private var addressHost: NSHostingView<AddressBarView>!
    private var statusHost: NSHostingView<StatusBarView>!

    private var listVC: FileListViewController!
    private var gridVC: IconGridViewController!
    private var currentArea: FileAreaController?
    private var currentViewMode: ViewMode?

    private var cancellables = Set<AnyCancellable>()

    init(model: WindowModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supporte") }

    // MARK: - Construction

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1180, height: 700))

        sidebarVC = SidebarViewController(model: model)
        listVC = FileListViewController(model: model)
        gridVC = IconGridViewController(model: model)
        detailsVC = NSHostingController(rootView: DetailsPaneView(model: model))

        sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarVC)
        sidebarItem.minimumThickness = 190
        sidebarItem.maximumThickness = 380
        sidebarItem.canCollapse = true

        mainItem = NSSplitViewItem(viewController: fileAreaVC)
        mainItem.minimumThickness = 320
        mainItem.canCollapse = false

        inspectorItem = NSSplitViewItem(inspectorWithViewController: detailsVC)
        inspectorItem.minimumThickness = 260
        inspectorItem.maximumThickness = 420
        inspectorItem.isCollapsed = true

        splitVC.splitViewItems = [sidebarItem, mainItem, inspectorItem]
        splitVC.splitView.autosaveName = "MExplorerSplit"
        addChild(splitVC)

        commandHost = NSHostingView(rootView: CommandBarView(model: model))
        addressHost = NSHostingView(rootView: AddressBarView(model: model))
        statusHost = NSHostingView(rootView: StatusBarView(model: model))

        let stack = NSStackView(views: [commandHost, addressHost, splitVC.view, statusHost])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        var constraints: [NSLayoutConstraint] = [
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            commandHost.heightAnchor.constraint(equalToConstant: 40),
            addressHost.heightAnchor.constraint(equalToConstant: 38),
            statusHost.heightAnchor.constraint(equalToConstant: 24)
        ]
        // Une NSStackView verticale centre ses vues sur leur largeur intrinseque :
        // on les force a occuper toute la largeur.
        for arranged in [commandHost, addressHost, splitVC.view, statusHost] as [NSView] {
            constraints.append(arranged.leadingAnchor.constraint(equalTo: stack.leadingAnchor))
            constraints.append(arranged.trailingAnchor.constraint(equalTo: stack.trailingAnchor))
        }
        NSLayoutConstraint.activate(constraints)

        stack.setHuggingPriority(.defaultLow, for: .vertical)
        splitVC.view.setContentHuggingPriority(.defaultLow, for: .vertical)
        splitVC.view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        wireModel()
        attach(tab: model.activeTab)
        observePanes()
    }

    // MARK: - Cablage

    private func wireModel() {
        model.onActiveTabChanged = { [weak self] tab in self?.attach(tab: tab) }
        model.onBeginRename = { [weak self] url in
            DispatchQueue.main.async { self?.currentArea?.beginRename(url) }
        }
        model.onFocusFileList = { [weak self] in self?.currentArea?.focus() }
        model.shareAnchorProvider = { [weak self] in self?.currentArea?.view }

        QuickLookCoordinator.shared.frameProvider = { [weak self] url in
            self?.currentArea?.frameOnScreen(for: url)
        }

        NotificationCenter.default.publisher(for: FileClipboard.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.currentArea?.reloadContent() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: IconCache.changed)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.currentArea?.reloadContent() }
            .store(in: &cancellables)
    }

    private func observePanes() {
        // dropFirst : l'etat initial est deja celui fixe a la construction des items.
        model.$showSidebar
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] visible in self?.setCollapsed(self?.sidebarItem, !visible) }
            .store(in: &cancellables)

        Publishers.CombineLatest(model.$showDetailsPane, model.$showPreviewPane)
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] details, preview in
                self?.setCollapsed(self?.inspectorItem, !(details || preview))
            }
            .store(in: &cancellables)
    }

    /// Animer un NSSplitViewItem hors fenetre peut lever une exception pendant
    /// la passe de layout : on n'anime que lorsque la vue est a l'ecran.
    private func setCollapsed(_ item: NSSplitViewItem?, _ collapsed: Bool) {
        guard let item, item.isCollapsed != collapsed else { return }
        if view.window != nil {
            item.animator().isCollapsed = collapsed
        } else {
            item.isCollapsed = collapsed
        }
    }

    private var tabCancellables = Set<AnyCancellable>()

    private func attach(tab: TabState) {
        tabCancellables.removeAll()

        tab.onRowsChanged = { [weak self] in
            self?.currentArea?.reloadContent()
            self?.fileAreaVC.updateOverlay(for: tab, model: self?.model)
        }
        tab.onRequestSelection = { [weak self] urls in
            self?.currentArea?.applySelection(urls)
        }

        tab.$settings
            .receive(on: RunLoop.main)
            .sink { [weak self] settings in self?.switchArea(mode: settings.viewMode, tab: tab) }
            .store(in: &tabCancellables)

        tab.$location
            .receive(on: RunLoop.main)
            .sink { [weak self] location in
                guard let self else { return }
                self.sidebarVC.syncSelection(to: location)
                self.updateWindowTitle()
                if case .search = location {} else { self.model.searchFieldText = "" }
            }
            .store(in: &tabCancellables)

        currentViewMode = nil
        switchArea(mode: tab.settings.viewMode, tab: tab)
        fileAreaVC.updateOverlay(for: tab, model: model)
        sidebarVC.syncSelection(to: tab.location)
        updateWindowTitle()
    }

    private func switchArea(mode: ViewMode, tab: TabState) {
        let wantsGrid = mode.isIconGrid
        let needsSwap = currentViewMode == nil || (currentViewMode!.isIconGrid != wantsGrid) || currentArea == nil

        if needsSwap {
            let controller: (NSViewController & FileAreaController) = wantsGrid ? gridVC : listVC
            fileAreaVC.embed(controller)
            currentArea = controller
        }
        currentViewMode = mode
        currentArea?.attach(tab: tab)
        currentArea?.rebuildColumns()
    }

    private func updateWindowTitle() {
        (view.window?.windowController as? BrowserWindowController)?.updateTitle()
    }

    private var didApplyInitialPaneState = false

    override func viewDidAppear() {
        super.viewDidAppear()
        // La restauration automatique du NSSplitView ecrase l'etat fixe trop tot :
        // on applique la visibilite memorisee une fois la fenetre affichee.
        guard !didApplyInitialPaneState else { return }
        didApplyInitialPaneState = true
        setCollapsed(sidebarItem, !model.showSidebar)
        setCollapsed(inspectorItem, !(model.showDetailsPane || model.showPreviewPane))
    }

    func windowDidBecomeKey() {
        currentArea?.focus()
    }
}

/// Conteneur de la zone de fichiers : heberge la presentation courante
/// et affiche les etats vides / erreurs d'acces.
final class FileAreaContainerViewController: NSViewController {

    private var childArea: NSViewController?
    private var overlay: NSHostingView<FileAreaOverlay>?

    override func loadView() {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        view = v
    }

    func embed(_ controller: NSViewController) {
        guard childArea !== controller else { return }
        childArea?.view.removeFromSuperview()
        childArea?.removeFromParent()

        addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controller.view, positioned: .below, relativeTo: overlay)
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: view.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        childArea = controller
    }

    func updateOverlay(for tab: TabState, model: WindowModel?) {
        overlay?.removeFromSuperview()
        overlay = nil

        let state: FileAreaOverlay.State?
        if case .accessDenied(let url) = tab.loadError {
            state = .accessDenied(url)
        } else if tab.loadError != nil {
            state = .error(tab.loadError!)
        } else if tab.rows.isEmpty && !tab.isLoading {
            state = tab.filterText.isEmpty ? .empty : .noMatch
        } else {
            state = nil
        }

        guard let state, let model else { return }
        let host = NSHostingView(rootView: FileAreaOverlay(state: state, model: model))
        host.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host)
        NSLayoutConstraint.activate([
            host.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            host.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            host.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.8)
        ])
        overlay = host
    }
}

struct FileAreaOverlay: View {

    enum State {
        case empty
        case noMatch
        case accessDenied(URL)
        case error(Error)
    }

    let state: State
    let model: WindowModel

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 14, weight: .medium))
            if let detail {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if case .accessDenied(let url) = state {
                Button("Autoriser l'acces a ce dossier") {
                    model.requestAccess(for: url)
                }
                .controlSize(.large)
            }
        }
        .padding(24)
    }

    private var symbol: String {
        switch state {
        case .empty: return "tray"
        case .noMatch: return "magnifyingglass"
        case .accessDenied: return "lock"
        case .error: return "exclamationmark.triangle"
        }
    }

    private var title: String {
        switch state {
        case .empty: return "Ce dossier est vide"
        case .noMatch: return "Aucun element ne correspond"
        case .accessDenied: return "Acces non autorise"
        case .error: return "Impossible de lire ce dossier"
        }
    }

    private var detail: String? {
        switch state {
        case .empty: return nil
        case .noMatch: return "Modifiez le filtre ou appuyez sur Entree pour lancer une recherche Spotlight."
        case .accessDenied(let url):
            return "MExplorer fonctionne dans le bac a sable macOS.\nAutorisez \"\(url.lastPathComponent)\" pour afficher son contenu."
        case .error(let error): return (error as NSError).localizedDescription
        }
    }
}
