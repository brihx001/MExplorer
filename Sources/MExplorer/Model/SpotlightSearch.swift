import Foundation

/// Recherche Spotlight en direct (NSMetadataQuery), avec resultats incrementaux.
final class SpotlightSearch {

    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private let onUpdate: ([FileItem]) -> Void
    private let onFinish: () -> Void

    init(onUpdate: @escaping ([FileItem]) -> Void, onFinish: @escaping () -> Void) {
        self.onUpdate = onUpdate
        self.onFinish = onFinish
    }

    deinit { stop() }

    /// `scope` limite la recherche a un dossier ; nil = tout ce qui est indexe et accessible.
    func start(text: String, scope: URL?, includeContent: Bool) {
        stop()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let q = NSMetadataQuery()
        let escaped = trimmed.replacingOccurrences(of: "\"", with: "\\\"")
        var format = "(kMDItemFSName LIKE[cd] \"*\(escaped)*\")"
        if includeContent {
            format += " || (kMDItemTextContent LIKE[cd] \"*\(escaped)*\")"
            format += " || (kMDItemDisplayName LIKE[cd] \"*\(escaped)*\")"
        }
        q.predicate = NSPredicate(fromMetadataQueryString: format)
        q.searchScopes = scope.map { [$0] } ?? [NSMetadataQueryLocalComputerScope]
        q.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSNameKey, ascending: true)]
        q.notificationBatchingInterval = 0.4

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .NSMetadataQueryDidUpdate, object: q, queue: .main) { [weak self] _ in
            self?.publish(q)
        })
        observers.append(center.addObserver(forName: .NSMetadataQueryGatheringProgress, object: q, queue: .main) { [weak self] _ in
            self?.publish(q)
        })
        observers.append(center.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: q, queue: .main) { [weak self] _ in
            self?.publish(q)
            self?.onFinish()
        })

        query = q
        q.start()
    }

    func stop() {
        query?.stop()
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers.removeAll()
        query = nil
    }

    private func publish(_ q: NSMetadataQuery) {
        q.disableUpdates()
        defer { q.enableUpdates() }
        var results: [FileItem] = []
        results.reserveCapacity(q.resultCount)
        let keys = Set(FileItem.resourceKeys)
        for i in 0..<q.resultCount {
            guard let mdItem = q.result(at: i) as? NSMetadataItem,
                  let path = mdItem.value(forAttribute: NSMetadataItemPathKey) as? String
            else { continue }
            let url = URL(fileURLWithPath: path)
            results.append(FileItem(url: url, values: try? url.resourceValues(forKeys: keys)))
            if results.count >= 5000 { break }
        }
        onUpdate(results)
    }
}
