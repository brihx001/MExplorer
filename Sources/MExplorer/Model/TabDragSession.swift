import AppKit
import UniformTypeIdentifiers

extension UTType {
    /// Type prive, declare dans l'Info.plist, qui identifie un onglet en cours
    /// de glissement. Il evite que la bande d'onglets accepte n'importe quoi.
    static let mexplorerTab = UTType(exportedAs: "com.jerome.mexplorer.tab")
}

/// Glisser d'onglet en cours.
///
/// Les fenetres appartiennent au meme processus : plutot que de serialiser
/// l'onglet et de le recreer a l'arrivee (ce qui perdrait son historique, sa
/// selection et ses reglages), on garde une reference et le presse-papiers ne
/// sert qu'a identifier le glissement.
final class TabDragSession {

    static let shared = TabDragSession()
    private init() {}

    private(set) weak var tab: TabState?
    private(set) weak var source: WindowModel?

    func begin(tab: TabState, from model: WindowModel) {
        self.tab = tab
        self.source = model
    }

    func end() {
        tab = nil
        source = nil
    }

    var isActive: Bool { tab != nil && source != nil }

    /// Fournisseur a renvoyer depuis `.onDrag`. La visibilite est limitee au
    /// processus : un onglet n'a aucun sens dans une autre application.
    func itemProvider(for tab: TabState) -> NSItemProvider {
        let provider = NSItemProvider()
        let payload = Data(tab.id.uuidString.utf8)
        provider.registerDataRepresentation(forTypeIdentifier: UTType.mexplorerTab.identifier,
                                            visibility: .ownProcess) { completion in
            completion(payload, nil)
            return nil
        }
        return provider
    }
}
