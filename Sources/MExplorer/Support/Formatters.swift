import Foundation

enum Fmt {

    static let byteCount: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = false
        f.includesUnit = true
        return f
    }()

    static let dateTime: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        f.doesRelativeDateFormatting = false
        return f
    }()

    static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    static func size(_ bytes: Int64?) -> String {
        guard let bytes else { return "--" }
        return byteCount.string(fromByteCount: bytes)
    }

    static func date(_ d: Date?) -> String {
        guard let d else { return "--" }
        return dateTime.string(from: d)
    }

    /// Aligne les dates sur la langue de l'interface : sans cela elles
    /// resteraient dans la langue du systeme.
    static func applyLocale(for language: AppLanguage) {
        let locale = Locale(identifier: language.resolved == .french ? "fr_FR" : "en_US")
        dateTime.locale = locale
        dateOnly.locale = locale
        relative.locale = locale
    }

    /// "il y a 3 min", utilise dans le volet de details.
    static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()
}
