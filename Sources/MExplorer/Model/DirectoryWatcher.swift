import Foundation

/// Surveille un dossier et notifie (avec anti-rebond) quand son contenu change.
final class DirectoryWatcher {

    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private var debounce: DispatchWorkItem?
    /// Invalide les ouvertures de descripteur encore en cours.
    private var generation = 0
    private let interval: TimeInterval
    private let onChange: () -> Void

    init(interval: TimeInterval = 0.25, onChange: @escaping () -> Void) {
        self.interval = interval
        self.onChange = onChange
    }

    deinit { stop() }

    func watch(_ url: URL) {
        stop()
        generation &+= 1
        let token = generation

        // `open()` peut bloquer indefiniment sur un montage qui ne repond pas
        // (volume reseau, conteneur, iCloud en cours de synchronisation) : il
        // ne doit jamais etre appele depuis le thread principal.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let fd = open(url.path, O_EVTONLY)
            guard fd >= 0 else { return }
            DispatchQueue.main.async {
                guard let self, token == self.generation else {
                    close(fd)   // surveillance annulee entre-temps
                    return
                }
                self.install(fd)
            }
        }
    }

    private func install(_ fd: CInt) {
        descriptor = fd
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .revoke, .extend, .attrib],
            queue: DispatchQueue.global(qos: .utility)
        )
        src.setEventHandler { [weak self] in self?.schedule() }
        src.setCancelHandler { close(fd) }
        source = src
        src.resume()
    }

    func stop() {
        generation &+= 1        // invalide une ouverture encore en vol
        debounce?.cancel()
        debounce = nil
        source?.cancel()
        source = nil
        descriptor = -1
    }

    private func schedule() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.debounce?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.onChange() }
            self.debounce = work
            DispatchQueue.main.asyncAfter(deadline: .now() + self.interval, execute: work)
        }
    }
}
