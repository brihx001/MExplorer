import AppKit

/// Ouverture d'un dossier dans un emulateur de terminal.
///
/// Le bac a sable n'interdit pas de lancer une autre application : la demande
/// part a LaunchServices, et le terminal s'ouvre avec ses propres droits. Ce
/// qu'il verra du disque depend de ses autorisations, pas des notres.
enum TerminalLauncher {

    struct App {
        let name: String
        let url: URL
    }

    /// Terminaux installes, Terminal.app en tete.
    ///
    /// La liste est relue a chaque ouverture de menu : installer iTerm pendant
    /// la session doit suffire a le voir apparaitre.
    static var installed: [App] {
        let candidates: [(String, String)] = [
            ("com.apple.Terminal", L("Terminal")),
            ("com.googlecode.iterm2", "iTerm"),
            ("dev.warp.Warp-Stable", "Warp"),
            ("co.zeit.hyper", "Hyper"),
            ("net.kovidgoyal.kitty", "kitty"),
            ("com.github.wez.wezterm", "WezTerm"),
            ("com.mitchellh.ghostty", "Ghostty")
        ]
        return candidates.compactMap { bundleID, name in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
            return App(name: name, url: url)
        }
    }

    static func open(_ folder: URL, with app: App, completion: @escaping (Error?) -> Void) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([folder], withApplicationAt: app.url,
                                configuration: configuration) { _, error in
            DispatchQueue.main.async { completion(error) }
        }
    }
}
