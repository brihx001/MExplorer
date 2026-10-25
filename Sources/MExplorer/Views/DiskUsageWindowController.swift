import AppKit
import SwiftUI

/// Fenetre « Occupation du dossier » : ce qui pese, et ce qui est en double.
final class DiskUsageWindowController: NSWindowController {

    private static var open: [DiskUsageWindowController] = []

    static func show(for folder: URL, model: WindowModel) {
        let controller = DiskUsageWindowController(folder: folder, model: model)
        open.append(controller)
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private let state: DiskUsageState

    private init(folder: URL, model: WindowModel) {
        let state = DiskUsageState(folder: folder, model: model)
        self.state = state
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 540),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = L("Occupation : %@", folder.lastPathComponent)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: DiskUsageView(state: state))
        window.center()
        super.init(window: window)
        window.delegate = self
        state.start()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supporte") }
}

extension DiskUsageWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        state.cancel()
        Self.open.removeAll { $0 === self }
    }
}

// MARK: - Etat

private final class DiskUsageState: ObservableObject {

    enum Tab: String, CaseIterable, Identifiable {
        case breakdown, largest, duplicates
        var id: String { rawValue }
        var title: String {
            switch self {
            case .breakdown: return L("Repartition")
            case .largest: return L("Plus gros fichiers")
            case .duplicates: return L("Doublons")
            }
        }
    }

    let folder: URL
    private weak var model: WindowModel?

    @Published var tab: Tab = .breakdown
    @Published var findDuplicates = true
    @Published private(set) var result = DiskUsageScan.Result()
    @Published private(set) var isRunning = false
    @Published private(set) var scanned = 0

    private var scan: DiskUsageScan?

    init(folder: URL, model: WindowModel) {
        self.folder = folder
        self.model = model
    }

    func start() {
        scan?.cancel()
        let scan = DiskUsageScan()
        self.scan = scan
        isRunning = true
        scanned = 0
        result = DiskUsageScan.Result()
        scan.run(root: folder, findDuplicates: findDuplicates, progress: { [weak self] count in
            self?.scanned = count
        }, completion: { [weak self] result in
            self?.result = result
            self?.isRunning = false
        })
    }

    func cancel() {
        scan?.cancel()
        isRunning = false
    }

    func reveal(_ url: URL) {
        model?.openInNewTab(url.deletingLastPathComponent())
        model?.activeTab.selectedURLs = [url]
    }

    /// Part d'une entree dans le total, pour la barre de proportion.
    func fraction(_ size: Int64) -> Double {
        guard result.totalSize > 0 else { return 0 }
        return Double(size) / Double(result.totalSize)
    }

    var reclaimable: Int64 { result.duplicates.reduce(0) { $0 + $1.reclaimable } }
}

// MARK: - Vue

private struct DiskUsageView: View {

    @ObservedObject var state: DiskUsageState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Picker("", selection: $state.tab) {
                ForEach(DiskUsageState.Tab.allCases) { tab in Text(tab.title).tag(tab) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            switch state.tab {
            case .breakdown: list(state.result.children)
            case .largest: list(state.result.largestFiles)
            case .duplicates: duplicates
            }
        }
        .padding(16)
        .frame(minWidth: 620, minHeight: 420)
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(state.folder.path)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(summary)
                    .font(.system(size: 13, weight: .semibold))
            }
            Spacer()
            if state.isRunning {
                ProgressView().controlSize(.small)
                Button(L("Arreter")) { state.cancel() }
            } else {
                Toggle(L("Chercher les doublons"), isOn: $state.findDuplicates)
                    .font(.system(size: 11))
                Button(L("Relancer")) { state.start() }
            }
        }
    }

    private var summary: String {
        if state.isRunning { return L("%d fichiers parcourus...", state.scanned) }
        if state.result.wasCancelled { return L("Analyse interrompue - %@ vus", Fmt.size(state.result.totalSize)) }
        return L("%@ dans %d fichiers", Fmt.size(state.result.totalSize), state.result.fileCount)
    }

    private func list(_ entries: [DiskUsageScan.Entry]) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    HStack(spacing: 8) {
                        Image(systemName: entry.isDirectory ? "folder" : "doc")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 11))
                        Text(entry.url.lastPathComponent)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        // Barre de proportion : un tableau de chiffres ne
                        // montre pas d'un coup d'oeil ce qui pese.
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.primary.opacity(0.08))
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.accentColor.opacity(0.7))
                                    .frame(width: max(2, geometry.size.width * state.fraction(entry.size)))
                            }
                        }
                        .frame(width: 140, height: 8)
                        Text(Fmt.size(entry.size))
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 80, alignment: .trailing)
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                    .background(index.isMultiple(of: 2) ? Color.primary.opacity(0.04) : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { state.reveal(entry.url) }
                    .help(entry.url.path)
                }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.08)))
    }

    private var duplicates: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !state.findDuplicates {
                Text(L("La recherche de doublons est desactivee."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if state.result.duplicates.isEmpty && !state.isRunning {
                Text(L("Aucun doublon."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                Text(L("%@ repris en ne gardant qu'un exemplaire de chaque.", Fmt.size(state.reclaimable)))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(state.result.duplicates) { group in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("%d exemplaires de %@", group.urls.count, Fmt.size(group.size)))
                                .font(.system(size: 11, weight: .semibold))
                            ForEach(group.urls, id: \.self) { url in
                                Text(url.path)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .contentShape(Rectangle())
                                    .onTapGesture(count: 2) { state.reveal(url) }
                            }
                        }
                        .padding(.vertical, 5)
                        .padding(.horizontal, 8)
                    }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.08)))
        }
    }
}
