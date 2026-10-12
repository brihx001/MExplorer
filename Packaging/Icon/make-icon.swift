#!/usr/bin/env swift
// Genere Packaging/AppIcon.icns.
// L'icone est dessinee vectoriellement a chaque taille (et non reduite depuis
// 1024) pour rester nette a 16 et 32 points.
//
// Motif : un dossier a onglets dont la face avant porte une arborescence,
// les deux traits distinctifs de MExplorer.

import AppKit

let outputDirectory = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath

// MARK: - Palette

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}

let skyTop     = rgb(86, 168, 255)
let skyBottom  = rgb(24,  70, 184)
let folderBack = rgb(178, 208, 255)
let folderTop  = rgb(255, 255, 255)
let folderLow  = rgb(226, 238, 255)
let accent     = rgb(31,  94, 214)

// MARK: - Geometrie (espace de dessin 1024 x 1024)

func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r)
}

/// Silhouette de dossier avec deux onglets sur le bord superieur.
func folderBackPath() -> NSBezierPath {
    let path = NSBezierPath()
    let body = rounded(212, 286, 600, 404, 52)
    path.append(body)
    // Les deux onglets evoquent la navigation par onglets.
    path.append(rounded(256, 628, 206, 120, 34))
    path.append(rounded(486, 628, 178, 100, 30))
    return path
}

/// Arborescence : une racine et ses branches, en traits epais pour rester
/// lisibles une fois l'icone reduite.
///
/// En dessous de 32 points, le dessin est simplifie (deux branches, traits plus
/// gras) : a cette taille, trois branches fines se confondent en une tache.
func drawTree(in rect: NSRect, compact: Bool) {
    accent.setFill()

    let nodeSize: CGFloat = compact ? 86 : 62
    let stroke: CGFloat = compact ? 34 : 22
    let spacing: CGFloat = compact ? 148 : 108
    let branches = compact ? 2 : 3
    let leafWidths: [CGFloat] = compact ? [228, 180] : [196, 158, 126]

    let rootX = rect.minX + (compact ? 54 : 46)
    let rootY = rect.maxY - (compact ? 118 : 92)
    let childX = rootX + (compact ? 176 : 150)

    rounded(rootX, rootY, nodeSize, nodeSize, nodeSize / 3.4).fill()

    let trunkTop = rootY + nodeSize / 2 - stroke / 2
    let lastChildCenter = rootY + nodeSize / 2 - spacing * CGFloat(branches - 1)

    // Tronc vertical
    rounded(rootX + nodeSize / 2 - stroke / 2,
            lastChildCenter - stroke / 2,
            stroke,
            trunkTop - lastChildCenter + stroke,
            stroke / 2).fill()

    for index in 0..<branches {
        let centerY = rootY + nodeSize / 2 - spacing * CGFloat(index)
        rounded(rootX + nodeSize / 2 - stroke / 2,
                centerY - stroke / 2,
                childX - rootX - nodeSize / 2 + stroke,
                stroke,
                stroke / 2).fill()
        rounded(childX + stroke / 2, centerY - stroke / 2, leafWidths[index], stroke, stroke / 2).fill()
    }
}

func drawIcon(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                               pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    let scale = CGFloat(pixels) / 1024
    context.cgContext.scaleBy(x: scale, y: scale)
    // A 16 points il ne reste que la silhouette : une arborescence y devient
    // une tache. On la supprime et on laisse parler la forme du dossier.
    let compact = pixels <= 32
    let minimal = pixels <= 16

    // Fond : carre arrondi facon macOS (marge de 100 sur 1024).
    let plate = rounded(100, 92, 824, 824, 186)
    NSGradient(colors: [skyTop, skyBottom])?.draw(in: plate, angle: -90)

    // Lumiere diagonale discrete sur la moitie haute.
    if !compact {
        NSGraphicsContext.saveGraphicsState()
        plate.addClip()
        NSGradient(colors: [NSColor.white.withAlphaComponent(0.22),
                            NSColor.white.withAlphaComponent(0.0)])?
            .draw(in: NSRect(x: 100, y: 520, width: 824, height: 396), angle: -90)
        NSGraphicsContext.restoreGraphicsState()
    }

    // Dossier. L'ombre portee est omise en petite taille : elle ne ferait
    // qu'empater le contour.
    NSGraphicsContext.saveGraphicsState()
    if !compact {
        let shadow = NSShadow()
        shadow.shadowColor = rgb(6, 24, 70, 0.35)
        shadow.shadowBlurRadius = 34
        shadow.shadowOffset = NSSize(width: 0, height: -14)
        shadow.set()
    }
    folderBack.setFill()
    folderBackPath().fill()
    NSGraphicsContext.restoreGraphicsState()

    // Face avant, legerement degradee
    let front = rounded(212, 286, 600, 322, 52)
    NSGradient(colors: [folderTop, folderLow])?.draw(in: front, angle: -90)

    // Arborescence sur la face avant
    if !minimal {
        drawTree(in: NSRect(x: 212, y: 286, width: 600, height: 322), compact: compact)
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// MARK: - Generation

let iconset = (outputDirectory as NSString).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(atPath: iconset)
try FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

for variant in variants {
    let rep = drawIcon(pixels: variant.pixels)
    guard let data = rep.representation(using: .png, properties: [:]) else { continue }
    let path = (iconset as NSString).appendingPathComponent(variant.name)
    try data.write(to: URL(fileURLWithPath: path))
}

print("iconset ecrit : \(iconset)")
