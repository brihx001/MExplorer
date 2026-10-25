import SwiftUI

/// Barre d'etat : nombre et poids des elements, resume de la selection,
/// jauge de remplissage du disque, bascules d'affichage.
struct StatusBarView: View {

    @ObservedObject var model: WindowModel
    /// Redessine la vue quand la langue (ou un reglage global) change.
    @ObservedObject private var appSettings = AppSettings.shared
    /// Sans cette observation, l'apparition et la disparition de la barre de
    /// progression ne seraient pas redessinees.
    @ObservedObject private var operations = FileOperations.shared.progress
    @State private var selectionSize: Int64?

    private var tab: TabState { model.activeTab }

    var body: some View {
        HStack(spacing: 10) {
            Text(itemCountText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if let total = displayedSizeText {
                Text(total)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .help(L("Taille cumulee des elements affiches"))
            }

            if model.hasSelection {
                Divider().frame(height: 12)
                Text(selectionText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if tab.isLoading {
                Divider().frame(height: 12)
                ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 14, height: 14)
                Text(L("Chargement...")).font(.system(size: 11)).foregroundStyle(.secondary)
            }

            if tab.isMeasuringFolders {
                Divider().frame(height: 12)
                ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 14, height: 14)
                Text(L("Calcul des tailles...")).font(.system(size: 11)).foregroundStyle(.secondary)
            }

            if operations.isRunning {
                Divider().frame(height: 12)
                OperationProgressView(progress: operations)
            }

            Spacer(minLength: 6)

            if let usage = tab.volumeUsage {
                DiskGauge(usage: usage)
                Divider().frame(height: 12)
            }

            Button {
                tab.update { $0.viewMode = .details }
            } label: {
                Image(systemName: "list.dash")
                    .foregroundStyle(tab.settings.viewMode == .details ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(L("Details"))

            Button {
                tab.update { $0.viewMode = .largeIcons }
            } label: {
                Image(systemName: "square.grid.2x2")
                    .foregroundStyle(tab.settings.viewMode.isIconGrid ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(L("Grandes icones"))
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .top) { Divider() }
        .onChange(of: model.selectionCount) { _, _ in updateSelectionSize() }
    }

    // MARK: - Libelles

    private var itemCountText: String {
        let count = tab.rows.compactMap { $0.item }.count
        if !tab.filterText.isEmpty {
            return L("%d element(s) sur %d", count, tab.items.count)
        }
        return count == 1 ? L("1 element") : L("%d elements", count)
    }

    /// Poids cumule des elements affiches. Le point de suspension signale que
    /// des tailles de dossiers sont encore en cours de calcul.
    private var displayedSizeText: String? {
        guard !tab.rows.isEmpty else { return nil }
        guard tab.displayedSize > 0 || !tab.displayedSizeIsPartial else { return nil }
        return "-  " + Fmt.size(tab.displayedSize) + (tab.displayedSizeIsPartial ? "..." : "")
    }

    private var selectionText: String {
        let count = model.selectionCount
        let base = count == 1 ? L("1 element selectionne") : L("%d elements selectionnes", count)
        if let size = selectionSize, size > 0 { return "\(base)  -  \(Fmt.size(size))" }
        return base
    }

    private func updateSelectionSize() {
        let files = model.selection.filter { !$0.isNavigableContainer }
        selectionSize = files.isEmpty ? nil : files.reduce(0) { $0 + $1.byteSize }
    }
}

/// Jauge de remplissage du volume courant, du vert au rouge.
struct DiskGauge: View {

    @ObservedObject private var appSettings = AppSettings.shared

    let usage: VolumeUsage

    private static let width: CGFloat = 72
    private static let height: CGFloat = 7

    var body: some View {
        HStack(spacing: 6) {
            ZStack(alignment: .leading) {
                // La piste doit rester lisible : sans elle, la jauge ressemble
                // a une simple barre pleine et la proportion ne se lit plus.
                Capsule()
                    .fill(Color.primary.opacity(0.22))
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.5))
                    .frame(width: Self.width, height: Self.height)
                Capsule()
                    .fill(color)
                    .frame(width: max(3, Self.width * usage.fraction), height: Self.height)
            }

            Text(L("%@ libres", Fmt.size(usage.available)))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .help(usage.summary)
    }

    /// Vert jusqu'aux deux tiers, puis bascule vers l'orange et le rouge.
    /// L'exposant retarde le virage : un disque a moitie plein reste rassurant.
    private var color: Color {
        let hue = (1 - pow(usage.fraction, 1.8)) * 0.33
        return Color(hue: hue, saturation: 0.9, brightness: 0.8)
    }
}

struct OperationProgressView: View {

    @ObservedObject private var appSettings = AppSettings.shared
    @ObservedObject var progress: FileOperationProgress

    var body: some View {
        HStack(spacing: 6) {
            ProgressView(value: progress.fraction)
                .frame(width: 90)
                .controlSize(.small)
            Text(summary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .help(progress.label)
            Button {
                FileOperations.shared.cancelCurrent()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(progress.isCancelling)
            .help(L("Arreter l'operation"))
        }
    }

    /// « Copie 3/12 » ou, quand le volume est connu, « Copie 1,2 Go sur 4,0 Go ».
    private var summary: String {
        if progress.isCancelling { return L("Arret en cours...") }
        if progress.bytesTotal > 0 {
            return L("%@ %@ sur %@", progress.kind.title,
                     Fmt.size(progress.bytesDone), Fmt.size(progress.bytesTotal))
        }
        return "\(progress.kind.title) \(progress.completed)/\(progress.total)"
    }
}
