# Remove JPEG-Only Mode

**Date:** 2026-06-26
**Status:** Approved

## Summary

Remove all user-facing JPEG-Only Mode functionality from DuckSort: the toolbar toggle, menu bar toggle, settings shortcut entry, keyboard shortcut, state persistence, scanning filter logic, and related tests. The scanning pipeline reverts to its default behavior of scanning all file types (RAW, HEIF, JPEG, sidecars).

## Scope

### Files Modified (10)

| File | What is removed | Lines approx. |
|------|-----------------|---------------|
| `DuckSort/DuckSortApp.swift` | Menu bar `Toggle("JPEG Only Mode")` | 4 |
| `DuckSort/Views/ContentView.swift` | Toolbar toggle + shortcuts popover entry | 7 |
| `DuckSort/Views/SettingsShortcutsPaneView.swift` | Shortcut editable row | 1 |
| `DuckSort/Views/PhotoGridView.swift` | `isJpegOnlyMode` parameter to cell | 1 |
| `DuckSort/Views/Components/PhotoSetCell.swift` | Parameter + Equatable comparison | 2 |
| `DuckSort/ViewModels/PhotoLibraryViewModel.swift` | `isJpegOnlyMode` property + hotkey + shortcut info + scanning passes | ~15 |
| `DuckSort/Utilities/FileScanner.swift` | `jpegOnly` param from 3 methods + filter blocks | ~15 |
| `DuckSort/Models/UserPreferences.swift` | Persistence keys + save/load/reset | ~14 |
| `Tests/DuckSortTests/FileScannerTests.swift` | `testJpegOnlyIgnoresRawAndSidecars()` | ~18 |
| `RELEASE_NOTES.md` | Release notes references | 2 |

### No Files Added

### No Architectural Changes

The FileScanner always scans all file types — which is exactly what happens when `jpegOnly` was `false`. No new abstractions or rewrites.

## Design Decisions

1. **Remove, don't abstract.** The JPEG-Only Mode was a simple boolean filter. Removing it means removing the boolean and its conditional branches. No abstraction layer is needed.

2. **Keep `ignoredFileCount`.** The counter remains for truly unknown extensions (`.txt`, `.mp4`, etc.). Only the JPEG-specific filter is removed.

3. **Remove the hotkey.** Since the mode is gone, the configurable keyboard shortcut has no target. Remove `jpegOnlyHotkey` entirely — no replacement shortcut.

4. **Leave `FileExtension` enum unchanged.** JPEG and JPEG-Extended extensions remain in the enum — they are still valid file types, just no longer given special filtering treatment.

## Risk Assessment

- **Low risk.** All changes are removals of dead code paths. The scanning pipeline's core logic (basename grouping, sidecar matching, sorting) is untouched.
- The `Equatable` comparison in `PhotoSetCell` loses one field — cells that were previously considered "different" only due to mode toggle will now be "equal" (they always were equal in visual appearance).

## Testing

- Remove the existing `testJpegOnlyIgnoresRawAndSidecars` test.
- All remaining tests should pass unchanged since the scanning pipeline (minus the removed filter) behaves identically to the pre-existing `jpegOnly: false` path.
