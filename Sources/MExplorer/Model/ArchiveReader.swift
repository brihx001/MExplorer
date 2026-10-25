import Foundation

/// Extraction d'archives, et ouverture d'une archive comme un dossier.
///
/// macOS n'expose aucune API de decompression : `NSFileCoordinator` sait
/// creer un .zip mais pas le relire, `Compression` ne traite que des flux sans
/// conteneur, et `AppleArchive` ne connait que le format .aar. Les outils du
/// systeme sont donc appeles. Un processus lance depuis une application en bac
/// a sable herite du bac a sable : `ditto` et `tar` ne verront que ce que
/// MExplorer voit.
enum ArchiveReader {

    enum Format {
        case zip
        case tar
        /// Archive tar compressee, que `tar` reconnait seul a l'extension.
        case tarCompressed

        var tool: String {
            switch self {
            case .zip: return "/usr/bin/ditto"
            case .tar, .tarCompressed: return "/usr/bin/tar"
            }
        }
    }

    /// Format de l'archive, ou nil si le fichier n'en est pas une.
    static func format(of url: URL) -> Format? {
        let name = url.lastPathComponent.lowercased()
        if name.hasSuffix(".zip") { return .zip }
        if name.hasSuffix(".tar") { return .tar }
        for suffix in [".tar.gz", ".tgz", ".tar.bz2", ".tbz", ".tbz2", ".tar.xz", ".txz", ".tar.zst"]
        where name.hasSuffix(suffix) { return .tarCompressed }
        return nil
    }

    static func isArchive(_ url: URL) -> Bool { format(of: url) != nil }

    /// Nom de dossier propose pour l'extraction : « notes.tar.gz » donne
    /// « notes », pas « notes.tar ».
    static func baseName(of url: URL) -> String {
        var name = url.lastPathComponent
        for suffix in [".tar.gz", ".tar.bz2", ".tar.xz", ".tar.zst", ".tgz", ".tbz2", ".tbz", ".txz", ".tar", ".zip"] {
            if name.lowercased().hasSuffix(suffix) {
                name = String(name.dropLast(suffix.count))
                break
            }
        }
        return name.isEmpty ? url.lastPathComponent : name
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Extrait `archive` dans un dossier neuf sous `destination`, et rend ce
    /// dossier.
    static func extract(_ archive: URL, into destination: URL,
                        completion: @escaping (Result<URL, Error>) -> Void) {
        guard let format = format(of: archive) else {
            completion(.failure(Failure(message: L("Ce fichier n'est pas une archive reconnue."))))
            return
        }
        let target = FileOperations.uniqueURL(for: destination.appendingPathComponent(baseName(of: archive)))
        extract(archive, format: format, to: target, completion: completion)
    }

    /// Extrait vers un dossier precis, qui est cree.
    static func extract(_ archive: URL, format: Format, to target: URL,
                        completion: @escaping (Result<URL, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                let arguments: [String]
                switch format {
                case .zip:
                    // -x extrait, -k lit une archive PKZip, et les metadonnees
                    // Mac sont restaurees telles qu'elles ont ete ecrites.
                    arguments = ["-x", "-k", archive.path, target.path]
                case .tar:
                    arguments = ["-x", "-f", archive.path, "-C", target.path]
                case .tarCompressed:
                    // tar reconnait seul gzip, bzip2, xz et zstd.
                    arguments = ["-x", "-f", archive.path, "-C", target.path]
                }
                try run(format.tool, arguments)
                DispatchQueue.main.async { completion(.success(target)) }
            } catch {
                try? FileManager.default.removeItem(at: target)
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    /// Ouvre une archive comme un dossier.
    ///
    /// Le contenu est extrait une fois dans un dossier de travail, puis
    /// parcouru comme n'importe quel dossier : les elements y sont de vrais
    /// fichiers, avec une vraie URL, ce qu'exige tout le reste de
    /// l'application. La contrepartie est claire et assumee : ce qui est
    /// modifie la ne retourne pas dans l'archive.
    ///
    /// Le dossier est garde tant que l'archive n'a pas change, pour que la
    /// rouvrir soit immediat.
    static func open(_ archive: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        guard let format = format(of: archive) else {
            completion(.failure(Failure(message: L("Ce fichier n'est pas une archive reconnue."))))
            return
        }
        let modified = (try? archive.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let stamp = modified.map { String(Int($0.timeIntervalSince1970)) } ?? "0"
        let key = "\(abs(archive.path.hashValue))-\(stamp)"
        let cached = workingDirectory.appendingPathComponent(key, isDirectory: true)
            .appendingPathComponent(baseName(of: archive), isDirectory: true)

        if FileManager.default.fileExists(atPath: cached.path) {
            completion(.success(cached))
            return
        }
        extract(archive, format: format, to: cached, completion: completion)
    }

    /// Dossier de travail, dans le conteneur de l'application : il part avec
    /// elle et n'encombre pas le dossier de l'utilisateur.
    static var workingDirectory: URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("archives", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Efface les extractions precedentes.
    static func clearWorkingDirectory() {
        try? FileManager.default.removeItem(at: workingDirectory)
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = Pipe()
        try process.run()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let text = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw Failure(message: text.isEmpty
                          ? L("L'extraction a echoue (code %d).", Int(process.terminationStatus))
                          : text)
        }
    }
}
