import Foundation

/// Occupation d'un volume, pour la jauge de la barre d'etat.
struct VolumeUsage: Equatable {

    let name: String
    let total: Int64
    /// Espace reellement disponible pour l'utilisateur, purgeable compris :
    /// c'est le chiffre qu'annonce le Finder.
    let available: Int64

    var used: Int64 { max(0, total - available) }

    /// Part occupee, entre 0 et 1.
    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(max(Double(used) / Double(total), 0), 1)
    }

    var percentText: String {
        "\(Int((fraction * 100).rounded())) %"
    }

    var summary: String {
        "\(name) : \(Fmt.size(used)) utilises sur \(Fmt.size(total)) (\(percentText))"
    }

    /// Lecture bloquante : a appeler hors du thread principal.
    static func read(for url: URL) -> VolumeUsage? {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey, .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity, total > 0 else { return nil }

        // Sur les volumes non APFS/HFS+ (exFAT, FAT32, NTFS, partages reseau),
        // volumeAvailableCapacityForImportantUsage renvoie 0 et non nil : on ne
        // peut donc pas se contenter d'un repli sur l'absence de valeur.
        let important = Int64(values.volumeAvailableCapacityForImportantUsage ?? 0)
        let plain = Int64(values.volumeAvailableCapacity ?? 0)
        let available = min(Int64(total), max(important, plain))

        return VolumeUsage(name: values.volumeName ?? "Disque",
                           total: Int64(total),
                           available: available)
    }
}
