import AppKit

/// Conserve les controleurs de fenetre vivants et gere l'ouverture de nouvelles fenetres.
final class WindowManager {

    static let shared = WindowManager()
    private init() {}

    private(set) var controllers: [BrowserWindowController] = []

    @discardableResult
    func openWindow(at location: Location = .folder(SidebarCatalog.home)) -> BrowserWindowController {
        let controller = BrowserWindowController(location: location)
        controllers.append(controller)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: false)
        return controller
    }

    /// Ouvre une fenetre qui reprend un onglet detache d'une autre.
    @discardableResult
    func openWindow(adopting tab: TabState, from source: WindowModel) -> BrowserWindowController? {
        guard source.tabs.count > 1 else { return nil }
        source.release(tab)
        let controller = BrowserWindowController(adopting: tab)
        controllers.append(controller)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: false)
        return controller
    }

    func forget(_ controller: BrowserWindowController) {
        controllers.removeAll { $0 === controller }
    }

    var keyModel: WindowModel? {
        if let key = NSApp.keyWindow,
           let controller = controllers.first(where: { $0.window === key }) {
            return controller.model
        }
        return controllers.first?.model
    }
}
