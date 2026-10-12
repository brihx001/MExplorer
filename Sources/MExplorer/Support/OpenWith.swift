import AppKit
import UniformTypeIdentifiers

/// Sous-menu "Ouvrir avec" : applications capables d'ouvrir un fichier.
enum OpenWith {

    static func applications(for url: URL) -> [URL] {
        var apps = NSWorkspace.shared.urlsForApplications(toOpen: url)
        if let preferred = NSWorkspace.shared.urlForApplication(toOpen: url),
           let index = apps.firstIndex(of: preferred) {
            apps.remove(at: index)
            apps.insert(preferred, at: 0)
        }
        return Array(apps.prefix(20))
    }

    static func name(of appURL: URL) -> String {
        (try? appURL.resourceValues(forKeys: [.localizedNameKey]).localizedName)
            .map { $0.replacingOccurrences(of: ".app", with: "") }
            ?? appURL.deletingPathExtension().lastPathComponent
    }

    static func chooseApplication(model: WindowModel) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Choisir l'application avec laquelle ouvrir la selection"
        guard panel.runModal() == .OK, let app = panel.url else { return }
        model.openWith(application: app)
    }
}
