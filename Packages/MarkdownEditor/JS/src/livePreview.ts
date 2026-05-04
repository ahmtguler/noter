// Live-preview ViewPlugin that hides markdown marker characters in lines the
// caret isn't on (the same UX Obsidian's Live Preview / Bear use). Markers
// reappear on the active line so the user can edit them.

import {
    Decoration,
    DecorationSet,
    EditorView,
    ViewPlugin,
    ViewUpdate,
    WidgetType,
} from "@codemirror/view";
import { syntaxTree } from "@codemirror/language";
import { RangeSetBuilder } from "@codemirror/state";

const HIDDEN_MARKERS = new Set([
    "HeaderMark",     // # ## ### …
    "EmphasisMark",   // * or _ (italic) and ** or __ (bold)
    "CodeMark",       // ` (inline code)
    "StrikethroughMark", // ~~
    "LinkMark",       // [ ] ( ) and the leading ! for images
    "URL",            // the url part of a link or image
    "QuoteMark",      // > (blockquote)
    // ListMark and TaskMarker are intentionally NOT hidden — we want
    // bullets / numbers / checkboxes visible at all times.
]);

class BulletWidget extends WidgetType {
    constructor(private readonly char: string) {
        super();
    }

    eq(other: WidgetType): boolean {
        return other instanceof BulletWidget && other.char === this.char;
    }

    toDOM(): HTMLElement {
        const span = document.createElement("span");
        span.className = "cm-bullet-widget";
        span.textContent = this.char;
        return span;
    }

    ignoreEvent(): boolean {
        return false;
    }
}

export const livePreviewPlugin = ViewPlugin.fromClass(
    class {
        decorations: DecorationSet;

        constructor(view: EditorView) {
            this.decorations = compute(view);
        }

        update(update: ViewUpdate): void {
            if (
                update.docChanged ||
                update.viewportChanged ||
                update.selectionSet ||
                update.focusChanged
            ) {
                this.decorations = compute(update.view);
            }
        }
    },
    {
        decorations: (plugin) => plugin.decorations,
    }
);

function compute(view: EditorView): DecorationSet {
    const builder = new RangeSetBuilder<Decoration>();
    const tree = syntaxTree(view.state);
    const sel = view.state.selection.main;
    const cursorLine = view.state.doc.lineAt(sel.head);

    // Track which list items have already been processed so we don't
    // repeat the bullet substitution.
    const processedLists = new Set<number>();

    for (const { from, to } of view.visibleRanges) {
        tree.iterate({
            from,
            to,
            enter(node) {
                const name = node.type.name;
                const onCursorLine =
                    node.from >= cursorLine.from && node.to <= cursorLine.to;

                // Hide marker nodes when the caret is on a different line.
                if (HIDDEN_MARKERS.has(name) && !onCursorLine) {
                    // For multi-line selection, skip hiding inside selection
                    // so the user can clearly see what they're editing.
                    if (sel.from !== sel.to && node.from >= sel.from && node.to <= sel.to) {
                        return;
                    }
                    builder.add(node.from, node.to, Decoration.replace({}));
                }

                // Replace the dash/asterisk in bullet lists with a real bullet.
                if (name === "ListMark" && !processedLists.has(node.from)) {
                    processedLists.add(node.from);
                    const text = view.state.sliceDoc(node.from, node.to);
                    if (text === "-" || text === "*" || text === "+") {
                        // Don't replace if cursor is on this line (let user
                        // see the source).
                        if (!onCursorLine) {
                            builder.add(
                                node.from,
                                node.to,
                                Decoration.replace({
                                    widget: new BulletWidget("•"),
                                })
                            );
                        }
                    }
                }
            },
        });
    }

    return builder.finish();
}
