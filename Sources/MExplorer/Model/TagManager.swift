import AppKit

/// Lecture / ecriture des tags Finder (attribut etendu com.apple.metadata:_kMDItemUserTags,
/// expose par URLResourceValues.tagNames).
enum TagManager {

    static func tags(of url: URL) -> [String] {
        (try? url.resourceValues(forKeys: [.tagNamesKey]).tagNames) ?? []
    }

    @discardableResult
    static func setTags(_ tags: [String], on urls: [URL]) -> Error? {
        for url in urls {
            do { try write(tags, to: url) } catch { return error }
        }
        return nil
    }

    @discardableResult
    static func toggle(tag: String, on urls: [URL]) -> Error? {
        let allHave = urls.allSatisfy { tags(of: $0).contains(tag) }
        for url in urls {
            var current = tags(of: url)
            if allHave {
                current.removeAll { $0 == tag }
            } else if !current.contains(tag) {
                current.append(tag)
            }
            do { try write(current, to: url) } catch { return error }
        }
        UserDefaults.standard.register(tag: tag)
        return nil
    }

    /// Le setter URLResourceValues.tagNames n'existe qu'a partir de macOS 26 ;
    /// NSURL.setResourceValue couvre toutes les versions supportees.
    private static func write(_ tags: [String], to url: URL) throws {
        try (url as NSURL).setResourceValue(tags.isEmpty ? nil : tags as NSArray,
                                            forKey: .tagNamesKey)
        IconCache.shared.invalidate(path: url.path)
    }

    /// Tags systeme + tags deja rencontres dans cette installation.
    static var knownTags: [String] {
        let system = SidebarCatalog.systemTags.map { $0.name }
        let custom = UserDefaults.standard.stringArray(forKey: "com.jerome.mexplorer.customTags") ?? []
        return system + custom.filter { name in !system.contains { $0.caseInsensitiveCompare(name) == .orderedSame } }
    }

    /// Recherche Spotlight de tous les elements portant un tag.
    static func itemsWithTag(_ name: String, completion: @escaping ([FileItem]) -> Void) {
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "kMDItemUserTags == %@", name)
        query.searchScopes = [NSMetadataQueryLocalComputerScope]

        let box = ObserverBox()
        box.token = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main
        ) { _ in
            query.disableUpdates()
            var results: [FileItem] = []
            for i in 0..<query.resultCount {
                if let md = query.result(at: i) as? NSMetadataItem,
                   let path = md.value(forAttribute: NSMetadataItemPathKey) as? String {
                    results.append(FileItem(url: URL(fileURLWithPath: path)))
                }
            }
            query.stop()
            box.release()
            completion(results)
        }
        query.start()
    }
}

/// Petit conteneur pour liberer l'observateur depuis sa propre closure.
private final class ObserverBox {
    var token: NSObjectProtocol?
    func release() {
        if let token { NotificationCenter.default.removeObserver(token) }
        token = nil
    }
}

private extension UserDefaults {
    func register(tag: String) {
        let key = "com.jerome.mexplorer.customTags"
        var list = stringArray(forKey: key) ?? []
        let system = SidebarCatalog.systemTags.map { $0.name }
        guard !system.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }),
              !list.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) else { return }
        list.append(tag)
        set(list, forKey: key)
    }
}
