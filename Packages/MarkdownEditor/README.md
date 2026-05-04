# MarkdownEditor

A SwiftUI WYSIWYG markdown editor built on CodeMirror 6 inside a hidden WKWebView. Lives inside the Noter app for now; designed with a clean public API so it could be lifted into its own package later.

## Why CodeMirror

Native (NSTextView + regex/attributes) hits a quality ceiling around the 80% mark — bullet rendering, reveal-on-cursor, fenced-code highlighting, nested emphasis, tables — these all require deep TextKit work. CodeMirror 6 already solves them.

Cost: ~50 MB extra RAM idle. For an always-on notes app that's fine (Bear ~100 MB, iA Writer ~80 MB, Apple Notes ~50 MB, Obsidian ~500 MB).

## Architecture

```
Sources/MarkdownEditor/
├── MarkdownEditor.swift          # public SwiftUI view
├── EditorConfiguration.swift     # theme/font/behaviour
├── EditorCommands.swift          # public API for toolbars
├── Bridge/                       # WKWebView ↔ JS message passing
└── Resources/
    ├── editor.html               # host page
    ├── editor.bundle.js          # bundled CodeMirror (built from JS/)
    └── editor.css

JS/                               # source for editor.bundle.js
├── package.json
├── tsconfig.json
├── build.mjs                     # esbuild wrapper
└── src/
    ├── index.ts                  # boots CodeMirror, exposes window.bridge
    ├── commands.ts               # exec(name, arg) → CodeMirror commands
    └── theme.ts
```

## Building the JS bundle

```sh
cd JS
npm install
npm run build      # writes ../Sources/MarkdownEditor/Resources/editor.bundle.js
npm run watch      # rebuild on change while iterating
```

The build output is committed so `swift build` works without Node.

## Public API

```swift
import MarkdownEditor

struct MyView: View {
    @State private var text = ""

    var body: some View {
        MarkdownEditor(text: $text) { commands in
            // wire `commands.bold()` etc to a toolbar
        }
    }
}
```
