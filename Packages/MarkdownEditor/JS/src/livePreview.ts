// Live-preview ViewPlugin that hides markdown marker characters at all times,
// substituting bullets and showing only the rendered text. Markers stay in the
// underlying document, so the file on disk is plain markdown — only the
// presentation changes.
//
// Reveal-on-cursor (the Obsidian behaviour where markers reappear on the line
// you're editing) is intentionally NOT enabled — it confuses caret movement
// and makes selection ranges harder to reason about. Editing happens via the
// toolbar / keyboard shortcuts; markers stay invisible.

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
    "HeaderMark",         // # ## ### …
    "EmphasisMark",       // * or _ (italic) and ** or __ (bold)
    "CodeMark",           // ` (inline code)
    "StrikethroughMark",  // ~~
    "LinkMark",           // [ ] ( ) and the leading ! for images
    "URL",                // the url part of a link or image
    "QuoteMark",          // > (blockquote)
    // ListMark is replaced with a bullet widget below.
    // TaskMarker stays visible — checkbox is the affordance.
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
            // Only recompute when the document or visible viewport actually
            // changes — selection moves no longer affect what we render
            // because we always hide markers regardless of cursor position.
            if (update.docChanged || update.viewportChanged) {
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
    const processedLists = new Set<number>();

    for (const { from, to } of view.visibleRanges) {
        tree.iterate({
            from,
            to,
            enter(node) {
                const name = node.type.name;

                if (HIDDEN_MARKERS.has(name)) {
                    builder.add(node.from, node.to, Decoration.replace({}));
                    return;
                }

                if (name === "ListMark" && !processedLists.has(node.from)) {
                    processedLists.add(node.from);
                    const text = view.state.sliceDoc(node.from, node.to);
                    if (text === "-" || text === "*" || text === "+") {
                        builder.add(
                            node.from,
                            node.to,
                            Decoration.replace({
                                widget: new BulletWidget("•"),
                            })
                        );
                    }
                }
            },
        });
    }

    return builder.finish();
}
