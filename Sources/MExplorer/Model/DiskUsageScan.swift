import CryptoKit
import Foundation

/// Parcours recursif d'un dossier, pour l'occupation du disque et la recherche
/// de doublons.
///
/// Les deux repondent a la meme question, « que contient vraiment cette
/// arborescence ? », et paient le meme prix : un parcours complet. Il est donc
/// fait une fois, annulable, et les deux vues s'en servent.
final class DiskUsageScan {

    struct Entry: Identifiable {
        let id = UUID()
        let url: URL
        let size: Int64
        let isDirectory: Bool
    }

    struct DuplicateGroup: Identifiable {
        let id = UUID()
        let size: Int64
        let urls: [URL]
        /// Place reprise si l'on ne garde qu'un exemplaire.
        var reclaimable: Int64 { size * Int64(urls.count - 1) }
    }

    struct Result {
        /// Les plus gros elements de premier niveau, dossiers comme fichiers.
        var children: [Entry] = []
        /// Les plus gros fichiers de toute l'arborescence.
        var largestFiles: [Entry] = []
        var duplicates: [DuplicateGroup] = []
        var totalSize: Int64 = 0
        var fileCount = 0
        var wasCancelled = false
    }

    private let cancelFlag = OperationCancel()
    private let queue = DispatchQueue(label: "com.jerome.mexplorer.diskusage", qos: .utility)

    func cancel() { cancelFlag.cancel() }

    /// `progress` donne le nombre de fichiers vus, pour que l'attente ne soit
    /// pas muette sur une grosse arborescence.
    func run(root: URL,
             findDuplicates: Bool,
             progress: @escaping (Int) -> Void,
             completion: @escaping (Result) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            var result = Result()

            // Premier niveau : chaque entree porte le poids de sa propre
            // arborescence, c'est ce qui rend la vue lisible.
            let children = (try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles])) ?? []

            var files: [Entry] = []
            var bySize: [Int64: [URL]] = [:]
            var seen = 0

            for child in children {
                if self.cancelFlag.isCancelled { break }
                let isDirectory = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                var subtotal: Int64 = 0
                self.walk(child, isDirectory: isDirectory) { url, size in
                    subtotal += size
                    seen += 1
                    files.append(Entry(url: url, size: size, isDirectory: false))
                    if findDuplicates, size > 0 { bySize[size, default: []].append(url) }
                    if seen % 500 == 0 {
                        let count = seen
                        DispatchQueue.main.async { progress(count) }
                    }
                }
                result.children.append(Entry(url: child, size: subtotal, isDirectory: isDirectory))
                result.totalSize += subtotal
            }

            result.fileCount = files.count
            result.children.sort { $0.size > $1.size }
            result.largestFiles = files.sorted { $0.size > $1.size }.prefix(50).map { $0 }
            if findDuplicates, !self.cancelFlag.isCancelled {
                result.duplicates = self.duplicates(among: bySize)
            }
            result.wasCancelled = self.cancelFlag.isCancelled

            let finished = result
            DispatchQueue.main.async { completion(finished) }
        }
    }

    /// Visite chaque fichier ordinaire sous `url`.
    private func walk(_ url: URL, isDirectory: Bool, visit: (URL, Int64) -> Void) {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        guard isDirectory else {
            if let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true {
                visit(url, Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0))
            }
            return
        }
        guard let walker = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: Array(keys),
            options: [], errorHandler: { _, _ in true }) else { return }

        var counter = 0
        for case let child as URL in walker {
            counter += 1
            if counter % 256 == 0, cancelFlag.isCancelled { return }
            guard let values = try? child.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            visit(child, Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0))
        }
    }

    /// Doublons averes parmi les fichiers de meme taille.
    ///
    /// La taille sert de premier tamis : elle est gratuite et ecarte presque
    /// tout. Seuls les groupes restants sont haches, et seulement sur leur
    /// premier mega-octet puis en entier, pour ne pas lire des gigaoctets
    /// avant de constater une difference au deuxieme bloc.
    private func duplicates(among bySize: [Int64: [URL]]) -> [DuplicateGroup] {
        var groups: [DuplicateGroup] = []
        for (size, urls) in bySize where urls.count > 1 {
            if cancelFlag.isCancelled { break }
            var byPrefix: [String: [URL]] = [:]
            for url in urls {
                guard let digest = hash(url, limit: 1 << 20) else { continue }
                byPrefix[digest, default: []].append(url)
            }
            for (_, candidates) in byPrefix where candidates.count > 1 {
                if cancelFlag.isCancelled { break }
                // Au-dela d'un mega-octet, le prefixe ne suffit pas a conclure.
                guard size > (1 << 20) else {
                    groups.append(DuplicateGroup(size: size, urls: candidates))
                    continue
                }
                var byFull: [String: [URL]] = [:]
                for url in candidates {
                    guard let digest = hash(url, limit: nil) else { continue }
                    byFull[digest, default: []].append(url)
                }
                for (_, confirmed) in byFull where confirmed.count > 1 {
                    groups.append(DuplicateGroup(size: size, urls: confirmed))
                }
            }
        }
        return groups.sorted { $0.reclaimable > $1.reclaimable }
    }

    private func hash(_ url: URL, limit: Int?) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        var read = 0
        let chunkSize = 1 << 20
        while true {
            if cancelFlag.isCancelled { return nil }
            let want = limit.map { min(chunkSize, $0 - read) } ?? chunkSize
            guard want > 0 else { break }
            guard let chunk = try? handle.read(upToCount: want), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
            read += chunk.count
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
