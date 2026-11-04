# Design QA

**Evidence**

- Source visual truth: `/Users/pure/.codex/generated_images/01a0585a-5d89-7041-be78-178af3d58ca6/exec-8d41b578-6182-442d-9646-7998e78e597a.png`
- Implementation screenshot: `/Users/pure/Documents/better-photography-workflow/design-qa-implementation.png`
- Side-by-side comparison: `/Users/pure/Documents/better-photography-workflow/design-qa-comparison.png`
- Source pixels: 1487 × 1058.
- Implementation pixels: 1298 × 768, captured from the maximized native macOS window.
- Comparison normalization: source scaled proportionally to 768 px high; implementation kept at native screenshot density; a 24 px neutral gutter separates the images.
- CSS viewport: not applicable; this is a native SwiftUI macOS application.
- State: light appearance, `进行中` selected, `上海周末 Vlog` expanded at 71%, default project data.

**Full-view comparison**

The implementation preserves the selected concept's project-first hierarchy: Liquid Glass navigation, a light content layer, title and sorting controls, one expanded project, seven-stage progress rail, device-to-SSD relationship, project action, and two compact projects. The live window is wider and shorter than the generated source because it was captured at the current display's maximized native frame; the hierarchy remains intact with no clipping or overlap.

**Focused-region comparison**

The expanded project region was checked at full screenshot resolution because it contains the densest typography, stage states, icons, controls, and storage metadata. The sidebar and two compact rows were also checked for selection, menu, progress, and disclosure affordances. Separate crops were unnecessary because all labels and states remained legible at original resolution.

**Required fidelity surfaces**

- Fonts and typography: system San Francisco/Chinese fallback, hierarchy, weights, wrapping, and truncation are coherent and match the native macOS intent. No clipped copy was observed.
- Spacing and layout rhythm: page padding, card grouping, stage spacing, device grouping, and compact-row rhythm match the source intent. The implementation intentionally expands the destination surface at the wider live aspect ratio.
- Colors and visual tokens: system background, semantic blue, success green, separators, and macOS Liquid Glass are used. Content surfaces remain standard material instead of applying glass everywhere.
- Image quality and asset fidelity: device and storage representations use sharp SF Symbols rather than raster product thumbnails. This is an intentional native-code adaptation; no placeholder or low-resolution asset is present.
- Copy and content: project names, percentages, date, stages, devices, destination, and single-library verification state match the selected concept.

**Interaction verification**

- Sidebar navigation to Settings and back to Active Projects passed.
- `标记当前阶段完成` advanced the project from 71%/剪辑中 to 84%/导出成片 and updated stage states.
- Sort, overflow, favorite, continue-project, and compact-row disclosure controls are exposed as native accessible controls.
- Accessibility tree contains semantic labels for navigation, buttons, progress indicators, device symbols, and stage states.
- Browser console checks are not applicable to this native SwiftUI build.

**Comparison history**

- Initial finding: the app followed the host's dark appearance instead of the selected light concept. Fix: applied the selected light appearance to the root experience. Post-fix evidence: final implementation screenshot.
- Initial finding: the global Save button leaked into the Active Projects toolbar. Fix: limited it to Settings. Post-fix evidence: final implementation screenshot.
- Initial finding: compact project rows lacked the source's overflow affordance and the manual stage action lacked accent emphasis. Fix: added native glass overflow menus and accent-colored action styling. Post-fix evidence: final implementation screenshot.

**Findings**

No actionable P0, P1, or P2 mismatch remains.

**Follow-up polish**

- [P3] Replace generic device SF Symbols with device-profile artwork after the device-recognition model is implemented.
- [P3] Add responsive compact-stage labels for windows narrower than the current 1100 pt minimum if that minimum is relaxed later.

**Implementation checklist**

- [x] Native Liquid Glass functional layer with pre-macOS 26 fallback.
- [x] Project-first navigation and active-project hierarchy.
- [x] Functional stage advancement and project disclosure controls.
- [x] Swift tests and release app build.
- [x] Native screenshot comparison and interaction verification.

final result: passed
