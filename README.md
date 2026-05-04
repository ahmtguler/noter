# Noter

A native macOS popup notes app inspired by Raycast Notes. Lives in your menu bar, summons instantly via a global hotkey, and stores plain `.md` files inside an Obsidian vault subfolder so your notes round-trip with Obsidian.

## Features (v1)

- Floating popup window, summoned by a global hotkey (you set it on first launch).
- Hides on focus loss; pin button keeps it on top.
- Hybrid live-preview markdown editor (headings, bold, italic, lists styled inline).
- ⌘P note switcher with fuzzy title + full-text body search.
- Auto-rename files based on the first line (Obsidian-style).
- Debounced autosave (500ms).
- Menu-bar only — no Dock icon, near-zero idle resource use.

## Prerequisites

- macOS 14 (Sonoma) or later.
- **Xcode** from the App Store (~10GB). After install: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.
- Homebrew tools: `brew install lefthook swiftlint swiftformat xcbeautify xcodegen`.
- Node (for commitlint, optional): used by the commit-msg hook.

## Setup

```bash
git clone https://github.com/ahmtguler/noter.git
cd noter

# Install git hooks
lefthook install

# Generate the Xcode project from project.yml
xcodegen generate

# Open in Xcode and run
open Noter.xcodeproj
```

## Development

| Command       | What it does                          |
|---------------|---------------------------------------|
| `make fmt`    | Format all Swift source with SwiftFormat |
| `make lint`   | Lint with SwiftLint (`--strict`)         |
| `make test`   | Run unit tests via xcodebuild            |
| `make build`  | Release build                            |
| `make run`    | Build and launch the app                 |
| `make ci`     | What CI runs: lint + test + build        |

Hooks run automatically:

- **pre-commit**: SwiftFormat (auto-fix) + SwiftLint on staged Swift files.
- **commit-msg**: [Conventional Commits](https://www.conventionalcommits.org/) check via commitlint.
- **pre-push**: Build + tests (debug config).

## Project layout

```
Noter/
├── NoterApp.swift              # @main entry point
├── AppDelegate.swift           # hotkey, menu bar, panel lifecycle
├── Window/                     # NSPanel and lifecycle
├── Editor/                     # NSTextView + live markdown styling
├── Switcher/                   # ⌘P overlay
├── Store/                      # Note persistence
├── Preferences/                # vault path, settings
└── Onboarding/                 # first-launch flow
NoterTests/                     # Swift Testing unit tests
```

## License

MIT — see [LICENSE](LICENSE).
