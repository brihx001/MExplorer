import AppKit

enum SidebarCatalog {

    // MARK: - Dossiers standards

    /// Sous sandbox, `homeDirectoryForCurrentUser` renvoie le conteneur de l'app.
    /// Le vrai dossier personnel se lit dans la base des utilisateurs.
    static let home: URL = {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            let path = String(cString: dir)
            if !path.isEmpty { return URL(fileURLWithPath: path, isDirectory: true) }
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }()

    /// Conteneur sandbox de l'application (toujours accessible sans autorisation).
    static var appContainer: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// Les API `urls(for:in:)` pointent aussi vers le conteneur : on compose
    /// les chemins a partir du vrai dossier personnel.
    static func standardDirectory(_ d: FileManager.SearchPathDirectory) -> URL? {
        let name: String
        switch d {
        case .desktopDirectory: name = "Desktop"
        case .downloadsDirectory: name = "Downloads"
        case .documentDirectory: name = "Documents"
        case .picturesDirectory: name = "Pictures"
        case .musicDirectory: name = "Music"
        case .moviesDirectory: name = "Movies"
        case .libraryDirectory: name = "Library"
        case .applicationDirectory: return applications
        default: return FileManager.default.urls(for: d, in: .userDomainMask).first
        }
        return home.appendingPathComponent(name, isDirectory: true)
    }

    /// Dossiers "Acces rapide" par defaut, dans l'ordre de Windows 11.
    static var quickAccessDefaults: [URL] {
        var urls: [URL] = [home, applications]
        for d: FileManager.SearchPathDirectory in [.desktopDirectory, .downloadsDirectory,
                                                   .documentDirectory, .picturesDirectory,
                                                   .musicDirectory, .moviesDirectory] {
            if let u = standardDirectory(d) { urls.append(u) }
        }
        return urls
    }

    static var applications: URL { URL(fileURLWithPath: "/Applications", isDirectory: true) }

    static var iCloudDrive: URL? {
        let u = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    static var trash: URL? {
        home.appendingPathComponent(".Trash", isDirectory: true)
    }

    // MARK: - Volumes

    /// Clefs volontairement minimales : demander `tagNames` ici declenche une
    /// lecture d'attributs etendus sur chaque volume, ce qui bloque le thread
    /// principal des qu'un volume est lent (partage reseau, conteneur...).
    private static let volumeKeys: [URLResourceKey] = [
        .localizedNameKey, .volumeNameKey, .isDirectoryKey, .isVolumeKey,
        .volumeIsRemovableKey, .volumeIsEjectableKey,
        .volumeTotalCapacityKey, .volumeAvailableCapacityKey
    ]

    /// Dernier inventaire connu, mis a jour en tache de fond.
    private(set) static var cachedVolumes: [FileItem] = []

    static func mountedVolumes() -> [FileItem] { cachedVolumes }

    /// Recharge l'inventaire hors du thread principal puis notifie.
    static func refreshVolumes(completion: (([FileItem]) -> Void)? = nil) {
        DispatchQueue.global(qos: .utility).async {
            let urls = FileManager.default.mountedVolumeURLs(
                includingResourceValuesForKeys: volumeKeys,
                options: [.skipHiddenVolumes]
            ) ?? []
            let keys = Set(volumeKeys)
            let items = urls.map { url in
                FileItem(url: url, values: try? url.resourceValues(forKeys: keys))
            }
            DispatchQueue.main.async {
                cachedVolumes = items
                completion?(items)
                NotificationCenter.default.post(name: volumesChanged, object: nil)
            }
        }
    }

    static let volumesChanged = Notification.Name("com.jerome.mexplorer.volumesChanged")

    /// Vrai si le volume peut etre ejecte (support amovible, disque externe).
    ///
    /// Les cles DiskArbitration (`volumeIsEjectable`, `volumeIsRemovable`,
    /// `volumeIsInternal`) reviennent parfois toutes nil : c'est le cas d'un
    /// disque USB en exFAT lu depuis le bac a sable. On retombe alors sur la
    /// seule information fiable : un volume monte dans /Volumes qui n'est pas
    /// le disque de demarrage est ejectable.
    static func isEjectable(_ url: URL) -> Bool {
        guard url.resolvingSymlinksInPath().path != "/" else { return false }
        let v = try? url.resourceValues(forKeys: [.volumeIsEjectableKey,
                                                  .volumeIsRemovableKey,
                                                  .volumeIsInternalKey])
        if v?.volumeIsEjectable == true || v?.volumeIsRemovable == true { return true }
        if v?.volumeIsInternal == false { return true }
        if v?.volumeIsEjectable == nil, v?.volumeIsRemovable == nil, v?.volumeIsInternal == nil {
            return url.standardizedFileURL.path.hasPrefix("/Volumes/")
        }
        return false
    }

    // MARK: - Icones

    static func symbol(for url: URL) -> String {
        let path = url.standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        if path == home { return "house" }
        if path == "/" { return "internaldrive" }
        if path == "/Applications" { return "square.stack.3d.up" }
        if path.hasPrefix("/Volumes/") && url.pathComponents.count == 3 { return "externaldrive" }
        if path.contains("com~apple~CloudDocs") { return "icloud" }
        if path.hasSuffix("/.Trash") { return "trash" }

        switch url.lastPathComponent {
        case "Desktop", "Bureau": return "menubar.dock.rectangle"
        case "Documents": return "doc"
        case "Downloads", "Telechargements": return "arrow.down.circle"
        case "Pictures", "Images": return "photo"
        case "Music", "Musique": return "music.note"
        case "Movies", "Films": return "film"
        case "Public": return "person.2"
        case "Library", "Bibliotheque": return "building.columns"
        default: return "folder"
        }
    }

    // MARK: - Tags

    /// Les sept tags systeme, dans l'ordre des labels macOS.
    static let systemTags: [(name: String, color: NSColor)] = [
        ("Rouge", .systemRed), ("Orange", .systemOrange), ("Jaune", .systemYellow),
        ("Vert", .systemGreen), ("Bleu", .systemBlue), ("Violet", .systemPurple),
        ("Gris", .systemGray)
    ]

    static func color(forTag name: String) -> NSColor? {
        systemTags.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.color
    }
}
