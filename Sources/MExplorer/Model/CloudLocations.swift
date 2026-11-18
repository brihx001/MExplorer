import Foundation

/// Les services de stockage en nuage installes sur ce Mac, et l'etat de chaque
/// fichier qui s'y trouve.
///
/// macOS range les services modernes sous `~/Library/CloudStorage`, un dossier
/// par compte, pose par l'extension de fichiers du service : OneDrive, Dropbox,
/// Google Drive, Box, Proton Drive... iCloud Drive garde son emplacement
/// historique. Les clients qui n'utilisent pas ce mecanisme montent un volume
/// (pCloud) ou posent un dossier ordinaire dans le dossier personnel.
enum CloudLocations {

    // MARK: - Fournisseurs

    enum Provider: Equatable {
        case iCloud, oneDrive, dropbox, googleDrive, box, pCloud, protonDrive
        case creativeCloud, mega, nextcloud
        /// Service inconnu : son nom est celui du dossier qu'il a pose.
        case other(String)

        var name: String {
            switch self {
            case .iCloud: return "iCloud Drive"
            case .oneDrive: return "OneDrive"
            case .dropbox: return "Dropbox"
            case .googleDrive: return "Google Drive"
            case .box: return "Box"
            case .pCloud: return "pCloud"
            case .protonDrive: return "Proton Drive"
            case .creativeCloud: return "Creative Cloud"
            case .mega: return "MEGA"
            case .nextcloud: return "Nextcloud"
            case .other(let name): return name
            }
        }

        var symbol: String { self == .iCloud ? "icloud" : "cloud" }

        /// Le nom de dossier que pose une extension de fichiers commence par le
        /// nom du service, suivi du compte : « OneDrive-Contoso »,
        /// « GoogleDrive-moi@exemple.fr », « OneDrive-SharedLibraries-Contoso ».
        static func named(_ folderName: String) -> Provider {
            let head = folderName.split(separator: "-").first.map(String.init) ?? folderName
            switch head.lowercased().replacingOccurrences(of: " ", with: "") {
            case "icloud", "iclouddrive": return .iCloud
            case "onedrive": return .oneDrive
            case "dropbox": return .dropbox
            case "googledrive": return .googleDrive
            case "box": return .box
            case "pcloud", "pclouddrive": return .pCloud
            case "protondrive": return .protonDrive
            case "creativecloudfiles": return .creativeCloud
            case "mega", "megasync": return .mega
            case "nextcloud": return .nextcloud
            default: return .other(head)
            }
        }
    }

    /// La facon dont le service pose ses fichiers sur le Mac, d'ou se deduit
    /// l'etat de chacun.
    enum Storage {
        /// Extension de fichiers : macOS tient l'etat de chaque fichier, et le
        /// noyau marque d'un drapeau ceux qui restent en ligne.
        case fileProvider
        /// Volume monte par le client, qui diffuse les fichiers a la demande :
        /// rien n'occupe le disque du Mac.
        case streamed
        /// Dossier ordinaire que le client recopie : tout est sur le disque.
        case synced
    }

    /// Une racine de service : le dossier par lequel on entre dans le nuage.
    struct Root {
        let url: URL
        let provider: Provider
        /// Libelle montre dans la barre laterale.
        let title: String
        let storage: Storage
        /// Chemin standardise, garde pour la comparaison de prefixe.
        let path: String

        init(url: URL, provider: Provider, title: String, storage: Storage) {
            self.url = url
            self.provider = provider
            self.title = title
            self.storage = storage
            self.path = url.standardizedFileURL.path
        }
    }

    // MARK: - Etat d'un element

    enum State {
        /// Une copie locale existe : le fichier s'ouvre hors connexion.
        case downloaded
        /// Seul un substitut est pose sur le disque ; l'ouvrir declenche le
        /// telechargement.
        case inCloud
        /// Le service ne publie pas d'etat par fichier.
        case unknown
    }

    struct Status {
        let provider: Provider
        let state: State

        /// Libelle court, pour la colonne de la vue Details.
        var text: String {
            switch state {
            case .downloaded: return L("Telecharge")
            case .inCloud: return L("Dans le nuage")
            case .unknown: return provider.name
            }
        }

        /// Libelle complet, pour le volet de details et la fenetre d'infos.
        var detailedText: String {
            switch state {
            case .unknown: return provider.name
            default: return "\(provider.name) - \(text)"
            }
        }
    }

    /// Etat de l'element, ou nil s'il ne se trouve dans aucun nuage.
    ///
    /// L'etat vient du drapeau `SF_DATALESS`, que le noyau pose sur un
    /// substitut sans donnees. Les cles `isUbiquitousItem` et
    /// `ubiquitousItemDownloadingStatus` disent la meme chose, mais passent par
    /// le service de fichiers : mesure sur un dossier OneDrive de 123 elements,
    /// 414 ms contre 1,1 ms pour autant de `lstat`, soit 3,4 ms par ligne
    /// dessinee. Sur 400 fichiers iCloud, les deux sources se sont accordees
    /// sans exception.
    static func status(for url: URL, isDirectory: Bool,
                       attributes: @autoclosure () -> UnixAttributes?) -> Status? {
        guard let root = root(containing: url) else { return nil }
        // Le noyau ne pose le drapeau que sur les fichiers : un dossier dont
        // tout le contenu est en ligne ressemble a n'importe quel autre.
        // Annoncer « telecharge » serait faux, on s'en tient au service.
        guard !isDirectory else { return Status(provider: root.provider, state: .unknown) }
        switch root.storage {
        case .fileProvider:
            let isPlaceholder = attributes()?.isDataless ?? false
            return Status(provider: root.provider, state: isPlaceholder ? .inCloud : .downloaded)
        case .streamed:
            // Le client monte un volume reseau : le fichier n'est pas sur le
            // disque du Mac, quoi qu'en dise sa taille.
            return Status(provider: root.provider, state: .inCloud)
        case .synced:
            return Status(provider: root.provider, state: .downloaded)
        }
    }

    /// Racine qui contient cet element, le cas echeant.
    static func root(containing url: URL) -> Root? {
        guard !roots.isEmpty else { return nil }
        let path = url.standardizedFileURL.path
        return roots.first { root in
            path == root.path || path.hasPrefix(root.path + "/")
        }
    }

    // MARK: - Inventaire

    /// Racines connues. Lue sur le thread principal, remplacee par `refresh`.
    private(set) static var roots: [Root] = []

    /// Numero de version de l'inventaire. La recherche se fait en tache de
    /// fond : au lancement, le dossier affiche est dessine avant qu'elle
    /// n'aboutisse, et les elements qui ont deja retenu leur etat doivent le
    /// recalculer plutot que de rester sur un « hors du nuage » premature.
    private(set) static var generation = 0

    static let changed = Notification.Name("com.jerome.mexplorer.cloudLocationsChanged")

    /// Recharge l'inventaire hors du thread principal puis notifie.
    ///
    /// La lecture coute une vingtaine de millisecondes : elle interroge le
    /// service de fichiers pour chaque dossier de `~/Library/CloudStorage`.
    static func refresh() {
        DispatchQueue.global(qos: .utility).async {
            let found = discover()
            DispatchQueue.main.async {
                let changedList = found.map(\.path) != roots.map(\.path)
                roots = found
                if changedList {
                    generation &+= 1
                    NotificationCenter.default.post(name: changed, object: nil)
                }
            }
        }
    }

    private static func discover() -> [Root] {
        var result: [Root] = []
        let fm = FileManager.default

        if let icloud = SidebarCatalog.iCloudDrive {
            result.append(Root(url: icloud, provider: .iCloud,
                               title: L("iCloud Drive"), storage: .fileProvider))
        }

        // Les services modernes. Un dossier laisse par une installation
        // precedente reste sur le disque sans etre rattache a quoi que ce soit :
        // il ne porte plus le drapeau d'element distant, et n'a donc pas sa
        // place ici. Il reste visible dans l'arborescence, a sa place reelle.
        let storage = SidebarCatalog.home.appendingPathComponent("Library/CloudStorage", isDirectory: true)
        let keys: [URLResourceKey] = [.isDirectoryKey, .isUbiquitousItemKey]
        let entries = (try? fm.contentsOfDirectory(at: storage,
                                                   includingPropertiesForKeys: keys,
                                                   options: [.skipsHiddenFiles])) ?? []
        for url in entries.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isDirectory == true, values?.isUbiquitousItem == true else { continue }
            let name = url.lastPathComponent
            result.append(Root(url: url, provider: .named(name), title: name,
                               storage: .fileProvider))
        }

        // Les clients restes a l'ecart de ce mecanisme : un volume monte dans
        // le dossier personnel, ou un dossier ordinaire que le client
        // synchronise. Le type de systeme de fichiers tranche pour les
        // premiers, le nom pour les seconds.
        let homeEntries = (try? fm.contentsOfDirectory(at: SidebarCatalog.home,
                                                       includingPropertiesForKeys: [.isDirectoryKey],
                                                       options: [.skipsHiddenFiles])) ?? []
        for url in homeEntries.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            let name = url.lastPathComponent
            var storage = Storage.streamed
            var provider = mountedProvider(at: url)
            if provider == nil {
                storage = .synced
                provider = knownFolderProvider(named: name)
            }
            guard let provider else { continue }
            guard !result.contains(where: { $0.path == url.standardizedFileURL.path }) else { continue }
            result.append(Root(url: url, provider: provider, title: name, storage: storage))
        }

        return result
    }

    /// Systemes de fichiers poses par un client de stockage en nuage, qui
    /// diffuse les fichiers a la demande au lieu de les copier.
    private static let cloudFilesystems: Set<String> = ["pcloudfs"]

    private static func mountedProvider(at url: URL) -> Provider? {
        var info = statfs()
        guard statfs(url.path, &info) == 0 else { return nil }
        let type = withUnsafeBytes(of: info.f_fstypename) { raw in
            String(cString: raw.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
        guard cloudFilesystems.contains(type.lowercased()) else { return nil }
        return type.lowercased() == "pcloudfs" ? .pCloud : .other(type)
    }

    /// Dossiers de synchronisation poses dans le dossier personnel. La liste
    /// est volontairement courte : un dossier nomme au hasard ne doit pas se
    /// retrouver dans la section Nuage.
    private static func knownFolderProvider(named name: String) -> Provider? {
        switch name.lowercased() {
        case "pcloud drive": return .pCloud
        case "dropbox": return .dropbox
        case "google drive", "googledrive": return .googleDrive
        case "mega", "megasync": return .mega
        case "nextcloud": return .nextcloud
        default:
            if name.hasPrefix("Creative Cloud Files") { return .creativeCloud }
            return nil
        }
    }
}
