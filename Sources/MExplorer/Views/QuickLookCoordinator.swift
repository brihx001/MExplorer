import AppKit
import Quartz

/// Pilote le panneau Coup d'oeil (barre d'espace, comme dans le Finder).
final class QuickLookCoordinator: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {

    static let shared = QuickLookCoordinator()

    private var urls: [URL] = []
    private(set) var currentIndex = 0
    /// Fournit le rectangle d'origine de l'animation (zoom depuis la vignette).
    var frameProvider: ((URL) -> NSRect?)?

    private override init() { super.init() }

    var isVisible: Bool { QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible }

    func toggle(urls: [URL]) {
        if isVisible {
            QLPreviewPanel.shared().orderOut(nil)
        } else {
            show(urls: urls)
        }
    }

    func show(urls: [URL]) {
        guard !urls.isEmpty else { return }
        self.urls = urls
        self.currentIndex = 0
        let panel = QLPreviewPanel.shared()!
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
    }

    /// Met a jour le contenu si le panneau est deja ouvert (suivi de la selection).
    func updateIfVisible(urls: [URL]) {
        guard isVisible, !urls.isEmpty else { return }
        self.urls = urls
        self.currentIndex = 0
        QLPreviewPanel.shared().reloadData()
    }

    func attach(to panel: QLPreviewPanel) {
        panel.dataSource = self
        panel.delegate = self
    }

    func detach(from panel: QLPreviewPanel) {
        if panel.dataSource === self { panel.dataSource = nil }
        if panel.delegate === self { panel.delegate = nil }
    }

    // MARK: - QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        urls.indices.contains(index) ? urls[index] as NSURL : nil
    }

    // MARK: - QLPreviewPanelDelegate

    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        if event.type == .keyDown, let chars = event.charactersIgnoringModifiers, chars == " " {
            panel.orderOut(nil)
            return true
        }
        return false
    }

    func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: QLPreviewItem!) -> NSRect {
        guard let url = (item as? NSURL) as URL?, let frame = frameProvider?(url) else { return .zero }
        return frame
    }
}
