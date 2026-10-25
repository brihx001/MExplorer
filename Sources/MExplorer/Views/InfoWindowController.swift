import AppKit
import SwiftUI

/// Fenetre "Proprietes" / "Lire les informations".
final class InfoWindowController: NSWindowController {

    private static var open: [String: InfoWindowController] = [:]

    static func show(for urls: [URL], model: WindowModel) {
        guard !urls.isEmpty else { return }
        let key = urls.map(\.path).joined(separator: "|")
        if let existing = open[key] {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = InfoWindowController(urls: urls, model: model, key: key)
        open[key] = controller
        controller.showWindow(nil)
    }

    private let key: String

    private init(urls: [URL], model: WindowModel, key: String) {
        self.key = key
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = urls.count == 1 ? L("%@ - Infos", urls[0].lastPathComponent) : L("%d elements - Infos", urls.count)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: InfoView(urls: urls, model: model))
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supporte") }
}

extension InfoWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        InfoWindowController.clear(key: key)
    }
    fileprivate static func clear(key: String) { open.removeValue(forKey: key) }
}

private struct InfoView: View {

    let urls: [URL]
    let model: WindowModel

    @State private var items: [FileItem] = []
    @State private var totalSize: Int64?
    @State private var newName: String = ""
    @State private var tagsText: String = ""
    @State private var permissions: PosixPermissions?
    @State private var permissionsError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                Divider()
                generalSection
                if let single = items.first, items.count == 1 {
                    Divider()
                    nameSection(single)
                    Divider()
                    tagsSection
                    Divider()
                    permissionsSection(single)
                    if !single.isNavigableContainer {
                        Divider()
                        openWithSection(single)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear(perform: load)
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let first = items.first {
                Image(nsImage: IconCache.shared.icon(for: first))
                    .resizable()
                    .frame(width: 56, height: 56)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(items.count == 1 ? (items.first?.displayName ?? "") : "\(items.count) elements")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)
                Text(items.count == 1 ? (items.first?.kindDescription ?? "") : "Selection multiple")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(L("General"))
            infoRow(L("Taille"), totalSize.map { Fmt.size($0) } ?? L("Calcul en cours..."))
            if items.count == 1, let item = items.first {
                infoRow(L("Emplacement"), item.url.deletingLastPathComponent().path)
                infoRow(L("Cree le"), Fmt.date(item.creationDate))
                infoRow(L("Modifie le"), Fmt.date(item.modificationDate))
                if let added = item.addedDate { infoRow(L("Ajoute le"), Fmt.date(added)) }
                if !item.fileExtension.isEmpty { infoRow(L("Extension"), item.fileExtension) }
                if let type = item.contentType { infoRow(L("Type UTI"), type.identifier) }
            }
        }
    }

    private func nameSection(_ item: FileItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(L("Nom et extension"))
            HStack {
                TextField(L("Nom"), text: $newName)
                    .textFieldStyle(.roundedBorder)
                Button(L("Renommer")) {
                    model.rename(item.url, to: newName)
                }
                .disabled(newName == item.displayName || newName.isEmpty)
            }
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(L("Tags"))
            HStack {
                TextField(L("Separes par des virgules"), text: $tagsText)
                    .textFieldStyle(.roundedBorder)
                Button(L("Appliquer")) {
                    let tags = tagsText.split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    _ = TagManager.setTags(tags, on: urls)
                    model.activeTab.reload()
                    load()
                }
            }
        }
    }

    private func permissionsSection(_ item: FileItem) -> some View {
        let ownership = PosixPermissions.ownership(at: item.url)
        return VStack(alignment: .leading, spacing: 6) {
            sectionTitle(L("Autorisations"))
            if let permissions {
                accessRow(L("Proprietaire") + (ownership.owner.map { " (\($0))" } ?? ""),
                          value: permissions.owner, item: item) { $0.owner = $1 }
                accessRow(L("Groupe") + (ownership.group.map { " (\($0))" } ?? ""),
                          value: permissions.group, item: item) { $0.group = $1 }
                accessRow(L("Tous les autres"),
                          value: permissions.others, item: item) { $0.others = $1 }
                infoRow(L("Mode POSIX"), permissions.octal)
            } else {
                infoRow(L("Acces"), item.isWritable ? L("Lecture et ecriture") : L("Lecture seule"))
            }
            if let permissionsError {
                Text(permissionsError)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(L("Les bits d'execution sont conserves : les retirer rendrait un dossier intraversable et un programme inutilisable."))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Une ligne de droits : un menu par categorie, comme la fenetre
    /// d'informations du Finder.
    private func accessRow(_ label: String,
                           value: PosixPermissions.Access,
                           item: FileItem,
                           apply: @escaping (inout PosixPermissions, PosixPermissions.Access) -> Void) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)
            Picker("", selection: Binding(
                get: { value },
                set: { newValue in
                    guard var updated = permissions else { return }
                    apply(&updated, newValue)
                    writePermissions(updated, to: item)
                })) {
                ForEach(PosixPermissions.Access.allCases) { access in
                    Text(access.title).tag(access)
                }
            }
            .labelsHidden()
            .frame(width: 180)
        }
    }

    private func writePermissions(_ updated: PosixPermissions, to item: FileItem) {
        do {
            try updated.write(to: item.url)
            permissions = updated
            permissionsError = nil
            model.activeTab.reload()
        } catch {
            // Le bac a sable et le proprietaire reel peuvent tous deux refuser :
            // le message du systeme dit lequel.
            permissionsError = error.localizedDescription
            permissions = PosixPermissions.read(at: item.url)
        }
    }

    private func openWithSection(_ item: FileItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(L("Ouvrir avec"))
            let apps = OpenWith.applications(for: item.url)
            if apps.isEmpty {
                Text(L("Aucune application associee")).font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                ForEach(apps.prefix(6), id: \.self) { app in
                    Button {
                        model.openWith(application: app)
                    } label: {
                        HStack(spacing: 6) {
                            Image(nsImage: {
                                let i = NSWorkspace.shared.icon(forFile: app.path)
                                i.size = NSSize(width: 16, height: 16)
                                return i
                            }())
                            Text(OpenWith.name(of: app)).font(.system(size: 11))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            Text(value)
                .font(.system(size: 11))
                .textSelection(.enabled)
        }
    }

    private func load() {
        let targets = urls
        DispatchQueue.global(qos: .userInitiated).async {
            let loaded = targets.map { FileItem(url: $0) }
            DispatchQueue.main.async { finish(loaded) }
        }

        // Le calcul des tailles demarre une fois les metadonnees lues.
        func finish(_ loaded: [FileItem]) {
        items = loaded
        newName = items.first?.displayName ?? ""
        tagsText = items.first?.tagNames.joined(separator: ", ") ?? ""
        // Les droits ne sont montres que pour un seul element : une selection
        // multiple n'a pas de mode unique a afficher.
        permissions = loaded.count == 1 ? loaded.first.flatMap { PosixPermissions.read(at: $0.url) } : nil
        permissionsError = nil

        let files = items.filter { !$0.isNavigableContainer }
        let folders = items.filter { $0.isNavigableContainer }
        var running = files.reduce(Int64(0)) { $0 + $1.byteSize }
        if folders.isEmpty {
            totalSize = running
            return
        }
        totalSize = nil
        let group = DispatchGroup()
        for folder in folders {
            group.enter()
            DirectoryLister.folderSize(folder.url, cancelled: { false }) { size in
                running += size
                group.leave()
            }
        }
        group.notify(queue: .main) { totalSize = running }
        }
    }
}
