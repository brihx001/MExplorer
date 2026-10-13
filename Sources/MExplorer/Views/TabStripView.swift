import SwiftUI
import UniformTypeIdentifiers

/// Bande d'onglets facon Windows 11 : icone + titre + croix au survol.
///
/// Elle est a la fois source et cible de glissement :
///  - un onglet se reordonne dans sa fenetre et se deplace vers une autre ;
///  - des fichiers laches sur un onglet sont deplaces dans son dossier, et
///    survoler un onglet bascule dessus (onglet "a ressort").
struct TabStripView: View {

    @ObservedObject var model: WindowModel
    /// Redessine la vue quand la langue (ou un reglage global) change.
    @ObservedObject private var appSettings = AppSettings.shared
    @State private var dragging: UUID?
    @State private var fileTarget: UUID?

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(Array(model.tabs.enumerated()), id: \.element.id) { index, tab in
                            TabChip(
                                tab: tab,
                                isActive: index == model.selectedTabIndex,
                                isFileTarget: fileTarget == tab.id,
                                showClose: model.tabs.count > 1,
                                onSelect: { model.selectTab(at: index) },
                                onClose: { model.closeTab(at: index) }
                            )
                            .id(tab.id)
                            .contextMenu { tabMenu(index: index) }
                            .onDrag {
                                dragging = tab.id
                                TabDragSession.shared.begin(tab: tab, from: model)
                                return TabDragSession.shared.itemProvider(for: tab)
                            }
                            .onDrop(of: [.mexplorerTab, .fileURL], delegate: TabDropDelegate(
                                model: model, tab: tab, targetIndex: index,
                                dragging: $dragging, fileTarget: $fileTarget
                            ))
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .onChange(of: model.selectedTabIndex) { _, _ in
                    withAnimation { proxy.scrollTo(model.activeTab.id) }
                }
            }

            Button {
                model.newTab()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(.plain)
            .help(L("Nouvel onglet (Cmd T)"))
            .padding(.trailing, 8)
        }
        .frame(height: 34)
        .background(Color(nsColor: .windowBackgroundColor))
        // Zone libre de la bande : un onglet lache ici se place en dernier.
        .onDrop(of: [.mexplorerTab], delegate: TabStripTailDropDelegate(
            model: model, dragging: $dragging
        ))
    }

    @ViewBuilder
    private func tabMenu(index: Int) -> some View {
        Button(L("Dupliquer l'onglet")) { model.selectTab(at: index); model.duplicateTab() }
        Button(L("Fermer l'onglet")) { model.closeTab(at: index) }
        Button(L("Fermer les autres onglets")) { model.selectTab(at: index); model.closeOtherTabs() }
        Button(L("Fermer les onglets a droite")) { model.selectTab(at: index); model.closeTabsToTheRight() }
        Divider()
        Button(L("Deplacer vers une nouvelle fenetre")) { model.moveTabToNewWindow(at: index) }
            .disabled(model.tabs.count < 2)
        Button(L("Ouvrir dans une nouvelle fenetre")) {
            WindowManager.shared.openWindow(at: model.tabs[index].location)
        }
    }
}

// MARK: - Fiche d'onglet

private struct TabChip: View {
    @ObservedObject var tab: TabState
    let isActive: Bool
    let isFileTarget: Bool
    let showClose: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: tab.location.symbol)
                .font(.system(size: 11))
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            Text(tab.title)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
            if showClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .frame(width: 14, height: 14)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(hovering ? Color.primary.opacity(0.12) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .opacity(hovering || isActive ? 1 : 0)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 26)
        .frame(minWidth: 110, maxWidth: 220)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(borderColor, lineWidth: isFileTarget ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onSelect)
        .help(tab.location.addressPath)
    }

    private var background: Color {
        if isFileTarget { return Color.accentColor.opacity(0.18) }
        if isActive { return Color(nsColor: .controlBackgroundColor) }
        if hovering { return Color.primary.opacity(0.06) }
        return .clear
    }

    private var borderColor: Color {
        if isFileTarget { return Color.accentColor }
        return isActive ? Color.primary.opacity(0.10) : Color.clear
    }
}

// MARK: - Depot sur un onglet

private struct TabDropDelegate: DropDelegate {

    let model: WindowModel
    let tab: TabState
    let targetIndex: Int
    @Binding var dragging: UUID?
    @Binding var fileTarget: UUID?

    private func isTabDrag(_ info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.mexplorerTab])
    }

    private func isFileDrag(_ info: DropInfo) -> Bool {
        !isTabDrag(info) && info.hasItemsConforming(to: [.fileURL])
    }

    func validateDrop(info: DropInfo) -> Bool {
        if isTabDrag(info) { return TabDragSession.shared.isActive }
        if isFileDrag(info) { return tab.location.folderURL != nil }
        return false
    }

    func dropEntered(info: DropInfo) {
        if isTabDrag(info) {
            // Reordonnancement a la volee, uniquement au sein de la fenetre
            // d'origine : entre fenetres, l'insertion se fait au depot.
            guard let dragged = TabDragSession.shared.tab,
                  TabDragSession.shared.source === model,
                  let from = model.tabs.firstIndex(where: { $0 === dragged }),
                  from != targetIndex else { return }
            model.moveTab(from: from, to: targetIndex)
            return
        }

        guard isFileDrag(info) else { return }
        // Onglet a ressort : survoler bascule dessus au bout d'un instant,
        // pour pouvoir deposer dans la liste plutot que sur l'onglet.
        let identifier = tab.id
        fileTarget = identifier
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            guard fileTarget == identifier,
                  let index = model.tabs.firstIndex(where: { $0.id == identifier }) else { return }
            model.selectTab(at: index)
        }
    }

    func dropExited(info: DropInfo) {
        if fileTarget == tab.id { fileTarget = nil }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        if isTabDrag(info) { return DropProposal(operation: .move) }
        return DropProposal(operation: NSEvent.modifierFlags.contains(.option) ? .copy : .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            dragging = nil
            fileTarget = nil
        }

        if isTabDrag(info) {
            let session = TabDragSession.shared
            defer { session.end() }
            guard let dragged = session.tab, let source = session.source else { return false }
            if source === model { return true }   // deja reordonne pendant le survol
            model.adopt(dragged, from: source, at: targetIndex)
            return true
        }

        guard let destination = tab.location.folderURL else { return false }
        // Le glissement vient de notre propre liste : le presse-papiers de
        // glissement contient deja les URL, inutile de passer par l'async des
        // NSItemProvider.
        let urls = FileClipboard.shared.pasteboardURLsIn(NSPasteboard(name: .drag))
        guard !urls.isEmpty else { return false }

        let copy = NSEvent.modifierFlags.contains(.option)
        FileOperations.shared.drop(urls, into: destination,
                                   kind: copy ? .copy : .move,
                                   undoManager: model.undoManager) { _, error in
            if let error { model.present(error) }
        }
        return true
    }
}

/// Depot d'un onglet sur la zone libre de la bande : il se place en dernier.
private struct TabStripTailDropDelegate: DropDelegate {

    let model: WindowModel
    @Binding var dragging: UUID?

    func validateDrop(info: DropInfo) -> Bool { TabDragSession.shared.isActive }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            dragging = nil
            TabDragSession.shared.end()
        }
        guard let dragged = TabDragSession.shared.tab,
              let source = TabDragSession.shared.source,
              source !== model else { return true }
        model.adopt(dragged, from: source, at: model.tabs.count)
        return true
    }
}
