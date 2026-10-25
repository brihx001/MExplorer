import Foundation

/// Regles de renommage par lot, et leur application.
///
/// Le calcul est separe de l'interface pour que l'apercu montre exactement ce
/// que le renommage fera : une seule fonction produit les deux.
enum BatchRename {

    enum Mode: String, CaseIterable, Identifiable {
        case replace, addText, numbering, caseChange

        var id: String { rawValue }

        var title: String {
            switch self {
            case .replace: return L("Remplacer du texte")
            case .addText: return L("Ajouter du texte")
            case .numbering: return L("Numeroter")
            case .caseChange: return L("Changer la casse")
            }
        }
    }

    enum Position: String, CaseIterable, Identifiable {
        case prefix, suffix
        var id: String { rawValue }
        var title: String {
            switch self {
            case .prefix: return L("Au debut")
            case .suffix: return L("A la fin")
            }
        }
    }

    enum Casing: String, CaseIterable, Identifiable {
        case lower, upper, capitalized
        var id: String { rawValue }
        var title: String {
            switch self {
            case .lower: return L("minuscules")
            case .upper: return L("MAJUSCULES")
            case .capitalized: return L("Initiales Majuscules")
            }
        }
    }

    struct Rules {
        var mode: Mode = .replace
        var search = ""
        var replacement = ""
        var text = ""
        var position: Position = .prefix
        var baseName = ""
        var start = 1
        var digits = 2
        var casing: Casing = .lower
        /// L'extension est laissee tranquille par defaut : la changer casse
        /// l'association de l'application qui ouvre le fichier.
        var includeExtension = false
    }

    struct Proposal: Identifiable {
        let id = UUID()
        let url: URL
        let newName: String
        /// Vrai si le nom propose entre en collision, dans le lot ou sur le disque.
        var conflict = false
        var unchanged: Bool { newName == url.lastPathComponent }
    }

    /// Noms proposes pour cette selection, dans l'ordre donne.
    static func apply(_ rules: Rules, to urls: [URL]) -> [Proposal] {
        var proposals: [Proposal] = []
        for (index, url) in urls.enumerated() {
            let full = url.lastPathComponent
            let ext = url.pathExtension
            let stem = url.deletingPathExtension().lastPathComponent
            let subject = rules.includeExtension ? full : stem
            let transformed = transform(subject, rules: rules, index: index)
            var name = transformed
            if !rules.includeExtension, !ext.isEmpty { name += "." + ext }
            name = sanitize(name, fallback: full)
            proposals.append(Proposal(url: url, newName: name))
        }
        return flagConflicts(proposals)
    }

    private static func transform(_ subject: String, rules: Rules, index: Int) -> String {
        switch rules.mode {
        case .replace:
            guard !rules.search.isEmpty else { return subject }
            return subject.replacingOccurrences(of: rules.search, with: rules.replacement,
                                                options: [.caseInsensitive])
        case .addText:
            guard !rules.text.isEmpty else { return subject }
            return rules.position == .prefix ? rules.text + subject : subject + rules.text
        case .numbering:
            let number = String(format: "%0\(max(rules.digits, 1))d", rules.start + index)
            let base = rules.baseName.isEmpty ? subject : rules.baseName
            return base + " " + number
        case .caseChange:
            switch rules.casing {
            case .lower: return subject.lowercased()
            case .upper: return subject.uppercased()
            case .capitalized: return subject.capitalized
            }
        }
    }

    /// Un nom de fichier ne peut contenir ni « / » ni octet nul, et ne peut
    /// etre vide. Un reglage absurde rend le nom d'origine plutot qu'une erreur.
    private static func sanitize(_ name: String, fallback: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? fallback : cleaned
    }

    /// Signale les collisions : deux fichiers qui prendraient le meme nom, ou
    /// un nom deja pris sur le disque par un element etranger au lot.
    private static func flagConflicts(_ proposals: [Proposal]) -> [Proposal] {
        var counts: [String: Int] = [:]
        for proposal in proposals {
            let key = proposal.url.deletingLastPathComponent().path + "/" + proposal.newName.lowercased()
            counts[key, default: 0] += 1
        }
        let renamed = Set(proposals.map { $0.url.standardizedFileURL.path })
        let fm = FileManager.default

        return proposals.map { proposal in
            var flagged = proposal
            guard !proposal.unchanged else { return flagged }
            let folder = proposal.url.deletingLastPathComponent()
            let key = folder.path + "/" + proposal.newName.lowercased()
            if counts[key, default: 0] > 1 { flagged.conflict = true; return flagged }
            let target = folder.appendingPathComponent(proposal.newName)
            if fm.fileExists(atPath: target.path),
               !renamed.contains(target.standardizedFileURL.path) {
                flagged.conflict = true
            }
            return flagged
        }
    }
}
