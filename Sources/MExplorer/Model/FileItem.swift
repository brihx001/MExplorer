import AppKit
import UniformTypeIdentifiers

/// Instantane immuable d'une entree du systeme de fichiers.
/// NSObject pour servir d'identite stable dans NSOutlineView / NSTableView.
final class FileItem: NSObject {

    static let resourceKeys: [URLResourceKey] = [
        .localizedNameKey, .nameKey,
        .isDirectoryKey, .isPackageKey, .isApplicationKey,
        .isSymbolicLinkKey, .isAliasFileKey, .isHiddenKey,
        .fileSizeKey, .totalFileSizeKey, .fileAllocatedSizeKey,
        .contentModificationDateKey, .creationDateKey, .addedToDirectoryDateKey,
        .contentTypeKey, .localizedTypeDescriptionKey,
        .labelNumberKey, .tagNamesKey,
        .isWritableKey, .isVolumeKey
    ]

    /// Jeu de clefs du chargement de dossier.
    ///
    /// Trois clefs en sont exclues, toutes mesurees comme couteuses :
    /// - `tagNames` et `labelNumber` passent par DesktopServices et provoquent
    ///   un `getxattr` par fichier ;
    /// - `localizedName` passe par LaunchServices, qui interroge TCC : environ
    ///   5 secondes pour 22 elements dans un dossier protege.
    ///
    /// Elles sont lues ensuite, en tache de fond (voir TabState).
    static let listingKeys: [URLResourceKey] = resourceKeys.filter {
        $0 != .tagNamesKey && $0 != .labelNumberKey && $0 != .localizedNameKey
    }

    let url: URL
    var displayName: String
    let rawName: String
    let isDirectory: Bool
    let isPackage: Bool
    let isApplication: Bool
    let isSymbolicLink: Bool
    let isAliasFile: Bool
    /// Lien symbolique dont la cible est un dossier.
    let linksToDirectory: Bool
    let isHidden: Bool
    let isWritable: Bool
    let isVolume: Bool
    let byteSize: Int64
    let modificationDate: Date?
    let creationDate: Date?
    let addedDate: Date?
    let contentType: UTType?
    let kindDescription: String
    var labelNumber: Int
    var tagNames: [String]

    /// Taille calculee recursivement pour les dossiers (nil tant que non calculee).
    var computedFolderSize: Int64?

    init(url: URL, values: URLResourceValues?) {
        self.url = url
        let v = values
        self.rawName = v?.name ?? url.lastPathComponent
        self.displayName = v?.localizedName ?? url.lastPathComponent
        self.isDirectory = v?.isDirectory ?? false
        self.isPackage = v?.isPackage ?? false
        self.isApplication = v?.isApplication ?? false
        self.isSymbolicLink = v?.isSymbolicLink ?? false
        self.isAliasFile = v?.isAliasFile ?? false
        // `isDirectory` decrit le lien lui-meme, pas sa cible : sans cette
        // resolution, un lien vers un dossier (celui que OneDrive pose dans le
        // dossier personnel) n'etait pas navigable. Un lien se resout d'un
        // simple appel systeme, contrairement a un alias Finder dont la lecture
        // du signet peut bloquer : celui-la n'est resolu qu'a l'ouverture.
        self.linksToDirectory = (v?.isSymbolicLink ?? false)
            && (try? url.resolvingSymlinksInPath()
                .resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        self.isHidden = (v?.isHidden ?? false) || url.lastPathComponent.hasPrefix(".")
        self.isWritable = v?.isWritable ?? true
        self.isVolume = v?.isVolume ?? false
        self.byteSize = Int64(v?.totalFileSize ?? v?.fileSize ?? 0)
        self.modificationDate = v?.contentModificationDate
        self.creationDate = v?.creationDate
        self.addedDate = v?.addedToDirectoryDate
        self.contentType = v?.contentType
        self.kindDescription = Self.sharedKind(
            v?.localizedTypeDescription
                ?? (v?.isDirectory == true ? L("Dossier") : L("Document")))
        self.labelNumber = v?.labelNumber ?? 0
        self.tagNames = v?.tagNames ?? []
        super.init()
    }

    convenience init(url: URL) {
        let values = try? url.resourceValues(forKeys: Set(FileItem.resourceKeys))
        self.init(url: url, values: values)
    }

    /// Un dossier "navigable" : un paquet (.app, .rtfd) se comporte comme un fichier au double-clic.
    var isNavigableContainer: Bool { (isDirectory || linksToDirectory) && !isPackage }

    /// Les milliers de fichiers d'un meme type partagent le meme libelle
    /// ("Document texte") : le systeme en rend une chaine neuve a chaque
    /// appel, on n'en garde qu'une.
    private static var kindPool: [String: String] = [:]
    private static let kindLock = NSLock()

    private static func sharedKind(_ kind: String) -> String {
        kindLock.lock()
        defer { kindLock.unlock() }
        if let existing = kindPool[kind] { return existing }
        if kindPool.count < 512 { kindPool[kind] = kind }
        return kind
    }

    /// Etat iCloud, lu a la demande : il ne sert qu'au volet de details, pour
    /// l'element selectionne. Demande au listing, il coutait a lui seul les
    /// deux tiers du temps de chargement d'un grand dossier.
    var cloudState: (isUbiquitous: Bool, status: URLUbiquitousItemDownloadingStatus?) {
        let v = try? url.resourceValues(forKeys: [.isUbiquitousItemKey,
                                                  .ubiquitousItemDownloadingStatusKey])
        return (v?.isUbiquitousItem ?? false, v?.ubiquitousItemDownloadingStatus)
    }

    /// Droits, proprietaire et groupe, lus a la demande et une seule fois.
    ///
    /// Ces colonnes sont facultatives : les lire au chargement ferait un
    /// `lstat` par element dans tous les dossiers, y compris quand elles ne
    /// sont pas affichees. Le resultat est retenu sur l'element, dont la duree
    /// de vie est celle du listing : un changement de droits apparait au
    /// rechargement du dossier, comme le reste.
    private var cachedUnix: UnixAttributes??
    var unixAttributes: UnixAttributes? {
        if let cachedUnix { return cachedUnix }
        let read = UnixAttributes.read(at: url)
        cachedUnix = .some(read)
        return read
    }

    /// Vrai si demander une vignette Quick Look a un sens.
    ///
    /// Les paquets sont exclus volontairement : une requete sur une bibliotheque
    /// protegee par TCC (Photos Library.photoslibrary) ne recoit jamais de
    /// reponse et bloque la connexion QuickLook de tout le processus, ce qui
    /// prive de vignette tous les autres fichiers du dossier.
    var supportsThumbnail: Bool {
        !isDirectory && !isPackage && !isApplication
            && !isVolume && !isSymbolicLink && !isAliasFile
    }

    /// Extension affichee (vide pour les dossiers).
    var fileExtension: String { isDirectory && !isPackage ? "" : url.pathExtension }

    /// Un paquet (.app, .rtfd) est un dossier sur le disque : sa taille n'est
    /// connue qu'apres calcul recursif, comme pour un dossier ordinaire.
    var effectiveSize: Int64? {
        isDirectory ? computedFolderSize : byteSize
    }

    var labelColor: NSColor? { FileItem.color(forLabelNumber: labelNumber) }

    static func color(forLabelNumber n: Int) -> NSColor? {
        switch n {
        case 1: return .systemGray
        case 2: return .systemGreen
        case 3: return .systemPurple
        case 4: return .systemBlue
        case 5: return .systemYellow
        case 6: return .systemRed
        case 7: return .systemOrange
        default: return nil
        }
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? FileItem else { return false }
        return other.url == url
    }

    override var hash: Int { url.hashValue }
    override var description: String { "FileItem(\(url.path))" }
}
