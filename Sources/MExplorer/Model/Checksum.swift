import CryptoKit
import Foundation

/// Calcul de sommes de controle sur une selection.
///
/// Les fichiers sont lus par blocs : une image disque de 40 Go ne doit pas
/// tenir en memoire pour etre hachee.
final class ChecksumJob {

    enum Algorithm: String, CaseIterable, Identifiable {
        case sha256, sha1, md5

        var id: String { rawValue }

        var title: String {
            switch self {
            case .sha256: return "SHA-256"
            case .sha1: return "SHA-1"
            case .md5: return "MD5"
            }
        }
    }

    struct Result: Identifiable {
        let id = UUID()
        let url: URL
        let digest: String?
        let error: String?
    }

    /// 1 Mo : au-dela, le gain de debit ne compense plus l'empreinte memoire.
    private static let chunkSize = 1 << 20

    private var cancelled = false
    private let queue = DispatchQueue(label: "com.jerome.mexplorer.checksum", qos: .userInitiated)

    func cancel() { cancelled = true }

    /// `progress` et `completion` sont appeles sur le thread principal.
    func run(urls: [URL], algorithm: Algorithm,
             progress: @escaping (Int, String) -> Void,
             completion: @escaping ([Result]) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            var results: [Result] = []
            for (index, url) in urls.enumerated() {
                if self.cancelled { break }
                DispatchQueue.main.async { progress(index, url.lastPathComponent) }
                results.append(self.digest(of: url, algorithm: algorithm))
            }
            let finished = results
            DispatchQueue.main.async { completion(finished) }
        }
    }

    private func digest(of url: URL, algorithm: Algorithm) -> Result {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return Result(url: url, digest: nil, error: L("Fichier introuvable."))
        }
        guard !isDirectory.boolValue else {
            return Result(url: url, digest: nil, error: L("Un dossier n'a pas de somme de controle."))
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return Result(url: url, digest: nil, error: L("Lecture refusee."))
        }
        defer { try? handle.close() }

        var sha256 = SHA256()
        var sha1 = Insecure.SHA1()
        var md5 = Insecure.MD5()

        while true {
            if cancelled { return Result(url: url, digest: nil, error: L("Annule.")) }
            let chunk: Data?
            do { chunk = try handle.read(upToCount: Self.chunkSize) }
            catch { return Result(url: url, digest: nil, error: error.localizedDescription) }
            guard let chunk, !chunk.isEmpty else { break }
            switch algorithm {
            case .sha256: sha256.update(data: chunk)
            case .sha1: sha1.update(data: chunk)
            case .md5: md5.update(data: chunk)
            }
        }

        let hex: String
        switch algorithm {
        case .sha256: hex = Self.hex(sha256.finalize())
        case .sha1: hex = Self.hex(sha1.finalize())
        case .md5: hex = Self.hex(md5.finalize())
        }
        return Result(url: url, digest: hex, error: nil)
    }

    private static func hex<D: Digest>(_ digest: D) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
