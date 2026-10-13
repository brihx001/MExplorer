# MExplorer

Explorateur de fichiers natif macOS qui reprend l'ergonomie de l'Explorateur de
Windows 11 (arborescence complete, onglets, barre de commandes, fil d'Ariane,
regroupement) tout en s'appuyant sur les services natifs du Finder (Coup d'oeil,
tags, alias, Spotlight, partage, services).

Ecrit en Swift 6, en AppKit pour les vues a fort volume (arborescence,
liste multi-colonnes, grille d'icones) et en SwiftUI pour les barres de
commandes, le fil d'Ariane et le volet de details.

[![Build](https://github.com/brihx001/MExplorer/actions/workflows/build.yml/badge.svg)](https://github.com/brihx001/MExplorer/actions/workflows/build.yml)

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
  Le dossier courant est revele et selectionne automatiquement. Les dossiers
  deplies sont surveilles : une creation, une suppression ou un renommage, fait
  dans l'application ou ailleurs, apparait dans l'arborescence sans rien
  replier. Les volumes amovibles portent un bouton d'ejection.
- **Barre de commandes** : Nouveau, Couper, Copier, Coller, Renommer, Partager,
  Corbeille, Trier, Afficher, menu « ... ».
- **Barre d'adresse** : boutons Precedent / Suivant / Parent / Actualiser,
  fil d'Ariane cliquable avec menu de sous-dossiers sur chaque chevron,
  bascule en champ de saisie de chemin (Cmd L), champ de recherche.
- **8 modes d'affichage** : Tres grandes / Grandes / Moyennes / Petites icones,
  Liste, Details, Mosaiques, Contenu.
- **Details multi-colonnes** : Nom, Modifie le, Type, Taille, Cree le,
  Ajoute le, Tags, Extension, Chemin. Colonnes redimensionnables, reordonnables,
  triables par clic sur l'en-tete (un second clic inverse le sens), activables
  par clic droit sur l'en-tete. Largeurs memorisees par dossier.
- **Taille reelle des dossiers** en mode Details : calculee en tache de fond,
  un dossier a la fois, affichee au fur et a mesure et memorisee tant que le
  dossier n'a pas change. Le tri par taille suit les valeurs qui arrivent.
  Desactivable via Afficher > Calculer la taille des dossiers.
- **Regroupement** : aucun, nom, type, taille, date de modification, tags,
  avec en-tetes repliables.
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
- **Recents** : les elements ouverts ou modifies depuis trente jours, par
  l'index Spotlight (`kMDItemLastUsedDate`, `kMDItemFSContentChangeDate`).
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

- Le reordonnancement des favoris de l'Acces rapide par glisser-deposer n'est
  pas implemente (ajout et retrait le sont).
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
