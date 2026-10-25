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
        // Pas de setFrameAutosaveName : il enregistre le cadre mais ne le
        // repose jamais de lui-meme, et un nom unique ne saurait de toute
        // facon pas distinguer plusieurs fenetres. La session s'en charge,
        // fenetre par fenetre.
        window.center()

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
        // La derniere fenetre fermee fait quitter l'application : son etat doit
        // etre note maintenant, car applicationWillTerminate ne trouverait
        // plus de fenetre a enregistrer.
        SessionStore.save(closing: self)
        WindowManager.shared.forget(self)
    }

    /// Repose la fenetre la ou elle etait, si l'endroit existe toujours.
    func restoreFrame(_ frame: NSRect) {
        guard let window else { return }
        var target = frame
        target.size.width = max(target.width, window.minSize.width)
        target.size.height = max(target.height, window.minSize.height)
        guard SessionStore.isReachable(target) else { return }
        window.setFrame(target, display: false)
    }

    /// Decale la fenetre par rapport a la precedente, faute de cadre connu :
    /// sans cela, toutes les fenetres d'une session se superposeraient.
    func cascade(after previous: BrowserWindowController?) {
        guard let window else { return }
        guard let origin = previous?.window?.frame else { window.center(); return }
        window.cascadeTopLeft(from: NSPoint(x: origin.minX, y: origin.maxY))
    }

    func windowDidBecomeKey(_ notification: Notification) {
        browserVC.windowDidBecomeKey()
    }
}
