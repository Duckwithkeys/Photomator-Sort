# UI/UX Review — Task List

Findings from a review of drag-and-drop, floating-window top bars, and menu bars
(plus closely-related navigation paths). All items below are now resolved on the
`chore/ui-ux-review-tasks` branch. Each task records how it was addressed.

> Build status: `swift build` → **Build complete** (no warnings).
> A pre-existing compile error (`.accentColor` on `ShapeStyle`,
> `LargeImageViewer.swift:146`) was fixed by cherry-picking the existing
> `fix/inspector-accentcolor-shapestyle` commit (`6496f68`) from `origin/main`.

## 🔴 Critical — onboarding promises features that don't exist

- [x] **Empty state advertised non-existent capabilities.** Drag-and-drop and a
  File → Import command now both exist, so `EmptyLibraryView.swift` copy is
  accurate. The "Import…" button now calls `importItems()`.
- [x] **No drag-and-drop.** Added `.dropDestination(for: URL.self)` over the main
  content area in `ContentView.swift` (covering both the grid and the empty
  state), with a dashed highlight while a drag is over the window. Drops route to
  `PhotoLibraryViewModel.importURLs(_:)`.
- [x] **No File menu → Import.** Added a `CommandGroup(after: .newItem)` in
  `DuckSortApp.swift` with "Add Source Folder…" and "Import…".
- [x] **"Import..." button mislabeled / inconsistent naming.** Naming unified:
  **Import** = files *or* folders (`importItems()` → `FolderPanel.chooseItems`);
  **Add Source Folder** = folder only (`addSourceDirectory()`). The folder panel
  title is now "Add Source Folder" (was "Add Photoshoot Folder").

## 🟠 High

- [x] **Drag-and-drop entry point implemented.** Folders dropped/imported become
  source directories (recursive scan); individual files are grouped directly into
  photo sets. New `FileScanner.scanFiles(_:jpegOnly:)` (sharing the grouping logic
  via a new `assemble(media:sidecars:)` helper). Loose files are tracked in
  `PhotoLibraryViewModel.looseFiles` and persisted via
  `UserPreferences.lastLooseFilePaths`; `scanSourceDirectories` now scans folders
  **and** loose files together.
- [x] **Fragile floating-window close path fixed.** `FloatingWindowManager` now
  passes an `onClose` closure into each hosted view that closes the *specific*
  panel it owns (`tagManagerPanel`/`ruleEditorPanel`/`shortcutsPanel`). The dead
  `dismiss()` + `NSApp.keyWindow?.close()` guessing was removed from
  `TagManagerView`, `ExportRuleEditorView`, and `ShortcutsPopoverView`.
- [x] **Esc / close button on floating panels.** Each panel's "Done" button keeps
  `.defaultAction` (Return); a hidden sibling button adds `.cancelAction` (Esc).
- [x] **Global key monitor no longer leaks into floating windows.**
  `handleGlobalKeyPress` now returns early when `NSApp.keyWindow?.isFloatingPanel`
  is true, so culling shortcuts can't mutate the hidden grid. Also: plain-letter
  shortcuts (`s`/`i`/`0`) now require no `⌘`/`⌃`/`⌥`, fixing latent
  `⌘S`/`⌘I`-style misfires.

## 🟡 Medium — menu bar

- [x] **Hardcoded shortcuts unified with customizable ones.** The menu is now the
  single source of truth: `DuckSortApp` observes `UserPreferences.shared` and
  derives each command's shortcut from the stored hotkey via
  `KeyboardShortcutInfo.keyboardShortcut` + a new `optionalKeyboardShortcut(_:)`
  modifier. The duplicate handling of these three actions was removed from the
  global monitor, so rebinding a hotkey updates the menu and there is no
  double-handling.
- [x] **Menu items disabled without an active library.** `FloatingWindowManager`
  is now an `ObservableObject` publishing `isReady`; all Tools/File commands use
  `.disabled(!windowManager.isReady)`.
- [x] **File menu added** with "Add Source Folder…" (uses the customizable Add
  Source hotkey, default ⌘O) and "Import…" (⌘⇧I).
- [x] **Redundant titles removed.** The in-content `.title2` headers were dropped
  from Tag Manager, Routing Rules, and Keyboard Shortcuts panels; the system
  title bar (set by `FloatingWindowManager`) is now the single title. Action rows
  (Done / Import Contacts) are retained.

## 🟡 Medium — navigation

- [x] **Grid keyboard-nav math matches the layout.** Column count is now computed
  in `PhotoGridView` from the actual grid width using the *same* constants as the
  `GridItem` (minimum 180, spacing 14, horizontal padding 20) and published to
  `viewModel.gridColumnCount`. `ContentView.handleGridKeyPress` reads that instead
  of the old mismatched `208/18/56` math (which also wrongly used full-window
  width). The dead `columnsCount`/`windowWidth` were removed.

## ⚪ Minor / polish

- [x] **One close affordance in the viewer top bar.** Removed the redundant left
  `chevron.left` button (and its divider); the right-side `xmark` remains.
- [x] **Pan offset accumulates.** `LargeImagePane` tracks `accumulatedPan`; drags
  add to the committed offset and commit on `onEnded`, and it resets everywhere
  `panOffset` resets (zoom buttons, double-tap, photo change).
- [x] **`EdgeBorder` cleaned up.** `path(in:)` now builds each edge's `CGRect` via
  a single `switch` instead of four computed-property closures.

---

## Notes / decisions

- **Loose-file persistence:** individually imported files are persisted across
  launches (mirroring source directories) in `UserPreferences.lastLooseFilePaths`.
- **Import shortcut:** ⌘⇧I (distinct from the plain `i` inspector toggle, which is
  now modifier-guarded).
- **Verification:** validated via `swift build`. Manual UI verification (actual
  drag-drop, panel Esc-close, menu enable/disable, arrow-key grid nav across
  column counts) is still recommended on a running build.
