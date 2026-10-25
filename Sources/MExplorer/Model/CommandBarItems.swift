import Foundation

/// Composition de la barre de commandes, reglable par l'utilisateur.
///
/// Les actions elles-memes restent dans `CommandBarView` : seule la liste de
/// ce qui est montre, et dans quel ordre, est decrite ici. Le reglage est
/// enregistre par identifiant, de sorte qu'une version ulterieure puisse
/// ajouter un bouton sans perdre la configuration existante.
enum CommandBarItem: String, CaseIterable, Identifiable, Codable {

    case newMenu, cut, copy, paste, rename, share, trash
    case compress, checksum, terminal
    case sortMenu, viewMenu, moreMenu

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newMenu: return L("Nouveau")
        case .cut: return L("Couper")
        case .copy: return L("Copier")
        case .paste: return L("Coller")
        case .rename: return L("Renommer")
        case .share: return L("Partager")
        case .trash: return L("Placer dans la corbeille")
        case .compress: return L("Compresser")
        case .checksum: return L("Somme de controle")
        case .terminal: return L("Ouvrir dans le Terminal")
        case .sortMenu: return L("Trier par")
        case .viewMenu: return L("Affichage")
        case .moreMenu: return L("Plus")
        }
    }

    var symbol: String {
        switch self {
        case .newMenu: return "plus"
        case .cut: return "scissors"
        case .copy: return "doc.on.doc"
        case .paste: return "doc.on.clipboard"
        case .rename: return "pencil"
        case .share: return "square.and.arrow.up"
        case .trash: return "trash"
        case .compress: return "archivebox"
        case .checksum: return "number"
        case .terminal: return "terminal"
        case .sortMenu: return "arrow.up.arrow.down"
        case .viewMenu: return "list.bullet"
        case .moreMenu: return "ellipsis"
        }
    }

    /// Les trois menus deroulants ne peuvent pas etre retires : « Affichage »
    /// porte les modes de presentation et « Plus » le reste des commandes,
    /// dont le reglage de cette barre.
    var isRemovable: Bool {
        switch self {
        case .viewMenu, .moreMenu: return false
        default: return true
        }
    }

    /// Composition d'origine, celle de l'Explorateur de Windows 11.
    static let defaults: [CommandBarItem] = [
        .newMenu, .cut, .copy, .paste, .rename, .share, .trash, .sortMenu, .viewMenu, .moreMenu
    ]

    /// Separateur dessine avant cet element dans la barre d'origine.
    static let separatorsBefore: Set<CommandBarItem> = [.cut, .sortMenu]
}
