# MExplorer

Explorateur de fichiers natif macOS qui reprend l'ergonomie de l'Explorateur de
Windows 11 (arborescence complete, onglets, barre de commandes, fil d'Ariane,
regroupement) tout en s'appuyant sur les services natifs du Finder (Coup d'oeil,
tags, alias, Spotlight, partage, services).

Ecrit en Swift 6, en AppKit pour les vues a fort volume (arborescence,
liste multi-colonnes, grille d'icones) et en SwiftUI pour les barres de
commandes, le fil d'Ariane et le volet de details.

[![Build](https://github.com/brihx001/MExplorer/actions/workflows/build.yml/badge.svg)](https://github.com/brihx001/MExplorer/actions/workflows/build.yml)

**[English](#in-english)** · **[Francais](#en-francais)**

## In English

A native macOS file explorer with the ergonomics of the Windows 11 Explorer
(full folder tree, tabs, command bar, breadcrumb, grouping), built on the
Finder's own services (Quick Look, tags, aliases, Spotlight, sharing,
services).

Written in Swift 6: AppKit for the high-volume views (tree, multi-column list,
icon grid), SwiftUI for the bars and panels. No third-party dependency.

### Requirements

macOS 14 (Sonoma) or newer. To build it, Xcode must be installed in
`/Applications` for the Swift toolchain and the SwiftUI macro plugin, but it
does not need to be selected with `xcode-select`.

### Build and run

```bash
./build.sh release
open MExplorer.app
```

The script builds with Swift Package Manager, assembles `MExplorer.app` and
signs it ad-hoc with the sandbox entitlements. It applies two toolchain
workarounds on its own: SwiftPM's default build system fails with the Command
Line Tools alone, so `--build-system native` is forced; and the SwiftUI macros
plugin ships only with Xcode, so the script points at it with `-plugin-path`.

A signed build is also attached to every
[release](https://github.com/brihx001/MExplorer/releases). It is ad-hoc signed
and **not notarized**, so macOS quarantines the downloaded file and refuses to
open it; clear the quarantine first:

```bash
xattr -dr com.apple.quarantine /Applications/MExplorer.app
```

### Sandbox: read this first

The application is built **sandboxed**, App Store ready, so macOS forbids it to
read your files until you point it at a folder.

On first launch it offers to grant access to the **whole disk**: accept, then
pick the startup disk in the system panel. The permission is kept between
launches through a security-scoped bookmark, the prompt does not come back once
the root is granted, and a *Don't ask again* button disables it for good. It
stays reachable from **MExplorer > Allow access to the whole disk...**, and the
file area shows an **Allow access to this folder** button whenever a folder is
not readable.

Granting the root does not bypass TCC: folders protected by macOS (Desktop,
Documents, Downloads, the photo library) ask for their own permission on first
access.

### What it does

- **SMART information** for disks that expose it: wear, temperature, spare
  blocks, power-on hours, power cycles, unsafe shutdowns, errors, data read and
  written, with a warning icon on out-of-range values and an explanation behind
  each info marker. Reaching the IOKit SMART client from the sandbox needs the
  `iokit-user-client-class` temporary exception, which the entitlements declare;
  USB enclosures usually pass no SMART through at all, and the menu entry then
  stays hidden.
- **Double-click a column separator** in the details view to fit the column to
  its widest content, as in a spreadsheet.
- **Middle click** on a folder opens it in a **background** tab, as a browser
  does; the new tab marks itself with an accent outline for a couple of
  seconds. On a file it does nothing.
- **Links and aliases to a folder** behave like folders: navigating, sorting
  with the folders, *open in a new tab*. That covers the link OneDrive leaves
  in the home folder, which used to be handed over to the Finder because
  `isDirectory` describes the link, not its target. The navigation tree still
  expands real folders only, so a link pointing at an ancestor cannot be
  expanded forever.
- **Full navigation pane**: quick access, iCloud, This Mac, mounted volumes,
  tags, Recents, Trash. The current folder is revealed and selected in the real
  tree. Expanded folders are watched, so a creation, deletion or rename — made
  in the application or anywhere else — shows up without collapsing anything.
  Removable volumes carry an eject button.
- **Tabs**, reorderable, draggable between windows, with spring-loading when
  you hover one while dragging files. A **middle click** on a folder — in the
  list, the icon grid or the navigation pane — opens it in a new tab; on a file
  it does nothing.
- **Eight view modes**, from extra large icons to a multi-column details list
  with sortable, resizable, reorderable columns whose widths are remembered per
  folder.
- **Real folder sizes**, computed in the background, one folder at a time, and
  cached until the folder changes. Sorting by size uses them: folders and files
  are then interleaved by their actual size, and the order follows the values
  as they arrive. The computation also runs outside the details view when the
  sort depends on it. Switched off from *View > Compute folder sizes*, folders
  go back to being grouped first, since they then have no size to compare.
- **Sorting, grouping, filtering**, with collapsible group headers. Grouping by
  size uses the computed folder sizes too, so a folder lands in a size bucket
  rather than in a group of its own; without the computation it goes back to a
  *Folders* group.
- **File operations**: cut, copy, paste, rename, duplicate, alias, compress,
  trash, permanent deletion, undo. A name conflict offers to keep both, replace
  or cancel, like the Finder.
- **Rename** with F2, the context menu, the command bar, or two slow clicks on
  the name.
- **Finder services**: Quick Look, Get Info, tags, aliases, favourites,
  Spotlight search, network volumes, Open With, Services, Share.
- **Status bar**: item count, total size of the displayed items, and a fill
  gauge for the current volume.
- **Settings**: interface language, light/dark/system theme, hidden items, file
  name extensions, single-click opening, folders in a new tab, confirmation of
  permanent deletions, and the list of granted folders.

### Languages and appearance

The interface follows the Mac's language on first launch and can be changed in
**Settings > General > Language** (system, French, English); the change applies
immediately. Dates always follow the **system** format, not the application
language, so they match what you see everywhere else on your Mac.

The light/dark theme is set in **Settings > General > Theme** and defaults to
the system setting.

### Privacy permissions and signing

macOS records privacy approvals (removable volumes, network volumes, Desktop,
Documents, Downloads) against the application's **code identity**. An ad-hoc
signature has no certificate, so that identity is the binary's own hash: it
changes with every rebuild, and every update silently discards the approvals
already granted — measured here, a changed build number was enough to be asked
again for the removable volume, then the Downloads folder, then the Desktop.

Signing with a stable certificate ties the approval to the certificate instead.
An *Apple Development* certificate, free with an Apple account, is enough for
your own Mac:

```bash
security find-identity -v -p codesigning
echo 'Apple Development: me@example.com (XXXXXXXXXX)' > .signing-identity
./build.sh release
```

`build.sh` reads `MEXPLORER_SIGN_IDENTITY`, falls back to the `.signing-identity`
file (local, git-ignored), and signs ad-hoc otherwise. Released binaries stay
ad-hoc signed: a development certificate is worthless on another Mac.

### Known limitations

- A favourite already in the quick access list cannot be reordered by dragging.
- No *Put Back* from the Trash: the original location is not reachable under the
  sandbox.
- Session restore reopens a single window.
- Rubber-band selection exists only in the icon views.
- Packages (`.app`, `.photoslibrary`) keep their icon instead of a Quick Look
  thumbnail.
- Labels provided by macOS itself (a file's kind, system panels) follow the
  **system** language, not the application setting.

### Licence

MIT, see [LICENSE](LICENSE).

---

## En francais

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

Quatre couts mesures sur ce Mac ont dicte l'architecture :

| Appel | Cout mesure | Traitement |
| --- | --- | --- |
| `localizedName` sur un dossier protege par TCC | ~5 a 10 s par appel | `DisplayNameCache`, asynchrone et persistant |
| `tagNames` / `labelNumber` | un `getxattr` par fichier | seconde passe apres affichage |
| `isUbiquitousItem` / `ubiquitousItemDownloadingStatus` | 77 us par fichier, soit les deux tiers du chargement d'un dossier de 5 200 elements | lus a la demande, pour le seul element selectionne |
| `NSWorkspace.icon(forFile:)` | LaunchServices, blocage possible | icone generique immediate, specifique en differe |
| Contenu d'un menu SwiftUI | evalue **a chaque rendu** | `SubfolderCache`, jamais de lecture disque dans le menu |
| Taille d'un dossier | parcours recursif complet | `FolderSizeCalculator`, un dossier a la fois, annulable |

Trois pieges AppKit a corriger aussi : `removeTableColumn` efface les
`sortDescriptors` de la table. Comme les colonnes etaient reconstruites a chaque
changement de reglage, le second clic sur un en-tete repartait du prototype
ascendant au lieu d'inverser le tri. Les colonnes ne sont desormais recreees que
si leur composition change reellement.

Troisieme piege : la Corbeille du Dock n'accepte un depot que si la source a
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

Deux limites tiennent au materiel, pas au code :

- un boitier USB ne transmet en general pas les commandes de diagnostic au
  disque qu'il contient : le Crucial X9 de test repond « pas de SMART », et
  l'entree de menu n'apparait pas pour lui ;
- les attributs exposes sont ceux du journal SMART NVMe ; un disque SATA
  ancien n'en rend pas les memes.

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
