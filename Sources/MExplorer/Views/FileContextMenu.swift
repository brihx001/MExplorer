import AppKit

/// Menu contextuel de la zone de fichiers : reprend l'ordre de Windows 11
/// et y ajoute les entrees natives du Finder (Coup d'oeil, tags, services, partage).
enum FileContextMenu {

    static func build(for items: [FileItem], model: WindowModel, anchorView: NSView) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        if items.isEmpty {
            buildBackgroundMenu(menu, model: model)
        } else {
            buildSelectionMenu(menu, items: items, model: model, anchorView: anchorView)
        }
        return menu
    }

    // MARK: - Clic dans le vide

    private static func buildBackgroundMenu(_ menu: NSMenu, model: WindowModel) {
        let inFolder = model.currentFolder != nil
        let tab = model.activeTab

        let newMenu = NSMenu()
        newMenu.addBlockItem(L("Dossier"), enabled: inFolder, symbol: "folder") { model.newFolder() }
        newMenu.addItem(.separator())
        newMenu.addBlockItem(L("Document texte"), enabled: inFolder, symbol: "doc.text") {
            model.newFile(named: L("Nouveau document.txt"))
        }
        newMenu.addBlockItem(L("Document RTF"), enabled: inFolder, symbol: "doc.richtext") {
            model.newFile(named: L("Nouveau document.rtf"))
        }
        let newItem = NSMenuItem(title: L("Nouveau"), action: nil, keyEquivalent: "")
        newItem.submenu = newMenu
        menu.addItem(newItem)

        menu.addItem(.separator())
        menu.addBlockItem(L("Coller"), enabled: inFolder && FileClipboard.shared.canPaste, symbol: "doc.on.clipboard") {
            model.paste()
        }
        menu.addBlockItem(L("Coller un raccourci"), enabled: inFolder && FileClipboard.shared.canPaste) {
            model.pasteShortcut()
        }
        menu.addItem(.separator())

        let sortMenu = NSMenu()
        for key in SortKey.allCases {
            let item = sortMenu.addBlockItem(key.title) { tab.toggleSort(key) }
            item.state = tab.settings.sortKey == key ? .on : .off
        }
        let sortItem = NSMenuItem(title: L("Trier par"), action: nil, keyEquivalent: "")
        sortItem.submenu = sortMenu
        menu.addItem(sortItem)

        let groupMenu = NSMenu()
        for key in GroupKey.allCases {
            let item = groupMenu.addBlockItem(key.title) { tab.update { $0.groupKey = key } }
            item.state = tab.settings.groupKey == key ? .on : .off
        }
        let groupItem = NSMenuItem(title: L("Grouper par"), action: nil, keyEquivalent: "")
        groupItem.submenu = groupMenu
        menu.addItem(groupItem)

        let viewMenu = NSMenu()
        for mode in ViewMode.allCases {
            let item = viewMenu.addBlockItem(mode.title) { tab.update { $0.viewMode = mode } }
            item.state = tab.settings.viewMode == mode ? .on : .off
        }
        let viewItem = NSMenuItem(title: L("Affichage"), action: nil, keyEquivalent: "")
        viewItem.submenu = viewMenu
        menu.addItem(viewItem)

        menu.addItem(.separator())
        let hidden = menu.addBlockItem(L("Afficher les elements masques")) {
            AppSettings.shared.toggleHiddenItems()
        }
        hidden.state = AppSettings.shared.showHiddenItems ? .on : .off
        menu.addBlockItem(L("Actualiser"), symbol: "arrow.clockwise") { tab.reload() }
        if let folder = model.currentFolder, folder.lastPathComponent == ".Trash" {
            menu.addItem(.separator())
            menu.addBlockItem(L("Vider la corbeille..."), symbol: "trash.slash") { model.emptyTrash() }
        }

        menu.addItem(.separator())
        menu.addBlockItem(L("Occupation du dossier..."), enabled: inFolder, symbol: "chart.pie") {
            model.showDiskUsage()
        }

        menu.addItem(.separator())
        menu.addBlockItem(L("Tout selectionner")) { tab.selectAll() }
        menu.addBlockItem(L("Inverser la selection")) { tab.invertSelection() }
        menu.addBlockItem(L("Selectionner par motif...")) { model.promptForSelectionPattern() }

        menu.addItem(.separator())
        addTerminalItems(to: menu, model: model, folder: model.currentFolder)
        menu.addBlockItem(L("Afficher dans le Finder")) { model.revealInFinder() }
        menu.addBlockItem(L("Proprietes du dossier"), enabled: inFolder) { model.showFolderInfoWindow() }
    }

    /// « Deplacer vers » et « Copier vers » : favoris et destinations
    /// recentes, puis le selecteur systeme.
    private static func addTransferItems(to menu: NSMenu, model: WindowModel) {
        let destinations = model.transferDestinations()
        for (kind, title) in [(FileOperations.TransferKind.move, L("Deplacer vers")),
                              (FileOperations.TransferKind.copy, L("Copier vers"))] {
            let sub = NSMenu()
            for destination in destinations {
                let item = sub.addBlockItem(destination.lastPathComponent) {
                    model.transferSelection(to: destination, kind: kind)
                }
                let icon = NSWorkspace.shared.icon(forFile: destination.path)
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
                item.toolTip = destination.path
            }
            if !destinations.isEmpty { sub.addItem(.separator()) }
            sub.addBlockItem(L("Autre dossier...")) { model.chooseTransferDestination(kind: kind) }
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = sub
            menu.addItem(item)
        }
    }

    /// « Ouvrir dans le Terminal », au singulier si un seul terminal est
    /// installe, en sous-menu sinon.
    private static func addTerminalItems(to menu: NSMenu, model: WindowModel, folder: URL?) {
        guard folder ?? model.currentFolder != nil else { return }
        let terminals = TerminalLauncher.installed
        guard !terminals.isEmpty else { return }
        if terminals.count == 1, let only = terminals.first {
            menu.addBlockItem(L("Ouvrir dans le Terminal"), symbol: "terminal") {
                model.openInTerminal(only)
            }
            return
        }
        let sub = NSMenu()
        for terminal in terminals {
            sub.addBlockItem(terminal.name) { model.openInTerminal(terminal) }
        }
        let item = NSMenuItem(title: L("Ouvrir dans le Terminal"), action: nil, keyEquivalent: "")
        item.submenu = sub
        menu.addItem(item)
    }

    // MARK: - Clic sur une selection

    private static func buildSelectionMenu(_ menu: NSMenu, items: [FileItem],
                                           model: WindowModel, anchorView: NSView) {
        let single = items.count == 1 ? items[0] : nil
        let urls = items.map(\.url)
        let hasFolder = items.contains { $0.isNavigableContainer }

        menu.addBlockItem(L("Ouvrir"), symbol: "arrow.up.forward.app") { model.activate(items) }

        if hasFolder {
            let folders = items.filter { $0.isNavigableContainer }
            menu.addBlockItem(L("Ouvrir dans un nouvel onglet")) {
                folders.forEach { model.openInNewTab($0.url) }
            }
            menu.addBlockItem(L("Ouvrir dans une nouvelle fenetre")) {
                folders.forEach { model.openInNewWindow($0.url) }
            }
            let favorites = Set(AppSettings.shared.favoritePaths)
            if folders.allSatisfy({ favorites.contains($0.url.path) }) {
                menu.addBlockItem(L("Retirer de l'acces rapide"), symbol: "star.slash") {
                    folders.forEach { AppSettings.shared.removeFavorite($0.url) }
                }
            } else {
                menu.addBlockItem(L("Ajouter a l'acces rapide"), symbol: "star") {
                    folders.forEach { AppSettings.shared.addFavorite($0.url) }
                }
            }
        }

        if let single, !single.isNavigableContainer {
            let apps = OpenWith.applications(for: single.url)
            if !apps.isEmpty {
                let current = OpenWith.defaultApplication(for: single.url)
                let sub = NSMenu()
                for app in apps {
                    let icon = NSWorkspace.shared.icon(forFile: app.path)
                    icon.size = NSSize(width: 16, height: 16)
                    let isDefault = app.standardizedFileURL == current?.standardizedFileURL
                    let title = isDefault ? L("%@ (par defaut)", OpenWith.name(of: app)) : OpenWith.name(of: app)
                    let item = BlockMenuItem(title: title, image: icon) {
                        model.openWith(application: app)
                    }
                    sub.addItem(item)
                }
                sub.addItem(.separator())
                sub.addBlockItem(L("Autre application...")) { OpenWith.chooseApplication(model: model) }

                // « Toujours ouvrir avec » porte sur le type du fichier, comme
                // « Tout modifier » du Finder : c'est la seule granularite que
                // LaunchServices expose.
                let always = NSMenu()
                for app in apps where app.standardizedFileURL != current?.standardizedFileURL {
                    let icon = NSWorkspace.shared.icon(forFile: app.path)
                    icon.size = NSSize(width: 16, height: 16)
                    let item = BlockMenuItem(title: OpenWith.name(of: app), image: icon) {
                        model.setDefaultApplication(app, for: single.url)
                    }
                    always.addItem(item)
                }
                if always.numberOfItems > 0 {
                    sub.addItem(.separator())
                    let alwaysItem = NSMenuItem(title: L("Toujours ouvrir avec"), action: nil, keyEquivalent: "")
                    alwaysItem.submenu = always
                    sub.addItem(alwaysItem)
                }

                let openWith = NSMenuItem(title: L("Ouvrir avec"), action: nil, keyEquivalent: "")
                openWith.submenu = sub
                menu.addItem(openWith)
            }
        }

        menu.addItem(.separator())
        menu.addBlockItem(L("Coup d'oeil"), symbol: "eye") { QuickLookCoordinator.shared.toggle(urls: urls) }

        menu.addItem(.separator())
        menu.addBlockItem(L("Couper"), symbol: "scissors") { model.cutSelection() }
        menu.addBlockItem(L("Copier"), symbol: "doc.on.doc") { model.copySelection() }
        if hasFolder, let single, single.isNavigableContainer {
            menu.addBlockItem(L("Coller dans ce dossier"), enabled: FileClipboard.shared.canPaste) {
                FileClipboard.shared.paste(into: single.url, undoManager: model.undoManager)
            }
        }
        menu.addBlockItem(L("Copier le chemin d'acces")) { model.copySelectionPaths() }
        let copyAs = NSMenu()
        copyAs.addBlockItem(L("Nom seul")) { model.copySelectionNames() }
        copyAs.addBlockItem(L("URL de fichier")) { model.copySelectionFileURLs() }
        let copyAsItem = NSMenuItem(title: L("Copier sous la forme"), action: nil, keyEquivalent: "")
        copyAsItem.submenu = copyAs
        menu.addItem(copyAsItem)

        menu.addItem(.separator())
        menu.addBlockItem(L("Renommer"), enabled: items.count == 1, symbol: "pencil") {
            model.beginRenameSelection()
        }
        menu.addBlockItem(L("Renommer par lot..."), enabled: items.count > 1, symbol: "textformat") {
            model.showBatchRename()
        }
        addTransferItems(to: menu, model: model)
        menu.addBlockItem(L("Dupliquer"), symbol: "plus.square.on.square") { model.duplicateSelection() }
        menu.addBlockItem(L("Creer un alias"), symbol: "arrowshape.turn.up.left") { model.makeAliasForSelection() }
        menu.addBlockItem(L("Compresser"), symbol: "archivebox") { model.compressSelection() }
        if items.contains(where: { !$0.isDirectory }) {
            menu.addBlockItem(L("Somme de controle..."), symbol: "number") { model.showChecksums() }
        }
        if single?.isNavigableContainer == true {
            menu.addBlockItem(L("Occupation du dossier..."), symbol: "chart.pie") { model.showDiskUsage() }
        }
        addTerminalItems(to: menu, model: model, folder: single?.isNavigableContainer == true ? single?.url : nil)

        menu.addItem(.separator())
        let tagsMenu = NSMenu()
        let currentTags = Set(items.flatMap { $0.tagNames })
        for tag in TagManager.knownTags {
            let item = tagsMenu.addBlockItem(tag) { model.toggleTag(tag) }
            item.state = currentTags.contains(tag) ? .on : .off
            if let color = SidebarCatalog.color(forTag: tag) {
                item.image = dot(color)
            }
        }
        tagsMenu.addItem(.separator())
        tagsMenu.addBlockItem(L("Nouveau tag...")) { model.promptForNewTag() }
        let tagsItem = NSMenuItem(title: L("Tags"), action: nil, keyEquivalent: "")
        tagsItem.submenu = tagsMenu
        menu.addItem(tagsItem)

        menu.addBlockItem(L("Partager..."), symbol: "square.and.arrow.up") {
            model.shareSelection()
        }

        let servicesItem = NSMenuItem(title: L("Services"), action: nil, keyEquivalent: "")
        servicesItem.submenu = NSMenu()
        menu.addItem(servicesItem)
        NSApp.servicesMenu = servicesItem.submenu

        menu.addItem(.separator())
        menu.addBlockItem(L("Placer dans la corbeille"), symbol: "trash") { model.trashSelection() }
        menu.addBlockItem(L("Supprimer definitivement"), symbol: "trash.slash") { model.deleteSelectionPermanently() }

        menu.addItem(.separator())
        menu.addBlockItem(L("Afficher dans le Finder")) { model.revealInFinder() }
        menu.addBlockItem(L("Proprietes"), symbol: "info.circle") { model.showInfoWindow() }
    }

    private static func dot(_ color: NSColor) -> NSImage {
        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: 8, height: 8)).fill()
        image.unlockFocus()
        return image
    }
}

private extension BlockMenuItem {
    convenience init(title: String, image: NSImage?, handler: @escaping () -> Void) {
        self.init(title: title, keyEquivalent: "", modifiers: .command, enabled: true,
                  image: image, handler: handler)
    }
}
