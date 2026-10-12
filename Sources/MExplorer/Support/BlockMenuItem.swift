import AppKit

/// NSMenuItem pilote par une closure, pour construire des menus sans selecteurs.
final class BlockMenuItem: NSMenuItem, NSMenuItemValidation {

    private let handler: () -> Void
    /// Evaluee a l'ouverture du menu pour activer/desactiver l'entree.
    var validator: (() -> Bool)?
    /// Evaluee a l'ouverture du menu pour cocher l'entree.
    var stateProvider: (() -> Bool)?

    init(title: String, keyEquivalent: String = "",
         modifiers: NSEvent.ModifierFlags = .command,
         enabled: Bool = true,
         image: NSImage? = nil,
         handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: keyEquivalent)
        self.keyEquivalentModifierMask = modifiers
        self.target = self
        self.isEnabled = enabled
        self.image = image
    }

    required init(coder: NSCoder) { fatalError("init(coder:) non supporte") }

    @objc private func fire() { handler() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if let stateProvider { menuItem.state = stateProvider() ? .on : .off }
        return validator?() ?? true
    }
}

extension NSMenu {
    @discardableResult
    func addBlockItem(_ title: String, enabled: Bool = true, symbol: String? = nil,
                      handler: @escaping () -> Void) -> BlockMenuItem {
        let image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        let item = BlockMenuItem(title: title, enabled: enabled, image: image, handler: handler)
        addItem(item)
        return item
    }
}
