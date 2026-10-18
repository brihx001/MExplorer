import Foundation

/// Langue de l'interface.
///
/// Les libelles sont ecrits en francais dans le code : le francais sert donc
/// de cle, et chaque autre langue fournit une table de traduction. Une cle
/// absente de la table retombe sur le francais, ce qui laisse l'application
/// utilisable meme avec une traduction incomplete.
enum AppLanguage: String, CaseIterable, Identifiable {

    case system
    case french
    case english

    var id: String { rawValue }

    /// Nom affiche dans les reglages, dans sa propre langue.
    var title: String {
        switch self {
        case .system: return L("Langue du systeme")
        case .french: return "Francais"
        case .english: return "English"
        }
    }

    /// Langue effective une fois `system` resolue.
    var resolved: AppLanguage {
        guard self == .system else { return self }
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("fr") ? .french : .english
    }
}

enum L10n {

    /// Postee quand la langue change : les vues AppKit s'y abonnent pour
    /// reconstruire leurs libelles (SwiftUI suit AppSettings).
    static let changed = Notification.Name("com.jerome.mexplorer.languageChanged")

    private(set) static var table: [String: String] = [:]

    /// Charge la table correspondante. Le francais n'en a pas : il est deja
    /// dans le code.
    static func apply(_ language: AppLanguage) {
        switch language.resolved {
        case .english: table = EnglishStrings.table
        default: table = [:]
        }
        NotificationCenter.default.post(name: changed, object: nil)
    }
}

/// Traduit un libelle ecrit en francais dans le code.
func L(_ key: String) -> String {
    L10n.table[key] ?? key
}

/// Variante pour les libelles identiques en francais mais distincts ailleurs :
/// "Annuler" vaut *Undo* dans le menu Edition et *Cancel* sur un bouton. La
/// table porte alors la cle "<contexte>|<libelle>".
func L(_ key: String, context: String) -> String {
    L10n.table["\(context)|\(key)"] ?? L10n.table[key] ?? key
}

/// Variante a trous, pour les libelles qui portent une valeur.
/// Le gabarit utilise les marqueurs de `String(format:)` (`%@`, `%d`).
func L(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: L10n.table[key] ?? key, arguments: arguments)
}
