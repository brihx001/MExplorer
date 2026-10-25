import SwiftUI

/// Barre de commandes facon Windows 11 (Nouveau, Couper/Copier/Coller, Trier, Afficher...).
struct CommandBarView: View {

    @ObservedObject var model: WindowModel
    /// Redessine la vue quand la langue (ou un reglage global) change.
    @ObservedObject private var appSettings = AppSettings.shared

    private var tab: TabState { model.activeTab }
    private var hasSelection: Bool { model.hasSelection }
    private var inFolder: Bool { model.currentFolder != nil }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(appSettings.commandBarItems) { item in
                if CommandBarItem.separatorsBefore.contains(item) { divider }
                content(for: item)
            }

            Spacer(minLength: 8)

            Toggle(isOn: $model.showPreviewPane) {
                Image(systemName: "sidebar.squares.right")
            }
            .toggleStyle(.button)
            .help(L("Volet d'apercu"))

            Toggle(isOn: $model.showDetailsPane) {
                Image(systemName: "info.circle")
            }
            .toggleStyle(.button)
            .help(L("Volet de details"))
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
    }

    private var divider: some View {
        Divider().frame(height: 18).padding(.horizontal, 4)
    }

    /// Chaque element de la barre, dans l'ordre choisi par l'utilisateur.
    @ViewBuilder
    private func content(for item: CommandBarItem) -> some View {
        switch item {
        case .newMenu: newMenu
        case .cut:
            iconButton(item.symbol, item.title, L("Cmd X"), enabled: hasSelection) { model.cutSelection() }
        case .copy:
            iconButton(item.symbol, item.title, L("Cmd C"), enabled: hasSelection) { model.copySelection() }
        case .paste:
            iconButton(item.symbol, item.title, L("Cmd V"),
                       enabled: inFolder && FileClipboard.shared.canPaste) { model.paste() }
        case .rename:
            iconButton(item.symbol, item.title, L("Entree"), enabled: model.selectionCount == 1) {
                model.beginRenameSelection()
            }
        case .share:
            iconButton(item.symbol, item.title, nil, enabled: hasSelection) { model.shareSelection() }
        case .trash:
            iconButton(item.symbol, item.title, L("Cmd Suppr"), enabled: hasSelection) {
                model.trashSelection()
            }
        case .compress:
            iconButton(item.symbol, item.title, nil, enabled: hasSelection) { model.compressSelection() }
        case .checksum:
            iconButton(item.symbol, item.title, nil,
                       enabled: model.selection.contains { !$0.isDirectory }) { model.showChecksums() }
        case .terminal:
            iconButton(item.symbol, item.title, nil,
                       enabled: model.targetFolder != nil && !TerminalLauncher.installed.isEmpty) {
                if let first = TerminalLauncher.installed.first { model.openInTerminal(first) }
            }
        case .sortMenu: sortMenu
        case .viewMenu: viewMenu
        case .moreMenu: moreMenu
        }
    }

    private func iconButton(_ symbol: String, _ title: String, _ shortcut: String?,
                            enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .frame(width: 28, height: 24)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .help(shortcut.map { "\(title) (\($0))" } ?? title)
    }

    // MARK: - Menus

    private var newMenu: some View {
        Menu {
            Button(L("Dossier")) { model.newFolder() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button(L("Document texte")) { model.newFile(named: "Nouveau document.txt") }
            Button(L("Document RTF")) { model.newFile(named: "Nouveau document.rtf") }
            Divider()
            Button(L("Coller un raccourci")) { model.pasteShortcut() }
                .disabled(!FileClipboard.shared.canPaste)
        } label: {
            Label(L("Nouveau"), systemImage: "plus")
                .font(.system(size: 12))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(!inFolder)
    }

    private var sortMenu: some View {
        Menu {
            ForEach(SortKey.allCases, id: \.self) { key in
                Button {
                    tab.toggleSort(key)
                } label: {
                    if tab.settings.sortKey == key {
                        Label(key.title, systemImage: tab.settings.ascending ? "arrow.up" : "arrow.down")
                    } else {
                        Text(key.title)
                    }
                }
            }
            Divider()
            Button(L("Croissant")) { tab.update { $0.ascending = true } }
            Button(L("Decroissant")) { tab.update { $0.ascending = false } }
            Divider()
            Menu(L("Grouper par")) {
                ForEach(GroupKey.allCases, id: \.self) { key in
                    Button {
                        tab.update { $0.groupKey = key }
                    } label: {
                        if tab.settings.groupKey == key { Label(key.title, systemImage: "checkmark") }
                        else { Text(key.title) }
                    }
                }
            }
            Divider()
            Toggle(L("Dossiers en premier"), isOn: Binding(
                get: { tab.settings.foldersFirst },
                set: { v in tab.update { $0.foldersFirst = v } }
            ))
        } label: {
            Label(L("Trier"), systemImage: "arrow.up.arrow.down")
                .font(.system(size: 12))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var viewMenu: some View {
        Menu {
            ForEach(ViewMode.allCases, id: \.self) { mode in
                Button {
                    tab.update { $0.viewMode = mode }
                } label: {
                    if tab.settings.viewMode == mode { Label(mode.title, systemImage: "checkmark") }
                    else { Text(mode.title) }
                }
            }
            Divider()
            Menu(L("Afficher")) {
                Toggle(L("Volet de navigation"), isOn: $model.showSidebar)
                Toggle(L("Volet de details"), isOn: $model.showDetailsPane)
                Toggle(L("Volet d'apercu"), isOn: $model.showPreviewPane)
                Divider()
                Toggle(L("Extensions de noms de fichiers"), isOn: Binding(
                    get: { AppSettings.shared.showFileExtensions },
                    set: { AppSettings.shared.showFileExtensions = $0; tab.rebuildRows() }
                ))
                Toggle(L("Calculer la taille des dossiers"), isOn: Binding(
                    get: { tab.settings.calculateFolderSizes },
                    set: { v in tab.update { $0.calculateFolderSizes = v } }
                ))
            }
            Divider()
            Toggle(L("Elements masques"), isOn: Binding(
                get: { AppSettings.shared.showHiddenItems },
                set: { AppSettings.shared.showHiddenItems = $0 }
            ))
            Divider()
            Menu(L("Colonnes")) {
                ForEach(ColumnID.allCases, id: \.self) { column in
                    Toggle(column.title, isOn: Binding(
                        get: { tab.settings.visibleColumns.contains(column) },
                        set: { on in
                            tab.update { s in
                                if on {
                                    if !s.visibleColumns.contains(column) { s.visibleColumns.append(column) }
                                } else if column != .name {
                                    s.visibleColumns.removeAll { $0 == column }
                                }
                            }
                        }
                    ))
                }
            }
            Divider()
            Button(L("Appliquer ces reglages a tous les dossiers")) {
                FolderSettingsStore.shared.applyToAllFolders(tab.settings)
            }
        } label: {
            Label(L("Afficher"), systemImage: tab.settings.viewMode.symbol)
                .font(.system(size: 12))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var moreMenu: some View {
        Menu {
            Button(L("Ouvrir dans un nouvel onglet")) {
                if let url = model.selection.first(where: { $0.isNavigableContainer })?.url {
                    model.openInNewTab(url)
                }
            }.disabled(!model.selection.contains { $0.isNavigableContainer })
            Button(L("Ouvrir dans une nouvelle fenetre")) {
                if let url = model.selection.first(where: { $0.isNavigableContainer })?.url {
                    model.openInNewWindow(url)
                }
            }.disabled(!model.selection.contains { $0.isNavigableContainer })
            Divider()
            Button(L("Dupliquer")) { model.duplicateSelection() }.disabled(!hasSelection)
            Button(L("Creer un alias")) { model.makeAliasForSelection() }.disabled(!hasSelection)
            Button(L("Compresser")) { model.compressSelection() }.disabled(!hasSelection)
            Divider()
            Button(L("Copier le chemin d'acces")) { model.copySelectionPaths() }.disabled(!hasSelection)
            Button(L("Afficher dans le Finder")) { model.revealInFinder() }
            Divider()
            Button(L("Personnaliser la barre de commandes...")) { CommandBarEditorController.show() }
            Divider()
            Menu(L("Tags")) {
                ForEach(TagManager.knownTags, id: \.self) { tag in
                    Button(tag) { model.toggleTag(tag) }
                }
            }.disabled(!hasSelection)
            Divider()
            Button(L("Supprimer definitivement")) { model.deleteSelectionPermanently() }
                .disabled(!hasSelection)
            Button(L("Proprietes")) { model.showInfoWindow() }.disabled(!hasSelection)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
