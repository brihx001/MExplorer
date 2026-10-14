import AppKit

/// Renommage par « deux clics lents », comme le Finder : un clic simple sur un
/// element deja seul selectionne ouvre le champ de nom apres un court delai.
///
/// Le delai depasse l'intervalle de double-clic du systeme, sinon le premier
/// clic d'un double-clic declencherait le renommage avant l'arrivee du second.
/// Tout autre evenement (clic, touche, defilement, menu contextuel) annule.
final class SlowClickRenamer {

    private var pending: DispatchWorkItem?

    private var delay: TimeInterval { NSEvent.doubleClickInterval + 0.35 }

    func cancel() {
        pending?.cancel()
        pending = nil
    }

    func schedule(_ action: @escaping () -> Void) {
        cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pending = nil
            action()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Vrai si le clic qui vient d'etre traite peut armer un renommage :
    /// un seul clic, sur une ligne deja seule selectionnee, sans glissement.
    static func qualifies(event: NSEvent, wasAloneSelected: Bool, mouseOrigin: NSPoint) -> Bool {
        guard wasAloneSelected, event.clickCount == 1 else { return false }
        let now = NSEvent.mouseLocation
        return hypot(now.x - mouseOrigin.x, now.y - mouseOrigin.y) < 4
    }
}
