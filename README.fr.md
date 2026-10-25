# MExplorer

Explorateur de fichiers natif macOS qui reprend l'ergonomie de l'Explorateur de
Windows 11 (arborescence complete, onglets, barre de commandes, fil d'Ariane,
regroupement) tout en s'appuyant sur les services natifs du Finder (Coup d'oeil,
tags, alias, Spotlight, partage, services).

Ecrit en Swift 6, en AppKit pour les vues a fort volume (arborescence,
liste multi-colonnes, grille d'icones) et en SwiftUI pour les barres de
commandes, le fil d'Ariane et le volet de details. Aucune dependance tierce.

[![Build](https://github.com/brihx001/MExplorer/actions/workflows/build.yml/badge.svg)](https://github.com/brihx001/MExplorer/actions/workflows/build.yml)

**[English](README.md)** · **Francais**

**Derniere version : [v0.6.0](https://github.com/brihx001/MExplorer/releases/tag/v0.6.0)**
— renommage par lot, copies annulables, archives, occupation et doublons,
colonnes de droits Unix, et fenetres qui reviennent ou on les a laissees.

## Prerequis

- macOS 14 (Sonoma) ou plus recent ;
- Xcode installe dans `/Applications` (pour la toolchain Swift et le greffon de
  macros SwiftUI) ; il n'a pas besoin d'etre selectionne par `xcode-select` ;
- aucune dependance externe : le paquet ne tire aucun module tiers.

## Construire et lancer

```bash
./build.sh release
```

Le script compile avec Swift Package Manager, assemble `MExplorer.app`, puis
signe le bundle en ad-hoc avec les entitlements du bac a sable.

Deux contournements de toolchain sont appliques automatiquement par `build.sh`
(macOS 27 / Swift 6.4, sans Xcode selectionne) :

- le systeme de compilation par defaut de SwiftPM (`swiftbuild`) echoue avec les
  seuls Command Line Tools, meme sur un paquet vide (`Unknown error parsing
  property list`) : le script force `--build-system native` ;
- les macros SwiftUI (`@State`, `@Observable`...) sont fournies par un greffon
  livre uniquement avec Xcode : le script le pointe via `-plugin-path`.

Xcode doit donc etre installe dans `/Applications`, mais il n'a pas besoin
d'etre selectionne par `xcode-select`.

Puis :

```bash
open MExplorer.app
```

Pour une compilation de debogage : `./build.sh debug`.

## Bac a sable : lisez ceci en premier

L'application est construite **sandboxee**, prete pour l'App Store. macOS lui
interdit donc de lire vos fichiers tant que vous n'avez pas designe un dossier.

Au premier lancement, MExplorer propose d'autoriser **l'ensemble du disque** :
acceptez, puis choisissez le disque de demarrage dans le panneau systeme.
L'autorisation est conservee entre les lancements via un *security-scoped
bookmark*. La proposition ne revient pas une fois la racine autorisee, et le
bouton « Ne plus demander » la desactive definitivement.

Elle reste accessible ensuite par **MExplorer > Autoriser l'acces a tout le
disque...**, et la zone de fichiers affiche de toute facon un bouton
**Autoriser l'acces a ce dossier** chaque fois qu'un dossier n'est pas lisible.

Autoriser la racine ne contourne pas TCC : les dossiers proteges par macOS
(Bureau, Documents, Telechargements, photothèque) declenchent leur propre
demande au premier acces.

Vous pouvez ajouter ou retirer des dossiers autorises a tout moment dans
**Reglages > Acces**, ou via **MExplorer > Autoriser l'acces a un dossier...**
(Cmd Maj O).

Consequences du bac a sable, inherentes au choix « pret pour l'App Store » :

- le montage de volumes reseau (SMB/AFP) n'est pas possible depuis l'app ;
  les volumes deja montes par le Finder apparaissent et sont navigables ;
- la recherche Spotlight ne renvoie que ce qui est accessible a l'app ;
- l'ecriture de tags necessite que le fichier soit dans un dossier autorise.

Une soumission reelle a l'App Store demandera Xcode, un compte Apple Developer,
un identifiant d'app et une signature avec votre profil de distribution : la
structure du projet (entitlements, bookmarks, absence d'API privees) est prete
pour cela.

## Fonctionnalites

### Reprises de l'Explorateur Windows 11

- **Clic molette** : sur un dossier, dans la liste, la grille d'icones ou le
  volet de navigation, il l'ouvre dans un nouvel onglet **en arriere-plan**,
  comme un navigateur. Le nouvel onglet se signale deux secondes et demie par
  un contour d'accentuation, sans quoi rien ne montrerait qu'il est apparu.
  Sur un fichier, le clic molette ne fait rien.
- **Onglets** : creation, fermeture, duplication, « fermer les autres »,
  « fermer a droite », menu contextuel. Reordonnables par glisser-deposer, et
  **deplacables d'une fenetre a l'autre** : l'onglet emporte son historique et
  ses reglages, et la fenetre d'origine se ferme si c'etait son dernier onglet.
  Le menu contextuel propose aussi « Deplacer vers une nouvelle fenetre ».
- **Glisser-deposer avec les autres applications** : les fichiers sortent vers
  le Finder (ou toute application acceptant des URL de fichier) et y entrent de
  la meme facon, sur la liste, la barre laterale ou un onglet.
- **Deplacement de fichiers entre onglets** : lacher une selection sur un
  onglet la deplace dans son dossier (Option pour copier). Survoler un onglet
  pendant un glissement bascule dessus apres un court instant (onglet « a
  ressort »), ce qui permet de deposer dans la liste plutot que sur l'onglet.
- **Volet de navigation** : arborescence reelle et depliable a l'infini
  (Acces rapide, iCloud, Ce Mac, Emplacements, Tags, Recents, Corbeille).
  Le dossier courant est revele et selectionne dans l'arborescence reelle,
  meme quand on y arrive par un raccourci de l'acces rapide. Les dossiers
  deplies sont surveilles : une creation, une suppression ou un renommage, fait
  dans l'application ou ailleurs, apparait dans l'arborescence sans rien
  replier. Les volumes amovibles portent un bouton d'ejection. Le disque de
  demarrage n'est liste qu'une fois, sous « Ce Mac ».
- **Reglages** : langue de l'interface, theme clair/sombre/systeme, affichage
  des elements masques, des extensions de noms de fichiers, ouverture d'un
  seul clic, ouverture des dossiers dans un nouvel onglet, confirmation des
  suppressions definitives, reinitialisation des reglages d'affichage, et
  liste des dossiers autorises.
- **Liens et alias vers un dossier** : un lien symbolique ou un alias dont la
  cible est un dossier se comporte comme un dossier (navigation, tri avec les
  dossiers, « ouvrir dans un nouvel onglet »). C'est le cas du lien que
  OneDrive pose dans le dossier personnel : sans cela il partait au Finder,
  `isDirectory` decrivant le lien et non sa cible. L'arborescence laterale,
  elle, ne deplie que les vrais dossiers, pour qu'un lien vers un ancetre ne
  puisse pas s'ouvrir indefiniment.
- **Acces rapide** : une liste plate de raccourcis, sans chevron ni
  sous-arborescence (la hierarchie se deplie sous « Ce Mac »). Un dossier
  lache sur l'en-tete, ou entre deux favoris, devient un favori a la position
  du depot. Les menus contextuels de la barre laterale et de la zone de
  fichiers ajoutent et retirent egalement un dossier, l'entree proposee
  dependant de sa presence dans la liste.
- **Barre de commandes** : Nouveau, Couper, Copier, Coller, Renommer, Partager,
  Corbeille, Trier, Afficher, menu « ... ».
- **Renommage** : F2, le menu contextuel, le bouton de la barre de commandes,
  ou **deux clics lents** sur le nom d'un element deja selectionne, comme le
  Finder. Le delai depasse l'intervalle de double-clic du systeme, et tout
  autre evenement (clic, touche, defilement, menu contextuel, glissement)
  annule. En mode icones, seul un clic sur le nom arme le renommage, pas sur
  l'icone ; en mode Details, seule la colonne Nom.
- **Conflit de nom** : copier ou deplacer un element vers un dossier qui en
  contient deja un du meme nom propose de **conserver les deux**, de
  **remplacer** ou d'**annuler**, comme le Finder. Le remplacement passe par un
  nom temporaire puis un echange atomique : l'element existant n'est detruit
  qu'une fois le nouveau en place. Il n'est pas annulable, l'ancien contenu
  n'existant plus.
- **Barre d'adresse** : boutons Precedent / Suivant / Parent / Actualiser,
  fil d'Ariane cliquable avec menu de sous-dossiers sur chaque chevron,
  bascule en champ de saisie de chemin (Cmd L), champ de recherche.
- **8 modes d'affichage** : Tres grandes / Grandes / Moyennes / Petites icones,
  Liste, Details, Mosaiques, Contenu.
- **Details multi-colonnes** : Nom, Modifie le, Type, Taille, Cree le,
  Ajoute le, Tags, Extension, Chemin. Colonnes redimensionnables, reordonnables,
  triables par clic sur l'en-tete (un second clic inverse le sens), activables
  par clic droit sur l'en-tete. Largeurs memorisees par dossier. Un
  **double-clic sur un separateur de colonnes** l'ajuste au plus large de ses
  contenus, comme dans un tableur.
- **Taille reelle des dossiers** : calculee en tache de fond, un dossier a la
  fois, affichee au fur et a mesure en mode Details et memorisee tant que le
  dossier n'a pas change. Le **tri par taille s'appuie dessus** : dossiers et
  fichiers sont alors intercales selon leur taille reelle, et l'ordre suit les
  valeurs qui arrivent. Le calcul se declenche aussi hors du mode Details des
  que le tri en depend. Desactive via Afficher > Calculer la taille des
  dossiers, le tri regroupe a nouveau les dossiers en tete : ils n'ont plus de
  taille a comparer.
- **Regroupement** : aucun, nom, type, taille, date de modification, tags,
  avec en-tetes repliables. Le regroupement par taille s'appuie lui aussi sur
  la taille calculee des dossiers : un dossier rejoint alors la tranche qui lui
  correspond au lieu d'un groupe a part, et retrouve le groupe « Dossiers »
  quand le calcul est desactive.
- **Tri par date** : fichiers et dossiers sont intercales. L'option « Dossiers
  en premier » ne s'applique pas aux colonnes de date, ou elle masquerait
  justement ce que l'on cherche a voir.
- **Reglages d'affichage par dossier**, plus « Appliquer a tous les dossiers ».
- **Elements masques** : bascule globale (Afficher > Elements masques,
  Presentation > Elements masques, ou le menu contextuel). Volontairement
  globale et non par dossier, comme dans le Finder et dans l'Explorateur :
  un reglage par dossier donnait l'impression que l'option ne tenait pas.
- **Barre d'etat** : nombre d'elements et poids cumule a gauche, resume de la
  selection, progression des operations longues, puis a droite une **jauge de
  remplissage du volume courant** (du vert au rouge selon le taux d'occupation,
  detail complet en infobulle) et les bascules d'affichage. Le poids cumule se
  termine par des points de suspension tant que des tailles de dossiers restent
  a calculer.
- **Volet de details** et **volet d'apercu** a droite, dont la visibilite est
  memorisee entre les lancements.
- **Semantique Couper / Coller** de Windows : les elements coupes sont grises
  jusqu'au collage, qui les deplace.
- Suppression via **Suppr** (corbeille) et **Maj Suppr** (definitive),
  renommage via **F2**, actualisation via **F5**.

- **Renommage par lot** : remplacement de texte, prefixe, suffixe,
  numerotation, changement de casse. L'apercu montre les noms proposes au fur
  et a mesure de la saisie, et les collisions sont signalees en rouge, dans le
  lot comme avec ce qui est deja sur le disque.
- **Copies annulables**, avec progression en octets. `copyfile(3)` rend compte
  tous les mega-octets et accepte qu'on l'arrete, la ou `FileManager.copyItem`
  ne rend la main qu'une fois le fichier entier copie. Le drapeau
  `COPYFILE_CLONE` garde le chemin rapide : au sein d'un volume APFS la copie
  reste un clone instantane et aucun octet ne circule.
- **Deplacer vers / Copier vers**, avec les favoris de l'acces rapide, les dix
  dernieres destinations et un selecteur de dossier.
- **Conflits de nom** tranches element par element, avec « Ignorer » et une
  case « Appliquer aux N elements suivants », comme le Finder.
- **Archives** : ouvrir comme un dossier, extraire ici, extraire ailleurs.
  .zip, .tar et les tar compresses.
- **Saisie rapide** dans la grille d'icones aussi, et plus seulement en liste.
- **Inverser la selection** et **selectionner par motif**, avec les jokers du
  shell.
- **Copier sous la forme** d'un nom ou d'une URL de fichier, a cote du chemin
  POSIX.
- **Ouvrir dans le Terminal** : Terminal.app, iTerm, Warp, Hyper, kitty,
  WezTerm et Ghostty sont cherches a chaque ouverture du menu.
- **Sommes de controle** (SHA-256, SHA-1, MD5), comparees a une valeur collee.
- **Occupation du dossier** : ce qui pese, les cinquante plus gros fichiers et
  les doublons, en un seul parcours annulable.
- **Dossiers frequents** dans la barre laterale, des la troisieme visite.
- **Permissions POSIX editables** dans la fenetre d'informations, sans toucher
  aux bits d'execution.
- **Pastilles** sur les icones : alias, lien symbolique, verrou.
- **Colonne iCloud**, lue a la demande pour ne pas ralentir le chargement.
- **Toujours ouvrir avec**, pour tous les fichiers de meme type.
- **Completion de chemin** a la tabulation, et historique au clic maintenu sur
  Precedent ou Suivant.
- **Barre de commandes personnalisable** : quels boutons, dans quel ordre.
- **Toutes les fenetres** sont rouvertes au lancement, chacune avec ses onglets.

### Services natifs du Finder

- **Coup d'oeil** (barre d'espace) avec animation depuis la vignette, et
  vignettes QuickLookThumbnailing dans les modes icones.
- **Tags Finder** : lecture, ecriture, pastilles colorees dans la liste,
  section Tags dans la barre laterale, recherche par tag.
- **Alias** : creation, resolution, « Coller un raccourci ».
- **Corbeille** : mise a la corbeille annulable (Cmd Z), vidage. Accessible par
  le menu, la barre de commandes, la touche Suppr, un depot sur la Corbeille de
  la barre laterale ou sur celle du Dock. Tous ces chemins passent par
  `NSWorkspace.recycle`, donc « Remettre » reste disponible dans le Finder.
- **Recherche Spotlight** en direct (NSMetadataQuery) sur le nom et le contenu,
  limitee au dossier courant ou etendue au Mac.
- **Ouvrir avec** (applications proposees par LaunchServices), **Partager**
  (NSSharingServicePicker), **menu Services** de macOS.
- **Compression** en .zip via NSFileCoordinator (compatible bac a sable).
- **Fenetre Proprietes** : taille recursive, dates, autorisations POSIX,
  proprietaire, tags editables, applications associees.
- **Annulation** (Cmd Z) sur renommage, deplacement, copie, duplication,
  creation et mise a la corbeille.
- **Volumes** : detection des montages/demontages, ejection d'un clic depuis la
  barre laterale ou par le menu contextuel.
- **Informations SMART** : le menu contextuel d'un disque propose « Voir les
  informations SMART... », qui ouvre une fenetre lisible — usure, temperature,
  blocs de rechange, heures de fonctionnement, demarrages, arrets brutaux,
  erreurs, volumes lus et ecrits. Une icone d'alerte signale les valeurs hors
  plage, et un « i » survole explique chaque releve. L'entree n'apparait que
  pour les disques qui rendent vraiment ces donnees.
- **Informations du support** : pour une carte memoire, le menu propose « Voir
  les informations du support... ». Une carte ne rend aucune donnee SMART, et
  la fenetre affiche a la place ce qu'elle publie sur elle-meme : fabricant,
  revision, numero de serie, date de fabrication, classe de vitesse, capacite,
  protection en ecriture.
- **A propos** : affiche la date et l'heure de construction du binaire, posees
  par `build.sh` dans le bundle.
- **Recents** : les elements ouverts ou modifies depuis trente jours, par
  l'index Spotlight (`kMDItemLastUsedDate`, `kMDItemFSContentChangeDate`).
  La bibliotheque personnelle est ecartee : ses caches et ses journaux
  changent en permanence et noieraient les vrais documents.
- Rafraichissement automatique du dossier affiche (surveillance FSEvents).

## Raccourcis principaux

| Action | Raccourci |
| --- | --- |
| Nouvel onglet / fenetre | Cmd T / Cmd N |
| Onglet suivant / precedent | Cmd Alt Droite / Gauche |
| Precedent / Suivant | Cmd [ / Cmd ] |
| Dossier parent | Cmd Haut |
| Ouvrir | Entree ou Cmd Bas |
| Saisir un chemin | Cmd L |
| Rechercher | Cmd F |
| Nouveau dossier | Cmd Maj N |
| Renommer | F2 |
| Corbeille / suppression definitive | Suppr / Maj Suppr |
| Coup d'oeil | Espace |
| Informations | Cmd I |
| Modes d'affichage | Cmd 1 a Cmd 8 |
| Volet de navigation | Cmd Ctrl S |
| Volet de details | Cmd Maj P |
| Elements masques | Cmd Maj . |

La liste complete est dans **Aide > Raccourcis clavier**.

## Organisation du code

```
Sources/MExplorer/
  App/         point d'entree, delegue, barre de menus, fenetre
  Model/       systeme de fichiers, onglets, tri, tags, presse-papiers, sandbox
  Views/       barre laterale, liste, grille, barres SwiftUI, fenetres annexes
  Support/     formateurs, cache d'icones, menus a closures
Packaging/     Info.plist, entitlements et icone
Packaging/Icon/make-icon.swift   generateur de l'icone (dessin vectoriel)
build.sh       compilation + assemblage + signature du bundle
```

Points structurants :

- `TabState` porte tout l'etat d'un onglet (emplacement, historique, contenu,
  tri, selection) ; `WindowModel` est le point d'entree unique des commandes.
- `AccessManager` gere les autorisations sandbox et leurs bookmarks.
- Rien de lent ne touche le thread principal : chargement de dossier, taille
  recursive, tags, noms localises, icones specifiques, vignettes et sondage
  d'expansion de l'arborescence se font tous en tache de fond, puis
  rafraichissent la vue.

Six couts mesures sur ce Mac ont dicte l'architecture :

| Appel | Cout mesure | Traitement |
| --- | --- | --- |
| `localizedName` sur un dossier protege par TCC | ~5 a 10 s par appel | `DisplayNameCache`, asynchrone et persistant |
| `tagNames` / `labelNumber` | un `getxattr` par fichier | seconde passe apres affichage |
| `isUbiquitousItem` / `ubiquitousItemDownloadingStatus` | 77 us par fichier, soit les deux tiers du chargement d'un dossier de 5 200 elements | lus a la demande, pour le seul element selectionne |
| `NSWorkspace.icon(forFile:)` | LaunchServices, blocage possible | icone generique immediate, specifique en differe |
| Contenu d'un menu SwiftUI | evalue **a chaque rendu** | `SubfolderCache`, jamais de lecture disque dans le menu |
| Taille d'un dossier | parcours recursif complet | `FolderSizeCalculator`, un dossier a la fois, annulable |

Trois pieges a corriger aussi : `removeTableColumn` efface les
`sortDescriptors` de la table. Comme les colonnes etaient reconstruites a chaque
changement de reglage, le second clic sur un en-tete repartait du prototype
ascendant au lieu d'inverser le tri. Les colonnes ne sont desormais recreees que
si leur composition change reellement.

Deuxieme piege : la Corbeille du Dock n'accepte un depot que si la source a
declare l'operation `NSDragOperation.delete`. Sans elle, y lacher un fichier ne
declenche strictement rien. La vue source doit en plus implementer
`draggingSession(_:endedAt:operation:)` pour effectuer la mise a la corbeille
elle-meme : le Dock se contente de signaler le geste.

Et cote SwiftUI : demander le focus a un `TextField` dans le meme tour de boucle
que son apparition ne fonctionne pas, le champ n'existant pas encore. La saisie
de Cmd-L partait alors dans le champ de recherche. Le focus est maintenant
demande au tour suivant.

Deux pieges Quick Look valent d'etre notes :

- une requete de vignette sur un paquet protege (`Photos Library.photoslibrary`)
  ne recoit jamais de reponse et bloque la connexion QuickLook de tout le
  processus ; les paquets sont donc exclus des demandes de vignette ;
- `QLThumbnailGenerator` abandonne silencieusement les requetes au-dela de
  quelques demandes simultanees : elles sont mises en file, quatre a la fois,
  avec un chien de garde.

## Autorisations de confidentialite et signature

macOS demande son accord a l'utilisateur avant qu'une application touche
certaines zones : volumes amovibles, volumes reseau, Bureau, Documents,
Telechargements. Ces accords sont enregistres par TCC **contre l'identite de
code** de l'application, pas contre son chemin ni son identifiant seul.

Une signature **ad-hoc** n'a pas de certificat : l'identite s'y reduit a
l'empreinte du binaire, qui change a chaque reconstruction. Mesure faite sur
ce Mac : apres avoir accorde l'acces au volume amovible, il a suffi de rebatir
l'application avec un numero de build different pour que macOS redemande
l'autorisation - celle du volume amovible, puis celle des Telechargements,
puis celle du Bureau. Autrement dit, **chaque mise a jour efface toutes les
autorisations deja donnees**.

Signer avec un certificat stable lie l'autorisation au certificat et non au
binaire. Un certificat *Apple Development*, gratuit avec un compte Apple,
suffit pour son propre Mac :

```bash
security find-identity -v -p codesigning        # relever l'identite
echo 'Apple Development: moi@exemple.fr (XXXXXXXXXX)' > .signing-identity
./build.sh release
```

`build.sh` lit `MEXPLORER_SIGN_IDENTITY`, sinon le fichier `.signing-identity`
(local, ignore par git), sinon signe en ad-hoc. La premiere signature demande
le mot de passe du trousseau pour autoriser `codesign` a utiliser la clef
privee ; repondre **Toujours autoriser** evite que la question revienne.

Les artefacts publies dans les *releases* restent signes en ad-hoc : un
certificat de developpement ne vaut que pour la machine qui l'a emis, et
Gatekeeper le refuserait ailleurs. Seuls un *Developer ID* et une notarisation
y changeraient quelque chose.

## Donnees SMART et bac a sable

Le client SMART d'IOKit est ferme aux applications en bac a sable : l'ouvrir
repond `kIOReturnNotPermitted`, et `diskutil` lance depuis l'application rend
« Not Supported » la ou le meme appel hors bac a sable rend « Verified ».

`Packaging/MExplorer.entitlements` porte donc l'exception temporaire
`com.apple.security.temporary-exception.iokit-user-client-class`
(`AppleNVMeSMARTUserClient`, `AppleSATLSMARTUserClient`), qui rouvre ce seul
client. Mesure faite sur ce Mac : sans elle, aucune donnee ; avec elle, le
journal SMART complet du disque interne.

L'en-tete `<IOKit/storage/nvme/NVMeSMARTLibExternal.h>` n'etant pas expose au
module Swift, un petit module C (`Sources/CSmart`) l'inclut et rend la lecture
sous forme de structure plate.

Deux dialectes sont lus :

- le **journal SMART NVMe** des disques internes recents : usure, temperature,
  blocs de rechange, heures, demarrages, arrets brutaux, erreurs du support ;
- la **table d'attributs ATA** des disques SATA et des boitiers USB qui
  traduisent les commandes ATA (SAT) : secteurs realloues, secteurs en attente,
  secteurs non corrigibles, erreurs non corrigees, temperature, heures,
  demarrages, erreurs de transmission, vie restante. Les attributs portent des
  identifiants normalises ; seuls ceux qui parlent a un utilisateur sont
  presentes, les autres restent caches sauf s'ils franchissent le seuil du
  fabricant, auquel cas ils apparaissent avec leur numero.

Un attribut est signale anormal quand sa valeur normalisee tombe au seuil du
fabricant, et pour les compteurs de secteurs defectueux des qu'ils depassent
zero.

Une limite tient au materiel : un boitier USB ne transmet pas toujours les
commandes de diagnostic au disque qu'il contient. Le Crucial X9 de test est
dans ce cas, et l'entree de menu n'apparait pas pour lui.

### Cartes memoire

Une carte SD n'a pas de SMART, et n'en aura pas : SMART est un jeu de commandes
ATA (T13) et NVMe, que la norme de la SD Association ne reprend pas. Une carte
expose ses registres CID et CSD — identite, capacite, classes de vitesse — mais
aucun attribut de sante : ni heures de service, ni cycles d'ecriture, ni blocs
de rechange. Les commandes vendeur qui, sur certaines cartes industrielles,
rendent une estimation d'usure passent par CMD56, que macOS n'ouvre a aucune
API publique. L'eMMC, lui, porte bien un champ d'usure normalise dans son
`EXT_CSD` ; ce n'est pas du SMART non plus, et le SD ne l'a pas.

MExplorer reconnait une carte a son bus (« Secure Digital »), au dictionnaire
`Card Characteristics` que publie le pilote du lecteur, ou a la classe
`IOSDHCIBlockDevice`. Il affiche alors l'identite de la carte et la capacite et
le verrou d'ecriture lus sur son objet `IOMedia`, sous une phrase qui dit
pourquoi aucun releve de sante ne suit. Les cles du dictionnaire dependant du
lecteur, celles qui ne sont pas reconnues sont publiees telles quelles plutot
que perdues.

Ce chemin n'a pas pu etre eprouve sur une vraie carte : le Mac de
developpement est un MacBook Pro 13" M1, sans lecteur SD, et aucun lecteur USB
n'etait disponible. Il a ete verifie en forcant le chemin « carte » sur un
disque externe : fenetre, tableau, infobulles et repli sur les cles inconnues
se comportent comme prevu.

## Performances

Deux mesures faites sur un dossier de 5 200 elements, avant et apres le
degraissage du jeu de clefs de chargement :

| | Avant | Apres |
| --- | --- | --- |
| Lecture du dossier (listing + valeurs) | 0,655 s | 0,200 s |
| Memoire ajoutee par le dossier | 25,3 Mo | 13,7 Mo |

Le gain vient de trois clefs retirees du chargement : l'etat iCloud, qui
coutait a lui seul les deux tiers du temps et ne sert qu'au volet de details,
et les capacites de volume, lues par fichier alors qu'elles decrivent le
disque. S'y ajoutent les libelles de type partages entre fichiers de meme
nature, et un cache de vignettes borne en octets (64 Mo) plutot qu'en nombre :
1 500 vignettes Retina auraient pu depasser le demi-gigaoctet.

## Langues et apparence

L'interface suit la langue du Mac au premier lancement, et se change dans
**Reglages > General > Langue** : *Langue du systeme*, *Francais* ou
*English*. Le changement s'applique immediatement, sans redemarrer.

Les libelles sont ecrits en francais dans le code et le francais sert de cle :
`Support/EnglishStrings.swift` fournit la table anglaise, et une cle absente
retombe sur le francais. Ajouter une langue tient donc en un fichier de meme
forme, une entree dans `AppLanguage` et une ligne dans `L10n.apply`.

Deux details valent d'etre connus :

- `Packaging/Info.plist` declare `CFBundleLocalizations` (`fr`, `en`). Sans
  cette liste, macOS considere l'application comme non localisee et fournit
  ses propres libelles (type d'un fichier, panneaux systeme) dans la region de
  developpement, donc en francais meme sur un Mac en anglais.
- Ces libelles-la suivent la langue du **systeme**, pas le reglage de
  l'application : choisir le francais sur un Mac en anglais laisse la colonne
  Type en anglais.

Les **dates** suivent elles aussi le systeme, mais deliberement : elles
reprennent le format regle dans *Reglages systeme > Langue et region*, celui
que vous voyez partout ailleurs sur votre Mac, quelle que soit la langue
choisie dans l'application.

Le **theme** se regle dans **Reglages > General > Theme** : *Theme du systeme*,
*Clair* ou *Sombre*. Il s'applique immediatement a toutes les fenetres. Laisse
sur *Theme du systeme*, l'application suit macOS, y compris si l'apparence
bascule en cours de journee.

## Icone

L'icone est dessinee par programme, a chaque taille, par
`Packaging/Icon/make-icon.swift` : un dossier a onglets dont la face avant porte
une arborescence, les deux traits distinctifs de l'application. Le dessin est
simplifie en petite taille (deux branches a 32 points, aucune a 16) car des
traits fins s'y confondent en une tache.

Pour la regenerer :

```bash
cd Packaging/Icon && swift make-icon.swift . && iconutil --convert icns --output ../AppIcon.icns AppIcon.iconset
```

## Limites actuelles

- Les favoris de l'Acces rapide s'ajoutent par glisser-deposer, mais un favori
  deja present ne se deplace pas dans la liste par ce moyen.
- Pas de « Remettre » depuis la corbeille (l'emplacement d'origine n'est pas
  accessible sous bac a sable).
- La restauration de session ne retablit qu'une fenetre.
- La selection par lasso n'existe que dans les modes icones (limite de
  NSTableView en mode Details).
- Les paquets (`.app`, `.photoslibrary`) n'ont pas de vignette Quick Look :
  ils gardent leur icone, pour la raison expliquee plus haut.
- Les fichiers tres volumineux dont QuickLook echoue a produire une vignette
  gardent l'icone generique de leur type.
- Le calcul des tailles de dossiers est partage par toutes les fenetres : le
  dernier dossier affiche prend la main sur la file d'attente.
- Une taille memorisee est recalculee quand le dossier lui-meme change, pas
  quand un fichier change au fond de son arborescence.

## Contribuer

Les rapports de bugs et les propositions sont les bienvenus dans les
*issues*. Pour une correction, ouvrez une *pull request* sur `main` :
`./build.sh release` doit passer, et la convention du code est celle des
fichiers voisins (commentaires en francais sans accents, un fichier par
responsabilite).

## Licence

MIT, voir [LICENSE](LICENSE).
