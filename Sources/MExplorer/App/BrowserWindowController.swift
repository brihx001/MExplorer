import AppKit
import SwiftUI

/// Fenetre principale : barre de titre compacte + bande d'onglets, contenu delegue
/// a BrowserViewController.
final class BrowserWindowController: NSWindowController, NSWindowDelegate {

    let model: WindowModel
    private var browserVC: BrowserViewController!

    convenience init(adopting tab: TabState) {
        self.init(model: WindowModel(adopting: tab))
    }

    convenience init(location: Location) {
        self.init(model: WindowModel(initial: location))
    }

    private init(model: WindowModel) {
        self.model = model

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 720, height: 420)
        window.titleVisibility = .hidden
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("MExplorerMainWindow")

        super.init(window: window)

        model.window = window
        window.delegate = self

        browserVC = BrowserViewController(model: model)
        window.contentViewController = browserVC

        installTabStrip()
        updateTitle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supporte") }

    // MARK: - Bande d'onglets dans la barre de titre

    private func installTabStrip() {
        // La hauteur de l'accessoire vient de la frame de sa vue : une contrainte
        // de hauteur explicite entrerait en conflit avec son masque de redimensionnement.
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .bottom

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 34))
        let host = NSHostingView(rootView: TabStripView(model: model))
        host.translatesAutoresizingMaskIntoConstraints = true
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)

        accessory.view = container
        window?.addTitlebarAccessoryViewController(accessory)
    }

    func updateTitle() {
        window?.title = model.activeTab.title
        window?.representedURL = model.activeTab.location.folderURL
        if let url = model.activeTab.location.folderURL {
            window?.standardWindowButton(.documentIconButton)?.image =
                IconCache.shared.icon(forFileAt: url)
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        WindowManager.shared.forget(self)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        browserVC.windowDidBecomeKey()
    }
}
