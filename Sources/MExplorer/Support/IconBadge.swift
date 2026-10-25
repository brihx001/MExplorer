import AppKit

/// Pastille posee sur une icone : alias, lien symbolique, verrou.
///
/// Le Finder marque ainsi les elements dont la nature ne se devine pas au
/// dessin. L'image composee est mise en cache par le `IconCache` appelant :
/// recomposer a chaque dessin de cellule couterait une allocation par ligne
/// et par defilement.
enum IconBadge {

    enum Kind: String {
        case alias, symlink, locked

        /// Symbole SF pose dans le coin.
        var symbol: String {
            switch self {
            case .alias: return "arrowshape.turn.up.left.fill"
            case .symlink: return "link"
            case .locked: return "lock.fill"
            }
        }

        var color: NSColor {
            switch self {
            case .alias, .symlink: return .white
            case .locked: return .white
            }
        }

        var background: NSColor {
            switch self {
            case .alias, .symlink: return .controlAccentColor
            case .locked: return .systemGray
            }
        }
    }

    /// Pastille qui convient a cet element, ou nil s'il n'en demande aucune.
    ///
    /// L'alias l'emporte sur le verrou : il decrit ce qu'est l'element, le
    /// verrou seulement ce qu'on peut en faire.
    static func kind(for item: FileItem) -> Kind? {
        if item.isAliasFile { return .alias }
        if item.isSymbolicLink { return .symlink }
        if !item.isWritable { return .locked }
        return nil
    }

    /// Icone marquee, de meme taille que l'originale.
    static func apply(_ kind: Kind, to icon: NSImage) -> NSImage {
        let size = icon.size
        guard size.width >= 16, size.height >= 16 else { return icon }
        // Proportionnelle a l'icone : a 16 points, une pastille de 10 mangerait
        // le dessin ; au-dela de 22, elle cesse d'etre une pastille.
        let badgeSide = max(8, min(size.width * 0.42, 22))
        let rect = NSRect(x: 0, y: 0, width: badgeSide, height: badgeSide)

        let result = NSImage(size: size)
        result.lockFocus()
        icon.draw(in: NSRect(origin: .zero, size: size))

        // Disque plein derriere le symbole : sans lui, un glyphe blanc
        // disparait sur une icone claire.
        kind.background.setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
        NSColor.white.withAlphaComponent(0.9).setStroke()
        let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
        ring.lineWidth = 1
        ring.stroke()

        if let symbol = NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil) {
            let glyph = symbol.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: badgeSide * 0.56, weight: .bold)) ?? symbol
            let tinted = NSImage(size: glyph.size)
            tinted.lockFocus()
            kind.color.set()
            NSRect(origin: .zero, size: glyph.size).fill(using: .sourceOver)
            glyph.draw(in: NSRect(origin: .zero, size: glyph.size),
                       from: .zero, operation: .destinationIn, fraction: 1)
            tinted.unlockFocus()

            let inset = badgeSide * 0.24
            tinted.draw(in: rect.insetBy(dx: inset, dy: inset))
        }

        result.unlockFocus()
        return result
    }
}
