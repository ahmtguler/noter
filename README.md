# Noter

A native macOS popup notes app inspired by Raycast Notes. Lives in your menu bar, summons instantly via a global hotkey, and stores plain `.md` files inside an Obsidian vault subfolder so your notes round-trip with Obsidian automatically.

## Features

- 🪟 **Floating popup window** — pinnable, summoned via a global hotkey you set on first launch. Snaps to screen corners.
- 👻 **Hides on focus loss** — clicking another app dismisses the popup; the pin button overrides this.
- ✍️ **Live-preview markdown editor** — CodeMirror 6 with syntax markers hidden as you type: headings, bold, italic, inline code, blockquotes, code blocks, and links render inline.
- ☑️ **Clickable task checkboxes** — `- [ ]` renders as a real checkbox you can toggle with the mouse.
- 🔗 **Inline link popover** — hover a link to inspect it, or select text and hit the toolbar Link button to create one.
- ⌘P **Note switcher** — fuzzy title search plus full-text body search, arrow-key navigation, pinned notes float to the top, per-row pin and delete.
- ⌘K **Command palette** — new, browse, duplicate, pin, delete, preferences, and a Recently Deleted view with restore.
- ⌘N **New note** — auto-named from the first line; renames the file when the first line changes (Obsidian-style), with collision-safe suffixing.
- 🗑️ **Soft delete** — deleted notes move to a `Recently Deleted` subfolder and are purged after 14 days.
- 💾 **Debounced autosave** — files are written 500ms after the last keystroke; no save button.
- 📁 **Stores files in your Obsidian vault** — a security-scoped bookmark gives sandboxed access; you pick the subfolder.
- 🎨 **Theme and font size preferences** — system/light/dark, with the panel blur tracking your choice live.
- 🪶 **Near-zero idle resource use** — `LSUIElement = YES` (no Dock icon), panel hidden via `orderOut` rather than destroyed, no timers, no FS watchers.

## Architecture at a glance

The editor is **CodeMirror 6 running inside a hidden `WKWebView`**, packaged as a local SwiftPM module (`Packages/MarkdownEditor`). Swift and JavaScript talk over a small bridge:

```
RootView (SwiftUI)
   ├─ MarkdownEditor ──► WKWebView ◄── editor.html + editor.bundle.js (CodeMirror 6)
   │      Swift → JS:  evaluateJavaScript(window.bridge.*)
   │      JS → Swift:  WKScriptMessageHandler ('editor' channel)
   ├─ ToolbarView   ──► MarkdownCommands.bold() / heading(level) / …
   └─ EditorState   ──► debounced saves, draft promotion, slug-tracking renames
```

Going native (TextKit) would mean hand-building marker hiding, checkbox widgets, list continuation, and selection-aware style detection. CodeMirror gives all of that for the cost of one WebKit content process (~50 MB idle). Most editor "feel" issues are therefore fixed in TypeScript, not Swift.

## Prerequisites

- macOS 14 (Sonoma) or later.
- **Xcode** from the App Store. After install:
  ```sh
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  sudo xcodebuild -license accept
  sudo xcodebuild -runFirstLaunch
  ```
- Homebrew tools:
  ```sh
  brew install lefthook swiftlint swiftformat xcbeautify xcodegen
  ```
- **Node 20+** — required for commitlint (commit-msg hook) and for rebuilding the CodeMirror bundle.

## Quick start

```sh
git clone https://github.com/ahmtguler/noter.git
cd noter
make hooks              # install git hooks via lefthook
make generate           # generate Noter.xcodeproj from project.yml
make run                # release build + launch
```

On first launch you'll be asked to pick your Obsidian vault folder, set a subfolder, and record a global hotkey.

> `Noter.xcodeproj` is generated and gitignored. Re-run `make generate` after editing `project.yml` or adding a Swift file in a new directory.

## Daily commands

| Command | What it does |
|---|---|
| `make run` | Release build and launch the app |
| `make build` | Release build only |
| `make test` | Run all tests (app + MarkdownEditor package) |
| `make fmt` | Format all Swift sources with SwiftFormat |
| `make lint` | Lint with SwiftLint (`--strict`) |
| `make ci` | Everything CI runs: format check, lint, test, build |
| `make generate` | Regenerate `Noter.xcodeproj` from `project.yml` |
| `make hooks` | Install lefthook git hooks |
| `make clean` | Clean build artifacts |

### CodeMirror bundle

The compiled bundle is committed so a fresh `swift build` works without Node. **Rebuild it after editing any `.ts` file** — Swift ships the bundle, not the TypeScript sources.

```sh
cd Packages/MarkdownEditor/JS
npm install       # one time
npm run build     # writes ../Sources/MarkdownEditor/Resources/editor.bundle.js
npm run watch     # rebuild on every save while iterating
```

CI verifies the committed bundle matches `JS/src/`, so a stale bundle fails the build rather than silently shipping.

## Development workflow

This repo uses **trunk-based development**. `main` is always releasable and protected — no direct pushes.

```sh
git checkout -b feat/my-thing    # branch off main
# ... work, committing in Conventional Commits format ...
git push -u origin feat/my-thing
gh pr create                     # CI must pass before merge
```

Branch prefixes mirror the commit types: `feat/`, `fix/`, `chore/`, `docs/`, `refactor/`, `test/`, `ci/`, `perf/`, `build/`, `style/`.

Commits follow [Conventional Commits](https://www.conventionalcommits.org/): `<type>(<scope>): <subject>`, subject lowercase, header ≤ 100 characters. Scopes used here: `editor`, `noter`, `prefs`, `window`, `store`, `switcher`, `palette`, `onboarding`.

### Git hooks

`make hooks` wires:

| Hook | What it runs |
|---|---|
| pre-commit | SwiftFormat (auto-fix and re-stage) + SwiftLint `--strict`; TypeScript typecheck and bundle rebuild when `.ts` files change |
| commit-msg | Conventional Commits validation via commitlint |
| pre-push | Blocks direct pushes to `main`; builds (Debug) and runs tests |

Hooks degrade gracefully — if you haven't run `make generate`, or only have Command Line Tools installed, they skip with a message and let CI enforce instead.

## Project layout

```
Noter/                              # the app
├── NoterApp.swift                  # @main; Settings scene is a deliberate no-op stub
├── AppDelegate.swift               # menu bar, hotkey, panel lifecycle, onboarding gate
├── AppViewModel.swift              # owns NoteStore + EditorState; reloadVault()
├── Window/
│   ├── PopupPanel.swift            # NSWindow: floating, non-activating, all spaces
│   ├── PanelController.swift       # show/hide/toggle, frame persistence, hide-on-blur
│   ├── PanelKeyMonitor.swift       # intercepts ⌘N/⌘P/⌘K/⌘, before the web view eats them
│   ├── MenuBarController.swift     # NSStatusItem (left-click toggle, right-click menu)
│   └── Shortcuts.swift             # KeyboardShortcuts.Name.toggleNoter
├── Editor/
│   ├── RootView.swift              # title bar + editor + toolbar + overlay hosting
│   ├── EditorState.swift           # debounced autosave, draft promotion, rename tracking
│   ├── ToolbarView.swift           # bottom formatting buttons
│   └── VisualEffectBackground.swift
├── Switcher/                       # ⌘P note switcher (fuzzy + full-text search)
├── CommandPalette/                 # ⌘K palette and Recently Deleted view
├── Store/
│   ├── Note.swift                  # value type
│   ├── Slugify.swift               # title and filename derivation
│   └── NoteStore.swift             # CRUD over .md files, soft delete, pins
├── Preferences/                    # preferences window (hosted manually, not SwiftUI Settings)
├── Onboarding/                     # first-launch vault picker flow
└── Settings/                       # UserDefaults keys and typed preference enums

Packages/MarkdownEditor/            # liftable SwiftPM package — the editor
├── Sources/MarkdownEditor/
│   ├── MarkdownEditor.swift        # the public SwiftUI view
│   ├── EditorCommands.swift        # bold(), heading(level), todo(), …
│   ├── EditorConfiguration.swift   # theme, font size
│   ├── Bridge/                     # Swift ↔ JS message plumbing
│   ├── Link/                       # in-editor link inspect/edit popover
│   └── Resources/                  # editor.html, editor.css, editor.bundle.js
└── JS/src/                         # CodeMirror 6 TypeScript sources
    ├── index.ts                    # editor setup and bridge wiring
    ├── livePreview.ts              # decorations that hide markdown markers
    ├── commands.ts                 # bold/italic/heading/list transforms
    ├── detectStyles.ts             # selection-aware active-style detection
    ├── inputHandlers.ts            # smart Enter, list continuation
    ├── linkInteractions.ts         # hover inspect, click to open
    └── theme.ts
```

## Manual verification checklist

After `make run`:

1. **Cold start** — no Dock icon, menu-bar icon appears, no window.
2. **First launch** — onboarding opens; pick vault, set subfolder, record hotkey.
3. **Hotkey** — popup appears in under 100ms; the previously frontmost app stays active.
4. **Hide on blur** — clicking another app hides the popup; the hotkey restores position and size.
5. **Pin** — toggle pin, click another app, popup stays.
6. **Editing** — `# Hello` renders as a heading with the `#` hidden; after 500ms a `Hello.md` appears in the vault subfolder.
7. **Rename** — change the first line to `# Hello world` → the file renames to `Hello world.md`.
8. **⌘P switcher** — fuzzy search by title, arrows navigate, Enter switches; pinned notes sort first.
9. **⌘K palette** — duplicate, pin, delete; Recently Deleted restores a trashed note.
10. **Full-text search** — query a word that appears only in a body; that note still shows up.
11. **Obsidian** — open the same vault in Obsidian; files appear under the subfolder.
12. **Idle footprint** — with the popup hidden: CPU 0%, Energy Impact 0.

## License

MIT — see [LICENSE](LICENSE).
