import AppKit
import SwiftUI

/// Fenetre « Informations SMART » d'un disque.
final class DiskHealthWindowController: NSWindowController {

    private static var shared: [String: DiskHealthWindowController] = [:]

    static func show(for url: URL) {
        let key = url.path
        if let existing = shared[key] {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let health = DiskHealth.read(forVolumeAt: url)
        let controller = DiskHealthWindowController(health: health, title: url.lastPathComponent)
        shared[key] = controller
        controller.onClose = { shared.removeValue(forKey: key) }
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var onClose: (() -> Void)?

    private init(health: DiskHealth?, title: String) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = L("Informations SMART")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: DiskHealthView(health: health, volumeName: title))
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supporte") }
}

extension DiskHealthWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) { onClose?() }
}

// MARK: - Vue

private struct DiskHealthView: View {

    let health: DiskHealth?
    let volumeName: String
    @ObservedObject private var appSettings = AppSettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let health, health.hasSMART {
                    verdict(health)
                    if !health.criticalWarnings.isEmpty { warnings(health) }
                    Divider()
                    measures(health)
                } else {
                    unavailable
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 420, minHeight: 360)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: (health?.isInternal ?? true) ? "internaldrive" : "externaldrive")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(health?.deviceName ?? volumeName)
                    .font(.system(size: 15, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var subtitle: String {
        guard let health else { return volumeName }
        var parts = [volumeName]
        if !health.interconnect.isEmpty { parts.append(health.interconnect) }
        parts.append(health.isInternal ? L("Interne") : L("Externe"))
        parts.append("/dev/" + health.bsdName)
        return parts.joined(separator: "  ·  ")
    }

    private func verdict(_ health: DiskHealth) -> some View {
        HStack(spacing: 8) {
            Image(systemName: health.isHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(health.isHealthy ? Color.green : Color.orange)
                .font(.system(size: 16))
            Text(health.isHealthy
                 ? L("Le disque ne signale aucune anomalie.")
                 : L("Le disque signale au moins une valeur anormale."))
                .font(.system(size: 12, weight: .medium))
        }
    }

    private func warnings(_ health: DiskHealth) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(health.criticalWarnings, id: \.self) { warning in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.red)
                        .font(.system(size: 11))
                    Text(warning).font(.system(size: 11))
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.red.opacity(0.10)))
    }

    private func measures(_ health: DiskHealth) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(health.measures.enumerated()), id: \.element.id) { index, measure in
                HStack(spacing: 8) {
                    Text(measure.label)
                        .font(.system(size: 12))
                        .frame(width: 190, alignment: .leading)
                    if measure.isAbnormal {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.orange)
                            .font(.system(size: 11))
                            .help(L("Cette valeur sort de la plage attendue."))
                    }
                    Text(measure.value)
                        .font(.system(size: 12, weight: measure.isAbnormal ? .semibold : .regular))
                    Spacer()
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 11))
                        .help(measure.explanation)
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 8)
                .background(index.isMultiple(of: 2) ? Color.primary.opacity(0.04) : Color.clear)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.08)))
    }

    private var unavailable: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text(health?.unavailableReason ?? L("Ce disque n'expose pas de donnees SMART."))
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }
}
