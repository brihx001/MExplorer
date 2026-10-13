import AppKit

/// Construction de la barre de menus. Les raccourcis reprennent ceux de
/// l'Explorateur Windows quand ils ne heurtent pas une convention macOS.
enum MainMenu {

    private static var model: WindowModel? { WindowManager.shared.keyModel }
    private static var tab: TabState? { model?.activeTab }

    static func install() {
        let main = NSMenu()
        main.addItem(appMenu())
        main.addItem(fileMenu())
        main.addItem(editMenu())
        main.addItem(viewMenu())
        main.addItem(goMenu())
        main.addItem(windowMenu())
        main.addItem(helpMenu())
        NSApp.mainMenu = main
    }

    // MARK: - Fabriques

    private static func submenu(_ title: String, _ build: (NSMenu) -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        menu.autoenablesItems = true
        build(menu)
        item.submenu = menu
        return item
    }

    @discardableResult
    private static func add(_ menu: NSMenu, _ title: String,
                            _ key: String = "", _ mods: NSEvent.ModifierFlags = .command,
                            enabled: (() -> Bool)? = nil,
                            state: (() -> Bool)? = nil,
                            _ handler: @escaping () -> Void) -> BlockMenuItem {
        let item = BlockMenuItem(title: title, keyEquivalent: key, modifiers: mods, handler: handler)
        item.validator = enabled
        item.stateProvider = state
        menu.addItem(item)
        return item
    }

    private static func fn(_ code: Int) -> String { String(UnicodeScalar(UInt32(code))!) }

    // MARK: - Menus

    private static func appMenu() -> NSMenuItem {
        submenu("MExplorer") { menu in
            add(menu, L("A propos de MExplorer")) { NSApp.orderFrontStandardAboutPanel(nil) }
            menu.addItem(.separator())
            add(menu, L("Reglages..."), ",") { PreferencesWindowController.show() }
            menu.addItem(.separator())
            add(menu, L("Autoriser l'acces a tout le disque...")) {
                if AccessManager.shared.requestWholeDisk(window: NSApp.keyWindow) != nil {
                    WindowManager.shared.controllers.forEach { controller in
                        controller.model.tabs.forEach { $0.reload() }
                    }
                }
            }
            add(menu, L("Autoriser l'acces a un dossier..."), "o", [.command, .shift]) {
                if AccessManager.shared.requestAccess(
                    to: SidebarCatalog.home,
                    message: L("Choisissez un dossier auquel MExplorer pourra acceder durablement."),
                    window: NSApp.keyWindow) != nil {
                    model?.activeTab.reload()
                }
            }
            menu.addItem(.separator())
            let services = NSMenuItem(title: L("Services"), action: nil, keyEquivalent: "")
            services.submenu = NSMenu(title: L("Services"))
            NSApp.servicesMenu = services.submenu
            menu.addItem(services)
            menu.addItem(.separator())
            add(menu, L("Masquer MExplorer"), "h") { NSApp.hide(nil) }
            add(menu, L("Masquer les autres"), "h", [.command, .option]) { NSApp.hideOtherApplications(nil) }
            add(menu, L("Tout afficher")) { NSApp.unhideAllApplications(nil) }
            menu.addItem(.separator())
            add(menu, L("Quitter MExplorer"), "q") { NSApp.terminate(nil) }
        }
    }

    private static func fileMenu() -> NSMenuItem {
        submenu(L("Fichier")) { menu in
            add(menu, L("Nouvelle fenetre"), "n") { WindowManager.shared.openWindow() }
            add(menu, L("Nouvel onglet"), "t") { model?.newTab() }
            add(menu, L("Nouveau dossier"), "n", [.command, .shift]) { model?.newFolder() }
            add(menu, L("Nouveau document texte")) { model?.newFile(named: "Nouveau document.txt") }
            menu.addItem(.separator())
            add(menu, L("Ouvrir"), "o", enabled: { model?.selection.isEmpty == false }) {
                model.map { $0.activate($0.selection) }
            }
            add(menu, L("Ouvrir dans un nouvel onglet"), "\r", [.command, .option],
                enabled: { model?.selection.contains { $0.isNavigableContainer } == true }) {
                model?.selection.filter { $0.isNavigableContainer }.forEach { model?.openInNewTab($0.url) }
            }
            add(menu, L("Coup d'oeil"), "y", enabled: { model?.selection.isEmpty == false }) {
                model?.toggleQuickLook()
            }
            add(menu, L("Lire les informations"), "i", enabled: { model?.selection.isEmpty == false }) {
                model?.showInfoWindow()
            }
            menu.addItem(.separator())
            add(menu, L("Fermer l'onglet"), "w") { model?.closeActiveTab() }
            add(menu, L("Fermer la fenetre"), "w", [.command, .shift]) { NSApp.keyWindow?.performClose(nil) }
            menu.addItem(.separator())
            add(menu, L("Dupliquer"), "d", enabled: { model?.selection.isEmpty == false }) {
                model?.duplicateSelection()
            }
            add(menu, L("Creer un alias"), "a", [.command, .control],
                enabled: { model?.selection.isEmpty == false }) { model?.makeAliasForSelection() }
            add(menu, L("Compresser"), enabled: { model?.selection.isEmpty == false }) {
                model?.compressSelection()
            }
            menu.addItem(.separator())
            add(menu, L("Placer dans la corbeille"), fn(NSDeleteCharacter), [.command],
                enabled: { model?.selection.isEmpty == false }) { model?.trashSelection() }
            add(menu, L("Supprimer definitivement"), fn(NSDeleteCharacter), [.command, .shift],
                enabled: { model?.selection.isEmpty == false }) { model?.deleteSelectionPermanently() }
            add(menu, L("Vider la corbeille...")) { model?.emptyTrash() }
            menu.addItem(.separator())
            add(menu, L("Afficher dans le Finder")) { model?.revealInFinder() }
        }
    }

    private static func editMenu() -> NSMenuItem {
        submenu(L("Edition")) { menu in
            add(menu, L("Annuler"), "z", enabled: { NSApp.keyWindow?.undoManager?.canUndo ?? false }) {
                NSApp.keyWindow?.undoManager?.undo()
            }
            add(menu, L("Retablir"), "z", [.command, .shift],
                enabled: { NSApp.keyWindow?.undoManager?.canRedo ?? false }) {
                NSApp.keyWindow?.undoManager?.redo()
            }
            menu.addItem(.separator())
            add(menu, L("Couper"), "x", enabled: { model?.selection.isEmpty == false }) { model?.cutSelection() }
            add(menu, L("Copier"), "c", enabled: { model?.selection.isEmpty == false }) { model?.copySelection() }
            add(menu, L("Copier le chemin d'acces"), "c", [.command, .shift, .option],
                enabled: { model?.selection.isEmpty == false }) { model?.copySelectionPaths() }
            add(menu, L("Coller"), "v", enabled: { FileClipboard.shared.canPaste }) { model?.paste() }
            add(menu, L("Coller un raccourci"), "v", [.command, .shift],
                enabled: { FileClipboard.shared.canPaste }) { model?.pasteShortcut() }
            menu.addItem(.separator())
            add(menu, L("Tout selectionner"), "a") { tab?.selectAll() }
            add(menu, L("Renommer"), fn(NSF2FunctionKey), [],
                enabled: { model?.selection.count == 1 }) { model?.beginRenameSelection() }
            menu.addItem(.separator())
            add(menu, L("Rechercher"), "f") { model?.focusSearch() }
            add(menu, L("Aller au dossier..."), "l") { model?.isAddressBarEditing = true }
        }
    }

    private static func viewMenu() -> NSMenuItem {
        submenu(L("Presentation")) { menu in
            for (index, mode) in ViewMode.allCases.enumerated() {
                add(menu, mode.title, "\(index + 1)",
                    state: { tab?.settings.viewMode == mode }) {
                    tab?.update { $0.viewMode = mode }
                }
            }
            menu.addItem(.separator())
            let sort = NSMenuItem(title: L("Trier par"), action: nil, keyEquivalent: "")
            let sortMenu = NSMenu(title: L("Trier par"))
            for key in SortKey.allCases {
                add(sortMenu, key.title, state: { tab?.settings.sortKey == key }) { tab?.toggleSort(key) }
            }
            sort.submenu = sortMenu
            menu.addItem(sort)

            let group = NSMenuItem(title: L("Grouper par"), action: nil, keyEquivalent: "")
            let groupMenu = NSMenu(title: L("Grouper par"))
            for key in GroupKey.allCases {
                add(groupMenu, key.title, state: { tab?.settings.groupKey == key }) {
                    tab?.update { $0.groupKey = key }
                }
            }
            group.submenu = groupMenu
            menu.addItem(group)

            menu.addItem(.separator())
            add(menu, L("Volet de navigation"), "s", [.command, .control],
                state: { model?.showSidebar == true }) { model?.showSidebar.toggle() }
            add(menu, L("Volet de details"), "p", [.command, .shift],
                state: { model?.showDetailsPane == true }) { model?.showDetailsPane.toggle() }
            add(menu, L("Volet d'apercu"), "p", [.command, .option],
                state: { model?.showPreviewPane == true }) { model?.showPreviewPane.toggle() }
            menu.addItem(.separator())
            add(menu, L("Elements masques"), ".", [.command, .shift],
                state: { AppSettings.shared.showHiddenItems }) {
                AppSettings.shared.toggleHiddenItems()
            }
            add(menu, L("Extensions de noms de fichiers"),
                state: { AppSettings.shared.showFileExtensions }) {
                AppSettings.shared.showFileExtensions.toggle()
                tab?.rebuildRows()
            }
            add(menu, L("Calculer la taille des dossiers"),
                enabled: { tab?.settings.viewMode == .details },
                state: { tab?.settings.calculateFolderSizes == true }) {
                guard let tab else { return }
                let value = !tab.settings.calculateFolderSizes
                tab.update { $0.calculateFolderSizes = value }
            }
            menu.addItem(.separator())
            add(menu, L("Actualiser"), "r") { tab?.reload() }
        }
    }

    private static func goMenu() -> NSMenuItem {
        submenu(L("Aller")) { menu in
            add(menu, L("Precedent"), "[", enabled: { tab?.canGoBack ?? false }) { tab?.goBack() }
            add(menu, L("Suivant"), "]", enabled: { tab?.canGoForward ?? false }) { tab?.goForward() }
            add(menu, L("Dossier parent"), fn(NSUpArrowFunctionKey), [.command],
                enabled: { tab?.canGoUp ?? false }) { tab?.goUp() }
            menu.addItem(.separator())
            add(menu, L("Depart"), "h", [.command, .shift]) { model?.open(SidebarCatalog.home) }
            if let desktop = SidebarCatalog.standardDirectory(.desktopDirectory) {
                add(menu, L("Bureau"), "d", [.command, .shift]) { model?.open(desktop) }
            }
            if let documents = SidebarCatalog.standardDirectory(.documentDirectory) {
                add(menu, L("Documents"), "o", [.command, .shift, .option]) { model?.open(documents) }
            }
            if let downloads = SidebarCatalog.standardDirectory(.downloadsDirectory) {
                add(menu, L("Telechargements"), "l", [.command, .option]) { model?.open(downloads) }
            }
            add(menu, L("Applications"), "a", [.command, .shift]) { model?.open(SidebarCatalog.applications) }
            if let icloud = SidebarCatalog.iCloudDrive {
                add(menu, L("iCloud Drive")) { model?.open(icloud) }
            }
            if let trash = SidebarCatalog.trash {
                add(menu, L("Corbeille")) { model?.open(trash) }
            }
            menu.addItem(.separator())
            add(menu, L("Ce Mac"), "c", [.command, .shift]) { model?.go(to: .thisMac) }
            add(menu, L("Recents")) { model?.go(to: .recents) }
            menu.addItem(.separator())
            add(menu, L("Aller au dossier..."), "g", [.command, .shift]) { model?.isAddressBarEditing = true }
        }
    }

    private static func windowMenu() -> NSMenuItem {
        let item = submenu(L("Fenetre")) { menu in
            add(menu, L("Reduire"), "m") { NSApp.keyWindow?.miniaturize(nil) }
            add(menu, L("Zoom")) { NSApp.keyWindow?.zoom(nil) }
            menu.addItem(.separator())
            add(menu, L("Onglet suivant"), fn(0xF702), [.command, .option]) { model?.selectNextTab() }
            add(menu, L("Onglet precedent"), fn(0xF703), [.command, .option]) { model?.selectPreviousTab() }
            menu.addItem(.separator())
            add(menu, L("Tout ramener au premier plan")) { NSApp.arrangeInFront(nil) }
        }
        NSApp.windowsMenu = item.submenu
        return item
    }

    private static func helpMenu() -> NSMenuItem {
        let item = submenu(L("Aide")) { menu in
            add(menu, L("Raccourcis clavier")) { ShortcutsWindowController.show() }
        }
        NSApp.helpMenu = item.submenu
        return item
    }
}
