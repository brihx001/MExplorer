import AppKit
import SwiftUI

/// Fenetre « Renommer par lot » : regles a gauche, apercu a droite.
final class BatchRenameWindowController: NSWindowController {

    private static var open: [BatchRenameWindowController] = []

    static func show(for urls: [URL], model: WindowModel) {
        let controller = BatchRenameWindowController(urls: urls, model: model)
        open.append(controller)
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private init(urls: [URL], model: WindowModel) {
        let state = BatchRenameState(urls: urls, model: model)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 460),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = L("Renommer par lot")
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        state.onClose = { [weak self] in self?.close() }
        window.contentView = NSHostingView(rootView: BatchRenameView(state: state))
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supporte") }
}

extension BatchRenameWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        Self.open.removeAll { $0 === self }
    }
}

// MARK: - Etat

private final class BatchRenameState: ObservableObject {

    let urls: [URL]
    private weak var model: WindowModel?
    var onClose: (() -> Void)?

    @Published var rules = BatchRename.Rules() { didSet { recompute() } }
    @Published private(set) var proposals: [BatchRename.Proposal] = []

    init(urls: [URL], model: WindowModel) {
        self.urls = urls
        self.model = model
        recompute()
    }

    private func recompute() {
        proposals = BatchRename.apply(rules, to: urls)
    }

    var conflicts: Int { proposals.filter(\.conflict).count }
    var changes: Int { proposals.filter { !$0.unchanged && !$0.conflict }.count }
    var canApply: Bool { changes > 0 && conflicts == 0 }

    /// Renomme en deux temps quand les noms se croisent : passer « a » en « b »
    /// et « b » en « a » echoue si l'on renomme dans l'ordre. Un nom temporaire
    /// unique leve la collision.
    func apply() {
        guard let model else { return }
        let work = proposals.filter { !$0.unchanged }
        guard !work.isEmpty else { return }

        let undoManager = model.undoManager
        undoManager?.beginUndoGrouping()
        var staged: [(temp: URL, finalName: String)] = []
        for proposal in work {
            let temp = proposal.url.deletingLastPathComponent()
                .appendingPathComponent(".mexplorer-rename-" + UUID().uuidString)
            do {
                let moved = try FileOperations.shared.rename(proposal.url, to: temp.lastPathComponent,
                                                             undoManager: undoManager)
                staged.append((moved, proposal.newName))
            } catch {
                model.present(error)
            }
        }
        for entry in staged {
            do { _ = try FileOperations.shared.rename(entry.temp, to: entry.finalName, undoManager: undoManager) }
            catch { model.present(error) }
        }
        undoManager?.setActionName(L("Renommer par lot"))
        undoManager?.endUndoGrouping()

        FileOperations.shared.notifyChange()
        onClose?()
    }
}

// MARK: - Vue

private struct BatchRenameView: View {

    @ObservedObject var state: BatchRenameState

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                rulesPane
                    .frame(width: 280)
                    .padding(16)
                Divider()
                preview
                    .frame(maxWidth: .infinity)
            }
            Divider()
            footer
                .padding(12)
        }
        .frame(minWidth: 620, minHeight: 380)
    }

    private var rulesPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(L("Operation"), selection: Binding(
                get: { state.rules.mode },
                set: { state.rules.mode = $0 })) {
                ForEach(BatchRename.Mode.allCases) { mode in Text(mode.title).tag(mode) }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            switch state.rules.mode {
            case .replace:
                field(L("Rechercher"), text: Binding(
                    get: { state.rules.search }, set: { state.rules.search = $0 }))
                field(L("Remplacer par"), text: Binding(
                    get: { state.rules.replacement }, set: { state.rules.replacement = $0 }))
                Text(L("La recherche ignore la casse."))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            case .addText:
                field(L("Texte"), text: Binding(
                    get: { state.rules.text }, set: { state.rules.text = $0 }))
                Picker("", selection: Binding(
                    get: { state.rules.position }, set: { state.rules.position = $0 })) {
                    ForEach(BatchRename.Position.allCases) { p in Text(p.title).tag(p) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            case .numbering:
                field(L("Nom de base"), text: Binding(
                    get: { state.rules.baseName }, set: { state.rules.baseName = $0 }),
                      placeholder: L("(nom actuel)"))
                stepperRow(L("Commencer a"), value: Binding(
                    get: { state.rules.start }, set: { state.rules.start = $0 }), range: 0...99_999)
                stepperRow(L("Chiffres"), value: Binding(
                    get: { state.rules.digits }, set: { state.rules.digits = $0 }), range: 1...6)
            case .caseChange:
                Picker("", selection: Binding(
                    get: { state.rules.casing }, set: { state.rules.casing = $0 })) {
                    ForEach(BatchRename.Casing.allCases) { c in Text(c.title).tag(c) }
                }
                .labelsHidden()
                .pickerStyle(.radioGroup)
            }

            Toggle(L("Inclure l'extension"), isOn: Binding(
                get: { state.rules.includeExtension }, set: { state.rules.includeExtension = $0 }))
                .font(.system(size: 11))
                .help(L("Changer l'extension modifie l'application qui ouvre le fichier."))

            Spacer()
        }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String = "") -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
        }
    }

    private func stepperRow(_ label: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            Stepper(value: value, in: range) { Text("\(value.wrappedValue)").font(.system(size: 11)) }
        }
    }

    private var preview: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(state.proposals.enumerated()), id: \.element.id) { index, proposal in
                    HStack(spacing: 8) {
                        Text(proposal.url.lastPathComponent)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Text(proposal.newName)
                            .font(.system(size: 11, weight: proposal.unchanged ? .regular : .medium))
                            .foregroundStyle(proposal.conflict ? Color.red : Color.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if proposal.conflict {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.red)
                                .font(.system(size: 10))
                                .help(L("Ce nom est deja pris."))
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 10)
                    .background(index.isMultiple(of: 2) ? Color.primary.opacity(0.04) : Color.clear)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(summary)
                .font(.system(size: 11))
                .foregroundStyle(state.conflicts > 0 ? Color.red : Color.secondary)
            Spacer()
            Button(L("Annuler", context: "bouton")) { state.onClose?() }
                .keyboardShortcut(.cancelAction)
            Button(L("Renommer")) { state.apply() }
                .keyboardShortcut(.defaultAction)
                .disabled(!state.canApply)
        }
    }

    private var summary: String {
        if state.conflicts > 0 { return L("%d nom(s) en conflit", state.conflicts) }
        return L("%d element(s) renomme(s)", state.changes)
    }
}
