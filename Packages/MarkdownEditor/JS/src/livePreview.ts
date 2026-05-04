// Live-preview ViewPlugin that hides markdown marker characters at all times,
// substituting bullets and showing only the rendered text. Markers stay in the
// underlying document, so the file on disk is plain markdown — only the
// presentation changes.
//
// Special-cases:
// - HeaderMark only hides once the heading actually has content. Typing `#`
//   alone leaves the # visible so the user can see what they're doing.
// - When hiding a HeaderMark we also swallow the trailing space so the
//   rendered heading text starts at the line's left edge instead of being
//   indented by the orphaned space.
// - ListMark for unordered lists (`-`, `*`, `+`) is replaced with `•`.
//   Numbered list digits and TaskMarker brackets stay visible — the user
//   needs them as visual context.

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
    "EmphasisMark",
    "CodeMark",
    "StrikethroughMark",
    "LinkMark",
    "URL",
    "QuoteMark",
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

    for (const { from, to } of view.visibleRanges) {
        tree.iterate({
            from,
            to,
            enter(node) {
                const name = node.type.name;

                if (name === "HeaderMark") {
                    const line = view.state.doc.lineAt(node.from);
                    // Only hide once the heading has actual non-whitespace content
                    // after the marker. Otherwise the user can't see what they're
                    // typing while building a heading.
                    if (!/^#{1,6}\s+\S/.test(line.text)) return;
                    let hideTo = node.to;
                    const next = view.state.sliceDoc(node.to, node.to + 1);
                    if (next === " ") hideTo += 1;
                    builder.add(node.from, hideTo, Decoration.replace({}));
                    return;
                }

                if (HIDDEN_MARKERS.has(name)) {
                    builder.add(node.from, node.to, Decoration.replace({}));
                    return;
                }

                if (name === "ListMark") {
                    const text = view.state.sliceDoc(node.from, node.to);
                    if (text === "-" || text === "*" || text === "+") {
                        builder.add(
                            node.from,
                            node.to,
                            Decoration.replace({ widget: new BulletWidget("•") })
                        );
                    }
                }
            },
        });
    }

    return builder.finish();
}
