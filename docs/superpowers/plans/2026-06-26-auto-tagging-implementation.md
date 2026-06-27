# Auto Tagging — Implementation Plan

## 1. Overview

Auto-tagging analyzes a photo's EXIF metadata **only when focused in the large viewer** and suggests tags based on configurable rules. The user accepts or dismisses each suggestion. No batch scanning, no persistence of dismissed suggestions, no overhead when the large viewer is closed.

**Phase 1 (MVP):** Core engine + large viewer UI + default rules.
**Phase 2 (Settings):** Rule editor + persistence in `UserPreferences`.

---

## 2. Architecture

### Components

| Component | File (new) | Purpose |
|---|---|---|
| **AutoTagRule** (model) | `DuckSort/Models/AutoTagRule.swift` | Rule, Condition, SuggestedTag types — Codable + Sendable |
| **AutoTagEngine** (utility) | `DuckSort/Utilities/AutoTagEngine.swift` | Pure function: `MetadataSnapshot` → `[AutoTagSuggestion]` |
| **AutoTagSuggestionsView** | `DuckSort/Views/AutoTagSuggestionsView.swift` | Large viewer sidebar suggestions |
| **SettingsAutoTaggingPaneView** | `DuckSort/Views/SettingsAutoTaggingPaneView.swift` | Settings tab with rule editor |

### Existing files modified

| File | Change |
|---|---|
| `UserPreferences.swift` | Add `autoTaggingEnabled` (Bool) and `autoTaggingRules` ([AutoTagRule]) |
| `SettingsPaneWindow.swift` | Add `.autoTagging` case to `SettingsTab` enum; wire `SettingsAutoTaggingPaneView` |
| `LargeImageViewerSidebar.swift` | Insert `AutoTagSuggestionsView` between "IMAGE METADATA" and "ACTIVE TAGS" |
| `SidebarView.swift` (TagsSectionView) | Insert compact suggestion row above categories |
| `PhotoLibraryViewModel.swift` | Add `suggestedTags(for:)` method that delegates to `AutoTagEngine` |

### Data Flow

```
Photo focused in large viewer
  → get MetadataSnapshot (already loaded in photoMetadata cache)
  → PhotoLibraryViewModel.suggestedTags(for:)
  → AutoTagEngine.evaluate(metadata, rules: preferences.autoTaggingRules)
  → [AutoTagSuggestion]
  → AutoTagSuggestionsView renders cards
```

### Integration Points

- **LargeImageViewerSidebar** — insert `AutoTagSuggestionsView` between IMAGE METADATA and ACTIVE TAGS (after the `Divider()` following the metadata section)
- **SidebarView (TagsSectionView)** — insert suggestions above the `ForEach(viewModel.tagStore.categories)` loop
- **SettingsPaneWindow** — add `.autoTagging` case to `SettingsTab` enum and `.autoTagging` case in the `switch selectedTab`
- **UserPreferences** — store `autoTaggingEnabled` (Bool, default true) and `autoTaggingRules` ([AutoTagRule], default rules)
- **PhotoLibraryViewModel** — add `suggestedTags(for:)` that reads from `UserPreferences.shared.autoTaggingRules`

---

## 3. Data Model

### AutoTagSuggestion

```swift
struct AutoTagSuggestion: Identifiable, Sendable {
    let id: UUID = UUID()
    let tagName: String           // e.g. "Fuji", "Wide Angle"
    let reason: String            // e.g. "Camera: Fujifilm X-T5" or "35mm eq. 24mm"
    let categoryID: UUID?         // nil = suggest new tag, not = existing category
    let confidence: Confidence    // .high, .medium, .low
}

enum Confidence: String, Codable {
    case high
    case medium
    case low
}
```

### AutoTagRule

```swift
struct AutoTagRule: Codable, Sendable {
    let id: UUID
    var name: String              // Display name in settings, e.g. "Camera Brand"
    var enabled: Bool = true      // Toggle on/off
    var condition: Condition
    var suggestedTags: [SuggestedTag]
}

enum Condition: Codable, Sendable {
    case cameraBrand(contains: String)       // "Fujifilm"
    case focalLength35mm(lessThan: Double)   // 35.0
    case focalLength35mm(moreThan: Double)   // 200.0
    case iso(lessThan: Int)                  // 100
    case iso(moreThan: Int)                  // 6400
    case aperture(lessThan: Double)          // 2.8
    case aperture(moreThan: Double)          // 8.0
    case flashFired
    case flashNotFired
    case aspectRatio(widthToHeight ratio: Double)  // 1.5 = 3:2
    case imageStabilization
    case lensType(contains: String)          // "Macro", "Telephoto"
    case lensTypeNot(contains: String)       // "Prime"
}

struct SuggestedTag: Codable, Sendable {
    let name: String    // The tag name to suggest
    let category: String?  // Optional category to create/use
}
```

### Default Shipped Rules (all enabled by default)

| Condition | Suggested Tag |
|---|---|
| Camera contains "Fujifilm" | "Fuji" |
| 35mm eq. focal length < 35mm | "Wide Angle" |
| 35mm eq. focal length > 200mm | "Telephoto" |
| ISO < 200 | "Low ISO" |
| ISO > 3200 | "High ISO" |
| Aperture < 2.8 | "Shallow Depth of Field" |
| Aperture > 8.0 | "Deep Depth of Field" |
| Flash fired | "Flash" |
| Flash did not fire | "Natural Light" |
| Aspect ratio ~1.5 | "3:2" |
| Aspect ratio ~1.78 | "16:9" |
| Lens contains "Macro" | "Macro" |
| Lens contains "Tele" | "Telephoto" |
| Lens contains "Wide" | "Wide Angle" |

Note: Users can configure lens-based rules (e.g., `lensType(contains: "24-70mm")` → suggest "Zoom") instead of using any hardcoded zoom condition.

---

## 4. Implementation Steps (Phase 1 — Core Engine + Viewer UI)

### Step 1: Create `AutoTagRule.swift` (Models)

**File:** `DuckSort/Models/AutoTagRule.swift`

Define three types: `AutoTagSuggestion`, `AutoTagRule`, `Condition`, and `SuggestedTag`. Implement `Codable` and `Sendable` conformance for all. Provide a static `defaultRules` property that returns the 14 rules listed in Section 3 above.

**Key decisions:**
- `AutoTagSuggestion.id` is auto-generated `UUID()` (not persisted, ephemeral).
- `Condition` uses Codable's `CodingKey` enum with a single `tag` key (the default Codable behavior for enums with associated values).
- `SuggestedTag.category` is `String?` (category name, not ID) — resolved to a real `UUID` at suggestion time by looking up `TagStore`.

**No new dependencies.** Pure Swift types, no SwiftUI.

### Step 2: Create `AutoTagEngine.swift` (Utilities)

**File:** `DuckSort/Utilities/AutoTagEngine.swift`

```swift
class AutoTagEngine: Sendable {
    static let shared = AutoTagEngine()

    func suggestions(
        from metadata: MetadataSnapshot,
        rules: [AutoTagRule],
        tagStore: TagStore
    ) -> [AutoTagSuggestion]
}
```

**Evaluation logic:**
For each enabled rule:
1. Check if the condition matches the metadata (using `MetadataSnapshot` fields).
2. If matched, create a suggestion for each `SuggestedTag` in the rule.
3. Assign confidence:
   - `.high`: exact matches (camera brand, flash fired/not fired, lens contains specific string)
   - `.medium`: ranges (ISO, aperture, focal length thresholds)
   - `.low`: approximations (aspect ratio matching — allow ±5% tolerance)
4. Resolve `SuggestedTag.category` name → `UUID` via `tagStore.categoryID(name:)`. If category exists, set `categoryID`; if not, leave `nil`.
5. **Deduplicate:** If a suggestion with the same `tagName` already exists (same category or no category), skip it.

**Integration with existing `MetadataSnapshot`:**
- `cameraModel` → `Condition.cameraBrand`
- `focalLengthIn35mm` → `Condition.focalLength35mm`
- `iso` → `Condition.iso`
- `aperture` → `Condition.aperture`
- `flashFired` → `Condition.flashFired` / `Condition.flashNotFired`
- `pixelWidth` / `pixelHeight` → `Condition.aspectRatio`
- `lensModel` → `Condition.lensType` / `Condition.lensTypeNot`

**Edge case handling:**
- If `MetadataSnapshot` is empty (no EXIF), return `[]`.
- If a field is `nil` (e.g., no focal length), skip rules that depend on it.
- If a category name doesn't exist in the store, `categoryID` stays `nil`.

### Step 3: Create `AutoTagSuggestionsView.swift` (Views)

**File:** `DuckSort/Views/AutoTagSuggestionsView.swift`

```swift
struct AutoTagSuggestionsView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
}
```

**UI Layout (large viewer sidebar):**

```
┌──────────────────────────────┐
│ SUGGESTED TAGS               │  ← Section header (same style as "ACTIVE TAGS")
│ ┌──────────────────────────┐ │
│ │ Fuji                     │ │  ← Tag name (bold, prominent)
│ │ Camera: Fujifilm X-T5    │ │  ← Reason (smaller text)
│ │ [✓ Accept] [× Dismiss]   │ │  ← Action buttons
│ └──────────────────────────┘ │
│ ┌──────────────────────────┐ │
│ │ Wide Angle               │ │
│ │ 35mm eq. 24mm            │ │
│ │ [✓ Accept] [× Dismiss]   │ │
│ └──────────────────────────┘ │
├──────────────────────────────┤
│ ACTIVE TAGS                  │
└──────────────────────────────┘
```

**Per-suggestion card:**
- **Tag name** — bold, prominent (same font as active tags: `Theme.Font.caption`)
- **Reason** — smaller text, grayed (same as reason text in the design spec)
- **Accept button** (✓) — applies the tag to the current photo (or creates it if it doesn't exist)
- **Dismiss button** (×) — hides this suggestion for the current photo view (ephemeral)

**Integration in `LargeImageViewerSidebar.swift`:**
Insert `AutoTagSuggestionsView(viewModel: viewModel)` between the `Divider()` that follows the IMAGE METADATA section and the "ACTIVE TAGS" section. Only render when `viewModel.currentFocusedPhotoSet != nil` and suggestions are non-empty.

### Step 4: Wire up `PhotoLibraryViewModel`

**File:** `DuckSort/ViewModels/PhotoLibraryViewModel.swift`

Add a method:

```swift
func suggestedTags(for photoSet: PhotoSet) -> [AutoTagSuggestion] {
    guard UserPreferences.shared.autoTaggingEnabled else { return [] }
    guard let metadata = photoMetadata[photoSet.id] else { return [] }
    let rules = UserPreferences.shared.autoTaggingRules.filter(\.enabled)
    return AutoTagEngine.shared.suggestions(from: metadata, rules: rules, tagStore: tagStore)
}
```

This is called from `AutoTagSuggestionsView` via `viewModel.suggestedTags(for: viewModel.currentFocusedPhotoSet!)`.

### Step 5: Handle Accept / Dismiss in the ViewModel

In `PhotoLibraryViewModel`, add two methods:

```swift
func acceptSuggestion(_ suggestion: AutoTagSuggestion, for photoSetID: UUID) {
    // 1. Check if a tag with that name already exists in the active pack
    // 2. If yes, apply the existing tag (existing `applyTag` flow)
    // 3. If no, offer to create it:
    //    - If a category is specified, create the tag in that category
    //    - If no category, create in a new "Auto-Tagged" category (or the user's choice)
    // 4. Write to XMP sidecar (existing `XMPTaggingService` flow)
}

func dismissSuggestion(_ suggestion: AutoTagSuggestion, for photoSetID: UUID) {
    // Ephemeral: store in a local dictionary keyed by (photoSetID, suggestion.tagName)
    // When rendering, filter out dismissed suggestions.
    // No persistence — navigating away and back re-shows the suggestion.
}
```

**Accept flow:**
1. Look up `tagStore` for a tag with matching `suggestion.tagName` (case-insensitive).
2. If found, call existing `applyTag(tag, toPhotoSets: [photo])`.
3. If not found:
   - If `suggestion.categoryID != nil`, create a new tag in that category.
   - If `suggestion.categoryID == nil`, create a new "Auto-Tagged" category (or prompt the user).
4. Write to XMP sidecar via existing `XMPTaggingService.applyTagNames`.

**Dismiss flow (ephemeral):**
- Store dismissed `(photoSetID, tagName)` pairs in a local `Set<(UUID, String)>` on `PhotoLibraryViewModel`.
- Filter them out in `suggestedTags(for:)` before returning.
- Clear the set when the photo changes (new `currentFocusedPhotoSet`).

---

## 5. Implementation Steps (Phase 2 — Settings + Persistence)

### Step 6: Update `UserPreferences.swift`

**File:** `DuckSort/Models/UserPreferences.swift`

Add properties:

```swift
@Published var autoTaggingEnabled: Bool = true
@Published var autoTaggingRules: [AutoTagRule] = AutoTagRule.defaultRules
```

Add persistence keys:

```swift
static let autoTaggingEnabled = "autoTaggingEnabled"
static let autoTaggingRules = "autoTaggingRules"
```

Add to `performSave()`:

```swift
UserDefaults.standard.set(autoTaggingEnabled, forKey: Keys.autoTaggingEnabled)
if let encoded = try? JSONEncoder().encode(autoTaggingRules) {
    UserDefaults.standard.set(encoded, forKey: Keys.autoTaggingRules)
}
```

Add to `load()`:

```swift
autoTaggingEnabled = UserDefaults.standard.bool(forKey: Keys.autoTaggingEnabled)
if let data = UserDefaults.standard.data(forKey: Keys.autoTaggingRules) {
    autoTaggingRules = try? JSONDecoder().decode([AutoTagRule].self, from: data)
        ?? AutoTagRule.defaultRules
}
```

Add to `clear()`:

```swift
UserDefaults.standard.removeObject(forKey: Keys.autoTaggingEnabled)
UserDefaults.standard.removeObject(forKey: Keys.autoTaggingRules)
autoTaggingEnabled = true
autoTaggingRules = AutoTagRule.defaultRules
```

### Step 7: Create `SettingsAutoTaggingPaneView.swift`

**File:** `DuckSort/Views/SettingsAutoTaggingPaneView.swift`

```swift
struct SettingsAutoTaggingPaneView: View {
    @ObservedObject var preferences: UserPreferences
    @ObservedObject var tagStore: TagStore
}
```

**UI Layout:**

```
┌──────────────────────────────────────┐
│ AUTO TAGGING                         │
│ Suggest tags based on EXIF metadata. │
│ Rules are applied per-photo in the   │
│ large viewer.                        │
│                                      │
│ ┌──────────────────────────────────┐ │
│ │ [✓] Camera Brand                 │ │
│ │ Fujifilm → "Fuji"                │ │
│ │                                  │ │
│ │ [✓] Focal Length < 35mm          │ │
│ │ → "Wide Angle"                   │ │
│ │                                  │ │
│ │ [✓] ISO < 200                    │ │
│ │ → "Low ISO"                      │ │
│ └──────────────────────────────────┘ │
│                                      │
│ [+ Add Rule]                         │
└──────────────────────────────────────┘
```

**Components:**
- **Rule list** — scrollable `List` or `VStack` of all rules with enabled toggle
- **Rule editor** — sheet or inline form with:
  - **Name** (free text TextField)
  - **Condition** (picker: Camera Brand, Focal Length, ISO, Aperture, Flash, Aspect Ratio, Lens Type, Image Stabilization)
  - **Condition value** (TextField for brand/lens, NumberField for ISO/focal length/aperture)
  - **Suggested tag name(s)** (one or more TextFields, comma-separated or a List)
  - **Optional category** (dropdown of existing categories, or "Create New")
  - **Enabled toggle** (toggle button)
- **Presets section** — default rules with individual toggles
- **Custom rules section** — user-created rules

### Step 8: Wire Settings Tab

**File:** `DuckSort/Views/SettingsPaneWindow.swift`

Add to `SettingsTab` enum:

```swift
case autoTagging = "Auto Tagging"

var systemImage: String {
    switch self {
    // ... existing cases ...
    case .autoTagging: return "sparkles"
    }
}
```

Add case in `switch selectedTab`:

```swift
case .autoTagging:
    SettingsAutoTaggingPaneView(
        preferences: UserPreferences.shared,
        tagStore: viewModel.tagStore
    )
```

### Step 9: Update `SidebarView.swift` — TagsSectionView

**File:** `DuckSort/Views/SidebarView.swift`

In `TagsSectionView`, insert a compact suggestions row above the `ForEach(viewModel.tagStore.categories)` loop:

```
┌──────────────────────────────┐
│ TAGS                         │
│ ───────────────────────────  │
│ Flags & Ratings              │
│ ───────────────────────────  │
│ SUGGESTIONS     (3)          │  ← NEW (compact row)
│ Fuji · Wide Angle · Macro    │
│ [Apply All] [× Dismiss All]  │
│ ───────────────────────────  │
│ Scene                        │
│ Fuji (2)  Wide Angle (3)     │
│ Macro (1)                    │
│ ───────────────────────────  │
│ Action                       │
│ ...                          │
└──────────────────────────────┘
```

Only render when the current photo has suggestions and the sidebar is visible in large viewer mode.

---

## 6. Tag Creation on Accept

When the user accepts a suggestion:

1. **Check if a tag with that name already exists** in the active pack (case-insensitive lookup via `tagStore.tags`).
2. **If yes**, apply the existing tag using the existing `applyTag(tag, toPhotoSets:)` flow.
3. **If no**, create it:
   - If `suggestion.categoryID != nil`, create the tag in that existing category.
   - If `suggestion.categoryID == nil`, create a new "Auto-Tagged" category (or prompt the user to choose).
4. **Write to XMP sidecar** using the existing `XMPTaggingService.applyTagNames` flow.

**Existing code reused:**
- `tagStore.addTag(name:categoryID:)` — for creating new tags
- `tagStore.categoryID(name:)` — for resolving category names
- `XMPTaggingService.applyTagNames(_:to:)` — for persisting to XMP

---

## 7. Settings Integration

### UserPreferences additions (Phase 2)

```swift
@Published var autoTaggingEnabled: Bool = true
@Published var autoTaggingRules: [AutoTagRule] = defaultRules
```

### SettingsTab enum (Phase 2)

Add `.autoTagging` to `SettingsTab` enum in `SettingsPaneWindow.swift`.

### SettingsAutoTaggingPaneView (Phase 2)

- **Rule list view** — scrollable list of all rules with toggles
- **Rule editor** — sheet with condition picker, value input, suggested tag input
- **Presets** — section for default rules that can be individually toggled
- **Custom rules** — section for user-created rules

---

## 8. File Locations (Summary)

| File | Status | Purpose |
|---|---|---|
| `DuckSort/Models/AutoTagRule.swift` | **NEW** | Rule, Condition, SuggestedTag models |
| `DuckSort/Utilities/AutoTagEngine.swift` | **NEW** | EXIF analysis engine |
| `DuckSort/Views/AutoTagSuggestionsView.swift` | **NEW** | Large viewer sidebar suggestions |
| `DuckSort/Views/SettingsAutoTaggingPaneView.swift` | **NEW** (Phase 2) | Settings tab |
| `DuckSort/Models/UserPreferences.swift` | **MODIFY** (Phase 2) | Add autoTaggingEnabled + autoTaggingRules |
| `DuckSort/Views/SettingsPaneWindow.swift` | **MODIFY** (Phase 2) | Add `.autoTagging` tab |
| `DuckSort/Views/Components/LargeImageViewerSidebar.swift` | **MODIFY** | Insert suggestions section |
| `DuckSort/Views/SidebarView.swift` | **MODIFY** | Insert suggestions in TagsSectionView |
| `DuckSort/ViewModels/PhotoLibraryViewModel.swift` | **MODIFY** | Add `suggestedTags(for:)`, `acceptSuggestion`, `dismissSuggestion` |

---

## 9. Edge Cases

- **No EXIF data** — no suggestions shown (empty `MetadataSnapshot` → empty results).
- **Missing focal length** — skip focal length rules for that photo.
- **Camera model not in EXIF** — skip camera brand rules for that photo.
- **Accepted tag doesn't exist** — offer to create it in existing or new category (existing `applyTag` flow handles creation).
- **Multiple suggestions for same tag** — deduplicate (same `tagName` + same `categoryID` → one suggestion).
- **User creates a tag with the same name as a suggestion** — next time the photo is focused, the suggestion shows as already applied (grayed out with "Applied" label).
- **Auto-tagging disabled in preferences** — `suggestedTags(for:)` returns `[]` immediately, zero overhead.
- **Photo navigated away** — dismissed suggestions are cleared (ephemeral).
- **Library re-scanned** — dismissed suggestions are lost (ephemeral per-session, per-photo).

---

## 10. Non-Goals

- Batch scanning during library import (out of scope for v1).
- Persistence of dismissed suggestions across app relaunches (ephemeral per-session).
- Auto-applying suggestions without user confirmation.
- ML-based image content analysis (EXIF metadata only).
- Suggestion ranking or scoring beyond confidence levels.

---

## 11. Testing Strategy

### Unit tests (Phase 1)

- `AutoTagEngine` tests with mock `MetadataSnapshot` for each condition type.
- Deduplication tests (same tag from multiple rules → one suggestion).
- Empty/nil metadata handling (no crash, returns `[]`).

### Integration tests (Phase 1)

- Accept flow: suggestion → tag creation → XMP write.
- Dismiss flow: ephemeral dismissal clears from view, reappears on re-focus.

### Manual QA (Phase 1)

- Test with real Fuji, Sony, Canon, Nikon RAW files to verify camera brand detection.
- Test wide-angle (24mm), telephoto (200mm+), and normal focal lengths.
- Test high/low ISO ranges.
- Test shallow/deep aperture ranges.
- Test flash on/off scenarios.
- Test aspect ratio detection (3:2, 16:9).
- Test lens name detection (Macro, Tele, Wide).

---

## 12. Estimated Effort

| Phase | Components | Estimated Time |
|---|---|---|
| **Phase 1 — Core** | Models + Engine + Viewer UI + ViewModels | 2–3 days |
| **Phase 2 — Settings** | UserPreferences + Settings tab + Sidebar integration | 1–2 days |
| **Testing + QA** | Unit tests + manual QA with real photos | 1 day |
| **Total** | | **4–6 days** |
