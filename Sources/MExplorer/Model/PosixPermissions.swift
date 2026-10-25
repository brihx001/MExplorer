import Foundation

/// Droits POSIX d'un element, lisibles et modifiables.
///
/// macOS affiche ces droits sous forme de trois menus (proprietaire, groupe,
/// autres) la ou le shell parle en octal. Les deux representations sont
/// gardees : la fenetre d'informations montre le mode, et chaque menu agit sur
/// les trois bits qui le concernent.
struct PosixPermissions: Equatable {

    enum Access: String, CaseIterable, Identifiable {
        case none, read, readWrite

        var id: String { rawValue }

        var title: String {
            switch self {
            case .none: return L("Aucun acces")
            case .read: return L("Lecture seule")
            case .readWrite: return L("Lecture et ecriture")
            }
        }

        /// Les bits de lecture et d'ecriture, sans toucher a l'execution :
        /// retirer le bit x d'un dossier le rendrait intraversable, et celui
        /// d'un binaire le rendrait inutilisable.
        var bits: mode_t {
            switch self {
            case .none: return 0
            case .read: return 0o4
            case .readWrite: return 0o6
            }
        }

        static func from(_ bits: mode_t) -> Access {
            if bits & 0o2 != 0 { return .readWrite }
            if bits & 0o4 != 0 { return .read }
            return .none
        }
    }

    var owner: Access
    var group: Access
    var others: Access
    /// Bits d'execution d'origine, reposes tels quels a l'ecriture.
    private var executeBits: mode_t

    var mode: mode_t {
        (owner.bits << 6) | (group.bits << 3) | others.bits | executeBits
    }

    var octal: String { String(format: "%03o", mode & 0o777) }

    /// Le lien est resolu avant toute chose.
    ///
    /// `attributesOfItem` lit le lien lui-meme (lstat) tandis que
    /// `setAttributes` ecrit sur sa cible (chmod suit le lien) : lire d'un cote
    /// et ecrire de l'autre donnait a la cible les bits du lien, dont le 755
    /// que macOS pose sur tous les liens symboliques.
    private static func resolved(_ url: URL) -> URL { url.resolvingSymlinksInPath() }

    static func read(at url: URL) -> PosixPermissions? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: resolved(url).path),
              let number = attributes[.posixPermissions] as? NSNumber else { return nil }
        let mode = mode_t(number.uint16Value) & 0o777
        return PosixPermissions(
            owner: .from((mode >> 6) & 0o7),
            group: .from((mode >> 3) & 0o7),
            others: .from(mode & 0o7),
            executeBits: mode & 0o111)
    }

    func write(to url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: mode)],
                                              ofItemAtPath: Self.resolved(url).path)
    }

    /// Proprietaire et groupe, pour l'affichage seul : les changer demande des
    /// droits que le bac a sable n'accorde pas.
    static func ownership(at url: URL) -> (owner: String?, group: String?) {
        let attributes = try? FileManager.default.attributesOfItem(atPath: resolved(url).path)
        return (attributes?[.ownerAccountName] as? String, attributes?[.groupOwnerAccountName] as? String)
    }
}
