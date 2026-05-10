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
}

export interface EditorConfig {
    theme: "system" | "light" | "dark";
    fontSize: number;
    spellCheck: boolean;
    smartListContinuation: boolean;
    revealMarkersOnCursor: boolean;
    lineWrap: boolean;
    contentPadding: number;
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
                selection: clampSelection(view, text),
            });
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
    };

    postToSwift({ kind: "ready" });
}

function clampSelection(currentView: EditorView, newText: string) {
    const previous = currentView.state.selection.main.head;
    return { anchor: Math.min(previous, newText.length) };
}

function systemAppearance(): EditorAppearance {
    return window.matchMedia?.("(prefers-color-scheme: dark)").matches ? "dark" : "light";
}

if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", bootstrap);
} else {
    bootstrap();
}
