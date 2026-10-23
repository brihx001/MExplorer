#include "include/CSmart.h"
#include <IOKit/storage/nvme/NVMeSMARTLibExternal.h>
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
