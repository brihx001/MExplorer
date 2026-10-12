import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// Cache d'icones a deux niveaux :
///  - icones generiques par type (tres bon marche, partagees entre milliers de fichiers)
///  - icones/vignettes specifiques par chemin (applications, images, PDF...)
final class IconCache {

    static let shared = IconCache()

    private let generic = NSCache<NSString, NSImage>()
    private let specific = NSCache<NSString, NSImage>()
    private let thumbnails = NSCache<NSString, NSImage>()
    private var inFlight = Set<String>()
    private let generator = QLThumbnailGenerator.shared

    private init() {
        generic.countLimit = 400
        specific.countLimit = 2000
        thumbnails.countLimit = 1500
    }

    // MARK: - Icone immediate, jamais bloquante

    /// Poste quand des icones specifiques ont ete resolues en arriere-plan.
    static let changed = Notification.Name("com.jerome.mexplorer.iconsDidChange")

    private let resolveQueue = DispatchQueue(label: "com.jerome.mexplorer.icons", qos: .utility)
    private var resolving = Set<String>()
    private var flush: DispatchWorkItem?

    /// Icone a afficher tout de suite.
    ///
    /// `NSWorkspace.icon(forFile:)` interroge LaunchServices et peut bloquer
    /// plusieurs secondes sur un paquet protege par TCC : elle ne doit jamais
    /// etre appelee pendant le dessin d'une cellule. On rend l'icone generique
    /// du type, puis on resout l'icone specifique en arriere-plan.
    func icon(for item: FileItem) -> NSImage {
        guard needsSpecificIcon(item) else { return genericIcon(for: item) }
        let path = item.url.path
        if let cached = specific.object(forKey: path as NSString) { return cached }
        scheduleSpecificResolution(path: path)
        return genericIcon(for: item)
    }

    /// Variante pour les elements ponctuels (dossier courant, application).
    func icon(forFileAt url: URL, fallbackIsDirectory: Bool = true) -> NSImage {
        let path = url.path
        if let cached = specific.object(forKey: path as NSString) { return cached }
        scheduleSpecificResolution(path: path)
        let type: UTType = fallbackIsDirectory ? .folder : .data
        return genericIcon(forTypeIdentifier: type.identifier, fallback: type)
    }

    private func needsSpecificIcon(_ item: FileItem) -> Bool {
        item.isApplication || item.isVolume || item.isSymbolicLink || item.isAliasFile || item.isPackage
    }

    private func genericIcon(for item: FileItem) -> NSImage {
        if item.isDirectory && !item.isPackage {
            return genericIcon(forTypeIdentifier: "public.folder", fallback: .folder)
        }
        let identifier = item.contentType?.identifier ?? (item.isDirectory ? "public.folder" : "public.data")
        return genericIcon(forTypeIdentifier: identifier, fallback: item.isDirectory ? .folder : .data)
    }

    private func genericIcon(forTypeIdentifier identifier: String, fallback: UTType) -> NSImage {
        if let cached = generic.object(forKey: identifier as NSString) { return cached }
        let image = NSWorkspace.shared.icon(for: UTType(identifier) ?? fallback)
        image.size = NSSize(width: 32, height: 32)
        generic.setObject(image, forKey: identifier as NSString)
        return image
    }

    private func scheduleSpecificResolution(path: String) {
        guard !resolving.contains(path) else { return }
        resolving.insert(path)
        resolveQueue.async { [weak self] in
            let image = NSWorkspace.shared.icon(forFile: path)
            image.size = NSSize(width: 32, height: 32)
            DispatchQueue.main.async {
                guard let self else { return }
                self.resolving.remove(path)
                self.specific.setObject(image, forKey: path as NSString)
                self.scheduleNotification()
            }
        }
    }

    /// Les resolutions arrivent par paquets : un seul rafraichissement suffit.
    private func scheduleNotification() {
        flush?.cancel()
        let work = DispatchWorkItem { NotificationCenter.default.post(name: Self.changed, object: nil) }
        flush = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    // MARK: - Vignettes Quick Look

    private struct ThumbRequest {
        let url: URL
        let side: CGFloat
        let scale: CGFloat
        let key: String
    }

    /// QLThumbnailGenerator abandonne silencieusement les requetes au-dela de
    /// quelques demandes simultanees : mesure faite sur un dossier de 22 images,
    /// 4 rappels seulement. On serialise donc nous-memes, avec un chien de garde
    /// pour ne jamais bloquer la file sur une requete perdue.
    private static let maxConcurrentThumbnails = 4

    private var thumbQueue: [ThumbRequest] = []
    private var thumbActive: Set<String> = []
    private var thumbQueued: Set<String> = []

    func cachedThumbnail(for url: URL, side: CGFloat) -> NSImage? {
        thumbnails.object(forKey: thumbKey(url, side) as NSString)
    }

    /// Demande une vignette. `completion` n'est appele que si une vignette a pu
    /// etre produite ; la vue est de toute facon prevenue via `IconCache.changed`.
    func thumbnail(for url: URL, side: CGFloat, scale: CGFloat, completion: @escaping (NSImage) -> Void) {
        let key = thumbKey(url, side)
        if let cached = thumbnails.object(forKey: key as NSString) {
            completion(cached)
            return
        }
        guard !thumbActive.contains(key), !thumbQueued.contains(key) else { return }
        thumbQueued.insert(key)
        thumbQueue.append(ThumbRequest(url: url, side: side, scale: scale, key: key))
        pumpThumbnails()
    }

    /// Vide la file d'attente (changement de dossier) ; les requetes deja
    /// lancees se terminent normalement.
    func cancelPendingThumbnails() {
        thumbQueued.removeAll()
        thumbQueue.removeAll()
    }

    private func pumpThumbnails() {
        while thumbActive.count < Self.maxConcurrentThumbnails, !thumbQueue.isEmpty {
            let next = thumbQueue.removeFirst()
            thumbQueued.remove(next.key)
            start(next)
        }
    }

    private func start(_ request: ThumbRequest) {
        thumbActive.insert(request.key)
        var settled = false

        let finish: (NSImage?) -> Void = { [weak self] image in
            guard let self, !settled else { return }
            settled = true
            self.thumbActive.remove(request.key)
            if let image {
                self.thumbnails.setObject(image, forKey: request.key as NSString)
                self.scheduleNotification()
            }
            self.pumpThumbnails()
        }

        let qlRequest = QLThumbnailGenerator.Request(
            fileAt: request.url,
            size: CGSize(width: request.side, height: request.side),
            scale: request.scale,
            representationTypes: [.thumbnail, .lowQualityThumbnail]
        )
        generator.generateBestRepresentation(for: qlRequest) { rep, _ in
            DispatchQueue.main.async {
                finish(rep.map { NSImage(cgImage: $0.cgImage, size: $0.contentRect.size) })
            }
        }

        // Chien de garde : sans lui, une requete perdue bloquerait la file.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { finish(nil) }
    }

    func invalidate(path: String) {
        specific.removeObject(forKey: path as NSString)
        for side in [16, 32, 48, 64, 96, 128, 256] as [CGFloat] {
            thumbnails.removeObject(forKey: thumbKey(URL(fileURLWithPath: path), side) as NSString)
        }
    }

    private func thumbKey(_ url: URL, _ side: CGFloat) -> String {
        "\(Int(side))|\(url.path)"
    }
}
