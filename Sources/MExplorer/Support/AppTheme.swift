import AppKit

/// Apparence de l'application, independamment de celle du systeme.
enum AppTheme: String, CaseIterable, Identifiable {

    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return L("Theme du systeme")
        case .light: return L("Clair")
        case .dark: return L("Sombre")
        }
    }

    /// `nil` rend la main au systeme : l'application suit alors le reglage
    /// d'apparence de macOS, y compris s'il bascule en cours de journee.
    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    func apply() {
        NSApp.appearance = appearance
    }
}
