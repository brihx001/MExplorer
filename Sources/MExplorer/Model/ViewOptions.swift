import AppKit

enum ColumnID: String, CaseIterable, Codable {
    case name, dateModified, kind, size, dateCreated, dateAdded, tags, fileExtension, path, cloud
    case permissions, owner, group

    var title: String {
        switch self {
        case .cloud: return L("iCloud")
        case .permissions: return L("Droits")
        case .owner: return L("Proprietaire")
        case .group: return L("Groupe")
        case .name: return L("Nom")
        case .dateModified: return L("Modifie le")
        case .kind: return L("Type")
        case .size: return L("Taille")
        case .dateCreated: return L("Cree le")
        case .dateAdded: return L("Ajoute le")
        case .tags: return L("Tags")
        case .fileExtension: return L("Extension")
        case .path: return L("Chemin")
        }
    }

    var defaultWidth: CGFloat {
        switch self {
        case .cloud: return 110
        case .permissions: return 110
        case .owner, .group: return 110
        case .name: return 320
        case .dateModified, .dateCreated, .dateAdded: return 150
        case .kind: return 160
        case .size: return 90
        case .tags: return 120
        case .fileExtension: return 90
        case .path: return 300
        }
    }

    var isRightAligned: Bool { self == .size }

    /// Les droits s'ecrivent en chasse fixe : sans cela, les trois triplets ne
    /// s'alignent pas d'une ligne a l'autre et deviennent illisibles.
    var isMonospaced: Bool { self == .permissions }

    static let defaultVisible: [ColumnID] = [.name, .dateModified, .kind, .size]
}

enum SortKey: String, CaseIterable, Codable {
    case name, dateModified, kind, size, dateCreated, dateAdded, tags, fileExtension

    var title: String { column.title }

    var column: ColumnID {
        switch self {
        case .name: return .name
        case .dateModified: return .dateModified
        case .kind: return .kind
        case .size: return .size
        case .dateCreated: return .dateCreated
        case .dateAdded: return .dateAdded
        case .tags: return .tags
        case .fileExtension: return .fileExtension
        }
    }

    /// Vrai pour les tris ou separer dossiers et fichiers n'a pas de sens :
    /// on veut voir ce qui a bouge recemment, quel qu'en soit le genre.
    var ignoresFolderGrouping: Bool {
        switch self {
        case .dateModified, .dateCreated, .dateAdded: return true
        default: return false
        }
    }

    init?(column: ColumnID) {
        switch column {
        case .name: self = .name
        case .dateModified: self = .dateModified
        case .kind: self = .kind
        case .size: self = .size
        case .dateCreated: self = .dateCreated
        case .dateAdded: self = .dateAdded
        case .tags: self = .tags
        case .fileExtension: self = .fileExtension
        // Ces colonnes ne servent pas de critere de tri : le chemin est le
        // meme pour tout un dossier, et les autres demanderaient d'interroger
        // chaque element du dossier, y compris ceux qui ne sont pas affiches,
        // ce que le chargement evite precisement.
        case .path, .cloud, .permissions, .owner, .group: return nil
        }
    }
}

enum GroupKey: String, CaseIterable, Codable {
    case none, name, kind, size, dateModified, tags

    var title: String {
        switch self {
        case .none: return L("(Aucun)")
        case .name: return L("Nom")
        case .kind: return L("Type")
        case .size: return L("Taille")
        case .dateModified: return L("Modifie le")
        case .tags: return L("Tags")
        }
    }
}

enum ViewMode: String, CaseIterable, Codable {
    case extraLargeIcons, largeIcons, mediumIcons, smallIcons, list, details, tiles, content

    var title: String {
        switch self {
        case .extraLargeIcons: return L("Tres grandes icones")
        case .largeIcons: return L("Grandes icones")
        case .mediumIcons: return L("Icones moyennes")
        case .smallIcons: return L("Petites icones")
        case .list: return L("Liste")
        case .details: return L("Details")
        case .tiles: return L("Mosaiques")
        case .content: return L("Contenu")
        }
    }

    var symbol: String {
        switch self {
        case .extraLargeIcons, .largeIcons: return "square.grid.2x2"
        case .mediumIcons: return "square.grid.3x3"
        case .smallIcons: return "square.grid.4x3.fill"
        case .list: return "list.bullet"
        case .details: return "list.dash"
        case .tiles: return "rectangle.grid.1x2"
        case .content: return "rectangle.grid.1x2.fill"
        }
    }

    var isIconGrid: Bool {
        switch self {
        case .extraLargeIcons, .largeIcons, .mediumIcons, .smallIcons, .tiles, .content: return true
        case .list, .details: return false
        }
    }

    /// Cote de l'icone dans les modes grille.
    var iconSide: CGFloat {
        switch self {
        case .extraLargeIcons: return 192
        case .largeIcons: return 96
        case .mediumIcons: return 64
        case .smallIcons: return 32
        case .tiles: return 48
        case .content: return 32
        default: return 16
        }
    }

    /// Taille de cellule dans les modes grille.
    var cellSize: NSSize {
        switch self {
        case .extraLargeIcons: return NSSize(width: 220, height: 240)
        case .largeIcons: return NSSize(width: 128, height: 132)
        case .mediumIcons: return NSSize(width: 96, height: 100)
        case .smallIcons: return NSSize(width: 200, height: 40)
        case .tiles: return NSSize(width: 260, height: 64)
        case .content: return NSSize(width: 10_000, height: 56)
        default: return NSSize(width: 100, height: 100)
        }
    }
}

/// Reglages d'affichage d'un dossier (memorises par dossier, comme le Finder).
struct FolderViewSettings: Codable, Equatable {
    var viewMode: ViewMode = .details
    var sortKey: SortKey = .name
    var ascending: Bool = true
    var groupKey: GroupKey = .none
    var foldersFirst: Bool = true
    var visibleColumns: [ColumnID] = ColumnID.defaultVisible
    var columnWidths: [String: Double] = [:]
    /// Calcul de la taille reelle des dossiers en mode Details.
    var calculateFolderSizes: Bool = true

    static let `default` = FolderViewSettings()

    init() {}

    /// Decodage tolerant : les reglages deja memorises sur disque n'ont pas
    /// forcement toutes les clefs. Sans cela, l'ajout d'un reglage effacerait
    /// silencieusement les preferences de tous les dossiers.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = FolderViewSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ defaultValue: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? defaultValue
        }
        viewMode = value(.viewMode, fallback.viewMode)
        sortKey = value(.sortKey, fallback.sortKey)
        ascending = value(.ascending, fallback.ascending)
        groupKey = value(.groupKey, fallback.groupKey)
        foldersFirst = value(.foldersFirst, fallback.foldersFirst)
        visibleColumns = value(.visibleColumns, fallback.visibleColumns)
        columnWidths = value(.columnWidths, fallback.columnWidths)
        calculateFolderSizes = value(.calculateFolderSizes, fallback.calculateFolderSizes)
        if visibleColumns.isEmpty { visibleColumns = ColumnID.defaultVisible }
    }
}
