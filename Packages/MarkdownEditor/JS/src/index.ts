// Bootstraps a CodeMirror 6 editor in markdown mode and exposes a
// minimal `window.bridge` API for the Swift side to call.

import { EditorState, Compartment } from "@codemirror/state";
import {
    EditorView,
    keymap,
    drawSelection,
    rectangularSelection,
    crosshairCursor,
    highlightActiveLine,
} from "@codemirror/view";
import { indentOnInput, bracketMatching } from "@codemirror/language";
import { defaultKeymap, history, historyKeymap, indentWithTab } from "@codemirror/commands";
import { markdown, markdownLanguage } from "@codemirror/lang-markdown";

import { applyCommand } from "./commands";
import { detectActiveStyles } from "./detectStyles";
import { todoBracketAutoComplete } from "./inputHandlers";
import { livePreviewPlugin, taskCheckboxClickHandler } from "./livePreview";
import { makeLinkInteractions } from "./linkInteractions";
import { buildTheme, EditorAppearance } from "./theme";

declare global {
    interface Window {
        bridge: BridgeAPI;
        webkit?: {
            messageHandlers: {
                editor: {
                    postMessage: (msg: unknown) => void;
                };
            };
        };
    }
}

interface BridgeAPI {
    setText: (text: string) => void;
    exec: (command: string, arg: string | null) => void;
    applyConfig: (config: EditorConfig) => void;
    setCursorSuppressed: (suppressed: boolean) => void;
}

export interface EditorConfig {
    theme: "system" | "light" | "dark";
    fontSize: number;
    spellCheck: boolean;
    lineWrap: boolean;
}

function postToSwift(message: object) {
    try {
        window.webkit?.messageHandlers.editor.postMessage(JSON.stringify(message));
    } catch (err) {
        console.error("[markdown-editor] failed to post message", err);
    }
}

const themeCompartment = new Compartment();
const wrapCompartment = new Compartment();
const fontCompartment = new Compartment();

let view: EditorView | null = null;
let lastEmittedText: string | null = null;

function bootstrap() {
    const root = document.getElementById("editor-root");
    if (!root) {
        console.error("[markdown-editor] missing #editor-root");
        return;
    }

    const initialAppearance = systemAppearance();
    const initialFontSize = 16;

    const updateListener = EditorView.updateListener.of((update) => {
        if (update.docChanged) {
            const text = update.state.doc.toString();
            if (text !== lastEmittedText) {
                lastEmittedText = text;
                postToSwift({ kind: "textChanged", text });
            }
        }
        if (update.selectionSet || update.docChanged || update.focusChanged) {
            const styles = detectActiveStyles(update.state);
            postToSwift({ kind: "selectionChanged", styles });
        }
    });

    const state = EditorState.create({
        doc: "",
        extensions: [
            history(),
            drawSelection(),
            rectangularSelection(),
            crosshairCursor(),
            highlightActiveLine(),
            indentOnInput(),
            bracketMatching(),
            markdown({ base: markdownLanguage, codeLanguages: [], addKeymap: true }),
            // No defaultHighlightStyle — its heading underline doesn't fit
            // the live-preview look. The custom theme handles all colour /
            // weight rules we need.
            livePreviewPlugin,
            taskCheckboxClickHandler,
            makeLinkInteractions(postToSwift),
            todoBracketAutoComplete,
            keymap.of([...defaultKeymap, ...historyKeymap, indentWithTab]),
            wrapCompartment.of(EditorView.lineWrapping),
            themeCompartment.of(buildTheme(initialAppearance, initialFontSize)),
            fontCompartment.of(EditorView.theme({})),
            updateListener,
        ],
    });

    view = new EditorView({
        state,
        parent: root,
    });

    window.bridge = {
        setText(text: string) {
            if (!view) return;
            const current = view.state.doc.toString();
            if (current === text) return;
            lastEmittedText = text;
            view.dispatch({
                changes: { from: 0, to: view.state.doc.length, insert: text },
                // Drop the caret at the end of the freshly loaded note so the
                // user can start typing (or arrow up to navigate) right away;
                // for an empty note this is the start.
                selection: { anchor: text.length },
            });
            // Loading a note means we just entered the note view — focus the
            // editor so keystrokes land without a click first.
            view.focus();
        },
        exec(command: string, arg: string | null) {
            if (!view) return;
            applyCommand(view, command, arg, postToSwift);
            view.focus();
        },
        applyConfig(config: EditorConfig) {
            if (!view) return;
            const appearance = config.theme === "system" ? systemAppearance() : config.theme;
            view.dispatch({
                effects: [
                    themeCompartment.reconfigure(buildTheme(appearance, config.fontSize)),
                    wrapCompartment.reconfigure(
                        config.lineWrap ? EditorView.lineWrapping : []
                    ),
                ],
            });
            view.contentDOM.spellcheck = config.spellCheck;
        },
        setCursorSuppressed(suppressed: boolean) {
            // Toggle a class the CSS turns into `cursor: default !important`
            // on the whole document. Deliberately does NOT call view.focus()
            // (unlike exec) — an overlay's search field owns first responder
            // while this is on, and stealing it would break typing there.
            document.documentElement.classList.toggle("noter-cursor-suppressed", suppressed);
        },
    };

    postToSwift({ kind: "ready" });
}

function systemAppearance(): EditorAppearance {
    return window.matchMedia?.("(prefers-color-scheme: dark)").matches ? "dark" : "light";
}

if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", bootstrap);
} else {
    bootstrap();
}
