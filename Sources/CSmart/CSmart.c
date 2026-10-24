#include "include/CSmart.h"
#include <IOKit/storage/nvme/NVMeSMARTLibExternal.h>
#include <IOKit/storage/ata/ATASMARTLib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <string.h>

bool mex_read_nvme_smart(io_service_t device, MEXNVMeSMART *out)
{
    if (device == IO_OBJECT_NULL || out == NULL) { return false; }

    IOCFPlugInInterface **plugin = NULL;
    SInt32 score = 0;
    kern_return_t kr = IOCreatePlugInInterfaceForService(
        device, kIONVMeSMARTUserClientTypeID, kIOCFPlugInInterfaceID, &plugin, &score);
    if (kr != KERN_SUCCESS || plugin == NULL) { return false; }

    IONVMeSMARTInterface **interface = NULL;
    HRESULT hr = (*plugin)->QueryInterface(
        plugin, CFUUIDGetUUIDBytes(kIONVMeSMARTInterfaceID), (LPVOID *)&interface);
    if (hr != S_OK || interface == NULL) {
        IODestroyPlugInInterface(plugin);
        return false;
    }

    NVMeSMARTData data;
    memset(&data, 0, sizeof(data));
    IOReturn result = (*interface)->SMARTReadData(interface, &data);
    if (result == kIOReturnSuccess) {
        out->criticalWarning          = data.CRITICAL_WARNING;
        out->temperatureKelvin        = data.TEMPERATURE;
        out->availableSpare           = data.AVAILABLE_SPARE;
        out->availableSpareThreshold  = data.AVAILABLE_SPARE_THRESHOLD;
        out->percentageUsed           = data.PERCENTAGE_USED;
        // Les compteurs sont des entiers sur 128 bits ; les 64 bits de poids
        // faible suffisent largement a l'echelle d'un disque.
        out->dataUnitsRead    = data.DATA_UNITS_READ[0];
        out->dataUnitsWritten = data.DATA_UNITS_WRITTEN[0];
        out->powerCycles      = data.POWER_CYCLES[0];
        out->powerOnHours     = data.POWER_ON_HOURS[0];
        out->unsafeShutdowns  = data.UNSAFE_SHUTDOWNS[0];
        out->mediaErrors      = data.MEDIA_ERRORS[0];
        out->errorLogEntries  = data.NUM_ERROR_INFO_LOG_ENTRIES[0];
    }

    (*interface)->Release(interface);
    IODestroyPlugInInterface(plugin);
    return result == kIOReturnSuccess;
}

// MARK: - ATA / SAT

/// La structure rendue par SMARTReadData est le bloc de 512 octets defini par
/// la norme ATA : deux octets de revision, puis trente attributs de douze
/// octets. L'en-tete d'Apple ne modelise pas ce decoupage, on le fait ici.
static uint64_t mex_raw48(const uint8_t *bytes)
{
    uint64_t value = 0;
    for (int i = 5; i >= 0; i--) { value = (value << 8) | bytes[i]; }
    return value;
}

bool mex_read_ata_smart(io_service_t device, MEXATASMART *out)
{
    if (device == IO_OBJECT_NULL || out == NULL) { return false; }
    memset(out, 0, sizeof(*out));

    IOCFPlugInInterface **plugin = NULL;
    SInt32 score = 0;
    kern_return_t kr = IOCreatePlugInInterfaceForService(
        device, kIOATASMARTUserClientTypeID, kIOCFPlugInInterfaceID, &plugin, &score);
    if (kr != KERN_SUCCESS || plugin == NULL) { return false; }

    IOATASMARTInterface **interface = NULL;
    HRESULT hr = (*plugin)->QueryInterface(
        plugin, CFUUIDGetUUIDBytes(kIOATASMARTInterfaceID), (LPVOID *)&interface);
    if (hr != S_OK || interface == NULL) {
        IODestroyPlugInInterface(plugin);
        return false;
    }

    // Certains disques rendent des donnees vides tant que la collecte n'a pas
    // ete demandee ; l'echec n'est pas bloquant, la lecture suit.
    (*interface)->SMARTEnableDisableOperations(interface, true);

    Boolean exceeded = false;
    if ((*interface)->SMARTReturnStatus(interface, &exceeded) == kIOReturnSuccess) {
        out->thresholdExceeded = exceeded ? true : false;
    }

    ATASMARTData data;
    ATASMARTDataThresholds thresholds;
    memset(&data, 0, sizeof(data));
    memset(&thresholds, 0, sizeof(thresholds));

    IOReturn readResult = (*interface)->SMARTReadData(interface, &data);
    bool hasThresholds =
        (*interface)->SMARTReadDataThresholds(interface, &thresholds) == kIOReturnSuccess;

    if (readResult == kIOReturnSuccess) {
        const uint8_t *entries = data.vendorSpecific1 + 2;          // apres la revision
        const uint8_t *limits = thresholds.vendorSpecific1 + 2;
        for (int i = 0; i < MEX_ATA_ATTRIBUTE_MAX; i++) {
            const uint8_t *entry = entries + i * 12;
            if (entry[0] == 0) { continue; }                        // emplacement inutilise
            MEXATAAttribute *attribute = &out->attributes[out->attributeCount++];
            attribute->id = entry[0];
            attribute->current = entry[3];
            attribute->worst = entry[4];
            attribute->raw = mex_raw48(entry + 5);
            if (hasThresholds) {
                // Les seuils ne suivent pas forcement le meme ordre : on
                // cherche l'identifiant.
                for (int j = 0; j < MEX_ATA_ATTRIBUTE_MAX; j++) {
                    const uint8_t *limit = limits + j * 12;
                    if (limit[0] == attribute->id) { attribute->threshold = limit[1]; break; }
                }
            }
        }
    }

    (*interface)->Release(interface);
    IODestroyPlugInInterface(plugin);
    return readResult == kIOReturnSuccess && out->attributeCount > 0;
}
