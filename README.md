# Noter

A native macOS popup notes app inspired by Raycast Notes. Lives in your menu bar, summons instantly via a global hotkey, and stores plain `.md` files inside an Obsidian vault subfolder so your notes round-trip with Obsidian automatically.

## Features

- 🪟 **Floating popup window** — pinnable, summoned via a global hotkey you set on first launch.
- 👻 **Hides on focus loss** — clicking another app dismisses the popup; pin button overrides this.
- ✍️ **Hybrid live-preview markdown editor** — headings, bold, italic, inline code, blockquotes and links styled inline as you type, with markers visible (Bear/Raycast style).
- ⌘P **Note switcher** — fuzzy title search + full-text body search, arrow-key navigation, "Current" chip on the active note, last-modified + character-count metadata.
- ⌘N **New note** — auto-named from the first line; renames the file when the first line changes (Obsidian-style).
- 💾 **Debounced autosave** — files are written 500ms after the last keystroke; no save button.
- 📁 **Stores files in your Obsidian vault** — security-scoped bookmark gives sandboxed access; pick the subfolder.
- 🪶 **Near-zero idle resource use** — `LSUIElement = YES` (no Dock icon), panel hidden via `orderOut` instead of being destroyed, no timers, no FS watchers.

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
- Node (for commitlint, used by the commit-msg hook).

## Quick start

```sh
git clone https://github.com/ahmtguler/noter.git
cd noter
lefthook install        # install git hooks
xcodegen generate       # generate Noter.xcodeproj from project.yml
open Noter.xcodeproj    # build & run from Xcode (⌘R)
```

On first launch you'll be asked to pick your Obsidian vault folder, set a subfolder, and record a global hotkey.

## Daily commands

| Command       | What it does                                |
|---------------|---------------------------------------------|
| `make fmt`    | Format all Swift sources with SwiftFormat   |
| `make lint`   | Lint with SwiftLint (`--strict`)             |
| `make test`   | Run unit tests via `xcodebuild`              |
| `make build`  | Release build                                |
| `make run`    | Build and launch the app                     |
| `make ci`     | What CI runs: lint + test + build            |
| `make generate` | Regenerate `Noter.xcodeproj` from project.yml |

## Git hooks

`lefthook install` wires:

| Hook        | What it runs                                     |
|-------------|--------------------------------------------------|
| pre-commit  | SwiftFormat (auto-fix and re-stage) + SwiftLint  |
| commit-msg  | [Conventional Commits](https://www.conventionalcommits.org/) validation via commitlint |
| pre-push    | Build (Debug) + tests, both via `xcodebuild`     |

Hooks gracefully skip if you haven't run `xcodegen generate` yet, so a fresh clone can still scaffold itself.

## Project layout

```
Noter/
├── NoterApp.swift              # @main, hooks up AppDelegate and Settings scene
├── AppDelegate.swift           # menu bar, hotkey, panel lifecycle, onboarding gate
├── AppViewModel.swift          # owns NoteStore + EditorState; reloadVault()
├── Window/
│   ├── PopupPanel.swift        # NSPanel: floating, non-activating, joins all spaces
│   ├── PanelController.swift   # show/hide/toggle, frame persistence, hide-on-blur
│   ├── MenuBarController.swift # NSStatusItem (left-click toggle, right-click menu)
│   └── Shortcuts.swift         # KeyboardShortcuts.Name.toggleNoter
├── Editor/
│   ├── EditorView.swift        # NSTextView wrapped for SwiftUI
│   ├── MarkdownStyler.swift    # NSTextStorageDelegate — regex-based live styling
│   ├── EditorState.swift       # debounced autosave with URL-snapshot tracking
│   ├── ToolbarView.swift       # bottom formatting buttons
│   └── RootView.swift          # editor + toolbar + pin + ⌘P/⌘N shortcuts
├── Switcher/
│   ├── FuzzyMatcher.swift      # subsequence scorer with word-start/consecutive bonuses
│   ├── SearchField.swift       # NSTextField that forwards arrows/Enter/Esc
│   └── SwitcherOverlay.swift   # the ⌘P picker UI
├── Store/
│   ├── Note.swift              # value type
│   ├── Slugify.swift           # title + filename derivation
│   └── NoteStore.swift         # @MainActor ObservableObject; CRUD against .md files
├── Preferences/
│   ├── PreferencesView.swift   # Settings scene: vault, subfolder, hotkey
│   └── VaultBookmark.swift     # security-scoped bookmark persistence
├── Onboarding/
│   ├── FirstLaunchView.swift
│   └── OnboardingWindowController.swift
└── Settings/
    ├── SettingsKey.swift       # all UserDefaults keys, in one place
    └── Vault.swift             # resolves the on-disk notes folder
```

## End-to-end manual verification checklist

After `make run`:

1. **Cold start** — no Dock icon, menu-bar icon appears, no window.
2. **First launch** — onboarding window opens; pick vault, set subfolder, record hotkey.
3. **Hotkey responsiveness** — popup appears in <100ms, prior frontmost app stays active.
4. **Hide on blur** — clicking another app hides the popup. Hotkey returns it to the same position/size.
5. **Pin** — toggle pin → click another app → popup stays.
6. **Editing** — `# Hello` renders larger/bold inline; `**bold**` renders bold inline. After 500ms a `Hello.md` file appears in the vault subfolder.
7. **Rename** — change the first line to `# Hello world` → file renames to `Hello world.md`.
8. **⌘P switcher** — fuzzy-search by title, arrows navigate, Enter switches editor; current note shows "Current" chip.
9. **Full-text search** — query a word that's only in a body — that note still appears in the switcher.
10. **Obsidian** — open the same vault in Obsidian; files appear under the subfolder.
11. **Idle footprint** — Activity Monitor with popup hidden: CPU 0%, RAM 15–30 MB, Energy Impact 0.

## License

MIT — see [LICENSE](LICENSE).
