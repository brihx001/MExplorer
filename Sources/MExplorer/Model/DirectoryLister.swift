import Foundation

enum DirectoryLoadError: Error {
    case notADirectory
    case accessDenied(URL)
    case underlying(Error)
}

enum DirectoryLister {

    private static let queue = DispatchQueue(label: "com.jerome.mexplorer.lister",
                                             qos: .userInitiated,
                                             attributes: .concurrent)

    /// Lecture synchrone (a appeler hors du thread principal).
    static func listSync(_ url: URL, showHidden: Bool) throws -> [FileItem] {
        var options: FileManager.DirectoryEnumerationOptions = [.skipsSubdirectoryDescendants]
        if !showHidden { options.insert(.skipsHiddenFiles) }

        let keys = Set(FileItem.listingKeys)
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: Array(keys),
                options: options
            )
            return urls.map { child in
                FileItem(url: child, values: try? child.resourceValues(forKeys: keys))
            }
        } catch let error as NSError {
            if error.domain == NSCocoaErrorDomain,
               error.code == NSFileReadNoPermissionError || error.code == NSFileReadUnknownError {
                throw DirectoryLoadError.accessDenied(url)
            }
            throw DirectoryLoadError.underlying(error)
        }
    }

    /// Lecture asynchrone ; `completion` est invoquee sur la file principale.
    /// `token` permet a l'appelant d'ignorer les resultats perimes.
    static func list(_ url: URL,
                     showHidden: Bool,
                     token: Int,
                     completion: @escaping (Int, Result<[FileItem], DirectoryLoadError>) -> Void) {
        queue.async {
            let result: Result<[FileItem], DirectoryLoadError>
            do {
                result = .success(try listSync(url, showHidden: showHidden))
            } catch let e as DirectoryLoadError {
                result = .failure(e)
            } catch {
                result = .failure(.underlying(error))
            }
            DispatchQueue.main.async { completion(token, result) }
        }
    }

    /// Taille recursive d'un dossier, calculee en tache de fond.
    static func folderSize(_ url: URL, cancelled: @escaping () -> Bool,
                           completion: @escaping (Int64) -> Void) {
        queue.async {
            var total: Int64 = 0
            let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
            guard let e = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: Array(keys),
                options: [],
                errorHandler: { _, _ in true }
            ) else {
                DispatchQueue.main.async { completion(0) }
                return
            }
            var counter = 0
            for case let child as URL in e {
                counter += 1
                if counter % 512 == 0 && cancelled() { return }
                guard let v = try? child.resourceValues(forKeys: keys), v.isRegularFile == true else { continue }
                total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
            }
            DispatchQueue.main.async { completion(total) }
        }
    }
}
