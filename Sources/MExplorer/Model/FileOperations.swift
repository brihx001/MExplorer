import AppKit

/// Toutes les mutations du systeme de fichiers passent par ici :
/// nommage sans collision, coordination NSFileCoordinator, annulation (Cmd-Z).
final class FileOperations {

    static let shared = FileOperations()
    private init() {}

    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInitiated
        q.name = "com.jerome.mexplorer.fileops"
        return q
    }()

    /// Progression globale, observable par l'interface.
    let progress = FileOperationProgress()

    /// Drapeau lu par l'operation en cours, entre deux elements et, pour une
    /// copie qui travaille vraiment, tous les mega-octets.
    private let cancelFlag = OperationCancel()

    /// Demande l'arret de l'operation en cours.
    func cancelCurrent() {
        cancelFlag.cancel()
        progress.markCancelling()
    }

    var isCancelled: Bool { cancelFlag.isCancelled }

    // MARK: - Noms uniques

    /// "Rapport.pdf" -> "Rapport 2.pdf" (convention macOS) si le nom est deja pris.
    static func uniqueURL(for proposed: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: proposed.path) else { return proposed }
        let dir = proposed.deletingLastPathComponent()
        let ext = proposed.pathExtension
        let base = proposed.deletingPathExtension().lastPathComponent
        var index = 2
        while index < 10_000 {
            var name = "\(base) \(index)"
            if !ext.isEmpty { name += ".\(ext)" }
            let candidate = dir.appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
        return dir.appendingPathComponent(UUID().uuidString)
    }

    // MARK: - Creation

    @discardableResult
    func newFolder(in parent: URL, name: String = L("nouveau dossier"), undoManager: UndoManager? = nil) throws -> URL {
        let url = Self.uniqueURL(for: parent.appendingPathComponent(name))
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        registerUndoDelete(of: [url], undoManager: undoManager, actionName: L("Nouveau dossier"))
        return url
    }

    @discardableResult
    func newFile(in parent: URL, name: String, contents: Data = Data(), undoManager: UndoManager? = nil) throws -> URL {
        let url = Self.uniqueURL(for: parent.appendingPathComponent(name))
        guard FileManager.default.createFile(atPath: url.path, contents: contents) else {
            throw CocoaError(.fileWriteUnknown)
        }
        registerUndoDelete(of: [url], undoManager: undoManager, actionName: L("Nouveau fichier"))
        return url
    }

    // MARK: - Renommage

    @discardableResult
    func rename(_ url: URL, to newName: String, undoManager: UndoManager? = nil) throws -> URL {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/"), trimmed != url.lastPathComponent else { return url }
        let destination = url.deletingLastPathComponent().appendingPathComponent(trimmed)
        if FileManager.default.fileExists(atPath: destination.path) {
            throw NSError(domain: "MExplorer", code: 17, userInfo: [
                NSLocalizedDescriptionKey: L("Un element nomme \"%@\" existe deja a cet emplacement.", trimmed)
            ])
        }
        try FileManager.default.moveItem(at: url, to: destination)
        IconCache.shared.invalidate(path: url.path)

        let oldName = url.lastPathComponent
        undoManager?.registerUndo(withTarget: self) { target in
            _ = try? target.rename(destination, to: oldName, undoManager: undoManager)
        }
        undoManager?.setActionName(L("Renommer"))
        return destination
    }

    // MARK: - Corbeille / suppression

    func trash(_ urls: [URL], undoManager: UndoManager? = nil, completion: (([URL: URL], Error?) -> Void)? = nil) {
        guard !urls.isEmpty else { completion?([:], nil); return }
        NSWorkspace.shared.recycle(urls) { [weak self] newURLs, error in
            DispatchQueue.main.async {
                if error == nil, let self, !newURLs.isEmpty {
                    undoManager?.registerUndo(withTarget: self) { target in
                        for (original, inTrash) in newURLs {
                            try? FileManager.default.moveItem(at: inTrash, to: original)
                        }
                        target.notifyChange()
                    }
                    undoManager?.setActionName(urls.count == 1 ? L("Placer dans la corbeille")
                                                              : L("Placer %d elements dans la corbeille", urls.count))
                }
                self?.notifyChange()
                completion?(newURLs, error)
            }
        }
    }

    /// Suppression definitive : irreversible, l'appelant doit avoir demande confirmation.
    func deletePermanently(_ urls: [URL], completion: ((Error?) -> Void)? = nil) {
        run(kind: .delete, count: urls.count) { report in
            var failure: Error?
            for (index, url) in urls.enumerated() {
                if self.cancelFlag.isCancelled { break }
                report(index, url.lastPathComponent)
                do { try FileManager.default.removeItem(at: url) }
                catch { failure = failure ?? error }
            }
            return failure
        } completion: { [weak self] error in
            self?.notifyChange()
            completion?(error)
        }
    }

    func emptyTrash(completion: ((Error?) -> Void)? = nil) {
        guard let trash = SidebarCatalog.trash else { completion?(nil); return }
        let contents = (try? FileManager.default.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil)) ?? []
        deletePermanently(contents, completion: completion)
    }

    // MARK: - Copie / deplacement

    enum TransferKind { case copy, move }

    /// Vrai si l'URL designe la corbeille de l'utilisateur.
    static func isTrash(_ url: URL) -> Bool {
        guard let trash = SidebarCatalog.trash else { return false }
        return url.standardizedFileURL.path == trash.standardizedFileURL.path
    }

    /// Point d'entree des depots par glisser-deposer.
    ///
    /// Deposer sur la corbeille n'est pas un deplacement de fichier ordinaire :
    /// un simple `moveItem` vers ~/.Trash priverait l'element de sa fiche de
    /// provenance, donc de la commande « Remettre » du Finder.
    func drop(_ urls: [URL],
              into destination: URL,
              kind: TransferKind,
              undoManager: UndoManager? = nil,
              completion: (([URL], Error?) -> Void)? = nil) {
        guard Self.isTrash(destination) else {
            transfer(urls, to: destination, kind: kind, undoManager: undoManager, completion: completion)
            return
        }
        trash(urls, undoManager: undoManager) { moved, error in
            completion?(Array(moved.values), error)
        }
    }

    /// Choix de l'utilisateur quand un element du meme nom existe deja.
    enum ConflictResolution { case keepBoth, replace, skip }

    func transfer(_ urls: [URL],
                  to destination: URL,
                  kind: TransferKind,
                  undoManager: UndoManager? = nil,
                  completion: (([URL], Error?) -> Void)? = nil) {
        guard !urls.isEmpty else { completion?([], nil); return }

        // Un element deplace ou copie dans son propre dossier n'est pas un
        // conflit : le premier cas est sans effet, le second est un doublon
        // volontaire, qui prend un nom libre comme le fait le Finder.
        let fm = FileManager.default
        let conflicts = urls.filter { source in
            source.deletingLastPathComponent().standardizedFileURL != destination.standardizedFileURL
                && fm.fileExists(atPath: destination.appendingPathComponent(source.lastPathComponent).path)
        }
        guard !conflicts.isEmpty else {
            perform(urls, to: destination, kind: kind, resolutions: [:],
                    undoManager: undoManager, completion: completion)
            return
        }
        resolveConflicts(conflicts, kind: kind) { [weak self] resolutions in
            guard let self else { return }
            guard let resolutions else { completion?([], nil); return }
            self.perform(urls, to: destination, kind: kind, resolutions: resolutions,
                         undoManager: undoManager, completion: completion)
        }
    }

    /// Interroge l'utilisateur element par element, avec « Appliquer a tous »
    /// pour trancher d'un coup le reste de la file.
    ///
    /// Le Finder procede ainsi : une seule reponse imposee a tout le lot
    /// empeche de garder un fichier et d'en remplacer un autre.
    /// `nil` en reponse signifie annuler l'operation entiere.
    private func resolveConflicts(_ conflicts: [URL],
                                  kind: TransferKind,
                                  completion: @escaping ([String: ConflictResolution]?) -> Void) {
        var resolutions: [String: ConflictResolution] = [:]
        var remaining = conflicts

        func step() {
            guard !remaining.isEmpty else { completion(resolutions); return }
            let current = remaining.removeFirst()
            askConflict(current.lastPathComponent, kind: kind, left: remaining.count) { choice, applyToAll in
                guard let choice else { completion(nil); return }
                resolutions[current.lastPathComponent] = choice
                if applyToAll {
                    for url in remaining { resolutions[url.lastPathComponent] = choice }
                    remaining = []
                }
                step()
            }
        }
        step()
    }

    /// Propose de conserver les deux elements, de remplacer, d'ignorer ou
    /// d'annuler. `nil` en reponse signifie annuler toute l'operation.
    private func askConflict(_ name: String,
                             kind: TransferKind,
                             left: Int,
                             completion: @escaping (ConflictResolution?, Bool) -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("Un element nomme \"%@\" existe deja a cet emplacement.", name)
        alert.informativeText = kind == .copy
            ? L("Conservez les deux, remplacez l'element existant, ignorez-le, ou annulez la copie.")
            : L("Conservez les deux, remplacez l'element existant, ignorez-le, ou annulez le deplacement.")
        alert.addButton(withTitle: L("Conserver les deux"))
        alert.addButton(withTitle: L("Remplacer"))
        alert.addButton(withTitle: L("Ignorer"))
        alert.addButton(withTitle: L("Annuler", context: "bouton"))

        // La case n'a de sens qu'avec une file derriere : sur le dernier
        // element, « appliquer a tous » ne s'appliquerait a rien.
        var applyToAll: NSButton?
        if left > 0 {
            let box = NSButton(checkboxWithTitle: L("Appliquer aux %d elements suivants", left),
                               target: nil, action: nil)
            box.state = .off
            alert.accessoryView = box
            applyToAll = box
        }

        let handle: (NSApplication.ModalResponse) -> Void = { response in
            let all = applyToAll?.state == .on
            switch response {
            case .alertFirstButtonReturn: completion(.keepBoth, all)
            case .alertSecondButtonReturn: completion(.replace, all)
            case .alertThirdButtonReturn: completion(.skip, all)
            default: completion(nil, false)
            }
        }
        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window, completionHandler: handle)
        } else {
            handle(alert.runModal())
        }
    }

    private func perform(_ urls: [URL],
                         to destination: URL,
                         kind: TransferKind,
                         resolutions: [String: ConflictResolution],
                         undoManager: UndoManager?,
                         completion: (([URL], Error?) -> Void)?) {
        let opKind: FileOperationProgress.Kind = (kind == .copy) ? .copy : .move

        // Le volume total sert d'echelle a la barre : sans lui, une copie d'un
        // seul gros fichier resterait a zero pour cent jusqu'a la fin.
        let totalBytes = urls.reduce(Int64(0)) { $0 + FileCopier.size(of: $1) }
        DispatchQueue.main.async { self.progress.setTotalBytes(totalBytes) }

        run(kind: opKind, count: urls.count) { report in
            var created: [URL] = []
            var sources: [URL] = []
            var failure: Error?
            var replacedAny = false
            var doneBytes: Int64 = 0
            let fm = FileManager.default

            for (index, source) in urls.enumerated() {
                if self.cancelFlag.isCancelled { break }
                report(index, source.lastPathComponent)
                let itemBytes = FileCopier.size(of: source)
                let base = doneBytes
                let onBytes: (Int64) -> Void = { [weak self] copied in
                    self?.progress.setBytes(base + copied)
                }

                let sameFolder = source.deletingLastPathComponent().standardizedFileURL == destination.standardizedFileURL
                if sameFolder, kind == .move { doneBytes += itemBytes; continue }

                var target = destination.appendingPathComponent(source.lastPathComponent)
                var replacing = false
                if fm.fileExists(atPath: target.path) {
                    switch resolutions[source.lastPathComponent] ?? .keepBoth {
                    case .skip:
                        doneBytes += itemBytes
                        continue
                    case .replace where !sameFolder:
                        replacing = true
                    default:
                        target = Self.uniqueURL(for: target)
                    }
                }

                do {
                    if replacing {
                        // Ecriture sous un nom temporaire puis echange : l'element
                        // existant n'est detruit qu'une fois le nouveau en place.
                        let temp = destination.appendingPathComponent(".mexplorer-\(UUID().uuidString)")
                        switch kind {
                        case .copy: try FileCopier.copy(source, to: temp, cancel: self.cancelFlag, onBytes: onBytes)
                        case .move: try FileCopier.move(source, to: temp, cancel: self.cancelFlag, onBytes: onBytes)
                        }
                        do {
                            _ = try fm.replaceItemAt(target, withItemAt: temp)
                        } catch {
                            try? fm.removeItem(at: temp)
                            throw error
                        }
                        replacedAny = true
                    } else {
                        switch kind {
                        case .copy: try FileCopier.copy(source, to: target, cancel: self.cancelFlag, onBytes: onBytes)
                        case .move: try FileCopier.move(source, to: target, cancel: self.cancelFlag, onBytes: onBytes)
                        }
                    }
                    created.append(target)
                    sources.append(source)
                } catch is FileCopier.Cancelled {
                    break
                } catch {
                    failure = failure ?? error
                }
                doneBytes += itemBytes
                self.progress.setBytes(doneBytes)
            }
            self.lastCreated = created
            self.lastSources = sources
            self.lastReplaced = replacedAny
            return failure
        } completion: { [weak self] error in
            guard let self else { return }
            let created = self.lastCreated
            let sources = self.lastSources
            // Un remplacement a detruit l'element precedent : annuler ne ferait
            // que supprimer le nouveau sans rendre l'ancien. Une operation
            // interrompue ne s'annule pas davantage : elle est deja partielle.
            if error == nil, !created.isEmpty, !self.lastReplaced, !self.cancelFlag.isCancelled {
                undoManager?.registerUndo(withTarget: self) { target in
                    switch kind {
                    case .copy:
                        target.deletePermanently(created)
                    case .move:
                        for (i, url) in created.enumerated() where i < sources.count {
                            try? FileManager.default.moveItem(at: url, to: sources[i])
                        }
                        target.notifyChange()
                    }
                }
                undoManager?.setActionName(kind == .copy ? L("Copier") : L("Deplacer"))
            }
            self.notifyChange()
            completion?(created, error)
        }
    }

    private var lastCreated: [URL] = []
    /// Sources effectivement traitees, dans l'ordre de `lastCreated` : un
    /// element ignore ou en echec ne doit pas decaler l'annulation.
    private var lastSources: [URL] = []
    private var lastReplaced = false

    func duplicate(_ urls: [URL], undoManager: UndoManager? = nil, completion: (([URL], Error?) -> Void)? = nil) {
        run(kind: .copy, count: urls.count) { report in
            var created: [URL] = []
            var failure: Error?
            for (index, source) in urls.enumerated() {
                if self.cancelFlag.isCancelled { break }
                report(index, source.lastPathComponent)
                let ext = source.pathExtension
                let base = source.deletingPathExtension().lastPathComponent
                var name = "\(base) copie"
                if !ext.isEmpty { name += ".\(ext)" }
                let target = Self.uniqueURL(for: source.deletingLastPathComponent().appendingPathComponent(name))
                do {
                    try FileManager.default.copyItem(at: source, to: target)
                    created.append(target)
                } catch { failure = failure ?? error }
            }
            self.lastCreated = created
            return failure
        } completion: { [weak self] error in
            guard let self else { return }
            let created = self.lastCreated
            if error == nil, !created.isEmpty {
                undoManager?.registerUndo(withTarget: self) { target in target.deletePermanently(created) }
                undoManager?.setActionName(L("Dupliquer"))
            }
            self.notifyChange()
            completion?(created, error)
        }
    }

    // MARK: - Alias

    @discardableResult
    func makeAliases(for urls: [URL], in destination: URL, undoManager: UndoManager? = nil) -> [URL] {
        var created: [URL] = []
        for source in urls {
            let name = source.deletingPathExtension().lastPathComponent + " alias"
            let target = Self.uniqueURL(for: destination.appendingPathComponent(name))
            do {
                let data = try source.bookmarkData(options: .suitableForBookmarkFile,
                                                   includingResourceValuesForKeys: nil, relativeTo: nil)
                try URL.writeBookmarkData(data, to: target)
                created.append(target)
            } catch { continue }
        }
        registerUndoDelete(of: created, undoManager: undoManager, actionName: L("Creer un alias"))
        notifyChange()
        return created
    }

    // MARK: - Compression (NSFileCoordinator .forUploading : compatible sandbox)

    func compress(_ urls: [URL], in destination: URL, completion: @escaping (URL?, Error?) -> Void) {
        guard !urls.isEmpty else { completion(nil, nil); return }

        run(kind: .compress, count: 1) { report in
            report(0, urls.count == 1 ? urls[0].lastPathComponent : L("Archive"))
            do {
                let sourceForZip: URL
                let temp = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)

                if urls.count == 1 {
                    sourceForZip = urls[0]
                } else {
                    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
                    let staging = temp.appendingPathComponent(L("Archive"), isDirectory: true)
                    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                    for u in urls {
                        try FileManager.default.copyItem(at: u, to: staging.appendingPathComponent(u.lastPathComponent))
                    }
                    sourceForZip = staging
                }

                var coordError: NSError?
                var thrown: Error?
                let baseName = urls.count == 1
                    ? urls[0].deletingPathExtension().lastPathComponent
                    : L("Archive")
                let target = Self.uniqueURL(for: destination.appendingPathComponent(baseName + ".zip"))

                NSFileCoordinator().coordinate(readingItemAt: sourceForZip,
                                               options: [.forUploading],
                                               error: &coordError) { zipped in
                    do { try FileManager.default.copyItem(at: zipped, to: target) }
                    catch { thrown = error }
                }
                try? FileManager.default.removeItem(at: temp)
                if let e = coordError ?? (thrown as NSError?) { throw e }
                self.lastCreated = [target]
                return nil
            } catch {
                self.lastCreated = []
                return error
            }
        } completion: { [weak self] error in
            self?.notifyChange()
            completion(self?.lastCreated.first, error)
        }
    }

    // MARK: - Notification de changement

    static let didChangeNotification = Notification.Name("com.jerome.mexplorer.filesDidChange")

    func notifyChange() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    private func registerUndoDelete(of urls: [URL], undoManager: UndoManager?, actionName: String) {
        guard !urls.isEmpty, let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { target in
            target.deletePermanently(urls)
        }
        undoManager.setActionName(actionName)
    }

    // MARK: - Execution

    private func run(kind: FileOperationProgress.Kind,
                     count: Int,
                     work: @escaping ((Int, String) -> Void) -> Error?,
                     completion: @escaping (Error?) -> Void) {
        cancelFlag.reset()
        DispatchQueue.main.async { self.progress.begin(kind: kind, total: count) }
        queue.addOperation { [weak self] in
            let error = work { index, label in
                DispatchQueue.main.async { self?.progress.update(completed: index, label: label) }
            }
            DispatchQueue.main.async {
                self?.progress.finish()
                completion(error)
            }
        }
    }
}

/// Etat de progression observable des operations longues.
final class FileOperationProgress: ObservableObject {
    enum Kind: String {
        case copy, move, delete, compress

        /// Libelle affiche dans la barre d'etat.
        var title: String {
            switch self {
            case .copy: return L("Copie")
            case .move: return L("Deplacement")
            case .delete: return L("Suppression")
            case .compress: return L("Compression")
            }
        }
    }

    @Published private(set) var isRunning = false
    @Published private(set) var kind: Kind = .copy
    @Published private(set) var completed = 0
    @Published private(set) var total = 0
    @Published private(set) var label = ""
    /// Octets ecrits et volume attendu : seule echelle juste quand un seul
    /// element pese plusieurs gigaoctets.
    @Published private(set) var bytesDone: Int64 = 0
    @Published private(set) var bytesTotal: Int64 = 0
    /// L'arret a ete demande mais l'element en cours n'a pas encore rendu la main.
    @Published private(set) var isCancelling = false

    /// L'affichage attend un court instant : une copie instantanee ne doit pas
    /// faire clignoter la barre d'etat.
    private var reveal: DispatchWorkItem?

    func begin(kind: Kind, total: Int) {
        self.kind = kind
        self.total = total
        self.completed = 0
        self.label = ""
        self.bytesDone = 0
        self.isCancelling = false
        reveal?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.isRunning = true }
        reveal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    func setTotalBytes(_ bytes: Int64) { bytesTotal = bytes }

    /// Appele depuis le thread de copie, tous les mega-octets.
    func setBytes(_ bytes: Int64) {
        DispatchQueue.main.async { self.bytesDone = bytes }
    }

    func markCancelling() { isCancelling = true }

    func update(completed: Int, label: String) {
        self.completed = completed
        self.label = label
    }

    func finish() {
        reveal?.cancel()
        reveal = nil
        isRunning = false
        isCancelling = false
        completed = total
        bytesTotal = 0
        bytesDone = 0
    }

    /// Progression en octets quand le volume est connu, en elements sinon.
    var fraction: Double {
        if bytesTotal > 0 { return min(Double(bytesDone) / Double(bytesTotal), 1) }
        return total > 0 ? Double(completed) / Double(total) : 0
    }
}
