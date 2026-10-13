import Foundation

struct GroupSection {
    let key: String
    let title: String
    let count: Int
    let order: Int
}

enum ListRow {
    case group(GroupSection)
    case item(FileItem)

    var item: FileItem? { if case .item(let i) = self { return i }; return nil }
    var group: GroupSection? { if case .group(let g) = self { return g }; return nil }
}

enum Arranger {

    // MARK: - Tri

    static func sort(_ items: [FileItem], settings: FolderViewSettings) -> [FileItem] {
        let asc = settings.ascending
        // Un tri par date melange dossiers et fichiers : regrouper les dossiers
        // en tete masquerait justement ce que l'on cherche a voir.
        let foldersFirst = settings.foldersFirst && !settings.sortKey.ignoresFolderGrouping
        return items.sorted { a, b in
            if foldersFirst && a.isNavigableContainer != b.isNavigableContainer {
                return a.isNavigableContainer
            }
            let r = compare(a, b, key: settings.sortKey)
            if r == .orderedSame {
                return a.displayName.localizedStandardCompare(b.displayName) == .orderedAscending
            }
            return asc ? r == .orderedAscending : r == .orderedDescending
        }
    }

    private static func compare(_ a: FileItem, _ b: FileItem, key: SortKey) -> ComparisonResult {
        switch key {
        case .name:
            return a.displayName.localizedStandardCompare(b.displayName)
        case .kind:
            return a.kindDescription.localizedStandardCompare(b.kindDescription)
        case .fileExtension:
            return a.fileExtension.localizedStandardCompare(b.fileExtension)
        case .size:
            return num(a.effectiveSize ?? -1, b.effectiveSize ?? -1)
        case .dateModified:
            return date(a.modificationDate, b.modificationDate)
        case .dateCreated:
            return date(a.creationDate, b.creationDate)
        case .dateAdded:
            return date(a.addedDate, b.addedDate)
        case .tags:
            return (a.tagNames.first ?? "").localizedStandardCompare(b.tagNames.first ?? "")
        }
    }

    private static func num(_ a: Int64, _ b: Int64) -> ComparisonResult {
        a == b ? .orderedSame : (a < b ? .orderedAscending : .orderedDescending)
    }

    private static func date(_ a: Date?, _ b: Date?) -> ComparisonResult {
        switch (a, b) {
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedAscending
        case (_, nil): return .orderedDescending
        case let (x?, y?): return x == y ? .orderedSame : (x < y ? .orderedAscending : .orderedDescending)
        }
    }

    // MARK: - Regroupement

    static func rows(from items: [FileItem],
                     settings: FolderViewSettings,
                     collapsedGroups: Set<String>) -> [ListRow] {
        let sorted = sort(items, settings: settings)
        guard settings.groupKey != .none else { return sorted.map { .item($0) } }

        var buckets: [String: (title: String, order: Int, items: [FileItem])] = [:]
        for item in sorted {
            let b = bucket(item, key: settings.groupKey)
            buckets[b.key, default: (b.title, b.order, [])].items.append(item)
        }
        let ordered = buckets.sorted { lhs, rhs in
            if lhs.value.order != rhs.value.order { return lhs.value.order < rhs.value.order }
            return lhs.value.title.localizedStandardCompare(rhs.value.title) == .orderedAscending
        }
        var rows: [ListRow] = []
        for (key, value) in ordered {
            rows.append(.group(GroupSection(key: key, title: value.title,
                                            count: value.items.count, order: value.order)))
            if !collapsedGroups.contains(key) {
                rows.append(contentsOf: value.items.map { ListRow.item($0) })
            }
        }
        return rows
    }

    private static func bucket(_ item: FileItem, key: GroupKey) -> (key: String, title: String, order: Int) {
        switch key {
        case .none:
            return ("", "", 0)

        case .name:
            let first = item.displayName.first.map { String($0).uppercased() } ?? "#"
            if first.range(of: "[A-Z]", options: .regularExpression) != nil {
                return (first, first, Int(first.unicodeScalars.first!.value))
            }
            if first.range(of: "[0-9]", options: .regularExpression) != nil {
                return ("0-9", "0 - 9", 1)
            }
            return ("#", "Autres", 9999)

        case .kind:
            if item.isNavigableContainer { return ("__folder", L("Dossier de fichiers"), 0) }
            let k = item.kindDescription
            return (k, k, 1)

        case .tags:
            guard let tag = item.tagNames.first else { return ("__none", L("Sans tag"), 9999) }
            return (tag, tag, 0)

        case .size:
            guard let size = item.effectiveSize, !item.isNavigableContainer else {
                return ("__folder", L("Dossiers"), 0)
            }
            switch size {
            case 0:                     return ("s0", L("Vide (0 octet)"), 1)
            case 1..<16_384:            return ("s1", L("Minuscule (0 - 16 Ko)"), 2)
            case 16_384..<1_048_576:    return ("s2", L("Petit (16 Ko - 1 Mo)"), 3)
            case 1_048_576..<134_217_728: return ("s3", L("Moyen (1 - 128 Mo)"), 4)
            case 134_217_728..<1_073_741_824: return ("s4", L("Grand (128 Mo - 1 Go)"), 5)
            case 1_073_741_824..<4_294_967_296: return ("s5", L("Enorme (1 - 4 Go)"), 6)
            default:                    return ("s6", L("Gigantesque (> 4 Go)"), 7)
            }

        case .dateModified:
            guard let d = item.modificationDate else { return ("__unknown", L("Date inconnue"), 9999) }
            let cal = Calendar.current
            let now = Date()
            if cal.isDateInToday(d) { return ("d0", L("Aujourd'hui"), 0) }
            if cal.isDateInYesterday(d) { return ("d1", L("Hier"), 1) }
            let days = cal.dateComponents([.day], from: d, to: now).day ?? 0
            if days < 7 { return ("d2", L("La semaine derniere"), 2) }
            if days < 14 { return ("d3", L("Il y a deux semaines"), 3) }
            if days < 31 { return ("d4", L("Le mois dernier"), 4) }
            if days < 366 { return ("d5", L("Cette annee"), 5) }
            let year = cal.component(.year, from: d)
            return ("y\(year)", "\(year)", 6000 - year)
        }
    }
}
