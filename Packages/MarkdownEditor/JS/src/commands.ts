// Translates the Swift bridge command names into edits on the CodeMirror state.
// Each command operates on the current selection (or current line for line-prefix
// commands) and tries to toggle off when applied a second time.

import { EditorView } from "@codemirror/view";
import { EditorSelection, Transaction, ChangeSpec } from "@codemirror/state";

interface InlineWrap {
    prefix: string;
    suffix: string;
    /// Single-character markers (e.g. `*`) refuse to match the inner edge of
    /// doubled markers (e.g. `**`) so they stack rather than unwrap.
    singleCharMarker?: boolean;
}

const inlineWraps: Record<string, InlineWrap> = {
    bold: { prefix: "**", suffix: "**" },
    italic: { prefix: "*", suffix: "*", singleCharMarker: true },
    underline: { prefix: "<u>", suffix: "</u>" },
    strikethrough: { prefix: "~~", suffix: "~~" },
    code: { prefix: "`", suffix: "`", singleCharMarker: true },
};

const linePrefixes: Record<string, string> = {
    bulletList: "- ",
    numberedList: "1. ",
    todo: "- [ ] ",
    quote: "> ",
};

export function applyCommand(view: EditorView, command: string, arg: string | null) {
    if (command === "focus") {
        view.focus();
        return;
    }
    if (command === "heading") {
        const level = arg ? parseInt(arg, 10) : 1;
        applyHeading(view, level);
        return;
    }
    if (command === "link") {
        applyLink(view);
        return;
    }
    const inline = inlineWraps[command];
    if (inline) {
        applyInlineWrap(view, inline);
        return;
    }
    const prefix = linePrefixes[command];
    if (prefix !== undefined) {
        toggleLinePrefix(view, prefix);
    }
}

// MARK: - Inline wrap

function applyInlineWrap(view: EditorView, wrap: InlineWrap) {
    const { prefix, suffix, singleCharMarker } = wrap;
    const state = view.state;
    const range = state.selection.main;
    const doc = state.doc;
    const sliced = doc.sliceString(range.from, range.to);

    // 1) Selection covers wrap markers themselves — strip them.
    if (
        sliced.length >= prefix.length + suffix.length &&
        sliced.startsWith(prefix) &&
        sliced.endsWith(suffix)
    ) {
        const inner = sliced.slice(prefix.length, sliced.length - suffix.length);
        view.dispatch({
            changes: { from: range.from, to: range.to, insert: inner },
            selection: EditorSelection.single(range.from, range.from + inner.length),
            scrollIntoView: true,
        });
        return;
    }

    // 2) Selection is wrapped by surrounding markers — strip them.
    const outsideStart = range.from - prefix.length;
    const outsideEnd = range.to + suffix.length;
    if (outsideStart >= 0 && outsideEnd <= doc.length) {
        const leading = doc.sliceString(outsideStart, range.from);
        const trailing = doc.sliceString(range.to, outsideEnd);
        if (
            leading === prefix &&
            trailing === suffix &&
            !abutsDoubledMarker(doc, outsideStart, outsideEnd, prefix, !!singleCharMarker)
        ) {
            view.dispatch({
                changes: { from: outsideStart, to: outsideEnd, insert: sliced },
                selection: EditorSelection.single(outsideStart, outsideStart + sliced.length),
                scrollIntoView: true,
            });
            return;
        }
    }

    // 3) Empty selection inside an existing wrap — unwrap (caret moves to start).
    if (range.empty) {
        const surrounding = findEnclosingWrap(doc.toString(), range.from, prefix, suffix, !!singleCharMarker);
        if (surrounding) {
            const inner = doc.sliceString(
                surrounding.openEnd,
                surrounding.closeStart,
            );
            view.dispatch({
                changes: {
                    from: surrounding.openStart,
                    to: surrounding.closeEnd,
                    insert: inner,
                },
                selection: EditorSelection.single(surrounding.openStart + inner.length),
                scrollIntoView: true,
            });
            return;
        }
        // No surrounding wrap: insert markers, place caret between.
        view.dispatch({
            changes: { from: range.from, to: range.to, insert: prefix + suffix },
            selection: EditorSelection.single(range.from + prefix.length),
            scrollIntoView: true,
        });
        return;
    }

    // 4) Default: wrap selection.
    const insert = prefix + sliced + suffix;
    view.dispatch({
        changes: { from: range.from, to: range.to, insert },
        selection: EditorSelection.single(range.from + prefix.length, range.from + prefix.length + sliced.length),
        scrollIntoView: true,
    });
}

function abutsDoubledMarker(
    doc: { sliceString: (from: number, to: number) => string; length: number },
    outsideStart: number,
    outsideEnd: number,
    marker: string,
    singleChar: boolean,
): boolean {
    if (!singleChar) return false;
    const before = outsideStart > 0 ? doc.sliceString(outsideStart - 1, outsideStart) : "";
    const after = outsideEnd < doc.length ? doc.sliceString(outsideEnd, outsideEnd + 1) : "";
    return before === marker || after === marker;
}

function findEnclosingWrap(
    fullText: string,
    position: number,
    prefix: string,
    suffix: string,
    singleChar: boolean,
): { openStart: number; openEnd: number; closeStart: number; closeEnd: number } | null {
    const lineStart = fullText.lastIndexOf("\n", position - 1) + 1;
    const lineEnd = (() => {
        const idx = fullText.indexOf("\n", position);
        return idx === -1 ? fullText.length : idx;
    })();
    const line = fullText.slice(lineStart, lineEnd);
    const positionInLine = position - lineStart;
    const escapedPrefix = escapeRegExp(prefix);
    const escapedSuffix = escapeRegExp(suffix);
    const regex = new RegExp(`${escapedPrefix}([^\\n]+?)${escapedSuffix}`, "g");
    let match: RegExpExecArray | null;
    while ((match = regex.exec(line)) !== null) {
        const start = match.index;
        const end = match.index + match[0].length;
        if (start < positionInLine && positionInLine < end) {
            if (singleChar) {
                const before = start > 0 ? line[start - 1] : "";
                const after = end < line.length ? line[end] : "";
                if (before === prefix || after === prefix) {
                    continue;
                }
            }
            return {
                openStart: lineStart + start,
                openEnd: lineStart + start + prefix.length,
                closeStart: lineStart + end - suffix.length,
                closeEnd: lineStart + end,
            };
        }
    }
    return null;
}

function escapeRegExp(s: string): string {
    return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

// MARK: - Line prefix (lists, quotes, todos)

function toggleLinePrefix(view: EditorView, prefix: string) {
    const state = view.state;
    const sel = state.selection.main;
    const startLine = state.doc.lineAt(sel.from);
    const endLine = state.doc.lineAt(sel.to);

    const lines: { from: number; to: number; text: string }[] = [];
    for (let n = startLine.number; n <= endLine.number; n++) {
        const line = state.doc.line(n);
        lines.push({ from: line.from, to: line.to, text: line.text });
    }

    const isAnyBlockMarker = (line: string) => /^(#{1,6}\s|>\s|-\s\[[xX ]\]\s|[-*+]\s|\d+\.\s)/.test(line);
    const allHavePrefix = lines.every(({ text }) => text.length === 0 || text.startsWith(prefix));

    let cumulativeOffset = 0;
    const changes: ChangeSpec[] = [];

    for (const line of lines) {
        if (line.text.length === 0) continue;

        let newText: string;
        if (allHavePrefix) {
            newText = line.text.slice(prefix.length);
        } else {
            // Strip any other block marker first so toggles between styles replace cleanly.
            const stripped = stripAnyBlockMarker(line.text);
            newText = stripped.startsWith(prefix) ? stripped : prefix + stripped;
        }

        changes.push({ from: line.from, to: line.to, insert: newText });
        cumulativeOffset += newText.length - line.text.length;
        void isAnyBlockMarker;
    }

    if (changes.length === 0) return;

    view.dispatch({
        changes,
        selection: EditorSelection.single(sel.from, sel.to + cumulativeOffset),
        scrollIntoView: true,
    });
}

function stripAnyBlockMarker(line: string): string {
    return line
        .replace(/^#{1,6}\s+/, "")
        .replace(/^[-*+]\s+\[[xX ]\]\s+/, "")
        .replace(/^[-*+]\s+/, "")
        .replace(/^\d+\.\s+/, "")
        .replace(/^>\s+/, "");
}

// MARK: - Heading

function applyHeading(view: EditorView, level: number) {
    if (level < 1 || level > 6) return;
    const state = view.state;
    const sel = state.selection.main;
    const line = state.doc.lineAt(sel.from);
    const target = `${"#".repeat(level)} `;
    const stripped = stripAnyBlockMarker(line.text);
    const isAlreadyAtLevel = line.text.startsWith(target);
    const newText = isAlreadyAtLevel ? stripped : target + stripped;
    const offset = newText.length - line.text.length;
    view.dispatch({
        changes: { from: line.from, to: line.to, insert: newText },
        selection: EditorSelection.single(sel.from + offset, sel.to + offset),
        scrollIntoView: true,
    });
}

// MARK: - Link

function applyLink(view: EditorView) {
    const state = view.state;
    const sel = state.selection.main;
    const sliced = state.doc.sliceString(sel.from, sel.to);
    if (sel.empty) {
        view.dispatch({
            changes: { from: sel.from, to: sel.to, insert: "[]()" },
            selection: EditorSelection.single(sel.from + 1),
            scrollIntoView: true,
        });
        return;
    }
    const replacement = `[${sliced}]()`;
    view.dispatch({
        changes: { from: sel.from, to: sel.to, insert: replacement },
        selection: EditorSelection.single(sel.from + replacement.length - 1),
        scrollIntoView: true,
    });
}
