# MExplorer

A native macOS file explorer with the ergonomics of the Windows 11 Explorer
(full folder tree, tabs, command bar, breadcrumb, grouping), built on the
Finder's own services (Quick Look, tags, aliases, Spotlight, sharing,
services).

Written in Swift 6: AppKit for the high-volume views (tree, multi-column list,
icon grid), SwiftUI for the command bars, the breadcrumb and the details pane.
No third-party dependency.

[![Build](https://github.com/brihx001/MExplorer/actions/workflows/build.yml/badge.svg)](https://github.com/brihx001/MExplorer/actions/workflows/build.yml)

**English** · **[Francais](README.fr.md)**

**Latest release: [v0.5.3](https://github.com/brihx001/MExplorer/releases/tag/v0.5.3)**
— a maintenance release; 0.5.2 brought memory-card information to the SMART
window.

## Requirements

- macOS 14 (Sonoma) or newer;
- Xcode installed in `/Applications` (for the Swift toolchain and the SwiftUI
  macro plugin); it does not need to be selected with `xcode-select`;
- no external dependency: the package pulls no third-party module.

## Build and run

```bash
./build.sh release
```

The script builds with Swift Package Manager, assembles `MExplorer.app`, then
signs the bundle ad-hoc with the sandbox entitlements.

`build.sh` applies two toolchain workarounds on its own (macOS 27 / Swift 6.4,
with no Xcode selected):

- SwiftPM's default build system (`swiftbuild`) fails with the Command Line
  Tools alone, even on an empty package (`Unknown error parsing property
  list`): the script forces `--build-system native`;
- the SwiftUI macros (`@State`, `@Observable`...) come from a plugin shipped
  only with Xcode: the script points at it with `-plugin-path`.

Xcode must therefore be installed in `/Applications`, but it does not need to
be selected with `xcode-select`.

Then:

```bash
open MExplorer.app
```

For a debug build: `./build.sh debug`.

A signed build is also attached to every
[release](https://github.com/brihx001/MExplorer/releases). It is ad-hoc signed
and **not notarized**, so macOS quarantines the downloaded file and refuses to
open it; clear the quarantine first:

```bash
xattr -dr com.apple.quarantine /Applications/MExplorer.app
```

## Sandbox: read this first

The application is built **sandboxed**, App Store ready. macOS therefore
forbids it to read your files until you point it at a folder.

On first launch, MExplorer offers to grant access to the **whole disk**:
accept, then pick the startup disk in the system panel. The permission is kept
between launches through a security-scoped bookmark. The prompt does not come
back once the root is granted, and a *Don't ask again* button disables it for
good.

It stays reachable afterwards from **MExplorer > Allow access to the whole
disk...**, and the file area shows an **Allow access to this folder** button
whenever a folder is not readable anyway.

Granting the root does not bypass TCC: folders protected by macOS (Desktop,
Documents, Downloads, the photo library) raise their own prompt on first
access.

You can add or remove granted folders at any time in **Settings > Access**, or
through **MExplorer > Allow access to a folder...** (Cmd Shift O).

Consequences of the sandbox, inherent to the "App Store ready" choice:

- mounting network volumes (SMB/AFP) is not possible from the app; volumes
  already mounted by the Finder appear and can be browsed;
- Spotlight search only returns what the app can reach;
- writing tags requires the file to sit in a granted folder.

An actual App Store submission would need Xcode, an Apple Developer account, an
app identifier and a signature with your distribution profile: the structure of
the project (entitlements, bookmarks, no private API) is ready for it.

## Features

### Taken from the Windows 11 Explorer

- **Middle click**: on a folder, in the list, the icon grid or the navigation
  pane, it opens it in a **background** tab, as a browser does. The new tab
  marks itself for two and a half seconds with an accent outline, without which
  nothing would show it appeared. On a file, middle click does nothing.
- **Tabs**: creation, closing, duplication, *close others*, *close to the
  right*, context menu. Reorderable by dragging, and **movable from one window
  to another**: the tab carries its history and its settings along, and the
  source window closes if that was its last tab. The context menu also offers
  *Move to a new window*.
- **Drag and drop with other applications**: files go out to the Finder (or any
  application that accepts file URLs) and come in the same way, onto the list,
  the sidebar or a tab.
- **Moving files between tabs**: dropping a selection on a tab moves it into
  its folder (Option to copy). Hovering a tab during a drag switches to it
  after a short moment (spring-loaded tab), which allows dropping into the list
  rather than onto the tab.
- **Navigation pane**: a real tree, expandable without limit (Quick access,
  iCloud, This Mac, Locations, Tags, Recents, Trash). The current folder is
  revealed and selected in the real tree, even when reached through a quick
  access shortcut. Expanded folders are watched: a creation, a deletion or a
  rename, made in the application or anywhere else, shows up in the tree
  without collapsing anything. Removable volumes carry an eject button. The
  startup disk is listed only once, under *This Mac*.
- **Settings**: interface language, light/dark/system theme, hidden items, file
  name extensions, single-click opening, opening folders in a new tab,
  confirmation of permanent deletions, reset of the display settings, and the
  list of granted folders.
- **Links and aliases to a folder**: a symbolic link or an alias whose target
  is a folder behaves like a folder (navigation, sorting with the folders,
  *open in a new tab*). That is the case of the link OneDrive leaves in the
  home folder: without this it was handed over to the Finder, `isDirectory`
  describing the link and not its target. The navigation tree, for its part,
  expands real folders only, so that a link pointing at an ancestor cannot be
  expanded forever.
- **Quick access**: a flat list of shortcuts, with no chevron and no subtree
  (the hierarchy expands under *This Mac*). A folder dropped on the header, or
  between two favourites, becomes a favourite at the drop position. The context
  menus of the sidebar and of the file area also add and remove a folder, the
  entry offered depending on whether it is already in the list.
- **Command bar**: New, Cut, Copy, Paste, Rename, Share, Trash, Sort, View,
  "..." menu.
- **Rename**: F2, the context menu, the command bar button, or **two slow
  clicks** on the name of an already selected item, as in the Finder. The delay
  exceeds the system double-click interval, and any other event (click, key,
  scroll, context menu, drag) cancels it. In the icon modes, only a click on
  the name arms the rename, not on the icon; in Details, only the Name column.
- **Name conflict**: copying or moving an item into a folder that already holds
  one with the same name offers to **keep both**, to **replace** or to
  **cancel**, as in the Finder. The replacement goes through a temporary name
  then an atomic swap: the existing item is destroyed only once the new one is
  in place. It cannot be undone, the old content no longer existing.
- **Address bar**: Back / Forward / Parent / Refresh buttons, clickable
  breadcrumb with a subfolder menu on every chevron, switch to a path field
  (Cmd L), search field.
- **8 view modes**: Extra large / Large / Medium / Small icons, List, Details,
  Tiles, Content.
- **Multi-column details**: Name, Date modified, Type, Size, Date created, Date
  added, Tags, Extension, Path. Columns are resizable, reorderable, sortable by
  clicking the header (a second click reverses the direction), and switched on
  by right-clicking the header. Widths are remembered per folder. A
  **double-click on a column separator** fits it to its widest content, as in a
  spreadsheet.
- **Real folder sizes**: computed in the background, one folder at a time,
  shown as they arrive in Details and kept until the folder changes. **Sorting
  by size uses them**: folders and files are then interleaved by their actual
  size, and the order follows the values as they arrive. The computation also
  runs outside the Details view as soon as the sort depends on it. Switched off
  from View > Compute folder sizes, sorting groups folders first again: they no
  longer have a size to compare.
- **Grouping**: none, name, type, size, date modified, tags, with collapsible
  headers. Grouping by size relies on the computed folder sizes too: a folder
  then joins the bucket that matches it instead of a group of its own, and goes
  back to a *Folders* group when the computation is off.
- **Sorting by date**: files and folders are interleaved. The *Folders first*
  option does not apply to the date columns, where it would hide exactly what
  one is trying to see.
- **Per-folder display settings**, plus *Apply to all folders*.
- **Hidden items**: a global toggle (View > Hidden items, Presentation > Hidden
  items, or the context menu). Deliberately global and not per folder, as in
  the Finder and in the Explorer: a per-folder setting gave the impression that
  the option did not stick.
- **Status bar**: item count and total size on the left, summary of the
  selection, progress of long operations, then on the right a **fill gauge for
  the current volume** (green to red depending on how full it is, full detail in
  a tooltip) and the display toggles. The total size ends with an ellipsis for
  as long as folder sizes remain to be computed.
- **Details pane** and **preview pane** on the right, whose visibility is
  remembered between launches.
- **Windows Cut / Paste semantics**: cut items are greyed out until the paste,
  which moves them.
- Deletion with **Del** (trash) and **Shift Del** (permanent), rename with
  **F2**, refresh with **F5**.

### Native Finder services

- **Quick Look** (space bar) with an animation from the thumbnail, and
  QuickLookThumbnailing thumbnails in the icon modes.
- **Finder tags**: reading, writing, coloured dots in the list, a Tags section
  in the sidebar, search by tag.
- **Aliases**: creation, resolution, *Paste shortcut*.
- **Trash**: undoable move to the trash (Cmd Z), emptying. Reachable from the
  menu, the command bar, the Del key, a drop on the sidebar Trash or on the
  Dock one. All these paths go through `NSWorkspace.recycle`, so *Put Back*
  stays available in the Finder.
- **Live Spotlight search** (NSMetadataQuery) on name and content, limited to
  the current folder or extended to the Mac.
- **Open With** (applications offered by LaunchServices), **Share**
  (NSSharingServicePicker), macOS **Services menu**.
- **Compression** to .zip through NSFileCoordinator (sandbox compatible).
- **Info window**: recursive size, dates, POSIX permissions, owner, editable
  tags, associated applications.
- **Undo** (Cmd Z) on rename, move, copy, duplication, creation and move to the
  trash.
- **Volumes**: detection of mounts and unmounts, one-click eject from the
  sidebar or through the context menu.
- **SMART information**: the context menu of a disk offers *Show SMART
  information...*, which opens a readable window — wear, temperature, spare
  blocks, power-on hours, power cycles, unsafe shutdowns, errors, data read and
  written. A warning icon marks out-of-range values, and a hovered "i" explains
  every reading. The entry only appears for disks that really return this data.
- **Media information**: for a memory card, the menu offers *Show media
  information...*. A card returns no SMART data at all, and the window shows
  instead what it publishes about itself: maker, revision, serial number,
  manufacture date, speed class, capacity, write protection.
- **About**: shows the date and time the binary was built, written into the
  bundle by `build.sh`.
- **Recents**: items opened or modified in the last thirty days, from the
  Spotlight index (`kMDItemLastUsedDate`, `kMDItemFSContentChangeDate`). The
  personal library is left out: its caches and logs change constantly and would
  drown the real documents.
- Automatic refresh of the displayed folder (FSEvents watching).

## Main keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| New tab / window | Cmd T / Cmd N |
| Next / previous tab | Cmd Alt Right / Left |
| Back / Forward | Cmd [ / Cmd ] |
| Parent folder | Cmd Up |
| Open | Return or Cmd Down |
| Enter a path | Cmd L |
| Search | Cmd F |
| New folder | Cmd Shift N |
| Trash / permanent deletion | Del / Shift Del |
| Quick Look | Space |
| Get Info | Cmd I |
| View modes | Cmd 1 to Cmd 8 |
| Navigation pane | Cmd Ctrl S |
| Details pane | Cmd Shift P |
| Hidden items | Cmd Shift . |

The full list is under **Help > Keyboard shortcuts**.

## Code layout

```
Sources/MExplorer/
  App/         entry point, delegate, menu bar, window
  Model/       file system, tabs, sorting, tags, clipboard, sandbox
  Views/       sidebar, list, grid, SwiftUI bars, auxiliary windows
  Support/     formatters, icon cache, closure-based menus
Packaging/     Info.plist, entitlements and icon
Packaging/Icon/make-icon.swift   icon generator (vector drawing)
build.sh       build + bundle assembly + signing
```

Structural points:

- `TabState` carries the whole state of a tab (location, history, contents,
  sorting, selection); `WindowModel` is the single entry point for commands.
- `AccessManager` handles the sandbox permissions and their bookmarks.
- Nothing slow touches the main thread: folder loading, recursive size, tags,
  localized names, specific icons, thumbnails and the probing of tree
  expansion all happen in the background, then refresh the view.

Six costs measured on this Mac dictated the architecture:

| Call | Measured cost | Handling |
| --- | --- | --- |
| `localizedName` on a TCC-protected folder | ~5 to 10 s per call | `DisplayNameCache`, asynchronous and persistent |
| `tagNames` / `labelNumber` | one `getxattr` per file | second pass after display |
| `isUbiquitousItem` / `ubiquitousItemDownloadingStatus` | 77 us per file, two thirds of the load of a 5,200-item folder | read on demand, for the selected item only |
| `NSWorkspace.icon(forFile:)` | LaunchServices, may block | generic icon at once, specific one deferred |
| Contents of a SwiftUI menu | evaluated **on every render** | `SubfolderCache`, never a disk read inside the menu |
| Size of a folder | full recursive walk | `FolderSizeCalculator`, one folder at a time, cancellable |

Three pitfalls had to be worked around as well. First: `removeTableColumn`
clears the table's `sortDescriptors`. Since the columns were rebuilt on every
settings change, the second click on a header started again from the ascending
prototype instead of reversing the sort. Columns are now recreated only when
their composition really changes.

Second: the Dock Trash accepts a drop only if the source declared the
`NSDragOperation.delete` operation. Without it, dropping a file there does
strictly nothing. The source view must also implement
`draggingSession(_:endedAt:operation:)` to perform the move to the trash
itself: the Dock merely reports the gesture.

And on the SwiftUI side: asking a `TextField` for focus in the same run-loop
turn as its appearance does not work, the field not existing yet. The Cmd-L
input then went into the search field. Focus is now requested on the next turn.

Two Quick Look pitfalls are worth noting:

- a thumbnail request on a protected package
  (`Photos Library.photoslibrary`) never gets an answer and blocks the
  QuickLook connection of the whole process; packages are therefore excluded
  from thumbnail requests;
- `QLThumbnailGenerator` silently drops requests beyond a few simultaneous
  ones: they are queued, four at a time, with a watchdog.

## Privacy permissions and signing

macOS asks the user for approval before an application touches certain areas:
removable volumes, network volumes, Desktop, Documents, Downloads. TCC records
those approvals against the application's **code identity**, not against its
path nor its identifier alone.

An **ad-hoc** signature has no certificate: the identity there comes down to
the binary's own hash, which changes with every rebuild. Measured on this Mac:
after granting access to the removable volume, rebuilding the application with
a different build number was enough for macOS to ask again — for the removable
volume, then for Downloads, then for the Desktop. In other words, **every
update discards all the permissions already given**.

Signing with a stable certificate ties the approval to the certificate instead
of to the binary. An *Apple Development* certificate, free with an Apple
account, is enough for your own Mac:

```bash
security find-identity -v -p codesigning        # read the identity
echo 'Apple Development: me@example.com (XXXXXXXXXX)' > .signing-identity
./build.sh release
```

`build.sh` reads `MEXPLORER_SIGN_IDENTITY`, falls back to the
`.signing-identity` file (local, git-ignored), and signs ad-hoc otherwise. The
first signature asks for the keychain password to let `codesign` use the
private key; answering **Always Allow** keeps the question from coming back.

The artefacts published in the *releases* stay ad-hoc signed: a development
certificate is only worth anything on the machine that issued it, and
Gatekeeper would refuse it elsewhere. Only a *Developer ID* and notarization
would change that.

## SMART data and the sandbox

The IOKit SMART client is closed to sandboxed applications: opening it answers
`kIOReturnNotPermitted`, and `diskutil` launched from the application returns
"Not Supported" where the same call outside the sandbox returns "Verified".

`Packaging/MExplorer.entitlements` therefore carries the temporary exception
`com.apple.security.temporary-exception.iokit-user-client-class`
(`AppleNVMeSMARTUserClient`, `AppleSATLSMARTUserClient`), which reopens that
one client. Measured on this Mac: without it, no data at all; with it, the full
SMART log of the internal disk.

The header `<IOKit/storage/nvme/NVMeSMARTLibExternal.h>` not being exposed to
the Swift module, a small C module (`Sources/CSmart`) includes it and returns
the reading as a flat structure.

Two dialects are read:

- the **NVMe SMART log** of recent internal drives: wear, temperature, spare
  blocks, hours, power cycles, unsafe shutdowns, media errors;
- the **ATA attribute table** of SATA disks and of the USB enclosures that
  translate ATA commands (SAT): reallocated sectors, pending sectors,
  uncorrectable sectors, uncorrected errors, temperature, hours, power cycles,
  transmission errors, life left. The attributes carry standardized
  identifiers; only those that speak to a user are presented, the others stay
  hidden unless they cross the manufacturer's threshold, in which case they
  appear with their number.

An attribute is flagged abnormal when its normalized value falls to the
manufacturer's threshold, and the bad-sector counters as soon as they go above
zero.

One limit comes from the hardware: a USB enclosure does not always pass the
diagnostic commands through to the disk it holds. The Crucial X9 used for
testing is in that case, and the menu entry does not appear for it.

### Memory cards

An SD card has no SMART, and never will: SMART is an ATA (T13) and NVMe command
set, which the SD Association standard does not adopt. A card exposes its CID
and CSD registers — identity, capacity, speed classes — but no health
attribute: no hours of service, no write cycles, no spare blocks. The vendor
commands that, on some industrial cards, return a wear estimate go through
CMD56, which macOS opens to no public API. eMMC, for its part, does carry a
standardized wear field in its `EXT_CSD`; that is not SMART either, and SD does
not have it.

MExplorer recognizes a card by its bus ("Secure Digital"), by the `Card
Characteristics` dictionary the reader's driver publishes, or by the
`IOSDHCIBlockDevice` class. It then shows the card's identity, plus the
capacity and the write lock read from its `IOMedia` object, under a sentence
that says why no health reading follows. The dictionary keys depending on the
reader, the ones that are not recognized are published as-is rather than lost.

That path could not be exercised against a real card: the development Mac is a
13" M1 MacBook Pro, with no SD reader, and no USB reader was available. It was
verified by forcing the "card" path on an external disk: window, table,
tooltips and the fallback on unknown keys all behave as expected.

## Performance

Two measurements made on a 5,200-item folder, before and after trimming the set
of keys read at load time:

| | Before | After |
| --- | --- | --- |
| Folder read (listing + values) | 0.655 s | 0.200 s |
| Memory added by the folder | 25.3 MB | 13.7 MB |

The gain comes from three keys removed from the load: the iCloud state, which
alone cost two thirds of the time and only serves the details pane, and the
volume capacities, read per file although they describe the disk. Add to that
the type labels shared between files of the same kind, and a thumbnail cache
bounded in bytes (64 MB) rather than in count: 1,500 Retina thumbnails could
have gone past half a gigabyte.

## Languages and appearance

The interface follows the Mac's language on first launch, and is changed in
**Settings > General > Language**: *System language*, *French* or *English*.
The change applies immediately, without restarting.

The labels are written in French in the code and French serves as the key:
`Support/EnglishStrings.swift` provides the English table, and a missing key
falls back to French. Adding a language therefore amounts to one file of the
same shape, an entry in `AppLanguage` and a line in `L10n.apply`.

Two details are worth knowing:

- `Packaging/Info.plist` declares `CFBundleLocalizations` (`fr`, `en`).
  Without that list, macOS considers the application unlocalized and provides
  its own labels (a file's kind, system panels) in the development region, so
  in French even on an English Mac.
- Those labels follow the **system** language, not the application setting:
  choosing French on an English Mac leaves the Type column in English.

**Dates** follow the system too, but deliberately: they use the format set in
*System Settings > Language & Region*, the one you see everywhere else on your
Mac, whatever language is chosen in the application.

The **theme** is set in **Settings > General > Theme**: *System theme*, *Light*
or *Dark*. It applies immediately to every window. Left on *System theme*, the
application follows macOS, including when the appearance switches during the
day.

## Icon

The icon is drawn programmatically, at every size, by
`Packaging/Icon/make-icon.swift`: a tabbed folder whose front face carries a
tree, the two distinctive traits of the application. The drawing is simplified
at small sizes (two branches at 32 points, none at 16) because thin strokes
blur into a blob there.

To regenerate it:

```bash
cd Packaging/Icon && swift make-icon.swift . && iconutil --convert icns --output ../AppIcon.icns AppIcon.iconset
```

## Known limitations

- Quick access favourites are added by dragging, but a favourite already in the
  list cannot be moved within it that way.
- No *Put Back* from the trash (the original location is not reachable under
  the sandbox).
- Session restore reopens a single window.
- Rubber-band selection exists only in the icon modes (an NSTableView limit in
  Details).
- Packages (`.app`, `.photoslibrary`) have no Quick Look thumbnail: they keep
  their icon, for the reason explained above.
- Very large files for which QuickLook fails to produce a thumbnail keep the
  generic icon of their type.
- Folder size computation is shared by all windows: the last folder displayed
  takes over the queue.
- A remembered size is recomputed when the folder itself changes, not when a
  file changes deep in its tree.

## Contributing

Bug reports and suggestions are welcome in the *issues*. For a fix, open a
*pull request* against `main`: `./build.sh release` must pass, and the code
convention is that of the neighbouring files (comments in French without
accents, one file per responsibility).

## Licence

MIT, see [LICENSE](LICENSE).
