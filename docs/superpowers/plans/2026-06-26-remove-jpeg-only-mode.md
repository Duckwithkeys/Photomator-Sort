# Remove JPEG-Only Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove all JPEG-Only Mode functionality from DuckSort — toolbar toggle, menu bar toggle, settings shortcut, keyboard shortcut, state persistence, scanning filter logic, and related tests — while keeping the rest of the app fully functional.

**Architecture:** Pure removal. Each task removes a slice of JPEG-Only Mode from one file. The scanning pipeline reverts to its default behavior (scan all file types: RAW, HEIF, JPEG, sidecars). No new abstractions.

**Tech Stack:** Swift, SwiftUI, Xcode project (DuckSort.xcodeproj)

## Global Constraints

- Remove ALL references to JPEG-Only Mode — no dead code, no commented-out remnants.
- Keep every other feature fully functional (scanning, filtering, tagging, transfer, viewer, shortcuts).
- All remaining tests must pass after each task.

---

### Task 1: Remove JPEG-Only Mode from FileScanner.swift

**Files:**
- Modify: `DuckSort/DuckSort/Utilities/FileScanner.swift`

**Interfaces:**
- Consumes: none (standalone change)
- Produces: `scanDirectory(_: )`, `scanFiles(_: )`, `scanDirectories(_: )` — all with `jpegOnly` parameter removed

- [ ] **Step 1: Remove `jpegOnly: Bool = false` parameter from `scanDirectory`**

  Change the method signature from:
  ```swift
  func scanDirectory(_ url: URL, jpegOnly: Bool = false) async throws -> ScanResult
  ```
  to:
  ```swift
  func scanDirectory(_ url: URL) async throws -> ScanResult
  ```

- [ ] **Step 2: Remove the `jpegOnly` filter block inside `scanDirectory`**

  Remove these two blocks (lines 131 and 139):
  ```swift
  if jpegOnly && extensionKind != .jpeg && extensionKind != .jpegExtended {
      ignoredFileCount += 1
      continue
  }
  ```
  and:
  ```swift
  if jpegOnly {
      ignoredFileCount += 1
      continue
  }
  ```

- [ ] **Step 3: Remove `jpegOnly: Bool = false` parameter from `scanFiles`**

  Change the method signature from:
  ```swift
  func scanFiles(_ urls: [URL], jpegOnly: Bool = false) async -> ScanResult
  ```
  to:
  ```swift
  func scanFiles(_ urls: [URL]) async -> ScanResult
  ```

- [ ] **Step 4: Remove the `jpegOnly` filter blocks inside `scanFiles`**

  Remove the same two filter blocks (lines 194 and 202) as in `scanDirectory`.

- [ ] **Step 5: Remove `jpegOnly: Bool = false` parameter from `scanDirectories`**

  Change the method signature from:
  ```swift
  func scanDirectories(_ urls: [URL], jpegOnly: Bool = false) async -> ScanResult
  ```
  to:
  ```swift
  func scanDirectories(_ urls: [URL]) async -> ScanResult
  ```

- [ ] **Step 6: Update the call inside `scanDirectories`**

  Change:
  ```swift
  return try await self.scanDirectory(url, jpegOnly: jpegOnly)
  ```
  to:
  ```swift
  return try await self.scanDirectory(url)
  ```

- [ ] **Step 7: Commit**

  ```bash
  git add DuckSort/DuckSort/Utilities/FileScanner.swift
  git commit -m "refactor: remove jpegOnly parameter from FileScanner methods"
  ```

---

### Task 2: Remove JPEG-Only Mode from PhotoLibraryViewModel.swift

**Files:**
- Modify: `DuckSort/DuckSort/ViewModels/PhotoLibraryViewModel.swift`

**Interfaces:**
- Consumes: none (standalone change)
- Produces: No `isJpegOnlyMode` property, no `jpegOnlyHotkey` property, no `jpegOnlyShortcutInfo` computed property

- [ ] **Step 1: Remove `@Published var isJpegOnlyMode` property and its `didSet`**

  Remove lines 78-86:
  ```swift
  @Published var isJpegOnlyMode: Bool = false {
      didSet {
          guard !isInitializing else { return }
          UserPreferences.shared.isJpegOnlyMode = isJpegOnlyMode
          UserPreferences.shared.save()
          if !sourceDirectories.isEmpty {
              scanSourceDirectories(sourceDirectories)
          }
      }
  }
  ```

- [ ] **Step 2: Remove initialization of `isJpegOnlyMode` from UserDefaults**

  Remove line 227:
  ```swift
  self.isJpegOnlyMode = UserPreferences.shared.isJpegOnlyMode
  ```

- [ ] **Step 3: Remove `jpegOnlyHotkey` published property and its `didSet`**

  Remove lines 1596-1601:
  ```swift
  @Published var jpegOnlyHotkey: String? = "shift+cmd+q" {
      didSet {
          guard !isInitializing else { return }
          UserPreferences.shared.jpegOnlyHotkey = jpegOnlyHotkey ?? ""
          UserPreferences.shared.save()
      }
  }
  ```

- [ ] **Step 4: Remove initialization of `jpegOnlyHotkey` from UserDefaults**

  Remove line 241:
  ```swift
  self.jpegOnlyHotkey = UserPreferences.shared.jpegOnlyHotkey
  ```

- [ ] **Step 5: Remove `jpegOnlyShortcutInfo` computed property**

  Remove lines 1619-1621:
  ```swift
  var jpegOnlyShortcutInfo: KeyboardShortcutInfo? {
      guard let hotkey = jpegOnlyHotkey, !hotkey.isEmpty else { return nil }
      return KeyboardShortcutInfo.parse(hotkey)
  }
  ```

- [ ] **Step 6: Update `scanSourceDirectories` — remove `isJpegOnlyMode` from capture list and remove argument from scanner calls**

  Change:
  ```swift
  scanTask = Task { @MainActor [scanner, isJpegOnlyMode] in
  ```
  to:
  ```swift
  scanTask = Task { @MainActor [scanner] in
  ```

  Change:
  ```swift
  let dirResult = await scanner.scanDirectories(urls, jpegOnly: isJpegOnlyMode)
  ```
  to:
  ```swift
  let dirResult = await scanner.scanDirectories(urls)
  ```

  Change:
  ```swift
  let fileResult = await scanner.scanFiles(looseFiles, jpegOnly: isJpegOnlyMode)
  ```
  to:
  ```swift
  let fileResult = await scanner.scanFiles(looseFiles)
  ```

- [ ] **Step 7: Commit**

  ```bash
  git add DuckSort/DuckSort/ViewModels/PhotoLibraryViewModel.swift
  git commit -m "refactor: remove isJpegOnlyMode and jpegOnlyHotkey from PhotoLibraryViewModel"
  ```

---

### Task 3: Remove JPEG-Only Mode from DuckSortApp.swift (Menu Bar)

**Files:**
- Modify: `DuckSort/DuckSort/DuckSortApp.swift`

**Interfaces:**
- Consumes: none (standalone change)
- Produces: Menu bar without "JPEG Only Mode" toggle

- [ ] **Step 1: Remove the menu bar Toggle for JPEG Only Mode**

  Remove lines 39-43:
  ```swift
  Toggle("JPEG Only Mode", isOn: Binding(
      get: { windowManager.activeViewModel?.isJpegOnlyMode ?? false },
      set: { windowManager.activeViewModel?.isJpegOnlyMode = $0 }
  ))
  .optionalKeyboardShortcut(KeyboardShortcutInfo.parse(preferences.jpegOnlyHotkey).keyboardShortcut)
  .disabled(!windowManager.isReady)
  ```

  Keep the following `Divider()` and "Show Advanced EXIF" toggle intact.

- [ ] **Step 2: Commit**

  ```bash
  git add DuckSort/DuckSort/DuckSortApp.swift
  git commit -m "ui: remove JPEG Only Mode from menu bar"
  ```

---

### Task 4: Remove JPEG-Only Mode from ContentView.swift (Toolbar + Popover)

**Files:**
- Modify: `DuckSort/DuckSort/Views/ContentView.swift`

**Interfaces:**
- Consumes: none (standalone change)
- Produces: Toolbar without JPEG-only toggle, shortcuts popover without JPEG-only entry

- [ ] **Step 1: Remove the toolbar toggle for JPEG Only Mode**

  Remove lines 77-82:
  ```swift
  ToolbarItem(placement: .primaryAction) {
      Toggle(isOn: Binding(
          get: { viewModel.isJpegOnlyMode },
          set: { viewModel.isJpegOnlyMode = $0 }
      )) {
          Label("JPEG Only", systemImage: "photo")
      }
      .help("Show only JPEG derivatives")
  }
  ```

- [ ] **Step 2: Remove the shortcuts popover entry for JPEG Only Mode**

  Remove lines 393-396:
  ```swift
  HStack {
      Text("Toggle JPEG Only Mode")
      Spacer()
      ShortcutRecorderView(hotkey: $viewModel.jpegOnlyHotkey)
  }
  ```

- [ ] **Step 3: Commit**

  ```bash
  git add DuckSort/DuckSort/Views/ContentView.swift
  git commit -m "ui: remove JPEG Only Mode from toolbar and shortcuts popover"
  ```

---

### Task 5: Remove JPEG-Only Mode from SettingsShortcutsPaneView.swift

**Files:**
- Modify: `DuckSort/DuckSort/Views/SettingsShortcutsPaneView.swift`

**Interfaces:**
- Consumes: none (standalone change)
- Produces: Settings shortcuts pane without JPEG-only shortcut entry

- [ ] **Step 1: Remove the shortcut editable row for JPEG Only Mode**

  Remove line 128:
  ```swift
  ShortcutEditableRow(label: "Toggle JPEG Only Mode", hotkey: $viewModel.jpegOnlyHotkey)
  ```

- [ ] **Step 2: Commit**

  ```bash
  git add DuckSort/DuckSort/Views/SettingsShortcutsPaneView.swift
  git commit -m "ui: remove JPEG Only Mode from settings shortcuts pane"
  ```

---

### Task 6: Remove JPEG-Only Mode from PhotoGridView.swift

**Files:**
- Modify: `DuckSort/DuckSort/Views/PhotoGridView.swift`

**Interfaces:**
- Consumes: none (standalone change)
- Produces: PhotoSetCell created without `isJpegOnlyMode` parameter

- [ ] **Step 1: Remove `isJpegOnlyMode` argument from PhotoSetCell initializer**

  Change:
  ```swift
  EquatableView(content: PhotoSetCell(
      photoSet: photoSet,
      tags: viewModel.assignedTags(for: photoSet),
      isFocusedGridItem: isFocused,
      isJpegOnlyMode: viewModel.isJpegOnlyMode,
      handleClick: { ... },
      openInViewer: { ... }
  ))
  ```
  to:
  ```swift
  EquatableView(content: PhotoSetCell(
      photoSet: photoSet,
      tags: viewModel.assignedTags(for: photoSet),
      isFocusedGridItem: isFocused,
      handleClick: { ... },
      openInViewer: { ... }
  ))
  ```

- [ ] **Step 2: Commit**

  ```bash
  git add DuckSort/DuckSort/Views/PhotoGridView.swift
  git commit -m "ui: remove isJpegOnlyMode parameter from PhotoSetCell in PhotoGridView"
  ```

---

### Task 7: Remove JPEG-Only Mode from PhotoSetCell.swift

**Files:**
- Modify: `DuckSort/DuckSort/Views/Components/PhotoSetCell.swift`

**Interfaces:**
- Consumes: none (standalone change)
- Produces: PhotoSetCell without `isJpegOnlyMode` property

- [ ] **Step 1: Remove the `isJpegOnlyMode` property**

  Remove line 20:
  ```swift
  let isJpegOnlyMode: Bool
  ```

- [ ] **Step 2: Remove `isJpegOnlyMode` from the Equatable comparison**

  Change:
  ```swift
  lhs.photoSet == rhs.photoSet &&
  lhs.tags == rhs.tags &&
  lhs.isFocusedGridItem == rhs.isFocusedGridItem &&
  lhs.isJpegOnlyMode == rhs.isJpegOnlyMode
  ```
  to:
  ```swift
  lhs.photoSet == rhs.photoSet &&
  lhs.tags == rhs.tags &&
  lhs.isFocusedGridItem == rhs.isFocusedGridItem
  ```

- [ ] **Step 3: Commit**

  ```bash
  git add DuckSort/DuckSort/Views/Components/PhotoSetCell.swift
  git commit -m "ui: remove isJpegOnlyMode from PhotoSetCell"
  ```

---

### Task 8: Remove JPEG-Only Mode from UserPreferences.swift

**Files:**
- Modify: `DuckSort/DuckSort/Models/UserPreferences.swift`

**Interfaces:**
- Consumes: none (standalone change)
- Produces: UserPreferences without JPEG-only state

- [ ] **Step 1: Remove `@Published var isJpegOnlyMode: Bool`**

  Remove line 23:
  ```swift
  @Published var isJpegOnlyMode: Bool = false
  ```

- [ ] **Step 2: Remove `@Published var jpegOnlyHotkey: String`**

  Remove line 48:
  ```swift
  @Published var jpegOnlyHotkey: String = "shift+cmd+q"
  ```

- [ ] **Step 3: Remove `isJpegOnlyMode` and `jpegOnlyHotkey` from the Keys struct**

  Remove lines 84 and 96:
  ```swift
  static let isJpegOnlyMode = "isJpegOnlyMode"
  static let jpegOnlyHotkey = "jpegOnlyHotkey"
  ```

- [ ] **Step 4: Remove save calls for JPEG-only keys**

  Remove the lines that call `UserDefaults.standard.set(isJpegOnlyMode, forKey: Keys.isJpegOnlyMode)` and `UserDefaults.standard.set(jpegOnlyHotkey, forKey: Keys.jpegOnlyHotkey)`.

- [ ] **Step 5: Remove load calls for JPEG-only keys**

  Remove the lines that call `UserDefaults.standard.bool(forKey: Keys.isJpegOnlyMode)` and `UserDefaults.standard.string(forKey: Keys.jpegOnlyHotkey)`.

- [ ] **Step 6: Remove reset calls for JPEG-only keys**

  Remove the lines that call `UserDefaults.standard.removeObject(forKey: Keys.isJpegOnlyMode)` and `UserDefaults.standard.removeObject(forKey: Keys.jpegOnlyHotkey)`.

- [ ] **Step 7: Remove reset values for JPEG-only keys**

  Remove the lines that set `isJpegOnlyMode = false` and `jpegOnlyHotkey = "shift+cmd+q"` in the reset method.

- [ ] **Step 8: Commit**

  ```bash
  git add DuckSort/DuckSort/Models/UserPreferences.swift
  git commit -m "refactor: remove JPEG-Only Mode persistence from UserPreferences"
  ```

---

### Task 9: Remove JPEG-Only Mode test and update release notes

**Files:**
- Modify: `Tests/DuckSortTests/FileScannerTests.swift`
- Modify: `RELEASE_NOTES.md`

**Interfaces:**
- Consumes: none (standalone change)
- Produces: No JPEG-only test, updated release notes

- [ ] **Step 1: Remove `testJpegOnlyIgnoresRawAndSidecars` test**

  Remove the entire test function (lines 61-76):
  ```swift
  func testJpegOnlyIgnoresRawAndSidecars() async throws {
      let urls = [
          try makeFile("IMG_001.jpg"),
          try makeFile("IMG_001.raf"),
          try makeFile("IMG_001.photo-edit"),
          try makeFile("IMG_002.jpg")
      ]

      let result = await FileScanner().scanFiles(urls, jpegOnly: true)

      XCTAssertEqual(result.photoSets.count, 2)
      let first = try XCTUnwrap(set(named: "IMG_001", in: result))
      XCTAssertEqual(first.mediaCount, 1)
      XCTAssertFalse(first.hasEdit)
      XCTAssertEqual(result.scannedFileCount, 2)
      XCTAssertEqual(result.ignoredFileCount, 2) // .raf + .photo-edit
  }
  ```

- [ ] **Step 2: Update RELEASE_NOTES.md references**

  Update the release notes that mention JPEG-Only mode (lines 63, 166, 231) to remove references to the feature.

- [ ] **Step 3: Commit**

  ```bash
  git add Tests/DuckSortTests/FileScannerTests.swift RELEASE_NOTES.md
  git commit -m "tests: remove JPEG-Only Mode test and update release notes"
  ```

---

### Task 10: Verify build and tests pass

**Files:**
- Build: `DuckSort.xcodeproj` (entire project)
- Test: All test targets

**Interfaces:**
- Consumes: all previous tasks
- Produces: A working, test-passing DuckSort without JPEG-Only Mode

- [ ] **Step 1: Build the project**

  ```bash
  xcodebuild -project DuckSort.xcodeproj -scheme DuckSort -configuration Debug build
  ```

  Expected: Build succeeds with zero errors and zero warnings about unused code.

- [ ] **Step 2: Run all tests**

  ```bash
  xcodebuild -project DuckSort.xcodeproj -scheme DuckSort -configuration Debug test
  ```

  Expected: All tests pass, including all tests in `DuckSortTests`.

- [ ] **Step 3: Verify no remaining references**

  ```bash
  grep -rn -i "jpegOnly\|jpeg_only\|jpeg.*only" DuckSort/ --include='*.swift'
  ```

  Expected: Zero results (the `.build/` directory may still contain stale compiled records).

- [ ] **Step 4: Final commit**

  ```bash
  git add -A
  git commit -m "verify: build succeeds and all tests pass after removing JPEG-Only Mode"
  ```

---

## Self-Review

**Spec coverage:**
- Menu bar toggle → Task 3 ✓
- Toolbar toggle → Task 4 ✓
- Settings shortcut entry → Task 5 ✓
- Shortcuts popover entry → Task 4 ✓
- Keyboard shortcut → Tasks 2, 5 ✓
- State persistence → Tasks 2, 8 ✓
- Scanning filter → Task 1 ✓
- ViewModel state → Task 2 ✓
- UI parameters → Tasks 6, 7 ✓
- Tests → Task 9 ✓
- Release notes → Task 9 ✓
- Build verification → Task 10 ✓

**Placeholder scan:** No TBD, TODO, or "similar to" references found. Every step contains exact file paths, line numbers, and code.

**Type consistency:** All references to `isJpegOnlyMode`, `jpegOnlyHotkey`, and `jpegOnlyShortcutInfo` are removed consistently across all files. Scanner methods lose their `jpegOnly` parameter in Task 1, and callers in Task 2 are updated to match.

---

**Plan complete and saved to `docs/superpowers/plans/2026-06-26-remove-jpeg-only-mode.md`.**

Two execution options:

**1. Subagent-Driven (recommended)** — Dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
