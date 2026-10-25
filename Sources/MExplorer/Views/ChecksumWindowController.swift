import AppKit
import SwiftUI

/// Fenetre « Somme de controle » : hachage de la selection, avec comparaison
/// a une valeur attendue.
final class ChecksumWindowController: NSWindowController {

    private static var open: [ChecksumWindowController] = []

    static func show(for urls: [URL]) {
        guard !urls.isEmpty else { return }
        let controller = ChecksumWindowController(urls: urls)
        open.append(controller)
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private let state: ChecksumState

    private init(urls: [URL]) {
        let state = ChecksumState(urls: urls)
        self.state = state
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 420),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = L("Somme de controle")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ChecksumView(state: state))
        window.center()
        super.init(window: window)
        window.delegate = self
        state.start()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supporte") }
}

extension ChecksumWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        state.cancel()
        Self.open.removeAll { $0 === self }
    }
}

// MARK: - Etat

private final class ChecksumState: ObservableObject {

    let urls: [URL]
    @Published var algorithm: ChecksumJob.Algorithm = .sha256 { didSet { start() } }
    @Published var results: [ChecksumJob.Result] = []
    @Published var isRunning = false
    @Published var currentName = ""
    @Published var completed = 0
    /// Valeur collee par l'utilisateur pour verifier un telechargement.
    @Published var expected = ""

    private var job: ChecksumJob?

    init(urls: [URL]) { self.urls = urls }

    func start() {
        job?.cancel()
        results = []
        completed = 0
        isRunning = true
        let job = ChecksumJob()
        self.job = job
        job.run(urls: urls, algorithm: algorithm, progress: { [weak self] index, name in
            self?.completed = index
            self?.currentName = name
        }, completion: { [weak self] results in
            self?.results = results
            self?.isRunning = false
            self?.completed = results.count
        })
    }

    func cancel() {
        job?.cancel()
        isRunning = false
    }

    /// Comparaison insensible a la casse et aux espaces : on colle souvent la
    /// valeur avec le nom du fichier a la suite.
    func matches(_ digest: String?) -> Bool? {
        guard let digest else { return nil }
        let needle = expected.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return nil }
        return needle.contains(digest.lowercased())
    }

    var clipboardText: String {
        results.compactMap { result in
            guard let digest = result.digest else { return nil }
            return "\(digest)  \(result.url.lastPathComponent)"
        }.joined(separator: "\n")
    }
}

// MARK: - Vue

private struct ChecksumView: View {

    @ObservedObject var state: ChecksumState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if state.isRunning { running } else { Divider() }
            results
            Spacer(minLength: 0)
            footer
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 320)
    }

    private var header: some View {
        HStack(spacing: 12) {
            // Le libelle est pose a cote : dans un Picker segmente, SwiftUI le
            // serre et le coupe en deux lignes.
            Text(L("Algorithme"))
                .font(.system(size: 12))
                .fixedSize()
            Picker("", selection: $state.algorithm) {
                ForEach(ChecksumJob.Algorithm.allCases) { algorithm in
                    Text(algorithm.title).tag(algorithm)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 240)
            Spacer()
            Text(L("%d element(s)", state.urls.count))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var running: some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: Double(state.completed), total: Double(max(state.urls.count, 1)))
            Text(state.currentName)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var results: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(state.results.enumerated()), id: \.element.id) { index, result in
                    row(result, striped: index.isMultiple(of: 2))
                }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.08)))
    }

    private func row(_ result: ChecksumJob.Result, striped: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(result.url.lastPathComponent)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                if let digest = result.digest {
                    Text(digest)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else if let error = result.error {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let verdict = state.matches(result.digest) {
                Image(systemName: verdict ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(verdict ? Color.green : Color.red)
                    .help(verdict ? L("Correspond a la valeur attendue.")
                                  : L("Ne correspond pas a la valeur attendue."))
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(striped ? Color.primary.opacity(0.04) : Color.clear)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(L("Comparer a"))
                    .font(.system(size: 11))
                TextField(L("Collez ici la valeur publiee"), text: $state.expected)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
            }
            HStack {
                Spacer()
                Button(L("Copier le resultat")) {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(state.clipboardText, forType: .string)
                }
                .disabled(state.clipboardText.isEmpty)
            }
        }
    }
}
