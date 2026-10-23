import SwiftUI
import Quartz

/// Volet lateral droit : details de la selection (equivalent du volet de details
/// de Windows 11, enrichi des tags et de l'apercu Quick Look du Finder).
struct DetailsPaneView: View {

    @ObservedObject var model: WindowModel
    /// Redessine la vue quand la langue (ou un reglage global) change.
    @ObservedObject private var appSettings = AppSettings.shared
    @State private var folderSize: Int64?
    @State private var folderSizeURL: URL?

    private var selection: [FileItem] { model.selection }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if model.showPreviewPane {
                    previewSection
                }
                if selection.isEmpty {
                    emptyState
                } else if selection.count == 1, let item = selection[0] as FileItem? {
                    single(item)
                } else {
                    multiple
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Sections

    @ViewBuilder
    private var previewSection: some View {
        if let url = selection.first?.url {
            QuickLookPreview(url: url)
                .frame(height: 220)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let folder = model.currentFolder {
                header(icon: IconCache.shared.icon(forFileAt: folder), title: folder.lastPathComponent,
                       subtitle: L("Dossier"))
                row(L("Chemin"), folder.path)
                row(L("Elements"), "\(model.activeTab.items.count)")
            } else {
                Text(L("Aucun element selectionne"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func single(_ item: FileItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(icon: IconCache.shared.icon(for: item),
                   title: item.displayName,
                   subtitle: item.kindDescription)

            Divider()

            if item.isNavigableContainer {
                HStack {
                    Text(L("Taille")).font(.system(size: 11)).foregroundStyle(.secondary)
                        .frame(width: 92, alignment: .leading)
                    if let size = folderSize, folderSizeURL == item.url {
                        Text(Fmt.size(size)).font(.system(size: 11))
                    } else {
                        Button(L("Calculer")) { computeFolderSize(item) }
                            .buttonStyle(.link)
                            .font(.system(size: 11))
                    }
                }
            } else {
                row(L("Taille"), Fmt.size(item.byteSize))
            }
            row(L("Modifie le"), Fmt.date(item.modificationDate))
            row(L("Cree le"), Fmt.date(item.creationDate))
            if let added = item.addedDate { row(L("Ajoute le"), Fmt.date(added)) }
            row(L("Emplacement"), item.url.deletingLastPathComponent().path)
            if !item.fileExtension.isEmpty { row(L("Extension"), item.fileExtension) }
            row(L("Autorisations"), item.isWritable ? L("Lecture et ecriture") : L("Lecture seule"))
            if item.cloudState.isUbiquitous { row("iCloud", ubiquitousLabel(item)) }

            if !item.tagNames.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Tags")).font(.system(size: 11)).foregroundStyle(.secondary)
                    HStack(spacing: 5) {
                        ForEach(item.tagNames, id: \.self) { tag in
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(Color(nsColor: SidebarCatalog.color(forTag: tag) ?? .systemGray))
                                    .frame(width: 8, height: 8)
                                Text(tag).font(.system(size: 11))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.primary.opacity(0.07)))
                        }
                    }
                }
            }

            Divider()
            HStack(spacing: 8) {
                Button(L("Ouvrir")) { model.activate([item]) }
                Button(L("Proprietes")) { model.showInfoWindow() }
            }
            .controlSize(.small)
        }
    }

    private var multiple: some View {
        let files = selection.filter { !$0.isNavigableContainer }
        let folders = selection.count - files.count
        let total = files.reduce(Int64(0)) { $0 + $1.byteSize }
        return VStack(alignment: .leading, spacing: 8) {
            Text(L("%d elements selectionnes", selection.count))
                .font(.system(size: 13, weight: .semibold))
            row(L("Fichiers"), "\(files.count)")
            row(L("Dossiers"), "\(folders)")
            row(L("Taille totale"), Fmt.size(total))
        }
    }

    // MARK: - Briques

    private func header(icon: NSImage, title: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(.system(size: 11))
                .textSelection(.enabled)
                .lineLimit(4)
        }
    }

    private func ubiquitousLabel(_ item: FileItem) -> String {
        switch item.cloudState.status {
        case .some(.current): return L("Telecharge")
        case .some(.downloaded): return L("Telecharge")
        case .some(.notDownloaded): return L("Non telecharge")
        default: return "iCloud"
        }
    }

    private func computeFolderSize(_ item: FileItem) {
        folderSizeURL = item.url
        folderSize = nil
        model.activeTab.computeSize(for: item) { size in
            folderSize = size
        }
    }
}

/// Enrobage AppKit de QLPreviewView.
struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .compact) ?? QLPreviewView()
        view.autostarts = true
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        if (nsView.previewItem as? NSURL) as URL? != url {
            nsView.previewItem = url as NSURL
        }
    }
}
