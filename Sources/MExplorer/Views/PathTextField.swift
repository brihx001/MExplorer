import AppKit
import SwiftUI

/// Champ de saisie de chemin avec completion.
///
/// SwiftUI n'expose pas la completion de `NSTextField` : il faut descendre a
/// AppKit, dont `complete(_:)` ouvre la liste et `control(_:textView:
/// completions:...)` la remplit. La completion ne porte que sur le dernier
/// composant du chemin, le reste designant le dossier a lire.
struct PathTextField: NSViewRepresentable {

    @Binding var text: String
    var placeholder: String = ""
    var onSubmit: () -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 12)
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.stringValue = text
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.lineBreakMode = .byTruncatingMiddle
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        field.placeholderString = placeholder
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {

        var parent: PathTextField

        init(_ parent: PathTextField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView,
                     doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertTab(_:)):
                completePath(in: textView)
                return true
            case #selector(NSResponder.insertNewline(_:)):
                parent.text = control.stringValue
                parent.onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            default:
                return false
            }
        }

        // MARK: - Completion

        /// Complete le dernier composant du chemin, a la maniere d'un shell.
        ///
        /// La completion d'AppKit n'est pas utilisable ici : elle decoupe le
        /// mot partiel sur la ponctuation, si bien que « mex-l » lui parait
        /// etre le mot « l » et qu'elle ecrit « mex-mex-lotC ». Le remplacement
        /// est donc fait a la main, sur le composant entier.
        private func completePath(in textView: NSTextView) {
            let text = textView.string
            guard let slash = text.lastIndex(of: "/") else { return }
            let componentStart = text.index(after: slash)
            let partial = String(text[componentStart...])
            let directory = (String(text[...slash]) as NSString).expandingTildeInPath

            let matches = candidates(in: directory, startingWith: partial)
            guard !matches.isEmpty else { NSSound.beep(); return }

            let completion = matches.count == 1 ? matches[0] + "/" : commonPrefix(of: matches)
            if completion.count > partial.count {
                let completed = String(text[..<componentStart]) + completion
                textView.string = completed
                textView.setSelectedRange(NSRange(location: (completed as NSString).length, length: 0))
                parent.text = completed
            }
            if matches.count > 1 { show(matches, for: textView, componentStart: componentStart) }
        }

        /// Sous-dossiers de `directory` dont le nom commence par `partial`.
        /// Seuls les dossiers comptent : un chemin ne se poursuit pas apres un
        /// fichier. Les elements masques n'apparaissent que si la saisie
        /// commence par un point, ou si l'utilisateur les affiche.
        private func candidates(in directory: String, startingWith partial: String) -> [String] {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return [] }
            let showHidden = partial.hasPrefix(".") || AppSettings.shared.showHiddenItems
            return entries
                .filter { name in
                    guard showHidden || !name.hasPrefix(".") else { return false }
                    guard partial.isEmpty || name.range(of: partial, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil
                    else { return false }
                    var isDirectory: ObjCBool = false
                    FileManager.default.fileExists(atPath: (directory as NSString).appendingPathComponent(name),
                                                   isDirectory: &isDirectory)
                    return isDirectory.boolValue
                }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }

        private func commonPrefix(of names: [String]) -> String {
            guard var prefix = names.first else { return "" }
            for name in names.dropFirst() {
                prefix = String(prefix.commonPrefix(with: name, options: [.caseInsensitive]))
                if prefix.isEmpty { break }
            }
            return prefix
        }

        /// Liste des possibilites sous le champ, quand la frappe ne suffit pas
        /// a trancher.
        private func show(_ matches: [String], for textView: NSTextView, componentStart: String.Index) {
            let menu = NSMenu()
            for name in matches.prefix(40) {
                let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
                item.representedObject = name
                item.target = self
                item.action = #selector(choose(_:))
                menu.addItem(item)
            }
            pendingTextView = textView
            let origin = NSPoint(x: 0, y: textView.bounds.maxY + 4)
            menu.popUp(positioning: nil, at: origin, in: textView)
        }

        private weak var pendingTextView: NSTextView?

        @objc private func choose(_ sender: NSMenuItem) {
            guard let name = sender.representedObject as? String,
                  let textView = pendingTextView else { return }
            let text = textView.string
            guard let slash = text.lastIndex(of: "/") else { return }
            let completed = String(text[...slash]) + name + "/"
            textView.string = completed
            textView.setSelectedRange(NSRange(location: (completed as NSString).length, length: 0))
            parent.text = completed
        }
    }
}

