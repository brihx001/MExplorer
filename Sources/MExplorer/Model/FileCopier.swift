import Darwin
import Foundation

/// Drapeau d'annulation partage entre le thread qui lance l'operation et celui
/// qui l'execute.
final class OperationCancel {
    private var flag = false
    private let lock = NSLock()

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return flag
    }

    func cancel() { lock.lock(); flag = true; lock.unlock() }
    func reset() { lock.lock(); flag = false; lock.unlock() }
}

/// Copie et deplacement annulables, avec progression en octets.
///
/// `FileManager.copyItem` ne rend la main qu'une fois le fichier entier copie :
/// une image disque de 40 Go n'y est pas interruptible. `copyfile(3)` accepte
/// un rappel appele tous les mega-octets, qui peut repondre `COPYFILE_QUIT`.
///
/// Le drapeau `COPYFILE_CLONE` garde le chemin rapide : sur APFS et au sein
/// d'un meme volume, la copie est un clone instantane et aucun octet ne
/// circule. Mesure sur ce Mac avec 300 Mo : 0,000 s en clone contre 0,622 s en
/// copie reelle. Le rappel ne sert donc qu'aux copies qui travaillent vraiment.
enum FileCopier {

    /// Contexte passe a `copyfile` : un rappel C ne capture rien, tout doit
    /// transiter par ce pointeur.
    private final class Context {
        let cancel: OperationCancel
        let onBytes: (Int64) -> Void
        init(cancel: OperationCancel, onBytes: @escaping (Int64) -> Void) {
            self.cancel = cancel
            self.onBytes = onBytes
        }
    }

    struct Cancelled: LocalizedError {
        var errorDescription: String? { L("Operation annulee.") }
    }

    /// Copie `source` vers `target`, qui ne doit pas exister.
    static func copy(_ source: URL, to target: URL,
                     cancel: OperationCancel,
                     onBytes: @escaping (Int64) -> Void) throws {
        let context = Context(cancel: cancel, onBytes: onBytes)
        guard let state = copyfile_state_alloc() else { throw CocoaError(.fileWriteUnknown) }
        defer { copyfile_state_free(state) }

        // La valeur attendue est le pointeur de fonction lui-meme, pas son
        // adresse : passer `&callback` y ferait sauter copyfile et planter.
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB),
                           unsafeBitCast(callback, to: UnsafeRawPointer.self))
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CTX),
                           Unmanaged.passUnretained(context).toOpaque())

        let flags = copyfile_flags_t(COPYFILE_CLONE | COPYFILE_RECURSIVE)
        let result = copyfile(source.path, target.path, state, flags)
        guard result == 0 else {
            // Un abandon laisse derriere lui un fichier tronque.
            if cancel.isCancelled {
                try? FileManager.default.removeItem(at: target)
                throw Cancelled()
            }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [
                NSLocalizedDescriptionKey: String(cString: strerror(errno)),
                NSLocalizedFailureReasonErrorKey: L("Copie de \"%@\" impossible.", source.lastPathComponent)
            ])
        }
        withExtendedLifetime(context) {}
    }

    /// Deplace `source` vers `target`.
    ///
    /// Au sein d'un volume, `rename` est instantane et rien n'est a annuler.
    /// D'un volume a l'autre, le noyau refuse (`EXDEV`) et il faut copier puis
    /// effacer : c'est alors la copie, annulable, qui fait le travail.
    static func move(_ source: URL, to target: URL,
                     cancel: OperationCancel,
                     onBytes: @escaping (Int64) -> Void) throws {
        if rename(source.path, target.path) == 0 { return }
        guard errno == EXDEV else {
            // Toute autre erreur repart par FileManager, dont les messages
            // sont plus parlants que strerror.
            try FileManager.default.moveItem(at: source, to: target)
            return
        }
        try copy(source, to: target, cancel: cancel, onBytes: onBytes)
        try FileManager.default.removeItem(at: source)
    }

    /// Taille totale d'un element, dossiers compris : sert a donner une echelle
    /// a la progression.
    static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        if values.isDirectory != true {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys),
                                                          options: [.skipsPackageDescendants]) else { return 0 }
        var total: Int64 = 0
        for case let child as URL in walker {
            guard let v = try? child.resourceValues(forKeys: keys), v.isDirectory != true else { continue }
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        return total
    }

    private static let callback: copyfile_callback_t = { what, stage, state, _, _, info in
        guard let info else { return COPYFILE_CONTINUE }
        let context = Unmanaged<Context>.fromOpaque(info).takeUnretainedValue()
        if context.cancel.isCancelled { return COPYFILE_QUIT }
        if what == COPYFILE_COPY_DATA, stage == COPYFILE_PROGRESS, let state {
            var copied: off_t = 0
            copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &copied)
            context.onBytes(Int64(copied))
        }
        return COPYFILE_CONTINUE
    }
}
