// Live-preview ViewPlugin that hides markdown markers and replaces structural
// pieces (bullets, task checkboxes) with custom widgets. The underlying
// document stays as plain markdown — only the presentation changes.
//
// Special-cases handled:
// - HeaderMark only hides once the heading has actual content; before that,
//   the user can see what they're typing.
// - When hiding HeaderMark we also swallow the trailing space so the rendered
//   heading text is left-flush.
// - Task lines (`- [ ] …` or `- [x] …`) collapse the entire prefix into a
//   single CheckboxWidget. Clicking the widget toggles the task.
// - Numbered list markers (`1.`, `2.` …) get a subtle accent tint.
// - Plain bullet markers (`-`, `*`, `+`) get replaced with `•`.

import {
    Decoration,
    DecorationSet,
    EditorView,
    ViewPlugin,
    ViewUpdate,
    WidgetType,
} from "@codemirror/view";
import { syntaxTree } from "@codemirror/language";
import { Range } from "@codemirror/state";

const HIDDEN_MARKERS = new Set([
    "EmphasisMark",
    "CodeMark",
    "StrikethroughMark",
    "LinkMark",
    "URL",
    "QuoteMark",
]);

const TASK_LINE_REGEX = /^(\s*)([-*+])(\s+)(\[)([xX ])(\])(\s)/;

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

class CheckboxWidget extends WidgetType {
    constructor(private readonly checked: boolean) {
        super();
    }
    eq(other: WidgetType): boolean {
        return other instanceof CheckboxWidget && other.checked === this.checked;
    }
    toDOM(): HTMLElement {
        const span = document.createElement("span");
        span.className = "cm-task-checkbox" + (this.checked ? " cm-task-checkbox-checked" : "");
        span.setAttribute("role", "checkbox");
        span.setAttribute("aria-checked", String(this.checked));
        if (this.checked) {
            span.textContent = "✓";
        }
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

/// Click handler for the task checkbox widget. We use mousedown to intercept
/// before the editor processes the click for cursor placement.
export const taskCheckboxClickHandler = EditorView.domEventHandlers({
    mousedown(event, view) {
        const target = event.target as HTMLElement | null;
        if (!target?.classList.contains("cm-task-checkbox")) return false;
        const pos = view.posAtDOM(target);
        if (pos < 0) return false;
        const line = view.state.doc.lineAt(pos);
        const match = line.text.match(/^(\s*[-*+]\s+\[)([xX ])(\])/);
        if (!match) return false;
        const charPos = line.from + match[1].length;
        const next = match[2] === " " ? "x" : " ";
        view.dispatch({
            changes: { from: charPos, to: charPos + 1, insert: next },
        });
        event.preventDefault();
        event.stopPropagation();
        return true;
    },
});

interface TaskInfo {
    checked: boolean;
    prefixStart: number;
    prefixEnd: number;
}

function compute(view: EditorView): DecorationSet {
    const decos: Range<Decoration>[] = [];
    const tree = syntaxTree(view.state);

    // Pass 1: identify task lines so we can collapse the whole prefix into
    // a checkbox widget instead of showing `- [ ] `.
    const taskLines = new Map<number, TaskInfo>();
    for (const { from, to } of view.visibleRanges) {
        const startLine = view.state.doc.lineAt(from);
        const endLine = view.state.doc.lineAt(to);
        for (let n = startLine.number; n <= endLine.number; n++) {
            const line = view.state.doc.line(n);
            const match = line.text.match(TASK_LINE_REGEX);
            if (!match) continue;
            const indentLen = match[1].length;
            const prefixStart = line.from + indentLen;
            const prefixEnd = line.from + match[0].length;
            const checked = match[5] !== " ";
            taskLines.set(n, { checked, prefixStart, prefixEnd });
            decos.push(
                Decoration.replace({
                    widget: new CheckboxWidget(checked),
                }).range(prefixStart, prefixEnd)
            );
        }
    }

    // Pass 2: tree iteration for everything else.
    for (const { from, to } of view.visibleRanges) {
        tree.iterate({
            from,
            to,
            enter(node) {
                const lineNum = view.state.doc.lineAt(node.from).number;
                const taskInfo = taskLines.get(lineNum);

                // Skip nodes inside the task prefix range — already covered
                // by the checkbox widget above.
                if (
                    taskInfo &&
                    node.from >= taskInfo.prefixStart &&
                    node.to <= taskInfo.prefixEnd
                ) {
                    return;
                }

                const name = node.type.name;

                if (name === "HeaderMark") {
                    const line = view.state.doc.lineAt(node.from);
                    if (!/^#{1,6}\s+\S/.test(line.text)) return;
                    let hideTo = node.to;
                    const next = view.state.sliceDoc(node.to, node.to + 1);
                    if (next === " ") hideTo += 1;
                    decos.push(Decoration.replace({}).range(node.from, hideTo));
                    return;
                }

                if (HIDDEN_MARKERS.has(name)) {
                    decos.push(Decoration.replace({}).range(node.from, node.to));
                    return;
                }

                if (name === "ListMark") {
                    const text = view.state.sliceDoc(node.from, node.to);
                    if (text === "-" || text === "*" || text === "+") {
                        decos.push(
                            Decoration.replace({
                                widget: new BulletWidget("•"),
                            }).range(node.from, node.to)
                        );
                    } else if (/^\d+\.$/.test(text)) {
                        decos.push(
                            Decoration.mark({ class: "cm-numbered-marker" }).range(
                                node.from,
                                node.to
                            )
                        );
                    }
                }
            },
        });
    }

    decos.sort((a, b) => a.from - b.from || a.to - b.to);
    return Decoration.set(decos, true);
}
