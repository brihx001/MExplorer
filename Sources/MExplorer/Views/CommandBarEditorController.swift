import AppKit
import SwiftUI

/// Fenetre « Personnaliser la barre de commandes ».
final class CommandBarEditorController: NSWindowController {

    private static var shared: CommandBarEditorController?

    static func show() {
        if let existing = shared {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = CommandBarEditorController()
        shared = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 440),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = L("Personnaliser la barre de commandes")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: CommandBarEditorView())
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supporte") }
}

extension CommandBarEditorController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) { Self.shared = nil }
}

// MARK: - Vue

private struct CommandBarEditorView: View {

    @ObservedObject private var settings = AppSettings.shared

    private var shown: [CommandBarItem] { settings.commandBarItems }
    private var hidden: [CommandBarItem] { CommandBarItem.allCases.filter { !shown.contains($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Cochez ce qui doit apparaitre, et reordonnez avec les fleches."))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                        row(item, index: index, isShown: true)
                    }
                    if !hidden.isEmpty {
                        HStack {
                            Text(L("Masques"))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.top, 10)
                        .padding(.horizontal, 8)
                        ForEach(hidden) { item in row(item, index: nil, isShown: false) }
                    }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.08)))

            HStack {
                Button(L("Retablir la barre d'origine")) { settings.resetCommandBar() }
                Spacer()
            }
        }
        .padding(16)
        .frame(minWidth: 380, minHeight: 360)
    }

    private func row(_ item: CommandBarItem, index: Int?, isShown: Bool) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { isShown },
                set: { wanted in toggle(item, on: wanted) }))
                .labelsHidden()
                .disabled(!item.isRemovable)
                .help(item.isRemovable ? "" : L("Cet element ne peut pas etre retire."))
            Image(systemName: item.symbol)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            Text(item.title).font(.system(size: 12))
            Spacer()
            if let index {
                Button {
                    move(from: index, to: index - 1)
                } label: { Image(systemName: "chevron.up") }
                    .buttonStyle(.borderless)
                    .disabled(index == 0)
                Button {
                    move(from: index, to: index + 1)
                } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(.borderless)
                    .disabled(index == shown.count - 1)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }

    private func toggle(_ item: CommandBarItem, on wanted: Bool) {
        var items = settings.commandBarItems
        if wanted {
            guard !items.contains(item) else { return }
            items.append(item)
        } else {
            guard item.isRemovable else { return }
            items.removeAll { $0 == item }
        }
        settings.commandBarItems = items
    }

    private func move(from: Int, to: Int) {
        var items = settings.commandBarItems
        guard items.indices.contains(from), items.indices.contains(to) else { return }
        let item = items.remove(at: from)
        items.insert(item, at: to)
        settings.commandBarItems = items
    }
}
