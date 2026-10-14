import AppKit
import Quartz

/// NSTableView specialisee : raccourcis clavier facon Explorateur Windows,
/// menu contextuel contextuel a la ligne cliquee, prise en charge de Coup d'oeil.
final class FileTableView: NSTableView {

    var onKeyDown: ((NSEvent) -> Bool)?
    var onMenuForRow: ((Int) -> NSMenu?)?
    /// Clic simple sur une ligne deja seule selectionnee : candidat au
    /// renommage par deux clics lents (ligne, colonne cliquee).
    var onSlowClick: ((Int, Int) -> Void)?
    /// Tout le reste annule un renommage en attente.
    var onInterrupt: (() -> Void)?

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
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        let column = self.column(at: point)
        let aloneBefore = row >= 0 && selectedRowIndexes.count == 1 && selectedRowIndexes.contains(row)
        let origin = NSEvent.mouseLocation

        // Rend la main une fois le clic traite : selection faite, glissement
        // eventuel termine.
        super.mouseDown(with: event)

        guard column >= 0,
              SlowClickRenamer.qualifies(event: event, wasAloneSelected: aloneBefore, mouseOrigin: origin),
              selectedRowIndexes.count == 1, selectedRowIndexes.contains(row) else { return }
        onSlowClick?(row, column)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        onInterrupt?()
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
