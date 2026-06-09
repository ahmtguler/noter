# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Noter is a native macOS popup notes app (Raycast Notes / Obsidian Quick Note style). It lives in the menu bar (`LSUIElement = YES`, no Dock icon), summons via a global hotkey, and stores plain `.md` files inside an Obsidian vault subfolder. The editor is **CodeMirror 6 inside a hidden `WKWebView`**, packaged as a local SwiftPM module. Most editor "feel" issues should be fixed in JS, not Swift.

## Common commands

`make` runs everything from the repo root.

| Command | Use |
|---|---|
| `make run` | Release build + launch the `.app` |
| `make build` | Release build only |
| `make test` | `xcodebuild test` (Swift Testing + XCTest) |
| `make fmt` | SwiftFormat the whole tree |
| `make lint` | `swiftlint --strict` |
| `make ci` | What CI runs: lint + test + build |
| `make generate` | Regenerate `Noter.xcodeproj` from `project.yml` (xcodegen) |
| `make hooks` | `lefthook install` |

Runtime helpers:

```bash
# Tail Noter's logs (custom NSLogs are prefixed [Noter] / [MarkdownEditor]).
/usr/bin/log show --last 5m --predicate 'process == "Noter"' --info --debug --style compact

# Kill any running instance.
pkill -f "Noter.app/Contents/MacOS/Noter"

# Run a single Swift test (matches against the test name).
xcodebuild test -project Noter.xcodeproj -scheme Noter \
  -destination 'platform=macOS' \
  -only-testing:NoterTests/SlugifyTests/stripsLeadingHeadingMarkers
```

## CodeMirror bundle (the JS in `Packages/MarkdownEditor/JS/`)

```bash
cd Packages/MarkdownEditor/JS
npm install              # one time
npm run build            # writes ../Sources/MarkdownEditor/Resources/editor.bundle.js
npm run watch            # rebuild on every save while iterating
```

The compiled bundle is committed so a fresh `swift build` works without Node. **Always rebuild the bundle** after editing any `.ts` file in `JS/src/` — Swift only ships the bundle, not the TypeScript sources.

## Hooks (lefthook)

`lefthook install` wires:
- **pre-commit**: SwiftFormat (auto-fixes & re-stages) + SwiftLint `--strict` on staged Swift files.
- **commit-msg**: commitlint with [Conventional Commits](https://www.conventionalcommits.org/). **Header is hard-capped at 100 characters**; the rest of the body is free.
- **pre-push**: `xcodebuild build` (Debug) + `xcodebuild test`.

The pre-commit lint pass runs `swiftlint --strict --quiet`; warnings fail the commit. Common gotchas this repo's `.swiftlint.yml` enforces: `opening_brace`, `cyclomatic_complexity`, `function_parameter_count <= 5`, `type_body_length`, `force_unwrapping`. SwiftFormat re-orders imports alphabetically, so don't manually order them.

## Architecture (the big picture)

### Two halves of the editor

```
RootView (SwiftUI)
   │
   ├─ MarkdownEditor  ───────────────►  WKWebView  ◄── editor.html + editor.bundle.js (CodeMirror 6)
   │   (SwiftPM package)                   ▲                       │
   │                                       │                       │
   │   ┌───────────────────────────────────┴───────────────────────┴────┐
   │   │  EditorBridge                                                  │
   │   │     Swift  →  JS:   evaluateJavaScript(window.bridge.*)        │
   │   │     JS  →  Swift:   WKScriptMessageHandler ('editor' channel)  │
   │   └────────────────────────────────────────────────────────────────┘
   │
   ├─ ToolbarView ── calls MarkdownCommands.bold() / heading(level) / …
   │                  which sends an OutboundMessage.execute over the bridge
   │
   └─ EditorState ── @MainActor ObservableObject; debounces saves to disk
                     (500ms), promotes blank drafts into real .md files on
                     first non-empty save, renames file to track first-line
                     slug
```

**Where to fix things**:
- Toolbar selection-aware behaviour, marker hiding, list bullet glyphs, task checkboxes, syntax → `Packages/MarkdownEditor/JS/src/`. Re-bundle after editing.
- App lifecycle, vault access, hotkey, panel chrome, preferences UI → Swift sources under `Noter/`.
- Public API of the package (the surface Noter consumes) → `Packages/MarkdownEditor/Sources/MarkdownEditor/`. Keep it tiny — the package is designed to be liftable into its own repo later.
- In-editor link inspect/edit popover → `Packages/MarkdownEditor/Sources/MarkdownEditor/Link/`. JS (`linkInteractions.ts`) posts `linkInspect` on hover / handles clicks; the Swift `LinkPopoverState` + `LinkPopoverOverlay` render an in-bounds SwiftUI popover (deliberately *not* a free-floating `NSPopover`) and dispatch `linkApply` / `linkRemove` back over the bridge.

### Bridge protocol

JS → Swift via `WKScriptMessageHandler`:

```js
{ kind: "ready" }                                           // editor is mounted
{ kind: "textChanged", text }                              // doc edited
{ kind: "selectionChanged", styles: ["bold", "italic", …] }// caret moved / styles shifted
{ kind: "log", level, message }                            // dev console relay
```

Swift → JS via `evaluateJavaScript`:

```js
window.bridge.setText(text)
window.bridge.exec("bold" | "heading" | …, arg?)
window.bridge.applyConfig(EditorConfig)
```

`EditorBridge` queues outbound messages until JS reports `ready`, then flushes — so the editor receives the initial text and config in the right order.

### Floating overlays (⌘P switcher, ⌘K command palette)

Both are plain **SwiftUI overlays inside `RootView`'s `ZStack`** — not separate `NSWindow`s. They're toggled by `@State` flags (`showSwitcher` / `showCommandPalette`) that `RootView` flips when it receives the matching notification from `PanelKeyMonitor`. A near-transparent backdrop (`Color.black.opacity(0.001)`) catches outside taps to dismiss.

- `Noter/Switcher/SwitcherOverlay.swift` — ⌘P note switcher: fuzzy-match titles (`FuzzyMatcher`) + full-text body search, pinned notes float to top, arrow/Enter nav, per-row pin & delete. Keystrokes land in `SearchField` (an `NSViewRepresentable` text field that forwards ↑/↓/Enter/Esc).
- `Noter/CommandPalette/CommandPaletteOverlay.swift` — ⌘K palette: a flat action list (new / browse / duplicate / pin / delete / preferences) plus a "Recently Deleted" sub-mode with Restore / Delete-permanently rows. It has no text field, so `KeyCatcher` (an invisible first-responder `NSView`) captures the arrow/Enter/Esc keys instead.

**The cursor-over-overlay problem** (recurring — read before touching cursor code): the WKWebView underneath asserts CodeMirror's `cursor: text` (I-beam) on every `mouseMoved` it receives, which fights any arrow cursor the overlay sets. WebKit applies that cursor via **async IPC** from its content process, so host-side `NSCursor.set()` timing tricks (push/pop, a 30Hz heartbeat, a one-tick-deferred `.onContinuousHover` set — all in git history) can't reliably out-race it and flicker. The fix is **convergence: every cursor claimant over an open overlay must agree on arrow**, because the async claimant can't be beaten, only joined. (1) `RootView` calls `MarkdownCommands.setCursorSuppressed(true)` whenever an overlay is up, toggling the `noter-cursor-suppressed` class (`editor.css`) so the web content reports `cursor: default` — WebKit's IPC assertion becomes arrow. (2) `ArrowCursorArea` (an `NSTrackingArea` with `.cursorUpdate`) claims arrow for the panel. (3) The switcher's search field would be the last dissenter: it's focused while the switcher is open, its field editor is first responder, and AppKit routes every `mouseMoved` to the first responder where NSTextView re-asserts the I-beam — so `PanelController.windowWillReturnFieldEditor` hands it `ArrowCursorFieldEditor`, which no-ops `mouseMoved` and pins `cursorUpdate`/cursor rects to arrow. The search field deliberately shows **arrow, not I-beam** — stable I-beam would require WebKit to report I-beam for exactly that rect across the process boundary (fragile geometry sync), and a SwiftUI-side I-beam claim over the field was tried and still flickered against WebKit's async arrow. Don't reintroduce a deferred `NSCursor.set()` race, and don't "fix" the search field's arrow cursor back to an I-beam.

### Key files & responsibilities

- `Noter/AppDelegate.swift` — `applicationDidFinishLaunching` wires `AppViewModel`, the `PanelController`, the `MenuBarController`, the `KeyboardShortcuts` global hotkey, the `PreferencesWindowController`, and an observer on `.noterShowPreferences`.
- `Noter/AppViewModel.swift` — owns the live `NoteStore` and `EditorState`. `reloadVault()` swaps both when the user changes the vault path so all observers re-render.
- `Noter/Window/PopupPanel.swift` — `NSWindow` (not `NSPanel` — the older `NSPanel` config crashed on macOS 26 because `.canJoinAllSpaces` and `.moveToActiveSpace` are mutually exclusive). All traffic-light buttons are hidden; the SwiftUI title bar is the only chrome.
- `Noter/Window/PanelController.swift` — show/hide/toggle, frame persistence, hide-on-blur (with a `suppressHideUntil` window to defeat transient activation glitches in `LSUIElement` apps), and `applyAppearance()` keyed off `SettingsKey.editorTheme` so the visual-effect blur tracks the user's theme choice live.
- `Noter/Window/PanelKeyMonitor.swift` — `NSEvent.addLocalMonitorForEvents` that intercepts ⌘N / ⌘P / ⌘K / ⌘, before the WKWebView consumes them and posts notifications (`.noterNewNote` / `.noterShowSwitcher` / `.noterShowCommandPalette` / `.noterShowPreferences`). Hidden SwiftUI `.keyboardShortcut` buttons aren't enough because the web view eats the event first.
- `Noter/Store/NoteStore.swift` — `@MainActor` ObservableObject. CRUD against `.md` files. Auto-renames on first-line change with `Slugify.filename` (collisions get ` 2`, ` 3` suffixes). Also owns **soft-delete** (`delete` moves to a `.trash` subfolder; `trashedNotes` / `restoreTrashed` / `permanentlyDeleteTrashed`; `purgeExpiredTrash` drops items older than 14 days) and **pins** (`pinnedPaths` persisted to defaults; `togglePin` / `isPinned`). `duplicate(_:)` copies a note as a new file.
- `Noter/Preferences/PreferencesWindowController.swift` — the **only** preferences entry point. SwiftUI's `Settings` scene doesn't surface in `LSUIElement` apps (no main menu), so we host `PreferencesView` in a plain `NSWindow`. The `Settings { EmptyView() }` in `NoterApp.swift` is a vestigial stub kept only to satisfy the `App` protocol.
- `Noter/Settings/EditorAppearancePreference.swift` — the typed enum (`.system / .light / .dark`) backing `SettingsKey.editorTheme`. Maps to the package's `EditorConfiguration.Theme`, SwiftUI `ColorScheme?`, and `NSAppearance?`. Use this enum, not raw strings.
- `Noter/Onboarding/` — first-launch flow. `AppDelegate` shows `OnboardingWindowController` (hosting `FirstLaunchView`) after the panel is wired, gated on a defaults flag; it walks the user through picking the Obsidian vault folder before the popup is usable.

## Required entitlement: `com.apple.security.network.client`

WKWebView spawns a child content process under the sandbox; without this entitlement (set in `project.yml` under `entitlements.properties`) the content process crashes on launch and the editor area renders blank. The app loads no actual network resources — the entitlement is for the WebKit IPC.

## Project generation

The Xcode project is generated from `project.yml` via xcodegen and **is in `.gitignore`**. After editing `project.yml` (or after creating a new Swift file in a path xcodegen needs to know about, e.g. a new `Noter/Editor/Foo.swift`), run `xcodegen generate` so xcodebuild sees it.

Local SwiftPM packages are referenced under `packages:` in `project.yml`:

```yaml
packages:
  MarkdownEditor:
    path: Packages/MarkdownEditor
```

…and added as a dep on the Noter target via `dependencies: - package: MarkdownEditor`.

## Conventional Commits

Format: `<type>(<scope>): <subject>` with subject in lowercase, total header ≤ 100 chars. Allowed types: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `style`, `perf`, `ci`, `build`, `revert`. Scopes used in this repo include `editor`, `noter`, `prefs`, `window`, `store`, `switcher`, `palette`, `onboarding`.

## Things that look wrong but aren't

- `Packages/MarkdownEditor/Sources/MarkdownEditor/Resources/editor.bundle.js` is a 500 KB committed binary blob. That's intentional: it lets `swift build` work without Node.
- `Settings { EmptyView() }` in `NoterApp.swift` looks pointless — it's deliberately a no-op; preferences are hosted by `PreferencesWindowController`.
- The `WKWebView`-based editor's child process needs `com.apple.security.network.client` despite never making a network request. Don't remove that entitlement.
- `PanelController` listens to `UserDefaults.didChangeNotification` for *every* defaults change, just to reapply the panel's `appearance`. The cost is one read per change; it keeps theme switching responsive while the popup is visible.
- The overlays no longer chase the cursor with a deferred `.onContinuousHover { … NSCursor.arrow.set() }`. That async dance raced WebKit's IPC-applied I-beam and flickered. The editor now suppresses its own I-beam while an overlay is up (`setCursorSuppressed`), so `ArrowCursorArea` alone suffices. See "Floating overlays" above before adding cursor code back.
- The ⌘P search field shows an **arrow** cursor, not the I-beam a text input normally gets. Deliberate: its field editor (`ArrowCursorFieldEditor`) is neutered so it can't flicker against WebKit's async arrow assertion. See "Floating overlays" above before restoring the I-beam.
- `PaletteCommand.id` / row ids are stable string tokens, not `UUID()`. Random ids would make `ForEach` treat every row as new on each re-render, tearing down state and dropping focus.
