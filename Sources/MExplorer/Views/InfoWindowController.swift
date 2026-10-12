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
        window.title = urls.count == 1 ? "\(urls[0].lastPathComponent) - Infos" : "\(urls.count) elements - Infos"
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
            sectionTitle("General")
            infoRow("Taille", totalSize.map { Fmt.size($0) } ?? "Calcul en cours...")
            if items.count == 1, let item = items.first {
                infoRow("Emplacement", item.url.deletingLastPathComponent().path)
                infoRow("Cree le", Fmt.date(item.creationDate))
                infoRow("Modifie le", Fmt.date(item.modificationDate))
                if let added = item.addedDate { infoRow("Ajoute le", Fmt.date(added)) }
                if !item.fileExtension.isEmpty { infoRow("Extension", item.fileExtension) }
                if let type = item.contentType { infoRow("Type UTI", type.identifier) }
            }
        }
    }

    private func nameSection(_ item: FileItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Nom et extension")
            HStack {
                TextField("Nom", text: $newName)
                    .textFieldStyle(.roundedBorder)
                Button("Renommer") {
                    model.rename(item.url, to: newName)
                }
                .disabled(newName == item.displayName || newName.isEmpty)
            }
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Tags")
            HStack {
                TextField("Separes par des virgules", text: $tagsText)
                    .textFieldStyle(.roundedBorder)
                Button("Appliquer") {
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
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Autorisations")
            infoRow("Acces", item.isWritable ? "Lecture et ecriture" : "Lecture seule")
            if let posix = try? FileManager.default.attributesOfItem(atPath: item.url.path)[.posixPermissions] as? NSNumber {
                infoRow("Mode POSIX", String(format: "%03o", posix.intValue & 0o777))
            }
            if let owner = try? FileManager.default.attributesOfItem(atPath: item.url.path)[.ownerAccountName] as? String {
                infoRow("Proprietaire", owner)
            }
        }
    }

    private func openWithSection(_ item: FileItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Ouvrir avec")
            let apps = OpenWith.applications(for: item.url)
            if apps.isEmpty {
                Text("Aucune application associee").font(.system(size: 11)).foregroundStyle(.secondary)
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
