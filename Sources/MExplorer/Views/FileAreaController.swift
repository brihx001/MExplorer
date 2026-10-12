import AppKit

/// Contrat commun aux deux presentations de la zone de fichiers
/// (tableau "Details" et grille d'icones).
protocol FileAreaController: AnyObject {
    var view: NSView { get }
    var tab: TabState? { get set }

    func attach(tab: TabState)
    func reloadContent()
    func applySelection(_ urls: [URL])
    func beginRename(_ url: URL)
    func frameOnScreen(for url: URL) -> NSRect?
    func rebuildColumns()
    func focus()
}
