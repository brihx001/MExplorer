import AppKit

/// Remplit « Deplacer vers » / « Copier vers » de la barre de menus a chaque
/// ouverture.
///
/// Un sous-menu de la barre de menus est construit une fois pour toutes, alors
/// que les destinations recentes changent a l'usage et que la selection decide
/// de l'activation. Le delegue le refait donc juste avant l'affichage.
final class TransferMenuDelegate: NSObject, NSMenuDelegate {

    private static var instances: [String: TransferMenuDelegate] = [:]

    static func shared(for kind: FileOperations.TransferKind) -> TransferMenuDelegate {
        let key = kind == .copy ? "copy" : "move"
        if let existing = instances[key] { return existing }
        let delegate = TransferMenuDelegate(kind: kind)
        instances[key] = delegate
        return delegate
    }

    private let kind: FileOperations.TransferKind

    private init(kind: FileOperations.TransferKind) {
        self.kind = kind
        super.init()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let model = WindowManager.shared.keyModel, !model.selectionURLs.isEmpty else {
            let empty = menu.addBlockItem(L("Aucune selection"), enabled: false) {}
            empty.isEnabled = false
            return
        }
        for destination in model.transferDestinations() {
            let item = menu.addBlockItem(destination.lastPathComponent) { [kind] in
                model.transferSelection(to: destination, kind: kind)
            }
            let icon = NSWorkspace.shared.icon(forFile: destination.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            item.toolTip = destination.path
        }
        if menu.numberOfItems > 0 { menu.addItem(.separator()) }
        menu.addBlockItem(L("Autre dossier...")) { [kind] in
            model.chooseTransferDestination(kind: kind)
        }
    }
}
