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

/// Un attribut SMART ATA, tel que les disques SATA et les boitiers USB qui
/// traduisent les commandes ATA (SAT) les rendent.
///
/// `current` et `worst` sont des valeurs normalisees par le fabricant, sans
/// unite, d'autant meilleures qu'elles sont hautes ; le disque se declare en
/// echec des que `current` descend a `threshold`. `raw` porte la mesure brute,
/// dont le sens depend de l'attribut (heures, nombre de secteurs, degres).
typedef struct {
    uint8_t  id;
    uint8_t  current;
    uint8_t  worst;
    uint8_t  threshold;
    uint64_t raw;          // 48 bits utiles
} MEXATAAttribute;

#define MEX_ATA_ATTRIBUTE_MAX 30

typedef struct {
    bool     thresholdExceeded;   // verdict rendu par le disque lui-meme
    uint32_t attributeCount;
    MEXATAAttribute attributes[MEX_ATA_ATTRIBUTE_MAX];
} MEXATASMART;

/// Lit la table d'attributs SMART d'un disque ATA / SAT.
bool mex_read_ata_smart(io_service_t device, MEXATASMART *out);

#endif
