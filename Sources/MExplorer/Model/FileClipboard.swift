import AppKit

/// Presse-papiers fichiers avec semantique Windows : Couper marque les elements
/// pour un deplacement, Coller les consomme.
final class FileClipboard {

    static let shared = FileClipboard()
    private init() {}

    static let cutType = NSPasteboard.PasteboardType("com.jerome.mexplorer.cut")
    static let didChangeNotification = Notification.Name("com.jerome.mexplorer.clipboardDidChange")

    private(set) var cutURLs: [URL] = []
    private var cutChangeCount: Int = -1

    // MARK: - Ecriture

    func copy(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        clearCut()
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls as [NSURL])
        pb.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    func cut(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls as [NSURL])
        pb.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
        pb.setData(Data([1]), forType: Self.cutType)
        cutURLs = urls
        cutChangeCount = pb.changeCount
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    func copyPaths(_ urls: [URL]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
    }

    // MARK: - Lecture

    var pasteboardURLs: [URL] {
        let pb = NSPasteboard.general
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return (pb.readObjects(forClasses: [NSURL.self], options: options) as? [URL]) ?? []
    }

    var canPaste: Bool { !pasteboardURLs.isEmpty }

    /// Lecture des URL de fichiers depuis un presse-papiers arbitraire (glisser-deposer).
    func pasteboardURLsIn(_ pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return (pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]) ?? []
    }

    /// Vrai si le contenu du presse-papiers provient d'un Couper toujours valide.
    var isCutPending: Bool {
        NSPasteboard.general.changeCount == cutChangeCount
            && NSPasteboard.general.data(forType: Self.cutType) != nil
    }

    private var cutPathCache: Set<String> = []
    private var cachedChangeCount = -1

    /// Interroge par chaque ligne affichee : le resultat est memorise tant que
    /// le presse-papiers n'a pas change.
    func isMarkedForCut(_ url: URL) -> Bool {
        let changeCount = NSPasteboard.general.changeCount
        if changeCount != cachedChangeCount {
            cachedChangeCount = changeCount
            cutPathCache = (changeCount == cutChangeCount
                            && NSPasteboard.general.data(forType: Self.cutType) != nil)
                ? Set(cutURLs.map { $0.standardizedFileURL.path })
                : []
        }
        return cutPathCache.contains(url.standardizedFileURL.path)
    }

    // MARK: - Collage

    func paste(into destination: URL,
               undoManager: UndoManager? = nil,
               completion: (([URL], Error?) -> Void)? = nil) {
        let urls = pasteboardURLs
        guard !urls.isEmpty else { completion?([], nil); return }
        let move = isCutPending
        FileOperations.shared.transfer(urls, to: destination, kind: move ? .move : .copy,
                                       undoManager: undoManager) { [weak self] created, error in
            if move { self?.clearCut() }
            completion?(created, error)
        }
    }

    /// Colle un raccourci (alias) vers les elements du presse-papiers.
    func pasteAsAlias(into destination: URL, undoManager: UndoManager? = nil) -> [URL] {
        FileOperations.shared.makeAliases(for: pasteboardURLs, in: destination, undoManager: undoManager)
    }

    private func clearCut() {
        cutURLs = []
        cutChangeCount = -1
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }
}
