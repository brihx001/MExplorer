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

    /// Application actuellement associee a ce fichier, pour cocher l'entree
    /// correspondante dans le sous-menu.
    static func defaultApplication(for url: URL) -> URL? {
        NSWorkspace.shared.urlForApplication(toOpen: url)
    }

    /// Associe durablement cette application au type du fichier.
    ///
    /// L'association porte sur le type de contenu, pas sur ce fichier precis :
    /// c'est ainsi que le Finder l'entend avec « Tout modifier ». Le reglage
    /// est enregistre par LaunchServices, hors du bac a sable de MExplorer, et
    /// vaut donc pour toutes les applications.
    static func setDefault(application: URL, for url: URL, completion: @escaping (Error?) -> Void) {
        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            completion(NSError(domain: "MExplorer", code: 18, userInfo: [
                NSLocalizedDescriptionKey: L("Le type de ce fichier n'a pas pu etre determine.")
            ]))
            return
        }
        NSWorkspace.shared.setDefaultApplication(at: application, toOpen: type) { error in
            DispatchQueue.main.async { completion(error) }
        }
    }

    static func chooseApplication(model: WindowModel) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = L("Choisir l'application avec laquelle ouvrir la selection")
        guard panel.runModal() == .OK, let app = panel.url else { return }
        model.openWith(application: app)
    }
}
