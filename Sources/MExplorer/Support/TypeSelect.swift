import AppKit

/// Saisie rapide : les lettres tapees a la suite selectionnent le premier
/// element dont le nom commence par elles.
///
/// NSTableView sait le faire seule (`typeSelectStringFor`), mais pas
/// NSCollectionView : la grille d'icones a besoin de ce tampon.
final class TypeSelect {

    /// Au-dela de ce silence, la frappe suivante recommence une recherche.
    /// Valeur retenue par AppKit pour `NSTableView`.
    private let timeout: TimeInterval = 1.0

    private var buffer = ""
    private var lastKeystroke = Date.distantPast

    /// Vrai si une recherche est en cours : une espace prolonge alors le mot
    /// au lieu de declencher Coup d'oeil.
    var isTyping: Bool {
        !buffer.isEmpty && Date().timeIntervalSince(lastKeystroke) < timeout
    }

    /// Prefixe a rechercher, ou nil si la touche n'est pas une saisie.
    func accept(_ event: NSEvent) -> String? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.isEmpty || flags == .shift else { return nil }
        guard let characters = event.charactersIgnoringModifiers, !characters.isEmpty,
              let scalar = characters.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(scalar),
              !CharacterSet.illegalCharacters.contains(scalar) else { return nil }

        let now = Date()
        if now.timeIntervalSince(lastKeystroke) >= timeout { buffer = "" }
        lastKeystroke = now
        buffer += characters
        return buffer
    }

    /// Vrai tant que l'utilisateur repete la meme lettre : on fait alors
    /// defiler les elements qui commencent par elle, comme le Finder.
    var isCycling: Bool {
        buffer.count > 1 && Set(buffer.lowercased()).count == 1
    }

    var prefix: String {
        isCycling ? String(buffer.prefix(1)) : buffer
    }

    func reset() { buffer = "" }
}

extension StringProtocol {
    /// Comparaison de prefixe indulgente : casse et accents ignores, comme
    /// dans le Finder ou « e » trouve « Etudes ».
    func matchesTypeSelect(prefix: String) -> Bool {
        guard !prefix.isEmpty else { return false }
        return range(of: prefix, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil
    }
}
