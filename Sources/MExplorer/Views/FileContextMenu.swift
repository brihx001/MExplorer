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
        menu.addBlockItem(L("Afficher dans le Finder")) { model.revealInFinder() }
        menu.addBlockItem(L("Proprietes du dossier"), enabled: inFolder) { model.showFolderInfoWindow() }
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
                let sub = NSMenu()
                for app in apps {
                    let icon = NSWorkspace.shared.icon(forFile: app.path)
                    icon.size = NSSize(width: 16, height: 16)
                    let item = BlockMenuItem(title: OpenWith.name(of: app), image: icon) {
                        model.openWith(application: app)
                    }
                    sub.addItem(item)
                }
                sub.addItem(.separator())
                sub.addBlockItem(L("Autre application...")) { OpenWith.chooseApplication(model: model) }
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

        menu.addItem(.separator())
        menu.addBlockItem(L("Renommer"), enabled: items.count == 1, symbol: "pencil") {
            model.beginRenameSelection()
        }
        menu.addBlockItem(L("Dupliquer"), symbol: "plus.square.on.square") { model.duplicateSelection() }
        menu.addBlockItem(L("Creer un alias"), symbol: "arrowshape.turn.up.left") { model.makeAliasForSelection() }
        menu.addBlockItem(L("Compresser"), symbol: "archivebox") { model.compressSelection() }

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
