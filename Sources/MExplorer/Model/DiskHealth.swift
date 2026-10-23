import Foundation
import IOKit
import CSmart

/// Etat de sante d'un disque, lu par SMART.
///
/// macOS n'ouvre le client SMART qu'aux applications qui le declarent :
/// `Packaging/MExplorer.entitlements` porte pour cela l'exception temporaire
/// `iokit-user-client-class`. Sans elle, l'ouverture repond
/// `kIOReturnNotPermitted` depuis le bac a sable.
struct DiskHealth {

    /// Un releve, avec ce qu'il faut pour le juger anormal et l'expliquer.
    struct Measure: Identifiable {
        let id = UUID()
        let label: String
        let value: String
        let isAbnormal: Bool
        let explanation: String
    }

    let deviceName: String
    let interconnect: String
    let isInternal: Bool
    let bsdName: String
    let smart: MEXNVMeSMART?
    /// Raison de l'absence de donnees SMART, le cas echeant.
    let unavailableReason: String?

    var hasSMART: Bool { smart != nil }

    // MARK: - Lecture

    /// Disque physique qui porte ce volume, ou nil s'il n'est pas identifiable.
    static func read(forVolumeAt url: URL) -> DiskHealth? {
        guard let device = wholeDiskName(for: url) else { return nil }
        guard let service = service(forBSDName: device) else {
            return DiskHealth(deviceName: device, interconnect: "", isInternal: false,
                              bsdName: device, smart: nil,
                              unavailableReason: L("Le peripherique n'a pas ete trouve dans le registre du systeme."))
        }
        defer { IOObjectRelease(service) }

        var name = device
        var interconnect = ""
        var isInternal = false
        var props: Unmanaged<CFMutableDictionary>?
        if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
           let dict = props?.takeRetainedValue() as? [String: Any] {
            if let characteristics = dict["Device Characteristics"] as? [String: Any],
               let product = characteristics["Product Name"] as? String {
                name = product.trimmingCharacters(in: .whitespaces)
            }
            if let proto = dict["Protocol Characteristics"] as? [String: Any] {
                interconnect = (proto["Physical Interconnect"] as? String) ?? ""
                isInternal = (proto["Physical Interconnect Location"] as? String) == "Internal"
            }
        }

        var data = MEXNVMeSMART()
        let ok = mex_read_nvme_smart(service, &data)
        return DiskHealth(
            deviceName: name,
            interconnect: interconnect,
            isInternal: isInternal,
            bsdName: device,
            smart: ok ? data : nil,
            unavailableReason: ok ? nil : L("Ce disque n'expose pas de donnees SMART. C'est le cas courant des boitiers USB, qui ne transmettent pas les commandes de diagnostic du disque qu'ils contiennent."))
    }

    /// Vrai si le disque qui porte ce volume rend effectivement des donnees
    /// SMART. Le resultat est retenu par disque : l'entree de menu est evaluee
    /// a chaque ouverture du menu contextuel, et la lecture, bien que breve,
    /// n'a pas a etre refaite.
    private static var supportCache: [String: Bool] = [:]

    static func isSupported(forVolumeAt url: URL) -> Bool {
        guard let device = wholeDiskName(for: url) else { return false }
        if let known = supportCache[device] { return known }
        let supported = read(forVolumeAt: url)?.hasSMART ?? false
        supportCache[device] = supported
        return supported
    }

    /// `/Volumes/X` -> `disk0`, en remontant de la tranche au disque entier.
    private static func wholeDiskName(for url: URL) -> String? {
        var fs = statfs()
        guard statfs(url.path, &fs) == 0 else { return nil }
        let from = withUnsafeBytes(of: fs.f_mntfromname) { raw -> String in
            String(cString: raw.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
        guard from.hasPrefix("/dev/disk") else { return nil }
        let node = String(from.dropFirst("/dev/".count))
        // disk4s2 -> disk4 ; un volume APFS synthetise (disk3s1s1) remonte de meme.
        guard let range = node.range(of: #"^disk\d+"#, options: .regularExpression) else { return nil }
        return String(node[range])
    }

    private static func service(forBSDName name: String) -> io_service_t? {
        guard let matching = IOBSDNameMatching(kIOMainPortDefault, 0, name) else { return nil }
        let media = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard media != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(media) }

        // Le media n'est pas le peripherique : on remonte jusqu'au premier
        // IOBlockStorageDevice, seul a vendre le client SMART.
        var current = media
        IOObjectRetain(current)
        for _ in 0..<8 {
            if IOObjectConformsTo(current, "IOBlockStorageDevice") != 0 { return current }
            var parent: io_registry_entry_t = 0
            let kr = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
            IOObjectRelease(current)
            guard kr == KERN_SUCCESS else { return nil }
            current = parent
        }
        IOObjectRelease(current)
        return nil
    }

    // MARK: - Lecture humaine

    /// Temperature en degres Celsius (le disque la rend en kelvins).
    var temperatureCelsius: Double? {
        guard let smart, smart.temperatureKelvin > 0 else { return nil }
        return Double(smart.temperatureKelvin) - 273.15
    }

    /// Les releves, dans l'ordre ou ils comptent pour un utilisateur.
    var measures: [Measure] {
        guard let smart else { return [] }
        var list: [Measure] = []

        list.append(Measure(
            label: L("Usure estimee"),
            value: "\(smart.percentageUsed) %",
            isAbnormal: smart.percentageUsed >= 90,
            explanation: L("Part de la duree de vie prevue par le fabricant deja consommee. 0 % correspond a un disque neuf, 100 % a la fin de la garantie d'endurance : le disque continue en general de fonctionner au-dela.")))

        if let temperature = temperatureCelsius {
            list.append(Measure(
                label: L("Temperature"),
                value: String(format: "%.0f °C", temperature),
                isAbnormal: temperature >= 70,
                explanation: L("Temperature relevee par le controleur. Au-dela de 70 °C, un disque ralentit volontairement pour se proteger.")))
        }

        if smart.availableSpareThreshold > 0 || smart.availableSpare > 0 {
            list.append(Measure(
                label: L("Blocs de rechange disponibles"),
                value: "\(smart.availableSpare) %",
                isAbnormal: smart.availableSpare < smart.availableSpareThreshold,
                explanation: L("Reserve de blocs memoire gardee pour remplacer ceux qui s'usent. Passer sous le seuil du fabricant (%d %%) annonce une fin de vie proche.", Int(smart.availableSpareThreshold))))
        }

        list.append(Measure(
            label: L("Heures de fonctionnement"),
            value: L("%@ h", Fmt.decimal(smart.powerOnHours)),
            isAbnormal: false,
            explanation: L("Duree totale pendant laquelle le disque a ete alimente.")))

        list.append(Measure(
            label: L("Demarrages"),
            value: Fmt.decimal(smart.powerCycles),
            isAbnormal: false,
            explanation: L("Nombre de mises sous tension du disque.")))

        list.append(Measure(
            label: L("Arrets brutaux"),
            value: Fmt.decimal(smart.unsafeShutdowns),
            isAbnormal: false,
            explanation: L("Coupures d'alimentation sans arret propre. Quelques-unes sont normales ; beaucoup exposent a des pertes de donnees.")))

        list.append(Measure(
            label: L("Erreurs du support"),
            value: Fmt.decimal(smart.mediaErrors),
            isAbnormal: smart.mediaErrors > 0,
            explanation: L("Erreurs de lecture ou d'ecriture que le disque n'a pas pu corriger. Toute valeur superieure a zero merite une sauvegarde immediate.")))

        list.append(Measure(
            label: L("Entrees au journal d'erreurs"),
            value: Fmt.decimal(smart.errorLogEntries),
            isAbnormal: false,
            explanation: L("Nombre d'evenements inscrits au journal interne du disque depuis sa fabrication. Une valeur elevee n'est pas alarmante en soi.")))

        list.append(Measure(
            label: L("Donnees ecrites"),
            value: Fmt.size(Int64(smart.dataUnitsWritten) * 512_000),
            isAbnormal: false,
            explanation: L("Volume total ecrit sur le disque depuis sa fabrication, compte par unites de 512 Ko.")))

        list.append(Measure(
            label: L("Donnees lues"),
            value: Fmt.size(Int64(smart.dataUnitsRead) * 512_000),
            isAbnormal: false,
            explanation: L("Volume total lu depuis le disque depuis sa fabrication.")))

        return list
    }

    /// Alertes critiques remontees par le disque lui-meme.
    var criticalWarnings: [String] {
        guard let smart, smart.criticalWarning != 0 else { return [] }
        var warnings: [String] = []
        let bits: [(UInt8, String)] = [
            (0x01, L("La reserve de blocs de rechange est passee sous le seuil du fabricant.")),
            (0x02, L("Le disque signale une temperature hors de sa plage de fonctionnement.")),
            (0x04, L("Le disque signale une fiabilite degradee.")),
            (0x08, L("Le disque est passe en lecture seule.")),
            (0x10, L("La memoire tampon de secours du disque est en defaut."))
        ]
        for (mask, text) in bits where smart.criticalWarning & mask != 0 { warnings.append(text) }
        return warnings
    }

    /// Verdict d'ensemble, celui qu'on lit en premier.
    var isHealthy: Bool {
        criticalWarnings.isEmpty && !measures.contains { $0.isAbnormal }
    }
}
