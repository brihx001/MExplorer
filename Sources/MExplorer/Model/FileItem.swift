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
        .isWritableKey, .isReadableKey, .isExecutableKey,
        .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
        .isVolumeKey, .volumeNameKey, .volumeIsRemovableKey, .volumeIsEjectableKey,
        .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
        .isMountTriggerKey
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
    let isHidden: Bool
    let isWritable: Bool
    let isVolume: Bool
    let isEjectable: Bool
    let byteSize: Int64
    let modificationDate: Date?
    let creationDate: Date?
    let addedDate: Date?
    let contentType: UTType?
    let kindDescription: String
    var labelNumber: Int
    var tagNames: [String]
    let isUbiquitous: Bool
    let ubiquitousStatus: URLUbiquitousItemDownloadingStatus?
    let volumeCapacity: Int64
    let volumeAvailable: Int64

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
        self.isHidden = (v?.isHidden ?? false) || url.lastPathComponent.hasPrefix(".")
        self.isWritable = v?.isWritable ?? true
        self.isVolume = v?.isVolume ?? false
        self.isEjectable = (v?.volumeIsEjectable ?? false) || (v?.volumeIsRemovable ?? false)
        self.byteSize = Int64(v?.totalFileSize ?? v?.fileSize ?? 0)
        self.modificationDate = v?.contentModificationDate
        self.creationDate = v?.creationDate
        self.addedDate = v?.addedToDirectoryDate
        self.contentType = v?.contentType
        self.kindDescription = v?.localizedTypeDescription
            ?? (v?.isDirectory == true ? "Dossier" : "Document")
        self.labelNumber = v?.labelNumber ?? 0
        self.tagNames = v?.tagNames ?? []
        self.isUbiquitous = v?.isUbiquitousItem ?? false
        self.ubiquitousStatus = v?.ubiquitousItemDownloadingStatus
        self.volumeCapacity = Int64(v?.volumeTotalCapacity ?? 0)
        self.volumeAvailable = Int64(v?.volumeAvailableCapacity ?? 0)
        super.init()
    }

    convenience init(url: URL) {
        let values = try? url.resourceValues(forKeys: Set(FileItem.resourceKeys))
        self.init(url: url, values: values)
    }

    /// Un dossier "navigable" : un paquet (.app, .rtfd) se comporte comme un fichier au double-clic.
    var isNavigableContainer: Bool { isDirectory && !isPackage }

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
