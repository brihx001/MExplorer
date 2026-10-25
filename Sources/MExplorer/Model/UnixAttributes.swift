import Foundation

/// Droits, proprietaire et groupe d'un element, lus par `lstat`.
///
/// `lstat` decrit le lien symbolique lui-meme, comme `ls -l` : c'est bien le
/// lien que l'on veut voir dans la liste, sa cible ayant sa propre ligne
/// ailleurs. Un seul appel systeme suffit aux trois colonnes, la traduction
/// des identifiants en noms passant ensuite par un cache.
struct UnixAttributes {

    let mode: mode_t
    let userID: uid_t
    let groupID: gid_t

    static func read(at url: URL) -> UnixAttributes? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        return UnixAttributes(mode: info.st_mode, userID: info.st_uid, groupID: info.st_gid)
    }

    /// Chaine a la maniere de `ls -l` : type puis trois triplets.
    var text: String {
        var result = String(typeCharacter)
        for shift in [6, 3, 0] {
            let bits = (mode >> mode_t(shift)) & 0o7
            result.append(bits & 0o4 != 0 ? "r" : "-")
            result.append(bits & 0o2 != 0 ? "w" : "-")
            result.append(executeCharacter(shift: shift, bits: bits))
        }
        return result
    }

    var octal: String { String(format: "%03o", mode & 0o777) }

    private var typeCharacter: Character {
        switch mode & S_IFMT {
        case S_IFDIR: return "d"
        case S_IFLNK: return "l"
        case S_IFIFO: return "p"
        case S_IFSOCK: return "s"
        case S_IFCHR: return "c"
        case S_IFBLK: return "b"
        default: return "-"
        }
    }

    /// setuid, setgid et sticky remplacent le « x » de leur triplet, comme le
    /// fait `ls` : une majuscule quand le bit d'execution est absent.
    private func executeCharacter(shift: Int, bits: mode_t) -> Character {
        let executes = bits & 0o1 != 0
        switch shift {
        case 6 where mode & mode_t(S_ISUID) != 0: return executes ? "s" : "S"
        case 3 where mode & mode_t(S_ISGID) != 0: return executes ? "s" : "S"
        case 0 where mode & mode_t(S_ISVTX) != 0: return executes ? "t" : "T"
        default: return executes ? "x" : "-"
        }
    }

    // MARK: - Noms d'utilisateur et de groupe

    /// `getpwuid` et `getgrgid` interrogent le service d'annuaire : sur un Mac
    /// relie a un annuaire reseau, l'appel peut partir sur le reseau. Les
    /// reponses sont donc retenues, les identifiants d'un dossier se repetant
    /// de toute facon d'une ligne a l'autre.
    private static var userNames: [uid_t: String] = [:]
    private static var groupNames: [gid_t: String] = [:]
    private static let lock = NSLock()

    var userName: String {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        if let known = Self.userNames[userID] { return known }
        let name = getpwuid(userID).flatMap { String(cString: $0.pointee.pw_name) } ?? String(userID)
        Self.userNames[userID] = name
        return name
    }

    var groupName: String {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        if let known = Self.groupNames[groupID] { return known }
        let name = getgrgid(groupID).flatMap { String(cString: $0.pointee.gr_name) } ?? String(groupID)
        Self.groupNames[groupID] = name
        return name
    }
}
