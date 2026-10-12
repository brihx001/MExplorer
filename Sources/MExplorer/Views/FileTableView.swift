import AppKit
import Quartz

/// NSTableView specialisee : raccourcis clavier facon Explorateur Windows,
/// menu contextuel contextuel a la ligne cliquee, prise en charge de Coup d'oeil.
final class FileTableView: NSTableView {

    var onKeyDown: ((NSEvent) -> Bool)?
    var onMenuForRow: ((Int) -> NSMenu?)?

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true { return }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        if row >= 0 && !selectedRowIndexes.contains(row) {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        return onMenuForRow?(row)
    }

    // Coup d'oeil : la fenetre demande un controleur via la chaine des repondeurs.
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        QuickLookCoordinator.shared.attach(to: panel)
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        QuickLookCoordinator.shared.detach(from: panel)
    }

    override var acceptsFirstResponder: Bool { true }
}
