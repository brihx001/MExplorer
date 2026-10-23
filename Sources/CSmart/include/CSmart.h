// Passerelle vers la bibliotheque SMART d'IOKit.
//
// L'en-tete <IOKit/storage/nvme/NVMeSMARTLibExternal.h> n'est pas expose par
// le module IOKit cote Swift : ce petit module C l'inclut et rend la lecture
// sous la forme d'une structure plate.
#ifndef CSMART_H
#define CSMART_H

#include <IOKit/IOKitLib.h>
#include <stdbool.h>
#include <stdint.h>

/// Journal SMART d'un disque NVMe, tel que le controleur le rend.
typedef struct {
    uint8_t  criticalWarning;       // champ de bits, 0 = rien a signaler
    uint16_t temperatureKelvin;
    uint8_t  availableSpare;        // %
    uint8_t  availableSpareThreshold;
    uint8_t  percentageUsed;        // usure estimee, %
    uint64_t dataUnitsRead;         // unites de 512 Ko
    uint64_t dataUnitsWritten;
    uint64_t powerCycles;
    uint64_t powerOnHours;
    uint64_t unsafeShutdowns;
    uint64_t mediaErrors;
    uint64_t errorLogEntries;
} MEXNVMeSMART;

/// Lit le journal SMART du peripherique IOKit donne.
/// Renvoie false si le peripherique n'expose pas SMART ou si la lecture echoue.
bool mex_read_nvme_smart(io_service_t device, MEXNVMeSMART *out);

#endif
